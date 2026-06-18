class_name BattleManager
extends RefCounted
## 戦闘進行の仲介ハブ（→ ../../docs/06_systems.md BattleManager / 11_battle-spec.md §0,§1.5）。
## グリッド・時計・ATB・ユニット・フォーカス・進行状態を束ね、各部品を疎結合に保つ。
##
## 状態は2層（§0-1）:
##  - ゲーム進行状態 Progress: RUNNING / PAUSED / ENDING（危険地帯は PAUSED と ENDING）。
##  - アクター状態: 各 BattleUnit が持つ FSM（BattleUnit.State）。
## 時間は PausableClock 一本（§0-4）。RUNNING 以外は ATB もフォーカス送りも凍結する。

enum Progress { RUNNING, PAUSED, ENDING }
# フォーカス中の入力フロー: コマンド待ち → ターゲット選択（→ 06_systems 入力フロー）。
enum TurnPhase { NONE, COMMAND, TARGETING }

signal focus_changed(unit: BattleUnit)  # 引数 null = フォーカスなし
signal enemy_turn(unit: BattleUnit)     # 敵がアクティブ化（今はAI未実装→即パス）
signal battle_ended(victory: bool)

var grid := BattleGrid.new()
var clock := PausableClock.new()
var atb := ATBSystem.new()
var skill := SkillSystem.new()
var ai := EnemyAI.new()
var rng := RandomNumberGenerator.new()
var progress: Progress = Progress.RUNNING
var units: Array[BattleUnit] = []

# アクティブで指示待ちの味方（溜まった順＝決定論的）。先頭から1人ずつフォーカスする。
var _active_queue: Array[BattleUnit] = []
var focus: BattleUnit = null

# フォーカス中ターンの入力状態
var turn_phase: TurnPhase = TurnPhase.NONE
var move_left: int = 0            # このターンの残り移動量
var selected_slot: int = -1       # TARGETING 中に選んだスキルスロット
var targets: Array[BattleUnit] = []  # 現在の有効ターゲット候補
var target_index: int = 0
var victory: bool = false


func _init() -> void:
	atb.unit_became_active.connect(_on_unit_became_active)
	rng.randomize()


func add_unit(unit: BattleUnit, origin: Vector2i) -> void:
	units.append(unit)
	atb.add_unit(unit)
	grid.place_unit(unit.id, origin, unit.size)


## 毎フレーム1回。時計を進め、RUNNING のときだけ ATB とフォーカス送りを回す。
func process(real_delta: float) -> void:
	var dt := clock.tick(real_delta)
	if progress != Progress.RUNNING:
		return  # PAUSED / ENDING は完全凍結（dt も 0 だが二重に守る）
	skill.tick_cooltimes(units, dt)
	atb.advance(dt)
	_ensure_focus()


# --- フォーカス管理 -----------------------------------------------------
func _on_unit_became_active(unit: BattleUnit) -> void:
	if progress != Progress.RUNNING:
		return  # 終了処理中などに満了が来ても行動させない（§0-5）
	if unit.is_ally():
		if unit not in _active_queue:
			_active_queue.append(unit)  # 溜まった順に並べる
	else:
		# 敵: その場で1ターンを完結（接近→攻撃 or パス）。判断はこの満了の瞬間だけ（§8）。
		enemy_turn.emit(unit)
		var used := ai.take_turn(unit, units, grid, skill, rng)
		atb.reset_after_turn(unit, used)  # 攻撃した=0% / パス=20%
		_check_battle_end()


## フォーカス不在なら次のアクティブ味方へ回す。死亡/失効したフォーカスは外す。
func _ensure_focus() -> void:
	if focus != null and focus.state != BattleUnit.State.FOCUS:
		focus = null
	while focus == null and not _active_queue.is_empty():
		var next: BattleUnit = _active_queue.pop_front()
		if next.state == BattleUnit.State.ACTIVE and next.is_alive():
			focus = next
			focus.set_state(BattleUnit.State.FOCUS)
			_begin_turn(focus)
			focus_changed.emit(focus)


## フォーカスが回ってきたターンの入力状態を初期化する。
func _begin_turn(unit: BattleUnit) -> void:
	turn_phase = TurnPhase.COMMAND
	move_left = unit.move_range
	selected_slot = -1
	targets = []
	target_index = 0


# --- プレイヤー操作（battle.gd から呼ぶ） -------------------------------
## フォーカス中ユニットを1マス動かす。移動量を消費。埋まってるマスには入れない（押し出さない・§2）。
func move_focus(dir: Vector2i) -> bool:
	if not _can_command() or turn_phase != TurnPhase.COMMAND or move_left <= 0:
		return false
	var target := grid.get_origin(focus.id) + dir
	if grid.can_place(target, focus.size, focus.id):
		grid.place_unit(focus.id, target, focus.size)
		move_left -= 1
		return true
	return false


## スキルスロット(0..3)を選ぶ。自己/全体は即実行、対象ありはターゲット選択へ。
## 使えない（クールタイム/マナ/対象なし）なら false。
func select_skill(slot: int) -> bool:
	if not _can_command() or turn_phase != TurnPhase.COMMAND:
		return false
	if not skill.is_usable(focus, slot, units, grid):
		return false
	var data := skill.slot_skill(focus, slot)
	if data.is_self_or_all():
		_execute(slot, null)
		return true
	targets = skill.valid_targets(focus, data, units, grid)
	selected_slot = slot
	target_index = 0
	turn_phase = TurnPhase.TARGETING
	return true


## ターゲット候補カーソルを動かす（step: -1/+1、巡回）。
func cycle_target(step: int) -> void:
	if turn_phase != TurnPhase.TARGETING or targets.is_empty():
		return
	target_index = wrapi(target_index + step, 0, targets.size())


## ターゲットを確定してスキル実行。
func confirm_target() -> void:
	if turn_phase != TurnPhase.TARGETING or targets.is_empty():
		return
	_execute(selected_slot, targets[target_index])


## ターゲット選択をやめてコマンドに戻る。
func cancel_targeting() -> void:
	if turn_phase != TurnPhase.TARGETING:
		return
	turn_phase = TurnPhase.COMMAND
	selected_slot = -1
	targets = []


## 行動終了（パス・`w`）。スキル未使用なので used_skill=false（次ATB 20%・§1.5）。
func end_turn() -> void:
	if not _can_command():
		return
	_end_focus_turn(false)


func _execute(slot: int, target: BattleUnit) -> void:
	skill.execute(focus, slot, target, units, grid)
	# スキルを使ったターン → ATB 0% で終了（§1.5）。
	_end_focus_turn(true)
	_check_battle_end()


func _end_focus_turn(used_skill: bool) -> void:
	var ending := focus
	focus = null
	turn_phase = TurnPhase.NONE
	targets = []
	selected_slot = -1
	atb.reset_after_turn(ending, used_skill)  # ウェイトへ
	focus_changed.emit(null)
	# 次のアクティブへは次フレームの _ensure_focus が回す。


func _check_battle_end() -> void:
	var allies_alive := units.any(func(u: BattleUnit) -> bool: return u.is_ally() and u.is_alive())
	var enemies_alive := units.any(func(u: BattleUnit) -> bool: return not u.is_ally() and u.is_alive())
	if not enemies_alive:
		_finish(true)
	elif not allies_alive:
		_finish(false)


## 戦闘終了処理（§0-5: 行動中に終了が来たら畳む。今は cast_time=0 で in-flight 無し。
## 詠唱/アニメを足したら、ここで行動コンテキストの後始末を必ず呼ぶこと）。
func _finish(win: bool) -> void:
	victory = win
	progress = Progress.ENDING
	clock.set_paused(true)
	focus = null
	turn_phase = TurnPhase.NONE
	battle_ended.emit(win)


func _can_command() -> bool:
	return focus != null and progress == Progress.RUNNING


func toggle_pause() -> void:
	if progress == Progress.ENDING:
		return  # 終了処理中はポーズに入らない
	if progress == Progress.RUNNING:
		progress = Progress.PAUSED
		clock.set_paused(true)
	else:
		progress = Progress.RUNNING
		clock.set_paused(false)

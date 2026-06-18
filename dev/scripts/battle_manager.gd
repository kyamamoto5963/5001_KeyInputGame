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

signal focus_changed(unit: BattleUnit)  # 引数 null = フォーカスなし
signal enemy_turn(unit: BattleUnit)     # 敵がアクティブ化（今はAI未実装→即パス）

var grid := BattleGrid.new()
var clock := PausableClock.new()
var atb := ATBSystem.new()
var progress: Progress = Progress.RUNNING
var units: Array[BattleUnit] = []

# アクティブで指示待ちの味方（溜まった順＝決定論的）。先頭から1人ずつフォーカスする。
var _active_queue: Array[BattleUnit] = []
var focus: BattleUnit = null


func _init() -> void:
	atb.unit_became_active.connect(_on_unit_became_active)


func add_unit(unit: BattleUnit, origin: Vector2i) -> void:
	units.append(unit)
	atb.add_unit(unit)
	grid.place_unit(unit.id, origin, unit.size)


## 毎フレーム1回。時計を進め、RUNNING のときだけ ATB とフォーカス送りを回す。
func process(real_delta: float) -> void:
	var dt := clock.tick(real_delta)
	if progress != Progress.RUNNING:
		return  # PAUSED / ENDING は完全凍結（dt も 0 だが二重に守る）
	atb.advance(dt)
	_ensure_focus()


# --- フォーカス管理 -----------------------------------------------------
func _on_unit_became_active(unit: BattleUnit) -> void:
	if unit.is_ally():
		if unit not in _active_queue:
			_active_queue.append(unit)  # 溜まった順に並べる
	else:
		# 敵: AI未実装 → 即パス（次ATBは20%へ）。後で敵AI（§8）に差し替える。
		enemy_turn.emit(unit)
		atb.reset_after_turn(unit, false)


## フォーカス不在なら次のアクティブ味方へ回す。死亡/失効したフォーカスは外す。
func _ensure_focus() -> void:
	if focus != null and focus.state != BattleUnit.State.FOCUS:
		focus = null
	while focus == null and not _active_queue.is_empty():
		var next: BattleUnit = _active_queue.pop_front()
		if next.state == BattleUnit.State.ACTIVE and next.is_alive():
			focus = next
			focus.set_state(BattleUnit.State.FOCUS)
			focus_changed.emit(focus)


# --- プレイヤー操作（battle.gd から呼ぶ） -------------------------------
## フォーカス中ユニットを1マス動かす。埋まってるマスには入れない（押し出さない・§2）。
func move_focus(dir: Vector2i) -> bool:
	if focus == null or progress != Progress.RUNNING:
		return false
	var target := grid.get_origin(focus.id) + dir
	if grid.can_place(target, focus.size, focus.id):
		grid.place_unit(focus.id, target, focus.size)
		return true
	return false


## 行動終了（パス・`w`）。スキル未実装なので used_skill=false（次ATB 20%・§1.5）。
func end_turn() -> void:
	if focus == null or progress != Progress.RUNNING:
		return
	var ending := focus
	focus = null
	atb.reset_after_turn(ending, false)  # ウェイトへ
	focus_changed.emit(null)
	# 次のアクティブへは次フレームの _ensure_focus が回す。


func toggle_pause() -> void:
	if progress == Progress.ENDING:
		return  # 終了処理中はポーズに入らない
	if progress == Progress.RUNNING:
		progress = Progress.PAUSED
		clock.set_paused(true)
	else:
		progress = Progress.RUNNING
		clock.set_paused(false)

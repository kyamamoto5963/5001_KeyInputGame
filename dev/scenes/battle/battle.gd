extends Node2D
## 戦闘シーン（縦スライスの足場）。描画と入力ルーティングだけを持ち、進行ロジックは
## BattleManager に委ねる（→ ../../docs/06_systems.md 疎結合方針）。
##
## ターン入力フロー（→ 06_systems）: 移動 → スキル(a/s/d/f) → ターゲット → 決定。
##   COMMAND  : 移動キーで移動範囲内を動く。a/s/d/f でスキル選択。W で行動終了(パス)。
##   TARGETING: 移動キーで対象カーソル送り。Enter で確定、Esc で戻る。
## P でポーズ（全凍結）。敵はAI未実装なので満了即パス。決着後は Enter でリトライ。

const CELL_PX := 64
const ORIGIN := Vector2(48, 150)
const ATB_BAR_H := 5.0
const HP_BAR_H := 5.0

var _mgr := BattleManager.new()
var _flash := ""          # パリィ結果の一時表示
var _flash_t := 0.0

@onready var _info: Label = $UI/Info
@onready var _result: Label = $UI/Result


func _ready() -> void:
	var slash := load("res://data/skills/slash.tres") as SkillData
	var helm := load("res://data/skills/helm_split.tres") as SkillData
	var staff := load("res://data/skills/staff.tres") as SkillData
	var fireball := load("res://data/skills/fireball.tres") as SkillData

	var kenshi := BattleUnit.new(0, "剣士", BattleUnit.Team.ALLY, 0.25)
	kenshi.max_hp = 34; kenshi.hp = 34; kenshi.move_range = 3
	kenshi.equip([slash, helm] as Array[SkillData])

	var mahou := BattleUnit.new(1, "魔法", BattleUnit.Team.ALLY, 0.18)
	mahou.max_hp = 24; mahou.hp = 24; mahou.move_range = 2
	mahou.equip([staff, fireball] as Array[SkillData])

	var tackle := load("res://data/skills/tackle.tres") as SkillData
	var zako := BattleUnit.new(2, "雑魚", BattleUnit.Team.ENEMY, 0.20)
	zako.max_hp = 28; zako.hp = 28; zako.move_range = 3
	zako.equip([tackle] as Array[SkillData])
	zako.ai = load("res://data/ai/zako.tres") as EnemyAIData

	_mgr.add_unit(kenshi, Vector2i(1, 1))
	_mgr.add_unit(mahou, Vector2i(0, 0))
	_mgr.add_unit(zako, Vector2i(8, 1))

	_mgr.battle_ended.connect(_on_battle_ended)
	_mgr.parry_feedback.connect(_on_parry_feedback)
	_result.visible = false


func _process(delta: float) -> void:
	_mgr.process(delta)
	if _flash_t > 0.0:
		_flash_t -= delta
	queue_redraw()
	_update_info()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.PAUSE):
		_mgr.toggle_pause()
		get_viewport().set_input_as_handled()
		return

	# パリィは独立リアルタイム（§7）。ターン状態に関係なく常時受け付ける。
	if event.is_action_pressed(InputActions.PARRY_ATTACK):
		_mgr.try_parry(SkillData.ParryKind.ATTACK)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(InputActions.PARRY_SKILL):
		_mgr.try_parry(SkillData.ParryKind.SKILL)
		get_viewport().set_input_as_handled()
		return

	if _mgr.progress == BattleManager.Progress.ENDING:
		if event.is_action_pressed(InputActions.CONFIRM):
			get_tree().reload_current_scene()
		return

	if event.is_action_pressed(InputActions.END_TURN):
		_mgr.end_turn()
		get_viewport().set_input_as_handled()
		return

	match _mgr.turn_phase:
		BattleManager.TurnPhase.COMMAND:
			if _handle_command(event):
				get_viewport().set_input_as_handled()
				return
		BattleManager.TurnPhase.TARGETING:
			if _handle_targeting(event):
				get_viewport().set_input_as_handled()
				return

	# デバッグ: 移動レイアウト切替（1=jikl / 2=hjkl / 3=arrows）。後で設定画面へ。
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1: GameState.set_movement_layout("jikl")
			KEY_2: GameState.set_movement_layout("hjkl")
			KEY_3: GameState.set_movement_layout("arrows")


func _handle_command(event: InputEvent) -> bool:
	if event.is_action_pressed(InputActions.SKILL_A): return _mgr.select_skill(0)
	if event.is_action_pressed(InputActions.SKILL_S): return _mgr.select_skill(1)
	if event.is_action_pressed(InputActions.SKILL_D): return _mgr.select_skill(2)
	if event.is_action_pressed(InputActions.SKILL_F): return _mgr.select_skill(3)
	var dir := _read_dir(event)
	if dir != Vector2i.ZERO:
		_mgr.move_focus(dir)
		return true
	return false


func _handle_targeting(event: InputEvent) -> bool:
	if event.is_action_pressed(InputActions.CONFIRM):
		_mgr.confirm_target()
		return true
	if event.is_action_pressed(InputActions.CANCEL):
		_mgr.cancel_targeting()
		return true
	var step := _read_cycle(event)
	if step != 0:
		_mgr.cycle_target(step)
		return true
	return false


func _read_dir(event: InputEvent) -> Vector2i:
	if event.is_action_pressed(InputActions.MOVE_UP): return Vector2i(0, -1)
	if event.is_action_pressed(InputActions.MOVE_DOWN): return Vector2i(0, 1)
	if event.is_action_pressed(InputActions.MOVE_LEFT): return Vector2i(-1, 0)
	if event.is_action_pressed(InputActions.MOVE_RIGHT): return Vector2i(1, 0)
	return Vector2i.ZERO


func _read_cycle(event: InputEvent) -> int:
	if event.is_action_pressed(InputActions.MOVE_LEFT) or event.is_action_pressed(InputActions.MOVE_UP):
		return -1
	if event.is_action_pressed(InputActions.MOVE_RIGHT) or event.is_action_pressed(InputActions.MOVE_DOWN):
		return 1
	return 0


func _on_battle_ended(win: bool) -> void:
	_result.text = "勝利！  （Enter でリトライ）" if win else "敗北…  （Enter でリトライ）"
	_result.visible = true


func _on_parry_feedback(success: bool, combo: int) -> void:
	_flash = "PARRY! x%d" % combo if success else "MISS"
	_flash_t = 0.6


# --- 表示 ---------------------------------------------------------------
func _update_info() -> void:
	var prog: String = ["進行中", "ポーズ", "終了処理中"][_mgr.progress]
	var pinfo := "  パリィ r/e"
	if _mgr.parry.combo > 0:
		pinfo += " コンボ%d" % _mgr.parry.combo
	if _flash_t > 0.0:
		pinfo += "  ▶ %s" % _flash
	if _mgr.focus == null:
		_info.text = "[%s] フォーカス待ち ｜ 移動:%s(矢印可) / P:ポーズ%s" % [prog, GameState.movement_layout, pinfo]
		return
	var u := _mgr.focus
	var phase: String = "ターゲット選択(Enter確定/Esc戻る)" if _mgr.turn_phase == BattleManager.TurnPhase.TARGETING else "コマンド(移動/a s d f/W終了)"
	_info.text = "[%s] %s HP%d/%d MP%d/%d 残移動%d ｜ %s ｜ %s%s" % [
		prog, u.display_name, u.hp, u.max_hp, u.mana, u.max_mana, _mgr.move_left,
		_slots_text(u), phase, pinfo,
	]


func _slots_text(u: BattleUnit) -> String:
	var labels := ["a", "s", "d", "f"]
	var parts: PackedStringArray = []
	for i in u.loadout.size():
		var s := u.loadout[i]
		var mark := "" if _mgr.skill.is_usable(u, i, _mgr.units, _mgr.grid) else "×"
		var cd := "" if u.cool[i] <= 0.0 else "CT%.1f" % u.cool[i]
		parts.append("%s:%s%s%s" % [labels[i], s.display_name, mark, cd])
	return " ".join(parts)


func _draw() -> void:
	for y in BattleGrid.ROWS:
		for x in BattleGrid.COLS:
			var r := Rect2(ORIGIN + Vector2(x, y) * CELL_PX, Vector2(CELL_PX, CELL_PX))
			draw_rect(r, Color(0.12, 0.13, 0.16), true)
			draw_rect(r, Color(0.30, 0.32, 0.38), false, 2.0)
	for unit in _mgr.units:
		if unit.is_alive():
			_draw_unit(unit)
	# パリィリング（飛来攻撃の予告）。最後に重ねて描く。
	for inc in _mgr.parry.incoming:
		_draw_parry_ring(inc)


func _draw_unit(unit: BattleUnit) -> void:
	var base := ORIGIN + Vector2(_mgr.grid.get_origin(unit.id)) * CELL_PX
	var m := 8.0

	var col := Color(0.40, 0.70, 1.0) if unit.is_ally() else Color(0.95, 0.45, 0.45)
	draw_rect(Rect2(base + Vector2(m, m), Vector2(CELL_PX - 2.0 * m, CELL_PX - 2.0 * m)), col, true)
	# 向き（左右）を小さな印で
	var eye_x := base.x + (CELL_PX - m - 6 if unit.facing > 0 else m + 2)
	draw_rect(Rect2(eye_x, base.y + m + 4, 4, 4), Color.BLACK, true)

	# 状態フチ（フォーカス=黄太 / アクティブ=緑）
	if unit.state == BattleUnit.State.FOCUS:
		draw_rect(Rect2(base + Vector2(3, 3), Vector2(CELL_PX - 6, CELL_PX - 6)), Color(1.0, 0.9, 0.2), false, 3.0)
	elif unit.state == BattleUnit.State.ACTIVE:
		draw_rect(Rect2(base + Vector2(3, 3), Vector2(CELL_PX - 6, CELL_PX - 6)), Color(0.55, 0.9, 0.4), false, 2.0)

	# ターゲット候補の強調（選択中は太い赤、他候補は細い赤）
	if _mgr.turn_phase == BattleManager.TurnPhase.TARGETING and unit in _mgr.targets:
		var is_cur := _mgr.targets[_mgr.target_index] == unit
		draw_rect(Rect2(base + Vector2(1, 1), Vector2(CELL_PX - 2, CELL_PX - 2)),
			Color(1.0, 0.3, 0.3), false, 4.0 if is_cur else 1.5)

	# ATBバー（上）
	var atb_bg := Rect2(base + Vector2(m, -ATB_BAR_H - HP_BAR_H - 5.0), Vector2(CELL_PX - 2.0 * m, ATB_BAR_H))
	draw_rect(atb_bg, Color(0.18, 0.18, 0.22), true)
	var atb_ratio := clampf(unit.atb / BattleUnit.ATB_FULL, 0.0, 1.0)
	var atb_col := Color(0.3, 0.8, 1.0) if unit.state == BattleUnit.State.WAIT else Color(1.0, 0.85, 0.3)
	draw_rect(Rect2(atb_bg.position, Vector2(atb_bg.size.x * atb_ratio, atb_bg.size.y)), atb_col, true)

	# HPバー（ATBの下）
	var hp_bg := Rect2(base + Vector2(m, -HP_BAR_H - 3.0), Vector2(CELL_PX - 2.0 * m, HP_BAR_H))
	draw_rect(hp_bg, Color(0.25, 0.12, 0.12), true)
	var hp_ratio := clampf(float(unit.hp) / float(unit.max_hp), 0.0, 1.0)
	draw_rect(Rect2(hp_bg.position, Vector2(hp_bg.size.x * hp_ratio, hp_bg.size.y)), Color(0.4, 0.85, 0.4), true)


## 飛来攻撃の予告リング。対象マスの中心に、基準円へ収束する外周リングを描く。
## 重なる瞬間（外周≒基準円）に r(攻撃)/e(スキル) を押すと成功。
func _draw_parry_ring(inc: ParrySystem.Incoming) -> void:
	if not _mgr.grid.has_unit(inc.target.id):
		return
	var center := ORIGIN + Vector2(_mgr.grid.get_origin(inc.target.id)) * CELL_PX + Vector2(CELL_PX, CELL_PX) * 0.5
	var base_r := CELL_PX * 0.46
	# 種別で色分け（r=攻撃=橙 / e=スキル=紫）。潰された予告は灰色。
	var col := Color(1.0, 0.6, 0.2) if inc.kind == SkillData.ParryKind.ATTACK else Color(0.7, 0.4, 1.0)
	if inc.disabled:
		col = Color(0.45, 0.45, 0.45)
	# 基準円（着弾位置）
	draw_arc(center, base_r, 0.0, TAU, 48, Color(col, 0.5), 2.0)
	# 収束する外周リング（t=TELEGRAPH で大きく、t=0 で基準円に重なる）
	var ratio := clampf(inc.t / ParrySystem.TELEGRAPH, 0.0, 1.0)
	var outer_r := base_r + CELL_PX * 1.1 * ratio
	draw_arc(center, outer_r, 0.0, TAU, 48, col, 3.0)
	# 重なる瞬間が近いほど内側を満たして「合わせどき」を示す
	if not inc.disabled and absf(inc.t) <= ParrySystem.WINDOW * 2.0:
		draw_circle(center, base_r * 0.4, Color(col, 0.8))

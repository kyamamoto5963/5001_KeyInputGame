extends Node2D
## 戦闘シーン（縦スライスの足場）。描画と入力ルーティングだけを持ち、
## 進行ロジックは BattleManager に委ねる（→ ../../docs/06_systems.md 疎結合方針）。
##
## 今スライスで見えるもの: ATBバーが溜まる → 溜まった順にアクティブ化 → フォーカスが回る。
## フォーカス中の味方を移動キーで動かし、W で行動終了（パス→ATB20%へ）、P でポーズ（全凍結）。
## 敵はAI未実装なのでアクティブ化したら即パスする（ループを見えるようにするための仮挙動）。

const CELL_PX := 64
const ORIGIN := Vector2(48, 120)  # グリッド左上の画面位置
const ATB_BAR_H := 6.0

var _mgr := BattleManager.new()

@onready var _info: Label = $UI/Info


func _ready() -> void:
	# 味方2・敵1を配置（atb_speed はキャラ差の仮値＝満了まで 剣士4s/魔法5.5s/雑魚5s）。
	_mgr.add_unit(BattleUnit.new(0, "剣士", BattleUnit.Team.ALLY, 0.25), Vector2i(1, 1))
	_mgr.add_unit(BattleUnit.new(1, "魔法", BattleUnit.Team.ALLY, 0.18), Vector2i(0, 0))
	_mgr.add_unit(BattleUnit.new(2, "雑魚", BattleUnit.Team.ENEMY, 0.20), Vector2i(8, 1))


func _process(_delta: float) -> void:
	_mgr.process(_delta)
	queue_redraw()
	_update_info()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.PAUSE):
		_mgr.toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(InputActions.END_TURN):
		_mgr.end_turn()
		get_viewport().set_input_as_handled()
		return

	var dir := Vector2i.ZERO
	if event.is_action_pressed(InputActions.MOVE_UP):
		dir = Vector2i(0, -1)
	elif event.is_action_pressed(InputActions.MOVE_DOWN):
		dir = Vector2i(0, 1)
	elif event.is_action_pressed(InputActions.MOVE_LEFT):
		dir = Vector2i(-1, 0)
	elif event.is_action_pressed(InputActions.MOVE_RIGHT):
		dir = Vector2i(1, 0)
	if dir != Vector2i.ZERO:
		_mgr.move_focus(dir)
		get_viewport().set_input_as_handled()
		return

	# デバッグ: 移動レイアウト切替（1=jikl / 2=hjkl / 3=arrows）。後で設定画面へ移す。
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1: GameState.set_movement_layout("jikl")
			KEY_2: GameState.set_movement_layout("hjkl")
			KEY_3: GameState.set_movement_layout("arrows")


func _update_info() -> void:
	var prog: String = ["進行中", "ポーズ", "終了処理中"][_mgr.progress]
	var focus_name: String = _mgr.focus.display_name if _mgr.focus != null else "なし"
	_info.text = "[%s] フォーカス:%s ｜ 移動:%s(矢印可) / W:行動終了 / P:ポーズ ｜ 切替 1jikl 2hjkl 3arrows" % [
		prog, focus_name, GameState.movement_layout,
	]


func _draw() -> void:
	# グリッド
	for y in BattleGrid.ROWS:
		for x in BattleGrid.COLS:
			var r := Rect2(ORIGIN + Vector2(x, y) * CELL_PX, Vector2(CELL_PX, CELL_PX))
			draw_rect(r, Color(0.12, 0.13, 0.16), true)
			draw_rect(r, Color(0.30, 0.32, 0.38), false, 2.0)
	# ユニット
	for unit in _mgr.units:
		_draw_unit(unit)


func _draw_unit(unit: BattleUnit) -> void:
	var cell := _mgr.grid.get_origin(unit.id)
	var base := ORIGIN + Vector2(cell) * CELL_PX
	var m := 8.0

	# 本体（味方=青 / 敵=赤、死亡は暗く）
	var col := Color(0.40, 0.70, 1.0) if unit.is_ally() else Color(0.95, 0.45, 0.45)
	if not unit.is_alive():
		col = col.darkened(0.6)
	draw_rect(Rect2(base + Vector2(m, m), Vector2(CELL_PX - 2.0 * m, CELL_PX - 2.0 * m)), col, true)

	# 状態フチ（フォーカス=黄太 / アクティブ=緑）
	if unit.state == BattleUnit.State.FOCUS:
		draw_rect(Rect2(base + Vector2(3, 3), Vector2(CELL_PX - 6, CELL_PX - 6)), Color(1.0, 0.9, 0.2), false, 3.0)
	elif unit.state == BattleUnit.State.ACTIVE:
		draw_rect(Rect2(base + Vector2(3, 3), Vector2(CELL_PX - 6, CELL_PX - 6)), Color(0.55, 0.9, 0.4), false, 2.0)

	# ATBバー（マスの上）。蓄積中=水色 / 満了待ち=橙。
	var bar_bg := Rect2(base + Vector2(m, -ATB_BAR_H - 3.0), Vector2(CELL_PX - 2.0 * m, ATB_BAR_H))
	draw_rect(bar_bg, Color(0.18, 0.18, 0.22), true)
	var ratio := clampf(unit.atb / BattleUnit.ATB_FULL, 0.0, 1.0)
	var bar_col := Color(0.3, 0.8, 1.0) if unit.state == BattleUnit.State.WAIT else Color(1.0, 0.85, 0.3)
	draw_rect(Rect2(bar_bg.position, Vector2(bar_bg.size.x * ratio, bar_bg.size.y)), bar_col, true)

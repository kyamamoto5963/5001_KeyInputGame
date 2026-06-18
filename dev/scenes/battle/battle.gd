extends Node2D
## 戦闘シーンの土台（縦スライスの足場）。
## いまの責務は最小限: 3×10 グリッドを描き、トークン1体を移動キーで動かす。
## ATB・ターン・スキル・パリィは後続スライスで足す（→ ../../docs/11_battle-spec.md）。

const CELL_PX := 64
const ORIGIN := Vector2(48, 96)  # グリッド左上の画面位置
const PLAYER_ID := 0

var _grid := BattleGrid.new()

@onready var _info: Label = $UI/Info


func _ready() -> void:
	# 中段の左端にトークンを1体置く。
	_grid.place_unit(PLAYER_ID, Vector2i(0, 1), Vector2i.ONE)
	GameState.movement_layout_changed.connect(_on_layout_changed)
	_update_info()


func _unhandled_input(event: InputEvent) -> void:
	# --- 移動（移動範囲は未実装なので 1マスずつ） ---
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
		_try_move(dir)
		get_viewport().set_input_as_handled()
		return

	# --- デバッグ: 移動レイアウト切替（1=jikl / 2=hjkl / 3=arrows）。後で設定画面へ移す。 ---
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1: GameState.set_movement_layout("jikl")
			KEY_2: GameState.set_movement_layout("hjkl")
			KEY_3: GameState.set_movement_layout("arrows")


func _try_move(dir: Vector2i) -> void:
	var target := _grid.get_origin(PLAYER_ID) + dir
	# 盤内かつ空き（自分は無視）なら確定。埋まってるマスには入れない（押し出さない）。
	if _grid.can_place(target, _grid.get_size(PLAYER_ID), PLAYER_ID):
		_grid.place_unit(PLAYER_ID, target, _grid.get_size(PLAYER_ID))
		queue_redraw()
		_update_info()


func _on_layout_changed(_layout_name: String) -> void:
	_update_info()


func _update_info() -> void:
	var cell := _grid.get_origin(PLAYER_ID)
	_info.text = "移動: %s（矢印も可） / 切替 1:jikl 2:hjkl 3:arrows\nセル: (%d, %d)" % [
		GameState.movement_layout, cell.x, cell.y,
	]


func _draw() -> void:
	# グリッド
	for y in BattleGrid.ROWS:
		for x in BattleGrid.COLS:
			var r := Rect2(ORIGIN + Vector2(x, y) * CELL_PX, Vector2(CELL_PX, CELL_PX))
			draw_rect(r, Color(0.12, 0.13, 0.16), true)
			draw_rect(r, Color(0.30, 0.32, 0.38), false, 2.0)
	# トークン（中央寄せで一回り小さく）
	var cell := _grid.get_origin(PLAYER_ID)
	var margin := 8.0
	var token := Rect2(
		ORIGIN + Vector2(cell) * CELL_PX + Vector2(margin, margin),
		Vector2(CELL_PX - margin * 2.0, CELL_PX - margin * 2.0),
	)
	draw_rect(token, Color(0.40, 0.70, 1.0), true)

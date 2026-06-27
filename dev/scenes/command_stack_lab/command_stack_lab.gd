extends Node2D
## コマンドスタック体感ラボ（→ ../../docs/11_battle-spec.md §2.5 入力モデル / §6 向きの決定ルール）。
## 動作開始タイミング **A（コマンド確定後に一括実行）** を試す独立シーン。ATB・敵なし、自キャラ1体。
##
## 操作:
##   移動キー(jikl/矢印): 1キー=1歩スタックに積む（移動歩数=3まで）。青カーソルが進む（押した歩数で数える）。
##   q → 左右           : 方向転換（黄カーソル）。向きを変える。**1行動ポイント消費**（移動と共有）。ターンは終了しない。
##   a → (左右上下) → a : 隣接マス選択スキル（赤カーソル）。初期照準は現在の向き側。a再押し/Enterで確定＝ターン締め。
##   w                  : 行動終了（パス）。今のスタックをそのまま実行。
##   Esc/Back           : サブモード解除 ／ MOVE中は直前の入力を取り消し。
## 確定すると、キャラが歩き速度(1マス/秒・MOVE_TIME)でスタックを消化する（ワープしない＝座標補間）。
## 向きは「移動の左右成分／q／スキル方向」で決まり、消化順に後勝ち（§6）。

const CELL_PX := 64
const ORIGIN := Vector2(48, 180)
const CHAR_DIR := "res://assets/char/char_001/"
const CHAR_SCALE := 0.42       # 256px原画をセルに合わせる表示倍率
const MOVE_STEPS := 3          # 仮（メンバー固有の move_steps）
const MOVE_TIME := 0.5         # 0.5秒/マス（要調整）
const FACE_BEAT := 0.15        # 方向転換の見せ間
const SKILL_FLASH := 0.4       # スキル発動マーカーの表示時間

const COL_GRID_FILL := Color(0.12, 0.13, 0.16)
const COL_GRID_LINE := Color(0.30, 0.32, 0.38)
const COL_MOVE := Color(0.30, 0.60, 1.0)   # 青: 移動カーソル
const COL_FACE := Color(1.0, 0.85, 0.20)   # 黄: 方向転換
const COL_SKILL := Color(1.0, 0.30, 0.30)  # 赤: スキル照準

enum Phase { MOVE, FACE, SKILL, EXECUTING }

var _phase: int = Phase.MOVE
var _stack: Array[Dictionary] = []
var _char_cell := Vector2i(2, 1)
var _char_px := Vector2.ZERO     # 実行中の補間用ピクセル座標
var _facing := 1                 # +1=右 / -1=左
var _cursor := Vector2i(2, 1)    # 入力で組んだ着地予定マス
var _pending_facing := 1         # スタック消化後の向き（後勝ち）
var _skill_dir := Vector2i(1, 0)
var _skill_flash_t := 0.0
var _skill_flash_cell := Vector2i.ZERO
var _hint := ""
var _char: CutoutCharacter

@onready var _info: Label = $UI/Info
@onready var _stack_label: Label = $UI/Stack


func _ready() -> void:
	_char_px = _cell_to_px(_char_cell)
	_char = CutoutCharacter.new()
	add_child(_char)
	_char.build(CHAR_DIR, CHAR_SCALE)
	_char.set_facing(_facing)
	_recompute()


func _process(delta: float) -> void:
	if _skill_flash_t > 0.0:
		_skill_flash_t -= delta
	# キャラ本体は CutoutCharacter ノードを足元位置に追従させる（_draw の四角は撤去）。
	var base_px := _char_px if _phase == Phase.EXECUTING else _cell_to_px(_char_cell)
	_char.position = base_px + Vector2(CELL_PX * 0.5, CELL_PX * 0.9)
	_char.set_facing(_facing)
	queue_redraw()
	_update_labels()


# --- 入力 ---------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if _phase == Phase.EXECUTING:
		return  # 方式A: 実行中は再入力を受けない（先行入力/タイミングBは次段）
	match _phase:
		Phase.MOVE: _input_move(event)
		Phase.FACE: _input_face(event)
		Phase.SKILL: _input_skill(event)


func _input_move(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.FACE):
		if _points_used() >= MOVE_STEPS:
			_hint = "行動ポイントの上限（%d）" % MOVE_STEPS
			return
		_phase = Phase.FACE
		_hint = ""
		return
	if event.is_action_pressed(InputActions.SKILL_A):
		_enter_skill()
		return
	if event.is_action_pressed(InputActions.END_TURN):
		_execute()
		return
	if event.is_action_pressed(InputActions.CANCEL):
		if not _stack.is_empty():
			_stack.pop_back()
			_recompute()
		return
	var dir := _read_dir(event)
	if dir != Vector2i.ZERO:
		if _points_used() >= MOVE_STEPS:
			_hint = "行動ポイントの上限（%d）" % MOVE_STEPS
			return
		if not _in_bounds(_cursor + dir):
			_hint = "盤外"
			return
		_hint = ""
		_stack.append({"type": "move", "dir": dir})
		_recompute()


func _input_face(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.CANCEL):
		_phase = Phase.MOVE
		return
	if event.is_action_pressed(InputActions.MOVE_LEFT):
		_stack.append({"type": "face", "dir": -1})
		_recompute()
		_phase = Phase.MOVE
		return
	if event.is_action_pressed(InputActions.MOVE_RIGHT):
		_stack.append({"type": "face", "dir": 1})
		_recompute()
		_phase = Phase.MOVE
		return
	# 上下は向きに無関係（向きは左右のみ・§6）


func _enter_skill() -> void:
	_phase = Phase.SKILL
	_skill_dir = Vector2i(_pending_facing, 0)  # 初期照準＝現在の向き側（§6）
	if not _in_bounds(_cursor + _skill_dir):
		_skill_dir = Vector2i(-_pending_facing, 0)  # 盤端なら反対側から
	_hint = ""


func _input_skill(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.CANCEL):
		_phase = Phase.MOVE
		return
	if event.is_action_pressed(InputActions.SKILL_A) or event.is_action_pressed(InputActions.CONFIRM):
		_stack.append({"type": "skill", "dir": _skill_dir})
		_execute()
		return
	var dir := _read_dir(event)
	if dir != Vector2i.ZERO and _in_bounds(_cursor + dir):
		_skill_dir = dir


# --- 実行（確定後に一括消化・歩き速度） ---------------------------------
func _execute() -> void:
	_phase = Phase.EXECUTING
	_hint = ""
	_char_px = _cell_to_px(_char_cell)
	for e in _stack:
		match e["type"]:
			"move":
				await _walk(e["dir"])
			"face":
				_facing = int(e["dir"])
				await _beat(FACE_BEAT)
			"skill":
				var d: Vector2i = e["dir"]
				if d.x != 0:
					_facing = signi(d.x)
				await _fire(_char_cell + d)
	_stack.clear()
	_phase = Phase.MOVE
	_recompute()


func _walk(dir: Vector2i) -> void:
	var target := _char_cell + dir
	if dir.x != 0:
		_facing = signi(dir.x)  # 移動方向を向く（左右成分のみ・§6）
	var tw := create_tween()
	tw.tween_property(self, "_char_px", _cell_to_px(target), MOVE_TIME)
	await tw.finished
	_char_cell = target


func _fire(cell: Vector2i) -> void:
	if _char != null:
		_char.play_attack()
	_skill_flash_cell = cell
	_skill_flash_t = SKILL_FLASH
	await get_tree().create_timer(SKILL_FLASH).timeout


func _beat(t: float) -> void:
	await get_tree().create_timer(t).timeout


# --- 派生状態 -----------------------------------------------------------
## スタックを replay して着地予定マス(_cursor)と確定向き(_pending_facing)を更新（後勝ち・§6）。
func _recompute() -> void:
	var pos := _char_cell
	var face := _facing
	for e in _stack:
		var t: String = e["type"]
		if t == "move":
			var d: Vector2i = e["dir"]
			pos += d
			if d.x != 0:
				face = signi(d.x)
		elif t == "face":
			face = int(e["dir"])
	_cursor = pos
	_pending_facing = face


func _move_count() -> int:
	var n := 0
	for e in _stack:
		if e["type"] == "move":
			n += 1
	return n


## 行動ポイント消費数。移動も方向転換も同じバジェット(MOVE_STEPS)を食う（q=1pt）。
func _points_used() -> int:
	var n := 0
	for e in _stack:
		if e["type"] == "move" or e["type"] == "face":
			n += 1
	return n


func _read_dir(event: InputEvent) -> Vector2i:
	if event.is_action_pressed(InputActions.MOVE_UP): return Vector2i(0, -1)
	if event.is_action_pressed(InputActions.MOVE_DOWN): return Vector2i(0, 1)
	if event.is_action_pressed(InputActions.MOVE_LEFT): return Vector2i(-1, 0)
	if event.is_action_pressed(InputActions.MOVE_RIGHT): return Vector2i(1, 0)
	return Vector2i.ZERO


func _in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < BattleGrid.COLS and c.y >= 0 and c.y < BattleGrid.ROWS


func _cell_to_px(c: Vector2i) -> Vector2:
	return ORIGIN + Vector2(c) * CELL_PX


func _center(c: Vector2i) -> Vector2:
	return _cell_to_px(c) + Vector2(CELL_PX, CELL_PX) * 0.5


# --- 描画 ---------------------------------------------------------------
func _draw() -> void:
	for y in BattleGrid.ROWS:
		for x in BattleGrid.COLS:
			var r := Rect2(_cell_to_px(Vector2i(x, y)), Vector2(CELL_PX, CELL_PX))
			draw_rect(r, COL_GRID_FILL, true)
			draw_rect(r, COL_GRID_LINE, false, 2.0)

	if _phase != Phase.EXECUTING:
		_draw_path()

	# キャラは CutoutCharacter ノードが描画する（_process で足元位置を追従）。

	match _phase:
		Phase.MOVE:
			_draw_cursor(_cursor, COL_MOVE)
		Phase.FACE:
			_draw_cursor(_cursor, COL_FACE)
			_draw_facing_arrow(_cursor, _pending_facing, COL_FACE)
		Phase.SKILL:
			_draw_cursor(_cursor, Color(COL_SKILL, 0.4))      # 発動位置（着地予定）
			_draw_cursor(_cursor + _skill_dir, COL_SKILL)     # 対象マス

	if _skill_flash_t > 0.0:
		var c := _cell_to_px(_skill_flash_cell)
		draw_rect(Rect2(c, Vector2(CELL_PX, CELL_PX)), Color(COL_SKILL, 0.5), true)
		draw_string(ThemeDB.fallback_font, c + Vector2(8, 38), "発動!", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)


func _draw_path() -> void:
	var pos := _char_cell
	var pts: Array[Vector2] = [_center(pos)]
	for e in _stack:
		if e["type"] == "move":
			pos += (e["dir"] as Vector2i)
			pts.append(_center(pos))
	for i in range(1, pts.size()):
		draw_line(pts[i - 1], pts[i], Color(COL_MOVE, 0.5), 2.0)
	for p in pts:
		draw_circle(p, 4.0, Color(COL_MOVE, 0.6))


func _draw_cursor(cell: Vector2i, col: Color) -> void:
	var r := Rect2(_cell_to_px(cell) + Vector2(2, 2), Vector2(CELL_PX - 4, CELL_PX - 4))
	draw_rect(r, col, false, 3.0)


func _draw_facing_arrow(cell: Vector2i, face: int, col: Color) -> void:
	var c := _center(cell)
	var tip := c + Vector2(face * CELL_PX * 0.3, 0)
	draw_line(c, tip, col, 3.0)
	draw_circle(tip, 4.0, col)


# --- ラベル -------------------------------------------------------------
func _update_labels() -> void:
	var face_txt := "右" if _facing > 0 else "左"
	var pf_txt := "右" if _pending_facing > 0 else "左"
	var phase_txt := ""
	match _phase:
		Phase.MOVE: phase_txt = "移動（青）"
		Phase.FACE: phase_txt = "方向転換（黄, 1pt消費）: 左右で向き"
		Phase.SKILL: phase_txt = "スキル照準（赤）: 左右上下で照準 → a再押し/Enterで発動"
		Phase.EXECUTING: phase_txt = "実行中…"
	var head := "[%s] 向き:%s  残ポイント:%d/%d" % [phase_txt, face_txt, MOVE_STEPS - _points_used(), MOVE_STEPS]
	if _phase == Phase.MOVE or _phase == Phase.FACE:
		head += "  (確定後の向き:%s)" % pf_txt
	if _hint != "":
		head += "   ⚠ " + _hint
	_info.text = "%s\n移動:jikl/矢印   q:方向転換   a:スキル(隣接)   w:行動終了   Esc:取消" % head
	_stack_label.text = "STACK:  " + _stack_text()


func _stack_text() -> String:
	var parts: PackedStringArray = []
	for e in _stack:
		match e["type"]:
			"move": parts.append(_arrow(e["dir"]))
			"face": parts.append("q" + ("→" if int(e["dir"]) > 0 else "←"))
			"skill": parts.append("a" + _arrow(e["dir"]))
	if _phase == Phase.FACE:
		parts.append("q?")
	elif _phase == Phase.SKILL:
		parts.append("a" + _arrow(_skill_dir) + "?")
	if parts.is_empty():
		return "(空)"
	return "  ".join(parts)


func _arrow(dir: Variant) -> String:
	var d: Vector2i = dir
	if d == Vector2i(1, 0): return "→"
	if d == Vector2i(-1, 0): return "←"
	if d == Vector2i(0, -1): return "↑"
	if d == Vector2i(0, 1): return "↓"
	return "?"

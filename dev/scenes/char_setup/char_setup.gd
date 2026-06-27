extends Node2D
## キャラ・カットアウト セットアップ／プレビュー シーン（最小サンプル）。
## CutoutCharacter コンポーネント（→ res://scripts/cutout_character.gd）で char_001 のリグを組み、
## 手続きアイドルとテストモーションを確認する。リグ本体は同コンポーネントが持つ（command_stack_lab と共用）。
##
## 操作:
##   Space / a : テストモーション（前のめりの予備動作っぽい揺れ）
##   b         : ボーン・ギズモ表示 ON/OFF
##   f         : 向き反転（左右）
##   [ / ]     : 表示倍率 −／＋
##   r         : リセット

const CHAR_DIR := "res://assets/char/char_001/"

var _char: CutoutCharacter
var _scale := 2.0
var _facing := 1
var _show_bones := true

@onready var _info: Label = $UI/Info


func _ready() -> void:
	_char = CutoutCharacter.new()
	_char.z_index = -1            # キャラを背面へ。ボーン・ギズモ(self の _draw)を前面に。
	_char.z_as_relative = false
	add_child(_char)
	_char.build(CHAR_DIR, _scale)
	_place_char()


func _process(_delta: float) -> void:
	queue_redraw()
	_update_label()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.SKILL_A) or _is_space(event):
		_char.play_attack()
	elif _is_key(event, KEY_B):
		_show_bones = not _show_bones
	elif _is_key(event, KEY_F):
		_facing *= -1
		_char.set_facing(_facing)
	elif _is_key(event, KEY_BRACKETRIGHT):
		_scale = min(_scale + 0.25, 4.0)
		_char.set_display_scale(_scale)
	elif _is_key(event, KEY_BRACKETLEFT):
		_scale = max(_scale - 0.25, 0.75)
		_char.set_display_scale(_scale)
	elif _is_key(event, KEY_R):
		_scale = 2.0
		_facing = 1
		_char.set_display_scale(_scale)
		_char.set_facing(_facing)


func _place_char() -> void:
	var vp := get_viewport_rect().size
	_char.position = Vector2(vp.x * 0.5, vp.y * 0.94)


# --- ボーン・ギズモ -----------------------------------------------------
func _draw() -> void:
	if not _show_bones:
		return
	var pts := _char.bone_globals()   # 足元, 腰, 胸, 首
	if pts.is_empty():
		return
	for i in range(1, pts.size()):
		draw_line(to_local(pts[i - 1]), to_local(pts[i]), Color(0.3, 1.0, 0.5, 0.7), 2.0)
	draw_circle(to_local(pts[0]), 4.0, Color(0.3, 1.0, 0.5, 0.9))   # 足元
	for i in range(1, pts.size()):
		draw_circle(to_local(pts[i]), 5.0, Color(1.0, 0.85, 0.2, 0.9))


func _update_label() -> void:
	var face_txt := "右" if _facing > 0 else "左"
	_info.text = "カットアウト・キャラ セットアップ（char_001 / 頭・胴・スカートの3パーツ）\n" \
		+ "向き:%s  倍率:%.2fx  ボーン:%s\n" % [face_txt, _scale, "表示" if _show_bones else "非表示"] \
		+ "Space/a:テストモーション  b:ボーン表示  f:向き反転  [ ]:倍率  r:リセット"


# --- ユーティリティ -----------------------------------------------------
func _is_space(event: InputEvent) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE


func _is_key(event: InputEvent, code: int) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.keycode == code

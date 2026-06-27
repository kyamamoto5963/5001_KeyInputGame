extends Node2D
## キャラ・カットアウト セットアップ／プレビュー シーン（最小サンプル）。
## CutoutCharacter コンポーネント（→ res://scripts/cutout_character.gd）で char_001 のリグを組み、
## 手続きアイドルとテストモーションを確認する。リグ本体は同コンポーネントが持つ（command_stack_lab と共用）。
##
## 操作:
##   n         : キャラ切り替え（char_001 / char_002 ...）
##   Space / a : テストモーション（前のめりの予備動作っぽい揺れ）
##   b         : ボーン・ギズモ表示 ON/OFF
##   f         : 向き反転（左右）
##   [ / ]     : 表示倍率 −／＋
##   r         : 自動フィット倍率に戻す

const SKELETON := "res://assets/char/skeletons/humanoid_v1.json"
const CHARS := [
	{"name": "mannequin(rig)", "type": "rig", "src": "res://data/characters/mannequin.json"},
	{"name": "char_001", "type": "legacy", "src": "res://assets/char/char_001/"},
	{"name": "char_002", "type": "legacy", "src": "res://assets/char/char_002/"},
]

var _char: CutoutCharacter
var _idx := 0
var _scale := 2.0
var _facing := 1
var _show_bones := true

@onready var _info: Label = $UI/Info


func _ready() -> void:
	_load_char(0)


func _load_char(idx: int) -> void:
	_idx = (idx + CHARS.size()) % CHARS.size()
	if is_instance_valid(_char):
		_char.queue_free()
	_char = CutoutCharacter.new()
	_char.z_index = -1            # キャラを背面へ。ボーン・ギズモ(self の _draw)を前面に。
	_char.z_as_relative = false
	add_child(_char)
	var entry: Dictionary = CHARS[_idx]
	if entry["type"] == "rig":
		_char.build_rig(SKELETON, entry["src"], 1.0)
	else:
		_char.build(entry["src"], 1.0)
	_facing = 1
	_char.set_facing(_facing)
	_fit_scale()
	_place_char()


## ビューポート高さの約7割に収まる表示倍率へ。
func _fit_scale() -> void:
	var vp := get_viewport_rect().size
	_scale = clampf(vp.y * 0.72 / _char.content_height(), 0.3, 4.0)
	_char.set_display_scale(_scale)


func _process(_delta: float) -> void:
	queue_redraw()
	_update_label()


func _unhandled_input(event: InputEvent) -> void:
	if _is_key(event, KEY_N):
		_load_char(_idx + 1)
	elif event.is_action_pressed(InputActions.SKILL_A) or _is_space(event):
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
		_fit_scale()


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
	var cname := str(CHARS[_idx]["name"])
	_info.text = "カットアウト・キャラ セットアップ（%s）\n" % cname \
		+ "向き:%s  倍率:%.2fx  ボーン:%s\n" % [face_txt, _scale, "表示" if _show_bones else "非表示"] \
		+ "n:キャラ切替  Space/a:モーション  b:ボーン  f:向き反転  [ ]:倍率  r:フィット"


# --- ユーティリティ -----------------------------------------------------
func _is_space(event: InputEvent) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE


func _is_key(event: InputEvent, code: int) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.keycode == code

extends Node2D
class_name CutoutCharacter
## パーツ画像(parts.json)からカットアウト・リグを組み、手続きアイドルを再生する再利用コンポーネント。
## ノード原点＝キャラの足元。owner はこのノードを足元位置に置き、build() を呼ぶだけでよい。
## ボーンや変形は無し（パーツを親子で繋ぐ操り人形方式）。1枚のAI生成絵をそのまま動かす。
##
## 階層: self(足元) → _rig(表示倍率・左右反転) → hip(腰) → chest(胸=揺れ起点) → neck(首)

const DEFAULT_DIR := "res://assets/char/char_001/"

# 二次モーション（胸の揺れ・スプリングボーン近似 → docs/12 §5.3-jiggle）
const JIG_STIFF := 110.0     # 戻る強さ（高い=速い揺れ）
const JIG_DAMP := 6.0        # 減衰（高い=すぐ収束）
const JIG_DRIVE := 0.035     # 本体加速度→揺れ の効き
const JIG_MAX := 9.0         # 揺れ幅クランプ(px・未スケール)
const JIG_SQUASH := 0.018    # 縦揺れの伸縮量

var display_scale := 2.0
var _rig: Node2D                        # 倍率・左右反転をまとめる入れ物
var _hip: Node2D
var _chest: Node2D
var _neck: Node2D
var _sprites := {}
var _joints := {}                       # name -> 元キャンバス座標(Vector2)
var _facing := 1                        # +1=右 / -1=左
var _art_facing := 1                     # 原画が向いている方向(+1=右/-1=左)。parts.json の art_facing。
var _content_top := 0.0                  # 最上部パーツのY（足元からの全高計算用）
var _t := 0.0
var _lean := 0.0                        # テストモーションのエンベロープ(0..1)
var _jig := Vector2.ZERO                # 揺れ変位
var _jig_v := Vector2.ZERO              # 揺れ速度
var _prev_g := Vector2.ZERO             # 前フレームのワールド座標
var _prev_v := Vector2.ZERO             # 前フレームのワールド速度
var _jig_init := false
var _built := false


## parts.json からリグを構築。成功したら true。
func build(dir := DEFAULT_DIR, scale := 2.0) -> bool:
	display_scale = scale
	var meta := _load_meta(dir)
	if meta.is_empty():
		push_error("parts.json を読めません: " + dir)
		return false

	_art_facing = signi(int(meta.get("art_facing", 1)))   # 既定=右向き（本チャンデータ）
	if _art_facing == 0:
		_art_facing = 1
	var j: Dictionary = meta["joints"]
	_joints = {
		"neck": _v2(j["neck"]),
		"waist": _v2(j["waist"]),
		"feet": _v2(j["feet"]),
	}
	var parts := {}
	for p in meta["parts"]:
		parts[p["name"]] = p

	_rig = Node2D.new()
	add_child(_rig)
	_apply_rig_transform()

	# ボーン階層（自関節 − 親関節 で配置。root基準＝feet）
	_hip = _make_bone(_rig, _joints["waist"], _joints["feet"])
	_chest = _make_bone(_hip, _joints["waist"], _joints["waist"])
	_neck = _make_bone(_chest, _joints["neck"], _joints["waist"])

	_sprites["skirt"] = _make_sprite(_hip, dir, parts["skirt"], _joints["waist"])
	_sprites["torso"] = _make_sprite(_chest, dir, parts["torso"], _joints["waist"])
	_sprites["head"] = _make_sprite(_neck, dir, parts["head"], _joints["neck"])

	_content_top = _joints["feet"].y
	for p in parts.values():
		_content_top = min(_content_top, float(p["offset"][1]))

	_built = true
	return true


## 原画の全高(px・未スケール)。足元〜最上部パーツ。表示倍率の自動フィットに使う。
func content_height() -> float:
	return maxf(1.0, _joints["feet"].y - _content_top)


func set_facing(f: int) -> void:
	if f != 0:
		_facing = signi(f)
	if _built:
		_apply_rig_transform()


func set_display_scale(s: float) -> void:
	display_scale = s
	if _built:
		_apply_rig_transform()


## テストモーション（前のめりの予備動作っぽいリーン）。
func play_attack() -> void:
	if not _built:
		return
	_jig_v += Vector2(0.0, 22.0)   # 攻撃で胸にバウンスのインパルス
	var tw := create_tween()
	tw.tween_property(self, "_lean", 1.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "_lean", 0.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## ボーン位置（グローバル座標）。owner がギズモ描画したい時用。順: 足元, 腰, 胸, 首。
func bone_globals() -> PackedVector2Array:
	if not _built:
		return PackedVector2Array()
	return PackedVector2Array([
		global_position, _hip.global_position, _chest.global_position, _neck.global_position,
	])


func _process(delta: float) -> void:
	if not _built:
		return
	_t += delta
	_update_jiggle(delta)
	var breathe := sin(_t * 2.2)
	# 揺れ: 縦成分=スカッシュ＋上下、横成分=左右オフセット＋わずかな傾き
	var squash := _jig.y * JIG_SQUASH
	_chest.scale = Vector2(1.0 - squash, 1.0 + breathe * 0.015 + squash)
	_chest.position = Vector2(_jig.x * 0.5, _jig.y * 0.5)
	var lean_rot := deg_to_rad(_lean * -16.0)   # 反転は _rig のミラーが面倒を見る
	_chest.rotation = deg_to_rad(breathe * 1.2) + lean_rot + deg_to_rad(_jig.x * 0.4)
	_neck.rotation = deg_to_rad(sin(_t * 2.2 + 0.7) * 2.2) + lean_rot * 0.6
	_hip.rotation = deg_to_rad(sin(_t * 1.6) * 0.8)


## 本体ボーンの加速度を入力に、胸ボーンをバネ-ダンパで遅れて揺らす（半暗黙オイラー）。
func _update_jiggle(delta: float) -> void:
	var g := global_position
	if not _jig_init:           # 初フレームのワープ加速度を拾わない
		_prev_g = g
		_jig_init = true
	var v := (g - _prev_g) / maxf(delta, 0.0001)
	var a := v - _prev_v
	_prev_g = g
	_prev_v = v
	_jig_v += (-JIG_STIFF * _jig - JIG_DAMP * _jig_v) * delta
	_jig_v += -a * JIG_DRIVE     # 慣性: 本体が動くと胸は逆向きに遅れる
	_jig = (_jig + _jig_v * delta).limit_length(JIG_MAX)


# --- 構築ヘルパ ---------------------------------------------------------
func _apply_rig_transform() -> void:
	# 望む向き(_facing)と原画の向き(_art_facing)が違う時だけミラーする。
	var flip := _facing * _art_facing
	_rig.scale = Vector2(flip * display_scale, display_scale)


func _make_bone(parent: Node2D, anchor: Vector2, parent_anchor: Vector2) -> Node2D:
	var b := Node2D.new()
	b.position = anchor - parent_anchor
	parent.add_child(b)
	return b


func _make_sprite(bone: Node2D, dir: String, part: Dictionary, bone_anchor: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = load(dir + str(part["name"]) + ".png")
	s.centered = false
	s.position = _v2(part["offset"]) - bone_anchor
	bone.add_child(s)
	return s


func _load_meta(dir: String) -> Dictionary:
	var path := dir + "parts.json"
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


func _v2(a: Variant) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))

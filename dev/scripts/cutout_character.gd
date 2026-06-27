extends Node2D
class_name CutoutCharacter
## パーツ画像(parts.json)からカットアウト・リグを組み、手続きアイドルを再生する再利用コンポーネント。
## ノード原点＝キャラの足元。owner はこのノードを足元位置に置き、build() を呼ぶだけでよい。
## ボーンや変形は無し（パーツを親子で繋ぐ操り人形方式）。1枚のAI生成絵をそのまま動かす。
##
## 階層: self(足元) → _rig(表示倍率・左右反転) → hip(腰) → chest(胸=揺れ起点) → neck(首)

const DEFAULT_DIR := "res://assets/char/char_001/"

# 二次モーション（胸の揺れ・スプリングボーン近似 → docs/12 §5.3-jiggle）
const JIG_STIFF := 70.0      # 戻る強さ（低い=ゆったり大きく揺れる）
const JIG_DAMP := 3.2        # 減衰（低い=ぷるんと長く揺れる）
const JIG_DRIVE := 0.06      # 本体加速度→揺れ の効き
const JIG_MAX := 26.0        # 揺れ幅クランプ(px・未スケール)
const JIG_SQUASH := 0.05     # 縦揺れの伸縮量（大きい=よく伸び縮み）
const JIG_ATTACK_IMPULSE := 60.0  # 攻撃時のバウンス強さ

var display_scale := 2.0
var _rig: Node2D                        # 倍率・左右反転をまとめる入れ物
var _hip: Node2D
var _chest: Node2D
var _neck: Node2D
var _chest_rest := Vector2.ZERO         # 胸ボーンの基準位置（揺れはここからのオフセット）
var _bones := {}                        # リグ方式: name -> Node2D（legacyでは空）
var _limb_pairs := []                    # facingで前後入れ替える左右ペア [{r,l,far,near}]
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
	_chest_rest = _chest.position

	_sprites["skirt"] = _make_sprite(_hip, dir, parts["skirt"], _joints["waist"])
	_sprites["torso"] = _make_sprite(_chest, dir, parts["torso"], _joints["waist"])
	_sprites["head"] = _make_sprite(_neck, dir, parts["head"], _joints["neck"])

	_content_top = _joints["feet"].y
	for p in parts.values():
		_content_top = min(_content_top, float(p["offset"][1]))

	_built = true
	return true


## スケルトン＋キャラデータからフルボーン・リグを組む（→ docs/12）。成功で true。
## skeleton_path: humanoid_v1.json / character_path: data/characters/<name>.json
func build_rig(skeleton_path: String, character_path: String, scale := 1.0) -> bool:
	display_scale = scale
	var skel := _load_json(skeleton_path)
	var char := _load_json(character_path)
	if skel.is_empty() or char.is_empty():
		push_error("skeleton/character を読めません: %s / %s" % [skeleton_path, character_path])
		return false

	_art_facing = signi(int(char.get("art_facing", 1)))
	if _art_facing == 0:
		_art_facing = 1
	var bones_def: Dictionary = skel["bones"]
	var slots_def: Dictionary = skel.get("slots", {})
	var feet_pos := _v2(bones_def["feet"]["pos"])
	_joints = {"feet": feet_pos}

	_rig = Node2D.new()
	add_child(_rig)
	_apply_rig_transform()

	# ボーン生成（親→子の順）。各ボーン位置 = 自pos − 親pos（root親=feet）。
	_bones = {}
	for name in _topo_order(bones_def):
		var bd: Dictionary = bones_def[name]
		var parent_name: Variant = bd.get("parent", null)
		var parent_node: Node2D = _rig if parent_name == null else _bones[parent_name]
		var parent_pos := feet_pos if parent_name == null else _v2(bones_def[parent_name]["pos"])
		var b := Node2D.new()
		b.position = _v2(bd["pos"]) - parent_pos
		parent_node.add_child(b)
		_bones[name] = b

	_hip = _bones.get("hip")
	_chest = _bones.get("chest")
	_neck = _bones.get("neck")
	if _chest != null:
		_chest_rest = _chest.position

	# パーツ配置（anchor をボーン原点へ合わせる。z でレイヤ順、tint で色替え）
	_content_top = feet_pos.y
	var tint: Dictionary = char.get("tint", {})
	var parts: Dictionary = char["parts"]
	for slot in parts:
		var idv: Variant = parts[slot]
		if idv == null or str(idv) == "":
			continue
		var pj := _load_json("res://assets/char/parts/%s/%s.json" % [slot, idv])
		if pj.is_empty():
			continue
		var attach := str(pj.get("attach", slots_def.get(slot, {}).get("attach", "")))
		if not _bones.has(attach):
			push_warning("未知のattachボーン: %s (slot=%s)" % [attach, slot])
			continue
		var anchor := _v2(pj["anchor"])
		var s := Sprite2D.new()
		s.texture = load("res://assets/char/parts/%s/%s.png" % [slot, idv])
		s.centered = false
		s.position = -anchor
		s.z_index = int(pj.get("z", slots_def.get(slot, {}).get("z", 0)))
		if tint.has(slot):
			s.modulate = Color(str(tint[slot]))
		_bones[attach].add_child(s)
		_sprites[slot] = s
		_content_top = min(_content_top, _v2(bones_def[attach]["pos"]).y - anchor.y)

	_build_limb_pairs()
	_apply_limb_depth()
	_built = true
	return true


# 左右の腕脚を前後ペアとして登録（facing反転で z を入れ替えるため）。
func _build_limb_pairs() -> void:
	_limb_pairs = []
	for base in ["arm_upper", "arm_fore", "hand", "leg_thigh", "leg_shin", "foot"]:
		var sr: Sprite2D = _sprites.get(base + "_r")
		var sl: Sprite2D = _sprites.get(base + "_l")
		if sr != null and sl != null:
			_limb_pairs.append({
				"r": sr, "l": sl,
				"far": mini(sr.z_index, sl.z_index),   # 奥
				"near": maxi(sr.z_index, sl.z_index),   # 手前
			})


# キャラが向いている側の腕脚を手前に（振り返り＝前後入れ替え）。
func _apply_limb_depth() -> void:
	for p in _limb_pairs:
		if _facing > 0:
			p["r"].z_index = p["far"]
			p["l"].z_index = p["near"]
		else:
			p["r"].z_index = p["near"]
			p["l"].z_index = p["far"]


## 原画の全高(px・未スケール)。足元〜最上部パーツ。表示倍率の自動フィットに使う。
func content_height() -> float:
	return maxf(1.0, _joints["feet"].y - _content_top)


func set_facing(f: int) -> void:
	if f != 0:
		_facing = signi(f)
	if _built:
		_apply_rig_transform()
		_apply_limb_depth()


func set_display_scale(s: float) -> void:
	display_scale = s
	if _built:
		_apply_rig_transform()


## テストモーション（前のめりの予備動作っぽいリーン）。
func play_attack() -> void:
	if not _built:
		return
	_jig_v += Vector2(0.0, JIG_ATTACK_IMPULSE)   # 攻撃で胸にバウンスのインパルス
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
	_chest.position = _chest_rest + Vector2(_jig.x * 0.5, _jig.y * 0.5)
	var lean_rot := deg_to_rad(_lean * -16.0)   # 反転は _rig のミラーが面倒を見る
	_chest.rotation = deg_to_rad(breathe * 1.2) + lean_rot + deg_to_rad(_jig.x * 0.4)
	_neck.rotation = deg_to_rad(sin(_t * 2.2 + 0.7) * 2.2) + lean_rot * 0.6
	_hip.rotation = deg_to_rad(sin(_t * 1.6) * 0.8)
	_animate_limbs(lean_rot)


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
	_jig_v.y += cos(_t * 2.2) * 14.0 * delta   # 呼吸に同期した待機中の微揺れ
	_jig = (_jig + _jig_v * delta).limit_length(JIG_MAX)


# 腕脚の待機スウェイ＋攻撃時の前腕リーン（リグ方式のみ。legacyは _bones 空で無効）。
func _animate_limbs(lean_rot: float) -> void:
	if _bones.is_empty():
		return
	var sway := sin(_t * 1.4)
	_set_bone_rot("shoulder_l", deg_to_rad(7.0 + sway * 4.0) + lean_rot)
	_set_bone_rot("shoulder_r", deg_to_rad(-7.0 - sway * 4.0))
	_set_bone_rot("elbow_l", deg_to_rad(sway * 3.0))
	_set_bone_rot("elbow_r", deg_to_rad(-sway * 3.0))
	_set_bone_rot("thigh_l", deg_to_rad(sway * 2.0))
	_set_bone_rot("thigh_r", deg_to_rad(-sway * 2.0))


func _set_bone_rot(name: String, r: float) -> void:
	if _bones.has(name):
		_bones[name].rotation = r


# 親が子より先に来るボーン順（トポロジカル）。
func _topo_order(bones_def: Dictionary) -> Array:
	var order: Array = []
	var added := {}
	while order.size() < bones_def.size():
		var progressed := false
		for name in bones_def:
			if added.has(name):
				continue
			var parent: Variant = bones_def[name].get("parent", null)
			if parent == null or added.has(parent):
				order.append(name)
				added[name] = true
				progressed = true
		if not progressed:
			break   # 不正な親参照（循環/欠落）で無限ループ回避
	return order


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
	return _load_json(dir + "parts.json")


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


func _v2(a: Variant) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))

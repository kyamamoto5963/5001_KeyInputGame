extends Node
## InputMap をコードで構築する（→ ../../docs/06_systems.md「入力定義」）。
##
## 方針:
## - キーは直書きせず InputMap のアクション名で参照する（コア制約＝キーボードのみ の担保）。
## - キーは physical_keycode で割り当て、配列差（QWERTY/AZERTY 等）に強くする。
## - 移動レイアウトは差し替え可能（jikl / hjkl / arrows）。**矢印キーは常に併用**。
## - アクション名は用語集（docs/README.md）・06_systems と一致させる。
##
## 実体の適用は GameState._ready() が保存中のレイアウトで呼ぶ（共有データが主、ここは機構）。

# --- アクション名（用語集と一致） ---------------------------------------
const MOVE_UP := "move_up"
const MOVE_DOWN := "move_down"
const MOVE_LEFT := "move_left"
const MOVE_RIGHT := "move_right"

const FACE := "face"                 # Q: 向き変更モード
const END_TURN := "end_turn"         # W: 行動終了（パス）
const PARRY_SKILL := "parry_skill"   # E: スキルパリィ
const PARRY_ATTACK := "parry_attack" # R: 攻撃パリィ
const SKILL_A := "skill_a"           # A/S/D/F: 編成した4スキル
const SKILL_S := "skill_s"
const SKILL_D := "skill_d"
const SKILL_F := "skill_f"
const CONFIRM := "confirm"
const CANCEL := "cancel"
const PAUSE := "pause"

# --- 移動レイアウトのプリセット（右手レイアウト） -----------------------
# 矢印キーは常に併用するので、ここには letter 割り当てだけを書く。
const LAYOUTS := {
	"jikl": {"up": KEY_I, "down": KEY_K, "left": KEY_J, "right": KEY_L},
	"hjkl": {"up": KEY_K, "down": KEY_J, "left": KEY_H, "right": KEY_L},
	"arrows": {},  # 矢印のみ（letter 割り当てなし）
}

const _ARROW_KEYS := {"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT}
const _MOVE_ACTIONS := {
	MOVE_UP: "up", MOVE_DOWN: "down", MOVE_LEFT: "left", MOVE_RIGHT: "right",
}


## 全アクションを構築し、移動だけ指定レイアウトで割り当てる。
func setup_all(movement_layout: String) -> void:
	_setup_fixed_actions()
	apply_movement_layout(movement_layout)


## 移動4アクションを差し替える。矢印キーは常に併用、letter は指定プリセット。
func apply_movement_layout(layout_name: String) -> void:
	var preset: Dictionary = LAYOUTS.get(layout_name, {})
	for action in _MOVE_ACTIONS:
		var dir: String = _MOVE_ACTIONS[action]
		_ensure_action(action)
		InputMap.action_erase_events(action)
		_add_key(action, _ARROW_KEYS[dir])  # 矢印は常に有効
		if preset.has(dir):
			_add_key(action, preset[dir])


## 移動以外（拠点が変わっても固定）のアクションを割り当てる。
func _setup_fixed_actions() -> void:
	# 左手レイアウト: 上段 Q W E R ／ 下段 A S D F（→ 06_systems）
	_bind(FACE, [KEY_Q])
	_bind(END_TURN, [KEY_W])
	_bind(PARRY_SKILL, [KEY_E])
	_bind(PARRY_ATTACK, [KEY_R])
	_bind(SKILL_A, [KEY_A])
	_bind(SKILL_S, [KEY_S])
	_bind(SKILL_D, [KEY_D])
	_bind(SKILL_F, [KEY_F])
	# 決定・キャンセル・ポーズ
	_bind(CONFIRM, [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE])
	_bind(CANCEL, [KEY_ESCAPE, KEY_BACKSPACE])
	_bind(PAUSE, [KEY_P])


# --- 低レベルヘルパ -----------------------------------------------------
func _bind(action: String, keycodes: Array) -> void:
	_ensure_action(action)
	InputMap.action_erase_events(action)
	for kc in keycodes:
		_add_key(action, kc)


func _ensure_action(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)


func _add_key(action: String, physical_keycode: int) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = physical_keycode
	InputMap.action_add_event(action, ev)

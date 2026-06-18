class_name SkillData
extends Resource
## スキル1つの定義（→ ../../docs/11_battle-spec.md §6「スキル(データ駆動)」）。
## コード直書きにせず Godot リソース(.tres)として持つ。通常攻撃もこの形（特別扱いしない）。
## 後でスキルエディタを被せられるよう、ここの @export がそのまま「エディタで弄る項目」。

enum TargetType { TARGET, AREA, SELF, ALL }  # ターゲット攻撃/地点攻撃/自己/全体
enum Shape { SINGLE, LINE, CROSS, BOX, ROW, COLUMN, ALL }  # 単マス/直線/十字/N×N/行/列/全体
enum ParryKind { ATTACK, SKILL }  # この攻撃を受けるパリィ種別（r=攻撃 / e=スキル・§7）

@export var id: StringName
@export var display_name: String
@export var target_type: TargetType = TargetType.TARGET
@export var range: int = 1          # 射程（マス）。使用者から届く距離
@export var shape: Shape = Shape.SINGLE
@export var shape_size: int = 1     # 直線N / 範囲N×N の N（今スライスは SINGLE のみ運用）
@export var needs_direction: bool = false
@export var cast_time: float = 0.0  # 0=即時。>0 は詠唱中を経る（今スライスは0のみ・§5未決定のため）
@export var mana_cost: int = 0
@export var cooltime: float = 0.0
@export var parry_kind: ParryKind = ParryKind.ATTACK  # 通常攻撃=ATTACK(r) / 魔法等=SKILL(e)
@export var effects: Array[SkillEffect] = []


## 向き・対象の指定が要らない（自己/全体）か。
func is_self_or_all() -> bool:
	return target_type == TargetType.SELF or target_type == TargetType.ALL

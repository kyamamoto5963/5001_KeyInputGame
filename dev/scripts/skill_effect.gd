class_name SkillEffect
extends Resource
## スキルの効果1つ（→ ../../docs/11_battle-spec.md §6「効果(effects)」）。
## データ駆動: .tres に埋め込むサブリソース。今スライスは DAMAGE 中心、他は型のみ用意。

enum Type { DAMAGE, HEAL, STUN }

@export var type: Type = Type.DAMAGE
@export var amount: int = 0
@export var duration: float = 0.0  # STUN等の持続（今スライス未使用）

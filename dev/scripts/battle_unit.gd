class_name BattleUnit
extends RefCounted
## 戦闘ユニット1体の戦闘ステータスと FSM 状態（→ ../../docs/11_battle-spec.md §4 アクター状態一覧）。
## 盤面上の位置は BattleGrid 側が unit id で持つ（責務分離）。ここは状態とパラメータだけ。
##
## §0-2 の精神で「取りうる状態は最初に全列挙」する。今スライスで実際に駆動するのは
## WAIT/ACTIVE/FOCUS だけだが、残りも先に列挙して状態×イベント表（§5）と対応づけられる形にする。

enum State {
	WAIT,        # ウェイト: ATB蓄積中
	ACTIVE,      # アクティブ: ATB満了、指示待ち（未フォーカス含む）
	FOCUS,       # フォーカス: 操作中（アクティブのうち1人）
	MOVING,      # 移動中（アニメ）
	CASTING,     # 詠唱中（割り込みに弱い）
	ACTING,      # 発動中（効果適用中）
	RECOVER,     # 硬直
	KNOCKBACK,   # 被吹き飛ばし
	STUN,        # スタン
	DEAD,        # 死亡（戦闘から除外）
}

enum Team { ALLY, ENEMY }

const ATB_FULL := 1.0

var id: int
var display_name: String
var team: Team
var size: Vector2i = Vector2i.ONE  # Phase 0 は 1×1 のみ。構造は最初から持つ。

var atb: float = 0.0               # 0.0 .. ATB_FULL
var atb_speed: float = 0.2         # 1（止まらない）秒あたりの蓄積量。キャラ＋スキル＋装備依存（今は仮値）。
var state: State = State.WAIT

# 戦闘ステータス
var max_hp: int = 30
var hp: int = 30
var max_mana: int = 10
var mana: int = 10
var move_range: int = 3            # 1ターンに動けるマス数（メンバー固有・§2）
var facing: int = 1               # 向き: -1=左 / +1=右（左右のみ・§6）

# 編成: a/s/d/f に割り当てた4スキル（通常攻撃もスキル）。cool は各スロットの残りクールタイム。
var loadout: Array[SkillData] = []
var cool: Array[float] = []

# 敵の性格（敵のみ。味方は null）。→ EnemyAIData / §8
var ai: EnemyAIData = null


func _init(p_id: int, p_name: String, p_team: Team, p_atb_speed: float, p_atb_start: float = 0.0) -> void:
	id = p_id
	display_name = p_name
	team = p_team
	atb_speed = p_atb_speed
	atb = p_atb_start


func set_state(next: State) -> void:
	state = next


## 編成スキルを差す。cool をスロット数ぶん 0 で初期化する。
func equip(skills: Array[SkillData]) -> void:
	loadout = skills
	cool = []
	cool.resize(skills.size())
	cool.fill(0.0)


func is_alive() -> bool:
	return state != State.DEAD


func is_ally() -> bool:
	return team == Team.ALLY

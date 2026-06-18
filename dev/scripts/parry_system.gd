class_name ParrySystem
extends RefCounted
## 音ゲー式パリィ（→ ../../docs/11_battle-spec.md §7 / 06_systems ParrySystem）。コアの快感の本体。
##
## 仕組み: 敵の攻撃は即着弾せず、約1秒の予告（パリィナビ＝縮むわっか）を経て着弾する。
## その予告中に対応キー（r=攻撃 / e=スキル）を「重なる瞬間」に押すとノーダメージ＋見返り。
## 独立リアルタイム（§1.5）。時間は PausableClock の dt 経由なのでポーズで凍結する。
##
## 判定方針（§7）:
## - 1段階のみ（Good/Perfect なし）。窓 ±WINDOW 内に対応種別があれば成功。
## - 同時着弾（窓内に複数）は1押しでまとめて成功。
## - 失敗（タイミング外し・誤キー）は最寄りのチャンスを1つ潰す（連打・先押し防止）。
## - 連続成功でコンボ加算（ドロップ率等へ接続は後続・§8）。

signal attack_parried(inc: Incoming)  # 着弾時: パリィ成功して無効化された
signal attack_hit(inc: Incoming)      # 着弾時: 食らった（damageはBattleManagerが適用）

const TELEGRAPH := 1.0  # 着弾までの予告秒数（§7「約1秒」・要調整）
const WINDOW := 0.12    # 成功判定の片側幅（要調整）

## 飛来中の1攻撃。
class Incoming:
	var caster: BattleUnit
	var target: BattleUnit
	var skill: SkillData
	var kind: int          # SkillData.ParryKind
	var t: float           # 着弾までの残り（TELEGRAPH→0）
	var parried := false
	var disabled := false  # 失敗で潰された＝もうパリィできない（着弾はする）
	var resolved := false

var incoming: Array[Incoming] = []
var combo: int = 0


## 飛来攻撃を1つ登録する（予告開始）。
func spawn(caster: BattleUnit, target: BattleUnit, skill: SkillData, kind: int) -> void:
	var inc := Incoming.new()
	inc.caster = caster
	inc.target = target
	inc.skill = skill
	inc.kind = kind
	inc.t = TELEGRAPH
	incoming.append(inc)


## 時計の dt で予告を進め、着弾したものを解決（emit）する。
func update(dt: float) -> void:
	if dt <= 0.0:
		return
	for inc in incoming:
		if inc.resolved:
			continue
		inc.t -= dt
		if inc.t <= 0.0:
			inc.resolved = true
			if inc.parried:
				attack_parried.emit(inc)
			else:
				attack_hit.emit(inc)
	incoming = incoming.filter(func(i: Incoming) -> bool: return not i.resolved)


## パリィ入力（kind=押した種別）。成功したら true。
func try_parry(kind: int) -> bool:
	# 1) 窓内の同種別をまとめてパリィ（同時着弾対応）。
	var any := false
	for inc in incoming:
		if _parryable(inc) and inc.kind == kind and absf(inc.t) <= WINDOW:
			inc.parried = true
			any = true
	if any:
		combo += 1
		return true
	# 2) 失敗: 最寄りのチャンス（種別問わず）を1つ潰す。コンボ切れ。
	var nearest := _nearest_parryable()
	if nearest != null:
		nearest.disabled = true
	combo = 0
	return false


func _parryable(inc: Incoming) -> bool:
	return not inc.resolved and not inc.disabled and not inc.parried


func _nearest_parryable() -> Incoming:
	var best: Incoming = null
	for inc in incoming:
		if _parryable(inc) and (best == null or inc.t < best.t):
			best = inc
	return best

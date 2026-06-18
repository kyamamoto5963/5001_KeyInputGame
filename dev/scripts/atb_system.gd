class_name ATBSystem
extends RefCounted
## ATB（タイムバー）の蓄積管理（→ ../../docs/11_battle-spec.md §1.5 / 06_systems ATBSystem）。
##
## 責務はひとつ: WAIT のユニットの atb を時計の dt で進め、満了したら ACTIVE にして通知する。
## フォーカスの回り方・敵AI・行動解決は持たない（BattleManager が仲介）。
## 時間は必ず PausableClock 経由の dt で受け取る（生 delta を見ない＝ポーズで一括停止）。

signal unit_became_active(unit: BattleUnit)

const PASS_RESTART := 0.2  # スキル未使用で行動終了したとき、次ATBは20%から再開（§1.5）

var _units: Array[BattleUnit] = []


func add_unit(unit: BattleUnit) -> void:
	if unit not in _units:
		_units.append(unit)


func remove_unit(unit: BattleUnit) -> void:
	_units.erase(unit)


## 時計の dt（ポーズ中は 0.0）で全ユニットの ATB を進める。
func advance(dt: float) -> void:
	if dt <= 0.0:
		return
	for unit in _units:
		if unit.state != BattleUnit.State.WAIT:
			continue  # アクティブ/行動中/死亡などは蓄積しない
		unit.atb = minf(BattleUnit.ATB_FULL, unit.atb + unit.atb_speed * dt)
		if unit.atb >= BattleUnit.ATB_FULL:
			unit.atb = BattleUnit.ATB_FULL
			unit.set_state(BattleUnit.State.ACTIVE)
			unit_became_active.emit(unit)


## 行動を終えたユニットをウェイトへ戻す。ATB再開位置は終わり方で変わる（§1.5）。
## used_skill: スキルを使った=0%から / 使わず終了(パス)=20%から。
func reset_after_turn(unit: BattleUnit, used_skill: bool) -> void:
	unit.atb = 0.0 if used_skill else PASS_RESTART * BattleUnit.ATB_FULL
	unit.set_state(BattleUnit.State.WAIT)

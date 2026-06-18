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
		if unit.state == BattleUnit.State.RECOVER:
			# 硬直中は ATB を止める（=アクション中は待機）。明けたらウェイトへ。
			unit.recover_left -= dt
			if unit.recover_left <= 0.0:
				unit.recover_left = 0.0
				unit.set_state(BattleUnit.State.WAIT)
			continue
		if unit.state != BattleUnit.State.WAIT:
			continue  # アクティブ/死亡などは蓄積しない
		unit.atb = minf(BattleUnit.ATB_FULL, unit.atb + unit.atb_speed * dt)
		if unit.atb >= BattleUnit.ATB_FULL:
			unit.atb = BattleUnit.ATB_FULL
			unit.set_state(BattleUnit.State.ACTIVE)
			unit_became_active.emit(unit)


## スキルを使ったユニットを硬直（RECOVER）へ。ATBは0でこの間止まり、明けてからWAITで蓄積開始（§1.5）。
## recover_time<=0 なら即WAIT（0%から蓄積）。
func begin_recover(unit: BattleUnit, recover_time: float) -> void:
	unit.atb = 0.0
	unit.recover_total = maxf(0.0, recover_time)
	unit.recover_left = unit.recover_total
	unit.set_state(BattleUnit.State.RECOVER if unit.recover_left > 0.0 else BattleUnit.State.WAIT)


## スキル未使用で終了（パス）したユニットをウェイトへ。硬直なし・次ATBは20%から（§1.5）。
func reset_pass(unit: BattleUnit) -> void:
	unit.atb = PASS_RESTART * BattleUnit.ATB_FULL
	unit.recover_left = 0.0
	unit.recover_total = 0.0
	unit.set_state(BattleUnit.State.WAIT)

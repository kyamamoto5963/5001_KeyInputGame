class_name SkillSystem
extends RefCounted
## スキルの解決（→ ../../docs/06_systems.md SkillSystem / 11_battle-spec.md §6）。
## 使用可否（クールタイム・マナ・射程・対象成立）の判定と、効果の適用を担う。
## 盤面・ユニットは引数で受け取り、状態は持たない（BattleManager が仲介）。
##
## 今スライスの範囲: 単体ターゲットの DAMAGE/HEAL。shape は SINGLE のみ、cast_time=0 のみ。
## 範囲(shape)/詠唱/吹き飛ばし/状態異常/床生成は後続スライス。

const NO_SLOT := -1


## 各ユニットの各スロットのクールタイムを時計の dt で減らす。
func tick_cooltimes(units: Array[BattleUnit], dt: float) -> void:
	if dt <= 0.0:
		return
	for unit in units:
		for i in unit.cool.size():
			if unit.cool[i] > 0.0:
				unit.cool[i] = maxf(0.0, unit.cool[i] - dt)


func slot_skill(unit: BattleUnit, slot: int) -> SkillData:
	if slot < 0 or slot >= unit.loadout.size():
		return null
	return unit.loadout[slot]


## そのスロットのスキルが今使えるか（クールタイム0・マナ足りる・有効対象あり）。
func is_usable(unit: BattleUnit, slot: int, units: Array[BattleUnit], grid: BattleGrid) -> bool:
	var skill := slot_skill(unit, slot)
	if skill == null:
		return false
	if unit.cool[slot] > 0.0:
		return false
	if unit.mana < skill.mana_cost:
		return false
	if skill.is_self_or_all():
		return true
	return not valid_targets(unit, skill, units, grid).is_empty()


## 射程内の有効な対象ユニット一覧（ダメージ系は敵のみ＝フレンドリーファイア無し）。
func valid_targets(caster: BattleUnit, skill: SkillData, units: Array[BattleUnit], grid: BattleGrid) -> Array[BattleUnit]:
	var out: Array[BattleUnit] = []
	var origin := grid.get_origin(caster.id)
	for unit in units:
		if not unit.is_alive() or unit == caster:
			continue
		if unit.team == caster.team:
			continue  # 味方は対象外（FF無し）
		if _grid_distance(origin, grid.get_origin(unit.id)) <= skill.range:
			out.append(unit)
	return out


## スキルを実行し、結果（倒した対象など）を返す。target は自己/全体なら null。
func execute(caster: BattleUnit, slot: int, target: BattleUnit, units: Array[BattleUnit], grid: BattleGrid) -> Dictionary:
	var skill := slot_skill(caster, slot)
	var result := {"killed": []}
	# 向きを対象側へ自動で合わせる（左右のみ）。
	if target != null:
		var dx := grid.get_origin(target.id).x - grid.get_origin(caster.id).x
		if dx != 0:
			caster.facing = 1 if dx > 0 else -1
	for eff in skill.effects:
		_apply_effect(eff, caster, target, grid, result)
	caster.mana -= skill.mana_cost
	caster.cool[slot] = skill.cooltime
	return result


func _apply_effect(eff: SkillEffect, caster: BattleUnit, target: BattleUnit, grid: BattleGrid, result: Dictionary) -> void:
	match eff.type:
		SkillEffect.Type.DAMAGE:
			if target != null and target.is_alive():
				target.hp = maxi(0, target.hp - eff.amount)
				if target.hp == 0:
					target.set_state(BattleUnit.State.DEAD)
					grid.remove_unit(target.id)  # マスを空ける
					result["killed"].append(target)
		SkillEffect.Type.HEAL:
			var who := target if target != null else caster
			who.hp = mini(who.max_hp, who.hp + eff.amount)
		SkillEffect.Type.STUN:
			pass  # 今スライス未対応（構造のみ／§5 状態×イベントを埋めてから）


func _grid_distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))  # チェビシェフ距離（盤上のマス距離）

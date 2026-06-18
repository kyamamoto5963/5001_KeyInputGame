class_name EnemyAI
extends RefCounted
## 敵1体の1ターンを完結させる実行器（→ ../../docs/11_battle-spec.md §8）。
## ATB満了の瞬間に take_turn が1回呼ばれるだけ（毎フレームでない＝ほぼタダ）。
##
## 手順（§8「使えるスキル」とフォールバック）:
##  1) 今そのまま使えるスキルがあれば使う。
##  2) 無ければ性格の fallback（接近/距離取り/パス）。接近して射程に入ったら撃つ。
##  3) それでも撃てなければパス。
## 戻り値: スキルを使ったか（true=ATB0% / false=パス20%）。

func take_turn(unit: BattleUnit, units: Array[BattleUnit], grid: BattleGrid, skill: SkillSystem, rng: RandomNumberGenerator) -> bool:
	var data := unit.ai
	if data == null:
		return false  # AI未設定 → パス

	if _try_attack(unit, units, grid, skill, data, rng):
		return true

	match data.fallback_policy:
		EnemyAIData.FallbackPolicy.APPROACH:
			_approach(unit, units, grid)
		EnemyAIData.FallbackPolicy.RETREAT:
			_retreat(unit, units, grid)
		EnemyAIData.FallbackPolicy.PASS:
			pass

	# 移動して射程に入ったら撃つ。
	return _try_attack(unit, units, grid, skill, data, rng)


# --- 攻撃 ---------------------------------------------------------------
func _try_attack(unit: BattleUnit, units: Array[BattleUnit], grid: BattleGrid, skill: SkillSystem, data: EnemyAIData, rng: RandomNumberGenerator) -> bool:
	var slot := _pick_usable_slot(unit, units, grid, skill, rng)
	if slot == SkillSystem.NO_SLOT:
		return false
	var sdata := skill.slot_skill(unit, slot)
	var target := _pick_target(unit, sdata, units, grid, skill, data, rng)
	if target == null:
		return false
	skill.execute(unit, slot, target, units, grid)
	return true


func _pick_usable_slot(unit: BattleUnit, units: Array[BattleUnit], grid: BattleGrid, skill: SkillSystem, rng: RandomNumberGenerator) -> int:
	var usable: Array[int] = []
	for i in unit.loadout.size():
		if skill.is_usable(unit, i, units, grid):
			usable.append(i)
	if usable.is_empty():
		return SkillSystem.NO_SLOT
	return usable[rng.randi_range(0, usable.size() - 1)]  # 今は一様抽選（重みは後続）


func _pick_target(unit: BattleUnit, sdata: SkillData, units: Array[BattleUnit], grid: BattleGrid, skill: SkillSystem, data: EnemyAIData, rng: RandomNumberGenerator) -> BattleUnit:
	var cands := skill.valid_targets(unit, sdata, units, grid)
	if cands.is_empty():
		return null
	match data.target_policy:
		EnemyAIData.TargetPolicy.NEAREST:
			return _closest(unit, cands, grid)
		EnemyAIData.TargetPolicy.WEAKEST:
			var best := cands[0]
			for c in cands:
				if c.hp < best.hp:
					best = c
			return best
		EnemyAIData.TargetPolicy.RANDOM:
			return cands[rng.randi_range(0, cands.size() - 1)]
		EnemyAIData.TargetPolicy.FOCUS:
			for c in cands:
				if c.state == BattleUnit.State.FOCUS:
					return c
			return _closest(unit, cands, grid)  # フォーカスが射程外なら最寄り
	return cands[0]


# --- 移動（接近/距離取り） ----------------------------------------------
func _approach(unit: BattleUnit, units: Array[BattleUnit], grid: BattleGrid) -> void:
	var target := _nearest_opposing(unit, units, grid)
	if target == null:
		return
	var steps := unit.move_range
	while steps > 0:
		var cur := grid.get_origin(unit.id)
		var tpos := grid.get_origin(target.id)
		if _dist(cur, tpos) <= 1:
			break  # 近接想定: 隣接で十分
		var dir := _step_toward(cur, tpos, unit, grid)
		if dir == Vector2i.ZERO:
			break  # 動けない
		grid.place_unit(unit.id, cur + dir, unit.size)
		steps -= 1


func _retreat(unit: BattleUnit, units: Array[BattleUnit], grid: BattleGrid) -> void:
	var target := _nearest_opposing(unit, units, grid)
	if target == null:
		return
	var steps := unit.move_range
	while steps > 0:
		var cur := grid.get_origin(unit.id)
		var tpos := grid.get_origin(target.id)
		var dir := _step_away(cur, tpos, unit, grid)
		if dir == Vector2i.ZERO:
			break
		grid.place_unit(unit.id, cur + dir, unit.size)
		steps -= 1


## 対象へ1歩近づく向き（ギャップの大きい軸を優先、空きマスのみ）。無ければ ZERO。
func _step_toward(cur: Vector2i, tpos: Vector2i, unit: BattleUnit, grid: BattleGrid) -> Vector2i:
	for dir in _axis_order(tpos - cur):
		if grid.can_place(cur + dir, unit.size, unit.id):
			return dir
	return Vector2i.ZERO


## 対象から1歩遠ざかる向き。
func _step_away(cur: Vector2i, tpos: Vector2i, unit: BattleUnit, grid: BattleGrid) -> Vector2i:
	for dir in _axis_order(tpos - cur):
		var away := -dir
		if grid.can_place(cur + away, unit.size, unit.id):
			return away
	return Vector2i.ZERO


## diff の符号から、ギャップの大きい軸を先にした候補向き（最大2つ）。
func _axis_order(diff: Vector2i) -> Array[Vector2i]:
	var hor := Vector2i(signi(diff.x), 0)
	var ver := Vector2i(0, signi(diff.y))
	var order: Array[Vector2i] = []
	if absi(diff.x) >= absi(diff.y):
		if diff.x != 0: order.append(hor)
		if diff.y != 0: order.append(ver)
	else:
		if diff.y != 0: order.append(ver)
		if diff.x != 0: order.append(hor)
	return order


# --- 探索ヘルパ ---------------------------------------------------------
func _nearest_opposing(unit: BattleUnit, units: Array[BattleUnit], grid: BattleGrid) -> BattleUnit:
	var opposing: Array[BattleUnit] = []
	for u in units:
		if u.is_alive() and u.team != unit.team:
			opposing.append(u)
	return _closest(unit, opposing, grid)


func _closest(unit: BattleUnit, cands: Array[BattleUnit], grid: BattleGrid) -> BattleUnit:
	if cands.is_empty():
		return null
	var origin := grid.get_origin(unit.id)
	var best := cands[0]
	var best_d := _dist(origin, grid.get_origin(best.id))
	for c in cands:
		var d := _dist(origin, grid.get_origin(c.id))
		if d < best_d:
			best_d = d
			best = c
	return best


func _dist(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))  # チェビシェフ距離

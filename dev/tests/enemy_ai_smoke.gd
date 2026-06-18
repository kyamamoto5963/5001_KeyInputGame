extends SceneTree
## 敵AIのスモークテスト（ヘッドレス）。
##   実行: Godot --headless --path dev --script res://tests/enemy_ai_smoke.gd
## 検証: 射程外の敵が接近(APPROACH)して最寄り(NEAREST)の味方を攻撃 → 味方が削れる →
##       味方全滅で敗北(ENDING・victory=false)。スキル/AIはコードで作って決定論的に。

var _fail := 0


func _initialize() -> void:
	var mgr := BattleManager.new()
	mgr.rng.seed = 12345  # 決定論

	# 味方: 攻撃手段なし・遅い（テスト中はほぼ動かない）。
	var ally := BattleUnit.new(0, "ally", BattleUnit.Team.ALLY, 0.001)
	ally.max_hp = 20; ally.hp = 20; ally.move_range = 0

	# 敵: 体当たり(range1, dmg9, cool0.3)・接近/最寄り・速い。
	var enemy := BattleUnit.new(1, "enemy", BattleUnit.Team.ENEMY, 1.0)
	enemy.max_hp = 30; enemy.hp = 30; enemy.move_range = 5
	enemy.equip([_tackle(9, 1, 0.3)] as Array[SkillData])
	enemy.ai = _ai(EnemyAIData.TargetPolicy.NEAREST, EnemyAIData.FallbackPolicy.APPROACH)

	mgr.add_unit(ally, Vector2i(0, 0))
	mgr.add_unit(enemy, Vector2i(6, 0))

	# 最初の敵ターンまで（atb満了1.0s）進める。接近して隣接するはず。
	_run(mgr, 1.05, 0.05)
	var ex := mgr.grid.get_origin(1).x
	_check(ex < 6, "敵が味方へ接近した（x=%d < 6）" % ex)
	_check(mgr.grid.get_origin(1) != Vector2i(0, 0), "味方マスには重ならない")

	# 敵の攻撃はパリィ予告（約1秒）を経て着弾する。パリィしなければダメージが入る。
	_run(mgr, 1.2, 0.05)
	_check(ally.hp < 20, "予告を経て攻撃が着弾しHPが減る（hp=%d）" % ally.hp)

	# 味方全滅まで進める → 敗北で凍結（予告ぶん時間がかかるので余裕を見る）。
	_run(mgr, 16.0, 0.05)
	_check(not ally.is_alive(), "味方が倒れる")
	_check(mgr.progress == BattleManager.Progress.ENDING and not mgr.victory, "敗北でENDING（victory=false）")

	if _fail == 0:
		print("enemy AI smoke test: ALL PASS")
	else:
		print("enemy AI smoke test: %d FAILED" % _fail)
	quit(0 if _fail == 0 else 1)


func _tackle(dmg: int, reach: int, cool: float) -> SkillData:
	var s := SkillData.new()
	s.id = "tackle"
	s.display_name = "tackle"
	s.target_type = SkillData.TargetType.TARGET
	s.range = reach
	s.mana_cost = 0
	s.cooltime = cool
	var e := SkillEffect.new()
	e.type = SkillEffect.Type.DAMAGE
	e.amount = dmg
	var arr: Array[SkillEffect] = [e]
	s.effects = arr
	return s


func _ai(tp: EnemyAIData.TargetPolicy, fp: EnemyAIData.FallbackPolicy) -> EnemyAIData:
	var a := EnemyAIData.new()
	a.target_policy = tp
	a.fallback_policy = fp
	return a


func _run(mgr: BattleManager, total: float, dt: float) -> void:
	var t := 0.0
	while t < total - 1e-6:
		mgr.process(dt)
		t += dt


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok  : ", msg)
	else:
		print("  FAIL: ", msg)
		_fail += 1

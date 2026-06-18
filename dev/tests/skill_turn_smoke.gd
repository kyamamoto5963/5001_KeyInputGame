extends SceneTree
## スキル＋ターン入力フローのスモークテスト（ヘッドレス）。
##   実行: Godot --headless --path dev --script res://tests/skill_turn_smoke.gd
## 検証: 射程外で不可 → 移動量消費 → スキル選択→ターゲット確定→ダメージ →
##       スキル使用でATB0% → クールタイム経過 → 撃破 → 勝利(ENDING)。
## スキルは .tres に依存せずコードで作る（数値を固定して決定論的に）。

var _fail := 0


func _initialize() -> void:
	var mgr := BattleManager.new()

	var ally := BattleUnit.new(0, "ally", BattleUnit.Team.ALLY, 1.0)  # 満了1.0s
	ally.max_hp = 30; ally.hp = 30; ally.max_mana = 10; ally.mana = 10; ally.move_range = 5
	ally.equip([_slash(12, 1, 0, 0.5)] as Array[SkillData])

	var enemy := BattleUnit.new(1, "enemy", BattleUnit.Team.ENEMY, 0.001)  # ほぼ動かない
	enemy.max_hp = 20; enemy.hp = 20

	mgr.add_unit(ally, Vector2i(0, 0))
	mgr.add_unit(enemy, Vector2i(3, 0))

	# 味方がフォーカスされるまで進める。
	_run(mgr, 1.1, 0.05)
	_check(mgr.focus == ally, "味方がフォーカスになる")
	_check(mgr.turn_phase == BattleManager.TurnPhase.COMMAND, "コマンドフェーズで開始")
	_check(mgr.move_left == 5, "残移動 = move_range")

	# 射程外（距離3 > range1）ではスキル選択できない。
	_check(not mgr.select_skill(0), "射程外はスキル選択不可")
	_check(mgr.turn_phase == BattleManager.TurnPhase.COMMAND, "コマンドのまま")

	# 隣接まで移動（移動量を消費）。
	_check(mgr.move_focus(Vector2i(1, 0)) and mgr.move_focus(Vector2i(1, 0)), "右へ2マス移動")
	_check(mgr.grid.get_origin(0) == Vector2i(2, 0), "(2,0)に居る")
	_check(mgr.move_left == 3, "残移動が2減る")
	_check(not mgr.move_focus(Vector2i(1, 0)), "敵の居るマスには入れない")

	# スキル選択 → ターゲット → 確定でダメージ。
	_check(mgr.select_skill(0), "射程内でスキル選択→ターゲット")
	_check(mgr.turn_phase == BattleManager.TurnPhase.TARGETING and mgr.targets.size() == 1, "対象候補1体")
	mgr.confirm_target()
	_check(enemy.hp == 8, "ダメージ適用 20-12=8")
	_check(ally.state == BattleUnit.State.WAIT and is_equal_approx(ally.atb, 0.0), "スキル使用→ATB0%でウェイト")
	_check(ally.cool[0] > 0.0, "クールタイムが入る")

	# クールタイム経過＋再蓄積でフォーカスが戻り、2撃目で撃破→勝利。
	_run(mgr, 1.1, 0.05)
	_check(mgr.focus == ally, "再びフォーカス")
	_check(is_equal_approx(ally.cool[0], 0.0), "クールタイムが明けている")
	_check(mgr.select_skill(0), "2撃目を選択")
	mgr.confirm_target()
	_check(not enemy.is_alive(), "敵を撃破")
	_check(mgr.victory and mgr.progress == BattleManager.Progress.ENDING, "勝利でENDINGに凍結")

	if _fail == 0:
		print("skill+turn smoke test: ALL PASS")
	else:
		print("skill+turn smoke test: %d FAILED" % _fail)
	quit(0 if _fail == 0 else 1)


func _slash(dmg: int, reach: int, mana: int, cool: float) -> SkillData:
	var s := SkillData.new()
	s.id = "slash"
	s.display_name = "slash"
	s.target_type = SkillData.TargetType.TARGET
	s.range = reach
	s.mana_cost = mana
	s.cooltime = cool
	var e := SkillEffect.new()
	e.type = SkillEffect.Type.DAMAGE
	e.amount = dmg
	var arr: Array[SkillEffect] = [e]
	s.effects = arr
	return s


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

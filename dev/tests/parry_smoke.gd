extends SceneTree
## パリィのスモークテスト（ヘッドレス）。
##   実行: Godot --headless --path dev --script res://tests/parry_smoke.gd
## 検証: 窓内パリィ成功=ノーダメージ＋マナ見返り＋コンボ加算 / 誤キー=失敗で最寄りチャンス
##       を潰し着弾（ダメージ）/ 先押し（窓外）=失敗。飛来攻撃は直接 spawn して決定論的に。

const ATTACK := SkillData.ParryKind.ATTACK
const SKILL := SkillData.ParryKind.SKILL

var _fail := 0


func _initialize() -> void:
	var mgr := BattleManager.new()
	var ally := BattleUnit.new(0, "ally", BattleUnit.Team.ALLY, 0.01)
	ally.max_hp = 30; ally.hp = 30; ally.max_mana = 10; ally.mana = 5
	var enemy := BattleUnit.new(1, "enemy", BattleUnit.Team.ENEMY, 0.01)  # AI/編成なし＝勝手に攻撃しない
	mgr.add_unit(ally, Vector2i(0, 0))
	mgr.add_unit(enemy, Vector2i(1, 0))

	var tackle := _tackle(9)

	# 1) 窓内で対応キー → 成功（ノーダメージ＋マナ+2＋コンボ）。
	mgr.parry.spawn(enemy, ally, tackle, ATTACK)
	mgr.parry.incoming[0].t = 0.05  # 窓 WINDOW=0.12 内
	_check(mgr.try_parry(ATTACK), "窓内の攻撃パリィは成功")
	_check(mgr.parry.combo == 1, "コンボ1")
	_run(mgr, 0.15, 0.05)  # 着弾を解決
	_check(ally.hp == 30, "パリィ成功＝ノーダメージ")
	_check(ally.mana == 7, "見返りでマナ+2")
	_check(mgr.parry.incoming.is_empty(), "解決済みは消える")

	# 2) 連続成功でコンボが伸びる。
	mgr.parry.spawn(enemy, ally, tackle, ATTACK)
	mgr.parry.incoming[0].t = 0.05
	_check(mgr.try_parry(ATTACK), "2回目も成功")
	_check(mgr.parry.combo == 2, "コンボ2")
	_run(mgr, 0.15, 0.05)

	# 3) 誤キー（攻撃にスキルパリィ）→ 失敗。最寄りチャンスを潰しコンボ切れ→着弾でダメージ。
	mgr.parry.spawn(enemy, ally, tackle, ATTACK)
	var inc := mgr.parry.incoming[0]
	inc.t = 0.05
	_check(not mgr.try_parry(SKILL), "誤キー（種別違い）は失敗")
	_check(inc.disabled, "最寄りのパリィチャンスが潰れる")
	_check(mgr.parry.combo == 0, "コンボが切れる")
	_run(mgr, 0.15, 0.05)
	_check(ally.hp == 21, "潰れた攻撃は着弾（30-9）")

	# 4) 先押し（窓外）→ 失敗。次の一発が取れなくなる。
	mgr.parry.spawn(enemy, ally, tackle, ATTACK)
	var inc2 := mgr.parry.incoming[0]
	inc2.t = 0.5  # 窓外
	_check(not mgr.try_parry(ATTACK), "先押し（窓外）は失敗")
	_check(inc2.disabled, "先押しでも最寄りチャンスを消費")

	if _fail == 0:
		print("parry smoke test: ALL PASS")
	else:
		print("parry smoke test: %d FAILED" % _fail)
	quit(0 if _fail == 0 else 1)


func _tackle(dmg: int) -> SkillData:
	var s := SkillData.new()
	s.id = "tackle"
	s.display_name = "tackle"
	s.target_type = SkillData.TargetType.TARGET
	s.range = 1
	s.parry_kind = ATTACK
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

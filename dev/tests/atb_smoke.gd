extends SceneTree
## ATB素体のスモークテスト（ヘッドレス実行）。
##   実行: Godot --headless --path dev --script res://tests/atb_smoke.gd
## 目的: FSM の中核遷移（ウェイト→アクティブ→フォーカス、パス→20%、ポーズ凍結、
##       敵の即パス）が壊れていないかを GUI なしで素早く確かめる。
## ※ 状態×イベントの網羅テストは機能追加に合わせて足す（→ docs/11_battle-spec.md §5）。

var _fail := 0


func _initialize() -> void:
	var mgr := BattleManager.new()
	var ally := BattleUnit.new(0, "ally", BattleUnit.Team.ALLY, 1.0)   # 満了 1.0s
	var enemy := BattleUnit.new(1, "enemy", BattleUnit.Team.ENEMY, 2.0) # 満了 0.5s
	mgr.add_unit(ally, Vector2i(0, 0))
	mgr.add_unit(enemy, Vector2i(9, 0))

	# 0.6s 経過: 敵は一度満了→即パスでウェイトへ。味方はまだ蓄積中。
	_run(mgr, 0.6, 0.1)
	_check(enemy.state == BattleUnit.State.WAIT, "敵はアクティブ化後 即パスでウェイトに戻る")
	_check(ally.state == BattleUnit.State.WAIT, "味方は0.6sではまだウェイト")

	# さらに進めて味方が満了→アクティブ→自動フォーカス。
	_run(mgr, 0.6, 0.1)
	_check(ally.state == BattleUnit.State.FOCUS, "味方が満了してフォーカスになる")
	_check(mgr.focus == ally, "BattleManager.focus が味方を指す")

	# フォーカス中ユニットを移動できる。
	var moved := mgr.move_focus(Vector2i(1, 0))
	_check(moved and mgr.grid.get_origin(0) == Vector2i(1, 0), "フォーカス中ユニットが1マス移動")

	# ポーズ中は時計が凍結し、入力（行動終了）も効かない。
	var atb_before := ally.atb
	mgr.toggle_pause()
	_run(mgr, 0.5, 0.1)
	_check(mgr.progress == BattleManager.Progress.PAUSED, "ポーズで進行状態がPAUSED")
	_check(is_equal_approx(ally.atb, atb_before), "ポーズ中はATBが進まない")
	mgr.end_turn()
	_check(ally.state == BattleUnit.State.FOCUS, "ポーズ中の行動終了は無視される")

	# 再開して行動終了（パス）→ ウェイト、ATBは20%から。
	mgr.toggle_pause()
	mgr.end_turn()
	_check(ally.state == BattleUnit.State.WAIT, "行動終了でウェイトへ")
	_check(is_equal_approx(ally.atb, 0.2), "スキル未使用のパスは次ATB20%スタート")

	if _fail == 0:
		print("ATB smoke test: ALL PASS")
	else:
		print("ATB smoke test: %d FAILED" % _fail)
	quit(0 if _fail == 0 else 1)


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

extends SceneTree
## 敵の性格(EnemyAIData)の .tres を生成する（データ駆動の正本）。
##   実行: Godot --headless --path dev --script res://tools/gen_enemies.gd
## エディタを使うまではこの生成器が出どころ。生成物（data/ai/*.tres）はコミットする。

const OUT_DIR := "res://data/ai/"


func _initialize() -> void:
	var d := DirAccess.open("res://")
	d.make_dir_recursive("data/ai")

	# 雑魚: 最寄りを狙い、射程外なら接近する素直な近接。
	var zako := EnemyAIData.new()
	zako.target_policy = EnemyAIData.TargetPolicy.NEAREST
	zako.fallback_policy = EnemyAIData.FallbackPolicy.APPROACH

	var err := ResourceSaver.save(zako, OUT_DIR + "zako.tres")
	if err != OK:
		push_error("save failed: zako.tres (err %d)" % err)
	else:
		print("saved: ", OUT_DIR + "zako.tres")
	quit()

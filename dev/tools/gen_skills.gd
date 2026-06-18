extends SceneTree
## スキルの .tres を生成する（データ駆動の正本：エディタを使うまではこの生成器が出どころ）。
##   実行: Godot --headless --path dev --script res://tools/gen_skills.gd
## ResourceSaver で書くので .tres の書式ミスが出ない。生成物（data/skills/*.tres）はコミットする。

const OUT_DIR := "res://data/skills/"


func _initialize() -> void:
	var d := DirAccess.open("res://")
	d.make_dir_recursive("data/skills")

	var skills := [
		_mk("slash", "斬りつけ", 1, 0, 1.0, 12),
		_mk("helm_split", "兜割", 1, 3, 4.0, 22),
		_mk("staff", "杖打ち", 1, 0, 1.0, 8),
		_mk("fireball", "ファイアボール", 3, 4, 3.0, 18),
	]
	for s in skills:
		var path: String = OUT_DIR + String(s.id) + ".tres"
		var err := ResourceSaver.save(s, path)
		if err != OK:
			push_error("save failed: %s (err %d)" % [path, err])
		else:
			print("saved: ", path)
	quit()


func _mk(id: String, disp: String, reach: int, mana: int, cool: float, dmg: int) -> SkillData:
	var s := SkillData.new()
	s.id = id
	s.display_name = disp
	s.target_type = SkillData.TargetType.TARGET
	s.range = reach
	s.shape = SkillData.Shape.SINGLE
	s.mana_cost = mana
	s.cooltime = cool
	var e := SkillEffect.new()
	e.type = SkillEffect.Type.DAMAGE
	e.amount = dmg
	var effs: Array[SkillEffect] = [e]
	s.effects = effs
	return s

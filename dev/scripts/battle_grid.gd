class_name BattleGrid
extends RefCounted
## 戦闘の盤面（横10×縦3 の共有グリッド）の純粋ロジック。描画・入力は持たない。
## → ../../docs/11_battle-spec.md §2 盤面
##
## 設計メモ:
## - 占有はユニットID単位で持つ。位置は左上マス(origin)＋サイズ(footprint)で表す。
## - **キャラサイズは最初から持たせる**（Phase 0 は 1×1 のみ、2×2 は Phase 1 で差す）。
## - 「同じマスには止まれない／通り抜けは可」は位置確定時の判定（is_free）で担保する。

const COLS := 10
const ROWS := 3

# unit_id -> { "origin": Vector2i, "size": Vector2i }
var _units: Dictionary = {}


## グリッド内か（単マス）。
func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < COLS and cell.y >= 0 and cell.y < ROWS


## size のユニットが origin に収まるか（盤外にはみ出さないか）。
func footprint_in_bounds(origin: Vector2i, size: Vector2i = Vector2i.ONE) -> bool:
	return in_bounds(origin) and in_bounds(origin + size - Vector2i.ONE)


## ignore_id を除く占有マス集合。
func _occupied_cells(ignore_id: int = -1) -> Dictionary:
	var occupied: Dictionary = {}
	for id in _units:
		if id == ignore_id:
			continue
		var u: Dictionary = _units[id]
		var origin: Vector2i = u["origin"]
		var size: Vector2i = u["size"]
		for dy in size.y:
			for dx in size.x:
				occupied[origin + Vector2i(dx, dy)] = id
	return occupied


## origin に size のユニットを置けるか（盤内かつ他ユニットと重ならない）。
## ignore_id は「自分自身は無視」（移動時の判定用）。
func can_place(origin: Vector2i, size: Vector2i = Vector2i.ONE, ignore_id: int = -1) -> bool:
	if not footprint_in_bounds(origin, size):
		return false
	var occupied := _occupied_cells(ignore_id)
	for dy in size.y:
		for dx in size.x:
			if occupied.has(origin + Vector2i(dx, dy)):
				return false
	return true


## ユニットを登録/更新する。
func place_unit(unit_id: int, origin: Vector2i, size: Vector2i = Vector2i.ONE) -> void:
	_units[unit_id] = {"origin": origin, "size": size}


func remove_unit(unit_id: int) -> void:
	_units.erase(unit_id)


func has_unit(unit_id: int) -> bool:
	return _units.has(unit_id)


func get_origin(unit_id: int) -> Vector2i:
	return _units[unit_id]["origin"]


func get_size(unit_id: int) -> Vector2i:
	return _units[unit_id]["size"]

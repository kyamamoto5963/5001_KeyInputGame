extends Node
## シーン間共有データの単一窓口（→ ../../docs/06_systems.md / 04_data-save）。
## 今は入力レイアウト設定だけ。編成・進行・選択ノード等は実装フェーズで足す。

const DEFAULT_MOVEMENT_LAYOUT := "jikl"

## 移動キーのレイアウト（"jikl" / "hjkl" / "arrows"）。既定は jikl。
var movement_layout: String = DEFAULT_MOVEMENT_LAYOUT

## 移動レイアウトが変わったら通知（UI が現在の割り当て表示を更新する等）。
signal movement_layout_changed(layout_name: String)


func _ready() -> void:
	# 保存中のレイアウトで InputMap を構築（InputActions は機構、設定はここが持つ）。
	InputActions.setup_all(movement_layout)


## 移動レイアウトを切り替える。未知の名前は無視。
func set_movement_layout(layout_name: String) -> void:
	if not InputActions.LAYOUTS.has(layout_name):
		push_warning("unknown movement layout: %s" % layout_name)
		return
	if layout_name == movement_layout:
		return
	movement_layout = layout_name
	InputActions.apply_movement_layout(layout_name)
	movement_layout_changed.emit(layout_name)

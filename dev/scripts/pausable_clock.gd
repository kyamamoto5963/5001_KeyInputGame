class_name PausableClock
extends RefCounted
## 「止められる時計」を1本だけ通すための器（→ ../../docs/11_battle-spec.md §0-4）。
##
## ATB・クールタイム・パリィナビ・床効果・アニメは **すべてこの時計経由** で進める。
## 生の経過時間（Node._process の delta）を各所で直接見ない＝ポーズで全部まとまって止まる。
##
## 使い方: 毎フレーム tick(real_delta) を1回だけ呼び、戻り値（=止まっていなければ実delta、
## ポーズ中は 0.0）を各システムへ配る。

var paused: bool = false
## 蓄積された「止まらない時間」。ポーズ中は進まない。可視化・ログ・乱数シード等の基準に使える。
var now: float = 0.0


## このフレームに進める時間を返す（ポーズ中は 0.0）。
func tick(real_delta: float) -> float:
	if paused:
		return 0.0
	now += real_delta
	return real_delta


func set_paused(value: bool) -> void:
	paused = value


func toggle() -> void:
	paused = not paused

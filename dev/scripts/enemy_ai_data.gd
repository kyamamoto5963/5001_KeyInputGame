class_name EnemyAIData
extends Resource
## 敵の「性格」（→ ../../docs/11_battle-spec.md §8 敵AI）。データ駆動(.tres)。
## ビヘイビアツリーは使わない。判断は ATB満了の瞬間だけ走る軽量方式。
##
## 今スライスの範囲: 単一フェーズ・使えるスキルから一様抽選・ターゲット方針・フォールバック。
## フェーズ（HP閾値で切替）＋抽選プールの重み＋ワンショットルールは後続で足す（構造は§8に準拠）。

enum TargetPolicy { NEAREST, WEAKEST, RANDOM, FOCUS }   # 最寄り/最弱(HP低)/ランダム/フォーカス狙い
enum FallbackPolicy { APPROACH, RETREAT, PASS }         # 接近/距離取り/パス

@export var target_policy: TargetPolicy = TargetPolicy.NEAREST
@export var fallback_policy: FallbackPolicy = FallbackPolicy.APPROACH

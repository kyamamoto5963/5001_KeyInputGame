# 10 基本思想（正本へのポインタ＋固有の適応）

最終更新: 2026-06-18

横断的な土台思想は**正本**にある。重複させず、ここではこのタイトル固有の適応だけ書く。

- 正本: [5000_GamePhilosohy/philosophy.md](../../5000_GamePhilosohy/philosophy.md)
- 環境（2拠点・git 癖）: [environment.md](../../5000_GamePhilosohy/environment.md)
- 開発者のクセ（コミット＝push 等）: [conventions.md](../../5000_GamePhilosohy/conventions.md)
- 横展開チェンジ: [cross-project-changes.md](../../5000_GamePhilosohy/cross-project-changes.md)

## このタイトル固有の適応

- **コア制約 = 入力デバイスをキーボードに限定**。これがこのタイトルの「個性」であり、
  全設計判断は「キーボードだけで完結するか」を基準に評価する。
- **シンプル基調＋こだわり演出を1つ**: 演出は「入力に呼応する手応え（ヒットストップ等）」を第一候補
  （→ [02_core-loop.md](02_core-loop.md)）。コアが面白くなってから足す。
- **縦スライス優先**: ステージを増やす前に、代表1ステージを一気通貫で遊べる状態にして手触り検証。
- エンジン・拠点依存の値は固定せず、選定・確認のつど docs に記録する。

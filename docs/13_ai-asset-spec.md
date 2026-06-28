# 13_ai-asset-spec.md — AI アセット生成規格（AI Asset Spec）

状態: ドラフト（2026-06-27 起票）

**生成側**の規格。[12_character-rig.md](12_character-rig.md) が「組み立て側（runtime）」なのに対し、本書は
「**AIに渡すだけで同一規格のパーツ／シートが出てくる**」状態を目指す。パーツが数百〜数千に増えても
破綻しない“量産パイプラインの土台”。

> 関係: 12=スケルトン/スロット/anchor/組み立て（正本）。13=ポーズ/ライティング/シート/切り出し/プロンプト（生成）。
> 既存テンプレ: `work/templates/template_body_1024x1536.png` / `template_head_base_1024.png`（→ §7）。

---

## 0. 大方針（一番大事な前提）

- **自由生成して賢く切る、ではない。枠を強制して生成し、機械的に切る。**
  AIはセル位置を守らないので、**グリッド・テンプレを下敷き**（img2img / ControlNet）にして生成 → **グリッドで単純分割** → bbox密着クロップ → anchor自動算出。
- **スケルトンは唯一の基準**（`humanoid_v1`）。全パーツ・全シートがこの関節規格に従う。
- **色替えは tint**（生成しない）。スタイルは**版で固定**（§6）。

---

## 1. 共通規格（全パーツ必須）

| 項目 | 規定 |
|---|---|
| ビュー | **3/4 向かって左向き**（標準。`art_facing=-1` 既定／flip前 char_002 の向き）。作画しやすさ優先 |
| ポーズ | **バインドポーズ**：直立・安静、腕は下げ、肘膝を軽く曲げる。動的ポーズ禁止 |
| ライティング | **均一フラット**。差し込み影／接地影／強いリムライト禁止（動くと破綻） |
| 背景 | **透過**（RGBA）。縁の白ハロー禁止。キー抜き運用なら単色(マゼンタ/緑)可 |
| のりしろ | 関節を**少し越えて**描く（目安：関節径の +8〜12%）。回転時の隙間防止 |
| 画風 | **同一スタイル**（同一LoRA / 固定プロンプト断片 / 固定seed）。版管理は §6 |
| 密度(SS) | **SS=4**（論理256×384 → 1024×1536密度）。頭は拡大テンプレで高精細（→ §3.2） |
| シート最小 | 出力最小 **1256²** 前提。1枚に複数候補（§3） |

---

## 2. スロット別 生成指示（描画範囲・のりしろ）

各スロットは「描く範囲」「のりしろ」を守る。ボーン/z は §12 §2 が正本。

| スロット群 | 描く範囲 | のりしろ | 備考 |
|---|---|---|---|
| `head`（素顔） | ハゲ頭＋肌＋耳＋首stub。**髪は描かない** | 首stubを下に伸ばす | 全顔が頭テンプレに一致（§3.2） |
| `hair_front` | 前髪・顔まわりの房のみ | 生え際で頭に被せる | 透過 |
| `hair_side_l/r` | 左右サイドの房（耳横〜ツインテ/サイドテール） | こめかみ〜耳横で頭に被せる | 透過・任意 |
| `hair_back` | 後ろ髪の塊のみ | 後頭部で被せる | 透過 |
| `hat` | 被り物のみ | 頭頂にフィット | 透過 |
| `upper` | 肩〜腰の上衣。**腕は含めない** | 肩/腰を少し越える | 首穴を開ける |
| `lower` | 腰〜下のスカート/ズボン | 腰を越える | 自然に広げる |
| `arm_upper/_fore` | 肩→肘 / 肘→手首の1節 | 両端を越える | 安静・軽い曲げ |
| `hand` | 手首から先 | 手首で重ねる | 安静の開き手 |
| `leg_thigh/_shin` | 腿/脛の1節 | 両端を越える | |
| `foot` | 足/靴 | 足首で重ねる | 横向き |
| `back`(マント) / `tail` | 1パーツ | 付け根を明確に | 揺れ対象（12 §5.3-jiggle） |
| `weapon` | 武器 | 握り端を明確に | ミラー共用 |

---

## 3. シートレイアウト（量産の核）

### 3.1 グリッド規格
- **固定グリッド** `cols × rows`、セル正方/縦長、外周マージン＋セル間ガター。
- **各セルに registration を敷く**（顔/髪は頭テンプレ、四肢はボーンマーク）。AIはそれに合わせて描く。
- 生成は**グリッド・テンプレを下敷き**に img2img / ControlNet で強制。
- 命名: `<slot>_sheet_<nnn>.png`（例 `hair_front_sheet_001.png`）。
- 例（最小1256²に収める）:
  - **顔/髪/帽子（小物）**: `3×3`（9候補）, セル ~400², ガター24px → 約1256²
  - **腕/脚/手/足**: `4×4` 等、細い縦パーツを密に
  - **上衣/下衣（大物）**: `1〜2/枚`（1024×1536）。詳細優先

### 3.2 頭テンプレの拡大（顔/髪）
- 顔/髪は**拡大した正準ハゲ頭**（`template_head_base`）に合わせて描く＝高精細。
- セル内の**頭ジョイント位置は固定**（全セル同じ）。これにより切り出し後の anchor が自動一致。
- 組込時 `x0.255`（テンプレ頭~690px → 素体頭~176px）で素体へ縮小（→ 12 §3）。

---

## 4. 自動切り出し＋anchor算出（bake）

**入力**: シートPNG＋グリッド定義 `{cols, rows, cell, margin, gutter}`＋スロットの**セル内ジョイント座標** `joint_cell:[x,y]`。

**手順**:
1. グリッドで各セルを切り出す（位置は定義から機械的に）。
2. セル内の中身を **bbox密着クロップ**。
3. `anchor = joint_cell − crop左上`（テンプレ由来＝手置きなし）。
4. `part.png` ＋ `part.json` を出力（スキーマは 12 §3.1）。`gen` も付与（§6）。

> 大物（1枚=1パーツ）は cols=rows=1 の特別ケース。`joint_cell` ＝ そのパーツの関節位置。

---

## 5. プロンプト・テンプレート

### 5.1 共通ポジ（毎回貼る）
```
Single game asset part of ONE consistent character, anime cel-shaded style,
3/4 view facing left, neutral bind pose, isolated on transparent background,
flat even frontal lighting, NO cast shadow, NO ground shadow, NO rim light,
uniform palette, consistent line weight, crisp edges, drawn in resting orientation,
small overlap margin at each joint end. Match the reference sheet exactly.
[character traits / style_vN fragment]
```

### 5.2 スロット別 追記（抜粋）
| slot | 追記 |
|---|---|
| head | `bald head + face only, short neck stub, no hair` |
| hair_front | `front bangs only, fit the reference head, hair only` |
| hair_side_l/r | `side hair lock only (sidelock/twintail base), hair only` |
| hair_back | `back hair mass only, hanging, hair only` |
| upper | `torso garment shoulders→waist, NO arms, neck hole` |
| lower | `skirt/coat-skirt waist down, spread` |
| arm_upper/_fore | `upper arm / forearm segment, hanging, slight bend, overlap both ends` |
| hand | `relaxed hand at wrist, small` |
| leg_*/foot | `thigh/shin segment / boot, overlap at joints` |
| hat / weapon / tail | `headwear / held weapon / tail only, attach end clear` |

### 5.3 ネガ（共通）
```
full body, multiple characters, background, ground, drop shadow, cast shadow,
dramatic lighting, backlight, motion blur, cropped limbs, merged parts,
different art style, inconsistent colors, white halo, watermark, text
```

---

## 6. スタイル版・生成メタ

- **style 版**: `styles/style_v1.md` 等に共通プロンプト断片＋LoRA/seed/モデルを定義。画風を更新したら **`style_v2`** を切る（既存は据置）。
- **生成メタ**: パーツに `gen` を保存（runtimeは無視）。後日「このローブの冬版」「style更新で再生成」が一発。
  ```jsonc
  // part.json（12 §3.1 に gen を追加）
  { "slot":"upper","attach":"chest","anchor":[..],"z":40,
    "gen": { "style":"style_v1", "model":"...", "seed":12345,
             "prompt":"long fantasy robe, gold trim, ...",
             "sheet":"upper_sheet_003.png", "cell":[1,0] } }
  ```

---

## 7. テンプレ資産（生成の下敷き）

| ファイル | 用途 |
|---|---|
| `work/templates/template_body_1024x1536.png` | 素体/装備の関節ガイド（人間向け・ラベル付） |
| `work/templates/template_head_guide_1024.png` | 顔/髪の頭ガイド（人間向け・目線等） |
| `work/templates/template_head_base_1024.png` | **AI下敷き**（クリーンなハゲ頭・透過） |
| （未） `*_sheet_template.png` | **グリッドシート下敷き**（顔用/髪用/四肢用）。§3 で生成予定 |

---

## 8. 確定事項

- 生成は **グリッド強制 → 機械切り出し → anchor自動**（自由生成＋賢い切りはしない）。
- 共通規格（§1）と スロット別（§2）を全生成で遵守。
- **style 版管理**＋**パーツに gen メタ保存**を採用（軽量）。
- 密度 SS=4、頭は拡大テンプレ、シート最小1256²で複数候補。

## 9. 未確定・宿題

- グリッドシート下敷き（顔/髪/四肢）の具体レイアウト確定 → テンプレ生成。
- bake スクリプト実装（グリッド切り＋bboxクロップ＋anchor＋json/gen出力）。
- `styles/style_v1` の中身（確定プロンプト断片・LoRA・seed運用）。
- ControlNet 種別（lineart/pose/depth）の選定と効き。
- キー抜き運用（透過が出ない生成器向け・単色背景→アルファ化）。

## 10. 夢（北極星・今は作らない）

**AI Character Factory**: 「髪20・帽子15・顔10・ローブ8 を生成 → 自動切り出し → anchor自動 → json自動 → Godotへ → 起動したらNPCが増えている」。
本書＋12の規格が揃えば原理的に到達可能。**当面は手動運用で規格を固め、自動化は後**（→ 09_backlog）。

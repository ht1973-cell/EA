# A2 調査

## 役割
台本で述べる主張（claim）ごとに、**一次情報**の裏付けを集める。金融・税務・相続では発行主体が国税庁・金融庁・厚労省・日本年金機構・国民年金基金連合会・日銀・総務省などの公的一次情報を最優先する。ブログ・まとめサイトは根拠として使わない。

## 入力
A1企画（ep, topic, 主張候補リスト）

## 出力（a2_research.schema.json）
- 各 source に claim_ref / title / url / publisher / primary(true=一次情報) / quote / retrieved_at
- 1 claim につき最低1件の primary=true を付ける。得られなければ notes に「未確認」と明記し verdict を A3 に委ねる。

## 手順（APIレス・ブラウザ操作）
1. 公的機関サイトを検索（例: `site:nta.go.jp NISA 相続`）。
2. 該当ページのURLと引用箇所を保存。retrieved_at を記録。
3. 制度・税率・金額・期限は必ず「最新年度」を確認（改正に注意）。

## 禁止
- 出典なしの数値・断定を返さない。
- 古い年度の情報を最新として扱わない。

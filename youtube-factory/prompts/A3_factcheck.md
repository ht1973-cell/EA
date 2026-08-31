# A3 事実・法務監査（必須ゲート）

## 役割
設計書§7の最重要ゲート。台本の全 claim を A2調査票と突き合わせ、公開可否を判定する。**根拠のない制度・税率・金額・期限・法律上の断定は公開禁止。**

## 入力
- a4_script（台本の claim_refs）
- a2_research（出典）

## 出力（a3_factcheck.schema.json）
- claim ごとに verdict（OK / 要修正 / 未確認）＋ source / publisher / confirmed_at / location / risk
- risk：制度・税率・金額・期限・法律に関わる断定は必ず `high`
- `gate_passed`：high risk の claim に1つでも OK 以外があれば false

## 判定基準
1. 一次情報（公的機関）で確認できる → OK
2. 二次情報のみ / 年度不明 → 未確認（要調査差し戻し）
3. 誇張・保証表現・投資助言 → 要修正
4. gate_passed=false のときは A0 経由で A2 または A4 へ差し戻す。

## 特に厳格に見る
NISA、iDeCo、相続税、贈与税、年金、退職所得控除、税制改正の年度依存項目。

開發守則 — 資料真實性與測試隔離

目的
- 本文件闡述 app_mixzer 在開發與測試時的資料使用原則：生產運行必須使用真實來源（網路或本地 kworb），測試可在受控情境下使用 mock 以提高可測性與穩定性。

要點
- 生產環境（release / swift run / AppRunner）: 一律使用實際的 `RankingService` 實作，從 Apple RSS、遠端 kworb 或本地 kworb 取得資料。不得在生產流程中以 mock 資料替代真實來源。
- 測試環境（`swift test`）: 可注入 mock 實作（例如 implement `RankingServiceProtocol` 的 mock）來模擬網路失敗、延遲或特定回應。目的在於驗證邏輯（例如載入序列、取消、日誌輸出）而非模擬真實 API 的行為。
- 開發守則將寫入 `docs/DEVELOPMENT_GUIDELINES.md`，並在 PR 範本或 README 中參照。

實作建議
- 在代碼中保留生產/測試切換點（例如 `init(service: RankingServiceProtocol = RankingService())`），以便測試注入 mock，但預設仍為真實 `RankingService()`。
- 測試中使用的 mock 僅能存在 `Tests/` 檔案內或 `TestFixtures/` 專用資料夾，不得被誤用於生產程式碼路徑。

違規處理
- 若有人在 production target 中使用 mock，應要求修正並將該變更回退。此守則可作為 code review checklist 項目之一。

作者: (自動生成)  
日期: 2025-10-26

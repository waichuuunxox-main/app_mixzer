合併計畫摘要（app_mixzer 與 nested copy）

目標
- 清理工作區中的重複檔案，避免 IDE 與 SPM 使用錯誤的副本，並保留無損備份以便回滾。

發現
- 目前有兩組同名檔案路徑：
  - Canonical: `Sources/app_mixzer/...`（已在 SPM 內且包含最新改動，例如 network timeout/retry、DI、view model 強化）
  - Duplicate: `app_mixzer/Sources/app_mixzer/...`（重複副本，似為舊備份）

合併策略（已執行）
1) 已將 `app_mixzer` 目錄安全封存為 `app_mixzer_ARCHIVE_<timestamp>`（避免直接刪除，保留備份）。
2) 保留 `Sources/app_mixzer` 為 canonical source（SPM 會繼續使用該路徑）。
3) 若未來需要回滾，可在 `app_mixzer_ARCHIVE_<timestamp>` 中取得完整副本。

後續建議
- 若你同意：在一週觀察期後刪除 archive。或在確認沒人依賴後立即移除。
- 在 README 或貢獻指南中補充「單一來源規則（keep a single Sources/... path）」以避免再次發生。

作者: (自動生成)
日期: 2025-10-26

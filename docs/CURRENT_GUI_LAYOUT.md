# CURRENT GUI LAYOUT (唯一版面契約)

此檔案紀錄目前（且唯一）接受的 GUI 佈局細節。未經審核，後續開發不得變更此佈局。

## 主要結構

- 頂層容器：`GeometryReader { geo in HStack(spacing: 0) { ... } }`
- 左側 Pane：`rightPaneView()`（註：檔案內該命名即為 Dashboard / detail 區），固定寬度為 `geo.size.width * 0.35`（即 35%）
- Divider：標準 `Divider()` 在左右 Pane 之間
- 右側 Pane：`sidebarView()`（列表 / master），固定寬度為 `geo.size.width * 0.65`（即 65%）
- HStack 的 spacing 必須為 0；頂層會再套 `.frame(maxWidth: .infinity, maxHeight: .infinity)` 以確保填滿視窗

## 每列（RankingRow）行為

- 每列使用一個命名座標系 `RankingRowCS-<rank>` 以便測量與診斷。
- 每列在 HStack 內最後使用一個透明實體視圖保留尾端空間：
  - `reservedWidth = hoverWidth + trailingStatusWidth`（視 `compact` 狀態改變）
  - 這個實體透明視圖穩定參與佈局，避免系統動態插入 overlay 或 swipe-actions 導致 song info 向右位移。
- 實作同時包含 overlay（.overlay）方式呈現 hover 動作與狀態按鈕，使其不影響主要 HStack 的度量。

## 日誌與診斷

- 每列會在啟動/度量完成時輸出兩類診斷：
  - `DEBUG: RankingRow.layoutProbe ...`（artworkRight / textLeft / delta）
  - `INFO: RowSafety rank=... main.maxX=... trailing.minX=... gap=... safe=true/false`
- `RankingsView` 在 `onAppear` 會寫入一筆固定的 INFO：
  - `INFO: RankingsView.layoutContract -> leftFraction=0.35 rightFraction=0.65 reservedTrailing=hoverWidth+trailingStatusWidth`
  - 目的為：當 App 被 Finder/Dock 啟動時，運維或自動化工具可從 `~/Library/Logs/app_mixzer/apprunner.log` 搜尋此條目以驗證正在執行的 bundle 仍遵守契約。

## 變更流程（必須遵守）

1. 任何想修改此佈局的提案必須開 PR，且在 PR 描述中明確說明變更理由與回退方案。
2. PR 必須包含：
   - 視覺回歸截圖（或錄影）展示變更前後的差異
   - 更新 `docs/CURRENT_GUI_LAYOUT.md`（若契約變動）
   - 執行 `scripts/check_layout_contract.sh`（或 CI 等價檢查）並通過
3. 若需要在程式碼中微調數值（例如由 0.35→0.34），請先在 PR 標題中標註 `LAYOUT-CONTRACT` 並獲得授權 reviewer 批准。

## 自動化檢查（建議）

- 提供了一個簡單檢查腳本 `scripts/check_layout_contract.sh`（位於 repo 根目錄），可在本地或 CI 執行，目的是阻擋最常見的意外編輯（搜尋 0.35 / 0.65 標記與 HStack spacing=0 的字串）。此腳本僅為快速回歸檢查，並非完整靜態保證。

---

若你需要，我可以把此檔加入 CI 檢查（例如在 PR pipeline 中跑此腳本），或新增一個更嚴格的解析器來檢查 Swift 檔 AST 層級的變更。
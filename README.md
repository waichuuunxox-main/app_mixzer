
# app_mixzer

本專案示範一個以 Swift + SwiftUI 撰寫的音樂排行檢視應用（macOS / Swift Package）。

- 資料來源：使用本地 Kworb 摘要（`docs/kworb_top10.json`）作為排行榜來源，並以 iTunes Search API 補足曲目資訊。
- 模組設計說明：請參閱 `docs/MusicRankingLogic.md`（包含資料流、錯誤處理與可擴充建議）。

如何執行（開發者快速參考）：

1. 在專案根目錄執行：

   ```bash
   swift build
   open .build/debug/AppRunner
   ```

2. 日誌檔案（如果啟用）會寫到 `logs/apprunner.log`，也可以在 UI 中開啟「Settings」切換除錯輸出。

若要了解實作細節或擴充建議，請閱讀 `docs/MusicRankingLogic.md`。

輔助腳本與檢查工具

- 本專案已移除對 Python 的依賴，並以 Swift 實作檢查工具與 UI：
  - CLI 可執行目標：`guidelines-check`（可用 `swift run guidelines-check` 執行）。
  - SwiftUI 檢查視圖：位於 `GuidelinesUI` 模組中的 `DocsConsistencyCheckerView`，可在 Xcode 中查看與測試。
- 若需要還原舊的 Python 腳本（例如基於 PyYAML 的舊版檢查器），可從 Git 歷史復原；如需我可以把 legacy 腳本放回 `scripts/legacy/` 並附上說明。

如何執行 Swift 檢查器：

```bash
swift run guidelines-check
```

--
（自動生成/更新，參考文件位於 `docs/`）

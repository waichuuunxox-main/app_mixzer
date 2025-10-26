# 維護歷史 / Changelog

> 本檔記錄使用者可感知的變更與修復，便於回溯、驗證與避免回歸。

## 2025-10-26

修復：啟動時歌曲資訊向右漂移、或回靠時覆蓋到 Artwork 的問題（macOS/SwiftUI 列表）

- 左側固定寬度群組：將「名次 Rank」+「Artwork 圖像」收納為固定寬度的左側群組，明確界定文字起點，杜絕文字入侵或重疊。
- 尾端穩定保留區：保留尾端透明視圖（實體寬度）參與 HStack 佈局；狀態/快捷動作用 overlay 呈現（不參與主佈局），避免佈局抖動。
- 文字對齊與壓縮策略：主文字 VStack 使用 `.frame(maxWidth: .infinity, alignment: .leading)` 並提升 `layoutPriority(1)`，確保在窄寬時先保文字可讀性且穩定靠左。
- 非回歸診斷：維持 `RowSafety` 與 `layoutProbe` 記錄（artworkRight vs textLeft 應為 12pt；main.maxX 與 trailing.minX 之 gap ≥ 12pt 視為 safe），於使用者路徑日誌可觀察。
- 佈署與日誌：
  - 部署腳本強化（zsh null_glob），避免備份清理時出現 glob 錯誤。
  - 日誌鏡射至 `~/Library/Logs/app_mixzer/apprunner.log`，確保 Finder/Dock 啟動時也能觀測。
- Git 噪音清理：新增 `.gitignore` 忽略 `dist/` 與 `logs/`，並移除既有索引追蹤，避免 Source Control 被生成物淹沒。

驗證：

- Build 與測試通過（6/6）。
- Finder/Dock 啟動檢視：歌曲文字固定從 Artwork 右側起始，無重疊；行尾 overlay 顯示穩定；無啟動後的「向右漂移」。

相關提交：

- fix(ui): prevent song info overlapping artwork on startup
- chore(git): ignore build artifacts and logs; stop tracking dist/ and logs/

# VS Code + Xcode 協作開發流程

## 🧠 專案初始化

1. 在 VS Code 中建立 Swift Package 專案：

```bash
swift package init --type executable
```

2. 初始化 Git 專案：

```bash
git init
git add .
git commit -m "Initial commit"
```

3. 建立 `.gitignore` 檔案，排除以下內容：

- `*.xcuserstate`
- `.DS_Store`
- `build/`
- `DerivedData/`

4. Push 至 GitHub（或其他 Git 平台）：

```bash
git remote add origin https://github.com/waichuuunxox-main/app_mixzer.git
git push -u origin main
```

---

## ✍️ VS Code 開發階段（主導端）

1. 使用 GitHub Copilot 撰寫 SwiftUI 畫面與邏輯模組。
2. 所有邏輯、資料模型、功能模組皆在 VS Code 編寫。
3. 使用 Swift Package Manager 管理模組與依賴。
4. Commit & Push 至遠端：

```bash
git add .
git commit -m "Update logic"
git push
```

---

## 🧪 Xcode 測試與發佈階段（輔助端）

1. 使用以下指令匯入 VS Code 專案至 Xcode：

```bash
swift package generate-xcodeproj
open *.xcodeproj
```

2. 在 Xcode 中進行以下操作：

- 加入 `AppDelegate`、`SceneDelegate` 或使用 SwiftUI App 模板
- 設定 `Info.plist`、LaunchScreen、App 圖示
- 使用模擬器預覽 SwiftUI 畫面
- 整合資源檔案（Assets、音效、字型等）

3. 若有修改，請 Commit & Push：

```bash
git add .
git commit -m "Xcode UI & resource updates"
git push
```

---

## 🔄 VS Code 套取 Xcode 更新

1. 在 VS Code 中執行：

```bash
git pull
```

2. 確認更新內容是否包含：

- 新增的 Swift 檔案
- UI 元件邏輯
- App 設定檔案（Info.plist 等）

3. 若有衝突，使用 VS Code Merge 工具解決。

---

## 📦 上架 App Store（僅在 Xcode 進行）

1. 設定 Apple Developer 帳號與簽名憑證。
2. 使用 Product → Archive 建立發佈版本。
3. 使用 Organizer → Distribute App 提交至 App Store Connect。

---

## ✅ 小結建議

- VS Code 為邏輯主體，Xcode 為發佈出口。
- 所有邏輯盡量集中在 VS Code 編寫，避免反向不同步。
- 使用 Git 保持版本一致性，減少手動同步負擔。
- 可建立 Shell Script 自動化 generate + open 流程。

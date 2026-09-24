# ange

macOS 桌面小工具 (WidgetKit), 監看你的 Claude 與 Claude Fable 訂閱用量.

Fork 自 [dependentsign/ClaudeUsageWidget](https://github.com/dependentsign/ClaudeUsageWidget), 已移除 Codex 支援.

![macOS](https://img.shields.io/badge/macOS-15.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.0-orange)
![License](https://img.shields.io/badge/License-MIT-green)

[English](README.md)

<img src="ClaudeUsageWidget/Assets.xcassets/AppIcon.appiconset/icon_256.png" width="96" alt="App 圖示">

## 截圖

![ange 預覽](screenshots/widget-preview-v1.1.png)

*預覽使用範例資料.*

## 功能

- **5 小時 session 用量** + 進度條
- **每週用量** + 進度條
- **Fable 獨立週額度** + 重置時間
- **App 內儀表板** 可手動重新整理
- **重置倒數**
- **顏色隨用量變化** 綠 → 黃 → 橘 → 紅
- **三種尺寸** small, medium, large
- **兩種驗證方式** OAuth token 或 session key
- **自動更新** 每 5 分鐘請求更新, 實際排程由 macOS 決定
- **原創 App 圖示** 隨專案以 MIT 授權提供, 未使用第三方圖示素材

---

## 用 Claude Code 快速安裝

把下面這段貼給你的 Claude Code:

```
幫我 clone 並建置 ange 桌面小工具.

步驟:
1. git clone https://github.com/elbaph/ange.git ~/Documents/ange
2. 建置並打包: cd ~/Documents/ange && ./scripts/build-local.sh
3. 解壓縮 build/ange-1.1.zip, 結束舊版 App 後將 ange.app 複製到 /Applications
4. 開啟 App, 在設定畫面填入我的 Claude OAuth token, 或 session key 與組織 UUID; 已有設定就沿用
5. 按 Save & Refresh
6. 提醒我在桌面按右鍵 → 編輯小工具 → 搜尋 "Claude" 加入
```

---

## 手動安裝

### 1. 建置

```bash
git clone https://github.com/elbaph/ange.git
cd ange
open ClaudeUsageWidget.xcodeproj
```

在 Xcode 中:
- 在兩個 target (ClaudeUsageWidget + ClaudeUsageWidgetExtension) 選擇你的 **Development Team**
- 視需要修改 **Bundle Identifier** (預設為 `io.github.elbaph.ange`)
- 建置並執行 (⌘R)

也可以執行 `./scripts/build-local.sh`, 產生 `build/ange-1.1.zip`. 腳本在暫存目錄建置, 避免 Documents/iCloud 的延伸屬性造成簽章失敗.

### 2. 設定憑證

開啟 App 填寫並儲存, 或自行建立設定檔 `~/.claude/claude-usage-widget.json`. Fable 沿用 Claude 憑證, 不需另外設定:

**方式 A: OAuth Token (建議)**
```json
{
  "oauthToken": "你的-oauth-bearer-token"
}
```

**方式 B: Session Key**
```json
{
  "sessionKey": "sk-ant-sid01-...",
  "organizationId": "你的-org-uuid"
}
```

<details>
<summary>如何取得 session key</summary>

1. 開啟 [claude.ai](https://claude.ai) 並登入
2. 開發者工具 (F12) → Application → Cookies → 複製 `sessionKey`
3. 取得組織 ID:
```bash
curl -s https://claude.ai/api/organizations \
  -H "Cookie: sessionKey=你的KEY" | python3 -m json.tool
```
選擇你正在使用的訂閱組織, 複製它的 **`uuid`** 欄位, 不是數字 `id` 或 `parent_organization_uuid`.

</details>

相容舊版設定; `claudeEnabled` 可開關 Claude, 儲存時會移除舊版 Codex 欄位. 儲存時保留未知欄位, 直接覆寫檔案並將權限設為 `0600`. 因為 sandbox 只開放這個檔案路徑, 所以不使用暫存檔.

### 3. 加入小工具

1. 在桌面按右鍵 → **編輯小工具**
2. 搜尋 **"Claude"**
3. 選擇尺寸並加入

---

## 運作原理

小工具呼叫 Claude 的用量 API:

| 方式 | 端點 |
|------|------|
| OAuth | `GET https://api.anthropic.com/api/oauth/usage` |
| Session Key | `GET https://claude.ai/api/organizations/{orgId}/usage` |

回傳資料:
- `five_hour.utilization` — 5 小時區間用量百分比
- `five_hour.resets_at` — 重置時間戳記
- `seven_day.utilization` — 每週用量百分比
- `seven_day.resets_at` — 每週重置時間戳記
- Fable: 優先讀取 `limits[]` 中 `weekly_scoped` 的 Fable 模型額度, 相容 `seven_day_overage_included` / `seven_day_fable`

百分比代表**已使用**額度. 缺少的資料顯示 `—`, 不視為 0%; 不會自行按 50% 換算 Fable 額度.

先嘗試 OAuth, 再嘗試 session key. 401 提示更新憑證, 403 提示檢查登入與存取權限, 429 提示等待下次更新. 中, 大尺寸顯示重置時間, 大尺寸另顯示更新時間. 訂閱用量 API 可能變動.

---

## 開發

### 專案結構

```
ange/
├── ClaudeUsageWidget/                    # 主 App (儀表板 + 設定)
├── ClaudeUsageWidgetExtension/           # WidgetKit timeline 與進入點
├── Shared/                              # 共用資料模型, 請求與 view
├── Tests/UsageCoreTests/                 # 回歸測試
├── scripts/                             # 建置, 預覽, 圖示產生與 API 檢查
├── artwork/                             # 原創圖示 SVG 與授權說明
└── screenshots/
```

> **注意:** 主 App 與小工具 extension 都在 App Sandbox 中執行, 且沒有 ATS 例外. App 可讀寫, extension 只能讀取 `~/.claude/claude-usage-widget.json` (temporary-exception entitlement). 程式使用 `getpwuid(getuid())` 取得真正的 home 路徑, 因為 `FileManager.default.homeDirectoryForCurrentUser` 在 sandbox 中回傳的是 container 路徑.

### 驗證

```bash
swift test
./scripts/build-local.sh

# 產生三種尺寸 × 深淺色 × 正常/錯誤/缺少資料, 共 18 張 SwiftUI 預覽
mkdir -p build
swiftc Shared/UsageModels.swift Shared/UsageViews.swift scripts/RenderPreviews.swift -o build/render-previews
build/render-previews
```

`CheckLiveUsage.swift` 可選擇用本機憑證做唯讀檢查, 只輸出用量與錯誤. 圖示由 `GenerateAppIcon.swift` 產生, 來源與授權見 [artwork](artwork/README.md).

## 系統需求

- macOS 15.0+
- Xcode 16.0+
- 顯示 Claude 用量: 具用量額度的 Claude 訂閱

## 授權

MIT — 詳見 [LICENSE](LICENSE)

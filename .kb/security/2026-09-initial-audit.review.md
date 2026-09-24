# 2026-09 初次安全審查 (fork 自 dependentsign/ClaudeUsageWidget)

- 日期: 2026-09-24
- 範圍: 基準 commit `98162c5` 的全部原始碼, Xcode 專案設定, entitlements, Info.plist, scripts, 二進位資產
- 目的: 在 macOS 上自行編譯前, 確認有沒有資料外送, 危險相依, 越權檔案存取或提權行為
- 預期用途: 只提供 Claude OAuth token, 透過 Claude API 查詢用量, 並更新桌面 widget

## 結論

沒發現惡意行為. 有幾個設定比這個用途需要的權限更寬, 列在下方.

## 發現

### 對外連線

原始版本只有 3 個 HTTPS 目的地, 都是官方網域, 沒有 telemetry 或 analytics:

| 目的地 | 送出內容 |
|---|---|
| `api.anthropic.com/api/oauth/usage` | `Authorization: Bearer <oauthToken>` |
| `claude.ai/api/organizations/{uuid}/usage` | `Cookie: sessionKey=...` (org ID 會先檢查是否為 UUID) |
| `chatgpt.com/backend-api/wham/usage` | Codex access token 與 account ID (**已移除**) |

### 相依套件

- 沒有 SPM remote package, CocoaPods 或 Carthage. 只連結系統內建的 WidgetKit 與 SwiftUI.
- Xcode 專案沒有 Run Script build phase.
- `scripts/build-local.sh` 只做 xcodebuild, ad-hoc 簽章與 zip 打包.
- PNG 結尾都是正常的 IEND, 沒有夾帶額外資料. 原始碼沒有 bidi 或 zero-width 字元.

### 檔案存取

- 讀寫 `~/.claude/claude-usage-widget.json`. 權限 0600, 寫入方式是先寫暫存檔再改名.
- 原本會自動讀取 `~/.codex/auth.json` (ChatGPT OAuth token), 且預設開啟. **已移除**.
- 不使用 Keychain, 剪貼簿, `Process`, AppleScript 或 `dlopen`.

### 權限

沒有提權: 沒有 sudo, `AuthorizationCreate`, `SMJobBless`, 也沒有 daemon 或 helper.

| 項目 | 狀態 | 風險 |
|---|---|---|
| 主 app `ENABLE_APP_SANDBOX = NO` | 已開 sandbox | 原本主 app 可以讀寫整個家目錄 |
| `NSAllowsArbitraryLoads = YES` (兩個 Info.plist 與 pbxproj) | 已刪除 | 原本關閉 ATS, 但所有連線都是 HTTPS, 用不到 |
| Extension sandbox 的 temporary-exception 唯讀路徑 | 已移除 `/.codex/auth.json` | - |
| Token 以明文存在 `~/.claude/` | 未處理 | 同一個使用者身分下跑的其他工具都讀得到 |

### 來源

- 上游為 `dependentsign/ClaudeUsageWidget`, commit 作者是 huanhuan.
- Bundle ID 原本是上游的 `dev.huan.*`, 已改為 `io.github.elbaph.ange` 與 `io.github.elbaph.ange.WidgetExtension`; app 產物名稱改為 `ange.app`.
- 上游的 Release zip 是 ad-hoc 簽章, 沒有經過公證. 不使用, 一律從原始碼自行編譯.

## 已處理

1. 移除 Codex: client, parser, config 欄位, UI, widget 顯示, entitlements, tests, scripts 與 README.
   - 儲存設定時會刪掉舊版留下的 `codexEnabled`, `codexAccessToken`, `codexAccountId`, 避免 token 殘留在磁碟上.
2. README 的 clone URL 改指向 `elbaph/ange`, 並刪掉上游 Releases 的下載說明. `README_CN.md` 由簡中改為正體中文, 並更名為 `README_ZH.md`.
3. 刪除所有 `NSAllowsArbitraryLoads`.
4. Bundle ID 改為 `io.github.elbaph.*`.
5. 主 app 開啟 sandbox: 新增 `ClaudeUsageWidget/ClaudeUsageWidget.entitlements`, 內容是 app-sandbox, network.client, 以及只開放 `/.claude/claude-usage-widget.json` 讀寫的 home-relative-path 例外.
   - 移除上游設定的 `ENABLE_USER_SELECTED_FILES = readonly`. 以前沒開 sandbox 所以沒作用, 開了 sandbox 後會多出 `files.user-selected.read-only`.
   - Release 設定 `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO`, 避免 Xcode 注入 `get-task-allow`. 有這項權限時, 同一個使用者身分下的程式可以 attach 並讀取記憶體中的 token.
   - 建置後簽章中的 entitlements, 主 app 只有 app-sandbox, network.client, 以及該檔案的 read-write 例外. extension 只有 app-sandbox, network.client, 以及該檔案的 read-only 例外.
   - `WidgetConfig.save` 從「暫存檔 + rename」改成用 `open(O_CREAT|O_TRUNC|O_NOFOLLOW, 0600)` + `fchmod` 直接覆寫. 代價是寫到一半 crash 時設定檔可能損毀, 需要重新儲存一次.

## 待辦

- [x] 刪除 `NSAllowsArbitraryLoads`
- [x] Bundle ID 改成自己的 prefix
- [x] 主 app 開啟 sandbox
- [x] `swift test`: 10/10 通過
- [x] `./scripts/build-local.sh` 建置成功 (universal x86_64 + arm64), `codesign --verify --deep --strict` 通過
- [ ] 實機確認 sandbox 下能正常存檔, 讀取與更新 widget
- [ ] 選做: token 改存 Keychain

## 主 app 開啟 sandbox 的限制 (採用單一檔案例外 + 直接覆寫)

- 主 app 要寫 `~/.claude/claude-usage-widget.json`. 開 sandbox 後需要加 `com.apple.security.temporary-exception.files.home-relative-path.read-write` 與 `com.apple.security.network.client`.
- 目前的 `WidgetConfig.save` 會在 `~/.claude/` 建立暫存檔再 rename. 只開放單一檔案的 exception 不允許這樣做. 要改成直接覆寫該檔, 或把 exception 放寬到整個 `~/.claude/`. 後者不建議, 因為這個目錄也存放 Claude Code 自己的資料.
- 另一個做法是改用 App Group container, 讓 app 與 extension 共用. 但 ad-hoc 簽章沒有 Team ID, macOS 15 以上可能會跳出存取其他 app 資料的提示, 需要實測.

## 驗證

- `swift test` 無法執行: 本機只有 Command Line Tools, 沒有 XCTest. 需要安裝 Xcode.
- `UsageCore` library 可以成功編譯. app 與 extension 做 typecheck 時, 唯一的錯誤是 `@State` 和 `#Preview` 的 macro plugin 需要 Xcode, 沒有其他型別錯誤.
- `scripts/RenderPreviews.swift` 成功產生 18 張預覽圖, 單一 Claude 版面顯示正常.
- Xcode 安裝後, 因為還沒同意授權 (`sudo xcodebuild -license`), `swift test` 與 `/usr/bin/git` 都被擋住.
- 新的 `save()` 另外用 CLT 的 swiftc 寫了臨時腳本驗證, 以下全部通過: 自動建立目錄與檔案, 新檔權限 0600, 既有 0644 會收緊為 0600, 內容變短時完整 truncate, 保留未知欄位並刪除舊版 Codex 欄位, 設定檔格式錯誤時不覆寫, 不跟隨 symlink.

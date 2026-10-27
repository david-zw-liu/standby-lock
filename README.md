# StandbyLock

macOS 待機鎖定工具。按下快捷鍵後整個螢幕被鎖定畫面蓋住，必須輸入事先設定的待機密碼才能繼續操作電腦，鎖定期間同時阻止電腦進入睡眠。

純 AppKit + SwiftPM，沒有第三方依賴，macOS 13 以上可用。

## 功能

- **待機密碼**：首次啟動會要求設定，之後可在選單列變更或移除。密碼以 PBKDF2-HMAC-SHA256（200,000 次、隨機 salt）雜湊後儲存，不保存明文。
- **鎖定畫面**：覆蓋所有螢幕的全螢幕視窗，位於系統最高視窗層級，顯示時間、日期與密碼輸入框。鎖定時隱藏 Dock 與選單列，停用 ⌘Tab 切換程式、強制結束視窗、登出/關機選單與隱藏程式。
- **阻止睡眠**：鎖定期間持有 `PreventUserIdleSystemSleep` 與 `PreventUserIdleDisplaySleep` 兩個 power assertion，解鎖後釋放。可在選單關閉。
- **防猜密碼**：連續輸錯 5 次會暫停輸入 30 秒。
- **全域快捷鍵**：`⌃⌥⌘L` 立即鎖定。
- **閒置自動鎖定**：可選 1 / 3 / 5 / 10 / 30 分鐘無操作後自動鎖定。
- **攔截系統快捷鍵**：鎖定期間吃掉所有帶 ⌘ 或 ⌃ 的按鍵（Spotlight、Mission Control 等）。macOS 要求「輔助使用」權限才能攔截鍵盤事件，首次啟動會跳出授權提示；未授權前鎖定畫面仍可正常使用，選單列會保留「授權輔助使用權限…」項目。
- **登入時自動啟動**：透過 `SMAppService` 註冊，需要 app 放在「應用程式」資料夾。

## 建置

```sh
./build.sh
```

產物在 `build/StandbyLock.app`（release、ad-hoc 簽章）。安裝：

```sh
cp -R build/StandbyLock.app /Applications/
open /Applications/StandbyLock.app
```

啟動後選單列會出現 🔒 圖示，第一次會跳出設定密碼視窗。

要直接啟動並鎖定（例如給 Shortcuts 或腳本用）：

```sh
open /Applications/StandbyLock.app --args --lock
```

## 使用

| 操作 | 方式 |
| --- | --- |
| 鎖定 | `⌃⌥⌘L`，或選單列 → 立即鎖定 |
| 解鎖 | 在鎖定畫面輸入密碼後按 Return |
| 變更 / 移除密碼 | 選單列 → 變更密碼… |
| 結束程式 | 選單列 → 結束 StandbyLock（鎖定中無法結束） |

## 忘記密碼

密碼雜湊存放於 `~/Library/Preferences/com.david.standbylock.plist`。若鎖定中忘記密碼，可從另一台電腦 SSH 進來執行：

```sh
pkill -x StandbyLock
defaults delete com.david.standbylock passwordRecord
```

重新啟動 app 後會要求重新設定密碼。

## 限制

這是應用程式層級的鎖定，不是取代系統登入畫面：

- 其他使用者帳號、SSH、遠端桌面仍可以結束這個程式。
- 長按電源鍵強制關機、合上筆電蓋子仍會讓電腦睡眠（assertion 只能阻止閒置睡眠）。
- 未授予「輔助使用」權限時，Mission Control、Spotlight 等系統快捷鍵仍可觸發，但鎖定視窗會持續蓋在最上層並搶回焦點。ad-hoc 簽章的 app 每次重新 build 後可能需要重新授權。
- 若 macOS 在螢幕喚醒時要求登入密碼，系統登入畫面會出現在鎖定畫面之前，兩者互不影響。

需要安全性等級更高的鎖定，請使用系統內建的「鎖定螢幕」（`⌃⌘Q`）。

## 專案結構

```
Sources/StandbyLock/
  main.swift                   進入點
  AppDelegate.swift            選單列、快捷鍵、設定選單
  LockController.swift         鎖定狀態、視窗管理、防睡眠、閒置偵測
  LockWindow.swift             全螢幕鎖定畫面
  PasswordWindowController.swift  設定 / 變更 / 移除密碼視窗
  PasswordStore.swift          PBKDF2 密碼雜湊儲存
  SleepPreventer.swift         ProcessInfo activity（power assertion）
  KeyboardGuard.swift          CGEventTap 攔截 ⌘ / ⌃ 快捷鍵
  HotKey.swift                 Carbon 全域快捷鍵
  Settings.swift               UserDefaults 偏好
Resources/Info.plist           LSUIElement app 設定
scripts/make-icon.swift        產生 app 圖示
build.sh                       組出 .app
```

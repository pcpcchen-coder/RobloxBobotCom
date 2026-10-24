# PUSHPUSH 發佈作業規範

更新日期：2026-10-24（Asia/Taipei）

**專案擁有者指示：之後更新都沿用本文件這次實際成功的 Publish 路徑。** 本文件優先取代舊 README 中「Publish to Roblox As」的更新步驟。

## 固定目標

| 項目 | 值 |
|---|---|
| 體驗名稱 | PUSHPUSH |
| Universe / Game ID | `10772683522` |
| 起始 Place ID | `106459847310293` |
| 遊玩連結 | https://www.roblox.com/games/106459847310293 |
| 每台伺服器人數 | 2 |
| 版本紀錄 | https://create.roblox.com/dashboard/creations/experiences/10772683522/places/106459847310293/version-history |

這是既有體驗的更新流程；不要為每次更新另建體驗或地點。ID 僅適用本專案，不能套用到其他 Roblox 專案。

## 更新步驟

1. 確認要交付的 Git commit，等待該 commit 的 CI 成功。下載該次 run 的 `RoboPushArena-place` artifact，解壓取得 `RoboPushArena.rbxl`。也可以用同版本來源與鎖定工具鏈重新建置。
2. 用 Studio 開啟該檔案。核對實際載入的檔案路徑、GameConfig 與預期技能數，不要將先前開啟的舊場景誤當最新版本。
3. **Window → Script → Command Bar**，執行以下指令，將本機建置對應至既有體驗：

~~~lua
game:SetPlaceId(106459847310293)
game:SetUniverseId(10772683522)

assert(game.PlaceId == 106459847310293, "Wrong Place ID")
assert(game.GameId == 10772683522, "Wrong Universe ID")

local config = require(game.ReplicatedStorage.Shared.GameConfig)
print("RoboPush release target", game.PlaceId, game.GameId, #config.Skills.Selectable)
~~~

4. 確認 Output 中兩個 ID 正確；目前預期為七項可選技能。指令僅設定本機 DataModel 的目標，**執行指令本身不是發佈完成**。
5. 使用 **File → Publish**（之後可能顯示 **Publish latest version**）。更新時固定走一般 Publish；不要改回 Publish As / Save to Roblox As。
6. 等待 Output 明確顯示 `Published new changes in "PUSHPUSH" to Roblox.`，並記下 publish notes 的版本號。
7. 到後台「版本歷史紀錄」，開啟「只顯示已發佈者」：核對新增版本、時間與已發佈勾選。**只新增儲存版本、對話框消失或沒有報錯，都不足以證明正式發佈成功。**
8. 核對「存取」的訪客上限仍為 **2**；讀回已保存的值。保留既有受眾設定；有變更需求時才調整。
9. 用 Roblox App / 遊戲頁面進入新伺服器做基本冒煙測試。新功能的雙人、手機與延遲驗收仍依 TEST_PLAN 分開記錄，不因 Publish 成功而標 Pass。
10. 回報：程式來源 commit、Roblox 版本號、時間、目標連結、已驗證與未驗證範圍。舊伺服器可能繼續跑前版；需要重啟時先確認在線玩家影響。

**輸入注意：** 本次 UI 自動化曾在逐字輸入 Command Bar 時漏字。使用貼上，執行前讀回完整內容；不要執行被截斷或拼錯的指令。

## 若再次卡在 Upload in progress

1. 先檢查 Output 和後台版本紀錄，分清楚「後台已成功但 UI 卡住」與「尚未產生新發佈版本」，避免無限重送。
2. 取消卡住的操作。
3. 將所有 Roblox Studio 實例關閉，再重新開啟**單一**實例。可在活動監視器確認 Roblox Studio 主程序已退出；正常結束無反應才強制結束。先保存需保留的未儲存工作，不結束其他無關 App。
4. 重新開啟正確建置檔、執行本文件的兩個 ID 設定，使用一般 **Publish**。
5. 若仍失敗，回報具體錯誤與最後成功版本，不將「正在上傳」當作完成。

**本次觀察：** Publish As 與 Save to Roblox As 都曾持續停在 Upload in progress；全部關閉重開後 Publish As 仍重現。設定目標 ID 後改用一般 Publish 成功。這是本環境實測結果，尚不能斷言 Roblox 內部根因。

## 2026-10-24 成功紀錄

| 欄位 | 紀錄 |
|---|---|
| 程式來源 commit | `9a46a959b9234f88cf42ac21caa777b66d0bff04` |
| CI run | https://github.com/pcpcchen-coder/RobloxBobotCom/actions/runs/40075827756 |
| Roblox 正式版本 | **v7** |
| 發佈時間 | **2026-10-24 16:39（Asia/Taipei）** |
| Studio Output | Published new changes in "PUSHPUSH" to Roblox.；Add publish notes to v7 |
| 後台驗證 | 「只顯示已發佈者」清單內有 v7，時間 16:39，已發佈欄有勾選 |
| 技能設定核對 | Command Bar 回報正確 Place / Universe ID，Selectable 數量為 7 |
| 人數設定 | 後台訪客上限由 50 改成 2 並保存 |
| 受眾狀態 | 公開；當時平台顯示 16 歲以上使用者與信任的聯絡對象 |
| 本輪未驗證 | 發佈後真機對戰；T23–T26 新四技能完整實測 |

平台另列未滿 16 歲的開放條件與費用；本次沒有付費，也沒有將較年輕受眾的開放標為完成。日後以當時後台顯示為準。

## 官方 API 參考

- https://create.roblox.com/docs/reference/engine/classes/DataModel#SetPlaceId
- https://create.roblox.com/docs/reference/engine/classes/DataModel#SetUniverseId

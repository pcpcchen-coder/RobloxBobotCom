# AGENTS.md｜RoboPush Arena 專案指示

## 工作定位

此 Repository 是 Roblox 小型對戰遊戲 **RoboPush Arena／機器人推推擂台** 的設計及後續實作來源。

- 對話中的草案已整理成 Repo 文件；實作時優先以 **docs/GDD.md、docs/SKILLS.md、docs/ARCHITECTURE.md** 和 **src/shared/GameConfig.lua** 作規格基準。
- **文件存在不代表功能已完成**。尚未驗證的項目不得標示已通過。
- 遇到不同文件有規格不一致時，先在 PR 註明差異、修正規格並同步更新配置。

## 實作習慣

1. 先確認目前 Repo 真實現況，再決定新增/修改的檔案。
2. 優先可玩閉環：玩家進場 → 倒數 → 對戰 → 擊退/掉落 → 得分/重生 → 結算。
3. 技能範圍：**基本 Dash＋七項特殊技能全部可選**（2026-10-24 依專案擁有者指示擴充；原 MVP 為 Dash＋Rocket Pop／Side Burst／Counter Shield）。新增技能須同步 GameConfig、SKILLS、TEST_PLAN。
4. 專案程式使用 Luau；比賽、技能與分數 Server-authoritative。
5. 所有 gameplay 數值放 GameConfig，不在多個程式碼中複製常數。
6. 先做好 PC 和手機，不要因為特效/外觀影響核心進度。
7. 每個模組寫清楚接口、呼叫責任、錯誤處理、生命週期清理。
8. 每次修改 gameplay 規則時，同步更改 GDD、SKILLS、ROADMAP、TEST_PLAN。
9. 對效能與公平性保持可驗證性，記錄關鍵事件 timeline 與具體測試證據。

## 驗證要求

- 實作任務依 **docs/ROADMAP.md** P1→P5。
- 測試依 **docs/TEST_PLAN.md** 的 T01–T22。
- 產出可追蹤的「需求 ↔ 測試 ↔ 結果 ↔ 證據」矩陣。
- 不可將 Not Run/Blocked 解讀為 Pass。
- 若無法啟動 Roblox Studio 或存取 Roblox 帳號，回報環境限制，仍完成可做的靜態檢查。
- 提交訊息說明功能與對應測試編號。

## 強烈避免

- 不要用 Client 傳來的命中、分數、位置作為最終依據。
- 不要先加入付費增益、跨伺服器排名或完整機器人組裝。
- 不要使用沒有記錄的魔法數字及未經清理的永久 Heartbeat 監聽。
- 不要重寫全部 Roblox 原生移動而沒有明確需求。

## 發佈更新（專案擁有者指定，2026-10-24）

- 發佈前必讀 [docs/PUBLISHING.md](docs/PUBLISHING.md)，之後更新固定沿用該文件的成功路徑。
- 固定目標：PUSHPUSH，Universe `10772683522`，Place `106459847310293`；人數上限 2。
- 先核對最新 CI 建置，再於 Studio Command Bar 設定 `game:SetPlaceId(106459847310293)`、`game:SetUniverseId(10772683522)`，讀回 ID 後使用一般 **File → Publish / Publish latest version**。
- 不將 Publish As / Save to Roblox As 作為此專案日常更新路徑；本次兩者卡住，一般 Publish 成功。
- 成功標準：Studio 明確成功訊息 + 後台版本紀錄的已發佈標記；記下來源 commit、版本與時間。正在上傳不算完成。
- 2026-10-24 16:39（Asia/Taipei）已成功發佈七技能程式至 Roblox **v7**；發佈成功不等於新增技能或真機回歸驗收通過。

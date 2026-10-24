# Claude Code / Codex｜開發 Agent 工作指令

本文件可直接提供給具備 GitHub/Roblox Studio 開發環境的 Agent。**不得跳過閱讀 Repo 文件**。

## 任務說明（可複製 Prompt）

你是一位資深 Roblox/Luau 多人遊戲工程師。請在本 Repo **pcpcchen-coder/RobloxBobotCom** 實作 RoboPush Arena（機器人推推擂台）。

### 先閱讀

- README.md
- docs/GDD.md
- docs/SKILLS.md
- docs/ARCHITECTURE.md
- docs/ROADMAP.md
- docs/TEST_PLAN.md
- AGENTS.md
- src/shared/GameConfig.lua

### 目標

完成一個 Roblox Studio 中可用兩位玩家操作的 1v1 對戰遊戲：固定基本 Dash + 每場選一項特殊技能（Rocket Pop、Side Burst、Counter Shield），掉落計分、先達 3 分獲勝、120 秒、20 秒延長賽、縮圈、重生保護、手機與 PC 控制及 UI。

### 開發要求

1. 先檢查現有專案與工作分支，不破壞已存在內容。
2. 先建立最小可跑專案（Roblox place / Luau scripts / Rojo），再按 ROADMAP P1→P5 實作。
3. 使用 server-authoritative 的比賽狀態、掉落、技能冷卻、命中及計分；RemoteEvent 請求一律驗證。
4. 將平衡參數集中在 GameConfig；使用清楚 Luau 模組邊界與必要型別註記。
5. 優先讓玩法完整可測，不為了美術資產阻塞。
6. 每次提交更新文件與對應 TEST_PLAN 狀態，註明是否實際在 Studio/真機測試。
7. 不要宣稱測試工具、Studio 或 Roblox 發佈操作成功，除非真的有執行並保存可檢查結果。
8. 針對物理、Network Ownership、技能取消、玩家斷線與縮圈重生，主動設計可重現的邊界測試。
9. 如果缺少 Roblox Studio、Rojo 或登入資訊，仍可完成可靜態檢查的 Luau 程式、配置和測試計畫；明確標示 Blocked 項，不要虛報整體完成。

### 每階段交付格式

- **實作摘要**：新增/修改的具體檔案和玩法。
- **檢查結果**：編譯/型別/靜態檢查/Studio 多人測試，各別說明。
- **測試證據**：Txx 案例、重現步驟、實際結果與畫面或 log。
- **風險及後續**：仍存在的公平性、網路同步、UI/效能問題。
- **版本連結**：提交 SHA、PR、建置結果（若有）。

### 禁止事項

- 禁止以客戶端聲稱的「命中/掉落/分數」當成權威。
- 禁止客戶端可任意改座標、技能冷卻或角色擊退參數。
- 禁止把尚未測試的機制標成 Pass。
- 禁止 v0.1 加入非必要商城/付費角色差異。

## 拆分可指派任務

- Agent A：P1 地圖、Avatar、Studio/Rojo 專案可啟動。
- Agent B：P2 狀態機、掉落計分、延長賽、斷線/重生。
- Agent C：P3 Combat/RemoteEvents、Dash 與三項特殊技能。
- Agent D：P4 UI、輸入跨平台、縮圈警示與特效。
- Agent E：P5 整合測試、回歸、證據矩陣、文件與限制。

**整合責任**：只由一名整合 Agent 確認對外 RemoteEvent 契約、GameConfig 與 matchId/lifeId 管理，避免多 Agent 修改互相衝突。

## 完成定義

- Roblox Studio 雙人模式完成可重複的完整對戰循環。
- 必測 T01–T22 至少有真實結果/Blocker；重大錯誤清零；手機真機經驗收。
- Repo 可以依 README 重現設置；有 commits、測試紀錄與已知限制。

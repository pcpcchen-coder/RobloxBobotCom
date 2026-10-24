# RoboPush Arena｜機器人推推擂台

> Roblox 小型多人對戰遊戲｜設計版本 **v0.2 (2026-10-24)**｜狀態：**P1–P4 已實作；T01–T22 經專案擁有者 Studio／真機實測回報通過（2026-10-24）；P5 進行中**

玩家操控可愛機器人，在逐漸縮小的懸浮擂台上，透過衝刺、突然彈跳與反制技能，將對手推下平台。遊戲以 **容易上手、短局制、公平競技、適合朋友同樂** 為核心。

**專案狀態說明：** 已有可由 Rojo 同步的 Luau 程式（比賽狀態機、計分、縮圈、Dash、七項特殊技能、HUD、跨裝置輸入）。專案擁有者已於 Studio 與真機實測 T01–T22 並回報正常（尚未附 log／截圖）；新增的四項技能（T23–T26）尚未實測；擊退與技能數值仍可依手感調整。測試現況見 [docs/TEST_REPORT.md](docs/TEST_REPORT.md)。

## 核心玩法

- **1v1**：等待兩位真人玩家後 3 秒倒數，開始正式 120 秒對戰。
- **計分**：讓對手掉下平台得 1 分；先達 **3 分** 立即獲勝。
- **時間到**：高分者獲勝；同分進入 **20 秒延長賽**，先得分者勝；仍同分則平手。
- **擂台縮圈**：起始 48×48 studs，45 秒縮至 36×36，90 秒縮至 24×24；延長賽開始縮至 18×18。
- **操作**：移動＋固定基本衝刺（4 秒冷卻）＋每場挑選 **一項特殊技能**。
- **平台**：PC 鍵鼠、手機觸控、手把。首版不做商店、付費數值或排行榜。

## 文件索引

| 文件 | 內容 |
|---|---|
| [docs/GDD.md](docs/GDD.md) | 完整遊戲規則、角色、地圖、操作與 UI |
| [docs/SKILLS.md](docs/SKILLS.md) | 7 項特殊技能、冷卻、反制、平衡與 MVP 優先級 |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Roblox/Luau 架構、模組、事件協定、伺服器權威 |
| [docs/ROADMAP.md](docs/ROADMAP.md) | 五階段 MVP 工作分解、交付與完成定義 |
| [docs/TEST_PLAN.md](docs/TEST_PLAN.md) | 多人、物理、輸入、作弊、掉線等驗收案例 |
| [docs/AGENT_HANDOFF.md](docs/AGENT_HANDOFF.md) | 交給 Claude Code / Codex 的可執行任務模板 |
| [AGENTS.md](AGENTS.md) | Agent 工作規則與完成條件 |
| [docs/TEST_REPORT.md](docs/TEST_REPORT.md) | 需求 ↔ 測試 ↔ 結果 ↔ 證據矩陣（目前執行狀況） |
| [src/shared/GameConfig.lua](src/shared/GameConfig.lua) | 全部 gameplay 參數（已接線，數值待實測調校） |

## 首個可玩版本（v0.1）

1. 先實作簡單角色與一張懸浮平台，不花時間製作精緻模型。
2. 讓兩位玩家完成等待、倒數、掉落得分、重生與勝負流程。
3. 實作固定基本衝刺；特殊技能優先做 **火箭彈跳、側向閃撞、反彈護盾**。
4. 完成縮圈、PC/手機操作、HUD、伺服器驗證和最基本的特效。
5. 使用 Roblox Studio **Server & Clients** 模擬雙人，並在手機真機驗收。

## 開發與執行

工具版本鎖定於 `rokit.toml`（Rojo 7.4.4、selene、StyLua、Lune）。

~~~bash
rokit install                 # 安裝工具鏈
./scripts/check.sh            # 格式 + lint + 純邏輯單元測試 + rojo build
rojo serve                    # 搭配 Roblox Studio Rojo 外掛同步
~~~

每次 push / PR 會由 GitHub Actions（`.github/workflows/ci.yml`）自動執行同一套檢查並上傳建置好的 `RoboPushArena.rbxl`。

Studio 雙人測試：`rojo serve` 連線後，於 Studio **Test → Clients and Servers** 選 1 Server + 2 Clients。
遊戲設定請把 **Max Players 設為 2**（伺服器人數無法由程式設定；第 3 位以後玩家會排隊觀戰）。

## 發佈私人測試版本（手機／手把實測用）

1. 以 Studio 開啟 `rojo build -o RoboPushArena.rbxl` 產生的檔案（或 CI artifact），或用 `rojo serve` 同步到已開啟的 place。
2. **File → Publish to Roblox As…** → 建立新體驗（或選既有體驗）。
3. **Home → Game Settings**：
   - **Permissions**：Playability 設 **Private**（只有你）或 **Friends**（邀請測試者）。
   - **Places → 設定 → Server Fill／Max Players** 設 **2**（程式無法設定伺服器人數）。
   - **Basic Info → Devices**：勾選 Computer、Phone、Tablet，需要手把時勾 Console。
4. 手機登入**同一個帳號或已被授權的帳號**，從 Roblox App「我的體驗」或分享連結進入。
5. 每次更新程式後重新 **Publish**；舊伺服器不會自動更新，可在網頁體驗設定中「Shut Down All Servers」。
6. 測試結果與 log 請記錄到 `docs/TEST_REPORT.md`。

> 公開（Public）發佈前需完成 Roblox 的 Experience Questionnaire（內容分級），且 MVP 不加入付費機制。

## 目錄

~~~text
RobloxBobotCom/
├── default.project.json          # Rojo 映射
├── rokit.toml / selene.toml / stylua.toml
├── .github/workflows/ci.yml      # CI：格式、lint、單元測試、rojo build
├── scripts/check.sh              # 離線靜態檢查與單元測試
├── src/
│   ├── shared/                   # → ReplicatedStorage.Shared
│   │   ├── GameConfig.lua        # 全部數值
│   │   ├── GameTypes.lua         # 狀態、結果原因、特效列舉
│   │   ├── Remotes.lua           # RemoteEvent 契約
│   │   ├── ArenaMath.lua         # 縮圈時程、出生點、掉落判定（純函式）
│   │   └── Maid.lua              # 生命週期清理
│   ├── server/                   # → ServerScriptService.RoboPush
│   │   ├── Bootstrap.server.lua
│   │   ├── Logic/                # 純邏輯，可離線測試
│   │   │   ├── MatchModel.lua    # 狀態機、計分、雙掉落、lifeId/matchId
│   │   │   ├── CombatRules.lua   # 命中幾何、擊退向量、驗證、節流
│   │   │   └── CombatState.lua   # 冷卻、護盾、抗擊退、技能選擇
│   │   └── Services/             # Roblox API 轉接層
│   │       ├── MatchService.lua  ArenaService.lua  CharacterService.lua
│   │       ├── CombatService.lua Logger.lua
│   └── client/                   # → StarterPlayerScripts.RoboPush
│       ├── Main.client.lua  ClientState.lua
│       └── Controllers/ InputController.lua UIController.lua EffectController.lua
├── tests/                        # Lune 單元測試（*.spec.luau）
└── docs/
~~~

## 版本展望

- **v0.1**：1v1 核心流程 + 三個特殊技能。
- **v0.2**：練習 AI、2v2（需重新檢討碰撞與比賽規則）。
- **v0.3**：新地圖、地形機關、角色裝扮。
- **v0.4**：好友房、勝場記錄、排名（需要資料持久化及反作弊）。
- **v0.5**：機器人組裝與模組化技能（平衡規則另訂）。

> 所有秒數、推力與距離都是 **設計初始值**，不是 Roblox 引擎保證的物理表現。以多人實測後更新 GameConfig 與文件。
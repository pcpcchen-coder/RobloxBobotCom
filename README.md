# RoboPush Arena｜機器人推推擂台

> Roblox 小型多人對戰遊戲｜設計版本 **v0.2 (2026-10-24)**｜狀態：**已完成設計，尚未實作與驗收**

玩家操控可愛機器人，在逐漸縮小的懸浮擂台上，透過衝刺、突然彈跳與反制技能，將對手推下平台。遊戲以 **容易上手、短局制、公平競技、適合朋友同樂** 為核心。

**專案狀態說明：** 此儲存庫目前以規劃文件為主；有參數草案，不代表 Roblox Studio 遊戲、物理手感或多人對戰已經完成。

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
| [src/shared/GameConfig.lua](src/shared/GameConfig.lua) | 預設平衡參數草案（尚未與遊戲接線） |

## 首個可玩版本（v0.1）

1. 先實作簡單角色與一張懸浮平台，不花時間製作精緻模型。
2. 讓兩位玩家完成等待、倒數、掉落得分、重生與勝負流程。
3. 實作固定基本衝刺；特殊技能優先做 **火箭彈跳、側向閃撞、反彈護盾**。
4. 完成縮圈、PC/手機操作、HUD、伺服器驗證和最基本的特效。
5. 使用 Roblox Studio **Server & Clients** 模擬雙人，並在手機真機驗收。

## 規劃中的目錄

~~~text
RoboPushArena/
├── README.md
├── AGENTS.md
├── default.project.json              # 待實作：Rojo 映射
├── src/
│   ├── shared/GameConfig.lua          # 已建立：參數草案
│   ├── server/                        # 待實作：Match / Combat / Arena 等
│   └── client/                        # 待實作：Input / UI / Effects
└── docs/
    ├── GDD.md
    ├── SKILLS.md
    ├── ARCHITECTURE.md
    ├── ROADMAP.md
    ├── TEST_PLAN.md
    └── AGENT_HANDOFF.md
~~~

## 版本展望

- **v0.1**：1v1 核心流程 + 三個特殊技能。
- **v0.2**：練習 AI、2v2（需重新檢討碰撞與比賽規則）。
- **v0.3**：新地圖、地形機關、角色裝扮。
- **v0.4**：好友房、勝場記錄、排名（需要資料持久化及反作弊）。
- **v0.5**：機器人組裝與模組化技能（平衡規則另訂）。

> 所有秒數、推力與距離都是 **設計初始值**，不是 Roblox 引擎保證的物理表現。以多人實測後更新 GameConfig 與文件。
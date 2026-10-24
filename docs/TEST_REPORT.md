# 測試報告｜需求 ↔ 測試 ↔ 結果 ↔ 證據

報告日期：2026-10-24｜分支：`claude/gifted-pasteur-ej3zpp`

## 執行環境與限制

- 環境：Linux 雲端容器，**沒有 Roblox Studio、沒有 Roblox 帳號、沒有手機/手把**。
- 因此 T01–T22 的 **Studio／真機欄位全部為 Not Run（Blocked：環境限制）**。
- 已執行的只有離線檢查：
  - `stylua --check src tests`（格式）→ 通過
  - `selene src`（lint）→ 0 errors / 0 warnings。**注意**：容器無法下載 Roblox API dump，lint 以自訂離線 std（luau + Roblox 全域名稱）執行；正式 `std = "roblox"` 尚未在本機跑過。
  - Luau 編譯檢查（Lune 內建 Luau compiler，全部 19 個 `.lua`）→ 通過
  - `lune run tests/run`（純邏輯單元測試）→ **41 passed, 0 failed**
  - `rojo build default.project.json`（Rojo 7.4.4）→ 成功產生 `.rbxlx`，實例樹符合 ARCHITECTURE 映射（Shared／RoboPush Script＋Logic＋Services／StarterPlayerScripts LocalScript＋Controllers）
- **未執行**：Luau 型別檢查（`luau-analyze` 需 Roblox 型別定義，容器內不可用）。

> 單元測試只驗證 `src/server/Logic/` 與 `src/shared/` 的純邏輯（狀態機、計分、冷卻、幾何、驗證）。
> 物理、網路同步、輸入、UI、手機操作都 **只能在 Studio／真機驗證**，不可把單元測試 Pass 當作 T 案例 Pass。

## 矩陣

| ID | 需求來源 | 邏輯單元測試（tests/） | 單元結果 | Studio／真機 | 證據 |
|---|---|---|---|---|---|
| T01 | GDD 2、7 | MatchModel: `T01 one player waits…` | Pass | Not Run | 單元測試輸出 |
| T02 | GDD 2 | MatchModel: `T02 a fall gives the opponent exactly one point…` | Pass | Not Run | 同上 |
| T03 | GDD 6.1 | Combat: `T03 dash cooldown…` | Pass | Not Run | 同上 |
| T04 | ARCH 4 | Combat: 擊退方向/數值（`knockback direction…`）；物理一致性無法離線 | 部分（向量計算 Pass） | Not Run | 同上 |
| T05 | GDD 2 | MatchModel: `T05 third point ends the match…` | Pass | Not Run | 同上 |
| T06 | GDD 2 | MatchModel: `T06 tie at 120s…`、`T06 sudden death without a score…` | Pass | Not Run | 同上 |
| T07 | GDD 3.2 | MatchModel: `T07/T19 shrink schedule…` | Pass | Not Run | 同上 |
| T08 | GDD 3.2 | Config: `T08 spawn points stay inside every platform size…` | Pass | Not Run | 同上 |
| T09 | GDD 2 | MatchModel: `T09 disconnect during RUNNING…` | Pass | Not Run | 同上 |
| T10 | GDD 5 | —（手機真機） | N/A | Not Run | — |
| T11 | ARCH 8 | Combat: `T11 rate limiter…`、`T03`（CD 拒絕） | Pass | Not Run | 同上 |
| T12 | ROADMAP P5 | —（30 場耐久） | N/A | Not Run | — |
| T13 | GDD 2 | MatchModel: `T13 double fall inside window…`、`T13 … sudden death…` | Pass | Not Run | 同上 |
| T14 | GDD 7 | MatchModel: `T14 disconnect during COUNTDOWN…` | Pass | Not Run | 同上 |
| T15 | GDD 2 | MatchModel: `spawn protection blocks acting…`；受擊保護在 CombatService（需 Studio） | 部分 Pass | Not Run | 同上 |
| T16 | SKILLS 2 | Combat: `T16 rocket pop radius…` | Pass | Not Run | 同上 |
| T17 | SKILLS 4 | Combat: `T17 side burst side selection…`、`T22 direction hint validation…` | Pass | Not Run | 同上 |
| T18 | SKILLS 6 | Combat: `T18 shield…` | Pass | Not Run | 同上 |
| T19 | GDD 3.2 | MatchModel: `T07/T19 shrink schedule…`、`T06`（延長賽 18×18） | Pass | Not Run | 同上 |
| T20 | GDD 5 | —（鍵鼠/手機/手把實機） | N/A | Not Run | — |
| T21 | ARCH 5 | MatchModel: `T21 stale lifeId…`、`stale SpawnPlayer token…` | Pass | Not Run | 同上 |
| T22 | ARCH 8 | Combat: `skill selection only when open… (T22)`、`T22 direction hint validation…` | Pass | Not Run | 同上 |

## 重現方式

~~~bash
./scripts/check.sh      # 或分別執行 stylua / selene / lune run tests/run / rojo build
~~~

## Studio 驗收時要收集的事件 timeline

伺服器 Output 會印出 `[RoboPush] t=<server time> <event> k=v …`，事件包括：
`player_added`、`state`、`life_started`、`dash`、`rocket_pop`、`side_burst`、`shield_up`、
`hit`、`shield_rebound`、`shield_block`、`impact_ignored`、`fall`、`score`、`result`、
`arena_warning`、`arena_changed`、`request_rejected`、`anomaly`。
Studio 測試時請把對應 Txx 的 log 片段與截圖/影片附到此表的「證據」欄。

## 已知風險（需 Studio 實測）

1. 擊退採「伺服器暫時接管 Network Ownership + ApplyImpulse」，可能在受擊者畫面出現短暫卡頓；42/12 studs/s 實際飛行距離未知。
2. Dash/Side Burst 位移由擁有者 Client 模擬，命中用伺服器位置判定，延遲高時可能出現「看起來撞到但沒中」。
3. Rocket Pop 的 `LaunchVerticalSpeed`、Side Burst `Duration`、護盾反彈值都是 placeholder。
4. 手機觸控按鈕位置（CAS 預設樣式）未經真機確認是否與搖桿或 HUD 重疊。
5. 內建音效路徑（`rbxasset://sounds/...`）未在 Studio 確認可播放。

# 技術架構｜RoboPush Arena v0.2

文件性質：**設計與實作指南**；P1–P4 腳本已依本文件實作（見第 11 節），**尚未經 Studio 多人實測**。

## 1. 技術選型

- **平台**：Roblox Studio / Luau；固定 2 位玩家的 Roblox 遊戲伺服器。
- **玩家角色**：R15 + Humanoid + HumanoidRootPart，基礎移動沿用 Roblox 原生控制。
- **物理**：Roblox Physics Engine。初步以 ApplyImpulse 施加擊退；運動及物理網路所有權依雙人測試確認。
- **網路**：RemoteEvents 傳輸「操作意圖」與「權威結果」，不能讓客戶端宣稱命中、分數或任意位置。
- **資料**：MVP 只保存在每場 server memory，不使用 DataStore、跨服 Matchmaking。
- **版本控管**：Git + Rojo（建議）或 Roblox Studio Script Sync；所有文字腳本與參數進 Git。
- **輸入**：優先統一 Input Action System；不同裝置綁到同一個命令。

## 2. 模組邊界

| 模組 | 執行端 | 單一責任 |
|---|---|---|
| Bootstrap.server.lua | ServerScriptService | 建立 RemoteEvents，初始化服務，註冊玩家 |
| MatchService | Server | WAITING/COUNTDOWN/RUNNING/SUDDEN_DEATH/RESULT、局號、斷線 |
| ArenaService | Server | 地圖產生、縮圈、當前平台範圍、掉落偵測 |
| CombatService | Server | 衝刺/技能冷卻、命中掃描、護盾優先權、擊退衝量 |
| ScoreService | Server | 事件去重、加分、勝負結算 |
| CharacterService | Server | 雙色等能力角色、重生位置、出生保護、死亡鎖定 |
| InputController | Client | 鍵鼠/觸控/手把統一到 Dash 與 Special 請求 |
| UIController | Client | HUD、倒數、技能選擇、結果與警示 |
| EffectController | Client | 音效、粒子、鏡頭震動（僅呈現） |
| GameConfig | Shared | 全數值設定，伺服器保有最終驗證權限 |
| GameTypes | Shared | 比賽狀態、結果原因、特效列舉與型別 |
| Remotes / ArenaMath / Maid | Shared | RemoteEvent 契約、縮圈與出生點純函式、生命週期清理 |
| MatchModel / CombatRules / CombatState | Server（Logic） | 純邏輯層，無 Roblox API，可用 Lune 離線測試 |
| Logger | Server | 事件 timeline（matchId、lifeId、技能、命中、掉落、得分、結果） |

**建議映射：**

~~~text
src/shared  -> ReplicatedStorage/Shared
src/server  -> ServerScriptService
src/client  -> StarterPlayer/StarterPlayerScripts
~~~

MVP 目錄結構詳見首頁 README；先從空白環境建立 Rojo project map，避免一邊在 Studio 手動改程式，一邊在 Git 維護不同版本。

## 3. 事件設計

### Client → Server

| Event | 最小 payload | 伺服器驗證 |
|---|---|---|
| RequestDash | clientSequence（僅去重輔助） | RUNNING/延長賽、角色可操作、冷卻、移動狀態 |
| RequestSpecial | skillId, directionHint | skillId 等於本局已選技能、冷卻、方向向量範圍、有效狀態 |
| SelectSkill | skillId | 必須在允許選技能時段，且為 unlocked/available |
| RequestSnapshot | 無 | 每位玩家最少間隔 `Net.SnapshotMinInterval` 秒 |
| RequestReady（可選，未實作） | 無 | 玩家在本場配對內 |

**方向安全規則**：directionHint 只作操作提示，不接受目標世界座標、傷害數字、分數或任何 hitPlayer ID。以角色的伺服器認可姿態與合理輸入來決定最終方向。

### Server → Client

| Event | payload | 用途 |
|---|---|---|
| MatchSnapshot | matchId, state, serverTime, endsAt, scores, arenaSize | 首次加入與狀態重同步 |
| MatchChanged | matchId, state, endsAt | 倒數、開戰、延長賽、結算 |
| ScoreChanged | matchId, scores, scorer | UI 得分 |
| SkillState | skillId, availableAt | UI 冷卻 |
| CombatEffect | effectType, source, target, position | 純視覺音效 |
| ArenaWarning | nextSize, shrinkAt | 縮圈提醒 |
| ArenaChanged | size, shrinkDuration | 平台同步及特效 |
| RoundResult | winner, reason, finalScores | 結算 |

事件載荷名稱只是契約草案；實作時明確制定 Roblox 型別/RemoteEvent 名稱與方向，禁止客戶端直接發送 Server → Client 權威結果。

## 4. Server-authoritative 驗證流程

### 衝刺 Dash

1. Client 使用 Shift／手機／手把發送 RequestDash。
2. Server 驗證 matchState、角色狀態、出生保護、技能冷卻、反重播。
3. Server 註冊 dashWindow（開始時間/結束時間/已命中集合），觸發可同步的移動。
4. Server 在有效窗口連續取樣位置/前方扇形/高度差，判斷是否與對手交會（必要時使用空間查詢/掃掠，避免高速穿透）。
5. 若對方正在有效 Counter Shield，**先處理護盾反彈**；否則執行一般命中擊退。
6. Server 施加物理效果、寫入 CD、廣播純呈現特效。
7. Server 觀測掉落、ScoreService 判斷是否可計分，並發送 ScoreChanged。

### 擊退模型（初始值）

目標：受擊機器人瞬間取得約 42 studs/s 的水平擊退增量及 12 studs/s 的向上增量：

~~~text
J = assemblyMass × (42 × horizontalDirection + 12 × worldUp)
~~~

Luau 可透過 AssemblyMass 配合 ApplyImpulse 給受擊模型 root part；**不是保證速度**。當前速度、質量、摩擦、角色控制器、重疊碰撞與 Network Ownership 都會改變結果。應用真實多人連線測試修正。

### 特殊技能

- 每個技能有唯一 ID、cooldown、startup、activeWindow、recovery/cancel 狀態。
- Fire Rocket Pop：起跳有提示，Server 決定擊退範圍，不信任 Client 的「我擊中」宣稱。
- Side Burst：Server 驗證側移方向，位移不能直接 Teleport 到客戶端提供座標。
- Counter Shield：伺服器時間窗口內可消耗一次撞擊；與 Dash 同幀發生時，規定先判 Shield。
- 後續技能 Ground Slam、Magnet Pull、Phantom Brake、Rescue Claw 不進第一個 milestone。

## 5. 伺服器比賽資料結構

~~~text
MatchState {
  matchId: string
  state: WAITING|COUNTDOWN|RUNNING|SUDDEN_DEATH|RESULT
  players: [playerA, playerB]
  scores: {[userId]: number}
  startedAt: serverTimestamp?
  phaseEndsAt: serverTimestamp?
  arenaSize: number
  activeLifeId: {[userId]: number}
  eliminatedLifeIds: set
  selectedSkill: {[userId]: skillId}
  skillReadyAt: {[userId]: {[skillId]: timestamp}}
}
~~~

- serverTimestamp 一律伺服器計時；客戶端只做視覺倒數。
- matchId 防止上一局延遲 RemoteEvent 汙染新的一局。
- lifeId 防止同一玩家同次掉落重複計分。
- 勝負結算只在單一路徑變更狀態，避免同時 Timeout 與得分雙重結算。
- 同幀雙掉落可採用短的判定合併窗口（例如 0.1 秒；需測試）而非誰先執行 callback 就先得分。

## 6. 地圖與角色生命週期

- ArenaService 管理單一 Anchored 平台的 TweenSize，平台中心位置不動，警示於縮圈前五秒發送。
- Shrink 大小：48 → 36 → 24，延長賽開始 18；對戰結束重設 48。
- 在每次重生前依當前尺寸算對稱安全出生點，檢查角色膠囊/碰撞外框。
- CharacterService 建立出生保護；保護期只允許移動，不允許技能擊退其他玩家。
- 如果玩家在 COUNTDOWN 離線，取消倒數；在 RUNNING/SUDDEN_DEATH 離線則另一方 forfeit 勝。
- Roblox PlayerRemoving、CharacterRemoving、Humanoid.Died 等事件須解除技能狀態、斷線連線及 pending task，避免跨回合作用。

## 7. 效能與網路

- 不以每幀全球掃描 Workspace；只檢查兩位配對者、有限技能窗口。
- RenderStepped 僅用於 Client 效果；分數判斷全部 Server。
- 不逐幀發送位置給 Client；原生角色/物理同步由 Roblox 負責。
- Client EffectController 可以平滑預測效果，但 **最後結果以 Server 為準**。
- 避免依賴客戶端 network-owned 物理狀態做關鍵命中；需要評估伺服器接管部分物理的流暢度成本。
- Logging 最少記 matchId、lifeId、timestamp、技能施放、命中、掉落、得分、結束原因。

## 8. 安全與公平

- RemoteEvent 驗證：player 身份、節流、matchId、state、skillId、CD、方向、角色存活。
- 不信任客戶端傳入的 target、position、velocity、impulse、score。
- 偵測異常移速、超出地圖瞬移、不合理施放頻率，先記錄再逐步加入處置。
- 所有可被命中的角色使用一致的 hitbox，不因裝甲外觀改變。
- 初期不上線競技排行，先把同步與物理手感調好。

## 9. 交付與驗證

優先完成 [ROADMAP](ROADMAP.md) P1→P5；每階段應有可重現遊戲影片/截圖、測試步驟和異常清單。測試依 [TEST_PLAN](TEST_PLAN.md)，禁止把未執行項目標為 Pass。

## 10. 實作決策（2026-10-24）

- **兩層結構**：`Logic/` 純邏輯（時間由參數注入、回傳事件列表）＋ `Services/` Roblox 轉接層。MatchService 把 MatchModel 事件（StateChanged、ScoreChanged、Result、SpawnPlayer、FallResolved、ArenaWarning、ArenaChanged）轉成角色生成、平台縮放與 RemoteEvent。
- **計時**：全部使用 `workspace:GetServerTimeNow()`；Client 只用同一時鐘顯示倒數。
- **重生序列化**：每位玩家一個 spawn worker，只執行最新 token 的 SpawnPlayer，避免 LoadCharacter 競態；`beginLife` 拒絕過期 token。
- **掉落偵測**：Heartbeat 只檢查最多 2 位參賽者的 HumanoidRootPart Y；Humanoid.Died 也視為該 life 的掉落（lifeId 去重）。
- **Heartbeat 生命週期**：比賽迴圈只在伺服器有玩家時連線；CombatService 的命中掃描只在有啟動中的技能窗口時連線，最後一個窗口結束即斷開；BindToClose 清理全部。
- **自身位移**（Dash、Side Burst、Rocket Pop 起跳）：伺服器在角色 root 上建立短暫 `LinearVelocity`，由擁有者 Client 模擬（無輸入延遲）；命中判定使用伺服器端位置。
- **擊退**：伺服器暫時取得受擊者 Network Ownership（`Physics.KnockbackOwnershipSeconds`），`PlatformStand` 後以 `ApplyImpulse(Δv × AssemblyMass)` 施加，之後歸還所有權。**此策略需 T04 雙人實測確認流暢度與一致性。**
- **節流**：每位玩家一個 token bucket（`Net.MaxRequestsPerSecond / BurstRequests`），超量請求記錄 anomaly 並丟棄。

## 11. 官方參考

- Roblox remote events: https://create.roblox.com/docs/scripting/events/remote
- Roblox network ownership: https://create.roblox.com/docs/physics/network-ownership
- Roblox BasePart.ApplyImpulse: https://create.roblox.com/docs/reference/engine/classes/BasePart#ApplyImpulse
- Roblox TweenService: https://create.roblox.com/docs/reference/engine/classes/TweenService
- Roblox testing modes: https://create.roblox.com/docs/studio/testing-modes
- Roblox Luau type checking: https://luau.org/typecheck

--!strict
-- RoboPush Arena / UIController.lua
-- HUD built in code (no assets): scores, timer, state banner / countdown,
-- shrink warning, Dash + skill cooldowns, skill picker, result (GDD 5).
-- Display only; every number shown comes from server events.
--
-- Interface: UIController.start(remotes) / UIController.stop()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local GameTypes = require(Shared:WaitForChild("GameTypes"))
local Maid = require(Shared:WaitForChild("Maid"))
local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local MatchState = GameTypes.MatchState

local UIController = {}

local maid = Maid.new()
local remotes: { [string]: RemoteEvent } = {}
local widgets: { [string]: any } = {}

local REASON_TEXT = {
    score = "先達 3 分",
    timeout = "時間到",
    sudden_death = "延長賽決勝",
    draw = "延長賽平手",
    forfeit = "對手離線",
}

local function slotColor(slot: number): Color3
    local rgb = GameConfig.Robot.SlotColors[slot].Color
    return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function label(name: string, parent: Instance, size: UDim2, position: UDim2, textSize: number): TextLabel
    local text = Instance.new("TextLabel")
    text.Name = name
    text.Size = size
    text.Position = position
    text.BackgroundTransparency = 1
    text.TextColor3 = Color3.new(1, 1, 1)
    text.TextStrokeTransparency = 0.4
    text.Font = Enum.Font.GothamBold
    text.TextSize = textSize
    text.Text = ""
    text.Parent = parent
    return text
end

local function formatClock(seconds: number): string
    local s = math.max(0, math.ceil(seconds))
    return string.format("%d:%02d", s // 60, s % 60)
end

local function build(): ScreenGui
    local gui = Instance.new("ScreenGui")
    gui.Name = "RoboPushHUD"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    local top = Instance.new("Frame")
    top.Name = "TopBar"
    top.Size = UDim2.fromOffset(360, 54)
    top.Position = UDim2.new(0.5, -180, 0, 6)
    top.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
    top.BackgroundTransparency = 0.3
    top.Parent = gui
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = top

    widgets.scoreBlue = label("ScoreBlue", top, UDim2.fromScale(0.33, 1), UDim2.new(0, 0, 0, 0), 28)
    widgets.scoreBlue.TextColor3 = slotColor(1)
    widgets.timer = label("Timer", top, UDim2.fromScale(0.34, 1), UDim2.fromScale(0.33, 0), 26)
    widgets.scoreOrange = label("ScoreOrange", top, UDim2.fromScale(0.33, 1), UDim2.fromScale(0.67, 0), 28)
    widgets.scoreOrange.TextColor3 = slotColor(2)

    widgets.banner = label("Banner", gui, UDim2.new(1, 0, 0, 60), UDim2.fromScale(0, 0.28), 40)
    widgets.subBanner = label("SubBanner", gui, UDim2.new(1, 0, 0, 30), UDim2.new(0, 0, 0.28, 60), 22)
    widgets.warning = label("Warning", gui, UDim2.new(1, 0, 0, 30), UDim2.fromOffset(0, 66), 22)
    widgets.warning.TextColor3 = Color3.fromRGB(255, 210, 60)

    -- Cooldowns: bottom-left, away from the right-side touch buttons.
    local cooldowns = Instance.new("Frame")
    cooldowns.Name = "Cooldowns"
    cooldowns.Size = UDim2.fromOffset(220, 60)
    cooldowns.Position = UDim2.new(0, 12, 1, -230)
    cooldowns.BackgroundTransparency = 1
    cooldowns.Parent = gui
    widgets.dashCd = label("DashCooldown", cooldowns, UDim2.fromScale(1, 0.5), UDim2.new(0, 0, 0, 0), 20)
    widgets.skillCd = label("SkillCooldown", cooldowns, UDim2.fromScale(1, 0.5), UDim2.fromScale(0, 0.5), 20)
    widgets.dashCd.TextXAlignment = Enum.TextXAlignment.Left
    widgets.skillCd.TextXAlignment = Enum.TextXAlignment.Left

    -- Skill picker (only while selection is open).
    local picker = Instance.new("Frame")
    picker.Name = "SkillPicker"
    picker.Size = UDim2.fromOffset(420, 56)
    picker.Position = UDim2.new(0.5, -210, 0.62, 0)
    picker.BackgroundTransparency = 1
    picker.Parent = gui
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.Padding = UDim.new(0, 8)
    layout.Parent = picker
    widgets.picker = picker
    widgets.skillButtons = {}
    for _, skillId in GameConfig.Skills.AvailableInMVP do
        local button = Instance.new("TextButton")
        button.Name = skillId
        button.Size = UDim2.new(0, 130, 1, 0)
        button.BackgroundColor3 = Color3.fromRGB(40, 44, 60)
        button.TextColor3 = Color3.new(1, 1, 1)
        button.Font = Enum.Font.GothamBold
        button.TextSize = 16
        button.TextWrapped = true
        button.Text = GameConfig.Skills[skillId].Name
        button.Parent = picker
        local buttonCorner = Instance.new("UICorner")
        buttonCorner.CornerRadius = UDim.new(0, 8)
        buttonCorner.Parent = button
        maid:give(button.Activated:Connect(function()
            remotes.SelectSkill:FireServer(skillId)
        end))
        widgets.skillButtons[skillId] = button
    end

    gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
    return gui
end

local function mySlot(s: ClientState.State): number?
    return table.find(s.players, Players.LocalPlayer.UserId)
end

local function renderStatic(s: ClientState.State)
    local blueId, orangeId = s.players[1], s.players[2]
    local blueScore = blueId and s.scores[tostring(blueId)] or 0
    local orangeScore = orangeId and s.scores[tostring(orangeId)] or 0
    widgets.scoreBlue.Text = string.format("藍 %d", blueScore)
    widgets.scoreOrange.Text = string.format("%d 橘", orangeScore)

    local selectOpen = GameTypes.isSkillSelectState(s.state) and mySlot(s) ~= nil
    widgets.picker.Visible = selectOpen
    for skillId, button in widgets.skillButtons do
        button.BackgroundColor3 = if skillId == s.selectedSkill then Color3.fromRGB(0, 170, 255) else Color3.fromRGB(40, 44, 60)
    end

    widgets.subBanner.Text = ""
    if s.state == MatchState.WAITING then
        widgets.banner.Text = "等待對手加入…"
    elseif s.state == MatchState.SUDDEN_DEATH then
        widgets.banner.Text = "延長賽！先掉落者負"
    elseif s.state == MatchState.RESULT and s.result then
        local winner = s.result.winner
        if winner == nil then
            widgets.banner.Text = "平手"
        elseif winner == Players.LocalPlayer.UserId then
            widgets.banner.Text = "你贏了！"
        elseif mySlot(s) then
            widgets.banner.Text = "你輸了"
        else
            local slot = table.find(s.players, winner)
            widgets.banner.Text = if slot == 1 then "藍隊獲勝" else "橘隊獲勝"
        end
        widgets.subBanner.Text = REASON_TEXT[s.result.reason] or s.result.reason
    elseif s.state ~= MatchState.COUNTDOWN then
        widgets.banner.Text = ""
    end
end

-- Per-frame text for clocks and cooldowns (presentation only).
local function renderFrame()
    local s = ClientState.get()
    local now = workspace:GetServerTimeNow()
    local remaining = if s.endsAt then s.endsAt - now else nil

    if s.state == MatchState.RUNNING or s.state == MatchState.SUDDEN_DEATH then
        widgets.timer.Text = remaining and formatClock(remaining) or ""
    else
        widgets.timer.Text = ""
    end
    if s.state == MatchState.COUNTDOWN and remaining then
        widgets.banner.Text = tostring(math.max(1, math.ceil(remaining)))
    end

    local warning = s.warning
    if warning and now < warning.shrinkAt and (s.state == MatchState.RUNNING) then
        widgets.warning.Text =
            string.format("擂台將縮小至 %d×%d（%.0f 秒）", warning.nextSize, warning.nextSize, math.ceil(warning.shrinkAt - now))
    else
        widgets.warning.Text = ""
    end

    local dashLeft = (s.readyAt.dash or 0) - now
    widgets.dashCd.Text = if dashLeft > 0 then string.format("DASH  %.1fs", dashLeft) else "DASH  就緒"
    local skillId = s.selectedSkill
    local skill = GameConfig.Skills[skillId]
    if skill then
        local skillLeft = (s.readyAt[skillId] or 0) - now
        widgets.skillCd.Text = if skillLeft > 0
            then string.format("%s  %.1fs", skill.Name, skillLeft)
            else string.format("%s  就緒", skill.Name)
    else
        widgets.skillCd.Text = ""
    end
end

function UIController.start(remoteMap: { [string]: RemoteEvent })
    remotes = remoteMap
    maid:give(build())
    maid:give(ClientState.subscribe(renderStatic))
    maid:give(RunService.RenderStepped:Connect(renderFrame))
    renderStatic(ClientState.get())
end

function UIController.stop()
    maid:cleanup()
end

return UIController

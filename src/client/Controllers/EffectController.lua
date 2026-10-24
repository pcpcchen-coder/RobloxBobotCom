--!strict
-- RoboPush Arena / EffectController.lua
-- Presentation-only feedback for CombatEffect events: flash spheres, sound,
-- light camera shake for the local robot. Never decides gameplay (GDD 6.1).
--
-- Interface: EffectController.start(remotes) / EffectController.stop()

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local GameTypes = require(Shared:WaitForChild("GameTypes"))
local Maid = require(Shared:WaitForChild("Maid"))

local EffectType = GameTypes.EffectType

local EffectController = {}

local maid = Maid.new()

-- Visual tuning (presentation only, not gameplay values).
local FLASH_SECONDS = 0.25
local SHAKE_OFFSET = 0.35
local STYLE: { [string]: { color: Color3, size: number, sound: string? } } = {
    [EffectType.DASH] = { color = Color3.fromRGB(255, 255, 255), size = 3 },
    [EffectType.DASH_HIT] = { color = Color3.fromRGB(255, 240, 120), size = 6, sound = "rbxasset://sounds/swordlunge.wav" },
    [EffectType.ROCKET_POP] = { color = Color3.fromRGB(255, 120, 40), size = 4, sound = "rbxasset://sounds/electronicpingshort.wav" },
    [EffectType.ROCKET_HIT] = { color = Color3.fromRGB(255, 90, 30), size = 8, sound = "rbxasset://sounds/swordlunge.wav" },
    [EffectType.SIDE_BURST] = { color = Color3.fromRGB(150, 255, 150), size = 3 },
    [EffectType.SIDE_HIT] = { color = Color3.fromRGB(120, 255, 120), size = 6, sound = "rbxasset://sounds/swordlunge.wav" },
    [EffectType.SHIELD_UP] = { color = Color3.fromRGB(120, 220, 255), size = 5, sound = "rbxasset://sounds/electronicpingshort.wav" },
    [EffectType.SHIELD_REBOUND] = { color = Color3.fromRGB(80, 200, 255), size = 9, sound = "rbxasset://sounds/swordlunge.wav" },
    [EffectType.SHIELD_BLOCK] = { color = Color3.fromRGB(80, 200, 255), size = 6 },
    [EffectType.SLAM_JUMP] = { color = Color3.fromRGB(255, 200, 80), size = 3 },
    [EffectType.SLAM_HIT] = { color = Color3.fromRGB(255, 170, 40), size = 14, sound = "rbxasset://sounds/swordlunge.wav" },
    [EffectType.MAGNET] = { color = Color3.fromRGB(200, 90, 255), size = 4, sound = "rbxasset://sounds/electronicpingshort.wav" },
    [EffectType.MAGNET_HIT] = { color = Color3.fromRGB(190, 80, 255), size = 6 },
    [EffectType.PHANTOM] = { color = Color3.fromRGB(180, 240, 255), size = 3 },
    [EffectType.RESCUE] = { color = Color3.fromRGB(255, 255, 120), size = 5, sound = "rbxasset://sounds/electronicpingshort.wav" },
}

local function rootOf(userId: number?): BasePart?
    if not userId then
        return nil
    end
    local player = Players:GetPlayerByUserId(userId)
    local character = player and player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    return if root and root:IsA("BasePart") then root else nil
end

local function flash(position: Vector3, color: Color3, size: number)
    local part = Instance.new("Part")
    part.Shape = Enum.PartType.Ball
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.Material = Enum.Material.Neon
    part.Color = color
    part.Size = Vector3.one * (size * 0.4)
    part.CFrame = CFrame.new(position)
    part.Parent = workspace
    TweenService:Create(part, TweenInfo.new(FLASH_SECONDS), { Size = Vector3.one * size, Transparency = 1 }):Play()
    Debris:AddItem(part, FLASH_SECONDS + 0.05)
end

local function playSound(soundId: string, parent: Instance)
    local sound = Instance.new("Sound")
    sound.SoundId = soundId
    sound.Volume = 0.6
    sound.Parent = parent
    sound:Play()
    Debris:AddItem(sound, 2)
end

local function shake()
    local character = Players.LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return
    end
    humanoid.CameraOffset = Vector3.new(SHAKE_OFFSET, SHAKE_OFFSET * 0.5, 0)
    TweenService:Create(humanoid, TweenInfo.new(FLASH_SECONDS), { CameraOffset = Vector3.zero }):Play()
end

-- Phantom Brake hologram: translucent, non-colliding block that keeps sliding
-- forward. Purely local presentation; it is not a player and cannot be hit.
local function phantom(from: Vector3, direction: Vector3)
    local skill = GameConfig.Skills.phantom_brake
    local flat = Vector3.new(direction.X, 0, direction.Z)
    if flat.Magnitude < 1e-3 then
        return
    end
    local ghost = Instance.new("Part")
    ghost.Name = "PhantomGhost"
    ghost.Anchored = true
    ghost.CanCollide = false
    ghost.CanQuery = false
    ghost.CanTouch = false
    ghost.Material = Enum.Material.Neon
    ghost.Color = Color3.fromRGB(180, 240, 255)
    ghost.Transparency = 0.5
    ghost.Size = Vector3.new(2, 5, 1)
    ghost.CFrame = CFrame.lookAt(from, from + flat)
    ghost.Parent = workspace
    local goal = CFrame.lookAt(from + flat.Unit * skill.GhostDistance, from + flat.Unit * (skill.GhostDistance + 1))
    TweenService:Create(ghost, TweenInfo.new(skill.GhostDuration, Enum.EasingStyle.Linear), { CFrame = goal, Transparency = 1 }):Play()
    Debris:AddItem(ghost, skill.GhostDuration + 0.05)
end

-- Rescue Claw: a short beam from where the robot was to where it landed.
local function claw(landing: Vector3, delta: Vector3)
    local from = landing - delta
    local length = delta.Magnitude
    if length < 1e-3 then
        return
    end
    local beam = Instance.new("Part")
    beam.Anchored = true
    beam.CanCollide = false
    beam.CanQuery = false
    beam.CanTouch = false
    beam.Material = Enum.Material.Neon
    beam.Color = Color3.fromRGB(255, 255, 120)
    beam.Size = Vector3.new(0.3, 0.3, length)
    beam.CFrame = CFrame.lookAt((from + landing) / 2, landing)
    beam.Parent = workspace
    TweenService:Create(beam, TweenInfo.new(FLASH_SECONDS), { Transparency = 1 }):Play()
    Debris:AddItem(beam, FLASH_SECONDS + 0.05)
end

local function onCombatEffect(effectType: string, sourceId: number?, targetId: number?, position: Vector3?, direction: Vector3?)
    if effectType == EffectType.FALL then
        return -- HUD score change is the feedback for falls
    end
    local style = STYLE[effectType]
    if not style then
        return
    end
    local anchor = rootOf(targetId) or rootOf(sourceId)
    local at = position or (anchor and anchor.Position)
    if at then
        flash(at, style.color, style.size)
    end
    if effectType == EffectType.PHANTOM and position and direction then
        phantom(position, direction)
    elseif effectType == EffectType.RESCUE and position and direction then
        claw(position, direction)
    end
    if style.sound and anchor then
        playSound(style.sound, anchor)
    end
    if targetId == Players.LocalPlayer.UserId then
        shake()
    end
end

function EffectController.start(remotes: { [string]: RemoteEvent })
    maid:give(remotes.CombatEffect.OnClientEvent:Connect(onCombatEffect))
end

function EffectController.stop()
    maid:cleanup()
end

return EffectController

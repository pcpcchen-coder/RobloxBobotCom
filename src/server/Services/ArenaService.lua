--!strict
-- RoboPush Arena / ArenaService.lua
-- Builds the Sky Arena platform and animates shrink steps (GDD 3). Timing
-- decisions live in MatchModel; this module only renders the size it is told.
--
-- Interface
--   ArenaService.init(config)            -- build workspace.SkyArena (idempotent)
--   ArenaService.resize(size, duration)  -- tween platform X/Z, cancels previous tween
--   ArenaService.spawnCFrame(size, slot) -- symmetric spawn facing the center
--   ArenaService.destroy()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArenaMath = require(Shared:WaitForChild("ArenaMath"))

local ArenaService = {}

local config: any = nil
local model: Model? = nil
local platform: Part? = nil
local activeTween: Tween? = nil

local function platformCFrame(): CFrame
    local arena = config.Arena
    return CFrame.new(arena.CenterX, arena.PlatformTopY - arena.PlatformThickness / 2, arena.CenterZ)
end

function ArenaService.init(gameConfig: any)
    config = gameConfig
    if model then
        return
    end
    local arena = config.Arena

    local arenaModel = Instance.new("Model")
    arenaModel.Name = "SkyArena"

    local part = Instance.new("Part")
    part.Name = "Platform"
    part.Anchored = true
    part.CanCollide = true
    part.Material = Enum.Material.SmoothPlastic
    part.Color = Color3.fromRGB(70, 78, 96)
    part.TopSurface = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
    part.Size = Vector3.new(arena.InitialSize, arena.PlatformThickness, arena.InitialSize)
    part.CFrame = platformCFrame()
    part.Parent = arenaModel

    -- Neon edge outline that follows the platform size (visual only).
    local outline = Instance.new("SelectionBox")
    outline.Name = "EdgeGlow"
    outline.Adornee = part
    outline.LineThickness = 0.15
    outline.Color3 = Color3.fromRGB(0, 230, 255)
    outline.SurfaceTransparency = 1
    outline.Parent = part

    arenaModel.PrimaryPart = part
    arenaModel.Parent = workspace
    model = arenaModel
    platform = part
end

function ArenaService.getPlatform(): Part?
    return platform
end

function ArenaService.resize(size: number, duration: number)
    local part = platform
    if not part then
        return
    end
    if activeTween then
        activeTween:Cancel()
        activeTween = nil
    end
    local goal = { Size = Vector3.new(size, config.Arena.PlatformThickness, size) }
    if duration <= 0 then
        part.Size = goal.Size
        part.CFrame = platformCFrame()
        return
    end
    -- Anchored part, center fixed: collision follows the tween (GDD 3.2).
    local tween = TweenService:Create(part, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal)
    activeTween = tween
    tween.Completed:Once(function()
        if activeTween == tween then
            activeTween = nil
        end
    end)
    tween:Play()
end

function ArenaService.spawnCFrame(size: number, slot: number): CFrame
    local x, y, z = ArenaMath.spawnPosition(config.Arena, size, slot)
    local position = Vector3.new(x, y, z)
    local center = Vector3.new(config.Arena.CenterX, y, config.Arena.CenterZ)
    return CFrame.lookAt(position, center)
end

function ArenaService.destroy()
    if activeTween then
        activeTween:Cancel()
        activeTween = nil
    end
    if model then
        model:Destroy()
    end
    model = nil
    platform = nil
end

return ArenaService

--!strict
-- RoboPush Arena / CharacterService.lua
-- R15 robot spawning, symmetric team colors, freeze during countdown and the
-- spawn-protection visual (GDD 4, ARCHITECTURE 6). Native Roblox movement is
-- kept; only WalkSpeed / jump are configured.
--
-- Interface
--   CharacterService.init(config)
--   CharacterService.spawn(player, cframe, slot) -> (Model?, Humanoid?, BasePart?)  -- yields
--   CharacterService.setFrozen(player, frozen)
--   CharacterService.showProtection(character, seconds)
--   CharacterService.getParts(player) -> (Humanoid?, BasePart?)
-- Caller (MatchService) is responsible for serialising spawns per player.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")

local CharacterService = {}

local config: any = nil

-- Max seconds to wait for R15 parts after LoadCharacter (diagnostic safety net).
local PART_WAIT_SECONDS = 5

function CharacterService.init(gameConfig: any)
    config = gameConfig
    -- MatchService decides when robots spawn (respawn delay, symmetric points).
    Players.CharacterAutoLoads = false
end

local function slotColor(slot: number): Color3
    local entry = config.Robot.SlotColors[slot] or config.Robot.SlotColors[1]
    local rgb = entry.Color
    return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

-- Cosmetic only: BodyColors + outline Highlight. Hitbox and mass unchanged.
local function applyLook(character: Model, slot: number)
    local color = slotColor(slot)
    local bodyColors = character:FindFirstChildOfClass("BodyColors")
    if not bodyColors then
        bodyColors = Instance.new("BodyColors")
        bodyColors.Parent = character
    end
    local bc = bodyColors :: BodyColors
    bc.HeadColor3 = Color3.fromRGB(235, 235, 240)
    bc.TorsoColor3 = color
    bc.LeftArmColor3 = color
    bc.RightArmColor3 = color
    bc.LeftLegColor3 = Color3.fromRGB(40, 40, 48)
    bc.RightLegColor3 = Color3.fromRGB(40, 40, 48)

    local highlight = Instance.new("Highlight")
    highlight.Name = "TeamOutline"
    highlight.FillTransparency = 1
    highlight.OutlineColor = color
    highlight.DepthMode = Enum.HighlightDepthMode.Occluded
    highlight.Parent = character
end

local function configureHumanoid(humanoid: Humanoid)
    humanoid.WalkSpeed = config.Robot.WalkSpeed
    humanoid.UseJumpPower = true
    if not config.Robot.JumpEnabled then
        humanoid.JumpPower = 0
        -- Server-side state toggle; the client mirrors it in InputController.
        humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
    end
    -- Falls are scored by height, not by damage.
    humanoid.BreakJointsOnDeath = false
end

function CharacterService.getParts(player: Player): (Humanoid?, BasePart?)
    local character = player.Character
    if not character then
        return nil, nil
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    return humanoid, if root and root:IsA("BasePart") then root else nil
end

function CharacterService.spawn(player: Player, cframe: CFrame, slot: number): (Model?, Humanoid?, BasePart?)
    if player.Parent ~= Players then
        return nil, nil, nil
    end
    local ok, err = pcall(function()
        player:LoadCharacter()
    end)
    if not ok then
        warn("[RoboPush] LoadCharacter failed:", err)
        return nil, nil, nil
    end
    local character = player.Character
    if not character then
        return nil, nil, nil
    end
    local humanoid = character:WaitForChild("Humanoid", PART_WAIT_SECONDS)
    local root = character:WaitForChild("HumanoidRootPart", PART_WAIT_SECONDS)
    if not (humanoid and humanoid:IsA("Humanoid") and root and root:IsA("BasePart")) then
        warn("[RoboPush] character missing Humanoid/HumanoidRootPart for", player.Name)
        return nil, nil, nil
    end
    configureHumanoid(humanoid)
    applyLook(character, slot)
    character:PivotTo(cframe)
    return character, humanoid, root
end

function CharacterService.setFrozen(player: Player, frozen: boolean)
    local humanoid = CharacterService.getParts(player)
    if humanoid then
        humanoid.WalkSpeed = if frozen then 0 else config.Robot.WalkSpeed
    end
end

-- Visible ForceField during spawn protection; gameplay immunity itself is
-- enforced by MatchModel.isProtected, not by the ForceField.
function CharacterService.showProtection(character: Model, seconds: number)
    local field = Instance.new("ForceField")
    field.Visible = true
    field.Parent = character
    Debris:AddItem(field, seconds)
end

return CharacterService

--!strict
-- RoboPush Arena / CombatState.lua
-- Pure per-player combat bookkeeping: selected skill, cooldowns, shield
-- window, knockback resistance and the currently active move. Time is
-- injected. CombatService owns one instance and clears players on leave,
-- respawn and match reset.

local CombatRules = require(script.Parent:WaitForChild("CombatRules"))

type PlayerRecord = {
    selectedSkill: string,
    readyAt: { [string]: number }, -- "dash" or skillId -> server time
    shieldUntil: number,
    resistUntil: number,
    busyUntil: number, -- an active dash / special blocks starting another move
}

local CombatState = {}
CombatState.__index = CombatState

export type CombatState = typeof(setmetatable({} :: { config: any, players: { [number]: PlayerRecord } }, CombatState))

CombatState.DASH_KEY = "dash"

function CombatState.new(config: any): CombatState
    return setmetatable({ config = config, players = {} }, CombatState)
end

function CombatState._record(self: CombatState, userId: number): PlayerRecord
    local record = self.players[userId]
    if not record then
        record = {
            selectedSkill = self.config.Skills.DefaultSelection,
            readyAt = {},
            shieldUntil = -math.huge,
            resistUntil = -math.huge,
            busyUntil = -math.huge,
        }
        self.players[userId] = record
    end
    return record
end

function CombatState.getSelected(self: CombatState, userId: number): string
    return self:_record(userId).selectedSkill
end

function CombatState.readyAt(self: CombatState, userId: number, key: string): number
    return self:_record(userId).readyAt[key] or -math.huge
end

-- Skill choice; the caller passes whether the match state allows selection.
function CombatState.selectSkill(self: CombatState, userId: number, skillId: any, selectionOpen: boolean): (boolean, string?)
    if not selectionOpen then
        return false, "selection_closed"
    end
    if not CombatRules.isValidSkill(self.config, skillId) then
        return false, "invalid_skill"
    end
    self:_record(userId).selectedSkill = skillId
    return true, nil
end

-- Generic cooldown gate. Writes the cooldown only when accepted.
function CombatState._tryUse(
    self: CombatState,
    userId: number,
    key: string,
    cooldown: number,
    busyFor: number,
    now: number,
    ignoreBusy: boolean?
): (boolean, string?)
    local record = self:_record(userId)
    if now < (record.readyAt[key] or -math.huge) then
        return false, "cooldown"
    end
    if not ignoreBusy and now < record.busyUntil then
        return false, "busy"
    end
    record.readyAt[key] = now + cooldown
    record.busyUntil = math.max(record.busyUntil, now + busyFor)
    return true, nil
end

function CombatState.tryUseDash(self: CombatState, userId: number, now: number): (boolean, string?)
    local dash = self.config.Dash
    return self:_tryUse(userId, CombatState.DASH_KEY, dash.Cooldown, dash.Duration, now)
end

-- `skillId` must equal the player's selected skill (ARCHITECTURE 3).
function CombatState.tryUseSpecial(self: CombatState, userId: number, skillId: any, now: number): (boolean, string?)
    if not CombatRules.isValidSkill(self.config, skillId) then
        return false, "invalid_skill"
    end
    local record = self:_record(userId)
    if record.selectedSkill ~= skillId then
        return false, "not_selected"
    end
    local skill = self.config.Skills[skillId]
    local busyFor = skill.BusyTime or skill.Duration or skill.Startup or 0
    if skillId == "counter_shield" then
        busyFor = 0 -- shielding does not lock movement or dash
    end
    local ok, err = self:_tryUse(userId, skillId, skill.Cooldown, busyFor, now, skill.IgnoreBusy)
    if ok and skillId == "counter_shield" then
        record.shieldUntil = now + skill.ActiveDuration
    end
    return ok, err
end

function CombatState.isShieldActive(self: CombatState, userId: number, now: number): boolean
    return now < self:_record(userId).shieldUntil
end

-- A shield absorbs exactly one impact, then ends (ARCHITECTURE 4).
function CombatState.consumeShield(self: CombatState, userId: number, now: number): boolean
    local record = self:_record(userId)
    if now < record.shieldUntil then
        record.shieldUntil = -math.huge
        return true
    end
    return false
end

function CombatState.canBeKnockedBack(self: CombatState, userId: number, now: number): boolean
    return now >= self:_record(userId).resistUntil
end

-- Call after a knockback is applied to start the anti-chain window (GDD 6.1).
function CombatState.markKnockedBack(self: CombatState, userId: number, now: number)
    self:_record(userId).resistUntil = now + self.config.Dash.KnockbackResistSeconds
end

-- New life: drop transient windows, keep cooldowns and skill choice.
function CombatState.onRespawn(self: CombatState, userId: number)
    local record = self:_record(userId)
    record.shieldUntil = -math.huge
    record.resistUntil = -math.huge
    record.busyUntil = -math.huge
end

-- New match: clear cooldowns and windows, keep skill choice.
function CombatState.onMatchReset(self: CombatState)
    for _, record in self.players do
        record.readyAt = {}
        record.shieldUntil = -math.huge
        record.resistUntil = -math.huge
        record.busyUntil = -math.huge
    end
end

function CombatState.removePlayer(self: CombatState, userId: number)
    self.players[userId] = nil
end

return CombatState

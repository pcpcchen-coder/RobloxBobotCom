--!nocheck
-- Unit tests for CombatRules / CombatState (logic layer of T03, T11, T15,
-- T16, T17, T18, T22). Physics, network ownership and feel need Studio.

local GameConfig = shared("GameConfig")
local CombatRules = server("Logic/CombatRules")
local CombatState = server("Logic/CombatState")

local A, B = 1, 2
local Dash = GameConfig.Dash

return function(t)
    t.test("T03 dash cooldown: at most one accepted dash per 4s", function()
        local combat = CombatState.new(GameConfig)
        expect.truthy(combat:tryUseDash(A, 0), "first dash")
        local accepted = 0
        for i = 1, 40 do
            if combat:tryUseDash(A, i * 0.099) then
                accepted += 1
            end
        end
        expect.eq(accepted, 0, "no dash within cooldown")
        expect.eq(combat:readyAt(A, "dash"), Dash.Cooldown, "readyAt")
        expect.truthy(combat:tryUseDash(A, Dash.Cooldown), "dash after cooldown")
    end)

    t.test("special must match the selected skill and respects its cooldown", function()
        local combat = CombatState.new(GameConfig)
        expect.eq(combat:getSelected(A), GameConfig.Skills.DefaultSelection, "default skill")
        local ok, err = combat:tryUseSpecial(A, "side_burst", 0)
        expect.falsy(ok, "not selected")
        expect.eq(err, "not_selected", "reason")
        expect.truthy(combat:tryUseSpecial(A, "rocket_pop", 0), "rocket pop")
        local again, why = combat:tryUseSpecial(A, "rocket_pop", 1)
        expect.falsy(again, "cooldown")
        expect.eq(why, "cooldown", "reason")
        expect.truthy(combat:tryUseSpecial(A, "rocket_pop", GameConfig.Skills.rocket_pop.Cooldown), "after CD")
    end)

    t.test("dash and special have independent cooldowns but cannot overlap moves", function()
        local combat = CombatState.new(GameConfig)
        combat:selectSkill(A, "side_burst", true)
        expect.truthy(combat:tryUseDash(A, 0), "dash")
        local ok, err = combat:tryUseSpecial(A, "side_burst", 0.1)
        expect.falsy(ok, "busy during dash")
        expect.eq(err, "busy", "reason")
        expect.truthy(combat:tryUseSpecial(A, "side_burst", Dash.Duration), "after dash ends")
    end)

    t.test("skill selection only when open and only MVP skills (T22)", function()
        local combat = CombatState.new(GameConfig)
        expect.falsy(combat:selectSkill(A, "side_burst", false), "closed during combat")
        expect.falsy(combat:selectSkill(A, "ground_slam", true), "non-MVP skill rejected")
        expect.falsy(combat:selectSkill(A, 12345, true), "non-string rejected")
        expect.falsy(combat:selectSkill(A, string.rep("x", 200), true), "oversized rejected")
        expect.truthy(combat:selectSkill(A, "counter_shield", true), "valid")
        expect.eq(combat:getSelected(A), "counter_shield", "selected")
    end)

    t.test("T18 shield: active 0.6s, absorbs one impact, expired shield does nothing", function()
        local combat = CombatState.new(GameConfig)
        combat:selectSkill(B, "counter_shield", true)
        expect.truthy(combat:tryUseSpecial(B, "counter_shield", 10), "shield up")
        expect.truthy(combat:isShieldActive(B, 10.5), "active inside window")
        expect.eq(CombatRules.resolveImpact(true, combat:isShieldActive(B, 10.5)), "rebound", "ram rebounds")
        expect.truthy(combat:consumeShield(B, 10.5), "consumed")
        expect.falsy(combat:isShieldActive(B, 10.55), "single use")
        combat.players[B].readyAt = {}
        combat:tryUseSpecial(B, "counter_shield", 20)
        expect.falsy(combat:isShieldActive(B, 20 + GameConfig.Skills.counter_shield.ActiveDuration), "expired")
        expect.eq(CombatRules.resolveImpact(true, false), "hit", "expired -> normal hit")
        expect.eq(CombatRules.resolveImpact(false, true), "blocked", "shockwave blocked, no rebound")
    end)

    t.test("knockback resistance prevents infinite chains", function()
        local combat = CombatState.new(GameConfig)
        expect.truthy(combat:canBeKnockedBack(B, 0), "initially")
        combat:markKnockedBack(B, 0)
        expect.falsy(combat:canBeKnockedBack(B, Dash.KnockbackResistSeconds - 0.01), "resisting")
        expect.truthy(combat:canBeKnockedBack(B, Dash.KnockbackResistSeconds), "after window")
    end)

    t.test("respawn clears windows but keeps cooldowns; match reset clears cooldowns", function()
        local combat = CombatState.new(GameConfig)
        combat:selectSkill(A, "counter_shield", true)
        combat:tryUseSpecial(A, "counter_shield", 0)
        combat:onRespawn(A)
        expect.falsy(combat:isShieldActive(A, 0.1), "shield cleared")
        expect.falsy(combat:tryUseSpecial(A, "counter_shield", 1), "cooldown kept")
        combat:onMatchReset()
        expect.truthy(combat:tryUseSpecial(A, "counter_shield", 1), "cooldown reset")
        expect.eq(combat:getSelected(A), "counter_shield", "selection kept")
    end)

    t.test("dash front arc: 120 deg, 5 studs, height limit", function()
        local function hit(tx, ty, tz)
            return CombatRules.isInFrontArc(0, 0, 0, 0, -1, tx, ty, tz, Dash.HitRadius, Dash.FrontArcDegrees, Dash.MaxHeightDifference)
        end
        expect.truthy(hit(0, 0, -4), "straight ahead")
        expect.truthy(hit(math.sin(math.rad(59)) * 4, 0, -math.cos(math.rad(59)) * 4), "59 deg")
        expect.falsy(hit(math.sin(math.rad(61)) * 4, 0, -math.cos(math.rad(61)) * 4), "61 deg")
        expect.falsy(hit(0, 0, 4), "behind")
        expect.falsy(hit(0, 0, -5.1), "too far")
        expect.falsy(hit(0, Dash.MaxHeightDifference + 0.1, -2), "too high")
        expect.truthy(hit(0, 0, 0), "overlapping")
    end)

    t.test("T16 rocket pop radius: inside 5 studs hits, outside does not", function()
        local rp = GameConfig.Skills.rocket_pop
        expect.truthy(CombatRules.isInRadius(0, 0, 0, 3, 0, 4, rp.HitRadius, rp.MaxHeightDifference), "5 studs")
        expect.falsy(CombatRules.isInRadius(0, 0, 0, 3.1, 0, 4, rp.HitRadius, rp.MaxHeightDifference), "just outside")
    end)

    t.test("knockback direction pushes away from source with configured magnitudes", function()
        local vx, vy, vz = CombatRules.knockbackVelocity(0, 0, 3, 4, 0, -1, Dash.KnockbackHorizontal, Dash.KnockbackVertical)
        expect.near(vx, 0.6 * Dash.KnockbackHorizontal, 1e-9, "vx")
        expect.near(vz, 0.8 * Dash.KnockbackHorizontal, 1e-9, "vz")
        expect.eq(vy, Dash.KnockbackVertical, "vy")
        local fx, _, fz = CombatRules.knockbackVelocity(1, 1, 1, 1, 0, -1, 10, 0)
        expect.near(fx, 0, 1e-9, "fallback x")
        expect.near(fz, -10, 1e-9, "fallback z")
    end)

    t.test("T17 side burst side selection from movement hint", function()
        -- character faces -Z, right vector is +X
        expect.eq(CombatRules.chooseSide(1, 0, 1, 0, 1), 1, "right input")
        expect.eq(CombatRules.chooseSide(1, 0, -1, 0, 1), -1, "left input")
        expect.eq(CombatRules.chooseSide(1, 0, 0, -1, 1), 1, "forward only -> default right")
        expect.eq(CombatRules.chooseSide(1, 0, nil, nil, -1), -1, "no hint -> configured default")
    end)

    t.test("T22 direction hint validation rejects NaN, inf and oversized vectors", function()
        expect.truthy(CombatRules.isValidHint(GameConfig, 1, 0, 0), "unit")
        expect.truthy(CombatRules.isValidHint(GameConfig, 0, 0, 0), "zero")
        expect.falsy(CombatRules.isValidHint(GameConfig, 0 / 0, 0, 0), "NaN")
        expect.falsy(CombatRules.isValidHint(GameConfig, math.huge, 0, 0), "inf")
        expect.falsy(CombatRules.isValidHint(GameConfig, 100, 0, 0), "teleport-sized")
        expect.falsy(CombatRules.isValidHint(GameConfig, "1", 0, 0), "string")
    end)

    t.test("T11 rate limiter caps request floods", function()
        local limiter = CombatRules.RateLimiter.new(GameConfig.Net.MaxRequestsPerSecond, GameConfig.Net.BurstRequests)
        local allowed = 0
        for _ = 1, 100 do
            if limiter:allow(A, 0) then
                allowed += 1
            end
        end
        expect.eq(allowed, GameConfig.Net.BurstRequests, "burst only")
        expect.truthy(limiter:allow(A, 1), "refills over time")
        expect.truthy(limiter:allow(B, 0), "per player buckets")
    end)
end

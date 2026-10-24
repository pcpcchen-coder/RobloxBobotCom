--!nocheck
-- GameConfig sanity + ArenaMath (logic layer of T08) + spec values that the
-- docs (GDD / SKILLS) state explicitly. If a doc value changes, update both.

local GameConfig = shared("GameConfig")
local ArenaMath = shared("ArenaMath")
local GameTypes = shared("GameTypes")
local Arena = GameConfig.Arena

return function(t)
    t.test("documented MVP values match GDD/SKILLS", function()
        expect.eq(GameConfig.Match.MaxPlayers, 2, "1v1")
        expect.eq(GameConfig.Match.Countdown, 3, "countdown")
        expect.eq(GameConfig.Match.Duration, 120, "duration")
        expect.eq(GameConfig.Match.ScoreToWin, 3, "score to win")
        expect.eq(GameConfig.Match.SuddenDeath, 20, "sudden death")
        expect.eq(GameConfig.Match.RespawnDelay, 2, "respawn")
        expect.eq(GameConfig.Match.SpawnProtection, 1.5, "protection")
        expect.eq(GameConfig.Dash.Cooldown, 4, "dash cd")
        expect.eq(GameConfig.Dash.Duration, 0.25, "dash duration")
        expect.eq(GameConfig.Dash.Speed, 40, "dash speed")
        expect.eq(GameConfig.Skills.rocket_pop.Cooldown, 8, "rocket cd")
        expect.eq(GameConfig.Skills.side_burst.Cooldown, 7, "side cd")
        expect.eq(GameConfig.Skills.counter_shield.Cooldown, 12, "shield cd")
        expect.eq(GameConfig.Skills.counter_shield.ActiveDuration, 0.6, "shield window")
        expect.eq(Arena.InitialSize, 48, "arena")
        expect.eq(Arena.SuddenDeathSize, 18, "sd arena")
        expect.eq(Arena.FallHeight, 8, "fall height")
    end)

    t.test("all seven designed skills are selectable with SKILLS cooldowns", function()
        expect.eq(GameConfig.Skills.Selectable, {
            "rocket_pop",
            "ground_slam",
            "side_burst",
            "magnet_pull",
            "counter_shield",
            "phantom_brake",
            "rescue_claw",
        }, "selectable list")
        local cooldowns = {
            rocket_pop = 8,
            ground_slam = 10,
            side_burst = 7,
            magnet_pull = 11,
            counter_shield = 12,
            phantom_brake = 6,
            rescue_claw = 15,
        }
        for id, cd in cooldowns do
            expect.eq(GameConfig.Skills[id].Cooldown, cd, id .. " cooldown")
            expect.truthy(GameConfig.Skills[id].Name, id .. " name")
        end
        expect.eq(GameConfig.Skills.ground_slam.HitRadius, 7, "slam radius")
        expect.eq(GameConfig.Skills.magnet_pull.Range, 11, "magnet range")
        expect.truthy(table.find(GameConfig.Skills.Selectable, GameConfig.Skills.DefaultSelection), "default selectable")
    end)

    t.test("edgeDistance / clampInside (Rescue Claw geometry)", function()
        expect.eq(ArenaMath.edgeDistance(Arena, 48, 0, 0), 24, "center")
        expect.eq(ArenaMath.edgeDistance(Arena, 48, 22, 0), 2, "near edge")
        expect.eq(ArenaMath.edgeDistance(Arena, 48, 26, 0), -2, "outside")
        local x, z = ArenaMath.clampInside(Arena, 24, 30, -5, 4)
        expect.eq(x, 8, "clamped x")
        expect.eq(z, -5, "z unchanged")
        expect.truthy(ArenaMath.edgeDistance(Arena, 24, x, z) >= 4 - 1e-9, "at least inset inside")
    end)

    t.test("shrink steps are ordered and shrinking", function()
        local lastTime, lastSize = 0, Arena.InitialSize
        for _, step in Arena.ShrinkSteps do
            expect.truthy(step.Time > lastTime, "time ascending")
            expect.truthy(step.Size < lastSize, "size descending")
            expect.truthy(step.Time - Arena.ShrinkWarning > lastTime, "warning after previous step")
            lastTime, lastSize = step.Time, step.Size
        end
        expect.truthy(lastTime < GameConfig.Match.Duration, "all steps inside regulation")
        expect.truthy(Arena.SuddenDeathSize < lastSize, "sudden death is smallest")
    end)

    t.test("sizeAtElapsed follows the schedule", function()
        expect.eq(ArenaMath.sizeAtElapsed(Arena, 0), 48, "0s")
        expect.eq(ArenaMath.sizeAtElapsed(Arena, 44.9), 48, "44.9s")
        expect.eq(ArenaMath.sizeAtElapsed(Arena, 45), 36, "45s")
        expect.eq(ArenaMath.sizeAtElapsed(Arena, 90), 24, "90s")
    end)

    t.test("T08 spawn points stay inside every platform size with margin", function()
        for _, size in { 48, 36, 24, 18 } do
            for slot = 1, 2 do
                local x, y, z = ArenaMath.spawnPosition(Arena, size, slot)
                expect.truthy(ArenaMath.isOverPlatform(Arena, size, x, z), "inside at size " .. size)
                local margin = size / 2 - math.abs(x - Arena.CenterX)
                expect.truthy(margin >= size / 4 - 1e-9, "edge margin >= size/4 at " .. size)
                expect.truthy(not ArenaMath.isFallen(Arena, y), "spawn not below fall height")
            end
            local x1 = ArenaMath.spawnPosition(Arena, size, 1)
            local x2 = ArenaMath.spawnPosition(Arena, size, 2)
            expect.near(x1 + x2, 2 * Arena.CenterX, 1e-9, "symmetric")
        end
        expect.eq(ArenaMath.spawnOffset(Arena, 48), 12, "initial offset 12")
        expect.eq(ArenaMath.spawnOffset(Arena, 18), 4.5, "sudden death offset")
    end)

    t.test("fall threshold is strict (Y < 8)", function()
        expect.falsy(ArenaMath.isFallen(Arena, 8), "8 is not fallen")
        expect.truthy(ArenaMath.isFallen(Arena, 7.99), "below")
    end)

    t.test("state helpers", function()
        expect.truthy(GameTypes.isCombatState("RUNNING"), "running")
        expect.truthy(GameTypes.isCombatState("SUDDEN_DEATH"), "sd")
        expect.falsy(GameTypes.isCombatState("COUNTDOWN"), "countdown")
        expect.truthy(GameTypes.isSkillSelectState("WAITING"), "waiting select")
        expect.falsy(GameTypes.isSkillSelectState("RUNNING"), "running select")
    end)
end

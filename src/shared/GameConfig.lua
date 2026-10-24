--!strict
-- RoboPush Arena / GameConfig.lua
-- Single source of truth for gameplay numbers (AGENTS.md rule 4).
-- Tunable starting values ONLY. Verify under real two-client physics tests;
-- values marked "placeholder" were not specified by GDD/SKILLS and need tuning.
-- Units: seconds, studs, studs/s.

local GameConfig = {
    Match = {
        MaxPlayers = 2,
        Countdown = 3,
        Duration = 120,
        ScoreToWin = 3,
        SuddenDeath = 20,
        RespawnDelay = 2,
        SpawnProtection = 1.5,
        -- Simultaneous-fall grouping; calibrate before production.
        DoubleFallWindow = 0.10,
        -- RESULT screen length before the next COUNTDOWN/WAITING (placeholder).
        ResultDuration = 6,
    },

    Robot = {
        WalkSpeed = 16,
        JumpEnabled = false,
        -- Team colors are cosmetic only; never change hitbox or stats.
        SlotColors = {
            { Name = "Blue Bot", Color = { 40, 120, 255 } },
            { Name = "Orange Bot", Color = { 255, 140, 30 } },
        },
    },

    Dash = {
        Cooldown = 4,
        Duration = 0.25,
        Speed = 40,
        HitRadius = 5,
        FrontArcDegrees = 120,
        -- "Reasonable height difference" from GDD 6.1 (placeholder).
        MaxHeightDifference = 4,
        KnockbackHorizontal = 42,
        KnockbackVertical = 12,
        KnockbackResistSeconds = 0.4,
        MaxHitsPerTargetPerUse = 1,
    },

    Arena = {
        InitialSize = 48,
        CenterX = 0,
        CenterZ = 0,
        PlatformTopY = 20,
        PlatformThickness = 2,
        FallHeight = 8,
        ShrinkWarning = 5,
        ShrinkDuration = 2,
        ShrinkSteps = {
            { Time = 45, Size = 36 },
            { Time = 90, Size = 24 },
        },
        SuddenDeathSize = 18,
        -- Spawn offset from center on X axis = min(SpawnOffsetMax, size / SpawnOffsetDivisor).
        SpawnOffsetMax = 12,
        SpawnOffsetDivisor = 4,
        -- HumanoidRootPart height above the platform top when spawning (R15 ~3).
        SpawnHeightAboveTop = 3,
    },

    Physics = {
        -- Server takes network ownership of a knocked-back robot so the impulse is
        -- authoritative, then hands it back. Needs two-client tuning (T04).
        KnockbackOwnershipSeconds = 0.5,
        -- Max force for self-motion LinearVelocity (dash / side burst / rocket launch).
        MotionMaxForce = 1e6,
    },

    Net = {
        -- Token bucket per player across all combat requests.
        MaxRequestsPerSecond = 6,
        BurstRequests = 6,
        -- Client direction hints are unit-ish movement vectors; larger values are rejected.
        MaxDirectionHintMagnitude = 1.05,
        -- Minimum seconds between client-requested MatchSnapshot resyncs.
        SnapshotMinInterval = 1,
    },

    Skills = {
        DefaultSelection = "rocket_pop",
        AvailableInMVP = {
            "rocket_pop",
            "side_burst",
            "counter_shield",
        },

        rocket_pop = {
            Name = "Rocket Pop",
            Cooldown = 8,
            Startup = 0.15,
            HitRadius = 5,
            MaxHeightDifference = 4,
            -- Jump impulse/height requires empirical tuning (placeholders).
            LaunchVerticalSpeed = 45,
            LaunchDuration = 0.2,
            -- Server raycast length below the root to decide "grounded" (no re-cast in air).
            GroundCheckDistance = 4.5,
            KnockbackHorizontal = 42,
            KnockbackVertical = 16,
        },

        ground_slam = {
            Name = "Ground Slam",
            Cooldown = 10,
            HitRadius = 7,
            MVP = false,
        },

        side_burst = {
            Name = "Side Burst",
            Cooldown = 7,
            SideDistance = 7,
            -- SideDistance / Duration = burst speed (placeholder duration).
            Duration = 0.2,
            HitRadius = 4,
            MaxHeightDifference = 4,
            KnockbackHorizontal = 42,
            KnockbackVertical = 12,
            -- 1 = right, -1 = left; used when no side input is given (SKILLS 4).
            DefaultSide = 1,
        },

        magnet_pull = {
            Name = "Magnet Pull",
            Cooldown = 11,
            Range = 11,
            MVP = false,
        },

        counter_shield = {
            Name = "Counter Shield",
            Cooldown = 12,
            ActiveDuration = 0.6,
            -- Rebound applied to the rammer (placeholder; mirrors Dash knockback).
            ReboundHorizontal = 42,
            ReboundVertical = 12,
        },

        phantom_brake = {
            Name = "Phantom Brake",
            Cooldown = 6,
            MVP = false,
        },

        rescue_claw = {
            Name = "Rescue Claw",
            Cooldown = 15,
            MVP = false,
        },
    },
}

return GameConfig

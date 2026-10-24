--!strict
-- RoboPush Arena / GameConfig.lua
-- Design-time baseline; not yet wired to a Roblox Studio game.
-- Tunable starting values ONLY. Verify under real two-client physics tests.

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
    },

    Robot = {
        WalkSpeed = 16,
        JumpEnabled = false,
    },

    Dash = {
        Cooldown = 4,
        Duration = 0.25,
        Speed = 40,
        HitRadius = 5,
        FrontArcDegrees = 120,
        KnockbackHorizontal = 42,
        KnockbackVertical = 12,
        KnockbackResistSeconds = 0.4,
        MaxHitsPerTargetPerUse = 1,
    },

    Arena = {
        InitialSize = 48,
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
            -- Jump impulse/height requires empirical tuning.
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

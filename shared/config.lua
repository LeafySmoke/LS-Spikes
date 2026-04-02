Config = {}

Config.Debug = false
Config.JobWhitelist = { "sahp", "bcso", "sast", "police", "sheriff", "lspd" }

Config.MaxStripsPerOfficer = 1
Config.CordMaxDistance = 30.0 -- Distance before cord "snaps"
Config.GroundClearance = 0.03 -- Small vertical lift to reduce terrain clipping
Config.PullSpeed = 0.05 -- Movement per tick while pulling (higher = faster)
Config.PullFollowDistance = 2.8 -- Keep strip this far from player while pulling to avoid collision-launch glitches
Config.PullDisableCollision = true -- During pull, keep world collision enabled and no-collide only with the player
Config.PullControlKey = 38 -- INPUT_CONTEXT (E)
Config.PullRopeVisualWidth = 0.025 -- Visual rope thickness offset when using non-physical rope
Config.PullRopeVisualStrands = 5 -- Number of parallel lines used to draw rope thickness (odd numbers look best)
Config.PullUsePhysicsRope = true -- Uses proxy-anchor physical rope (not directly attached to ped) to avoid teleport snaps
Config.PullRopeType = 4 -- FiveM rope type (4 is a stable default for hand-pull visuals)
Config.PullRopeProxyModel = "prop_beachball_02" -- Invisible local anchor object the rope attaches to near the player's hand
Config.PullRopeProxyHandZOffset = -0.03 -- Vertical offset applied to hand proxy anchor
Config.PullRopeAnchorProxyZOffset = 0.02 -- Vertical offset applied to strip-end proxy anchor
Config.BlockPullThroughVehicles = true -- Prevent strip movement into nearby vehicles while pulling
Config.PullVehicleSafetyRadius = 1.8 -- Meters around the pull target blocked if vehicles are present
Config.PullDistanceLengths = {
    default = 0.75, -- Default target pull distance in strip-lengths
    min = 0.5, -- Smallest target pull distance in strip-lengths
    max = 1.0, -- Largest target pull distance in strip-lengths
    step = 0.05 -- Scroll-wheel step in strip-lengths
}
Config.PlacementPreview = {
    enabled = true,
    useCameraRaycast = true,
    raycastDistance = 12.0,
    raycastFlags = 1 + 16 + 32,
    distanceStep = 0.15,
    headingStep = 3.0,
    headingHoldSpeed = 110.0 -- Degrees/second while holding left/right arrows
}

-- Animation customization
Config.Animations = {
    deploy = {
        dict = "amb@medic@standing@kneel@enter",
        anim = "enter",
        duration = 2500, -- Progress bar duration for deploy
        flag = 49, -- TaskPlayAnim flag
        blendIn = 4.0,
        blendOut = 4.0,
        playbackRate = 0.0,
        canCancel = true,
        loop = false, -- If true and duration > 0, animation task uses duration -1
        progressLabel = "Deploying %s..."
    },
    pickup = {
        dict = "veh@common@motorbike@high@ds",
        anim = "pickup",
        duration = 1500, -- Progress bar duration for pickup
        flag = 49, -- TaskPlayAnim flag
        blendIn = 4.0,
        blendOut = 4.0,
        playbackRate = 0.0,
        canCancel = true,
        loop = false,
        label = "Picking up %s..."
    },
    segmentDeploy = {
        dict = "p_ld_stinger_s",
        anim = "p_stinger_s_deploy",
        speed = 1000.0, -- PlayEntityAnim speed parameter
        loop = false,
        holdLastFrame = false,
        driveToPose = false,
        startPhase = 0.0,
        flags = 0,
        syncTimeline = false, -- true = phase-lock all segments to one timeline
        syncDurationMs = 1800, -- Used when syncTimeline = true
        delayMs = 1000 -- Used when syncTimeline = false
    }
}

Config.PlacementCooldown = 5000 -- ms
Config.BlockPlacementNearVehicles = true -- Prevent confirming placement when vehicles are overlapping the preview strip
Config.PlacementVehicleSafetyRadius = 2.4 -- Meters around each preview segment used for placement vehicle safety checks
Config.PopAllContactingTires = true -- true: pop every tire currently contacting spikes, false: pop only closest contacting tire
Config.LocalImmediatePopOnHit = true -- If local player is driving, apply an immediate local tire burst on contact
Config.ImmediatePopControlTimeoutMs = 120 -- How long to request vehicle network control before local instant pop
Config.TireHitCooldownMs = 1200 -- Per wheel cooldown to prevent re-trigger spam while still touching spikes
Config.TireRetryCooldownMs = 250 -- Short cooldown used when a wheel contact is detected but the tire is still not burst
Config.ServerTireHitCooldownMs = 1800 -- Server-side cooldown for same vehicle/wheel/strip hit key
Config.MinimumSpikeContactSpeed = 0.2 -- m/s; lower value catches near-stop rollovers more reliably
Config.WheelContactPadding = 0.24 -- Expands wheel-vs-strip overlap bounds to reduce edge misses
Config.WheelSweepStep = 0.45 -- Meters between swept wheel samples to catch high-speed pass-through contacts
Config.WheelSweepMaxSamples = 8 -- Maximum swept samples tested per wheel per tick
Config.SpikeScanIntervalMs = 250 -- Idle/on-foot spike rescan interval
Config.SpikeScanIntervalDrivingMs = 75 -- In-vehicle spike rescan interval for faster contact acquisition
Config.SpikeRescanDistance = 1.6 -- Force spike rescan when scan center moved this many meters
Config.DriverHitScanTickMs = 75 -- Main hit-processing loop tick while player is driving
Config.SpikeScanRadius = 16.0 -- Radius around the local player/driver used to gather nearby strip entities
Config.EnableNpcTireBurst = true -- Also process nearby NPC-driven vehicles crossing strips
Config.NpcVehicleScanRadius = 70.0 -- Vehicle scan radius for NPC spike checks
Config.NpcVehicleScanIntervalMs = 450 -- How often nearby NPC vehicles are re-scanned
Config.NpcHitSourceMaxDistance = 85.0 -- Server-side max distance from reporting player to NPC vehicle/strip hit

Config.Deflation = {
    InstantPop = true, -- true = burst tire immediately on contact
    PopDamage = 1000.0, -- Burst force passed to SetVehicleTyreBurst
    Time = 8000, -- Total time to fully deflate (ms)
    SlowdownFactor = 0.8, -- Multiplier for vehicle speed during deflation
    WobbleThreshold = 40.0 -- Speed in MPH/KPH where wobble starts
}

Config.Durability = {
    Enabled = true, -- If true, spikes will have durability and can be damaged/destroyed by vehicles
    Health = 100.0, -- Initial health of spikes
    DamagePerHit = 25.0, -- Damage applied to spikes each time a vehicle contacts them
    MaxTirePops = 12
}

Config.Items = {
    spikestrip = {
        label = "Spike Strip",
        model = "p_ld_stinger_s",
        placementDistance = 2.0,
        headingOffset = 0.0, -- Place in the same direction the player is facing
        freezeOnPlace = true, -- Prevent vehicle impacts from pushing the strip around
        segmentCount = 2, -- Spawn as a dual strip
        segmentSpacing = 2.5,
        hitDistance = 2.4
    }
}


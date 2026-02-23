Config = {}

Config.Debug = false
Config.JobWhitelist = { "police", "sheriff", "state" }

Config.MaxStripsPerOfficer = 3
Config.MaxDurability = 5 -- How many vehicles can hit it before it breaks
Config.CordMaxDistance = 15.0 -- Distance before cord "snaps"
Config.PlacementCooldown = 5000 -- ms

Config.Deflation = {
    Time = 8000, -- Total time to fully deflate (ms)
    SlowdownFactor = 0.8, -- Multiplier for vehicle speed during deflation
    WobbleThreshold = 40.0 -- Speed in MPH/KPH where wobble starts
}

Config.Items = {
    stopstick = {
        label = "Stop Stick",
        model = "p_ld_stoppad_s",
        placementDistance = 1.5,
        headingOffset = 0.0,
        freezeOnPlace = false,
        segmentCount = 1,
        segmentSpacing = 1.5,
        hitDistance = 1.1
    },
    spikestrip = {
        label = "Spike Strip",
        model = "p_ld_stinger_s",
        placementDistance = 2.0,
        headingOffset = 0.0, -- Place in the same direction the player is facing
        freezeOnPlace = true, -- Prevent vehicle impacts from pushing the strip around
        segmentCount = 3, -- Chain segments for a longer strip
        segmentSpacing = 2.5,
        hitDistance = 2.4
    }
}

Config.Animations = {
    Deploy = {
        dict = "amb@medic@standing@kneel@enter",
        anim = "enter"
    }
}
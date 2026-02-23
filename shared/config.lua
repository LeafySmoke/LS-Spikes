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

Config.Models = {
    Spike = "p_ld_stoppad_s", -- Standard GTA spike pad
}

Config.Animations = {
    Deploy = {
        dict = "amb@medic@standing@tendtopat@enter",
        anim = "enter"
    }
}
local QBCore = exports["qb-core"]:GetCoreObject()
local activeStrips = {}
local burstSequence = 0
local burstLogBuffer = {}
local BURST_LOG_WINDOW_MS = 3000
local nextStripId = 1
local stripIdByNetId = {}
local ownerStripCounts = {}

local spikeModelHashes = {}
for _, itemData in pairs(Config.Items or {}) do
    if itemData.model then
        spikeModelHashes[joaat(itemData.model)] = true
    end
end

local WHEEL_CODES = {
    [0] = "LF",
    [1] = "RF",
    [2] = "LM",
    [3] = "RM",
    [4] = "LR",
    [5] = "RR"
}

if type(NetworkHasControlOfEntity) ~= "function" then
    function NetworkHasControlOfEntity(entity)
        return true
    end
end

if type(NetworkRequestControlOfEntity) ~= "function" then
    function NetworkRequestControlOfEntity(entity)
        return false
    end
end

--- Generate a unique ID for each spike strip
local function generateId()
    while activeStrips[nextStripId] do
        nextStripId = nextStripId + 1
    end

    local generated = nextStripId
    nextStripId = nextStripId + 1
    return generated
end

local function isSpikeEntity(entity)
    if entity == 0 or not DoesEntityExist(entity) then return false end
    return spikeModelHashes[GetEntityModel(entity)] == true
end

local function removeStripById(stripId)
    local stripData = activeStrips[stripId]
    if not stripData then return false end

    local removedAny = false
    local groupedNetIds = stripData.netIds or { stripData.netId }
    for _, groupedNetId in ipairs(groupedNetIds) do
        stripIdByNetId[groupedNetId] = nil
        local entity = NetworkGetEntityFromNetworkId(groupedNetId)
        if isSpikeEntity(entity) then
            DeleteEntity(entity)
            removedAny = true
        end
    end

    if stripData.owner then
        ownerStripCounts[stripData.owner] = math.max(0, (ownerStripCounts[stripData.owner] or 1) - 1)
    end

    activeStrips[stripId] = nil
    return removedAny
end

local function isWhitelistedJob(Player)
    if not Player or not Player.PlayerData or not Player.PlayerData.job then return false end

    for _, job in ipairs(Config.JobWhitelist) do
        if Player.PlayerData.job.name == job then
            return true
        end
    end

    return false
end

local function resolveStripIdByNetId(spikeNetId)
    spikeNetId = tonumber(spikeNetId)
    if not spikeNetId or spikeNetId <= 0 then return nil end

    local mapped = stripIdByNetId[spikeNetId]
    if mapped and activeStrips[mapped] then
        return mapped
    end

    for stripId, stripData in pairs(activeStrips) do
        if stripData.netId == spikeNetId then
            stripIdByNetId[spikeNetId] = stripId
            return stripId
        end

        if type(stripData.netIds) == "table" then
            for _, groupedNetId in ipairs(stripData.netIds) do
                if groupedNetId == spikeNetId then
                    stripIdByNetId[spikeNetId] = stripId
                    return stripId
                end
            end
        end
    end

    return nil
end

local function getWheelCode(wheelIndex)
    return WHEEL_CODES[tonumber(wheelIndex)] or tostring(wheelIndex)
end

local function queuePopDebugLog(vehicleNetId, stripId, wheelIndex)
    local key = ("%s:%s"):format(vehicleNetId, stripId)
    local wheelCode = getWheelCode(wheelIndex)
    local entry = burstLogBuffer[key]

    if not entry then
        entry = {
            wheels = {},
            wheelSet = {}
        }
        burstLogBuffer[key] = entry

        SetTimeout(BURST_LOG_WINDOW_MS, function()
            local flushEntry = burstLogBuffer[key]
            if not flushEntry then return end

            local count = #flushEntry.wheels
            local wheelList = table.concat(flushEntry.wheels, ",")
            print(("Pop: %d [%s]"):format(count, wheelList))

            burstLogBuffer[key] = nil
        end)
    end

    if not entry.wheelSet[wheelCode] then
        entry.wheelSet[wheelCode] = true
        entry.wheels[#entry.wheels + 1] = wheelCode
    end
end

--- Validates if a player can deploy
local function canDeploy(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end

    if not isWhitelistedJob(Player) then return false end

    local currentCount = ownerStripCounts[Player.PlayerData.citizenid] or 0
    return currentCount < Config.MaxStripsPerOfficer
end

QBCore.Functions.CreateUseableItem("stopstick", function(source, item)
    if canDeploy(source) then
        TriggerClientEvent("ls_spikes:client:deploy", source, "stopstick")
    else
        TriggerClientEvent("ox_lib:notify", source, {
            title = "Deployment Failed",
            description = "You cannot deploy more Stop Sticks or lack permission.",
            type = "error"
        })
    end
end)

QBCore.Functions.CreateUseableItem("spikestrip", function(source, item)
    if canDeploy(source) then
        TriggerClientEvent("ls_spikes:client:deploy", source, "spikestrip")
    else
        TriggerClientEvent("ox_lib:notify", source, {
            title = "Deployment Failed",
            description = "You cannot deploy more Spike Strips or lack permission.",
            type = "error"
        })
    end
end)

RegisterNetEvent("ls_spikes:server:registerStrip", function(netIds, coords, itemName)
    local src = tonumber(source)
    if not src or src <= 0 then return end

    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    if not canDeploy(src) then
        TriggerClientEvent("ox_lib:notify", src, {
            title = "Deployment Failed",
            description = "You cannot deploy more spike strips or lack permission.",
            type = "error"
        })
        return
    end

    if not Config.Items[itemName] then
        itemName = "stopstick"
    end

    local resolvedNetIds = {}
    if type(netIds) == "table" then
        for _, id in ipairs(netIds) do
            local netId = tonumber(id)
            if netId and netId > 0 then
                resolvedNetIds[#resolvedNetIds + 1] = netId
            end
        end
    else
        local netId = tonumber(netIds)
        if netId and netId > 0 then
            resolvedNetIds[#resolvedNetIds + 1] = netId
        end
    end

    if #resolvedNetIds == 0 then return end

    local removedItem = Player.Functions.RemoveItem(itemName, 1)
    if not removedItem then
        for _, netId in ipairs(resolvedNetIds) do
            local entity = NetworkGetEntityFromNetworkId(netId)
            if isSpikeEntity(entity) then
                DeleteEntity(entity)
            end
        end

        TriggerClientEvent("ox_lib:notify", src, {
            title = "Deployment Failed",
            description = "Missing required spike strip item.",
            type = "error"
        })
        return
    end

    if QBCore.Shared and QBCore.Shared.Items and QBCore.Shared.Items[itemName] then
        TriggerClientEvent("inventory:client:ItemBox", src, QBCore.Shared.Items[itemName], "remove")
    end

    local stripId = generateId()
    local maxPops = (Config.Durability and tonumber(Config.Durability.MaxTirePops)) or 12
    activeStrips[stripId] = {
        netId = resolvedNetIds[1],
        netIds = resolvedNetIds,
        owner = Player.PlayerData.citizenid,
        ownerSrc = src,
        coords = coords,
        itemName = itemName,
        isPrimary = true,
        popCount = 0,
        maxPops = math.max(1, maxPops),
        triggeredWheels = {}
    }

    ownerStripCounts[Player.PlayerData.citizenid] = (ownerStripCounts[Player.PlayerData.citizenid] or 0) + 1

    for index, netId in ipairs(resolvedNetIds) do
        stripIdByNetId[netId] = stripId
        local entity = NetworkGetEntityFromNetworkId(netId)
        if entity ~= 0 and DoesEntityExist(entity) then
            Entity(entity).state:set("stripData", {
                id = stripId,
                itemName = itemName,
                isPrimary = index == 1
            }, true)
        end
    end
end)

RegisterNetEvent("ls_spikes:server:syncPull", function(netId, newCoords)
    return
end)

RegisterNetEvent("ls_spikes:server:onHit", function(stripId, vehicleNetId, wheelIndex, spikeNetId)
    local src = tonumber(source)
    if not src or src <= 0 then return end

    if not activeStrips[stripId] then
        stripId = resolveStripIdByNetId(spikeNetId)
    end

    if not activeStrips[stripId] then return end

    local vehicleEntity = NetworkGetEntityFromNetworkId(vehicleNetId)
    if vehicleEntity == 0 or not DoesEntityExist(vehicleEntity) then return end

    local playerPed = GetPlayerPed(src)
    if playerPed == 0 then return end

    wheelIndex = tonumber(wheelIndex)
    if not wheelIndex or wheelIndex < 0 or wheelIndex > 5 then return end

    local driverPed = GetPedInVehicleSeat(vehicleEntity, -1)
    local playerVehicle = GetVehiclePedIsIn(playerPed, false)
    local driverIsPlayer = driverPed ~= 0 and IsPedAPlayer(driverPed)

    if driverIsPlayer then
        if playerVehicle ~= vehicleEntity or driverPed ~= playerPed then
            return
        end
    else
        local maxDistance = tonumber(Config.NpcHitSourceMaxDistance) or 85.0
        local maxDistanceSq = maxDistance * maxDistance
        local playerCoords = GetEntityCoords(playerPed)
        local vehicleCoords = GetEntityCoords(vehicleEntity)

        local dx = playerCoords.x - vehicleCoords.x
        local dy = playerCoords.y - vehicleCoords.y
        local dz = playerCoords.z - vehicleCoords.z
        if (dx * dx + dy * dy + dz * dz) > maxDistanceSq then
            return
        end

        local spikeEntity = NetworkGetEntityFromNetworkId(tonumber(spikeNetId) or 0)
        if spikeEntity ~= 0 and DoesEntityExist(spikeEntity) then
            local spikeCoords = GetEntityCoords(spikeEntity)
            local sx = playerCoords.x - spikeCoords.x
            local sy = playerCoords.y - spikeCoords.y
            local sz = playerCoords.z - spikeCoords.z
            if (sx * sx + sy * sy + sz * sz) > maxDistanceSq then
                return
            end
        end
    end

    local stripData = activeStrips[stripId]
    local hitKey = ("%s:%s"):format(vehicleNetId, wheelIndex)
    stripData.triggeredWheels = stripData.triggeredWheels or {}

    local now = GetGameTimer()
    for key, expiresAt in pairs(stripData.triggeredWheels) do
        if type(expiresAt) ~= "number" or now >= expiresAt then
            stripData.triggeredWheels[key] = nil
        end
    end

    local serverCooldownMs = tonumber(Config.ServerTireHitCooldownMs) or 1800
    local nextAllowed = stripData.triggeredWheels[hitKey] or 0
    if now < nextAllowed then
        return
    end

    stripData.triggeredWheels[hitKey] = now + serverCooldownMs

    burstSequence = burstSequence + 1
    local burstData = {
        seq = burstSequence,
        wheelIndex = wheelIndex,
        stripId = stripId
    }

    Entity(vehicleEntity).state:set("ls_spikes_burst", burstData, true)
end)

RegisterNetEvent("ls_spikes:server:confirmBurst", function(vehicleNetId, seq)
    local vehicleEntity = NetworkGetEntityFromNetworkId(vehicleNetId)
    if vehicleEntity == 0 or not DoesEntityExist(vehicleEntity) then return end

    local pending = Entity(vehicleEntity).state.ls_spikes_burst
    if type(pending) ~= "table" then return end

    if tonumber(pending.seq) ~= tonumber(seq) then return end

    local stripId = tonumber(pending.stripId)
    local wheelIndex = tonumber(pending.wheelIndex)
    local stripData = stripId and activeStrips[stripId] or nil
    if stripData then
        if Config.Durability and Config.Durability.Enabled then
            stripData.popCount = (stripData.popCount or 0) + 1
            if stripData.popCount >= (stripData.maxPops or 12) then
                removeStripById(stripId)
            end
        end

        if wheelIndex then
            queuePopDebugLog(vehicleNetId, stripId, wheelIndex)
        end
    end

    Entity(vehicleEntity).state:set("ls_spikes_burst", false, true)
end)

RegisterNetEvent("ls_spikes:server:pickup", function(stripId, netId)
    local src = source
    if not src or src <= 0 then return end

    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    if not isWhitelistedJob(Player) then
        TriggerClientEvent("ox_lib:notify", src, {
            title = "Pickup Failed",
            description = "You are not authorized to pick up spike strips.",
            type = "error"
        })
        return
    end

    if not activeStrips[stripId] then
        stripId = resolveStripIdByNetId(netId)
    end

    local stripData = activeStrips[stripId]

    if not stripData then
        local fallbackEntity = NetworkGetEntityFromNetworkId(netId)
        if isSpikeEntity(fallbackEntity) then
            DeleteEntity(fallbackEntity)
        end
        return
    end

    local removedAny = removeStripById(stripId)

    if not removedAny then return end

    local itemName = stripData.itemName or "stopstick"
    Player.Functions.AddItem(itemName, 1)

    if QBCore.Shared and QBCore.Shared.Items and QBCore.Shared.Items[itemName] then
        TriggerClientEvent("inventory:client:ItemBox", src, QBCore.Shared.Items[itemName], "add")
    end
end)

lib.callback.register("ls_spikes:server:getStripStatus", function(source, netId)
    local entity = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if entity == 0 or not DoesEntityExist(entity) then
        return { ok = false, message = "Strip not found" }
    end

    if not isSpikeEntity(entity) then
        return { ok = false, message = "Invalid strip entity" }
    end

    local state = Entity(entity).state.stripData
    local stripId = state and state.id
    if not stripId then
        stripId = resolveStripIdByNetId(netId)
    end

    if not stripId then
        return { ok = false, message = "No strip data available" }
    end

    local stripData = activeStrips[stripId]
    if not stripData then
        return { ok = false, message = "Strip is not active" }
    end

    local pops = tonumber(stripData.popCount) or 0
    local maxPops = math.max(1, tonumber(stripData.maxPops) or 12)
    local remaining = math.max(0, maxPops - pops)
    local percent = math.floor((remaining / maxPops) * 100)

    return {
        ok = true,
        title = "Spike Strip Status",
        message = ("Durability: %d%% (%d/%d)"):format(percent, remaining, maxPops)
    }
end)

--- Admin cleanup
lib.addCommand("clearspikes", {
    help = "Remove all active spike strips (Admin Only)",
    restricted = { "group.admin" }
}, function(source, args, raw)
    for id, _ in pairs(activeStrips) do
        removeStripById(id)
    end
    activeStrips = {}
    stripIdByNetId = {}
    ownerStripCounts = {}
    TriggerClientEvent("ox_lib:notify", source, { description = "All spike strips cleared", type = "success" })
end)

AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for id, _ in pairs(activeStrips) do
        removeStripById(id)
    end
end)

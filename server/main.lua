local QBCore = exports["qb-core"]:GetCoreObject()
local activeStrips = {}

--- Generate a unique ID for each spike strip
local function generateId()
    return math.random(10000, 99999)
end

--- Validates if a player can deploy
local function canDeploy(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end

    local isWhitelisted = false
    for _, job in ipairs(Config.JobWhitelist) do
        if Player.PlayerData.job.name == job then
            isWhitelisted = true
            break
        end
    end

    if not isWhitelisted then return false end

    local count = 0
    for _, strip in pairs(activeStrips) do
        if strip.owner == Player.PlayerData.citizenid and strip.isPrimary then
            count = count + 1
        end
    end

    return count < Config.MaxStripsPerOfficer
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

RegisterNetEvent("ls_spikes:server:registerStrip", function(netId, coords, itemName, isPrimary)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    if not Config.Items[itemName] then
        itemName = "stopstick"
    end

    local stripId = generateId()
    activeStrips[stripId] = {
        netId = netId,
        owner = Player.PlayerData.citizenid,
        ownerSrc = src,
        durability = Config.MaxDurability,
        coords = coords,
        itemName = itemName,
        isPrimary = isPrimary == true
    }

    Entity(NetworkGetEntityFromNetworkId(netId)).state:set("stripData", {
        id = stripId,
        durability = Config.MaxDurability,
        itemName = itemName,
        isPrimary = isPrimary == true
    }, true)
end)

RegisterNetEvent("ls_spikes:server:syncPull", function(netId, newCoords)
    local entity = NetworkGetEntityFromNetworkId(netId)
    if DoesEntityExist(entity) then
        SetEntityCoords(entity, newCoords.x, newCoords.y, newCoords.z, false, false, false, false)
    end
end)

RegisterNetEvent("ls_spikes:server:onHit", function(stripId, vehicleNetId)
    local src = source
    if not activeStrips[stripId] then return end

    activeStrips[stripId].durability = activeStrips[stripId].durability - 1
    
    -- Update state bag
    local entity = NetworkGetEntityFromNetworkId(activeStrips[stripId].netId)
    if DoesEntityExist(entity) then
        Entity(entity).state:set("stripData", {
            id = stripId,
            durability = activeStrips[stripId].durability,
            itemName = activeStrips[stripId].itemName,
            isPrimary = activeStrips[stripId].isPrimary
        }, true)

        if activeStrips[stripId].durability <= 0 then
            local ownerSrc = activeStrips[stripId].ownerSrc
            DeleteEntity(entity)
            activeStrips[stripId] = nil
            if ownerSrc and ownerSrc > 0 then
                TriggerClientEvent("ox_lib:notify", ownerSrc, {
                    title = "Stop Stick Destroyed",
                    description = "A spike strip has reached its limit and broke.",
                    type = "warning"
                })
            end
        end
    end

    -- Logging/MDT Hook
    print(("[Spikes] Vehicle %s hit strip #%s"):format(vehicleNetId, stripId))
end)

RegisterNetEvent("ls_spikes:server:pickup", function(stripId, netId)
    local src = source
    if not src or src <= 0 then return end

    local entity = NetworkGetEntityFromNetworkId(netId)
    local stripData = activeStrips[stripId]
    
    if DoesEntityExist(entity) then
        DeleteEntity(entity)
        activeStrips[stripId] = nil
        local Player = QBCore.Functions.GetPlayer(src)
        if not Player then return end

        local itemName = "stopstick"
        if stripData and stripData.itemName then
            itemName = stripData.itemName
        end

        if stripData and stripData.isPrimary then
            Player.Functions.AddItem(itemName, 1)

            if QBCore.Shared and QBCore.Shared.Items and QBCore.Shared.Items[itemName] then
                TriggerClientEvent("inventory:client:ItemBox", src, QBCore.Shared.Items[itemName], "add")
            end
        end
    end
end)

--- Admin cleanup
lib.addCommand("clearspikes", {
    help = "Remove all active spike strips (Admin Only)",
    restricted = { "group.admin" }
}, function(source, args, raw)
    for id, data in pairs(activeStrips) do
        local entity = NetworkGetEntityFromNetworkId(data.netId)
        if DoesEntityExist(entity) then DeleteEntity(entity) end
    end
    activeStrips = {}
    TriggerClientEvent("ox_lib:notify", source, { description = "All spike strips cleared", type = "success" })
end)

AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, data in pairs(activeStrips) do
        local entity = NetworkGetEntityFromNetworkId(data.netId)
        if DoesEntityExist(entity) then DeleteEntity(entity) end
    end
end)
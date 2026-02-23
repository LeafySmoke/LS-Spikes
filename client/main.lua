local QBCore = exports["qb-core"]:GetCoreObject()
local isPulling = false
local currentStrip = nil

local function getItemConfig(itemName)
    return Config.Items[itemName] or Config.Items.stopstick
end

local function getSpikeModels()
    local models = {}
    for _, itemData in pairs(Config.Items) do
        if itemData.model then
            models[#models + 1] = itemData.model
        end
    end
    return models
end

local function findClosestSpikeObject(coords, radius)
    local closestObject = 0
    local closestDistance = radius + 0.01

    for _, model in ipairs(getSpikeModels()) do
        local object = GetClosestObjectOfType(coords.x, coords.y, coords.z, radius, joaat(model), false, false, false)
        if object ~= 0 then
            local distance = #(coords - GetEntityCoords(object))
            if distance < closestDistance then
                closestDistance = distance
                closestObject = object
            end
        end
    end

    return closestObject
end

local WHEELS = {
    { bone = "wheel_lf", index = 0 },
    { bone = "wheel_rf", index = 1 },
    { bone = "wheel_lm", index = 2 },
    { bone = "wheel_rm", index = 3 },
    { bone = "wheel_lr", index = 4 },
    { bone = "wheel_rr", index = 5 },
}

--- Deployment Logic
RegisterNetEvent("ls_spikes:client:deploy", function(itemName)
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return end

    local itemConfig = getItemConfig(itemName)

    local coords = GetEntityCoords(ped)
    local forward = GetEntityForwardVector(ped)
    local spawnPos = coords + (forward * (itemConfig.placementDistance or 1.5))

    -- Check incline/interior
    local _, groundZ = GetGroundZFor_3dCoord(spawnPos.x, spawnPos.y, spawnPos.z, false)
    if GetInteriorFromEntity(ped) ~= 0 then
        lib.notify({ title = "Invalid Area", description = "Cannot deploy indoors", type = "error" })
        return
    end

    if lib.progressBar({
        duration = 2500,
        label = ("Deploying %s..."):format(itemConfig.label or "Spike Strip"),
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true },
        anim = { dict = Config.Animations.Deploy.dict, clip = Config.Animations.Deploy.anim }
    }) then
        lib.requestModel(itemConfig.model)
        local heading = GetEntityHeading(ped) + (itemConfig.headingOffset or 0.0)
        local segmentCount = math.max(1, itemConfig.segmentCount or 1)
        local segmentSpacing = itemConfig.segmentSpacing or 1.5

        for i = 1, segmentCount do
            local segmentPos = spawnPos + (forward * ((i - 1) * segmentSpacing))
            local _, segmentGroundZ = GetGroundZFor_3dCoord(segmentPos.x, segmentPos.y, segmentPos.z, false)

            local spike = CreateObject(itemConfig.model, segmentPos.x, segmentPos.y, segmentGroundZ, true, true, false)
            PlaceObjectOnGroundProperly(spike)
            SetEntityHeading(spike, heading)

            if itemConfig.freezeOnPlace then
                FreezeEntityPosition(spike, true)
                SetEntityDynamic(spike, false)
            end

            local netId = NetworkGetNetworkIdFromEntity(spike)
            TriggerServerEvent("ls_spikes:server:registerStrip", netId, segmentPos, itemName, i == 1)
        end
    end
end)

--- Pulling Logic
local function pullStrip(entity)
    local ped = PlayerPedId()
    isPulling = true
    
    CreateThread(function()
        while isPulling do
            Wait(0)
            local pedCoords = GetEntityCoords(ped)
            local spikeCoords = GetEntityCoords(entity)
            local dist = #(pedCoords - spikeCoords)

            if dist > Config.CordMaxDistance then
                isPulling = false
                lib.notify({ title = "Cord Snapped", description = "You moved too far away!", type = "error" })
                break
            end

            if IsControlPressed(0, 47) then -- G Key
                local dir = vector3(pedCoords.x - spikeCoords.x, pedCoords.y - spikeCoords.y, 0.0)
                local norm = norm(dir)
                local move = spikeCoords + (norm * 0.05)
                SetEntityCoords(entity, move.x, move.y, spikeCoords.z, false, false, false, false)
                TriggerServerEvent("ls_spikes:server:syncPull", NetworkGetNetworkIdFromEntity(entity), move)
            end

            if IsControlJustReleased(0, 47) or IsPedInAnyVehicle(ped, true) then
                isPulling = false
            end
        end
    end)
end

function norm(v)
    local d = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    if d == 0 then return vector3(0.0, 0.0, 0.0) end
    return vector3(v.x / d, v.y / d, v.z / d)
end

--- Tire Deflation System
local function deflateTires(vehicle, wheelIndex)
    if IsVehicleTyreBurst(vehicle, wheelIndex, false) then return end
    
    lib.notify({ title = "Tire Punctured", description = "Slow leak detected...", type = "warning" })
    
    local timer = 0
    local duration = Config.Deflation.Time
    
    CreateThread(function()
        while timer < duration do
            Wait(1000)
            timer = timer + 1000
            
            -- Visual/Handling Wobble
            if GetEntitySpeed(vehicle) * 2.23 > Config.Deflation.WobbleThreshold then
                local currentSteer = GetVehicleSteeringAngle(vehicle)
                SetVehicleSteeringAngle(vehicle, currentSteer + math.random(-2, 2))
            end
        end
        SetVehicleTyreBurst(vehicle, wheelIndex, true, 1000.0)
    end)
end

--- Collision Detection Loop
CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        
        if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
            local coords = GetEntityCoords(vehicle)
            local spikes = findClosestSpikeObject(coords, 5.0)
            
            if spikes ~= 0 then
                for _, wheel in ipairs(WHEELS) do
                    local boneIndex = GetEntityBoneIndexByName(vehicle, wheel.bone)
                    if boneIndex ~= -1 then
                        local wheelPos = GetWorldPositionOfEntityBone(vehicle, boneIndex)
                        local nearbySpike = findClosestSpikeObject(wheelPos, 3.0)

                        if nearbySpike ~= 0 then
                            local spikeData = Entity(nearbySpike).state.stripData
                            if spikeData then
                                local hitDistance = (getItemConfig(spikeData.itemName).hitDistance or 1.0)
                                local dist = #(wheelPos - GetEntityCoords(nearbySpike))

                                if dist <= hitDistance then
                                    TriggerServerEvent("ls_spikes:server:onHit", spikeData.id, NetworkGetNetworkIdFromEntity(vehicle))
                                    deflateTires(vehicle, wheel.index)
                                    Wait(500) -- Prevent multi-hit on same tire
                                end
                            end
                        end
                    end
                end
            end
            Wait(100)
        else
            Wait(1000)
        end
    end
end)

--- Target Interactions
exports.ox_target:addModel(getSpikeModels(), {
    {
        name = "pickup_spike",
        icon = "fa-solid fa-hand-holding",
        label = "Pick Up Stop Stick",
        onSelect = function(data)
            local state = Entity(data.entity).state.stripData
            if state then
                TriggerServerEvent("ls_spikes:server:pickup", state.id, NetworkGetNetworkIdFromEntity(data.entity))
            end
        end
    },
    {
        name = "check_durability",
        icon = "fa-solid fa-shield-halved",
        label = "Check Durability",
        onSelect = function(data)
            local state = Entity(data.entity).state.stripData
            if state then
                lib.notify({ title = "Stop Stick Status", description = "Durability: " .. state.durability .. " hits remaining", type = "info" })
            end
        end
    },
    {
        name = "pull_spike",
        icon = "fa-solid fa-rope-angled",
        label = "Hold Cord (G)",
        onSelect = function(data)
            pullStrip(data.entity)
        end
    }
})
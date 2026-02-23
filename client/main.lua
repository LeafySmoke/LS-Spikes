local QBCore = exports["qb-core"]:GetCoreObject()
local isPulling = false
local currentStrip = nil

--- Deployment Logic
RegisterNetEvent("swisser_spikes:client:deploy", function()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return end

    local coords = GetEntityCoords(ped)
    local forward = GetEntityForwardVector(ped)
    local spawnPos = coords + (forward * 1.5)

    -- Check incline/interior
    local _, groundZ = GetGroundZFor_3dCoord(spawnPos.x, spawnPos.y, spawnPos.z, 0)
    if GetInteriorFromEntity(ped) ~= 0 then
        lib.notify({ title = "Invalid Area", description = "Cannot deploy indoors", type = "error" })
        return
    end

    if lib.progressBar({
        duration = 2500,
        label = "Deploying Stop Stick...",
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true },
        anim = { dict = Config.Animations.Deploy.dict, clip = Config.Animations.Deploy.anim }
    }) then
        lib.requestModel(Config.Models.Spike)
        local spike = CreateObject(Config.Models.Spike, spawnPos.x, spawnPos.y, groundZ, true, true, false)
        PlaceObjectOnGroundProperly(spike)
        SetEntityHeading(spike, GetEntityHeading(ped))
        
        local netId = NetworkGetNetworkIdFromEntity(spike)
        TriggerServerEvent("swisser_spikes:server:registerStrip", netId, spawnPos)
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
                SetEntityCoords(entity, move.x, move.y, spikeCoords.z)
                TriggerServerEvent("swisser_spikes:server:syncPull", NetworkGetNetworkIdFromEntity(entity), move)
            end

            if IsControlJustReleased(0, 47) or IsPedInAnyVehicle(ped, true) then
                isPulling = false
            end
        end
    end)
end

function norm(v)
    local d = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
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
            local spikes = GetClosestObjectOfType(coords.x, coords.y, coords.z, 5.0, joaat(Config.Models.Spike), false, false, false)
            
            if spikes ~= 0 then
                local spikeData = Entity(spikes).state.stripData
                if spikeData then
                    for i = 0, 7 do
                        local wheelPos = GetWorldPositionOfEntityBone(vehicle, GetEntityBoneIndexByName(vehicle, "wheel_" .. i))
                        local dist = #(wheelPos - GetEntityCoords(spikes))
                        
                        if dist < 1.0 then
                            TriggerServerEvent("swisser_spikes:server:onHit", spikeData.id, NetworkGetNetworkIdFromEntity(vehicle))
                            deflateTires(vehicle, i)
                            Wait(500) -- Prevent multi-hit on same tire
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
exports.ox_target:addModel(Config.Models.Spike, {
    {
        name = "pickup_spike",
        icon = "fa-solid fa-hand-holding",
        label = "Pick Up Stop Stick",
        onSelect = function(data)
            local state = Entity(data.entity).state.stripData
            if state then
                TriggerServerEvent("swisser_spikes:server:pickup", state.id, NetworkGetNetworkIdFromEntity(data.entity))
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
-- Runtime state
local isPulling = false
local currentStrip = nil
local currentPullCollisionDisabled = false
local currentStripWasFrozen = false
local currentPullDistance = 0.0
local currentPullMinDistance = 0.0
local currentPullMaxDistance = 0.0
local currentStripLength = 1.0
local currentPullAnchorEntity = nil
local currentPullAnchorOffset = vector3(0.0, 0.0, 0.05)
local pullUiShown = false
local currentPullRope = nil
local currentPullRopeProxy = nil
local currentPullRopeAnchorProxy = nil
local usingPhysicalPullRope = false
local currentPullStripId = nil
local currentPullStripEntities = {}

local wheelHitCooldowns = {}
local processedBurstByVehicle = {}
local lastWheelPositions = {}
local lastCacheCleanupAt = 0
local modelDimensionsCache = {}
local wheelBoneIndexCache = {}
local cachedSpikeModels = nil

-- Animation defaults (overridable via Config.Animations)
local DEFAULT_DEPLOY_ANIM = {
    dict = "amb@medic@standing@kneel@enter",
    anim = "enter",
    duration = 2500,
    flag = 49,
    blendIn = 4.0,
    blendOut = 4.0,
    playbackRate = 0.0,
    canCancel = true,
    progressLabel = "Deploying %s..."
}

local DEFAULT_PICKUP_ANIM = {
    dict = "veh@common@motorbike@high@ds",
    anim = "pickup",
    duration = 6800,
    flag = 49,
    blendIn = 4.0,
    blendOut = 4.0,
    playbackRate = 0.0,
    canCancel = true,
    label = "Picking up %s..."
}

local DEFAULT_SEGMENT_DEPLOY_ANIM = {
    dict = "p_ld_stinger_s",
    anim = "p_stinger_s_deploy",
    speed = 1000.0,
    loop = false,
    holdLastFrame = false,
    driveToPose = false,
    startPhase = 0.0,
    flags = 0
}

local spikeModelHashes = {}
for _, itemData in pairs(Config.Items or {}) do
    if itemData.model then
        spikeModelHashes[joaat(itemData.model)] = true
    end
end

local WHEELS = {
    { bone = "wheel_lf", index = 0 },
    { bone = "wheel_rf", index = 1 },
    { bone = "wheel_lm", index = 2 },
    { bone = "wheel_rm", index = 3 },
    { bone = "wheel_lr", index = 4 },
    { bone = "wheel_rr", index = 5 },
}

-- Generic helpers
local function clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

local function mergeAnimationConfig(defaults, overrides)
    local merged = {}
    for key, value in pairs(defaults or {}) do
        merged[key] = value
    end

    if type(overrides) == "table" then
        for key, value in pairs(overrides) do
            merged[key] = value
        end
    end

    return merged
end

local function getAnimationConfig(key, defaults)
    local configured = nil
    if type(Config.Animations) == "table" then
        configured = Config.Animations[key]
    end

    return mergeAnimationConfig(defaults, configured)
end

local function getItemConfig(itemName)
    return Config.Items[itemName] or Config.Items.stopstick
end

local function getStripLength(itemConfig)
    local segmentCount = math.max(1, itemConfig.segmentCount or 1)
    local segmentSpacing = itemConfig.segmentSpacing or 1.5
    return math.max(1.0, segmentCount * segmentSpacing)
end

local function getSpikeModels()
    if cachedSpikeModels then
        return cachedSpikeModels
    end

    local models = {}
    for _, itemData in pairs(Config.Items) do
        if itemData.model then
            models[#models + 1] = itemData.model
        end
    end

    cachedSpikeModels = models
    return models
end

local function getNearbySpikeObjects(coords, radius)
    local nearby = {}
    local objects = GetGamePool("CObject")
    local radiusSq = radius * radius

    for _, object in ipairs(objects) do
        if DoesEntityExist(object) and spikeModelHashes[GetEntityModel(object)] then
            local objectCoords = GetEntityCoords(object)
            local dx = coords.x - objectCoords.x
            local dy = coords.y - objectCoords.y
            local dz = coords.z - objectCoords.z
            if (dx * dx + dy * dy + dz * dz) <= radiusSq then
                nearby[#nearby + 1] = {
                    entity = object,
                    coords = objectCoords
                }
            end
        end
    end

    return nearby
end

local function canInteractWithSpikeEntity(entity)
    if entity == 0 or not DoesEntityExist(entity) then return false end
    return spikeModelHashes[GetEntityModel(entity)] == true
end

local function getModelDimensionsCached(model)
    local cached = modelDimensionsCache[model]
    if cached then
        return cached.minDim, cached.maxDim
    end

    local minDim, maxDim = GetModelDimensions(model)
    modelDimensionsCache[model] = {
        minDim = minDim,
        maxDim = maxDim
    }

    return minDim, maxDim
end

local function getWheelBoneIndices(vehicle)
    local vehicleModel = GetEntityModel(vehicle)
    local cached = wheelBoneIndexCache[vehicleModel]
    if cached then
        return cached
    end

    cached = {}
    for index = 1, #WHEELS do
        cached[index] = GetEntityBoneIndexByName(vehicle, WHEELS[index].bone)
    end

    wheelBoneIndexCache[vehicleModel] = cached
    return cached
end

local function isWheelOverSpike(wheelPos, spikeEntity, spikeCoords, extraPadding)
    if spikeEntity == 0 or not DoesEntityExist(spikeEntity) then
        return false, 9999.0
    end

    local minDim, maxDim = getModelDimensionsCached(GetEntityModel(spikeEntity))
    local localWheel = GetOffsetFromEntityGivenWorldCoords(spikeEntity, wheelPos.x, wheelPos.y, wheelPos.z)
    local padding = extraPadding or 0.18

    local insideX = localWheel.x >= (minDim.x - padding) and localWheel.x <= (maxDim.x + padding)
    local insideY = localWheel.y >= (minDim.y - padding) and localWheel.y <= (maxDim.y + padding)
    local insideZ = localWheel.z >= (minDim.z - 0.35) and localWheel.z <= (maxDim.z + 0.45)

    local dx = wheelPos.x - spikeCoords.x
    local dy = wheelPos.y - spikeCoords.y
    local dz = wheelPos.z - spikeCoords.z
    local distanceSq = dx * dx + dy * dy + dz * dz

    if insideX and insideY and insideZ then
        return true, distanceSq
    end

    return false, distanceSq
end

local function getWheelCooldownKey(vehicleNetId, wheelIndex, stripId)
    return ("%s:%s:%s"):format(vehicleNetId, wheelIndex, stripId or 0)
end

local function getWheelTrackKey(vehicleNetId, wheelIndex)
    return ("%s:%s"):format(vehicleNetId, wheelIndex)
end

local function findMatchingSpikeAtPosition(position, nearbySpikes)
    local matchedSpike = 0
    local matchedDistanceSq = 99999999.0
    local extraPadding = tonumber(Config.WheelContactPadding) or 0.16

    for index = 1, #nearbySpikes do
        local spikeEntry = nearbySpikes[index]
        local spikeEntity = spikeEntry.entity
        local isOverlapping, distSq = isWheelOverSpike(position, spikeEntity, spikeEntry.coords, extraPadding)
        if isOverlapping and distSq < matchedDistanceSq then
            matchedSpike = spikeEntity
            matchedDistanceSq = distSq
        end
    end

    return matchedSpike, matchedDistanceSq
end

local function findMatchingSpikeForWheel(wheelPos, previousWheelPos, nearbySpikes)
    local matchedSpike, matchedDistanceSq = findMatchingSpikeAtPosition(wheelPos, nearbySpikes)
    if matchedSpike ~= 0 or not previousWheelPos then
        return matchedSpike, matchedDistanceSq
    end

    local sweepStep = tonumber(Config.WheelSweepStep) or 0.45
    local maxSamples = math.max(1, math.floor(tonumber(Config.WheelSweepMaxSamples) or 8))
    if sweepStep <= 0.0 then
        sweepStep = 0.45
    end

    local dx = wheelPos.x - previousWheelPos.x
    local dy = wheelPos.y - previousWheelPos.y
    local dz = wheelPos.z - previousWheelPos.z
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    if distance <= sweepStep then
        return matchedSpike, matchedDistanceSq
    end

    local sampleCount = math.min(maxSamples, math.max(1, math.ceil(distance / sweepStep)))
    for sampleIndex = 1, sampleCount do
        local t = sampleIndex / sampleCount
        local samplePos = vector3(
            previousWheelPos.x + (dx * t),
            previousWheelPos.y + (dy * t),
            previousWheelPos.z + (dz * t)
        )

        local sampleSpike, sampleDistanceSq = findMatchingSpikeAtPosition(samplePos, nearbySpikes)
        if sampleSpike ~= 0 and sampleDistanceSq < matchedDistanceSq then
            matchedSpike = sampleSpike
            matchedDistanceSq = sampleDistanceSq
        end
    end

    return matchedSpike, matchedDistanceSq
end

local function norm(v)
    local d = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    if d == 0 then return vector3(0.0, 0.0, 0.0) end
    return vector3(v.x / d, v.y / d, v.z / d)
end

local function isSafeObjectEntity(entity)
    if entity == 0 or not DoesEntityExist(entity) then return false end
    if GetEntityType(entity) ~= 3 then return false end

    local model = GetEntityModel(entity)
    if spikeModelHashes[model] then
        return true
    end

    local ropeProxyModel = Config.PullRopeProxyModel or "prop_beachball_02"
    return model == joaat(ropeProxyModel)
end

local function safeDeleteObjectEntity(entity)
    if isSafeObjectEntity(entity) then
        DeleteEntity(entity)
    end
end

local function isVehicleNearCoords(coords, radius, ignoreVehicle)
    local radiusSq = radius * radius
    for _, vehicle in ipairs(GetGamePool("CVehicle")) do
        if vehicle ~= ignoreVehicle and DoesEntityExist(vehicle) and not IsEntityDead(vehicle) then
            local vehicleCoords = GetEntityCoords(vehicle)
            local dx = coords.x - vehicleCoords.x
            local dy = coords.y - vehicleCoords.y
            local dz = coords.z - vehicleCoords.z
            if (dx * dx + dy * dy + dz * dz) <= radiusSq then
                return true, vehicle
            end
        end
    end

    return false, 0
end

local function getAnchorOffsetForEntityEnd(entity, ped)
    if not DoesEntityExist(entity) then
        return vector3(0.0, 0.0, 0.05)
    end

    local minDim, maxDim = GetModelDimensions(GetEntityModel(entity))
    local pedCoords = GetEntityCoords(ped)
    local pedLocal = GetOffsetFromEntityGivenWorldCoords(entity, pedCoords.x, pedCoords.y, pedCoords.z)

    local xSize = math.abs(maxDim.x - minDim.x)
    local ySize = math.abs(maxDim.y - minDim.y)
    local centerX = (minDim.x + maxDim.x) * 0.5
    local centerY = (minDim.y + maxDim.y) * 0.5

    if ySize >= xSize then
        local chooseMin = math.abs(pedLocal.y - minDim.y) < math.abs(maxDim.y - pedLocal.y)
        return vector3(centerX, chooseMin and minDim.y or maxDim.y, 0.05)
    end

    local chooseMin = math.abs(pedLocal.x - minDim.x) < math.abs(maxDim.x - pedLocal.x)
    return vector3(chooseMin and minDim.x or maxDim.x, centerY, 0.05)
end

local function getPullAnchorCoords()
    if currentPullAnchorEntity and DoesEntityExist(currentPullAnchorEntity) then
        local offset = currentPullAnchorOffset or vector3(0.0, 0.0, 0.05)
        return GetOffsetFromEntityInWorldCoords(currentPullAnchorEntity, offset.x, offset.y, offset.z)
    end

    if currentStrip and DoesEntityExist(currentStrip) then
        return GetEntityCoords(currentStrip)
    end

    return nil
end

local function drawThickRopeLine(startCoords, endCoords)
    local strands = Config.PullRopeVisualStrands or 3
    if strands < 1 then strands = 1 end
    if strands % 2 == 0 then strands = strands + 1 end

    local half = math.floor(strands / 2)
    local thickness = Config.PullRopeVisualWidth or 0.015
    local strandSpacing = thickness * 0.35
    local dir = norm(endCoords - startCoords)
    local right = norm(vector3(-dir.y, dir.x, 0.0))

    if right.x == 0.0 and right.y == 0.0 and right.z == 0.0 then
        DrawLine(startCoords.x, startCoords.y, startCoords.z, endCoords.x, endCoords.y, endCoords.z, 0, 0, 0, 220)
        return
    end

    for index = -half, half do
        local offset = right * (strandSpacing * index)
        DrawLine(
            startCoords.x + offset.x, startCoords.y + offset.y, startCoords.z + offset.z,
            endCoords.x + offset.x, endCoords.y + offset.y, endCoords.z + offset.z,
            0, 0, 0, 220
        )
    end
end

local function findPrimaryStripEntity(stripId)
    if not stripId then return 0 end

    local objects = GetGamePool("CObject")
    for _, object in ipairs(objects) do
        if DoesEntityExist(object) then
            local state = Entity(object).state.stripData
            if state and state.id == stripId and state.isPrimary then
                return object
            end
        end
    end

    return 0
end

local function getStripEntities(stripId)
    local entities = {}
    if not stripId then return entities end

    local objects = GetGamePool("CObject")
    for _, object in ipairs(objects) do
        if DoesEntityExist(object) and spikeModelHashes[GetEntityModel(object)] then
            local state = Entity(object).state.stripData
            if state and state.id == stripId then
                entities[#entities + 1] = object
            end
        end
    end

    return entities
end

local function setStripEntitiesCollision(entities, enabled)
    for _, stripEntity in ipairs(entities or {}) do
        if stripEntity ~= 0 and DoesEntityExist(stripEntity) then
            SetEntityCollision(stripEntity, enabled, true)
        end
    end
end

local function setStripEntitiesNoCollisionWithPed(entities, ped)
    if ped == 0 or not DoesEntityExist(ped) then return end

    for _, stripEntity in ipairs(entities or {}) do
        if stripEntity ~= 0 and DoesEntityExist(stripEntity) then
            SetEntityNoCollisionEntity(ped, stripEntity, true)
            SetEntityNoCollisionEntity(stripEntity, ped, true)
        end
    end
end

-- Rope proxy helpers
local function getProxyHandCoords(playerPed)
    local handBone = GetPedBoneIndex(playerPed, 57005)
    if handBone ~= -1 then
        local handPos = GetWorldPositionOfEntityBone(playerPed, handBone)
        return vector3(handPos.x, handPos.y, handPos.z)
    end

    local handPos = GetPedBoneCoords(playerPed, 57005, 0.0, 0.0, 0.0)
    return vector3(handPos.x, handPos.y, handPos.z)
end

local function createRopeProxyAtCoords(coords)
    if not coords then
        return 0
    end

    local model = Config.PullRopeProxyModel or "prop_beachball_02"
    lib.requestModel(model)

    local proxy = CreateObjectNoOffset(joaat(model), coords.x, coords.y, coords.z, false, false, false)
    if proxy == 0 or not DoesEntityExist(proxy) then
        return 0
    end

    SetEntityCollision(proxy, false, false)
    FreezeEntityPosition(proxy, true)
    SetEntityDynamic(proxy, false)
    SetEntityVisible(proxy, false, false)
    SetEntityAlpha(proxy, 0, false)
    SetEntityAsMissionEntity(proxy, true, false)
    return proxy
end

local function createPullRopeProxy(playerPed)
    if playerPed == 0 or not DoesEntityExist(playerPed) then
        return 0
    end

    local handCoords = getProxyHandCoords(playerPed)
    local zOffset = Config.PullRopeProxyHandZOffset or -0.03
    return createRopeProxyAtCoords(vector3(handCoords.x, handCoords.y, handCoords.z + zOffset))
end

local function createPullRopeAnchorProxy(anchorCoords)
    if not anchorCoords then
        return 0
    end

    local zOffset = Config.PullRopeAnchorProxyZOffset or 0.02
    return createRopeProxyAtCoords(vector3(anchorCoords.x, anchorCoords.y, anchorCoords.z + zOffset))
end

local function updatePullRopeProxyPosition(playerPed)
    if not currentPullRopeProxy or currentPullRopeProxy == 0 or not DoesEntityExist(currentPullRopeProxy) then
        return false
    end

    local handCoords = getProxyHandCoords(playerPed)
    local zOffset = Config.PullRopeProxyHandZOffset or -0.03
    SetEntityCoordsNoOffset(currentPullRopeProxy, handCoords.x, handCoords.y, handCoords.z + zOffset, false, false, true)
    return true
end

local function updatePullRopeAnchorProxyPosition(anchorCoords)
    if not anchorCoords then
        return false
    end

    if not currentPullRopeAnchorProxy or currentPullRopeAnchorProxy == 0 or not DoesEntityExist(currentPullRopeAnchorProxy) then
        return false
    end

    local zOffset = Config.PullRopeAnchorProxyZOffset or 0.02
    SetEntityCoordsNoOffset(currentPullRopeAnchorProxy, anchorCoords.x, anchorCoords.y, anchorCoords.z + zOffset, false, false, true)
    return true
end

local function clearPullRope()
    if currentPullRope and currentPullRope ~= 0 then
        DeleteRope(currentPullRope)
    end

    if currentPullRopeProxy and currentPullRopeProxy ~= 0 and DoesEntityExist(currentPullRopeProxy) then
        safeDeleteObjectEntity(currentPullRopeProxy)
    end

    if currentPullRopeAnchorProxy and currentPullRopeAnchorProxy ~= 0 and DoesEntityExist(currentPullRopeAnchorProxy) then
        safeDeleteObjectEntity(currentPullRopeAnchorProxy)
    end

    currentPullRope = nil
    currentPullRopeProxy = nil
    currentPullRopeAnchorProxy = nil
    usingPhysicalPullRope = false

    if RopeAreTexturesLoaded() then
        RopeUnloadTextures()
    end
end

local function createPhysicalPullRope(playerPed, anchorCoords)
    if Config.PullUsePhysicsRope == false then
        return false
    end

    if playerPed == 0 or not DoesEntityExist(playerPed) then
        return false
    end

    if not anchorCoords then
        return false
    end

    clearPullRope()

    if not RopeAreTexturesLoaded() then
        RopeLoadTextures()
        local startedAt = GetGameTimer()
        while not RopeAreTexturesLoaded() and (GetGameTimer() - startedAt) < 1200 do
            Wait(0)
        end
    end

    if not RopeAreTexturesLoaded() then
        return false
    end

    currentPullRopeProxy = createPullRopeProxy(playerPed)
    currentPullRopeAnchorProxy = createPullRopeAnchorProxy(anchorCoords)

    if currentPullRopeProxy == 0 or currentPullRopeAnchorProxy == 0 then
        clearPullRope()
        return false
    end

    if not updatePullRopeProxyPosition(playerPed) or not updatePullRopeAnchorProxyPosition(anchorCoords) then
        clearPullRope()
        return false
    end

    local proxyCoords = GetEntityCoords(currentPullRopeProxy)
    local anchorProxyCoords = GetEntityCoords(currentPullRopeAnchorProxy)

    local ropeType = Config.PullRopeType or 4
    local minLength = math.max(0.25, currentPullMinDistance or 0.25)
    local initialLength = math.max(currentPullDistance or 1.0, minLength)
    local maxLength = math.max((Config.CordMaxDistance or 30.0) + 1.0, initialLength + 0.5)

    local rope = AddRope(
        anchorProxyCoords.x, anchorProxyCoords.y, anchorProxyCoords.z,
        0.0, 0.0, 0.0,
        maxLength,
        ropeType,
        initialLength,
        minLength,
        0.0,
        false,
        true,
        false,
        1.0,
        false,
        0
    )

    if not rope or rope == 0 then
        clearPullRope()
        return false
    end

    AttachEntitiesToRope(
        rope,
        currentPullRopeProxy,
        currentPullRopeAnchorProxy,
        proxyCoords.x, proxyCoords.y, proxyCoords.z,
        anchorProxyCoords.x, anchorProxyCoords.y, anchorProxyCoords.z,
        initialLength,
        false,
        false,
        "",
        ""
    )

    RopeForceLength(rope, initialLength)
    currentPullRope = rope
    usingPhysicalPullRope = true
    return true
end

-- Entity/world helpers
local function requestControl(entity, timeoutMs)
    if not DoesEntityExist(entity) then return false end
    if NetworkHasControlOfEntity(entity) then return true end

    local timeout = timeoutMs or 750
    local startedAt = GetGameTimer()

    NetworkRequestControlOfEntity(entity)
    while not NetworkHasControlOfEntity(entity) and (GetGameTimer() - startedAt) < timeout do
        Wait(0)
        NetworkRequestControlOfEntity(entity)
    end

    return NetworkHasControlOfEntity(entity)
end

local function getGroundedZ(x, y, fallbackZ)
    local probeZ = (fallbackZ or 40.0) + 2.0
    local found, groundZ = GetGroundZFor_3dCoord(x, y, probeZ, false)
    if found then
        return groundZ + 0.02
    end
    return fallbackZ or 0.0
end

local function requestAnimDict(dict)
    if not dict or dict == "" then return false end
    if HasAnimDictLoaded(dict) then return true end

    RequestAnimDict(dict)
    local startedAt = GetGameTimer()

    while not HasAnimDictLoaded(dict) and (GetGameTimer() - startedAt) < 2500 do
        Wait(0)
    end

    return HasAnimDictLoaded(dict)
end

local function isPullPathBlocked(stripEntity, playerPed, fromCoords, toCoords)
    local zOffset = 0.12
    local radius = 0.18
    local flags = 2 + 16

    local rayHandle = StartShapeTestSweptSphere(
        fromCoords.x, fromCoords.y, fromCoords.z + zOffset,
        toCoords.x, toCoords.y, toCoords.z + zOffset,
        radius,
        flags,
        stripEntity,
        7
    )

    for _ = 1, 5 do
        local result, didHit, _, _, hitEntity = GetShapeTestResult(rayHandle)
        if result == 2 then
            if didHit == 1 then
                if hitEntity == 0 then
                    return true
                end

                if hitEntity ~= stripEntity and hitEntity ~= playerPed then
                    return true
                end
            end

            return false
        elseif result == 0 then
            break
        end

        Wait(0)
    end

    return false
end

local function getRopeStartCoords(ped)
    local handBone = GetPedBoneIndex(ped, 57005)
    if handBone ~= -1 then
        local handPos = GetWorldPositionOfEntityBone(ped, handBone)
        return vector3(handPos.x, handPos.y, handPos.z)
    end

    local handPos = GetPedBoneCoords(ped, 57005, 0.0, 0.0, 0.0)
    return vector3(handPos.x, handPos.y, handPos.z)
end

local function placeObjectWithGroundClearance(entity, clearance)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return end

    PlaceObjectOnGroundProperly(entity)
    local coords = GetEntityCoords(entity)
    SetEntityCoordsNoOffset(entity, coords.x, coords.y, coords.z + (clearance or 0.0), false, false, true)
end

local function rotationToDirection(rotation)
    local rotX = math.rad(rotation.x)
    local rotZ = math.rad(rotation.z)
    local cosX = math.abs(math.cos(rotX))

    return vector3(
        -math.sin(rotZ) * cosX,
        math.cos(rotZ) * cosX,
        math.sin(rotX)
    )
end

local function cameraRaycastPlacement(ped, fallbackCoords, fallbackForward, fallbackDistance, maxDistance)
    local camCoords = GetGameplayCamCoord()
    local camRot = GetGameplayCamRot(2)
    local direction = rotationToDirection(camRot)
    local rayDistance = maxDistance or 12.0
    local rayEnd = camCoords + (direction * rayDistance)
    local rayFlags = (Config.PlacementPreview and Config.PlacementPreview.raycastFlags) or (1 + 16 + 32)

    local rayHandle = StartShapeTestRay(
        camCoords.x, camCoords.y, camCoords.z,
        rayEnd.x, rayEnd.y, rayEnd.z,
        rayFlags,
        ped,
        7
    )

    local hit = false
    local hitCoords = rayEnd
    for _ = 1, 5 do
        local result, didHit, endCoords = GetShapeTestResult(rayHandle)
        if result == 2 then
            hit = didHit == 1
            hitCoords = endCoords or rayEnd
            break
        elseif result == 0 then
            break
        end
        Wait(0)
    end

    if hit then
        return vector3(hitCoords.x, hitCoords.y, hitCoords.z)
    end

    if fallbackCoords and fallbackForward then
        return fallbackCoords + (fallbackForward * (fallbackDistance or 1.5))
    end

    return rayEnd
end

local function showPullUiText()
    local text = ("[E] Pull  |  [MWHEEL] Adjust (%.2fm)"):format(currentPullDistance)
    if pullUiShown then
        lib.hideTextUI()
        pullUiShown = false
    end

    lib.showTextUI(text, {
        position = "left-center",
        icon = "fa-solid fa-rope",
    })
    pullUiShown = true
end

local function hidePullUiText()
    if pullUiShown then
        lib.hideTextUI()
        pullUiShown = false
    end
end

-- Placement workflow
local function runPlacementPreview(itemConfig)
    if not Config.PlacementPreview or not Config.PlacementPreview.enabled then
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local forward = GetEntityForwardVector(ped)
        local previewCfg = Config.PlacementPreview or {}
        local useRaycast = previewCfg.useCameraRaycast == true
        local position

        if useRaycast then
            position = cameraRaycastPlacement(
                ped,
                coords,
                forward,
                itemConfig.placementDistance or 1.5,
                previewCfg.raycastDistance or 12.0
            )
        else
            position = coords + (forward * (itemConfig.placementDistance or 1.5))
        end

        return position, GetEntityHeading(ped) + (itemConfig.headingOffset or 0.0), false
    end

    local ped = PlayerPedId()
    local distance = itemConfig.placementDistance or 1.5
    local heading = GetEntityHeading(ped) + (itemConfig.headingOffset or 0.0)
    local distanceStep = (Config.PlacementPreview.distanceStep or 0.15)
    local headingStep = (Config.PlacementPreview.headingStep or 3.0)
    local headingHoldSpeed = (Config.PlacementPreview.headingHoldSpeed or 110.0)
    local groundClearance = Config.GroundClearance or 0.03
    local useRaycast = Config.PlacementPreview.useCameraRaycast == true
    local raycastDistance = Config.PlacementPreview.raycastDistance or 12.0
    local segmentCount = math.max(1, itemConfig.segmentCount or 1)
    local segmentSpacing = itemConfig.segmentSpacing or 1.5

    lib.requestModel(itemConfig.model)

    local previewSegments = {}
    for _ = 1, segmentCount do
        local preview = CreateObject(itemConfig.model, 0.0, 0.0, 0.0, false, false, false)
        SetEntityCollision(preview, false, false)
        FreezeEntityPosition(preview, true)
        SetEntityAlpha(preview, 160, false)
        previewSegments[#previewSegments + 1] = preview
    end

    local uiText = "[E] Place  |  [BACKSPACE] Cancel  |  [LEFT/RIGHT] Rotate"
    if not useRaycast then
        uiText = uiText .. "  |  [MWHEEL] Distance"
    end

    lib.showTextUI(uiText, {
        position = "left-center",
        icon = "fa-solid fa-location-dot",
    })

    local cancelled = false
    local placed = false
    local finalPos = nil
    local finalHeading = heading
    local previewOrigin = nil

    while true do
        Wait(0)

        ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local forward = GetEntityForwardVector(ped)

        local rotateLeftPressed = IsControlPressed(0, 174)
        local rotateRightPressed = IsControlPressed(0, 175)

        if IsControlJustPressed(0, 174) then
            heading = heading + headingStep
        elseif IsControlJustPressed(0, 175) then
            heading = heading - headingStep
        elseif rotateLeftPressed ~= rotateRightPressed then
            local frameStep = headingHoldSpeed * GetFrameTime()
            if rotateLeftPressed then
                heading = heading + frameStep
            else
                heading = heading - frameStep
            end
        end

        if not useRaycast then
            if IsControlJustPressed(0, 15) then
                distance = clamp(distance + distanceStep, 0.8, 8.0)
            elseif IsControlJustPressed(0, 14) then
                distance = clamp(distance - distanceStep, 0.8, 8.0)
            end
        end

        local targetPos
        if useRaycast then
            targetPos = cameraRaycastPlacement(ped, coords, forward, distance, raycastDistance)
        else
            targetPos = coords + (forward * distance)
        end

        local headingRad = math.rad(heading)
        local headingForward = vector3(-math.sin(headingRad), math.cos(headingRad), 0.0)
        local targetZ = getGroundedZ(targetPos.x, targetPos.y, coords.z)
        previewOrigin = vector3(targetPos.x, targetPos.y, targetZ)

        for index = 1, #previewSegments do
            local preview = previewSegments[index]
            if preview and DoesEntityExist(preview) then
                local offset = headingForward * (segmentSpacing * (index - 1))
                local segmentPos = previewOrigin + offset
                local segmentZ = getGroundedZ(segmentPos.x, segmentPos.y, segmentPos.z)

                SetEntityCoordsNoOffset(preview, segmentPos.x, segmentPos.y, segmentZ, false, false, true)
                SetEntityHeading(preview, heading)
                placeObjectWithGroundClearance(preview, groundClearance)
            end
        end

        if IsControlJustPressed(0, 38) then
            if Config.BlockPlacementNearVehicles ~= false then
                local safetyRadius = tonumber(Config.PlacementVehicleSafetyRadius) or 2.4
                local blockedPlacement = false

                for index = 1, #previewSegments do
                    local previewSegment = previewSegments[index]
                    if previewSegment and DoesEntityExist(previewSegment) then
                        local segmentCoords = GetEntityCoords(previewSegment)
                        local hasVehicleNearby = isVehicleNearCoords(segmentCoords, safetyRadius, 0)
                        if hasVehicleNearby then
                            blockedPlacement = true
                            break
                        end
                    end
                end

                if blockedPlacement then
                    lib.notify({
                        title = "Placement Blocked",
                        description = "Move spikes away from nearby vehicles before placing.",
                        type = "error"
                    })
                    goto continue_preview
                end
            end

            local primary = previewSegments[1]
            if primary and DoesEntityExist(primary) then
                finalPos = GetEntityCoords(primary)
            else
                finalPos = previewOrigin
            end
            finalHeading = heading
            placed = true
            break
        elseif IsControlJustPressed(0, 177) then
            cancelled = true
            break
        end

        ::continue_preview::
    end

    lib.hideTextUI()
    for _, preview in ipairs(previewSegments) do
        if preview and DoesEntityExist(preview) then
            safeDeleteObjectEntity(preview)
        end
    end

    if cancelled or not placed then
        return nil, nil, true
    end

    return finalPos, finalHeading, false
end

local function spawnStripSegments(itemConfig, originPos, heading)
    local segmentCount = math.max(1, itemConfig.segmentCount or 1)
    local segmentSpacing = itemConfig.segmentSpacing or 1.5
    local groundClearance = Config.GroundClearance or 0.03
    local headingRad = math.rad(heading)
    local forward = vector3(-math.sin(headingRad), math.cos(headingRad), 0.0)

    local spawned = {}
    for index = 1, segmentCount do
        local offset = segmentSpacing * (index - 1)
        local segmentPos = originPos + (forward * offset)
        local segmentZ = getGroundedZ(segmentPos.x, segmentPos.y, segmentPos.z)

        local segment = CreateObject(itemConfig.model, segmentPos.x, segmentPos.y, segmentZ, true, true, false)
        SetEntityHeading(segment, heading)
        placeObjectWithGroundClearance(segment, groundClearance)

        local segmentNetId = NetworkGetNetworkIdFromEntity(segment)
        if segmentNetId and segmentNetId > 0 then
            SetNetworkIdExistsOnAllMachines(segmentNetId, true)
            SetNetworkIdCanMigrate(segmentNetId, true)
            NetworkSetNetworkIdDynamic(segmentNetId, false)
        end

        spawned[#spawned + 1] = segment
    end

    local primary = spawned[1]
    if primary and DoesEntityExist(primary) then
        for index = 2, #spawned do
            local segment = spawned[index]
            if segment and DoesEntityExist(segment) then
                AttachEntityToEntity(segment, primary, 0, 0.0, segmentSpacing * (index - 1), 0.0, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
            end
        end
    end

    if itemConfig.freezeOnPlace then
        for _, segment in ipairs(spawned) do
            if DoesEntityExist(segment) then
                FreezeEntityPosition(segment, true)
                SetEntityDynamic(segment, false)
            end
        end
    end

    return spawned
end

-- Pull workflow
local function stopPulling(notifyCordSnapped)
    if currentStrip and DoesEntityExist(currentStrip) and currentStripWasFrozen then
        FreezeEntityPosition(currentStrip, true)
        SetEntityDynamic(currentStrip, false)
    end

    if currentPullCollisionDisabled then
        if #currentPullStripEntities > 0 then
            setStripEntitiesCollision(currentPullStripEntities, true)
        elseif currentStrip and DoesEntityExist(currentStrip) then
            SetEntityCollision(currentStrip, true, true)
        end
    end

    isPulling = false
    currentStrip = nil
    currentPullCollisionDisabled = false
    currentStripWasFrozen = false
    currentPullDistance = 0.0
    currentPullMinDistance = 0.0
    currentPullMaxDistance = 0.0
    currentStripLength = 1.0
    currentPullAnchorEntity = nil
    currentPullStripId = nil
    currentPullStripEntities = {}
    currentPullAnchorOffset = vector3(0.0, 0.0, 0.05)
    clearPullRope()
    hidePullUiText()

    if notifyCordSnapped then
        lib.notify({ title = "Cord Snapped", description = "You moved too far away!", type = "error" })
    end
end

local function startPulling(entity)
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return end
    if not DoesEntityExist(entity) then return end

    if IsEntityAttached(entity) then
        local attachedTo = GetEntityAttachedTo(entity)
        if attachedTo ~= 0 and DoesEntityExist(attachedTo) and spikeModelHashes[GetEntityModel(attachedTo)] then
            entity = attachedTo
        end
    end

    local selectedEntity = entity
    local selectedState = Entity(selectedEntity).state.stripData
    if selectedState and selectedState.id and not selectedState.isPrimary then
        local primary = findPrimaryStripEntity(selectedState.id)
        if primary ~= 0 and DoesEntityExist(primary) then
            entity = primary
        end
    end

    if isPulling then
        if currentStrip == entity then
            stopPulling(false)
            return
        end

        stopPulling(false)
    end

    isPulling = true
    currentStrip = entity
    currentStripWasFrozen = IsEntityPositionFrozen(entity)
    currentPullAnchorEntity = selectedEntity
    currentPullAnchorOffset = getAnchorOffsetForEntityEnd(selectedEntity, ped)

    local stripData = Entity(entity).state.stripData
    local itemConfig = getItemConfig(stripData and stripData.itemName or "stopstick")
    currentStripLength = getStripLength(itemConfig)
    currentPullStripId = stripData and stripData.id or nil
    currentPullStripEntities = getStripEntities(currentPullStripId)
    if #currentPullStripEntities == 0 and DoesEntityExist(entity) then
        currentPullStripEntities = { entity }
    end

    local lengthsConfig = Config.PullDistanceLengths or {}
    currentPullMinDistance = currentStripLength * (lengthsConfig.min or 0.5)
    currentPullMaxDistance = currentStripLength * (lengthsConfig.max or 1.0)
    currentPullDistance = clamp(
        currentStripLength * (lengthsConfig.default or 0.75),
        currentPullMinDistance,
        currentPullMaxDistance
    )

    if not requestControl(entity, 1000) then
        isPulling = false
        currentStrip = nil
        currentStripWasFrozen = false
        lib.notify({ title = "Pull Failed", description = "Could not take control of spike strip.", type = "error" })
        return
    end

    if currentStripWasFrozen then
        FreezeEntityPosition(entity, false)
        SetEntityDynamic(entity, true)
    end

    if Config.PullDisableCollision then
        currentPullCollisionDisabled = true
        -- Keep world collision enabled while pulling; only disable collision against the player.
        setStripEntitiesCollision(currentPullStripEntities, true)
    end

    showPullUiText()

    local initialAnchorCoords = getPullAnchorCoords() or GetEntityCoords(entity)
    createPhysicalPullRope(ped, initialAnchorCoords)

    CreateThread(function()
        local lastUiRefresh = 0
        while isPulling and currentStrip == entity do
            Wait(0)

            if not DoesEntityExist(entity) then
                stopPulling(false)
                break
            end

            if not NetworkHasControlOfEntity(entity) and not requestControl(entity, 250) then
                Wait(100)
                goto continue
            end

            local playerPed = PlayerPedId()
            if IsPedInAnyVehicle(playerPed, true) then
                stopPulling(false)
                break
            end

            local pedCoords = GetEntityCoords(playerPed)
            local spikeCoords = GetEntityCoords(entity)
            local anchorCoords = getPullAnchorCoords() or spikeCoords
            local dist = #(pedCoords - anchorCoords)

            if Config.PullDisableCollision then
                setStripEntitiesNoCollisionWithPed(currentPullStripEntities, playerPed)
            end

            local ropeStart = getRopeStartCoords(playerPed)
            local drewPhysicalRope = false

            if Config.PullUsePhysicsRope ~= false then
                if (not currentPullRope or currentPullRope == 0) and (currentPullAnchorEntity or entity) ~= 0 then
                    createPhysicalPullRope(playerPed, anchorCoords)
                end

                if currentPullRope and currentPullRope ~= 0 then
                    local proxyOk = updatePullRopeProxyPosition(playerPed)
                    local anchorProxyOk = updatePullRopeAnchorProxyPosition(anchorCoords)
                    if not proxyOk or not anchorProxyOk then
                        clearPullRope()
                    else
                        RopeForceLength(currentPullRope, math.max(0.25, dist))
                        drewPhysicalRope = usingPhysicalPullRope
                    end
                end
            end

            if not drewPhysicalRope then
                drawThickRopeLine(ropeStart, anchorCoords)
            end

            if IsControlJustPressed(0, 15) then
                local step = (Config.PullDistanceLengths and Config.PullDistanceLengths.step or 0.05) * currentStripLength
                currentPullDistance = clamp(currentPullDistance + step, currentPullMinDistance, currentPullMaxDistance)
                showPullUiText()
            elseif IsControlJustPressed(0, 14) then
                local step = (Config.PullDistanceLengths and Config.PullDistanceLengths.step or 0.05) * currentStripLength
                currentPullDistance = clamp(currentPullDistance - step, currentPullMinDistance, currentPullMaxDistance)
                showPullUiText()
            elseif (GetGameTimer() - lastUiRefresh) > 750 then
                showPullUiText()
                lastUiRefresh = GetGameTimer()
            end

            if dist > Config.CordMaxDistance then
                stopPulling(true)
                break
            end

            if IsControlPressed(0, (Config.PullControlKey or 38)) and dist > currentPullDistance then
                local dir = vector3(pedCoords.x - anchorCoords.x, pedCoords.y - anchorCoords.y, 0.0)
                local remaining = dist - currentPullDistance
                local step = math.min((Config.PullSpeed or 0.05), remaining)
                local move = spikeCoords + (norm(dir) * step)
                local moveZ = getGroundedZ(move.x, move.y, spikeCoords.z)

                local targetCoords = vector3(move.x, move.y, moveZ)
                if not isPullPathBlocked(entity, playerPed, spikeCoords, targetCoords) then
                    if Config.BlockPullThroughVehicles ~= false then
                        local pullSafetyRadius = tonumber(Config.PullVehicleSafetyRadius) or 1.8
                        local blockedByVehicle = isVehicleNearCoords(targetCoords, pullSafetyRadius, 0)
                        if blockedByVehicle then
                            goto continue
                        end
                    end

                    SetEntityCoordsNoOffset(entity, targetCoords.x, targetCoords.y, targetCoords.z, false, false, true)
                    placeObjectWithGroundClearance(entity, Config.GroundClearance or 0.03)
                end
            end

            ::continue::
        end
    end)
end

-- Tire burst pipeline
local function burstTireReliable(vehicle, wheelIndex)
    local damage = (Config.Deflation and Config.Deflation.PopDamage) or 1000.0

    SetVehicleTyreBurst(vehicle, wheelIndex, false, damage)
    if not IsVehicleTyreBurst(vehicle, wheelIndex, false) then
        SetVehicleTyreBurst(vehicle, wheelIndex, true, damage)
    end
end

local function tryBurstTireWithControl(vehicle, wheelIndex, timeoutMs)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return false end

    if not NetworkHasControlOfEntity(vehicle) then
        if not requestControl(vehicle, timeoutMs or 120) then
            return false
        end
    end

    burstTireReliable(vehicle, wheelIndex)
    return IsVehicleTyreBurst(vehicle, wheelIndex, false)
end

local function deflateTires(vehicle, wheelIndex)
    if IsVehicleTyreBurst(vehicle, wheelIndex, false) then return end

    if Config.Deflation and Config.Deflation.InstantPop then
        burstTireReliable(vehicle, wheelIndex)
        return
    end

    lib.notify({ title = "Tire Punctured", description = "Slow leak detected...", type = "warning" })

    local timer = 0
    local duration = Config.Deflation.Time

    CreateThread(function()
        while timer < duration do
            Wait(1000)
            timer = timer + 1000

            if GetEntitySpeed(vehicle) * 2.23 > Config.Deflation.WobbleThreshold then
                local currentSteer = GetVehicleSteeringAngle(vehicle)
                SetVehicleSteeringAngle(vehicle, currentSteer + math.random(-2, 2))
            end
        end
        burstTireReliable(vehicle, wheelIndex)
    end)
end

local function getProcessedKey(vehicleNetId, seq)
    return ("%s:%s"):format(vehicleNetId, seq)
end

local function cleanupCaches(now)
    if (now - lastCacheCleanupAt) < 30000 then return end
    lastCacheCleanupAt = now

    for key, expiresAt in pairs(wheelHitCooldowns) do
        if now >= expiresAt then
            wheelHitCooldowns[key] = nil
        end
    end

    for key, expiresAt in pairs(processedBurstByVehicle) do
        if now >= expiresAt then
            processedBurstByVehicle[key] = nil
        end
    end

    for key, data in pairs(lastWheelPositions) do
        if type(data) ~= "table" or type(data.at) ~= "number" or (now - data.at) > 30000 then
            lastWheelPositions[key] = nil
        end
    end
end

local function tryProcessVehicleBurst(vehicle, burstData)
    if type(burstData) ~= "table" then return false end

    local seq = tonumber(burstData.seq)
    local wheelIndex = tonumber(burstData.wheelIndex)
    if not seq or not wheelIndex then return false end

    local vehicleNetId = NetworkGetNetworkIdFromEntity(vehicle)
    if not vehicleNetId or vehicleNetId == 0 then return false end

    local key = getProcessedKey(vehicleNetId, seq)
    if processedBurstByVehicle[key] then return true end

    local localPed = PlayerPedId()
    local driverPed = GetPedInVehicleSeat(vehicle, -1)
    if driverPed ~= 0 and IsPedAPlayer(driverPed) and driverPed ~= localPed then
        return false
    end

    if not NetworkHasControlOfEntity(vehicle) then
        local timeoutMs = driverPed == localPed and 100 or 500
        if not requestControl(vehicle, timeoutMs) then
            return false
        end
    end

    deflateTires(vehicle, wheelIndex)
    processedBurstByVehicle[key] = GetGameTimer() + 120000
    TriggerServerEvent("ls_spikes:server:confirmBurst", vehicleNetId, seq)
    return true
end

-- Player/strip animations
local function playDeployAnimStage(ped, stageConfig)
    if not stageConfig then return end

    local dict = stageConfig.dict
    local clip = stageConfig.anim
    if not requestAnimDict(dict) then return end

    local duration = stageConfig.duration or 1000
    if stageConfig.loop == true and (stageConfig.duration == nil or stageConfig.duration > 0) then
        duration = -1
    end

    local taskFlag = stageConfig.flag
    if taskFlag == nil then
        taskFlag = stageConfig.loop == true and 1 or 49
    end

    TaskPlayAnim(
        ped,
        dict,
        clip,
        stageConfig.blendIn or 4.0,
        stageConfig.blendOut or 4.0,
        duration,
        taskFlag,
        stageConfig.playbackRate or 0.0,
        false,
        false,
        false
    )
end

local function runDeploySequence(itemLabel)
    local ped = PlayerPedId()
    local deployAnim = getAnimationConfig("deploy", DEFAULT_DEPLOY_ANIM)
    local placeDuration = math.max(100, math.floor(tonumber(deployAnim.duration) or DEFAULT_DEPLOY_ANIM.duration))

    playDeployAnimStage(ped, {
        dict = deployAnim.dict,
        anim = deployAnim.anim,
        duration = deployAnim.duration,
        flag = deployAnim.flag,
        blendIn = deployAnim.blendIn,
        blendOut = deployAnim.blendOut,
        playbackRate = deployAnim.playbackRate,
        loop = deployAnim.loop
    })

    local progressLabel = deployAnim.progressLabel or DEFAULT_DEPLOY_ANIM.progressLabel or "Deploying %s..."
    local success = lib.progressBar({
        duration = placeDuration,
        label = progressLabel:format(itemLabel or "Spike Strip"),
        useWhileDead = false,
        canCancel = deployAnim.canCancel ~= false,
        disable = { move = true, car = true, combat = true }
    })

    ClearPedTasks(ped)
    return success
end

local function runPickupSequence(itemLabel)
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        return false
    end

    local pickupAnim = getAnimationConfig("pickup", DEFAULT_PICKUP_ANIM)
    local duration = math.max(100, math.floor(tonumber(pickupAnim.duration) or DEFAULT_PICKUP_ANIM.duration))
    playDeployAnimStage(ped, {
        dict = pickupAnim.dict,
        anim = pickupAnim.anim,
        duration = duration,
        flag = pickupAnim.flag,
        blendIn = pickupAnim.blendIn,
        blendOut = pickupAnim.blendOut,
        playbackRate = pickupAnim.playbackRate,
        loop = pickupAnim.loop
    })

    local progressLabel = pickupAnim.label or DEFAULT_PICKUP_ANIM.label or "Picking up %s..."
    local success = lib.progressBar({
        duration = duration,
        label = progressLabel:format(itemLabel or "Spike Strip"),
        useWhileDead = false,
        canCancel = pickupAnim.canCancel ~= false,
        disable = { move = true, car = true, combat = true }
    })

    ClearPedTasks(ped)
    return success
end

local function playStripDeployAnimation(segments)
    local segmentAnim = getAnimationConfig("segmentDeploy", DEFAULT_SEGMENT_DEPLOY_ANIM)
    local animDict = segmentAnim.dict or DEFAULT_SEGMENT_DEPLOY_ANIM.dict
    local animName = segmentAnim.anim or DEFAULT_SEGMENT_DEPLOY_ANIM.anim
    local animSpeed = tonumber(segmentAnim.speed) or DEFAULT_SEGMENT_DEPLOY_ANIM.speed
    local animLoop = segmentAnim.loop == true
    local holdLastFrame = segmentAnim.holdLastFrame == true
    local driveToPose = segmentAnim.driveToPose == true
    local startPhase = tonumber(segmentAnim.startPhase) or DEFAULT_SEGMENT_DEPLOY_ANIM.startPhase
    local animFlags = tonumber(segmentAnim.flags) or DEFAULT_SEGMENT_DEPLOY_ANIM.flags
    local segmentCount = #segments
    if segmentCount == 0 then return end

    lib.requestAnimDict(animDict)

    local syncEnabled = segmentAnim.syncTimeline == true

    if syncEnabled and segmentCount > 1 then
        local validSegments = {}
        for _, segment in ipairs(segments) do
            if DoesEntityExist(segment) then
                PlayEntityAnim(segment, animName, animDict, animSpeed, animLoop, holdLastFrame, driveToPose, startPhase, animFlags)
                validSegments[#validSegments + 1] = segment
            end
        end

        local primary = validSegments[1]
        if primary and DoesEntityExist(primary) then
            local syncDurationConfig = tonumber(segmentAnim.syncDurationMs) or 1250
            local syncDurationMs = math.max(350, math.floor(syncDurationConfig))
            local startedAt = GetGameTimer()

            while (GetGameTimer() - startedAt) < syncDurationMs do
                if not DoesEntityExist(primary) or not IsEntityPlayingAnim(primary, animDict, animName, 3) then
                    break
                end

                local basePhase = clamp(GetEntityAnimCurrentTime(primary, animDict, animName), 0.0, 1.0)
                local total = #validSegments

                for index = 2, total do
                    local segment = validSegments[index]
                    if DoesEntityExist(segment) and IsEntityPlayingAnim(segment, animDict, animName, 3) then
                        local offset = (index - 1) / total
                        local denom = 1.0 - offset
                        local linkedPhase = basePhase
                        if denom > 0.0 then
                            linkedPhase = clamp((basePhase - offset) / denom, 0.0, 1.0)
                        end

                        SetEntityAnimCurrentTime(segment, animDict, animName, linkedPhase)
                    end
                end

                Wait(0)
            end
        end
    else
        local delayConfig = tonumber(segmentAnim.delayMs) or 180
        local segmentDeployDelayMs = math.max(0, math.floor(delayConfig))
        for index, segment in ipairs(segments) do
            if DoesEntityExist(segment) then
                PlayEntityAnim(segment, animName, animDict, animSpeed, animLoop, holdLastFrame, driveToPose, startPhase, animFlags)
            end

            if segmentDeployDelayMs > 0 and index < segmentCount then
                Wait(segmentDeployDelayMs)
            end
        end
    end

    RemoveAnimDict(animDict)
end

AddStateBagChangeHandler("ls_spikes_burst", "", function(bagName, key, value, reserved, replicated)
    local entity = GetEntityFromStateBagName(bagName)
    if entity == 0 or not DoesEntityExist(entity) then return end
    if type(value) ~= "table" then return end

    CreateThread(function()
        for _ = 1, 40 do
            if not DoesEntityExist(entity) then return end
            if tryProcessVehicleBurst(entity, value) then
                return
            end
            Wait(100)
        end
    end)
end)

-- Deploy item entrypoint
RegisterNetEvent("ls_spikes:client:deploy", function(itemName)
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return end

    local itemConfig = getItemConfig(itemName)

    if GetInteriorFromEntity(ped) ~= 0 then
        lib.notify({ title = "Invalid Area", description = "Cannot deploy indoors", type = "error" })
        return
    end

    local selectedPos, selectedHeading, cancelled = runPlacementPreview(itemConfig)
    if cancelled or not selectedPos then
        return
    end

    if runDeploySequence(itemConfig.label or "Spike Strip") then
        lib.requestModel(itemConfig.model)
        local finalHeading = selectedHeading or (GetEntityHeading(ped) + (itemConfig.headingOffset or 0.0))
        local segments = spawnStripSegments(itemConfig, selectedPos, finalHeading)

        playStripDeployAnimation(segments)

        local netIds = {}
        for _, segment in ipairs(segments) do
            if DoesEntityExist(segment) then
                netIds[#netIds + 1] = NetworkGetNetworkIdFromEntity(segment)
            end
        end

        if #netIds > 0 then
            TriggerServerEvent("ls_spikes:server:registerStrip", netIds, selectedPos, itemName)
        end
    end
end)

-- Continuous spike hit scan (player + nearby NPC vehicles)
local function processVehicleSpikeHits(vehicle, nearbySpikes)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return end

    local vehicleNetId = NetworkGetNetworkIdFromEntity(vehicle)
    if not vehicleNetId or vehicleNetId == 0 then return end
    local localPed = PlayerPedId()
    local localDriverVehicle = GetPedInVehicleSeat(vehicle, -1) == localPed

    local pendingBurst = Entity(vehicle).state.ls_spikes_burst
    if pendingBurst then
        tryProcessVehicleBurst(vehicle, pendingBurst)
    end

    if #nearbySpikes == 0 then return end

    local minContactSpeed = Config.MinimumSpikeContactSpeed or 1.0
    local vehicleSpeed = GetEntitySpeed(vehicle)
    if vehicleSpeed < minContactSpeed then return end

    local closestHit = nil
    local contactingHits = {}
    local boneIndices = getWheelBoneIndices(vehicle)
    local now = GetGameTimer()

    for wheelListIndex = 1, #WHEELS do
        local wheel = WHEELS[wheelListIndex]
        if IsVehicleTyreBurst(vehicle, wheel.index, false) then
            goto continue_wheel
        end

        local boneIndex = boneIndices[wheelListIndex]
        local wheelTrackKey = getWheelTrackKey(vehicleNetId, wheel.index)
        if boneIndex ~= -1 then
            local wheelPos = GetWorldPositionOfEntityBone(vehicle, boneIndex)
            local previousWheelData = lastWheelPositions[wheelTrackKey]
            local previousWheelPos = previousWheelData and previousWheelData.pos or nil
            local matchedSpike, matchedDistanceSq = findMatchingSpikeForWheel(wheelPos, previousWheelPos, nearbySpikes)
            lastWheelPositions[wheelTrackKey] = {
                pos = wheelPos,
                at = now
            }

            if matchedSpike ~= 0 then
                local spikeData = Entity(matchedSpike).state.stripData
                local isPulledStrip = isPulling and currentPullStripId and spikeData and spikeData.id == currentPullStripId
                if not isPulledStrip then
                    if localDriverVehicle and (Config.LocalImmediatePopOnHit ~= false) then
                        local controlTimeoutMs = tonumber(Config.ImmediatePopControlTimeoutMs) or 120
                        tryBurstTireWithControl(vehicle, wheel.index, controlTimeoutMs)
                    end

                    local retryCooldownMs = Config.TireRetryCooldownMs or 250
                    local cooldownMs = Config.TireHitCooldownMs or 1200
                    local stripId = spikeData and spikeData.id or 0
                    local cooldownKey = getWheelCooldownKey(vehicleNetId, wheel.index, stripId)
                    local nextAllowed = wheelHitCooldowns[cooldownKey] or 0
                    local cooldownWindowMs = IsVehicleTyreBurst(vehicle, wheel.index, false) and cooldownMs or retryCooldownMs

                    if now >= nextAllowed then
                        wheelHitCooldowns[cooldownKey] = now + cooldownWindowMs
                        local hitEntry = {
                            wheelIndex = wheel.index,
                            stripId = spikeData and spikeData.id or nil,
                            spikeNetId = NetworkGetNetworkIdFromEntity(matchedSpike),
                            distanceSq = matchedDistanceSq
                        }
                        contactingHits[#contactingHits + 1] = hitEntry

                        if not closestHit or matchedDistanceSq < closestHit.distanceSq then
                            closestHit = hitEntry
                        end
                    end
                end
            end
        else
            lastWheelPositions[wheelTrackKey] = nil
        end

        ::continue_wheel::
    end

    if Config.PopAllContactingTires then
        for _, hit in ipairs(contactingHits) do
            TriggerServerEvent("ls_spikes:server:onHit", hit.stripId, vehicleNetId, hit.wheelIndex, hit.spikeNetId)
        end
    elseif closestHit then
        TriggerServerEvent("ls_spikes:server:onHit", closestHit.stripId, vehicleNetId, closestHit.wheelIndex, closestHit.spikeNetId)
    end
end

CreateThread(function()
    local cachedNearbySpikes = {}
    local nearbySpikesScannedAt = 0
    local lastSpikeScanCenter = nil
    local cachedNpcVehicles = {}
    local npcVehiclesScannedAt = 0

    while true do
        local now = GetGameTimer()
        cleanupCaches(now)

        local ped = PlayerPedId()
        local pedCoords = GetEntityCoords(ped)
        local playerVehicle = GetVehiclePedIsIn(ped, false)
        local playerIsDriver = playerVehicle ~= 0 and GetPedInVehicleSeat(playerVehicle, -1) == ped

        local scanCenter = pedCoords
        if playerIsDriver then
            scanCenter = GetEntityCoords(playerVehicle)
        end

        local spikeScanIntervalMs = playerIsDriver and (Config.SpikeScanIntervalDrivingMs or 75) or (Config.SpikeScanIntervalMs or 250)
        local spikeScanRadius = Config.SpikeScanRadius or 16.0
        local forceSpikeScan = false

        if not lastSpikeScanCenter then
            forceSpikeScan = true
        else
            local dx = scanCenter.x - lastSpikeScanCenter.x
            local dy = scanCenter.y - lastSpikeScanCenter.y
            local dz = scanCenter.z - lastSpikeScanCenter.z
            local movedDistanceSq = dx * dx + dy * dy + dz * dz
            local rescanDistance = tonumber(Config.SpikeRescanDistance) or 1.6
            if movedDistanceSq >= (rescanDistance * rescanDistance) then
                forceSpikeScan = true
            end
        end

        if forceSpikeScan or (now - nearbySpikesScannedAt) >= spikeScanIntervalMs then
            cachedNearbySpikes = getNearbySpikeObjects(scanCenter, spikeScanRadius)
            nearbySpikesScannedAt = now
            lastSpikeScanCenter = scanCenter
        end

        if playerIsDriver then
            processVehicleSpikeHits(playerVehicle, cachedNearbySpikes)
        end

        if Config.EnableNpcTireBurst ~= false then
            local npcScanIntervalMs = Config.NpcVehicleScanIntervalMs or 450
            local npcScanRadius = Config.NpcVehicleScanRadius or 70.0

            if (now - npcVehiclesScannedAt) >= npcScanIntervalMs then
                cachedNpcVehicles = {}
                local npcScanRadiusSq = npcScanRadius * npcScanRadius

                for _, vehicle in ipairs(GetGamePool("CVehicle")) do
                    if vehicle ~= playerVehicle and DoesEntityExist(vehicle) then
                        local driverPed = GetPedInVehicleSeat(vehicle, -1)
                        if driverPed ~= 0 and not IsPedAPlayer(driverPed) then
                            local vehicleCoords = GetEntityCoords(vehicle)
                            local dx = pedCoords.x - vehicleCoords.x
                            local dy = pedCoords.y - vehicleCoords.y
                            local dz = pedCoords.z - vehicleCoords.z
                            if (dx * dx + dy * dy + dz * dz) <= npcScanRadiusSq then
                                cachedNpcVehicles[#cachedNpcVehicles + 1] = vehicle
                            end
                        end
                    end
                end

                npcVehiclesScannedAt = now
            end

            for index = 1, #cachedNpcVehicles do
                local npcVehicle = cachedNpcVehicles[index]
                if DoesEntityExist(npcVehicle) then
                    processVehicleSpikeHits(npcVehicle, cachedNearbySpikes)
                end
            end
        else
            cachedNpcVehicles = {}
            npcVehiclesScannedAt = 0
        end

        if #cachedNearbySpikes > 0 or playerIsDriver then
            Wait(playerIsDriver and (Config.DriverHitScanTickMs or 75) or 125)
        else
            Wait(425)
        end
    end
end)

-- Target interactions
local spikeTargetOptions = {
    {
        name = "pickup_spike",
        icon = "fa-solid fa-hand-holding",
        label = "Pick Up Spike Strip",
        canInteract = function(entity)
            return canInteractWithSpikeEntity(entity)
        end,
        onSelect = function(data)
            local state = Entity(data.entity).state.stripData
            local stripId = state and state.id or nil
            local itemName = state and state.itemName or "spikestrip"
            local itemLabel = getItemConfig(itemName).label or "Spike Strip"

            if runPickupSequence(itemLabel) then
                TriggerServerEvent("ls_spikes:server:pickup", stripId, NetworkGetNetworkIdFromEntity(data.entity))
            end
        end
    },
    {
        name = "check_durability",
        icon = "fa-solid fa-shield-halved",
        label = "Check Status",
        canInteract = function(entity)
            return canInteractWithSpikeEntity(entity)
        end,
        onSelect = function(data)
            local netId = NetworkGetNetworkIdFromEntity(data.entity)
            local result = lib.callback.await("ls_spikes:server:getStripStatus", false, netId)

            if result and result.ok then
                lib.notify({ title = result.title or "Stop Stick Status", description = result.message or "Status unavailable", type = "info" })
            else
                lib.notify({ title = "Stop Stick Status", description = (result and result.message) or "Unable to read strip status", type = "error" })
            end
        end
    },
    {
        name = "pull_spike",
        icon = "fa-solid fa-rope-angled",
        label = "Pull Spike Strip",
        canInteract = function(entity)
            return canInteractWithSpikeEntity(entity) and not isPulling
        end,
        onSelect = function(data)
            startPulling(data.entity)
        end
    },
    {
        name = "stop_pull_spike",
        icon = "fa-solid fa-circle-stop",
        label = "Stop Pulling",
        canInteract = function(entity)
            return canInteractWithSpikeEntity(entity) and isPulling and currentStrip == entity
        end,
        onSelect = function(data)
            stopPulling(false)
        end
    }
}

local spikeTargetsRegistered = false

-- Resource lifecycle hooks
local function registerSpikeTargets()
    if spikeTargetsRegistered then return true end

    local targetState = GetResourceState("ox_target")
    if targetState ~= "started" then
        return false
    end

    local ok = pcall(function()
        exports.ox_target:addModel(getSpikeModels(), spikeTargetOptions)
    end)

    if ok then
        spikeTargetsRegistered = true
    end

    return ok
end

CreateThread(function()
    for _ = 1, 20 do
        if registerSpikeTargets() then
            return
        end

        Wait(500)
    end
end)

AddEventHandler("onResourceStart", function(resource)
    if resource == "ox_target" or resource == GetCurrentResourceName() then
        registerSpikeTargets()
    end
end)

AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() then return end
    stopPulling(false)
    hidePullUiText()
    clearPullRope()
end)


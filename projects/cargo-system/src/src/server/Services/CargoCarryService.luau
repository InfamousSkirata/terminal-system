local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local CargoRegistry = require(script.Parent.CargoRegistry)
local CargoPersistenceService = require(script.Parent.CargoPersistenceService)
local Diagnostics = require(script.Parent.Diagnostics)

local CargoCarryService = {}

local carriedByUserId: {[number]: string} = {}
local droppedFollowByCargoId: {[string]: {surface: BasePart, localCFrame: CFrame, lastSurfaceCFrame: CFrame?}} = {}
local lastFollowRebuildAt = 0
local lastDroppedSelfHealAt = 0
local lastPromptRefreshAt = 0
local dropRng = Random.new()
local dropTuning = Config.Cargo.DropTuning or {}
local despawnConfig = Config.Cargo.Despawn or {}
local STACK_CLEARANCE_Y = dropTuning.StackClearanceY or 0.06
local STACK_YAW_MAX_DEG = dropTuning.StackYawMaxDeg or 0.6
local NON_STACK_MIN_CARGO_SPACING = dropTuning.NonStackMinCargoSpacing or 2.6
local STACK_SNAP_RADIUS = dropTuning.StackSnapRadius or 3.2
local DROPPED_LIFETIME_SEC = despawnConfig.DroppedLifetimeSec or 900
local NO_PLAYER_RADIUS = despawnConfig.NoPlayerRadius or 220
local VOID_Y = despawnConfig.VoidY or -200
local settleDroppedCargo: (cargoId: string, excludedSurfaceCarrier: Instance?, preferNonCargoSurface: boolean?) -> ()

local function setCarryingAttribute(player: Player, isCarrying: boolean)
    player:SetAttribute("IsCarryingCargo", isCarrying)
end

local function getCharacterRoot(player: Player): BasePart?
    local character = player.Character
    if not character then
        return nil
    end
    local root = character:FindFirstChild("HumanoidRootPart")
    if root and root:IsA("BasePart") then
        return root
    end
    return nil
end

local function projectLookOnUp(look: Vector3, up: Vector3): Vector3
    local projected = look - (up * look:Dot(up))
    if projected.Magnitude < 1e-4 then
        return Vector3.new(0, 0, -1)
    end
    return projected.Unit
end

local function getPrimaryPart(cargoModel: Model): BasePart?
    if cargoModel.PrimaryPart then
        return cargoModel.PrimaryPart
    end
    local part = cargoModel:FindFirstChildWhichIsA("BasePart")
    if part then
        cargoModel.PrimaryPart = part
        return part
    end
    return nil
end

local function findCargoModelFromInstance(instance: Instance?): Model?
    local current = instance
    while current do
        if current:IsA("Model") then
            local cargoId = current:GetAttribute("CargoId")
            if type(cargoId) == "string" and cargoId ~= "" then
                return current
            end
        end
        current = current.Parent
    end
    return nil
end

local function isCargoModelCarried(cargoModel: Model): boolean
    local status = cargoModel:GetAttribute("Status")
    if status == "InTransit" then
        return true
    end
    local holder = cargoModel:GetAttribute("CurrentHolderUserId")
    if type(holder) == "number" and holder > 0 then
        return true
    end
    return false
end

local function isPartOnOtherCargo(part: BasePart, selfModel: Model): boolean
    local current: Instance? = part
    while current do
        if current:IsA("Model") then
            if current == selfModel then
                return false
            end
            local cargoId = current:GetAttribute("CargoId")
            if type(cargoId) == "string" and cargoId ~= "" then
                return true
            end
        end
        current = current.Parent
    end
    return false
end

local function hasBlockingCargoOverlap(primaryPart: BasePart, cargoModel: Model): boolean
    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { cargoModel }
    params.MaxParts = 20

    local overlaps = Workspace:GetPartBoundsInBox(primaryPart.CFrame, primaryPart.Size * 0.94, params)
    for _, part in ipairs(overlaps) do
        if part:IsA("BasePart") and isPartOnOtherCargo(part, cargoModel) then
            return true
        end
    end
    return false
end

local function resolveCargoInterpenetration(primaryPart: BasePart, cargoModel: Model)
    local startCf = primaryPart.CFrame
    for _ = 1, 18 do
        if not hasBlockingCargoOverlap(primaryPart, cargoModel) then
            return
        end
        primaryPart.CFrame = primaryPart.CFrame + Vector3.new(0, 0.12, 0)
    end

    local baseCf = startCf
    local radii = { 1.0, 1.6, 2.2, 2.8 }
    local angles = { 0, 45, 90, 135, 180, 225, 270, 315 }
    for _, radius in ipairs(radii) do
        for _, angleDeg in ipairs(angles) do
            local angle = math.rad(angleDeg)
            local offset = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
            primaryPart.CFrame = baseCf + offset
            for _ = 1, 8 do
                if not hasBlockingCargoOverlap(primaryPart, cargoModel) then
                    return
                end
                primaryPart.CFrame = primaryPart.CFrame + Vector3.new(0, 0.12, 0)
            end
        end
    end

    primaryPart.CFrame = baseCf
end

local function isNearOtherCargo(position: Vector3, ignoreModel: Model?): boolean
    for _, tagged in ipairs(CollectionService:GetTagged("CargoCrate")) do
        if tagged:IsA("Model") and tagged ~= ignoreModel then
            local part = getPrimaryPart(tagged)
            if part then
                local delta = part.Position - position
                local planar = Vector3.new(delta.X, 0, delta.Z).Magnitude
                if planar < NON_STACK_MIN_CARGO_SPACING then
                    return true
                end
            end
        end
    end
    return false
end

local function findNearbyCargoSurfaceForSnap(root: BasePart, cargoModel: Model, hintPosition: Vector3): BasePart?
    local bestPart: BasePart? = nil
    local bestScore = math.huge

    for _, tagged in ipairs(CollectionService:GetTagged("CargoCrate")) do
        if tagged:IsA("Model") and tagged ~= cargoModel then
            if isCargoModelCarried(tagged) then
                continue
            end
            local part = getPrimaryPart(tagged)
            if part then
                local toPart = part.Position - root.Position
                local forwardDot = 0
                if toPart.Magnitude > 1e-4 then
                    forwardDot = toPart.Unit:Dot(root.CFrame.LookVector)
                end
                if forwardDot >= -0.1 then
                    local planarFromHint = Vector3.new(part.Position.X - hintPosition.X, 0, part.Position.Z - hintPosition.Z).Magnitude
                    if planarFromHint <= STACK_SNAP_RADIUS then
                        local score = planarFromHint + (math.max(0, 0.4 - forwardDot) * 2)
                        if score < bestScore then
                            bestScore = score
                            bestPart = part
                        end
                    end
                end
            end
        end
    end

    return bestPart
end

local function applyRecordToAttributes(cargoModel: Model, record)
    cargoModel:SetAttribute("CurrentHolderUserId", record.CurrentHolderUserId)
    cargoModel:SetAttribute("Status", record.Status)
    cargoModel:SetAttribute("IsStolen", record.IsStolen)
end

local function canInteract(player: Player, position: Vector3): boolean
    local root = getCharacterRoot(player)
    if not root then
        return false
    end
    return (root.Position - position).Magnitude <= Config.Cargo.MaxInteractDistance
end

local function clearDropWeld(primaryPart: BasePart)
    local existing = primaryPart:FindFirstChild("CargoDropWeld")
    if existing and (existing:IsA("WeldConstraint") or existing:IsA("Weld")) then
        existing:Destroy()
    end
end

local function createDropWeld(primaryPart: BasePart, surfacePart: BasePart)
    clearDropWeld(primaryPart)
    local weld = Instance.new("WeldConstraint")
    weld.Name = "CargoDropWeld"
    weld.Part0 = surfacePart
    weld.Part1 = primaryPart
    weld.Parent = primaryPart
end

local function clearCarryWeld(primaryPart: BasePart)
    local existing = primaryPart:FindFirstChild("CargoCarryWeld")
    if existing and existing:IsA("WeldConstraint") then
        existing:Destroy()
    end
end

local function setPickupPromptEnabled(cargoModel: Model, isEnabled: boolean)
    local primaryPart = getPrimaryPart(cargoModel)
    if not primaryPart then
        return
    end

    local prompt = primaryPart:FindFirstChild("CargoPickupPrompt")
    if prompt and prompt:IsA("ProximityPrompt") then
        prompt.Enabled = isEnabled
    end
end

local function setDroppedPlacementAttributes(cargoModel: Model, surface: BasePart, localCFrame: CFrame, worldCFrame: CFrame)
    local surfaceCargoId: string? = nil
    local current: Instance? = surface
    while current do
        if current:IsA("Model") then
            local maybeCargoId = current:GetAttribute("CargoId")
            if type(maybeCargoId) == "string" and maybeCargoId ~= "" then
                surfaceCargoId = maybeCargoId
                break
            end
        end
        current = current.Parent
    end

    cargoModel:SetAttribute("DropSurfacePath", surface:GetFullName())
    cargoModel:SetAttribute("DropSurfaceCargoId", surfaceCargoId)
    cargoModel:SetAttribute("DropLocalCFrame", localCFrame)
    cargoModel:SetAttribute("DropWorldCFrame", worldCFrame)
    cargoModel:SetAttribute("DroppedAt", os.clock())
end

local function clearDroppedPlacementAttributes(cargoModel: Model)
    cargoModel:SetAttribute("DropSurfacePath", nil)
    cargoModel:SetAttribute("DropSurfaceCargoId", nil)
    cargoModel:SetAttribute("DropLocalCFrame", nil)
    cargoModel:SetAttribute("DropWorldCFrame", nil)
    cargoModel:SetAttribute("DroppedAt", nil)
end

local function buildCharacterExcludes(baseExcludes: {Instance}): {Instance}
    local excludes = {}
    for _, instance in ipairs(baseExcludes) do
        table.insert(excludes, instance)
    end

    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        if character then
            table.insert(excludes, character)
        end
    end

    return excludes
end

local function isCargoSurface(surface: Instance): boolean
    local current: Instance? = surface
    while current do
        if current:IsA("Model") then
            local cargoId = current:GetAttribute("CargoId")
            if type(cargoId) == "string" and cargoId ~= "" then
                if isCargoModelCarried(current) then
                    return false
                end
                return true
            end
            if CollectionService:HasTag(current, "CargoCrate") then
                if isCargoModelCarried(current) then
                    return false
                end
                return true
            end
        end
        current = current.Parent
    end
    return false
end

local function getSurfaceCargoId(surface: Instance): string?
    local current: Instance? = surface
    while current do
        if current:IsA("Model") then
            if isCargoModelCarried(current) then
                return nil
            end
            local cargoId = current:GetAttribute("CargoId")
            if type(cargoId) == "string" and cargoId ~= "" then
                return cargoId
            end
        end
        current = current.Parent
    end
    return nil
end

local function isSurfaceDescendantOfModel(surface: BasePart?, cargoModel: Model): boolean
    if not surface then
        return false
    end
    local current: Instance? = surface
    while current do
        if current == cargoModel then
            return true
        end
        current = current.Parent
    end
    return false
end

local function hasStackedCargoAbove(targetCargoId: string, targetModel: Model): boolean
    for _, tagged in ipairs(CollectionService:GetTagged("CargoCrate")) do
        if tagged:IsA("Model") and tagged ~= targetModel then
            local depStatus = tagged:GetAttribute("Status")
            if depStatus == "Dropped" then
                local depSurfaceCargoId = tagged:GetAttribute("DropSurfaceCargoId")
                if depSurfaceCargoId == targetCargoId then
                    return true
                end
            end
        end
    end
    return false
end

local function shouldEnablePickupPrompt(cargoId: string, cargoModel: Model, status: string?): boolean
    if status == "InTransit" then
        return false
    end
    if status == "Dropped" and hasStackedCargoAbove(cargoId, cargoModel) then
        return false
    end
    return true
end

local function isAnyPlayerNear(position: Vector3, radius: number): boolean
    local radiusSq = radius * radius
    for _, player in ipairs(Players:GetPlayers()) do
        local root = getCharacterRoot(player)
        if root then
            local delta = root.Position - position
            local planarSq = (delta.X * delta.X) + (delta.Z * delta.Z)
            if planarSq <= radiusSq then
                return true
            end
        end
    end
    return false
end

local function refreshPickupPromptStates()
    for _, tagged in ipairs(CollectionService:GetTagged("CargoCrate")) do
        if tagged:IsA("Model") then
            local cargoId = tagged:GetAttribute("CargoId")
            if type(cargoId) == "string" and cargoId ~= "" then
                local status = tagged:GetAttribute("Status")
                setPickupPromptEnabled(tagged, shouldEnablePickupPrompt(cargoId, tagged, status))
            end
        end
    end
end

local function getCargoModelFromSurface(surface: Instance): Model?
    local current: Instance? = surface
    while current do
        if current:IsA("Model") then
            if isCargoModelCarried(current) then
                return nil
            end
            local cargoId = current:GetAttribute("CargoId")
            if type(cargoId) == "string" and cargoId ~= "" then
                return current
            end
            if CollectionService:HasTag(current, "CargoCrate") then
                return current
            end
        end
        current = current.Parent
    end
    return nil
end

local function getCargoModelTopY(cargoModel: Model): number?
    local maxTopY: number? = nil
    for _, descendant in ipairs(cargoModel:GetDescendants()) do
        if descendant:IsA("BasePart") then
            local topY = descendant.Position.Y + (descendant.Size.Y * 0.5)
            if maxTopY == nil or topY > maxTopY then
                maxTopY = topY
            end
        end
    end
    return maxTopY
end

local function getFlatLookFromVector(lookVector: Vector3): Vector3
    local flat = Vector3.new(lookVector.X, 0, lookVector.Z)
    if flat.Magnitude < 1e-4 then
        return Vector3.new(0, 0, -1)
    end
    return flat.Unit
end

local function getStackDropCFrame(cargoModel: Model, supportCargoModel: Model, lookVector: Vector3): CFrame
    local supportCf, supportSize = supportCargoModel:GetBoundingBox()
    local _, dropSize = cargoModel:GetBoundingBox()
    local supportTopY = supportCf.Position.Y + (supportSize.Y * 0.5)
    local dropHalfY = dropSize.Y * 0.5
    local pos = Vector3.new(
        supportCf.Position.X,
        supportTopY + dropHalfY + STACK_CLEARANCE_Y,
        supportCf.Position.Z
    )
    local flatLook = getFlatLookFromVector(lookVector)
    local baseCf = CFrame.lookAt(pos, pos + flatLook, Vector3.new(0, 1, 0))
    local yaw = math.rad(dropRng:NextNumber(-STACK_YAW_MAX_DEG, STACK_YAW_MAX_DEG))
    return baseCf * CFrame.fromAxisAngle(Vector3.new(0, 1, 0), yaw)
end

local function findByFullNamePath(path: string): Instance?
    local segments = string.split(path, ".")
    if #segments == 0 then
        return nil
    end

    local root: Instance? = nil
    if segments[1] == "Workspace" then
        root = workspace
    elseif segments[1] == "game" then
        root = game
    end
    if not root then
        return nil
    end

    local startIndex = 2
    if segments[1] == "game" and segments[2] == "Workspace" then
        root = workspace
        startIndex = 3
    end

    local current: Instance = root
    for i = startIndex, #segments do
        local nextInstance = current:FindFirstChild(segments[i])
        if not nextInstance then
            return nil
        end
        current = nextInstance
    end
    return current
end

local function resolveDropSurfacePart(cargoModel: Model): BasePart?
    local surfaceCargoId = cargoModel:GetAttribute("DropSurfaceCargoId")
    if type(surfaceCargoId) == "string" and surfaceCargoId ~= "" then
        local supportModel = CargoRegistry.getInstanceById(surfaceCargoId)
        if supportModel then
            local supportPart = getPrimaryPart(supportModel)
            if supportPart then
                return supportPart
            end
        end
    end

    local path = cargoModel:GetAttribute("DropSurfacePath")
    if type(path) == "string" and path ~= "" then
        local inst = findByFullNamePath(path)
        if inst and inst:IsA("BasePart") then
            return inst
        end
    end

    return nil
end

local function selfHealDroppedCargo()
    local toDespawn: {string} = {}
    for _, tagged in ipairs(CollectionService:GetTagged("CargoCrate")) do
        if tagged:IsA("Model") then
            local cargoId = tagged:GetAttribute("CargoId")
            local status = tagged:GetAttribute("Status")
            local primaryPart = getPrimaryPart(tagged)
            if type(cargoId) == "string" and cargoId ~= "" and primaryPart then
                local record = CargoRegistry.getById(cargoId)
                local isCarried = record and (record.Status == "InTransit" or record.CurrentHolderUserId ~= nil)
                if not isCarried then
                    if status == "Dropped" then
                        local surfacePart = resolveDropSurfacePart(tagged)
                        if surfacePart then
                            local existingDropWeld = primaryPart:FindFirstChild("CargoDropWeld")
                            if not (existingDropWeld and existingDropWeld:IsA("WeldConstraint")) then
                                local localCf = tagged:GetAttribute("DropLocalCFrame")
                                if typeof(localCf) == "CFrame" then
                                    primaryPart.CFrame = surfacePart.CFrame * localCf
                                end
                                createDropWeld(primaryPart, surfacePart)
                            end
                            primaryPart.Anchored = false
                            primaryPart.CanCollide = true
                        else
                            -- Surface disappeared (for example, destroyed ship part).
                            -- Re-home to nearest ground when possible, otherwise let physics drop it.
                            clearDropWeld(primaryPart)
                            local params = RaycastParams.new()
                            params.FilterType = Enum.RaycastFilterType.Exclude
                            params.FilterDescendantsInstances = buildCharacterExcludes({ tagged })
                            local hit = Workspace:Raycast(primaryPart.Position + Vector3.new(0, 3, 0), Vector3.new(0, -1200, 0), params)
                            if hit and hit.Instance and hit.Instance:IsA("BasePart") then
                                local up = hit.Normal.Unit
                                local look = projectLookOnUp(primaryPart.CFrame.LookVector, up)
                                local pos = hit.Position + (up * ((primaryPart.Size.Y * 0.5) + 0.05))
                                primaryPart.CFrame = CFrame.lookAt(pos, pos + look, up)
                                resolveCargoInterpenetration(primaryPart, tagged)
                                createDropWeld(primaryPart, hit.Instance)
                                setDroppedPlacementAttributes(tagged, hit.Instance, hit.Instance.CFrame:ToObjectSpace(primaryPart.CFrame), primaryPart.CFrame)
                                primaryPart.Anchored = false
                                primaryPart.CanCollide = true
                            else
                                clearDroppedPlacementAttributes(tagged)
                                primaryPart.Anchored = false
                                primaryPart.CanCollide = true
                            end
                        end
                    end

                    if status == "Dropped" then
                        local dropAt = tagged:GetAttribute("DroppedAt")
                        local dropAge = if type(dropAt) == "number" then (os.clock() - dropAt) else 0
                        local isAbandoned = dropAge >= DROPPED_LIFETIME_SEC and (not isAnyPlayerNear(primaryPart.Position, NO_PLAYER_RADIUS))
                        local isInVoid = primaryPart.Position.Y <= VOID_Y
                        if isAbandoned or isInVoid then
                            table.insert(toDespawn, cargoId)
                        end
                    end
                end
            end
        end
    end

    for _, cargoId in ipairs(toDespawn) do
        CargoCarryService.destroyCargoById(cargoId, "DESPAWN")
    end
end

local function getStackDepthForSurface(surface: Instance): number
    local cargoId = getSurfaceCargoId(surface)
    if not cargoId then
        return 0
    end
    local cargoModel = getCargoModelFromSurface(surface)
    if not cargoModel then
        return 1
    end
    local isUpperInStack = false
    local supportCargoId = cargoModel:GetAttribute("DropSurfaceCargoId")
    if type(supportCargoId) == "string" and supportCargoId ~= "" then
        isUpperInStack = true
    end
    if isUpperInStack or hasStackedCargoAbove(cargoId, cargoModel) then
        return 2
    end
    return 1
end

local function canStackOnCargoSurface(surface: Instance): boolean
    local cargoId = getSurfaceCargoId(surface)
    if not cargoId then
        return false
    end
    local cargoModel = getCargoModelFromSurface(surface)
    if not cargoModel then
        return false
    end

    local supportCargoId = cargoModel:GetAttribute("DropSurfaceCargoId")
    if type(supportCargoId) == "string" and supportCargoId ~= "" then
        return false
    end

    if hasStackedCargoAbove(cargoId, cargoModel) then
        return false
    end

    return true
end

local function getTopSurfaceDropPosition(surfacePart: BasePart, primaryPart: BasePart, hitPosition: Vector3, onCargoSurface: boolean): Vector3
    local topY = surfacePart.Position.Y + (surfacePart.Size.Y * 0.5)
    local centerX = surfacePart.Position.X
    local centerZ = surfacePart.Position.Z
    if onCargoSurface then
        local cargoModel = getCargoModelFromSurface(surfacePart)
        if cargoModel then
            local modelTopY = getCargoModelTopY(cargoModel)
            if modelTopY then
                topY = modelTopY
            end
            local cargoPrimary = getPrimaryPart(cargoModel)
            if cargoPrimary then
                centerX = cargoPrimary.Position.X
                centerZ = cargoPrimary.Position.Z
            end
        end
    end
    local clearance = onCargoSurface and STACK_CLEARANCE_Y or 0.05
    local dropY = topY + (primaryPart.Size.Y * 0.5) + clearance
    if onCargoSurface then
        -- For cargo-on-cargo stacking, snap to top-center for stable placement.
        return Vector3.new(centerX, dropY, centerZ)
    end
    return Vector3.new(hitPosition.X, dropY, hitPosition.Z)
end

local function raycastNonCargoNearby(center: Vector3, forward: Vector3, right: Vector3, cargoModel: Model, nearDistance: number?): RaycastResult?
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = buildCharacterExcludes({ cargoModel })

    local near = nearDistance or 2
    local probes = {
        center + Vector3.new(0, 2, 0),
        center + (forward * near) + Vector3.new(0, 2, 0),
        center - (forward * near) + Vector3.new(0, 2, 0),
        center + (right * near) + Vector3.new(0, 2, 0),
        center - (right * near) + Vector3.new(0, 2, 0),
        center + (forward * near) + (right * near) + Vector3.new(0, 2, 0),
        center + (forward * near) - (right * near) + Vector3.new(0, 2, 0),
        center - (forward * near) + (right * near) + Vector3.new(0, 2, 0),
        center - (forward * near) - (right * near) + Vector3.new(0, 2, 0),
    }
    local down = Vector3.new(0, -(Config.Cargo.DropRayDistance + 30), 0)

    local best: RaycastResult? = nil
    local bestDistance = math.huge
    local bestY = -math.huge
    for _, origin in ipairs(probes) do
        local result = Workspace:Raycast(origin, down, params)
        if result and result.Instance and result.Instance:IsA("BasePart") and result.Normal.Y >= 0.6 and not isCargoSurface(result.Instance) then
            if isNearOtherCargo(result.Position, cargoModel) then
                continue
            end
            local planarOffset = Vector3.new(result.Position.X - center.X, 0, result.Position.Z - center.Z)
            local distance = planarOffset.Magnitude
            if distance < bestDistance or (math.abs(distance - bestDistance) < 0.01 and result.Position.Y > bestY) then
                bestDistance = distance
                bestY = result.Position.Y
                best = result
            end
        end
    end

    return best
end

local function raycastDropSurface(root: BasePart, cargoModel: Model): RaycastResult?
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = buildCharacterExcludes({ root.Parent, cargoModel })

    local down = Vector3.new(0, -Config.Cargo.DropRayDistance, 0)
    local up = Vector3.new(0, 1.5, 0)
    local right = root.CFrame.RightVector
    local forward = root.CFrame.LookVector
    local sampleRadius = 3
    local probes = {
        root.Position + up,
        root.Position + (forward * 2) + up,
        root.Position - (forward * 2) + up,
        root.Position + (right * sampleRadius) + up,
        root.Position - (right * sampleRadius) + up,
        root.Position + (forward * sampleRadius) + (right * sampleRadius) + up,
        root.Position + (forward * sampleRadius) - (right * sampleRadius) + up,
        root.Position - (forward * sampleRadius) + (right * sampleRadius) + up,
        root.Position - (forward * sampleRadius) - (right * sampleRadius) + up,
    }

    local bestResult: RaycastResult? = nil
    local bestTopResult: RaycastResult? = nil
    local bestY = -math.huge
    local bestTopY = -math.huge

    for _, origin in ipairs(probes) do
        local result = Workspace:Raycast(origin, down, params)
        if result and result.Instance and result.Instance:IsA("BasePart") then
            local y = result.Position.Y
            if y > bestY then
                bestY = y
                bestResult = result
            end
            if result.Normal.Y >= 0.6 and y > bestTopY then
                bestTopY = y
                bestTopResult = result
            end
        end
    end

    return bestTopResult or bestResult
end

local function getDropCFrame(root: BasePart, primaryPart: BasePart, result: RaycastResult): CFrame
    local onCargoSurface = isCargoSurface(result.Instance)
    if onCargoSurface and result.Instance:IsA("BasePart") then
        local supportCargoModel = getCargoModelFromSurface(result.Instance)
        local cargoModel = findCargoModelFromInstance(primaryPart)
        if supportCargoModel and cargoModel then
            return getStackDropCFrame(cargoModel, supportCargoModel, root.CFrame.LookVector)
        end
    end

    local up = onCargoSurface and Vector3.new(0, 1, 0) or result.Normal.Unit
    local look = root.CFrame.LookVector
    local projectedLook = look - (up * look:Dot(up))

    if projectedLook.Magnitude < 1e-4 then
        local right = root.CFrame.RightVector
        projectedLook = right - (up * right:Dot(up))
    end

    if projectedLook.Magnitude < 1e-4 then
        projectedLook = Vector3.new(0, 0, -1)
    else
        projectedLook = projectedLook.Unit
    end

    local heightOffset = (primaryPart.Size.Y * 0.5) + 0.05
    local forwardOffset = onCargoSurface and 0 or (Config.Cargo.DropForwardOffset or 0)
    local dropPosition = result.Position + (up * heightOffset) + (projectedLook * forwardOffset)
    if onCargoSurface and result.Instance:IsA("BasePart") then
        dropPosition = getTopSurfaceDropPosition(result.Instance, primaryPart, result.Position, true)
    end
    local baseCFrame = CFrame.lookAt(dropPosition, dropPosition + projectedLook, up)

    if onCargoSurface then
        local yaw = math.rad(dropRng:NextNumber(-STACK_YAW_MAX_DEG, STACK_YAW_MAX_DEG))
        return baseCFrame * CFrame.fromAxisAngle(up, yaw)
    end

    return baseCFrame
end

local function getDropCFrameForSurface(root: BasePart, primaryPart: BasePart, surfacePart: BasePart, hitPosition: Vector3, hitNormal: Vector3): CFrame
    local onCargoSurface = isCargoSurface(surfacePart)
    if onCargoSurface then
        local supportCargoModel = getCargoModelFromSurface(surfacePart)
        local cargoModel = findCargoModelFromInstance(primaryPart)
        if supportCargoModel and cargoModel then
            return getStackDropCFrame(cargoModel, supportCargoModel, root.CFrame.LookVector)
        end
    end

    local up = onCargoSurface and Vector3.new(0, 1, 0) or hitNormal.Unit
    local look = root.CFrame.LookVector
    local projectedLook = look - (up * look:Dot(up))

    if projectedLook.Magnitude < 1e-4 then
        local right = root.CFrame.RightVector
        projectedLook = right - (up * right:Dot(up))
    end

    if projectedLook.Magnitude < 1e-4 then
        projectedLook = Vector3.new(0, 0, -1)
    else
        projectedLook = projectedLook.Unit
    end

    local heightOffset = (primaryPart.Size.Y * 0.5) + 0.05
    local forwardOffset = onCargoSurface and 0 or (Config.Cargo.DropForwardOffset or 0)
    local dropPosition = hitPosition + (up * heightOffset) + (projectedLook * forwardOffset)
    if onCargoSurface then
        dropPosition = getTopSurfaceDropPosition(surfacePart, primaryPart, hitPosition, true)
    end
    local baseCFrame = CFrame.lookAt(dropPosition, dropPosition + projectedLook, up)

    if onCargoSurface then
        local yaw = math.rad(dropRng:NextNumber(-STACK_YAW_MAX_DEG, STACK_YAW_MAX_DEG))
        return baseCFrame * CFrame.fromAxisAngle(up, yaw)
    end

    return baseCFrame
end

local function getDropCFrameFromLook(lookVector: Vector3, primaryPart: BasePart, result: RaycastResult): CFrame
    local onCargoSurface = isCargoSurface(result.Instance)
    if onCargoSurface and result.Instance:IsA("BasePart") then
        local supportCargoModel = getCargoModelFromSurface(result.Instance)
        local cargoModel = findCargoModelFromInstance(primaryPart)
        if supportCargoModel and cargoModel then
            return getStackDropCFrame(cargoModel, supportCargoModel, lookVector)
        end
    end

    local up = onCargoSurface and Vector3.new(0, 1, 0) or result.Normal.Unit
    local projectedLook = lookVector - (up * lookVector:Dot(up))
    if projectedLook.Magnitude < 1e-4 then
        projectedLook = Vector3.new(0, 0, -1)
    else
        projectedLook = projectedLook.Unit
    end

    local heightOffset = (primaryPart.Size.Y * 0.5) + 0.05
    local dropPosition = result.Position + (up * heightOffset)
    if onCargoSurface and result.Instance:IsA("BasePart") then
        dropPosition = getTopSurfaceDropPosition(result.Instance, primaryPart, result.Position, true)
    end

    local baseCFrame = CFrame.lookAt(dropPosition, dropPosition + projectedLook, up)
    if onCargoSurface then
        local yaw = math.rad(dropRng:NextNumber(-STACK_YAW_MAX_DEG, STACK_YAW_MAX_DEG))
        return baseCFrame * CFrame.fromAxisAngle(up, yaw)
    end
    return baseCFrame
end

local function snapDroppedNonCargoToGround(primaryPart: BasePart, cargoModel: Model)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = buildCharacterExcludes({ cargoModel })

    local origin = primaryPart.Position + Vector3.new(0, 20, 0)
    local hit = Workspace:Raycast(origin, Vector3.new(0, -200, 0), params)
    if not hit or not hit.Instance or not hit.Instance:IsA("BasePart") then
        return
    end
    if isCargoSurface(hit.Instance) then
        return
    end

    local up = hit.Normal.Unit
    local projectedLook = projectLookOnUp(primaryPart.CFrame.LookVector, up)

    local pos = hit.Position + (up * ((primaryPart.Size.Y * 0.5) + 0.05))
    primaryPart.CFrame = CFrame.lookAt(pos, pos + projectedLook, up)
end

local function raycastDropSurfaceFromPosition(position: Vector3, cargoModel: Model, extraExcludes: {Instance}?): RaycastResult?
    local excludes = { cargoModel }
    if extraExcludes then
        for _, instance in ipairs(extraExcludes) do
            table.insert(excludes, instance)
        end
    end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = buildCharacterExcludes(excludes)

    local origin = position + Vector3.new(0, 1.5, 0)
    local down = Vector3.new(0, -(Config.Cargo.DropRayDistance + 50), 0)
    local result = Workspace:Raycast(origin, down, params)
    if result and result.Instance and result.Instance:IsA("BasePart") then
        return result
    end
    return nil
end

settleDroppedCargo = function(cargoId: string, excludedSurfaceCarrier: Instance?, preferNonCargoSurface: boolean?)
    local cargoModel = CargoRegistry.getInstanceById(cargoId)
    if not cargoModel then
        droppedFollowByCargoId[cargoId] = nil
        return
    end

    local primaryPart = getPrimaryPart(cargoModel)
    local record = CargoRegistry.getById(cargoId)
    if not primaryPart or not record then
        droppedFollowByCargoId[cargoId] = nil
        return
    end
    if record.Status == "InTransit" or record.CurrentHolderUserId ~= nil then
        droppedFollowByCargoId[cargoId] = nil
        return
    end

    local excludes = {}
    if excludedSurfaceCarrier then
        table.insert(excludes, excludedSurfaceCarrier)
    end

    local result = raycastDropSurfaceFromPosition(primaryPart.Position, cargoModel, excludes)
    if preferNonCargoSurface and (not result or isCargoSurface(result.Instance)) then
        local look = primaryPart.CFrame.LookVector
        local right = primaryPart.CFrame.RightVector
        local fallback = raycastNonCargoNearby(primaryPart.Position, look, right, cargoModel)
        if fallback then
            result = fallback
        end
    end
    if not result then
        local emergencyParams = RaycastParams.new()
        emergencyParams.FilterType = Enum.RaycastFilterType.Exclude
        emergencyParams.FilterDescendantsInstances = buildCharacterExcludes({ cargoModel, excludedSurfaceCarrier })
        local emergencyOrigin = primaryPart.Position + Vector3.new(0, 400, 0)
        local emergencyDown = Vector3.new(0, -2000, 0)
        local emergencyHit = Workspace:Raycast(emergencyOrigin, emergencyDown, emergencyParams)
        if emergencyHit and emergencyHit.Instance and emergencyHit.Instance:IsA("BasePart") then
            result = emergencyHit
        end
    end
    if not result then
        droppedFollowByCargoId[cargoId] = nil
        -- Hard fallback: keep crate grounded and stable, never leave dynamic/airborne.
        local finalParams = RaycastParams.new()
        finalParams.FilterType = Enum.RaycastFilterType.Exclude
        finalParams.FilterDescendantsInstances = buildCharacterExcludes({ cargoModel })
        local finalOrigin = primaryPart.Position + Vector3.new(0, 400, 0)
        local finalHit = Workspace:Raycast(finalOrigin, Vector3.new(0, -2400, 0), finalParams)
        if finalHit and finalHit.Instance and finalHit.Instance:IsA("BasePart") then
            local y = finalHit.Position.Y + (primaryPart.Size.Y * 0.5) + 0.05
            primaryPart.CFrame = CFrame.new(primaryPart.Position.X, y, primaryPart.Position.Z)
        end
        primaryPart.Anchored = true
        primaryPart.CanCollide = true
        record.Status = "Dropped"
        record.CurrentHolderUserId = nil
        applyRecordToAttributes(cargoModel, record)
        setPickupPromptEnabled(cargoModel, shouldEnablePickupPrompt(cargoId, cargoModel, record.Status))
        clearDroppedPlacementAttributes(cargoModel)
        return
    end

    primaryPart.CFrame = getDropCFrameFromLook(primaryPart.CFrame.LookVector, primaryPart, result)
    resolveCargoInterpenetration(primaryPart, cargoModel)
    record.Status = "Dropped"
    record.CurrentHolderUserId = nil
    applyRecordToAttributes(cargoModel, record)
    setPickupPromptEnabled(cargoModel, shouldEnablePickupPrompt(cargoId, cargoModel, record.Status))
    droppedFollowByCargoId[cargoId] = {
        surface = result.Instance,
        localCFrame = result.Instance.CFrame:ToObjectSpace(primaryPart.CFrame),
        lastSurfaceCFrame = result.Instance.CFrame,
    }
    setDroppedPlacementAttributes(cargoModel, result.Instance, droppedFollowByCargoId[cargoId].localCFrame, primaryPart.CFrame)
end

local function getSupportCargoIdForDroppedModel(cargoModel: Model): string?
    local fromAttr = cargoModel:GetAttribute("DropSurfaceCargoId")
    if type(fromAttr) == "string" and fromAttr ~= "" then
        return fromAttr
    end

    local cargoId = cargoModel:GetAttribute("CargoId")
    if type(cargoId) == "string" and cargoId ~= "" then
        local follow = droppedFollowByCargoId[cargoId]
        if follow then
            local fromFollow = getSurfaceCargoId(follow.surface)
            if type(fromFollow) == "string" and fromFollow ~= "" then
                return fromFollow
            end
        end
    end

    local path = cargoModel:GetAttribute("DropSurfacePath")
    if type(path) == "string" and path ~= "" then
        local inst = findByFullNamePath(path)
        if inst then
            local fromPath = getSurfaceCargoId(inst)
            if type(fromPath) == "string" and fromPath ~= "" then
                return fromPath
            end
        end
    end

    return nil
end

local function settleDependentsOnSurfacePickUp(surfacePart: BasePart, pickedCargoModel: Model)
    local _ = surfacePart
    local _ = pickedCargoModel
    -- Intentionally no-op: top-only pickup prevents support removal under stacks,
    -- so background "re-settle nearby crates" logic is disabled to avoid random disassembly.
end

function CargoCarryService.getCarriedCargo(player: Player): Model?
    local cargoId = carriedByUserId[player.UserId]
    if not cargoId then
        return nil
    end
    return CargoRegistry.getInstanceById(cargoId)
end

function CargoCarryService.clearCarried(player: Player)
    carriedByUserId[player.UserId] = nil
    setCarryingAttribute(player, false)
end

function CargoCarryService.destroyCargoById(cargoId: string, reason: string?): boolean
    local model = CargoRegistry.getInstanceById(cargoId)
    local record = CargoRegistry.getById(cargoId)
    if not model or not record then
        return false
    end

    local holderUserId = record.CurrentHolderUserId
    if type(holderUserId) == "number" and carriedByUserId[holderUserId] == cargoId then
        carriedByUserId[holderUserId] = nil
        local holderPlayer = Players:GetPlayerByUserId(holderUserId)
        if holderPlayer then
            setCarryingAttribute(holderPlayer, false)
        end
    else
        for userId, carriedCargoId in pairs(carriedByUserId) do
            if carriedCargoId == cargoId then
                carriedByUserId[userId] = nil
                local holderPlayer = Players:GetPlayerByUserId(userId)
                if holderPlayer then
                    setCarryingAttribute(holderPlayer, false)
                end
            end
        end
    end

    droppedFollowByCargoId[cargoId] = nil
    CargoRegistry.destroyCargo(cargoId)
    CargoPersistenceService.forceSaveForUserId(record.OriginalOwnerUserId)
    if Config.DiagnosticsEnabled then
        print(string.format("[P5_TEST] event=destroy_cargo cargoId=%s reason=%s", cargoId, tostring(reason or "UNKNOWN")))
    end
    return true
end

function CargoCarryService.tryPickUp(player: Player, cargoModel: Model): (boolean, string?)
    local primaryPart = getPrimaryPart(cargoModel)
    if not primaryPart then
        Diagnostics.increment("errors")
        return false, "PICKUP_REJECT_INVALID"
    end

    local record = CargoRegistry.getByInstance(cargoModel)
    if not record then
        return false, "PICKUP_REJECT_INVALID"
    end

    if hasStackedCargoAbove(record.CargoId, cargoModel) then
        return false, "PICKUP_REJECT_NOT_TOP"
    end

    if record.Status == "InTransit" and record.CurrentHolderUserId and record.CurrentHolderUserId ~= player.UserId then
        return false, "PICKUP_REJECT_IN_USE"
    end

    if carriedByUserId[player.UserId] ~= nil then
        return false, "PICKUP_REJECT_ALREADY_CARRYING"
    end

    if not canInteract(player, primaryPart.Position) then
        return false, "PICKUP_REJECT_DISTANCE"
    end

    local root = getCharacterRoot(player)
    if not root then
        return false, "PICKUP_REJECT_CHARACTER"
    end

    droppedFollowByCargoId[record.CargoId] = nil
    clearDropWeld(primaryPart)
    clearCarryWeld(primaryPart)
    clearDroppedPlacementAttributes(cargoModel)

    primaryPart.CanCollide = false
    primaryPart.Anchored = false
    primaryPart.CFrame = root.CFrame * Config.Cargo.CarryOffset

    local weld = Instance.new("WeldConstraint")
    weld.Name = "CargoCarryWeld"
    weld.Part0 = root
    weld.Part1 = primaryPart
    weld.Parent = primaryPart

    carriedByUserId[player.UserId] = record.CargoId
    setCarryingAttribute(player, true)
    if record.OriginalOwnerUserId ~= player.UserId then
        record.IsStolen = true
        print(string.format("[P2_TEST] event=pickup_stolen cargoId=%s pickerUserId=%d ownerUserId=%d", record.CargoId, player.UserId, record.OriginalOwnerUserId))
    end
    record.CurrentHolderUserId = player.UserId
    record.Status = "InTransit"
    applyRecordToAttributes(cargoModel, record)
    setPickupPromptEnabled(cargoModel, false)
    refreshPickupPromptStates()

    print(string.format("[P1_TEST] event=pickup_result ok=true reason=PICKUP_OK cargoId=%s", record.CargoId))
    Diagnostics.log("PICKUP_OK", { userId = player.UserId, cargoId = record.CargoId })

    return true, nil
end

function CargoCarryService.tryDropCarried(player: Player): (boolean, string?)
    local cargoId = carriedByUserId[player.UserId]
    print(string.format("[P1_TEST] event=drop_attempt player=%s cargoId=%s", player.Name, cargoId or "none"))

    if not cargoId then
        Diagnostics.increment("drops_rejected")
        print("[P1_TEST] event=drop_result ok=false reason=DROP_REJECT_NOCARGO weldedTo=none")
        Diagnostics.printP1Summary("drop")
        return false, "DROP_REJECT_NOCARGO"
    end

    local cargoModel = CargoRegistry.getInstanceById(cargoId)
    if not cargoModel then
        carriedByUserId[player.UserId] = nil
        Diagnostics.increment("drops_rejected")
        print("[P1_TEST] event=drop_result ok=false reason=DROP_REJECT_INVALID weldedTo=none")
        Diagnostics.printP1Summary("drop")
        return false, "DROP_REJECT_INVALID"
    end

    local primaryPart = getPrimaryPart(cargoModel)
    local root = getCharacterRoot(player)
    if not primaryPart or not root then
        Diagnostics.increment("drops_rejected")
        print("[P1_TEST] event=drop_result ok=false reason=DROP_REJECT_CHARACTER weldedTo=none")
        Diagnostics.printP1Summary("drop")
        return false, "DROP_REJECT_CHARACTER"
    end

    local result = raycastDropSurface(root, cargoModel)
    if not result or not result.Instance or not result.Instance:IsA("BasePart") then
        Diagnostics.increment("drops_rejected")
        print("[P1_TEST] event=drop_result ok=false reason=DROP_REJECT_SURFACE weldedTo=none")
        Diagnostics.printP1Summary("drop")
        return false, "DROP_REJECT_SURFACE"
    end

    local targetSurface: BasePart = result.Instance
    local targetPosition = result.Position
    local targetNormal = result.Normal

    if not isCargoSurface(targetSurface) then
        local snapSurface = findNearbyCargoSurfaceForSnap(root, cargoModel, result.Position)
        if snapSurface and canStackOnCargoSurface(snapSurface) then
            targetSurface = snapSurface
            targetPosition = snapSurface.Position
            targetNormal = Vector3.new(0, 1, 0)
        end
    end

    if isCargoSurface(targetSurface) then
        if not canStackOnCargoSurface(targetSurface) then
            local fallback = raycastNonCargoNearby(targetPosition, root.CFrame.LookVector, root.CFrame.RightVector, cargoModel, 1.8)
            if not fallback then
                fallback = raycastNonCargoNearby(root.Position + (root.CFrame.LookVector * 1.6), root.CFrame.LookVector, root.CFrame.RightVector, cargoModel, 1.6)
            end
            if fallback then
                targetSurface = fallback.Instance
                targetPosition = fallback.Position
                targetNormal = fallback.Normal
            else
                Diagnostics.increment("drops_rejected")
                print("[P1_TEST] event=drop_result ok=false reason=DROP_REJECT_STACK_LIMIT weldedTo=none")
                Diagnostics.printP1Summary("drop")
                return false, "DROP_REJECT_STACK_LIMIT"
            end
        end
    end

    clearCarryWeld(primaryPart)

    primaryPart.CFrame = getDropCFrameForSurface(root, primaryPart, targetSurface, targetPosition, targetNormal)
    resolveCargoInterpenetration(primaryPart, cargoModel)
    if not isCargoSurface(targetSurface) then
        snapDroppedNonCargoToGround(primaryPart, cargoModel)
    end
    primaryPart.CanCollide = true
    primaryPart.Anchored = false

    clearDropWeld(primaryPart)
    createDropWeld(primaryPart, targetSurface)

    local record = CargoRegistry.getById(cargoId)
    if record then
        record.CurrentHolderUserId = nil
        record.Status = "Dropped"
        applyRecordToAttributes(cargoModel, record)
        droppedFollowByCargoId[cargoId] = nil
        setDroppedPlacementAttributes(cargoModel, targetSurface, targetSurface.CFrame:ToObjectSpace(primaryPart.CFrame), primaryPart.CFrame)
    end
    setPickupPromptEnabled(cargoModel, shouldEnablePickupPrompt(cargoId, cargoModel, "Dropped"))

    carriedByUserId[player.UserId] = nil
    setCarryingAttribute(player, false)

    Diagnostics.increment("drops_success")
    print(string.format("[P1_TEST] event=drop_result ok=true reason=DROP_OK mode=follow_v2 weldedTo=%s", targetSurface:GetFullName()))
    Diagnostics.log("DROP_OK", { userId = player.UserId, cargoId = cargoId })
    Diagnostics.printP1Summary("drop")
    CargoPersistenceService.saveForPlayer(player)
    refreshPickupPromptStates()

    return true, nil
end

Players.PlayerRemoving:Connect(function(player)
    local cargoId = carriedByUserId[player.UserId]
    if not cargoId then
        return
    end

    carriedByUserId[player.UserId] = nil
    setCarryingAttribute(player, false)

    local cargoModel = CargoRegistry.getInstanceById(cargoId)
    local record = CargoRegistry.getById(cargoId)
    if cargoModel and record then
        local primaryPart = getPrimaryPart(cargoModel)
        if primaryPart then
            clearCarryWeld(primaryPart)
            primaryPart.CanCollide = true
            primaryPart.Anchored = true
        end
        record.CurrentHolderUserId = nil
        record.Status = "Owned"
        applyRecordToAttributes(cargoModel, record)
        setPickupPromptEnabled(cargoModel, shouldEnablePickupPrompt(cargoId, cargoModel, "Owned"))
        clearDroppedPlacementAttributes(cargoModel)
    end
end)

RunService.Heartbeat:Connect(function()
    local now = os.clock()
    if now - lastDroppedSelfHealAt >= 0.35 then
        lastDroppedSelfHealAt = now
        selfHealDroppedCargo()
    end
    if now - lastPromptRefreshAt >= 0.4 then
        lastPromptRefreshAt = now
        refreshPickupPromptStates()
    end
end)

return CargoCarryService

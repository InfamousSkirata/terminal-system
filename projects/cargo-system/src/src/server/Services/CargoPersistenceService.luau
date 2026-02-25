local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local CargoFactory = require(script.Parent.CargoFactory)
local CargoRegistry = require(script.Parent.CargoRegistry)
local Diagnostics = require(script.Parent.Diagnostics)

local CargoPersistenceService = {}

local store = DataStoreService:GetDataStore("CargoOwnedState")
local restoredByUserId: {[number]: boolean} = {}
local shipRootById: {[string]: Model} = {}
local lastSaveAtByUserId: {[number]: number} = {}
local saveQueuedByUserId: {[number]: boolean} = {}
local lastSavedFingerprintByUserId: {[number]: string} = {}

local SAVE_INTERVAL_SEC = 20
local MIN_SAVE_GAP_SEC = 12

local function keyForUser(userId: number): string
    return string.format("%s:%d", Config.Cargo.DataStoreKeyPrefix, userId)
end

local function encodeCFrame(value: CFrame?): {[string]: number}?
    if typeof(value) ~= "CFrame" then
        return nil
    end
    local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = value:GetComponents()
    return {
        x = x,
        y = y,
        z = z,
        r00 = r00,
        r01 = r01,
        r02 = r02,
        r10 = r10,
        r11 = r11,
        r12 = r12,
        r20 = r20,
        r21 = r21,
        r22 = r22,
    }
end

local function decodeCFrame(value: any): CFrame?
    if type(value) ~= "table" then
        return nil
    end

    -- Backward compatibility for any previously persisted array payload.
    if #value == 12 then
        for i = 1, 12 do
            if type(value[i]) ~= "number" then
                return nil
            end
        end
        return CFrame.new(
            value[1], value[2], value[3],
            value[4], value[5], value[6],
            value[7], value[8], value[9],
            value[10], value[11], value[12]
        )
    end

    local x = value.x
    local y = value.y
    local z = value.z
    local r00 = value.r00
    local r01 = value.r01
    local r02 = value.r02
    local r10 = value.r10
    local r11 = value.r11
    local r12 = value.r12
    local r20 = value.r20
    local r21 = value.r21
    local r22 = value.r22
    if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
        return nil
    end
    if type(r00) ~= "number" or type(r01) ~= "number" or type(r02) ~= "number" then
        return nil
    end
    if type(r10) ~= "number" or type(r11) ~= "number" or type(r12) ~= "number" then
        return nil
    end
    if type(r20) ~= "number" or type(r21) ~= "number" or type(r22) ~= "number" then
        return nil
    end
    return CFrame.new(
        x, y, z,
        r00, r01, r02,
        r10, r11, r12,
        r20, r21, r22
    )
end

local function normalizeStoredRecord(raw: any, userId: number)
    if type(raw) ~= "table" then
        return nil
    end

    local cargoId = raw.CargoId
    local cargoType = raw.CargoType
    local originSellerId = raw.OriginSellerId
    local destinationBuyerId = raw.DestinationBuyerId
    local purchasePrice = raw.PurchasePrice
    local sellPrice = raw.SellPrice
    local isStolen = raw.IsStolen == true
    local status = raw.Status == "Dropped" and "Dropped" or "Owned"

    if type(cargoId) ~= "string" or cargoId == "" then
        return nil
    end
    if type(cargoType) ~= "string" or cargoType == "" then
        return nil
    end
    if type(originSellerId) ~= "string" or originSellerId == "" then
        return nil
    end
    if type(destinationBuyerId) ~= "string" or destinationBuyerId == "" then
        return nil
    end
    if type(purchasePrice) ~= "number" or type(sellPrice) ~= "number" then
        return nil
    end

    return {
        CargoId = cargoId,
        CargoType = cargoType,
        OriginSellerId = originSellerId,
        DestinationBuyerId = destinationBuyerId,
        PurchasePrice = purchasePrice,
        SellPrice = sellPrice,
        OriginalOwnerUserId = userId,
        CurrentHolderUserId = nil,
        IsStolen = isStolen,
        PlanetTag = type(raw.PlanetTag) == "string" and raw.PlanetTag or nil,
        Status = status,
    }
end

local function findShipRoot(instance: Instance?): Model?
    local current = instance
    while current and current ~= workspace do
        if current:IsA("Model") then
            local shipId = current:GetAttribute("ShipId")
            if type(shipId) == "string" and shipId ~= "" then
                return current
            end
        end
        current = current.Parent
    end
    return nil
end

local function getRelativePath(root: Instance, target: Instance): string?
    if root == target then
        return ""
    end

    local names = {}
    local current: Instance? = target
    while current and current ~= root do
        table.insert(names, 1, current.Name)
        current = current.Parent
    end
    if current ~= root then
        return nil
    end
    return table.concat(names, ".")
end

local function findByRelativePath(root: Instance, path: string): Instance?
    if path == "" then
        return root
    end

    local current: Instance = root
    for _, segment in ipairs(string.split(path, ".")) do
        local nextInstance = current:FindFirstChild(segment)
        if not nextInstance then
            return nil
        end
        current = nextInstance
    end
    return current
end

local function findShipById(shipId: string): Model?
    local cached = shipRootById[shipId]
    if cached and cached.Parent and cached:GetAttribute("ShipId") == shipId then
        return cached
    end

    for _, inst in ipairs(workspace:GetDescendants()) do
        if inst:IsA("Model") then
            local candidate = inst:GetAttribute("ShipId")
            if candidate == shipId then
                shipRootById[shipId] = inst
                return inst
            end
        end
    end
    shipRootById[shipId] = nil
    return nil
end

local findByFullNamePath: (path: string) -> Instance?

local function serializeRecord(record, model: Model?): {[string]: any}
    local dropSurfacePath = nil
    local dropSurfaceCargoId = nil
    local dropLocalCFrameEncoded = nil
    local dropWorldCFrameEncoded = nil
    local lastWorldCFrameEncoded = nil
    local dropShipId = nil
    local dropShipSurfacePath = nil
    if model then
        local maybePath = model:GetAttribute("DropSurfacePath")
        if type(maybePath) == "string" and maybePath ~= "" then
            dropSurfacePath = maybePath
            local surface = findByFullNamePath(maybePath)
            if surface then
                local shipRoot = findShipRoot(surface)
                if shipRoot then
                    local shipId = shipRoot:GetAttribute("ShipId")
                    local relPath = getRelativePath(shipRoot, surface)
                    if type(shipId) == "string" and shipId ~= "" and type(relPath) == "string" then
                        dropShipId = shipId
                        dropShipSurfacePath = relPath
                    end
                end
            end
        end
        local maybeSurfaceCargoId = model:GetAttribute("DropSurfaceCargoId")
        if type(maybeSurfaceCargoId) == "string" and maybeSurfaceCargoId ~= "" then
            dropSurfaceCargoId = maybeSurfaceCargoId
        end
        local maybeLocal = model:GetAttribute("DropLocalCFrame")
        dropLocalCFrameEncoded = encodeCFrame(maybeLocal)
        local maybeWorld = model:GetAttribute("DropWorldCFrame")
        dropWorldCFrameEncoded = encodeCFrame(maybeWorld)
        local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
        if primary then
            lastWorldCFrameEncoded = encodeCFrame(primary.CFrame)
        end
    end

    return {
        CargoId = record.CargoId,
        CargoType = record.CargoType,
        OriginSellerId = record.OriginSellerId,
        DestinationBuyerId = record.DestinationBuyerId,
        PurchasePrice = record.PurchasePrice,
        SellPrice = record.SellPrice,
        Status = record.Status,
        IsStolen = record.IsStolen == true,
        PlanetTag = record.PlanetTag,
        DropShipId = dropShipId,
        DropShipSurfacePath = dropShipSurfacePath,
        DropSurfacePath = dropSurfacePath,
        DropSurfaceCargoId = dropSurfaceCargoId,
        DropLocalCFrame = dropLocalCFrameEncoded,
        DropWorldCFrame = dropWorldCFrameEncoded,
        LastWorldCFrame = lastWorldCFrameEncoded,
    }
end

local function placeRestoredCargo(model: Model, player: Player, index: number)
    local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
    if not part then
        return
    end

    local base = Vector3.new(0, 8, 0)
    local character = player.Character
    if character then
        local root = character:FindFirstChild("HumanoidRootPart")
        if root and root:IsA("BasePart") then
            base = root.Position + (root.CFrame.LookVector * 8) + Vector3.new(0, 2, 0)
        end
    end

    local row = math.floor((index - 1) / 3)
    local col = (index - 1) % 3
    local offset = Vector3.new((col - 1) * 3.5, 0, row * 3.5)
    local desired = base + offset

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { model, player.Character }
    local rayOrigin = desired + Vector3.new(0, 20, 0)
    local rayDown = Vector3.new(0, -200, 0)
    local hit = workspace:Raycast(rayOrigin, rayDown, params)

    if hit and hit.Instance and hit.Instance:IsA("BasePart") then
        local y = hit.Position.Y + (part.Size.Y * 0.5) + 0.05
        part.CFrame = CFrame.new(Vector3.new(desired.X, y, desired.Z))
    else
        local rootHit = nil
        if character then
            local root = character:FindFirstChild("HumanoidRootPart")
            if root and root:IsA("BasePart") then
                rootHit = workspace:Raycast(root.Position + Vector3.new(0, 40, 0), Vector3.new(0, -400, 0), params)
            end
        end
        if rootHit and rootHit.Instance and rootHit.Instance:IsA("BasePart") then
            local y = rootHit.Position.Y + (part.Size.Y * 0.5) + 0.05
            part.CFrame = CFrame.new(Vector3.new(desired.X, y, desired.Z))
        else
            part.CFrame = CFrame.new(desired)
        end
    end

    part.Anchored = true
    part.CanCollide = true
end

local function placeFromSavedWorldCFrame(model: Model, raw: any): boolean
    local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
    if not part then
        return false
    end

    local worldCFrame = decodeCFrame(raw.DropWorldCFrame)
    if typeof(worldCFrame) ~= "CFrame" then
        worldCFrame = decodeCFrame(raw.LastWorldCFrame)
    end
    if typeof(worldCFrame) ~= "CFrame" then
        return false
    end

    part.CFrame = worldCFrame
    part.Anchored = true
    part.CanCollide = true

    -- Guard against stale world snapshots that leave crates floating above spawn.
    local snapParams = RaycastParams.new()
    snapParams.FilterType = Enum.RaycastFilterType.Exclude
    snapParams.FilterDescendantsInstances = { model }
    local snapOrigin = part.Position + Vector3.new(0, 6, 0)
    local snapHit = workspace:Raycast(snapOrigin, Vector3.new(0, -2000, 0), snapParams)
    if snapHit and snapHit.Instance and snapHit.Instance:IsA("BasePart") then
        local downDistance = snapOrigin.Y - snapHit.Position.Y
        if downDistance > 10 then
            local groundedY = snapHit.Position.Y + (part.Size.Y * 0.5) + 0.05
            part.CFrame = CFrame.new(part.Position.X, groundedY, part.Position.Z)
        end
    end

    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { model }
    params.MaxParts = 20
    for _ = 1, 18 do
        local overlaps = workspace:GetPartBoundsInBox(part.CFrame, part.Size * 0.94, params)
        local blocking = false
        for _, overlap in ipairs(overlaps) do
            if overlap:IsA("BasePart") then
                local current: Instance? = overlap
                while current do
                    if current:IsA("Model") then
                        if current == model then
                            break
                        end
                        local cargoId = current:GetAttribute("CargoId")
                        if type(cargoId) == "string" and cargoId ~= "" then
                            blocking = true
                            break
                        end
                    end
                    current = current.Parent
                end
            end
            if blocking then
                break
            end
        end
        if not blocking then
            break
        end
        part.CFrame = part.CFrame + Vector3.new(0, 0.12, 0)
    end

    return true
end

findByFullNamePath = function(path: string): Instance?
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

local function clearDropWeld(part: BasePart)
    local existing = part:FindFirstChild("CargoDropWeld")
    if existing and (existing:IsA("WeldConstraint") or existing:IsA("Weld")) then
        existing:Destroy()
    end
end

local function attachRestoredDroppedCargo(model: Model, raw: any)
    local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
    if not primary then
        return false
    end

    local surfacePath = raw.DropSurfacePath
    local surfaceCargoId = raw.DropSurfaceCargoId
    local shipId = raw.DropShipId
    local shipSurfacePath = raw.DropShipSurfacePath
    local localCFrame = decodeCFrame(raw.DropLocalCFrame)
    local worldCFrame = decodeCFrame(raw.DropWorldCFrame)
    local lastWorldCFrame = decodeCFrame(raw.LastWorldCFrame)

    local surface: Instance? = nil
    local resolvedBySurfaceCargo = false
    local resolvedByShip = false
    local resolvedByPath = false
    if type(surfaceCargoId) == "string" and surfaceCargoId ~= "" then
        local surfaceCargoModel = CargoRegistry.getInstanceById(surfaceCargoId)
        if surfaceCargoModel then
            local surfacePart = surfaceCargoModel.PrimaryPart or surfaceCargoModel:FindFirstChildWhichIsA("BasePart", true)
            if surfacePart and surfacePart:IsA("BasePart") then
                surface = surfacePart
                resolvedBySurfaceCargo = true
            end
        end
    end
    if type(shipId) == "string" and shipId ~= "" and type(shipSurfacePath) == "string" then
        if not surface then
            local shipRoot = findShipById(shipId)
            if shipRoot then
                surface = findByRelativePath(shipRoot, shipSurfacePath)
                if surface then
                    resolvedByShip = true
                end
            end
        end
    end
    if not surface then
        if type(surfacePath) == "string" and surfacePath ~= "" then
            surface = findByFullNamePath(surfacePath)
            if surface then
                resolvedByPath = true
            end
        end
    end

    clearDropWeld(primary)
    if surface and surface:IsA("BasePart") and typeof(localCFrame) == "CFrame" then
        local resolvedSurfaceCargoId: string? = nil
        local current: Instance? = surface
        while current do
            if current:IsA("Model") then
                local maybeCargoId = current:GetAttribute("CargoId")
                if type(maybeCargoId) == "string" and maybeCargoId ~= "" then
                    resolvedSurfaceCargoId = maybeCargoId
                    break
                end
            end
            current = current.Parent
        end

        primary.CFrame = surface.CFrame * localCFrame
        model:SetAttribute("DropSurfacePath", surface:GetFullName())
        if type(resolvedSurfaceCargoId) == "string" and resolvedSurfaceCargoId ~= "" then
            model:SetAttribute("DropSurfaceCargoId", resolvedSurfaceCargoId)
        elseif type(surfaceCargoId) == "string" and surfaceCargoId ~= "" then
            model:SetAttribute("DropSurfaceCargoId", surfaceCargoId)
        else
            model:SetAttribute("DropSurfaceCargoId", nil)
        end
        model:SetAttribute("DropLocalCFrame", localCFrame)
        model:SetAttribute("DropWorldCFrame", primary.CFrame)
        primary.Anchored = true
        primary.CanCollide = true
        if resolvedByShip then
            Diagnostics.increment("restore_drop_ship_attach")
        elseif resolvedBySurfaceCargo then
            Diagnostics.increment("restore_drop_surface_attach")
        elseif resolvedByPath then
            Diagnostics.increment("restore_drop_path_attach")
        else
            Diagnostics.increment("restore_drop_surface_attach")
        end
        return true
    end

    if typeof(worldCFrame) == "CFrame" then
        primary.CFrame = worldCFrame
        if type(surfacePath) == "string" and surfacePath ~= "" then
            model:SetAttribute("DropSurfacePath", surfacePath)
        end
        if type(surfaceCargoId) == "string" and surfaceCargoId ~= "" then
            model:SetAttribute("DropSurfaceCargoId", surfaceCargoId)
        end
        if typeof(localCFrame) == "CFrame" then
            model:SetAttribute("DropLocalCFrame", localCFrame)
        end
        model:SetAttribute("DropWorldCFrame", worldCFrame)
        primary.Anchored = true
        primary.CanCollide = true
        Diagnostics.increment("restore_drop_world_attach")
        return true
    end

    if typeof(lastWorldCFrame) == "CFrame" then
        primary.CFrame = lastWorldCFrame
        if type(surfacePath) == "string" and surfacePath ~= "" then
            model:SetAttribute("DropSurfacePath", surfacePath)
        end
        if type(surfaceCargoId) == "string" and surfaceCargoId ~= "" then
            model:SetAttribute("DropSurfaceCargoId", surfaceCargoId)
        end
        if typeof(localCFrame) == "CFrame" then
            model:SetAttribute("DropLocalCFrame", localCFrame)
        end
        model:SetAttribute("DropWorldCFrame", lastWorldCFrame)
        primary.Anchored = true
        primary.CanCollide = true
        Diagnostics.increment("restore_drop_world_attach")
        return true
    end

    -- Runtime drop behavior uses follow tracking, not weld chains.
    -- Keep restored crates physically stable and let CargoCarryService reconstruct follow state.
    primary.Anchored = true
    primary.CanCollide = true
    return false
end

local function restoreForPlayer(player: Player)
    if restoredByUserId[player.UserId] then
        return
    end

    local ok, payload = pcall(function()
        return store:GetAsync(keyForUser(player.UserId))
    end)
    if not ok then
        Diagnostics.increment("errors")
        warn(string.format("[CargoPersistence] load failed userId=%d", player.UserId))
        restoredByUserId[player.UserId] = true
        return
    end

    local restoredCount = 0
    local pending = {}
    if type(payload) == "table" then
        for _, raw in ipairs(payload) do
            if restoredCount >= Config.Cargo.MaxOwnedPerPlayer then
                break
            end
            local record = normalizeStoredRecord(raw, player.UserId)
            if record then
                local existing = CargoRegistry.getById(record.CargoId)
                if not existing then
                    local model = CargoFactory.createCargo(record)
                    CargoRegistry.register(model, record)
                    table.insert(pending, {
                        model = model,
                        record = record,
                        raw = raw,
                        index = restoredCount + 1,
                    })
                    restoredCount += 1
                end
            end
        end
    end

    for _, entry in ipairs(pending) do
        local attached = false
        if entry.record.Status == "Dropped" then
            attached = attachRestoredDroppedCargo(entry.model, entry.raw)
        end
        if not attached then
            local placedFromWorld = false
            if entry.record.Status == "Dropped" then
                placedFromWorld = placeFromSavedWorldCFrame(entry.model, entry.raw)
            end
            if placedFromWorld then
                Diagnostics.increment("restore_drop_world_attach")
            else
                if entry.record.Status == "Dropped" then
                    Diagnostics.increment("restore_drop_near_player")
                else
                    Diagnostics.increment("restore_owned_near_player")
                end
                placeRestoredCargo(entry.model, player, entry.index)
            end
        end
    end

    print(string.format("[P4_TEST] event=restore userId=%d count=%d", player.UserId, restoredCount))
    lastSavedFingerprintByUserId[player.UserId] = nil
    restoredByUserId[player.UserId] = true
end

local function buildPayloadAndFingerprint(userId: number): ({[number]: {[string]: any}}, string)
    local records = CargoRegistry.getActiveOwnedRecordsBy(userId)
    local payload = {}
    local fp = {}
    for _, record in ipairs(records) do
        local model = CargoRegistry.getInstanceById(record.CargoId)
        local row = serializeRecord(record, model)
        table.insert(payload, row)
        table.insert(fp, string.format(
            "%s|%s|%s|%s|%d|%d|%s|%s|%s|%s|%s|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f",
            tostring(row.CargoId),
            tostring(row.CargoType),
            tostring(row.OriginSellerId),
            tostring(row.DestinationBuyerId),
            tonumber(row.PurchasePrice) or 0,
            tonumber(row.SellPrice) or 0,
            tostring(row.Status),
            tostring(row.IsStolen == true),
            tostring(row.DropShipId or ""),
            tostring(row.DropSurfacePath or ""),
            tostring(row.DropSurfaceCargoId or ""),
            tonumber(row.DropLocalCFrame and row.DropLocalCFrame.x) or 0,
            tonumber(row.DropLocalCFrame and row.DropLocalCFrame.y) or 0,
            tonumber(row.DropLocalCFrame and row.DropLocalCFrame.z) or 0,
            tonumber(row.DropLocalCFrame and row.DropLocalCFrame.r00) or 0,
            tonumber(row.DropLocalCFrame and row.DropLocalCFrame.r01) or 0,
            tonumber(row.DropLocalCFrame and row.DropLocalCFrame.r02) or 0,
            tonumber(row.DropLocalCFrame and row.DropLocalCFrame.r10) or 0,
            tonumber(row.DropLocalCFrame and row.DropLocalCFrame.r11) or 0,
            tonumber(row.DropLocalCFrame and row.DropLocalCFrame.r12) or 0,
            tonumber(row.DropLocalCFrame and row.DropLocalCFrame.r20) or 0,
            tonumber(row.DropLocalCFrame and row.DropLocalCFrame.r21) or 0,
            tonumber(row.DropLocalCFrame and row.DropLocalCFrame.r22) or 0,
            tonumber(row.LastWorldCFrame and row.LastWorldCFrame.x) or 0,
            tonumber(row.LastWorldCFrame and row.LastWorldCFrame.y) or 0,
            tonumber(row.LastWorldCFrame and row.LastWorldCFrame.z) or 0
        ))
    end
    return payload, table.concat(fp, ";")
end

local function saveForUserId(userId: number)
    local payload, fingerprint = buildPayloadAndFingerprint(userId)
    if lastSavedFingerprintByUserId[userId] == fingerprint then
        return
    end

    local ok, err = pcall(function()
        store:SetAsync(keyForUser(userId), payload)
    end)
    if not ok then
        Diagnostics.increment("errors")
        warn(string.format("[CargoPersistence] save failed userId=%d err=%s", userId, tostring(err)))
        return
    end
    print(string.format("[P4_TEST] event=save userId=%d count=%d", userId, #payload))
    lastSaveAtByUserId[userId] = os.clock()
    lastSavedFingerprintByUserId[userId] = fingerprint
end

local function requestSaveForUserId(userId: number)
    local now = os.clock()
    local last = lastSaveAtByUserId[userId] or 0
    local elapsed = now - last
    if elapsed >= MIN_SAVE_GAP_SEC then
        saveForUserId(userId)
        return
    end

    if saveQueuedByUserId[userId] then
        return
    end
    saveQueuedByUserId[userId] = true

    local delaySec = MIN_SAVE_GAP_SEC - elapsed
    task.delay(delaySec, function()
        saveQueuedByUserId[userId] = nil
        if restoredByUserId[userId] ~= nil then
            saveForUserId(userId)
        end
    end)
end

function CargoPersistenceService.saveForPlayer(player: Player)
    requestSaveForUserId(player.UserId)
end

function CargoPersistenceService.forceSaveForUserId(userId: number)
    saveQueuedByUserId[userId] = nil
    saveForUserId(userId)
end

function CargoPersistenceService.forceSaveForPlayer(player: Player)
    CargoPersistenceService.forceSaveForUserId(player.UserId)
end

function CargoPersistenceService.init()
    Players.PlayerAdded:Connect(function(player)
        restoreForPlayer(player)
    end)

    Players.PlayerRemoving:Connect(function(player)
        saveForUserId(player.UserId)
        restoredByUserId[player.UserId] = nil
        saveQueuedByUserId[player.UserId] = nil
        lastSaveAtByUserId[player.UserId] = nil
        lastSavedFingerprintByUserId[player.UserId] = nil
    end)

    for _, player in ipairs(Players:GetPlayers()) do
        restoreForPlayer(player)
    end

    task.spawn(function()
        while true do
            task.wait(SAVE_INTERVAL_SEC)
            for _, player in ipairs(Players:GetPlayers()) do
                saveForUserId(player.UserId)
            end
        end
    end)
end

return CargoPersistenceService

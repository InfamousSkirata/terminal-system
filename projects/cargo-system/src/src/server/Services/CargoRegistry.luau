local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Types"))
local Diagnostics = require(script.Parent.Diagnostics)

type CargoRecord = Types.CargoRecord

local CargoRegistry = {}

local recordsById: {[string]: CargoRecord} = {}
local instancesById: {[string]: Model} = {}
local idByInstance: {[Instance]: string} = {}
local soldById: {[string]: boolean} = {}

local function cloneRecord(record: CargoRecord): CargoRecord
    return {
        CargoId = record.CargoId,
        CargoType = record.CargoType,
        OriginSellerId = record.OriginSellerId,
        DestinationBuyerId = record.DestinationBuyerId,
        PurchasePrice = record.PurchasePrice,
        SellPrice = record.SellPrice,
        OriginalOwnerUserId = record.OriginalOwnerUserId,
        CurrentHolderUserId = record.CurrentHolderUserId,
        IsStolen = record.IsStolen,
        PlanetTag = record.PlanetTag,
        Status = record.Status,
    }
end

local function recalcActiveCargoCount()
    local count = 0
    for cargoId, record in pairs(recordsById) do
        if not soldById[cargoId] and record.Status ~= "Sold" then
            count += 1
        end
    end
    Diagnostics.set("active_cargo_count", count)
end

function CargoRegistry.register(instance: Model, record: CargoRecord)
    recordsById[record.CargoId] = record
    instancesById[record.CargoId] = instance
    idByInstance[instance] = record.CargoId
    recalcActiveCargoCount()
end

function CargoRegistry.getByInstance(instance: Instance): CargoRecord?
    local cargoId = idByInstance[instance]
    if not cargoId then
        return nil
    end
    return recordsById[cargoId]
end

function CargoRegistry.getById(cargoId: string): CargoRecord?
    return recordsById[cargoId]
end

function CargoRegistry.getInstanceById(cargoId: string): Model?
    return instancesById[cargoId]
end

function CargoRegistry.markSold(cargoId: string)
    soldById[cargoId] = true
    local record = recordsById[cargoId]
    if record then
        record.Status = "Sold"
    end
    recalcActiveCargoCount()
end

function CargoRegistry.isSold(cargoId: string): boolean
    return soldById[cargoId] == true
end

function CargoRegistry.countOwnedBy(userId: number): number
    local count = 0
    for cargoId, record in pairs(recordsById) do
        if not soldById[cargoId] and record.OriginalOwnerUserId == userId and record.Status ~= "Sold" then
            count += 1
        end
    end
    return count
end

function CargoRegistry.destroyCargo(cargoId: string)
    local model = instancesById[cargoId]
    if model then
        idByInstance[model] = nil
        model:Destroy()
    end

    instancesById[cargoId] = nil
    recordsById[cargoId] = nil
    recalcActiveCargoCount()
end

function CargoRegistry.getActiveOwnedRecordsBy(userId: number): {CargoRecord}
    local records = {}
    for cargoId, record in pairs(recordsById) do
        if not soldById[cargoId] and record.OriginalOwnerUserId == userId and record.Status ~= "Sold" then
            table.insert(records, cloneRecord(record))
        end
    end
    table.sort(records, function(a, b)
        return a.CargoId < b.CargoId
    end)
    return records
end

return CargoRegistry

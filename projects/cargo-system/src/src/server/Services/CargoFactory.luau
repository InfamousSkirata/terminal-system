local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local CargoFactory = {}

local cargoFolder: Folder? = nil
local warnedMissingTemplate = false

local function getCargoFolder(): Folder
    if cargoFolder and cargoFolder.Parent then
        return cargoFolder
    end

    local existing = Workspace:FindFirstChild("CargoCrates")
    if existing and existing:IsA("Folder") then
        cargoFolder = existing
        return existing
    end

    local folder = Instance.new("Folder")
    folder.Name = "CargoCrates"
    folder.Parent = Workspace
    cargoFolder = folder
    return folder
end

local function setAttributeIfNotNil(instance: Instance, name: string, value: any)
    if value ~= nil then
        instance:SetAttribute(name, value)
    end
end

local function findTemplateInstance(): Instance?
    local direct = Workspace:FindFirstChild("CargoModel")
    if direct then
        return direct
    end

    local alt = Workspace:FindFirstChild("cargomodel")
    if alt then
        return alt
    end

    for _, child in ipairs(Workspace:GetChildren()) do
        if string.lower(child.Name) == "cargomodel" then
            return child
        end
    end

    return nil
end

local function getOrMakePrimaryPart(model: Model): BasePart?
    if model.PrimaryPart then
        return model.PrimaryPart
    end
    local part = model:FindFirstChildWhichIsA("BasePart", true)
    if part then
        model.PrimaryPart = part
        return part
    end
    return nil
end

local function makeFallbackModel(record): Model
    local model = Instance.new("Model")
    model.Name = string.format("Cargo_%s", record.CargoType)

    local part = Instance.new("Part")
    part.Name = "Crate"
    part.Size = Vector3.new(2.5, 2.5, 2.5)
    part.Anchored = false
    part.CanCollide = true
    part.TopSurface = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
    part.Color = Color3.fromRGB(138, 93, 59)
    part.Material = Enum.Material.WoodPlanks
    part.Parent = model

    model.PrimaryPart = part
    return model
end

local function buildCargoModel(record): Model
    local template = findTemplateInstance()
    if template then
        if template:IsA("Model") then
            local cloned = template:Clone()
            cloned.Name = string.format("Cargo_%s", record.CargoType)
            local primary = getOrMakePrimaryPart(cloned)
            if primary then
                primary.Anchored = false
                primary.CanCollide = true
            end
            return cloned
        end

        if template:IsA("BasePart") then
            local model = Instance.new("Model")
            model.Name = string.format("Cargo_%s", record.CargoType)
            local part = template:Clone()
            part.Name = "Crate"
            part.Anchored = false
            part.CanCollide = true
            part.Parent = model
            model.PrimaryPart = part
            return model
        end
    end

    if not warnedMissingTemplate then
        warnedMissingTemplate = true
        warn("[CargoFactory] Workspace CargoModel/cargomodel template not found. Using fallback crate.")
    end
    return makeFallbackModel(record)
end

function CargoFactory.createCargo(record)
    local model = buildCargoModel(record)

    setAttributeIfNotNil(model, "CargoId", record.CargoId)
    setAttributeIfNotNil(model, "CargoType", record.CargoType)
    setAttributeIfNotNil(model, "OriginSellerId", record.OriginSellerId)
    setAttributeIfNotNil(model, "DestinationBuyerId", record.DestinationBuyerId)
    setAttributeIfNotNil(model, "PurchasePrice", record.PurchasePrice)
    setAttributeIfNotNil(model, "SellPrice", record.SellPrice)
    setAttributeIfNotNil(model, "OriginalOwnerUserId", record.OriginalOwnerUserId)
    setAttributeIfNotNil(model, "CurrentHolderUserId", record.CurrentHolderUserId)
    setAttributeIfNotNil(model, "IsStolen", record.IsStolen)
    setAttributeIfNotNil(model, "Status", record.Status)

    local folder = getCargoFolder()
    model.Parent = folder
    local primaryPart = getOrMakePrimaryPart(model)
    if primaryPart then
        primaryPart.CFrame = CFrame.new(0, 10, 0)
    end

    CollectionService:AddTag(model, "CargoCrate")

    return model
end

return CargoFactory

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Sellers = require(script.Parent.Parent.Data.Sellers)
local Buyers = require(script.Parent.Parent.Data.Buyers)
local Permits = require(script.Parent.Parent.Data.Permits)

local StartupValidator = {}

local function getStringAttributeFromChain(instance: Instance, attributeName: string): string?
    local current: Instance? = instance
    while current do
        local value = current:GetAttribute(attributeName)
        if type(value) == "string" and value ~= "" then
            return value
        end
        current = current.Parent
    end
    return nil
end

local function validateConfig()
    if Config.Cargo.MaxOwnedPerPlayer < 1 then
        error("Cargo startup failed: invalid Config value (MaxOwnedPerPlayer)")
    end
    if Config.Cargo.PickupPromptDistance <= 0 or Config.Cargo.SellerPromptDistance <= 0 or Config.Cargo.BuyerPromptDistance <= 0 then
        error("Cargo startup failed: invalid Config value (prompt distance)")
    end
end

local function createDefaultSellerIfMissing()
    if #CollectionService:GetTagged("CargoSeller") > 0 then
        return
    end

    local sellerPart = Instance.new("Part")
    sellerPart.Name = "CargoSeller_AlphaOutpost"
    sellerPart.Size = Vector3.new(4, 4, 4)
    sellerPart.Anchored = true
    sellerPart.CanCollide = true
    sellerPart.Position = Vector3.new(0, 4, 0)
    sellerPart:SetAttribute("SellerId", "AlphaOutpost")
    sellerPart.Parent = Workspace
    CollectionService:AddTag(sellerPart, "CargoSeller")
end

local function createDefaultBuyerIfMissing()
    if #CollectionService:GetTagged("CargoBuyer") > 0 or #CollectionService:GetTagged("BlackMarketBuyer") > 0 then
        return
    end

    local buyerPart = Instance.new("Part")
    buyerPart.Name = "CargoBuyer_CoreBuyerA"
    buyerPart.Size = Vector3.new(4, 4, 4)
    buyerPart.Anchored = true
    buyerPart.CanCollide = true
    buyerPart.Position = Vector3.new(20, 4, 0)
    buyerPart:SetAttribute("BuyerId", "CoreBuyerA")
    buyerPart.Parent = Workspace
    CollectionService:AddTag(buyerPart, "CargoBuyer")
end

local function validateTaggedEntities()
    createDefaultSellerIfMissing()
    createDefaultBuyerIfMissing()

    local sellers = CollectionService:GetTagged("CargoSeller")
    if #sellers == 0 then
        error("Cargo startup failed: no CargoSeller-tagged instance found")
    end

    for _, seller in ipairs(sellers) do
        local sellerId = getStringAttributeFromChain(seller, "SellerId")
        if not sellerId then
            error("Cargo startup failed: CargoSeller missing SellerId")
        end
        if not Sellers[sellerId] then
            error(string.format("Cargo startup failed: CargoSeller SellerId '%s' not found in Sellers data", sellerId))
        end
        local requiredPermitId = Sellers[sellerId].RequiredPermitId
        if type(requiredPermitId) == "string" and requiredPermitId ~= "" and not Permits[requiredPermitId] then
            error(string.format("Cargo startup failed: SellerId '%s' requires unknown permit '%s'", sellerId, requiredPermitId))
        end
    end

    local buyers = {}
    for _, buyer in ipairs(CollectionService:GetTagged("CargoBuyer")) do
        table.insert(buyers, buyer)
    end
    for _, buyer in ipairs(CollectionService:GetTagged("BlackMarketBuyer")) do
        table.insert(buyers, buyer)
    end

    if #buyers == 0 then
        error("Cargo startup failed: no CargoBuyer/BlackMarketBuyer-tagged instance found")
    end

    for _, buyer in ipairs(buyers) do
        local buyerId = getStringAttributeFromChain(buyer, "BuyerId")
        if not buyerId then
            error("Cargo startup failed: CargoBuyer missing BuyerId")
        end
        if not Buyers[buyerId] then
            error(string.format("Cargo startup failed: CargoBuyer BuyerId '%s' not found in Buyers data", buyerId))
        end
    end
end

function StartupValidator.validateOrError()
    validateConfig()
    validateTaggedEntities()
end

return StartupValidator

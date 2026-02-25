local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local Sellers = require(script.Parent.Parent.Data.Sellers)
local Permits = require(script.Parent.Parent.Data.Permits)
local Buyers = require(script.Parent.Parent.Data.Buyers)
local CargoCarryService = require(script.Parent.CargoCarryService)
local CargoTradingService = require(script.Parent.CargoTradingService)

local InteractionService = {}

local promptConnections: {[ProximityPrompt]: RBXScriptConnection} = {}
local promptCleanupConnections: {[ProximityPrompt]: RBXScriptConnection} = {}

local function cleanupPromptBindings(prompt: ProximityPrompt)
    local conn = promptConnections[prompt]
    if conn then
        conn:Disconnect()
        promptConnections[prompt] = nil
    end

    local cleanupConn = promptCleanupConnections[prompt]
    if cleanupConn then
        cleanupConn:Disconnect()
        promptCleanupConnections[prompt] = nil
    end
end

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

local function getPrimaryPart(target: Instance): BasePart?
    if target:IsA("Model") then
        if target.PrimaryPart then
            return target.PrimaryPart
        end
        local anyPart = target:FindFirstChildWhichIsA("BasePart", true)
        if anyPart then
            target.PrimaryPart = anyPart
            return anyPart
        end
    elseif target:IsA("BasePart") then
        return target
    else
        local anyPart = target:FindFirstChildWhichIsA("BasePart", true)
        if anyPart then
            return anyPart
        end
    end
    return nil
end

local function getOrCreatePrompt(parent: Instance, promptName: string, actionText: string, objectText: string, maxDistance: number): ProximityPrompt?
    local primaryPart = getPrimaryPart(parent)
    if not primaryPart then
        return nil
    end

    local existing = primaryPart:FindFirstChild(promptName)
    if existing and existing:IsA("ProximityPrompt") then
        existing.ActionText = actionText
        existing.ObjectText = objectText
        existing.MaxActivationDistance = maxDistance
        return existing
    end

    local prompt = Instance.new("ProximityPrompt")
    prompt.Name = promptName
    prompt.ActionText = actionText
    prompt.ObjectText = objectText
    prompt.MaxActivationDistance = maxDistance
    prompt.HoldDuration = 0
    prompt.RequiresLineOfSight = false
    prompt.Parent = primaryPart
    return prompt
end

local function getFirstCargoTypeForSeller(sellerId: string): string?
    local seller = Sellers[sellerId]
    if not seller or not seller.Cargo then
        return nil
    end

    local keys = {}
    for cargoType in pairs(seller.Cargo) do
        table.insert(keys, cargoType)
    end

    table.sort(keys)
    return keys[1]
end

local function bindPrompt(prompt: ProximityPrompt, handler: (Player) -> ())
    if promptConnections[prompt] then
        return
    end

    promptConnections[prompt] = prompt.Triggered:Connect(function(player)
        handler(player)
    end)
    promptCleanupConnections[prompt] = prompt.AncestryChanged:Connect(function(_, parent)
        if parent == nil then
            cleanupPromptBindings(prompt)
        end
    end)
end

local function wireSellerPrompt(sellerInstance: Instance, remotes)
    local sellerId = getStringAttributeFromChain(sellerInstance, "SellerId")
    if not sellerId then
        return
    end

    local cargoType = getFirstCargoTypeForSeller(sellerId)
    if not cargoType then
        return
    end
    local cargoDef = Sellers[sellerId] and Sellers[sellerId].Cargo and Sellers[sellerId].Cargo[cargoType]
    local actionText = "Buy Cargo"
    if cargoDef then
        actionText = string.format("Buy Cargo ($%d)", cargoDef.PurchasePrice)
    end

    local prompt = getOrCreatePrompt(sellerInstance, "CargoSellerPrompt", actionText, "Cargo Seller", Config.Cargo.SellerPromptDistance)
    if not prompt then
        return
    end

    bindPrompt(prompt, function(player)
        local ok, reason = CargoTradingService.tryPurchase(player, sellerId, cargoType, 1)
        if ok then
            return
        end

        if reason == "BUY_REJECT_PERMIT" then
            local sellerDef = Sellers[sellerId]
            local requiredPermitId = sellerDef and sellerDef.RequiredPermitId
            local allowPermitPurchase = sellerDef ~= nil and sellerDef.AllowPermitPurchase == true
            if allowPermitPurchase and type(requiredPermitId) == "string" and requiredPermitId ~= "" then
                local permitDef = Permits[requiredPermitId]
                remotes.OpenPermitUi:FireClient(player, {
                    PermitId = requiredPermitId,
                    Price = permitDef and permitDef.Price or 0,
                })
            else
                remotes.NotifyTradeMessage:FireClient(player, "BUY_REJECT_PERMIT", "Permit required. Buy it from a permit vendor.")
            end
            return
        end

        remotes.NotifyTradeMessage:FireClient(player, reason, nil)
    end)
end

local function getBuyerActionText(buyerId: string): string
    local buyerDef = Buyers[buyerId]
    if not buyerDef then
        return "Sell Cargo"
    end

    if buyerDef.BuyerType == "BlackMarket" then
        local bestPurchasePrice = 0
        for _, sellerDef in pairs(Sellers) do
            for _, cargoDef in pairs(sellerDef.Cargo) do
                if cargoDef.PurchasePrice > bestPurchasePrice then
                    bestPurchasePrice = cargoDef.PurchasePrice
                end
            end
        end
        if bestPurchasePrice > 0 then
            return string.format("Sell Cargo ($%d)", bestPurchasePrice)
        end
        return "Sell Cargo"
    end

    local bestSellPrice = 0
    for _, sellerDef in pairs(Sellers) do
        for _, cargoDef in pairs(sellerDef.Cargo) do
            if cargoDef.DestinationBuyerId == buyerId and cargoDef.SellPrice > bestSellPrice then
                bestSellPrice = cargoDef.SellPrice
            end
        end
    end

    if bestSellPrice > 0 then
        return string.format("Sell Cargo ($%d)", bestSellPrice)
    end
    return "Sell Cargo"
end

local function wireBuyerPrompt(buyerInstance: Instance, remotes)
    local buyerId = getStringAttributeFromChain(buyerInstance, "BuyerId")
    if not buyerId then
        return
    end

    local prompt = getOrCreatePrompt(buyerInstance, "CargoBuyerPrompt", getBuyerActionText(buyerId), "Cargo Buyer", Config.Cargo.BuyerPromptDistance)
    if not prompt then
        return
    end

    bindPrompt(prompt, function(player)
        local ok, reason = CargoTradingService.trySellCarriedToBuyer(player, buyerId)
        if ok then
            return
        end
        if reason == "SELL_REJECT_DEST" then
            remotes.NotifyTradeMessage:FireClient(player, reason, "I'm the wrong man pal.")
            return
        end
        remotes.NotifyTradeMessage:FireClient(player, reason, nil)
    end)
end

local function wireCargoPickupPrompt(cargoModel: Instance)
    local prompt = getOrCreatePrompt(cargoModel, "CargoPickupPrompt", "Pick Up", "Cargo Crate", Config.Cargo.PickupPromptDistance)
    if not prompt then
        return
    end

    if cargoModel:IsA("Model") then
        local status = cargoModel:GetAttribute("Status")
        prompt.Enabled = status ~= "InTransit"
    end

    bindPrompt(prompt, function(player)
        if cargoModel:IsA("Model") then
            CargoCarryService.tryPickUp(player, cargoModel)
        end
    end)
end

function InteractionService.init(remotes)
    for _, seller in ipairs(CollectionService:GetTagged("CargoSeller")) do
        wireSellerPrompt(seller, remotes)
    end

    for _, buyer in ipairs(CollectionService:GetTagged("CargoBuyer")) do
        wireBuyerPrompt(buyer, remotes)
    end
    for _, buyer in ipairs(CollectionService:GetTagged("BlackMarketBuyer")) do
        wireBuyerPrompt(buyer, remotes)
    end

    for _, cargo in ipairs(CollectionService:GetTagged("CargoCrate")) do
        wireCargoPickupPrompt(cargo)
    end

    CollectionService:GetInstanceAddedSignal("CargoSeller"):Connect(function(instance)
        wireSellerPrompt(instance, remotes)
    end)
    CollectionService:GetInstanceAddedSignal("CargoBuyer"):Connect(function(instance)
        wireBuyerPrompt(instance, remotes)
    end)
    CollectionService:GetInstanceAddedSignal("BlackMarketBuyer"):Connect(function(instance)
        wireBuyerPrompt(instance, remotes)
    end)
    CollectionService:GetInstanceAddedSignal("CargoCrate"):Connect(wireCargoPickupPrompt)
end

return InteractionService

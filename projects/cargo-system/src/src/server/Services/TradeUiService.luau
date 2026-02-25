local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local UiTypes = require(ReplicatedStorage:WaitForChild("UiTypes"))

local Sellers = require(script.Parent.Parent.Data.Sellers)
local Buyers = require(script.Parent.Parent.Data.Buyers)
local Permits = require(script.Parent.Parent.Data.Permits)
local CargoRegistry = require(script.Parent.CargoRegistry)
local CargoCarryService = require(script.Parent.CargoCarryService)
local CargoTradingService = require(script.Parent.CargoTradingService)
local PermitService = require(script.Parent.PermitService)

type SellerUiState = UiTypes.SellerUiState
type BuyerUiState = UiTypes.BuyerUiState
type SellerUiProduct = UiTypes.SellerUiProduct

local TradeUiService = {}

local function getSortedProducts(sellerDef): {SellerUiProduct}
    local products = {}
    for _, cargoDef in pairs(sellerDef.Cargo) do
        table.insert(products, {
            CargoType = cargoDef.CargoType,
            PurchasePrice = cargoDef.PurchasePrice,
            SellPrice = cargoDef.SellPrice,
            DestinationBuyerId = cargoDef.DestinationBuyerId,
        })
    end
    table.sort(products, function(a, b)
        return a.CargoType < b.CargoType
    end)
    return products
end

function TradeUiService.getSellerUiState(player: Player, sellerId: string): SellerUiState?
    local sellerDef = Sellers[sellerId]
    if not sellerDef then
        return nil
    end

    local ownedCount = CargoRegistry.countOwnedBy(player.UserId)
    local slotsRemaining = math.max(0, Config.Cargo.MaxOwnedPerPlayer - ownedCount)
    local requiredPermitId = sellerDef.RequiredPermitId
    local missingPermit = false
    local permitPrice: number? = nil

    if type(requiredPermitId) == "string" and requiredPermitId ~= "" then
        missingPermit = not PermitService.playerHasPermit(player, requiredPermitId)
        local permitDef = Permits[requiredPermitId]
        if permitDef then
            permitPrice = permitDef.Price
        end
    end

    local state: SellerUiState = {
        SellerId = sellerId,
        Products = getSortedProducts(sellerDef),
        OwnedCount = ownedCount,
        SlotsRemaining = slotsRemaining,
        RequiredPermitId = requiredPermitId,
        MissingPermit = missingPermit,
        PermitPrice = permitPrice,
    }

    return state
end

function TradeUiService.getBuyerUiState(player: Player, buyerId: string): BuyerUiState?
    if not Buyers[buyerId] then
        return nil
    end

    local expectedPayout, expectedReason = CargoTradingService.previewSellToBuyer(player, buyerId)
    local state: BuyerUiState = {
        BuyerId = buyerId,
        HasCarriedCargo = CargoCarryService.getCarriedCargo(player) ~= nil,
        ExpectedPayout = expectedPayout,
        ExpectedReason = expectedReason,
    }
    return state
end

return TradeUiService

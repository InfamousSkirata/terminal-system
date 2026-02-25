local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

local Sellers = require(script.Parent.Parent.Data.Sellers)
local Buyers = require(script.Parent.Parent.Data.Buyers)
local EconomyService = require(script.Parent.EconomyService)
local IdService = require(script.Parent.IdService)
local CargoRegistry = require(script.Parent.CargoRegistry)
local CargoFactory = require(script.Parent.CargoFactory)
local CargoCarryService = require(script.Parent.CargoCarryService)
local PermitService = require(script.Parent.PermitService)
local CargoPersistenceService = require(script.Parent.CargoPersistenceService)
local Diagnostics = require(script.Parent.Diagnostics)

type CargoRecord = Types.CargoRecord

local CargoTradingService = {}
local tradeBusyByUserId: {[number]: boolean} = {}
local sellBusyByCargoId: {[string]: boolean} = {}

local function withPlayerTradeLock(player: Player, fn: () -> (boolean, string?)): (boolean, string?)
    if tradeBusyByUserId[player.UserId] then
        return false, "TRADE_REJECT_BUSY"
    end

    tradeBusyByUserId[player.UserId] = true
    local ok, resultOk, reason = pcall(fn)
    tradeBusyByUserId[player.UserId] = nil

    if not ok then
        Diagnostics.increment("errors")
        warn(string.format("[CargoTradingService] transaction failed userId=%d err=%s", player.UserId, tostring(resultOk)))
        return false, "TRADE_REJECT_INTERNAL"
    end

    return resultOk, reason
end

local function withCargoSellLock(cargoId: string, fn: () -> (boolean, string?)): (boolean, string?)
    if sellBusyByCargoId[cargoId] then
        return false, "SELL_REJECT_BUSY"
    end

    sellBusyByCargoId[cargoId] = true
    local ok, resultOk, reason = pcall(fn)
    sellBusyByCargoId[cargoId] = nil

    if not ok then
        Diagnostics.increment("errors")
        warn(string.format("[CargoTradingService] sell transaction failed cargoId=%s err=%s", cargoId, tostring(resultOk)))
        return false, "SELL_REJECT_INTERNAL"
    end

    return resultOk, reason
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

local function applyRecordToAttributes(cargoModel: Model, record: CargoRecord)
    cargoModel:SetAttribute("CurrentHolderUserId", record.CurrentHolderUserId)
    cargoModel:SetAttribute("Status", record.Status)
    cargoModel:SetAttribute("IsStolen", record.IsStolen)
end

local function getSellerCargoDef(sellerId: string, cargoType: string)
    local sellerDef = Sellers[sellerId]
    if not sellerDef then
        return nil, nil
    end
    return sellerDef, sellerDef.Cargo[cargoType]
end

local function resolveSaleOutcome(record: CargoRecord, buyerId: string, buyerDef): (boolean, number, string?)
    if not buyerDef then
        return false, 0, "SELL_REJECT_CONFIG"
    end

    if CargoRegistry.isSold(record.CargoId) then
        return false, 0, "SELL_REJECT_ALREADY_SOLD"
    end

    if buyerDef.BuyerType == "Normal" then
        if record.IsStolen then
            return false, 0, "SELL_REJECT_STOLEN"
        end
        if record.DestinationBuyerId ~= buyerId then
            return false, 0, "SELL_REJECT_DEST"
        end
        return true, record.SellPrice, nil
    end

    if buyerDef.BuyerType == "BlackMarket" then
        return true, record.PurchasePrice, nil
    end

    return false, 0, "SELL_REJECT_CONFIG"
end

function CargoTradingService.tryPurchase(player: Player, sellerId: string, cargoType: string, quantity: number): (boolean, string?)
    return withPlayerTradeLock(player, function()
        print(string.format("[P1_TEST] event=buy_attempt seller=%s cargoType=%s qty=%d", sellerId, cargoType, quantity))

        if CargoCarryService.getCarriedCargo(player) then
            Diagnostics.increment("purchases_rejected")
            print(string.format("[P1_TEST] event=buy_result ok=false reason=BUY_REJECT_ALREADY_CARRYING owned=%d credits=%d", CargoRegistry.countOwnedBy(player.UserId), EconomyService.getCredits(player)))
            Diagnostics.log("BUY_REJECT_ALREADY_CARRYING", { userId = player.UserId })
            Diagnostics.printP1Summary("purchase", { carried = 1 })
            return false, "BUY_REJECT_ALREADY_CARRYING"
        end

        if quantity < 1 or quantity > (Config.UI.QuantityMaxPerAction or 5) then
            Diagnostics.increment("purchases_rejected")
            print("[P1_TEST] event=buy_result ok=false reason=BUY_REJECT_CONFIG owned=0 credits=0")
            Diagnostics.printP1Summary("purchase", { carried = CargoCarryService.getCarriedCargo(player) and 1 or 0 })
            return false, "BUY_REJECT_CONFIG"
        end

        local sellerDef, cargoDef = getSellerCargoDef(sellerId, cargoType)
        if not cargoDef then
            Diagnostics.increment("purchases_rejected")
            print(string.format("[P1_TEST] event=buy_result ok=false reason=BUY_REJECT_CONFIG owned=%d credits=%d", CargoRegistry.countOwnedBy(player.UserId), EconomyService.getCredits(player)))
            Diagnostics.log("BUY_REJECT_CONFIG", { userId = player.UserId, sellerId = sellerId, cargoType = cargoType })
            Diagnostics.printP1Summary("purchase", { carried = CargoCarryService.getCarriedCargo(player) and 1 or 0 })
            return false, "BUY_REJECT_CONFIG"
        end

        local requiredPermitId = sellerDef and sellerDef.RequiredPermitId or nil
        if type(requiredPermitId) == "string" and requiredPermitId ~= "" then
            local hasPermit = PermitService.playerHasPermit(player, requiredPermitId)
            print(string.format("[P3_TEST] event=permit_check seller=%s permit=%s has=%s", sellerId, requiredPermitId, tostring(hasPermit)))
            if not hasPermit then
                Diagnostics.increment("purchases_rejected")
                print(string.format("[P1_TEST] event=buy_result ok=false reason=BUY_REJECT_PERMIT owned=%d credits=%d", CargoRegistry.countOwnedBy(player.UserId), EconomyService.getCredits(player)))
                Diagnostics.log("BUY_REJECT_PERMIT", { userId = player.UserId, sellerId = sellerId, permitId = requiredPermitId })
                Diagnostics.printP1Summary("purchase", { carried = CargoCarryService.getCarriedCargo(player) and 1 or 0 })
                return false, "BUY_REJECT_PERMIT"
            end
        end

        local ownedCount = CargoRegistry.countOwnedBy(player.UserId)
        if ownedCount + quantity > Config.Cargo.MaxOwnedPerPlayer then
            Diagnostics.increment("purchases_rejected")
            print(string.format("[P1_TEST] event=buy_result ok=false reason=BUY_REJECT_LIMIT owned=%d credits=%d", ownedCount, EconomyService.getCredits(player)))
            Diagnostics.log("BUY_REJECT_LIMIT", { userId = player.UserId, ownedCount = ownedCount })
            Diagnostics.printP1Summary("purchase", { carried = CargoCarryService.getCarriedCargo(player) and 1 or 0 })
            return false, "BUY_REJECT_LIMIT"
        end

        local totalCost = cargoDef.PurchasePrice * quantity
        local spent, spendReason = EconomyService.trySpend(player, totalCost)
        if not spent then
            Diagnostics.increment("purchases_rejected")
            print(string.format("[P1_TEST] event=buy_result ok=false reason=%s owned=%d credits=%d", spendReason or "BUY_REJECT_FUNDS", ownedCount, EconomyService.getCredits(player)))
            Diagnostics.log("BUY_REJECT_FUNDS", { userId = player.UserId, cost = totalCost })
            Diagnostics.printP1Summary("purchase", { carried = CargoCarryService.getCarriedCargo(player) and 1 or 0 })
            return false, spendReason or "BUY_REJECT_FUNDS"
        end

        local firstModel: Model? = nil

        for _ = 1, quantity do
            local cargoId = IdService.nextCargoId()
            local record: CargoRecord = {
                CargoId = cargoId,
                CargoType = cargoDef.CargoType,
                OriginSellerId = sellerId,
                DestinationBuyerId = cargoDef.DestinationBuyerId,
                PurchasePrice = cargoDef.PurchasePrice,
                SellPrice = cargoDef.SellPrice,
                OriginalOwnerUserId = player.UserId,
                CurrentHolderUserId = nil,
                IsStolen = false,
                PlanetTag = nil,
                Status = "Owned",
            }

            local model = CargoFactory.createCargo(record)
            applyRecordToAttributes(model, record)
            CargoRegistry.register(model, record)

            local root = getCharacterRoot(player)
            if root and model.PrimaryPart then
                model:PivotTo(root.CFrame * CFrame.new(0, 0, -4))
            end

            if not firstModel then
                firstModel = model
            end
        end

        if firstModel and not CargoCarryService.getCarriedCargo(player) then
            CargoCarryService.tryPickUp(player, firstModel)
        end

        Diagnostics.increment("purchases_success", quantity)
        local newOwned = CargoRegistry.countOwnedBy(player.UserId)
        print(string.format("[P1_TEST] event=buy_result ok=true reason=BUY_OK owned=%d credits=%d", newOwned, EconomyService.getCredits(player)))
        Diagnostics.log("BUY_OK", { userId = player.UserId, quantity = quantity, owned = newOwned })
        Diagnostics.printP1Summary("purchase", { carried = CargoCarryService.getCarriedCargo(player) and 1 or 0 })
        CargoPersistenceService.saveForPlayer(player)

        return true, nil
    end)
end

function CargoTradingService.trySellCarriedToBuyer(player: Player, buyerId: string): (boolean, string?)
    return withPlayerTradeLock(player, function()
        local buyerDef = Buyers[buyerId]
        local carried = CargoCarryService.getCarriedCargo(player)

        local cargoId = "none"
        if carried then
            local maybeId = carried:GetAttribute("CargoId")
            if type(maybeId) == "string" then
                cargoId = maybeId
            end
        end

        print(string.format("[P1_TEST] event=sell_attempt buyer=%s cargoId=%s", buyerId, cargoId))

        if not buyerDef then
            Diagnostics.increment("sales_rejected")
            print("[P1_TEST] event=sell_result ok=false reason=SELL_REJECT_CONFIG payout=0")
            Diagnostics.printP1Summary("sell", { credits_delta = 0 })
            return false, "SELL_REJECT_CONFIG"
        end

        if not carried then
            Diagnostics.increment("sales_rejected")
            print("[P1_TEST] event=sell_result ok=false reason=SELL_REJECT_NOCARGO payout=0")
            Diagnostics.log("SELL_REJECT_NOCARGO", { userId = player.UserId, buyerId = buyerId })
            Diagnostics.printP1Summary("sell", { credits_delta = 0 })
            return false, "SELL_REJECT_NOCARGO"
        end

        local record = CargoRegistry.getByInstance(carried)
        if not record then
            Diagnostics.increment("sales_rejected")
            print("[P1_TEST] event=sell_result ok=false reason=SELL_REJECT_INVALID payout=0")
            Diagnostics.printP1Summary("sell", { credits_delta = 0 })
            return false, "SELL_REJECT_INVALID"
        end

        return withCargoSellLock(record.CargoId, function()
            local okSale, payout, saleReason = resolveSaleOutcome(record, buyerId, buyerDef)
            if not okSale then
                Diagnostics.increment("sales_rejected")
                if saleReason == "SELL_REJECT_DEST" then
                    Diagnostics.increment("sell_reject_dest")
                elseif saleReason == "SELL_REJECT_STOLEN" then
                    Diagnostics.increment("sell_reject_stolen")
                elseif saleReason == "SELL_REJECT_ALREADY_SOLD" then
                    Diagnostics.increment("sell_reject_sold")
                end

                local reasonCode = saleReason or "SELL_REJECT_CONFIG"
                if reasonCode == "SELL_REJECT_STOLEN" then
                    print("[P2_TEST] event=sell_result ok=false reason=SELL_REJECT_STOLEN payout=0")
                else
                    print(string.format("[P1_TEST] event=sell_result ok=false reason=%s payout=0", reasonCode))
                end
                Diagnostics.log(reasonCode, { userId = player.UserId, cargoId = record.CargoId, buyerId = buyerId })
                Diagnostics.printP1Summary("sell", { credits_delta = 0 })
                return false, reasonCode
            end

            local successReason = buyerDef.BuyerType == "BlackMarket" and "SELL_OK_BLACKMARKET" or "SELL_OK"

            local before = EconomyService.getCredits(player)
            EconomyService.addCredits(player, payout)
            local after = EconomyService.getCredits(player)

            CargoCarryService.clearCarried(player)
            CargoRegistry.markSold(record.CargoId)
            CargoRegistry.destroyCargo(record.CargoId)

            Diagnostics.increment("sales_success")
            local delta = after - before
            if successReason == "SELL_OK_BLACKMARKET" then
                print(string.format("[P2_TEST] event=sell_result ok=true reason=%s payout=%d", successReason, delta))
            else
                print(string.format("[P1_TEST] event=sell_result ok=true reason=%s payout=%d", successReason, delta))
            end
            Diagnostics.log(successReason, { userId = player.UserId, cargoId = record.CargoId, payout = delta })
            Diagnostics.printP1Summary("sell", { credits_delta = delta })
            CargoPersistenceService.forceSaveForPlayer(player)

            return true, nil
        end)
    end)
end

function CargoTradingService.previewSellToBuyer(player: Player, buyerId: string): (number, string?)
    local buyerDef = Buyers[buyerId]
    if not buyerDef then
        return 0, "SELL_REJECT_CONFIG"
    end

    local carried = CargoCarryService.getCarriedCargo(player)
    if not carried then
        return 0, "SELL_REJECT_NOCARGO"
    end

    local record = CargoRegistry.getByInstance(carried)
    if not record then
        return 0, "SELL_REJECT_INVALID"
    end

    local okSale, payout, reason = resolveSaleOutcome(record, buyerId, buyerDef)
    if not okSale then
        return 0, reason or "SELL_REJECT_CONFIG"
    end

    return payout, nil
end

return CargoTradingService

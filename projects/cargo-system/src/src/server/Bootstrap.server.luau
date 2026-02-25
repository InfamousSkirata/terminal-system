local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local StartupValidator = require(script.Parent.Services.StartupValidator)
local EconomyService = require(script.Parent.Services.EconomyService)
local CargoCarryService = require(script.Parent.Services.CargoCarryService)
local InteractionService = require(script.Parent.Services.InteractionService)
local PermitService = require(script.Parent.Services.PermitService)
local CargoPersistenceService = require(script.Parent.Services.CargoPersistenceService)

local remotes = Remotes.getCargoRemotes()

StartupValidator.validateOrError()
EconomyService.init()
PermitService.init()
CargoPersistenceService.init()
InteractionService.init(remotes)

remotes.RequestDropCarried.OnServerEvent:Connect(function(player)
    CargoCarryService.tryDropCarried(player)
end)

remotes.RequestBuyPermit.OnServerInvoke = function(player, permitId)
    if type(permitId) ~= "string" then
        return { ok = false, reason = "PERMIT_BUY_REJECT_CONFIG" }
    end

    local ok, reason = PermitService.tryPurchasePermit(player, permitId)
    local credits = EconomyService.getCredits(player)
    print(string.format("[P3_TEST] event=permit_buy_result ok=%s reason=%s credits=%d", tostring(ok), reason or "PERMIT_BUY_OK", credits))
    return { ok = ok, reason = reason, credits = credits }
end

task.delay(3, function()
    print("========== START READ HERE ==========")
end)

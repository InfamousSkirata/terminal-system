local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local EconomyService = {}

local function ensureCreditsAttribute(player: Player)
    if player:GetAttribute("Credits") == nil then
        player:SetAttribute("Credits", Config.Economy.StartingCredits)
    end
end

function EconomyService.init()
    Players.PlayerAdded:Connect(function(player)
        ensureCreditsAttribute(player)
    end)

    for _, player in ipairs(Players:GetPlayers()) do
        ensureCreditsAttribute(player)
    end
end

function EconomyService.getCredits(player: Player): number
    ensureCreditsAttribute(player)
    return player:GetAttribute("Credits") or 0
end

function EconomyService.trySpend(player: Player, amount: number): (boolean, string?)
    if amount <= 0 then
        return false, "BUY_REJECT_FUNDS"
    end

    local current = EconomyService.getCredits(player)
    if current < amount then
        return false, "BUY_REJECT_FUNDS"
    end

    player:SetAttribute("Credits", current - amount)
    return true, nil
end

function EconomyService.addCredits(player: Player, amount: number)
    if amount <= 0 then
        return
    end

    local current = EconomyService.getCredits(player)
    player:SetAttribute("Credits", current + amount)
end

return EconomyService

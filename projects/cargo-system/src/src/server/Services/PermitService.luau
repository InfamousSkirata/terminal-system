local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local Permits = require(script.Parent.Parent.Data.Permits)
local EconomyService = require(script.Parent.EconomyService)
local Diagnostics = require(script.Parent.Diagnostics)

local PermitService = {}

local permitStore = DataStoreService:GetDataStore("CargoPermitOwnership")
local ownedByUserId: {[number]: {[string]: boolean}} = {}

local function getPlayerKey(userId: number): string
    return string.format("%s:%d", Config.Permit.DataStoreKeyPrefix, userId)
end

local function normalizePermitMap(raw: any): {[string]: boolean}
    local result: {[string]: boolean} = {}
    if type(raw) ~= "table" then
        return result
    end

    for _, permitId in ipairs(raw) do
        if type(permitId) == "string" and Permits[permitId] then
            result[permitId] = true
        end
    end

    return result
end

local function serializePermitMap(map: {[string]: boolean}): {string}
    local serialized = {}
    for permitId, owned in pairs(map) do
        if owned then
            table.insert(serialized, permitId)
        end
    end
    table.sort(serialized)
    return serialized
end

local function loadPlayerPermits(player: Player)
    local ok, data = pcall(function()
        return permitStore:GetAsync(getPlayerKey(player.UserId))
    end)

    if not ok then
        ownedByUserId[player.UserId] = {}
        Diagnostics.increment("errors")
        warn(string.format("[PermitService] Failed to load permits for userId=%d", player.UserId))
        return
    end

    ownedByUserId[player.UserId] = normalizePermitMap(data)
end

local function savePlayerPermits(userId: number)
    local permits = ownedByUserId[userId]
    if not permits then
        return
    end

    local payload = serializePermitMap(permits)
    local ok, err = pcall(function()
        permitStore:SetAsync(getPlayerKey(userId), payload)
    end)

    if not ok then
        Diagnostics.increment("errors")
        warn(string.format("[PermitService] Failed to save permits for userId=%d err=%s", userId, tostring(err)))
    end
end

function PermitService.init()
    Players.PlayerAdded:Connect(function(player)
        loadPlayerPermits(player)
    end)

    Players.PlayerRemoving:Connect(function(player)
        savePlayerPermits(player.UserId)
        ownedByUserId[player.UserId] = nil
    end)

    for _, player in ipairs(Players:GetPlayers()) do
        loadPlayerPermits(player)
    end
end

function PermitService.getOwnedPermitIds(player: Player): {[string]: boolean}
    if not ownedByUserId[player.UserId] then
        ownedByUserId[player.UserId] = {}
    end
    return ownedByUserId[player.UserId]
end

function PermitService.playerHasPermit(player: Player, permitId: string): boolean
    local map = PermitService.getOwnedPermitIds(player)
    return map[permitId] == true
end

function PermitService.tryPurchasePermit(player: Player, permitId: string): (boolean, string?)
    local permitDef = Permits[permitId]
    if not permitDef then
        Diagnostics.increment("permits_rejected")
        return false, "PERMIT_BUY_REJECT_CONFIG"
    end

    local owned = PermitService.getOwnedPermitIds(player)
    if owned[permitId] then
        Diagnostics.increment("permits_rejected")
        return false, "PERMIT_BUY_REJECT_OWNED"
    end

    local spent = EconomyService.trySpend(player, permitDef.Price)
    if not spent then
        Diagnostics.increment("permits_rejected")
        return false, "PERMIT_BUY_REJECT_FUNDS"
    end

    owned[permitId] = true
    Diagnostics.increment("permits_success")
    task.spawn(function()
        savePlayerPermits(player.UserId)
    end)

    return true, nil
end

return PermitService

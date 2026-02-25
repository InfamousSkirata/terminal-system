local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type CargoRemotes = {
    RequestDropCarried: RemoteEvent,
    OpenPermitUi: RemoteEvent,
    RequestBuyPermit: RemoteFunction,
    NotifyTradeMessage: RemoteEvent,
}

local Remotes = {}

local function getOrCreateFolder(parent: Instance, name: string): Folder
    local existing = parent:FindFirstChild(name)
    if existing and existing:IsA("Folder") then
        return existing
    end

    local folder = Instance.new("Folder")
    folder.Name = name
    folder.Parent = parent
    return folder
end

local function getOrCreateRemoteEvent(parent: Instance, name: string): RemoteEvent
    local existing = parent:FindFirstChild(name)
    if existing and existing:IsA("RemoteEvent") then
        return existing
    end

    local remote = Instance.new("RemoteEvent")
    remote.Name = name
    remote.Parent = parent
    return remote
end

local function getOrCreateRemoteFunction(parent: Instance, name: string): RemoteFunction
    local existing = parent:FindFirstChild(name)
    if existing and existing:IsA("RemoteFunction") then
        return existing
    end

    local remote = Instance.new("RemoteFunction")
    remote.Name = name
    remote.Parent = parent
    return remote
end

function Remotes.getCargoRemotes(): CargoRemotes
    -- "Remotes" is used by this ModuleScript name in ReplicatedStorage.
    -- Use a distinct folder name for runtime RemoteEvents to avoid name collisions.
    local remotesFolder = getOrCreateFolder(ReplicatedStorage, "RuntimeRemotes")
    local cargoFolder = getOrCreateFolder(remotesFolder, "Cargo")

    return {
        RequestDropCarried = getOrCreateRemoteEvent(cargoFolder, "RequestDropCarried"),
        OpenPermitUi = getOrCreateRemoteEvent(cargoFolder, "OpenPermitUi"),
        RequestBuyPermit = getOrCreateRemoteFunction(cargoFolder, "RequestBuyPermit"),
        NotifyTradeMessage = getOrCreateRemoteEvent(cargoFolder, "NotifyTradeMessage"),
    }
end

return Remotes

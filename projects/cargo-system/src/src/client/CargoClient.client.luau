local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local localPlayer = Players.LocalPlayer
local remotes = Remotes.getCargoRemotes()

local function setSellerPromptsEnabled(isEnabled: boolean)
    for _, seller in ipairs(CollectionService:GetTagged("CargoSeller")) do
        local prompt = seller:FindFirstChild("CargoSellerPrompt", true)
        if prompt and prompt:IsA("ProximityPrompt") then
            prompt.Enabled = isEnabled
        end
    end
end

local function refreshSellerPromptVisibility()
    local isCarrying = localPlayer:GetAttribute("IsCarryingCargo") == true
    setSellerPromptsEnabled(not isCarrying)
end

localPlayer:GetAttributeChangedSignal("IsCarryingCargo"):Connect(refreshSellerPromptVisibility)
CollectionService:GetInstanceAddedSignal("CargoSeller"):Connect(function()
    task.defer(refreshSellerPromptVisibility)
end)
task.defer(refreshSellerPromptVisibility)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
    if processed then
        return
    end

    if input.KeyCode == Config.Input.DropKey then
        remotes.RequestDropCarried:FireServer()
    end
end)

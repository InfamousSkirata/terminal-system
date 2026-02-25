local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local remotes = Remotes.getCargoRemotes()

local reasonTextByCode = {
    PERMIT_BUY_REJECT_CONFIG = "Permit purchase failed: invalid permit.",
    PERMIT_BUY_REJECT_OWNED = "Permit already owned.",
    PERMIT_BUY_REJECT_FUNDS = "Permit purchase failed: insufficient credits.",
    BUY_REJECT_PERMIT = "This seller requires a permit.",
    BUY_REJECT_PERMIT_VENDOR = "Permit required. Buy it from a permit vendor.",
}

local currentPermitId: string? = nil

local gui = Instance.new("ScreenGui")
gui.Name = "CargoTradeUi"
gui.ResetOnSpawn = false
gui.Parent = playerGui

local root = Instance.new("Frame")
root.Name = "PermitRoot"
root.Size = UDim2.fromOffset(360, 190)
root.AnchorPoint = Vector2.new(0.5, 0.5)
root.Position = UDim2.fromScale(0.5, 0.5)
root.BackgroundColor3 = Color3.fromRGB(20, 28, 42)
root.BorderSizePixel = 0
root.Visible = false
root.Parent = gui

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -48, 0, 30)
title.Position = UDim2.fromOffset(12, 8)
title.BackgroundTransparency = 1
title.Text = "Permit Required"
title.TextXAlignment = Enum.TextXAlignment.Left
title.Font = Enum.Font.GothamBold
title.TextSize = 18
title.TextColor3 = Color3.fromRGB(245, 245, 245)
title.Parent = root

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.fromOffset(30, 30)
closeButton.Position = UDim2.new(1, -38, 0, 8)
closeButton.BackgroundColor3 = Color3.fromRGB(62, 76, 112)
closeButton.Text = "X"
closeButton.Font = Enum.Font.GothamBold
closeButton.TextSize = 14
closeButton.TextColor3 = Color3.fromRGB(245, 245, 245)
closeButton.Parent = root

local body = Instance.new("TextLabel")
body.Size = UDim2.new(1, -24, 0, 78)
body.Position = UDim2.fromOffset(12, 44)
body.BackgroundTransparency = 1
body.TextWrapped = true
body.TextXAlignment = Enum.TextXAlignment.Left
body.TextYAlignment = Enum.TextYAlignment.Top
body.Font = Enum.Font.Gotham
body.TextSize = 14
body.TextColor3 = Color3.fromRGB(220, 220, 220)
body.Parent = root

local message = Instance.new("TextLabel")
message.Size = UDim2.new(1, -24, 0, 24)
message.Position = UDim2.fromOffset(12, 124)
message.BackgroundTransparency = 1
message.Font = Enum.Font.GothamSemibold
message.TextSize = 13
message.TextXAlignment = Enum.TextXAlignment.Left
message.TextColor3 = Color3.fromRGB(255, 214, 120)
message.Parent = root

local buyButton = Instance.new("TextButton")
buyButton.Size = UDim2.fromOffset(130, 30)
buyButton.Position = UDim2.new(1, -142, 1, -42)
buyButton.BackgroundColor3 = Color3.fromRGB(42, 61, 95)
buyButton.Text = "Purchase Permit"
buyButton.Font = Enum.Font.GothamSemibold
buyButton.TextSize = 13
buyButton.TextColor3 = Color3.fromRGB(245, 245, 245)
buyButton.Parent = root

local function setMessageFromCode(code: string?)
    if not code then
        message.Text = ""
        return
    end
    message.Text = reasonTextByCode[code] or code
end

local function openPermitUi(payload)
    if type(payload) ~= "table" then
        return
    end

    local permitId = payload.PermitId
    local price = payload.Price
    if type(permitId) ~= "string" then
        return
    end

    if type(price) ~= "number" then
        price = 0
    end

    currentPermitId = permitId
    body.Text = string.format("Seller requires permit:\n%s\n\nPrice: $%d", permitId, price)
    setMessageFromCode(nil)
    root.Visible = true
end

closeButton.MouseButton1Click:Connect(function()
    root.Visible = false
    currentPermitId = nil
    setMessageFromCode(nil)
end)

buyButton.MouseButton1Click:Connect(function()
    if not currentPermitId then
        return
    end

    local ok, result = pcall(function()
        return remotes.RequestBuyPermit:InvokeServer(currentPermitId)
    end)
    if not ok or type(result) ~= "table" then
        setMessageFromCode("PERMIT_BUY_REJECT_CONFIG")
        return
    end

    if result.ok then
        message.Text = "Permit purchased."
        task.delay(0.7, function()
            root.Visible = false
        end)
        return
    end

    setMessageFromCode(result.reason)
end)

remotes.OpenPermitUi.OnClientEvent:Connect(openPermitUi)
remotes.NotifyTradeMessage.OnClientEvent:Connect(function(code, text)
    if type(text) == "string" and text ~= "" then
        message.Text = text
        return
    end
    if root.Visible then
        setMessageFromCode(code)
    end
end)

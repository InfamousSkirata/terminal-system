local Config = {
    DiagnosticsEnabled = false,

    Cargo = {
        MaxOwnedPerPlayer = 5,
        CarryOffset = CFrame.new(0, 0, -2.5),
        DropRayDistance = 14,
        DropForwardOffset = 2.2,
        DataStoreKeyPrefix = "cargo_owned_v1",
        MaxInteractDistance = 14,
        PickupPromptDistance = 8,
        SellerPromptDistance = 12,
        BuyerPromptDistance = 18,
        DropTuning = {
            StackClearanceY = 0.03,
            StackYawMaxDeg = 0.35,
            NonStackMinCargoSpacing = 2.2,
            StackSnapRadius = 4.6,
        },
        Despawn = {
            DroppedLifetimeSec = 720,
            NoPlayerRadius = 180,
            VoidY = -250,
        },
    },

    Economy = {
        StartingCredits = 1500,
    },

    Permit = {
        DataStoreKeyPrefix = "cargo_permits_v1",
    },

    UI = {
        SellerMaxRows = 8,
        QuantityMin = 1,
        QuantityMaxPerAction = 5,
    },

    Input = {
        DropKey = Enum.KeyCode.G,
    },
}

return Config

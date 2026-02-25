local Sellers = {
    AlphaOutpost = {
        SellerId = "AlphaOutpost",
        RequiredPermitId = "Permit_CoreTrade",
        AllowPermitPurchase = true,
        Cargo = {
            Spice = {
                CargoType = "Spice",
                PurchasePrice = 100,
                SellPrice = 130,
                DestinationBuyerId = "CoreBuyerA",
            },
        },
    },
}

return Sellers

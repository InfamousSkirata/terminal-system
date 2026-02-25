export type CargoStatus = "Owned" | "Dropped" | "InTransit" | "Sold"

export type CargoRecord = {
    CargoId: string,
    CargoType: string,
    OriginSellerId: string,
    DestinationBuyerId: string,
    PurchasePrice: number,
    SellPrice: number,
    OriginalOwnerUserId: number,
    CurrentHolderUserId: number?,
    IsStolen: boolean,
    PlanetTag: string?,
    Status: CargoStatus,
}

export type SellerCargoDefinition = {
    CargoType: string,
    PurchasePrice: number,
    SellPrice: number,
    DestinationBuyerId: string,
}

export type SellerDefinition = {
    SellerId: string,
    RequiredPermitId: string?,
    AllowPermitPurchase: boolean?,
    Cargo: { [string]: SellerCargoDefinition },
}

export type BuyerDefinition = {
    BuyerId: string,
    BuyerType: "Normal" | "BlackMarket",
}

export type PermitCategory = "Planet" | "Tier" | "Legality"

export type PermitDefinition = {
    PermitId: string,
    DisplayName: string,
    Category: PermitCategory,
    Price: number,
}

return {}

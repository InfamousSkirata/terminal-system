export type SellerUiProduct = {
    CargoType: string,
    PurchasePrice: number,
    SellPrice: number,
    DestinationBuyerId: string,
}

export type SellerUiState = {
    SellerId: string,
    Products: { SellerUiProduct },
    OwnedCount: number,
    SlotsRemaining: number,
    RequiredPermitId: string?,
    MissingPermit: boolean,
    PermitPrice: number?,
}

export type BuyerUiState = {
    BuyerId: string,
    HasCarriedCargo: boolean,
    ExpectedPayout: number,
    ExpectedReason: string?,
}

return {}

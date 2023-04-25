module orderbook::BasicCoin {

    use sui::coin::{Self, TreasuryCap};
    use sui::tx_context::{ TxContext};
    use sui::transfer;
    use std::option::{Self};

    struct XBTC has drop {}

    fun init( ctx: &mut TxContext ) {
        let (treasuryCap, coinMetadata) = coin::create_currency<XBTC>(XBTC{}, 8, b"AC", b"AliCoin", b"", option::none(), ctx);
        transfer::share_object(treasuryCap);
        transfer::freeze_object( coinMetadata );
    }


    public fun mint(
        tc: &mut TreasuryCap<XBTC>,
        receiver: address,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let coins_minted = coin::mint<XBTC>(tc, amount, ctx);
        transfer::transfer(coins_minted, receiver)
    }

}
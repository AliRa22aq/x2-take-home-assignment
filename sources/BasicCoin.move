module orderbook::basicCoin {

    use sui::coin::{Self, TreasuryCap};
    use sui::tx_context::{TxContext};
    use sui::transfer;
    use std::option::{Self};

    struct ALIC has drop {}
    
    // public fun create_witness_for_testing() : ALIC {
    //     ALIC {}
    // }

    fun init(ctx: &mut TxContext ) {
        let test_witness = ALIC {};
        let (treasuryCap, coinMetadata) = coin::create_currency<ALIC>(test_witness, 8, b"AC", b"AliCoin", b"", option::none(), ctx);
        transfer::public_share_object(treasuryCap);
        transfer::public_freeze_object( coinMetadata );
    }

    public fun mint<T: drop>(
        tc: &mut TreasuryCap<T>,
        receiver: address,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let coins_minted = coin::mint<T>(tc, amount, ctx);
        transfer::public_transfer(coins_minted, receiver)
    }


    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }


}
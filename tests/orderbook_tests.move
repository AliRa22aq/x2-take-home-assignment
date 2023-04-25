// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module orderbook::orderbook_tests {

    // use std::debug;
    // use sui::coin::{Self};
    // use std::option::{Self};
    // use sui::transfer;

    use orderbook::basicCoin::{ Self };
    use sui::test_scenario::Self;

    const USER1_ADDRESS: address = @0xA001;

    struct TEST has drop {}

    #[test]
    public fun yooo() {

        let user = @0xA;
        let scenario_val = test_scenario::begin(user);
        let scenario = &mut scenario_val;
        {
            let ctx = test_scenario::ctx(scenario);
            basicCoin::init_for_testing(ctx);
        };

            // let (treasuryCap, coinMetadata) = coin::create_currency<TEST>(TEST {}, 8, b"AC", b"AliCoin", b"", option::none(), ctx);
            // transfer::public_share_object(treasuryCap);
            // transfer::public_freeze_object( coinMetadata );

        // let scenario_val = test_scenario::begin(USER1_ADDRESS);
        // let scenario = &mut scenario_val;
        {   

            // let witness = basicCoin::create_witness_for_testing();

            // let (treasuryCap, coinMetadata) = coin::create_currency<TEST>(
            //     witness, 8, b"AC", b"AliCoin", b"", option::none(), test_scenario::ctx(scenario)
            //     );

            // transfer::public_share_object(treasuryCap);
            
            // basicCoin::mint<ALIC>(
            //     &mut witness, USER1_ADDRESS, 100, test_scenario::ctx(scenario)
            //     );

            // debug::print(&2);
            // test_scenario::return_to_sender(scenario, coinMetadata);

            // Orderbook::create_orderbook(
            //     @0xC001, // This should be an application object ID.
            //     HELLO,
            //     METADATA, // Some metadata (it could be empty).
            //     test_scenario::ctx(scenario)
            // );
        };

        // test_scenario::next_tx(scenario, USER1_ADDRESS);
        // {
        //     assert!(test_scenario::has_most_recent_for_sender<Chat>(scenario), 0);
        //     let chat = test_scenario::take_from_sender<Chat>(scenario); // if can remove, object exists
        //     assert!(chat::text(&chat) == ascii::string(HELLO), 0);
        //     test_scenario::return_to_sender(scenario, chat);
        // };
        test_scenario::end(scenario_val);

    }
}
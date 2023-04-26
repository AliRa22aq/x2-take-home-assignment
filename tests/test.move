// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module orderbook::tests {

    // use std::debug;
    use std::vector;

    use orderbook::orderbook::{Self, OrderBook, BuyOrder, SellOrder};
    use orderbook::erc20::{Self, ERC20};
    use sui::coin::{Self, Coin};
    use sui::transfer;
    use sui::sui::SUI;
    use sui::test_scenario;
    use sui::object::{ID};

    #[test]
    public fun test_erc20_mint() {
        let user = @0xA;

        let scenario_val = test_scenario::begin(user);
        let scenario = &mut scenario_val;
        {
            let ctx = test_scenario::ctx(scenario);
            erc20::init_for_testing(ctx);
        };
        test_scenario::next_tx(scenario, user);
        {
            let ctx = test_scenario::ctx(scenario);

            let num_coins = 10;
            let sui = coin::mint_for_testing<SUI>(num_coins, ctx);
            assert!(coin::value(&sui) == num_coins, 1);

            let coins_minted = 100;
            let coins = coin::mint_for_testing<ERC20>(coins_minted, ctx);
            assert!(coin::value(&coins) == coins_minted, 1);
            
            transfer::public_transfer(sui, user);
            transfer::public_transfer(coins, user);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_orderbook_creation() {
        let user = @0xA;

        let scenario_val = test_scenario::begin(user);
        let scenario = &mut scenario_val;
        {
            let ctx = test_scenario::ctx(scenario);
            orderbook::create_orderbook<ERC20>(ctx);
        };

        // Buy and Sell order list should be empty
        test_scenario::next_tx(scenario, user);
        {
            let orderBook = test_scenario::take_shared<OrderBook<ERC20>>(scenario);
            let buyOrders = orderbook::get_buy_orders(&orderBook);
            let sellOrders = orderbook::get_sell_orders(&orderBook);

            assert!(vector::length<ID>(buyOrders) == 0, 1);
            assert!(vector::length<ID>(sellOrders) == 0, 1);

            test_scenario::return_shared(orderBook);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_create_orders_and_cancel() {
        let user = @0xA;

        let scenario_val = test_scenario::begin(user);
        let scenario = &mut scenario_val;
        {
            let ctx = test_scenario::ctx(scenario);
            orderbook::create_orderbook<ERC20>(ctx);
        };

        // place a buy order and a sell order
        test_scenario::next_tx(scenario, user);
        {

            let orderBook = test_scenario::take_shared<OrderBook<ERC20>>(scenario);
            let num_coins = 100;

            let ctx = test_scenario::ctx(scenario);
            let sui = coin::mint_for_testing<SUI>(num_coins, ctx);
            let coins = coin::mint_for_testing<ERC20>(num_coins, ctx);

            orderbook::place_a_buy_order<ERC20>( 1, 100, sui, &mut orderBook, ctx );
            orderbook::place_a_sell_order<ERC20>( 1, coins, &mut orderBook, ctx );


            test_scenario::return_shared(orderBook);

        };
        
        // let scenario = &mut scenario_val;
        test_scenario::next_tx(scenario, user);
        {

            let buyOrder = test_scenario::take_from_address<BuyOrder<ERC20>>(scenario, user);
            let sellOrder = test_scenario::take_from_address<SellOrder<ERC20>>(scenario, user);

            assert!(orderbook::get_buy_order_status<ERC20>(&buyOrder) == 0, 1);
            assert!(orderbook::get_sell_order_status<ERC20>(&sellOrder) == 0, 1);

            let ctx = test_scenario::ctx(scenario);
            orderbook::cancel_buy_order<ERC20>( &mut buyOrder, ctx );
            orderbook::cancel_sell_order<ERC20>(&mut sellOrder, ctx );

            assert!(orderbook::get_buy_order_status<ERC20>(&buyOrder) == 2, 1);
            assert!(orderbook::get_sell_order_status<ERC20>(&sellOrder) == 2, 1);

            test_scenario::return_to_sender(scenario, buyOrder);
            test_scenario::return_to_sender(scenario, sellOrder);

        };
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_complete_trade() {
        let user = @0xA;
        let user1 = @0xB;
        let user2 = @0xC;

        let scenario_val = test_scenario::begin(user);
        let scenario = &mut scenario_val;
        {
            let ctx = test_scenario::ctx(scenario);
            orderbook::create_orderbook<ERC20>(ctx);

            let num_coins = 100;
            let sui = coin::mint_for_testing<SUI>(num_coins, ctx);
            let coins = coin::mint_for_testing<ERC20>(num_coins, ctx);

            transfer::public_transfer(sui, user1);
            transfer::public_transfer(coins, user2);

        };

        // place a buy order and fulfill it
        {
            test_scenario::next_tx(scenario, user1);
            let orderBook = test_scenario::take_shared<OrderBook<ERC20>>(scenario);
            let sui = test_scenario::take_from_address<Coin<SUI>>(scenario, user1);
            let ctx = test_scenario::ctx(scenario);
            orderbook::place_a_buy_order<ERC20>( 1, 100, sui, &mut orderBook, ctx );
            test_scenario::return_shared(orderBook);


            test_scenario::next_tx(scenario, user2);
            let buyOrder = test_scenario::take_from_address<BuyOrder<ERC20>>(scenario, user1);
            let orderBook = test_scenario::take_shared<OrderBook<ERC20>>(scenario);

            assert!(orderbook::get_buy_order_status<ERC20>(&buyOrder) == 0, 1);

            let coins = test_scenario::take_from_address<Coin<ERC20>>(scenario, user2);
            let ctx = test_scenario::ctx(scenario);
            orderbook::fulfill_buy_order<ERC20>( coins, &mut buyOrder, ctx );
            
            assert!(orderbook::get_buy_order_status<ERC20>(&buyOrder) == 1, 1);

            test_scenario::return_shared(orderBook);
            test_scenario::return_to_address(user1, buyOrder);
                    
        };
        test_scenario::end(scenario_val);
    }


}


// test_scenario::return_to_sender(scenario, buyOrder);
// test_scenario::return_to_sender(scenario, sellOrder);

// test_scenario::next_tx(scenario, user);
// let buyOrder = test_scenario::take_from_address<BuyOrder<ERC20>>(scenario, user);
// let sellOrder = test_scenario::take_from_address<SellOrder<ERC20>>(scenario, user);

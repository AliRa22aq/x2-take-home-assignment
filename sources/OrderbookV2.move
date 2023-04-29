/*
    * What's happening in this contract?

    - Indexing all the order IDs by price categories
    - storing all the orders as Key-Value (IDs => Order) pairs in the main orderbook struct
    - Matching engine will try to match the newly created order with existing offers

    Problem: At the moment, matching only happens when someone is selling exact order size at exact price as someone is trying to buy
    Todos:
    - Make partial order matching
    - Over over order matching by taking using more than one order

    - All remainig functions

*/

module orderbook::orderbookV2 {

    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{ Self, Coin };
    use std::vector::{Self};
    use sui::balance::{Self, Balance};
    
    use sui::object::{ Self, UID, ID };
    use sui::dynamic_object_field as ofield;
    
    // use std::debug;
    // use std::option::{Self, Option};

    const EInsufficientBalance:u64 = 0;
    const ENotAllowed:u64= 1;
    const EOrderNotExists:u64 =1;

    const TRADE_PENDING: u64 = 0;
    const TRADE_FULFILLED: u64 = 1;
    const TRADE_PARTIALLY_FULFILLED: u64 = 2;
    const TRADE_CANCELED: u64 = 3;

    struct SellingOrder<phantom S, phantom E> has key, store {
        id: UID,
        owner: address,
        asking_price_of_each_unit: u64,
        selling_amount: u64,
        // minimum_selling_amount: u64, TODO
        deposited_balance: Balance<S>,
        earned_amount: u64,
        status: u64
    }

    struct BuyingOrder<phantom S, phantom E> has key, store {
        id: UID,
        owner: address,
        bidding_price_of_each_unit: u64,
        buying_amount: u64,
        // minimum_buying_amount: u64, TODO
        deposited_balance: Balance<E>,
        earned_amount: u64,
        status: u64
    }

    struct OrderFamily <phantom S, phantom E> has key, store {
        id: UID,
        selling_orders: vector<ID>,
        buying_orders: vector<ID>,
    }

    struct OrderBook<phantom S, phantom E> has key {
        id: UID,
        best_selling_order_price: u64,
        best_buying_order_price: u64
    }

    /// A new shared orderbook
    public entry fun create_orderbook<S,E>(ctx: &mut TxContext) {      

        let orderBook = OrderBook<S,E> {
            id: object::new(ctx),
            best_selling_order_price: 0,
            best_buying_order_price: 0,
        };

        let genesis_order_family = OrderFamily<S,E> {
            id: object::new(ctx),
            selling_orders: vector::empty<ID>(),
            buying_orders: vector::empty<ID>(),
        };

        // In case the order family is not availabe then this will be used to return an empty vector
        ofield::add(&mut orderBook.id, 0, genesis_order_family );
        transfer::share_object(orderBook);
    
    }

    public entry fun create_selling_order<S, E>(
        _asking_price_of_each_unit: u64,
        _selling_amount: u64,
        _deposited_coins: Coin<S>,
        orderbook: &mut OrderBook<S,E>,
        ctx: &mut TxContext
    ) {

        assert!(_selling_amount > 0, 1);
        assert!(coin::value(&_deposited_coins) == _selling_amount*_asking_price_of_each_unit, 1);

        let new_selling_order_id = object::new(ctx);
        let new_selling_order_id_ref = object::uid_to_inner(&new_selling_order_id);

        // Create a new selling order struct
        let new_selling_order = SellingOrder<S,E> {
            id: new_selling_order_id,
            owner: tx_context::sender(ctx),
            asking_price_of_each_unit: _asking_price_of_each_unit,
            selling_amount: _selling_amount,
            deposited_balance: coin::into_balance(_deposited_coins),
            earned_amount: 0,
            status: TRADE_PENDING
        };

        // Check if any customer exists to fulfill this order
        let cutomer_exists: bool = is_buying_order_exists_by_price(orderbook, _asking_price_of_each_unit);

        // If customer exists then try to get that order
        if(cutomer_exists){

            let order_family =
                ofield::remove<u64, OrderFamily<S,E> >(&mut orderbook.id, _asking_price_of_each_unit);
            let buying_order_id = vector::remove<ID>(&mut order_family.buying_orders, 0);
            let buying_order =
                ofield::remove<ID, BuyingOrder<S,E>>(&mut orderbook.id, buying_order_id);
            
            // Exact match  
            if(new_selling_order.selling_amount == buying_order.buying_amount){

                let selling_earned_amount = balance::value(&buying_order.deposited_balance);
                let buying_earned_amount = balance::value(&new_selling_order.deposited_balance);

                new_selling_order.status = TRADE_FULFILLED;
                buying_order.status = TRADE_FULFILLED;

                let selling_coins = coin::take(&mut new_selling_order.deposited_balance, selling_earned_amount, ctx);
                let buying_coins = coin::take(&mut buying_order.deposited_balance, buying_earned_amount, ctx);
                
                new_selling_order.earned_amount = selling_earned_amount;
                buying_order.earned_amount = buying_earned_amount;

                let buyer_address = buying_order.owner;
                let seller_address = new_selling_order.owner;

                // Transfer new assets to both parties
                transfer::public_transfer(selling_coins , buyer_address);
                transfer::public_transfer(buying_coins, seller_address);

                // Transfer both fulfilled orders objects to their respective owners. As we can't drop them 
                transfer::transfer(buying_order , buyer_address);
                transfer::transfer(new_selling_order, seller_address);
                ofield::add(&mut orderbook.id, _asking_price_of_each_unit, order_family );

            }

            // Partial Match: TODO

            // Matched but not fulfilled because any reason.
            else {
               
                vector::insert(&mut order_family.buying_orders, buying_order_id, 0);
                vector::push_back(&mut order_family.selling_orders, new_selling_order_id_ref);   
                
                ofield::add(&mut orderbook.id, buying_order_id, buying_order );
                ofield::add(&mut orderbook.id, new_selling_order_id_ref, new_selling_order );
                ofield::add(&mut orderbook.id, _asking_price_of_each_unit, order_family );

            }

        }   

        // If no customer exist then add a new selling order entry in record
        else {

            // Check if order family for this price exists or not
            let order_family_exist = ofield::exists_(&orderbook.id, _asking_price_of_each_unit);
            
            if(order_family_exist){

                let order_family =
                    ofield::borrow_mut<u64, OrderFamily<S,E> >(&mut orderbook.id, _asking_price_of_each_unit);
                vector::push_back(&mut order_family.selling_orders, new_selling_order_id_ref); 
                ofield::add(&mut orderbook.id, new_selling_order_id_ref, new_selling_order );
            
            }
            else {
                // If not than create a new OrderFamily struct and set this order only entry of the vector.
                let newOrderFamily = OrderFamily<S,E> {
                    id: object::new(ctx),
                    selling_orders: vector::singleton(new_selling_order_id_ref),
                    buying_orders: vector::empty<ID>(),
                };
                ofield::add(&mut orderbook.id, _asking_price_of_each_unit, newOrderFamily );
                ofield::add(&mut orderbook.id, new_selling_order_id_ref, new_selling_order );

            };

        };
        
        // If no best offer exists already then assign this one as best available offer
        if( _asking_price_of_each_unit > orderbook.best_selling_order_price){
            orderbook.best_selling_order_price = _asking_price_of_each_unit;
        }

    }

    public fun is_buying_order_exists_by_price<S,E>(orderbook: &OrderBook<S,E>, price: u64): bool {
        
        if(ofield::exists_(&orderbook.id, price)) {

            let OrderFamily {id: _, selling_orders: _, buying_orders} = 
                ofield::borrow<u64, OrderFamily<S,E>>(&orderbook.id, price);

            if( vector::length(buying_orders) > 0){
                return true
            }
            else {
                return false
            }

        }
        else {
            return false
        }
    }

    public fun is_order_family_exists_by_price<S,E>(orderbook: &OrderBook<S,E>, price: u64): bool {
        ofield::exists_(&orderbook.id, price)
    }

    // TODO
    public entry fun create_buying_order<S, E>(){}

    public entry fun cancel_selling_order<S,E>(){}
    public entry fun cancel_buying_order<S,E>(){}

    public entry fun take_selling_order_by_price<S,E>(){}
    public entry fun take_selling_order_by_id<S,E>(){}

    public entry fun take_buying_order_by_price<S,E>(){}
    public entry fun take_buying_order_by_id<S,E>(){}

    public entry fun take_best_selling_order<S,E>(){}
    public entry fun take_best_buying_order<S,E>(){}


    public fun get_selling_order_by_id<S,E>(orderbook: &OrderBook<S,E>, selling_order_id: ID): &SellingOrder<S,E>{
        assert!(ofield::exists_(&orderbook.id, selling_order_id), EOrderNotExists);
        ofield::borrow<ID, SellingOrder<S,E>>(&orderbook.id, selling_order_id)
    }

    public fun get_buying_order_by_id<S,E> (orderbook: &OrderBook<S,E>, buying_order_id: ID): &BuyingOrder<S,E>{
        assert!(ofield::exists_(&orderbook.id, buying_order_id), EOrderNotExists);
        ofield::borrow<ID, BuyingOrder<S,E>>(&orderbook.id, buying_order_id)
    }


    // fun is_selling_offer_exists<S,E>(orderbook: &OrderBook<S,E>, price: u64): bool {
    //     ofield::exists_(&orderbook.id, price)
    // }

    // public fun get_best_offer_id_ref<S,E>(orderbook: &OrderBook<S,E>): &Option<ID> {
    //     &orderbook.best_offer
    // }

    // public fun get_offer_family_ref<S,E>(price: u64, orderbook: &OrderBook<S,E>): &vector<Order<S,E>> 
    // {
    //     let order_family_exist = is_offer_exists(orderbook, price);
        
    //     if(order_family_exist){
    //     let OrderFamily {id: _, orders} = ofield::borrow(&orderbook.id, price);
    //     return orders
    //     }
    //     else {
    //         let OrderFamily {id: _, orders} = ofield::borrow(&orderbook.id, 0);
    //         return orders
    //     }

    // }

}


// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module orderbook::tests {

    use std::debug;
    // use std::vector;

    use orderbook::erc20::{Self, ERC20};
    use orderbook::orderbookV2::{Self, OrderBook};
    use sui::coin::{Self};
    use sui::transfer;
    use sui::sui::SUI;
    use sui::test_scenario;
    // use sui::object::{ID};

    // #[test]
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
        let user1 = @0xB;

        debug::print(&11111);

        let scenario_val = test_scenario::begin(user);
        let scenario = &mut scenario_val;
        {
            let ctx = test_scenario::ctx(scenario);
            orderbookV2::create_orderbook<ERC20, SUI>(ctx);
        };

        // Buy and Sell order list should be empty
        test_scenario::next_tx(scenario, user1);
        {
            // let orderBook_ERC20_to_SUI = test_scenario::take_shared<OrderBook<ERC20, SUI>>(scenario);
            // let orderBook_SUI_to_ERC20 = test_scenario::take_shared<OrderBook<SUI, ERC20>>(scenario);
            
            // // debug::print(&orderBook_ERC20_to_SUI);
            // // debug::print(&orderBook_SUI_to_ERC20);

            // let ctx = test_scenario::ctx(scenario);
            // let coins_to_sell = coin::mint_for_testing<ERC20>(100, ctx);
            // orderbookV2::create_offer<ERC20, SUI>(10, coins_to_sell, &mut orderBook_ERC20_to_SUI, ctx);
            
            // let coins_to_sell = coin::mint_for_testing<ERC20>(100, ctx);
            // orderbookV2::create_offer<ERC20, SUI>(10, coins_to_sell, &mut orderBook_ERC20_to_SUI, ctx);

            // let offers = orderbookV2::get_offer_family_ref(10, &orderBook_SUI_to_ERC20);
            // let best_offer = orderbookV2::get_best_offer_id_ref(&orderBook_SUI_to_ERC20);
            // debug::print(offers);
            // debug::print(best_offer);

            // test_scenario::return_shared(orderBook_ERC20_to_SUI);
            // test_scenario::return_shared(orderBook_SUI_to_ERC20);

        };
        test_scenario::end(scenario_val);
    }



}




////////////////////////////////////////////////////////////////////////////////

// if(ofield::exists_(&orderbook.id, price)){
//     let OrderFamily {id: _, selling_orders, buying_orders: _} = 
//         ofield::borrow<u64, OrderFamily<S,E>>(&orderbook.id, price);
//     if( vector::length(selling_orders) > 0){
//         return true
//     }
//     else {
//         return false
//     }
// }
// else {
//     return false
// }

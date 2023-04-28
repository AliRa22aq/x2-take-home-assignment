module orderbook::orderbookV2 {

    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{ Self, Coin };
    use std::vector::{Self};
    use sui::balance::{Self, Balance};
    
    use sui::object::{Self, UID, ID};
    use sui::dynamic_object_field as ofield;
    
    use std::debug;
    use std::option::{Self, Option};

    const EInsufficientBalance:u64 = 0;
    const ENotAllowed:u64= 1;

    const TRADE_PENDING: u64 = 0;
    const TRADE_FULFILLED: u64 = 1;
    const TRADE_PARTIALLY_FULFILLED: u64 = 2;
    const TRADE_CANCELED: u64 = 3;

    struct SellingOrder<phantom S, phantom E> has key, store {
        id: UID,
        owner: address,
        asking_price_of_each_unit: u64,
        selling_amount: Balance<S>,
        minimum_selling_amount: u64,
        earned_amount: Balance<E>,
        status: u64
    }

    struct BuyingOrder<phantom S, phantom E> has key, store {
        id: UID,
        owner: address,
        bidding_price_of_each_unit: u64,
        buying_amount: Balance<S>,
        minimum_buying_amount: u64,
        deposited_amount: Balance<E>,
        status: u64
    }

    struct OrderFamily <phantom S, phantom E> has key, store {
        id: UID,
        selling_orders: vector<SellingOrder<S,E>>,
        buying_orders: vector<BuyingOrder<S,E>>,
    }

    struct OrderBook<phantom S, phantom E> has key {
        id: UID,
        best_selling_order: Option<ID>,
        best_buying_order: Option<ID>,
    }

    /// A new shared orderbook
    public entry fun create_orderbook<S,E>(ctx: &mut TxContext) {      

        let orderBook = OrderBook<S,E> {
            id: object::new(ctx),
            best_selling_order: option::none<ID>(),
            best_buying_order: option::none<ID>()

        };

        let genesis_order_family = OrderFamily<S,E> {
            id: object::new(ctx),
            selling_orders: vector::empty<SellingOrder<S,E>>(),
            buying_orders: vector::empty<BuyingOrder<S,E>>(),
        };

        ofield::add(&mut orderBook.id, 0, genesis_order_family );
        transfer::share_object(orderBook);
    
    }

    public entry fun create_selling_offer<S, E>(
        _asking_price_of_each_unit: u64,
        _selling_amount: Coin<S>,
        _minimum_selling_amount: u64,
        orderbook: &mut OrderBook<S,E>,
        ctx: &mut TxContext
    ) {
        assert!(coin::value(&_selling_amount) > 0, 1);

        let new_order_id = object::new(ctx);

        // If no best offer exists already then assign this one as best available offer
        if(option::is_none(&orderbook.best_selling_order)){
            // debug::print(&option::is_none(&orderbook.best_selling_order));
            orderbook.best_selling_order = option::some(object::uid_to_inner(&new_order_id));
        }
        else{
            let best_selling_order_id_ref= option::borrow(&orderbook.best_selling_order);
            // debug::print(&option::is_none(&orderbook.best_selling_order));
            debug::print(best_selling_order_id_ref);
        };

        // Create a new selling order struct
        let new_selling_order = SellingOrder<S,E> {
            id: new_order_id,
            owner: tx_context::sender(ctx),
            asking_price_of_each_unit: _asking_price_of_each_unit,
            selling_amount: coin::into_balance<S>(_selling_amount),
            minimum_selling_amount: _minimum_selling_amount,
            earned_amount: balance::zero<E>(),
            status: TRADE_PENDING
        };

        // Check if any customer exists to fulfill this order
        let cutomer_exists = is_buying_offer_exists_by_price(orderbook, _asking_price_of_each_unit);
        debug::print(&cutomer_exists);
        // if(cutomer_exists){
        //     let OrderFamily {id: _, selling_orders: _, buying_orders} =
        //         ofield::borrow_mut<u64, OrderFamily<S,E>>(&orderbook.id, price);
        //     let buying_order = vector::borrow_mut(buying_orders, 0);
            
        //     // See if order size is exactly matching
        //         let totalBuyingAmount = buying_order.buying_amount;
        //         let totalSellingAmount = new_selling_order.selling_amount;

        //         // Exact match
        //         if(totalBuyingAmount == totalSellingAmount){

        //         }







        //     // struct SellingOrder<phantom S, phantom E> has key, store {
        //     //     id: UID,
        //     //     owner: address,
        //     //     asking_price_of_each_unit: u64,
        //     //     selling_amount: Balance<S>,
        //     //     minimum_selling_amount: u64,
        //     //     earned_amount: Balance<E>,
        //     //     status: u64
        //     // }

        //     // struct BuyingOrder<phantom S, phantom E> has key, store {
        //     //     id: UID,
        //     //     owner: address,
        //     //     bidding_price_of_each_unit: u64,
        //     //     buying_amount: Balance<S>,
        //     //     minimum_buying_amount: u64,
        //     //     deposited_amount: Balance<E>,
        //     //     status: u64
        //     // }



        // }
        

        // Do somthing with this customer


        // Check if a family of this order already exists
        let order_family_exist = ofield::exists_(&orderbook.id, _asking_price_of_each_unit);
        if(order_family_exist){
            // If exist than take orderFamily struct and push this order in orders vec.
            let OrderFamily {id, selling_orders, buying_orders} = 
                ofield::remove(&mut orderbook.id, _asking_price_of_each_unit);
            
            object::delete(id);
            vector::push_back(&mut selling_orders, new_selling_order);

            let updated_order_family = OrderFamily<S,E> {
                id: object::new(ctx),
                selling_orders, 
                buying_orders
            };
           
            ofield::add(&mut orderbook.id, _asking_price_of_each_unit, updated_order_family );
        
        }
        else {
            // If not than create a new OrderFamily struct and set this order only entry of the vector.
            let newOrderFamily = OrderFamily<S,E> {
                id: object::new(ctx),
                selling_orders: vector::singleton(new_selling_order),
                buying_orders: vector::empty<BuyingOrder<S,E>>(),
            };
            ofield::add(&mut orderbook.id, _asking_price_of_each_unit, newOrderFamily );        
        };

    }

    // No check if buying offer exists or not
    // fun take_matching_buying_order<S,E>(price: u64, orderbook: &OrderBook<S,E>) {
    //     // get the buying offer

    //     let OrderFamily {id: _, selling_orders: _, buying_orders} =
    //         ofield::borrow<u64, OrderFamily<S,E>>(&orderbook.id, price);

    //     let buying_order = vector::borrow(buying_orders, 0);

    //     // Match offer


    // } 


    public fun is_buying_offer_exists_by_price<S,E>(orderbook: &OrderBook<S,E>, price: u64): bool {
        if(ofield::exists_(&orderbook.id, price)){
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
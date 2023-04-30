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
    
    use std::debug;
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
        best_selling_price: u64,
        best_buying_price: u64
    }

    /// A new shared orderbook
    public entry fun create_orderbook<S,E>(ctx: &mut TxContext) {      

        let orderBook = OrderBook<S,E> {
            id: object::new(ctx),
            best_selling_price: 0,
            best_buying_price: 0,
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

    public entry fun create_sell_order<S, E>(
        _asking_price_of_each_unit: u64,
        _selling_amount: u64,
        _deposited_coins: Coin<S>,
        orderbook: &mut OrderBook<S,E>,
        ctx: &mut TxContext
    ): ID {

        assert!(_selling_amount > 0, 1);
        assert!(coin::value(&_deposited_coins) == _selling_amount, 1);

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
        // debug::print(&cutomer_exists);

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
                // transfer::transfer(buying_order , buyer_address);
                // transfer::transfer(new_selling_order, seller_address);

                ofield::add(&mut orderbook.id, buying_order_id, buying_order );
                ofield::add(&mut orderbook.id, new_selling_order_id_ref, new_selling_order );
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

                // If no best offer exists already then assign this one as best available offer
                if( _asking_price_of_each_unit > orderbook.best_selling_price){
                    orderbook.best_selling_price = _asking_price_of_each_unit;
                };

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

            // If no best offer exists already then assign this one as best available offer
            if( _asking_price_of_each_unit > orderbook.best_selling_price){
                orderbook.best_selling_price = _asking_price_of_each_unit;
            };

        };

        return new_selling_order_id_ref
        
    }

    public entry fun create_buy_order<S, E>(
        _bidding_price_of_each_unit: u64,
        _buying_amount: u64,
        _deposited_coins: Coin<E>,
        orderbook: &mut OrderBook<S,E>,
        ctx: &mut TxContext
    ): ID {

        assert!(_buying_amount > 0, 1);
        assert!(coin::value(&_deposited_coins) == _bidding_price_of_each_unit*_buying_amount, 1);

        let new_buying_order_id = object::new(ctx);
        let new_buying_order_id_ref = object::uid_to_inner(&new_buying_order_id);

        // Create a new selling order struct
        let new_buying_order = BuyingOrder<S,E> {
            id: new_buying_order_id,
            owner: tx_context::sender(ctx),
            bidding_price_of_each_unit: _bidding_price_of_each_unit,
            buying_amount: _buying_amount,
            deposited_balance: coin::into_balance(_deposited_coins),
            earned_amount: 0,
            status: TRADE_PENDING
        };
        
        // Check if any customer exists to fulfill this order
        let cutomer_exists: bool = is_selling_order_exists_by_price(orderbook, _bidding_price_of_each_unit);
        debug::print(&cutomer_exists);

        // // If customer exists then try to get that order
        if(cutomer_exists){

            let order_family =
                ofield::remove<u64, OrderFamily<S,E> >(&mut orderbook.id, _bidding_price_of_each_unit);
            let selling_order_id = vector::remove<ID>(&mut order_family.selling_orders, 0);
            let selling_order =
                ofield::remove<ID, SellingOrder<S,E>>(&mut orderbook.id, selling_order_id);
            
            // Exact match  
            if(new_buying_order.buying_amount == selling_order.selling_amount){

                let buying_deposited_amount = balance::value(&new_buying_order.deposited_balance);
                let selling_deposited_amount = balance::value(&selling_order.deposited_balance);

                new_buying_order.status = TRADE_FULFILLED;
                selling_order.status = TRADE_FULFILLED;

                let buying_coins = coin::take(&mut new_buying_order.deposited_balance, buying_deposited_amount, ctx);
                let selling_coins = coin::take(&mut selling_order.deposited_balance, selling_deposited_amount, ctx);
                
                new_buying_order.earned_amount = selling_deposited_amount;
                selling_order.earned_amount = buying_deposited_amount;

                let buyer_address = new_buying_order.owner;
                let seller_address = selling_order.owner;

                // Transfer new assets to both parties
                transfer::public_transfer(selling_coins , buyer_address);
                transfer::public_transfer(buying_coins, seller_address);

                // Transfer both fulfilled orders objects to their respective owners. As we can't drop them 
                // transfer::transfer(new_buying_order , buyer_address);
                // transfer::transfer(selling_order, seller_address);

                ofield::add(&mut orderbook.id, selling_order_id, selling_order );
                ofield::add(&mut orderbook.id, new_buying_order_id_ref, new_buying_order );
                ofield::add(&mut orderbook.id, _bidding_price_of_each_unit, order_family );


            }

            // Partial Match: TODO

            // Matched but not fulfilled because any reason.
            else {
               
                vector::insert(&mut order_family.selling_orders, selling_order_id, 0);
                vector::push_back(&mut order_family.buying_orders, new_buying_order_id_ref);   
                
                ofield::add(&mut orderbook.id, selling_order_id, selling_order );
                ofield::add(&mut orderbook.id, new_buying_order_id_ref, new_buying_order );
                ofield::add(&mut orderbook.id, _bidding_price_of_each_unit, order_family );

                // If no best offer exists already then assign this one as best available offer
                if( _bidding_price_of_each_unit > orderbook.best_buying_price){
                    orderbook.best_buying_price = _bidding_price_of_each_unit;
                };

            }

        }

        // If no customer exist then add a new selling order entry in record
        else {

            // Check if order family for this price exists or not
            let order_family_exist = ofield::exists_(&orderbook.id, _bidding_price_of_each_unit);
            
            if(order_family_exist){

                let order_family =
                    ofield::borrow_mut<u64, OrderFamily<S,E> >(&mut orderbook.id, _bidding_price_of_each_unit);
                vector::push_back(&mut order_family.buying_orders, new_buying_order_id_ref); 
                ofield::add(&mut orderbook.id, new_buying_order_id_ref, new_buying_order );
            
            }
            else {
                // If not than create a new OrderFamily struct and set this order only entry of the vector.
                let newOrderFamily = OrderFamily<S,E> {
                    id: object::new(ctx),
                    selling_orders: vector::empty<ID>(),
                    buying_orders: vector::singleton(new_buying_order_id_ref),
                };

                ofield::add(&mut orderbook.id, _bidding_price_of_each_unit, newOrderFamily );
                ofield::add(&mut orderbook.id, new_buying_order_id_ref, new_buying_order );

            };

            // If no best offer exists already then assign this one as best available offer

            if( _bidding_price_of_each_unit > orderbook.best_buying_price){
                orderbook.best_buying_price = _bidding_price_of_each_unit;
            };


        };

        return new_buying_order_id_ref
        
    }


    public fun is_order_family_exists_by_price<S,E>(orderbook: &OrderBook<S,E>, price: u64): bool {
        ofield::exists_(&orderbook.id, price)
    }

    // TODO
    public entry fun cancel_selling_order<S,E>(){}
    public entry fun cancel_buying_order<S,E>(){}

    public entry fun take_selling_order_by_price<S,E>(){}
    public entry fun take_selling_order_by_id<S,E>(){}

    public entry fun take_buying_order_by_price<S,E>(){}
    public entry fun take_buying_order_by_id<S,E>(){}

    public entry fun take_best_selling_order<S,E>(){}
    public entry fun take_best_buying_order<S,E>(){}


    public fun get_sell_order_by_id<S,E>(orderbook: &OrderBook<S,E>, selling_order_id: ID): &SellingOrder<S,E>{
        assert!(ofield::exists_(&orderbook.id, selling_order_id), EOrderNotExists);
        ofield::borrow<ID, SellingOrder<S,E>>(&orderbook.id, selling_order_id)
    }

    public fun get_buy_order_by_id<S,E> (orderbook: &OrderBook<S,E>, buying_order_id: ID): &BuyingOrder<S,E>{
        assert!(ofield::exists_(&orderbook.id, buying_order_id), EOrderNotExists);
        ofield::borrow<ID, BuyingOrder<S,E>>(&orderbook.id, buying_order_id)
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

    public fun is_selling_order_exists_by_price<S,E>(orderbook: &OrderBook<S,E>, price: u64): bool {
        
        if(ofield::exists_(&orderbook.id, price)) {

            let OrderFamily {id: _, selling_orders, buying_orders:_} = 
                ofield::borrow<u64, OrderFamily<S,E>>(&orderbook.id, price);

            if( vector::length(selling_orders) > 0){
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

    public fun destruct_sell_order<S,E>(o: &SellingOrder<S,E>): 
    (address, u64, u64, u64, u64, u64) {

        (
            o.owner, 
            o.asking_price_of_each_unit, 
            o.selling_amount, 
            balance::value(&o.deposited_balance), 
            o.earned_amount, 
            o.status
        )

    }

    public fun destruct_buy_order<S,E>(o: &BuyingOrder<S,E>): 
    (address, u64, u64, u64, u64, u64) {

        (
            o.owner, 
            o.bidding_price_of_each_unit, 
            o.buying_amount, 
            balance::value(&o.deposited_balance), 
            o.earned_amount, 
            o.status
        )

    }

    public fun get_best_prices<S,E>(ob: &OrderBook<S,E>): (u64, u64) {
        (ob.best_selling_price, ob.best_buying_price)
    }



}


#[test_only]
module orderbook::tests {

    // use std::debug;

    use orderbook::erc20::{Self, ERC20};
    use orderbook::orderbookV2::{Self, OrderBook};
    use sui::coin::{Self};
    use sui::transfer;
    use sui::sui::SUI;
    use sui::test_scenario;

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
        let user1 = @0xB;

        let scenario_val = test_scenario::begin(user);
        let scenario = &mut scenario_val;
        {
            let ctx = test_scenario::ctx(scenario);
            orderbookV2::create_orderbook<ERC20, SUI>(ctx);
        };

        test_scenario::next_tx(scenario, user1);
        {
            let orderBook = test_scenario::take_shared<OrderBook<ERC20, SUI>>(scenario);

            let (best_selling, best_buying) = orderbookV2::get_best_prices(&orderBook);
            assert!(best_selling == 0, 1);
            assert!(best_buying == 0, 1);

            test_scenario::return_shared(orderBook);

        };
        test_scenario::end(scenario_val);

    }

    #[test]
    public fun test_sell_order_creation() {
        let user = @0xA;
        let user1 = @0xB;

        let scenario_val = test_scenario::begin(user);
        let scenario = &mut scenario_val;
        {
            let ctx = test_scenario::ctx(scenario);
            orderbookV2::create_orderbook<ERC20, SUI>(ctx);
        };

        test_scenario::next_tx(scenario, user1);
        {
            let orderBook = test_scenario::take_shared<OrderBook<ERC20, SUI>>(scenario);
            
            let ctx = test_scenario::ctx(scenario);
            let coins_to_sell = coin::mint_for_testing<ERC20>(100, ctx);
            let order_id = orderbookV2::create_sell_order<ERC20, SUI>(
                10,
                100,
                coins_to_sell, 
                &mut orderBook, 
                ctx
            );

            let selling_order = orderbookV2::get_sell_order_by_id(&orderBook, order_id);
            let (owner,asking_price,selling_amount,deposited_amount,earned_amount,status) = orderbookV2::destruct_sell_order(selling_order);
            assert!(owner == user1, 1);
            assert!(asking_price == 10, 1);
            assert!(selling_amount == 100, 1);
            assert!(deposited_amount == 100, 1);
            assert!(earned_amount == 0, 1);
            assert!(status == 0, 1);
            

            let (best_selling, best_buying) = orderbookV2::get_best_prices(&orderBook);
            assert!(best_selling == 10, 1);
            assert!(best_buying == 0, 1);

            test_scenario::return_shared(orderBook);

        };
        test_scenario::end(scenario_val);

    }

    #[test]
    public fun test_buy_order_creation() {
        let user = @0xA;
        let user1 = @0xB;

        let scenario_val = test_scenario::begin(user);
        let scenario = &mut scenario_val;
        {
            let ctx = test_scenario::ctx(scenario);
            orderbookV2::create_orderbook<ERC20, SUI>(ctx);
        };

        test_scenario::next_tx(scenario, user1);
        {
            let orderBook = test_scenario::take_shared<OrderBook<ERC20, SUI>>(scenario);
            
            let ctx = test_scenario::ctx(scenario);
            let coins_to_deposite = coin::mint_for_testing<SUI>(1000, ctx);
            let order_id = orderbookV2::create_buy_order<ERC20, SUI>(
                10,
                100,
                coins_to_deposite, 
                &mut orderBook, 
                ctx
            );

            let buy_order = orderbookV2::get_buy_order_by_id(&orderBook, order_id);
            let (owner,bidding_price,buying_amount,deposited_amount,earned_amount,status) = orderbookV2::destruct_buy_order(buy_order);
            assert!(owner == user1, 1);
            assert!(bidding_price == 10, 1);
            assert!(buying_amount == 100, 1);
            assert!(deposited_amount == 1000, 1);
            assert!(earned_amount == 0, 1);
            assert!(status == 0, 1);
            

            let (best_selling, best_buying) = orderbookV2::get_best_prices(&orderBook);
            assert!(best_selling == 0, 1);
            assert!(best_buying == 10, 1);

            test_scenario::return_shared(orderBook);

        };
        test_scenario::end(scenario_val);

    }

    #[test]
    public fun test_matching_engine() {
        let user = @0xA;
        let user1 = @0xB;
        let user2 = @0xC;

        let scenario_val = test_scenario::begin(user);
        let scenario = &mut scenario_val;
        {
            let ctx = test_scenario::ctx(scenario);
            orderbookV2::create_orderbook<ERC20, SUI>(ctx);
        };

        test_scenario::next_tx(scenario, user1);
        {
            let orderBook = test_scenario::take_shared<OrderBook<ERC20, SUI>>(scenario);
            
            let ctx = test_scenario::ctx(scenario);
            let coins_to_sell = coin::mint_for_testing<ERC20>(100, ctx);
            let selling_order_id = orderbookV2::create_sell_order<ERC20, SUI>(
                10,
                100,
                coins_to_sell, 
                &mut orderBook, 
                ctx
            );

            test_scenario::next_tx(scenario, user2);

            let ctx = test_scenario::ctx(scenario);
            let coins_to_deposite = coin::mint_for_testing<SUI>(1000, ctx);
            let buying_order_id = orderbookV2::create_buy_order<ERC20, SUI>(
                10,
                100,
                coins_to_deposite, 
                &mut orderBook, 
                ctx
            );

            let buy_order = orderbookV2::get_buy_order_by_id(&orderBook, buying_order_id);
            let ( _, _, _, _, earned_amount, status) = orderbookV2::destruct_buy_order(buy_order);
            assert!(earned_amount == 100, 1);
            assert!(status == 1, 1);


            let sell_order = orderbookV2::get_sell_order_by_id(&orderBook, selling_order_id);
            let ( _, _, _, _, earned_amount, status) = orderbookV2::destruct_sell_order(sell_order);
            assert!(earned_amount == 1000, 1);
            assert!(status == 1, 1);


            // test_scenario::return_shared(orderBook);


            test_scenario::return_shared(orderBook);

        };

        // {
            // let orderBook = test_scenario::take_shared<OrderBook<ERC20, SUI>>(scenario);
            
            // let ctx = test_scenario::ctx(scenario);
            // let coins_to_deposite = coin::mint_for_testing<SUI>(1000, ctx);
            // let order_id = orderbookV2::create_buy_order<ERC20, SUI>(
            //     10,
            //     100,
            //     coins_to_deposite, 
            //     &mut orderBook, 
            //     ctx
            // );

            // let buy_order = orderbookV2::get_buy_order_by_id(&orderBook, order_id);
            // let ( _, _, _, _, earned_amount, status) = orderbookV2::destruct_buy_order(buy_order);
            // assert!(earned_amount == 100, 1);
            // assert!(status == 1, 1);

            // test_scenario::return_shared(orderBook);

        // };

        // test_scenario::next_tx(scenario, user);
        // {
        //     let orderBook = test_scenario::take_shared<OrderBook<ERC20, SUI>>(scenario);
            
        //     let ctx = test_scenario::ctx(scenario);
        //     let coins_to_deposite = coin::mint_for_testing<SUI>(1000, ctx);
        //     let order_id = orderbookV2::create_buy_order<ERC20, SUI>(
        //         10,
        //         100,
        //         coins_to_deposite, 
        //         &mut orderBook, 
        //         ctx
        //     );
            
        //     let buy_order = orderbookV2::get_buy_order_by_id(&orderBook, order_id);
        //     let ( _, _, _, _, earned_amount, status) = orderbookV2::destruct_buy_order(buy_order);
        //     assert!(earned_amount == 100, 1);
        //     assert!(status == 1, 1);


        //     test_scenario::return_shared(orderBook);

        // };

        test_scenario::end(scenario_val);

    }


}




////////////////////////////////////////////////////////////////////////////////

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

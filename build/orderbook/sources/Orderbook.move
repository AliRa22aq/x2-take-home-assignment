module orderbook::Orderbook {


    use sui::object::{Self, UID, ID};
    // use sui::object::object_table as ot;
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::sui::SUI;
    use sui::coin::{ Self, Coin };
    use std::vector;
    // use sui::balance::{Self, Balance};

    const EInsufficientBalance:u64 = 0;

    const TRADE_PENDING: u64 = 0;
    const TRADE_FULFILLED: u64 = 1;
    const TRADE_CANCELED: u64 = 2;

    struct SellOrder has key, store {
        id: UID,
        askPerToken: u64,
        amount: u64
    }

    struct BuyOrder has key, store {
        id: UID,
        bidPerToken: u64,
        amount: u64
    }

    struct OrderBook<phantom  T> has key {
        id: UID,
        sellOrders: vector<ID>,
        buyOrders: vector<ID>,
        asset: Coin<T>,
        orderCounts: u64
    }

    public fun create_orderbook<T>(coin: Coin<T>, ctx: &mut TxContext): OrderBook<T> {

        OrderBook {
            id: object::new(ctx),
            sellOrders: vector::empty(),
            buyOrders: vector::empty(),
            asset: coin,
            orderCounts: 0
        }

    }

    public entry fun place_a_buy_order<T>(
        _bidPerToken: u64, 
        _amount: u64, 
        _orderbook: &mut OrderBook<T>,
        payment: &mut Coin<SUI>, 
        ctx: &mut TxContext
    ) {
        let totalAmount: u64 = _amount * _bidPerToken;
        assert!(coin::value(payment) >= totalAmount, EInsufficientBalance);
        
        let orderId = object::new(ctx);

        let newBuyOrder = BuyOrder {
            id: orderId,
            bidPerToken: _bidPerToken,
            amount: _amount
        };

        _orderbook.orderCounts = _orderbook.orderCounts + 1;
        vector::push_back<ID>(&mut _orderbook.buyOrders, object::id(&newBuyOrder));
        transfer::transfer(newBuyOrder, tx_context::sender(ctx));

    }

    public fun get_buy_orders<T>(_orderbook: &OrderBook<T>): vector<ID> {
        _orderbook.buyOrders
    }

    // public fun get_orders_by_user<T>(user: address, _orderbook: &OrderBook<T>): vector<ID> {
        // _orderbook.buyOrders
        // ot.
    // }



    // struct Forge has key, store {
    //     id: UID,
    //     swords_created: u64,
    // }

    // // Part 3: Module initializer to be executed when this module is published
    // fun init(ctx: &mut TxContext) {
    //     let admin = Forge {
    //         id: object::new(ctx),
    //         swords_created: 0,
    //     };
    //     // Transfer the forge object to the module/package publisher
    //     transfer::transfer(admin, tx_context::sender(ctx));
    // }

    // // Part 4: Accessors required to read the struct attributes
    // public fun magic(self: &Sword): u64 {
    //     self.magic
    // }

    // public fun strength(self: &Sword): u64 {
    //     self.strength
    // }

    // public fun swords_created(self: &Forge): u64 {
    //     self.swords_created
    // }

    // Part 5: Public/entry functions (introduced later in the tutorial)

    // Part 6: Private functions (if any)
}

    #[test_only]
    module orderbook::tests {
    use sui::test_scenario;
    // use orderbook::BasicCoin;


    #[test]
    public fun get_buy_orders_for_testing() {


        // let owner = @0x1;
        // let scenario_val = test_scenario::begin(owner);
        
        // let scenario = &mut scenario_val;

        // // Create two ColorObjects owned by `owner`, and obtain their IDs.
        // let (id1, id2) = {
        //     let ctx = test_scenario::ctx(scenario);
        //     color_object::create(255, 255, 255, ctx);
        //     let id1 =
        //         object::id_from_address(tx_context::last_created_object_id(ctx));
        //     color_object::create(0, 0, 0, ctx);
        //     let id2 =
        //         object::id_from_address(tx_context::last_created_object_id(ctx));
        //     (id1, id2)
        // };
        // test_scenario::next_tx(scenario, owner);
        // {
        //     let obj1 = test_scenario::take_from_sender_by_id<ColorObject>(scenario, id1);
        //     let obj2 = test_scenario::take_from_sender_by_id<ColorObject>(scenario, id2);
        //     let (red, green, blue) = color_object::get_color(&obj1);
        //     assert!(red == 255 && green == 255 && blue == 255, 0);

        //     color_object::copy_into(&obj2, &mut obj1);
        //     test_scenario::return_to_sender(scenario, obj1);
        //     test_scenario::return_to_sender(scenario, obj2);
        // };
        // test_scenario::next_tx(scenario, owner);
        // {
        //     let obj1 = test_scenario::take_from_sender_by_id<ColorObject>(scenario, id1);
        //     let (red, green, blue) = color_object::get_color(&obj1);
        //     assert!(red == 0 && green == 0 && blue == 0, 0);
        //     test_scenario::return_to_sender(scenario, obj1);
        // };
        // test_scenario::end(scenario_val);
    
    }
    
}

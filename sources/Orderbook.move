module orderbook::Orderbook {

    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::sui::{SUI};
    use sui::coin::{ Self, Coin };
    use std::vector;

    const EInsufficientBalance:u64 = 0;
    const ENotAllowed:u64= 1;


    const TRADE_PENDING: u64 = 0;
    const TRADE_FULFILLED: u64 = 1;
    const TRADE_CANCELED: u64 = 2;

    struct SellOrder<phantom T> has key, store {
        id: UID,
        askPerToken: u64,
        amount: Coin<T>,
        owner: address,
        status: u64,
        siu_deposited: Coin<SUI>
    }

    struct BuyOrder<phantom T> has key, store {
        id: UID,
        bidPerToken: u64,
        amount: Coin<T>,
        owner: address,
        status: u64,
        siu_deposited: Coin<SUI>
    }

    // Orderbook Struct
    struct OrderBook<phantom  T> has key {
        id: UID,
        sellOrders: vector<ID>,
        buyOrders: vector<ID>,
        asset: Coin<T>,
        orderCounts: u64
    }

    /// Create a new shared orderbook for a perticular asset.
    public fun create_orderbook<T>(coin: Coin<T>, ctx: &mut TxContext) {

        let orderBook = OrderBook {
            id: object::new(ctx),
            sellOrders: vector::empty(),
            buyOrders: vector::empty(),
            asset: coin,
            orderCounts: 0
        };

        transfer::share_object(orderBook);

    }

    // Functinos related buy order
    public entry fun place_a_buy_order<T>(
        _bidPerToken: u64, 
        _amount: Coin<T>, 
        payment: Coin<SUI>, 
        _orderbook: &mut OrderBook<T>,
        ctx: &mut TxContext
    ) {
        let totalAmount = coin::value(&_amount) * _bidPerToken;
        assert!(coin::value(&mut payment) >= totalAmount, EInsufficientBalance);
        
        /*
            Transfer Sui from the user
        */


        let orderId = object::new(ctx);

        let newBuyOrder = BuyOrder {
            id: orderId,
            bidPerToken: _bidPerToken,
            amount: _amount,
            owner: tx_context::sender(ctx),
            status: TRADE_PENDING,
            siu_deposited: payment
        };

        _orderbook.orderCounts = _orderbook.orderCounts + 1;
        vector::push_back<ID>(&mut _orderbook.buyOrders, object::id(&newBuyOrder));
        transfer::transfer(newBuyOrder, tx_context::sender(ctx));

    }

    public entry fun cancel_buy_order<T>(buyOrder: &mut BuyOrder<T>, ctx: &mut TxContext) {
        assert!(buyOrder.owner == tx_context::sender(ctx), ENotAllowed);
        assert!(buyOrder.status == TRADE_PENDING, ENotAllowed);
        
        buyOrder.status = TRADE_CANCELED;

        // let amount = coin::take(&mut coin::into_balance(&buyOrder.siu_deposited), 0, ctx);
        // transfer::transfer(amount, buyOrder.owner)

        // Return Sui to the orignal owner

    }

    public entry fun fulfill_buy_order<T>(
        buyOrder: &mut BuyOrder<T>, 
        payment: Coin<T>, 
        ctx: &mut TxContext
        ) {
        assert!(buyOrder.status == TRADE_PENDING, ENotAllowed);
        assert!(buyOrder.owner == tx_context::sender(ctx), ENotAllowed);

        buyOrder.status = TRADE_FULFILLED;

        // let totalAmount = coin::value(&buyOrder.amount) * buyOrder.bidPerToken;
        // assert!(coin::value(&mut payment) >= totalAmount, EInsufficientBalance);


        // Send tokens to the order owner

        // Send Sui to the seller

    }

    // Functinos related sell order

    public entry fun place_a_sell_order<T>(
        _askPerToken: u64, 
        _amount: Coin<T>, 
        _orderbook: &mut OrderBook<T>,
        ctx: &mut TxContext
    ) {
        let totalAmount = coin::value(&_amount) * _askPerToken;
        assert!(coin::value(&mut _amount) >= totalAmount, EInsufficientBalance);

        /*
            Transfer tokens from the user
        */

        let orderId = object::new(ctx);

        let newSellOrder = SellOrder<T> {
            id: orderId,
            askPerToken: _askPerToken,
            amount: _amount,
            owner: tx_context::sender(ctx),
            status: TRADE_PENDING,
            siu_deposited: coin::zero<SUI>(ctx)
        };

        _orderbook.orderCounts = _orderbook.orderCounts + 1;
        vector::push_back<ID>(&mut _orderbook.sellOrders, object::id(&newSellOrder));
        transfer::transfer(newSellOrder, tx_context::sender(ctx));

    }

    public entry fun cancel_sell_order<T>(sellOrder: &mut SellOrder<T>, ctx: &mut TxContext) {
        assert!(sellOrder.owner == tx_context::sender(ctx), ENotAllowed);
        assert!(sellOrder.status == TRADE_PENDING, ENotAllowed);
        
        sellOrder.status = TRADE_CANCELED;

        // Return Tokens back to the orignal owner

    }

    public entry fun fulfill_sell_order<T>(
        sellOrder: &mut BuyOrder<T>, 
        payment: Coin<SUI>, 
        ctx: &mut TxContext
        ) {
        assert!(sellOrder.status == TRADE_PENDING, ENotAllowed);
        assert!(sellOrder.owner == tx_context::sender(ctx), ENotAllowed);

        sellOrder.status = TRADE_FULFILLED;

        // let totalAmount = coin::value(&buyOrder.amount) * buyOrder.bidPerToken;
        // assert!(coin::value(&mut payment) >= totalAmount, EInsufficientBalance);


        // Send Sui to the order owner

        // Send tokens to the buyer

    }

    // Getter functions

    public fun get_buy_orders<T>(_orderbook: &OrderBook<T>): vector<ID> {
        _orderbook.buyOrders
    }

    public fun get_sell_orders<T>(_orderbook: &OrderBook<T>): vector<ID> {
        _orderbook.sellOrders
    }

}
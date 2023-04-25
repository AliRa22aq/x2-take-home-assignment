module orderbook::Orderbook {

    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::sui::{SUI};
    use sui::coin::{ Self, Coin };
    use std::vector;
    use sui::balance::{Self, Balance};

    const EInsufficientBalance:u64 = 0;
    const ENotAllowed:u64= 1;

    const TRADE_PENDING: u64 = 0;
    const TRADE_FULFILLED: u64 = 1;
    const TRADE_CANCELED: u64 = 2;

    struct SellOrder<phantom T> has key, store {
        id: UID,
        askPerToken: u64,
        tokens_deposite: Balance<T>,
        owner: address,
        status: u64,
    }

    struct BuyOrder<phantom T> has key, store {
        id: UID,
        bidPerToken: u64,
        tokens_desired: Balance<T>,
        sui_deposite: Balance<SUI>,
        owner: address,
        status: u64,
    }

    struct OrderBook<phantom  T> has key {
        id: UID,
        sellOrders: vector<ID>,
        buyOrders: vector<ID>,
        orderCounts: u64
    }

    /// Create a new shared orderbook for a perticular asset.
    public fun create_orderbook<T>(ctx: &mut TxContext) {

        let orderBook = OrderBook<T> {
            id: object::new(ctx),
            sellOrders: vector::empty(),
            buyOrders: vector::empty(),
            orderCounts: 0
            // coinMetadata: _coinMetadata
        };

        transfer::share_object(orderBook);

    }

    public entry fun place_a_buy_order<T>(
        _bidPerToken: u64, 
        _tokenAmountDesired: Coin<T>, 
        payment: Coin<SUI>, 
        _orderbook: &mut OrderBook<T>,
        ctx: &mut TxContext
    ) {
        let sui_required_for_purchase = coin::value(&_tokenAmountDesired) * _bidPerToken;
        assert!(coin::value(&mut payment) >= sui_required_for_purchase, EInsufficientBalance);
        
        let orderId = object::new(ctx);

        let newBuyOrder = BuyOrder<T>{
            id: orderId,
            bidPerToken: _bidPerToken,
            tokens_desired: coin::into_balance<T>(_tokenAmountDesired),
            sui_deposite: coin::into_balance<SUI>(payment),
            owner: tx_context::sender(ctx),
            status: TRADE_PENDING,
        };

        _orderbook.orderCounts = _orderbook.orderCounts + 1;
        vector::push_back<ID>(&mut _orderbook.buyOrders, object::id(&newBuyOrder));
        transfer::public_transfer(newBuyOrder, tx_context::sender(ctx));

    }

    public entry fun cancel_buy_order<T>(buyOrder: &mut BuyOrder<T>, ctx: &mut TxContext) {
        assert!(buyOrder.owner == tx_context::sender(ctx), ENotAllowed);
        assert!(buyOrder.status == TRADE_PENDING, ENotAllowed);
        
        buyOrder.status = TRADE_CANCELED;

        // Return Sui to the orignal owner
        let sui_deposite = coin::take<SUI>(&mut buyOrder.sui_deposite, 0, ctx);
        transfer::public_transfer(sui_deposite, buyOrder.owner)

    }

    public entry fun fulfill_buy_order<T: drop>(
        buyOrder: &mut BuyOrder<T>, 
        tokenPayment: Coin<T>, 
        ctx: &mut TxContext
        ) {
        assert!(buyOrder.status == TRADE_PENDING, ENotAllowed);

        buyOrder.status = TRADE_FULFILLED;
                
        // Send Sui to the seller
        let sui_deposite = coin::take<SUI>(&mut buyOrder.sui_deposite, 0, ctx);
        transfer::public_transfer(sui_deposite, tx_context::sender(ctx));

        // Send tokens to the order owner
        assert!( coin::value(&tokenPayment) >= balance::value<T>(&buyOrder.tokens_desired), EInsufficientBalance);
        transfer::public_transfer(tokenPayment, buyOrder.owner);

    }

    // Sell orders

    public entry fun place_a_sell_order<T>(
        _askPerToken: u64, 
        token_amount_to_sell: Coin<T>,
        _orderbook: &mut OrderBook<T>,
        ctx: &mut TxContext
    ) {

        let orderId = object::new(ctx);

        let newSellOrder = SellOrder<T> {
            id: orderId,
            askPerToken: _askPerToken,
            tokens_deposite: coin::into_balance<T>(token_amount_to_sell),
            owner: tx_context::sender(ctx),
            status: TRADE_PENDING,
        };


        _orderbook.orderCounts = _orderbook.orderCounts + 1;
        vector::push_back<ID>(&mut _orderbook.sellOrders, object::id(&newSellOrder));
        transfer::public_transfer(newSellOrder, tx_context::sender(ctx));

    }

    public entry fun cancel_sell_order<T>(sellOrder: &mut SellOrder<T>, ctx: &mut TxContext) {
        assert!(sellOrder.owner == tx_context::sender(ctx), ENotAllowed);
        assert!(sellOrder.status == TRADE_PENDING, ENotAllowed);
        
        sellOrder.status = TRADE_CANCELED;

        // Return Tokens back to the orignal owner
        let tokens_deposite = coin::take<T>(&mut sellOrder.tokens_deposite, 0, ctx);
        transfer::public_transfer(tokens_deposite, sellOrder.owner);

    }

    public entry fun fulfill_sell_order<T>(
        sellOrder: &mut SellOrder<T>, 
        payment: Coin<SUI>, 
        ctx: &mut TxContext
        ) {
        assert!(sellOrder.status == TRADE_PENDING, ENotAllowed);

        sellOrder.status = TRADE_FULFILLED;

        // Send sui to the order creator
        let sui_required_for_purchase = balance::value(&sellOrder.tokens_deposite) * sellOrder.askPerToken;
        assert!(coin::value(&mut payment) >= sui_required_for_purchase, EInsufficientBalance);
        transfer::public_transfer(payment, sellOrder.owner);

        // Send tokens to current user
        let tokens_desired = coin::take<T>(&mut sellOrder.tokens_deposite, 0, ctx);
        transfer::public_transfer(tokens_desired, tx_context::sender(ctx));

    }

    // Getter functions
    public fun get_buy_orders<T>(_orderbook: &OrderBook<T>): vector<ID> {
        _orderbook.buyOrders
    }

    public fun get_sell_orders<T>(_orderbook: &OrderBook<T>): vector<ID> {
        _orderbook.sellOrders
    }

}
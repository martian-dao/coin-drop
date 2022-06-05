module NFTMarketplace::CoinDrop {
    use Std::Signer;
    use Std::Option::{Self, Option};
    use AptosFramework::Table::{Self, Table};
    use AptosFramework::TestCoin::TestCoin;
    use AptosFramework::Timestamp;
    use AptosFramework::Coin::{Self, Coin};
    use AptosFramework::IterableTable;

    const ERROR_CAN_ONLY_DEPOSIT_IN_PHASE_ONE: u64 = 0;
    const ERROR_CAN_ONLY_WITHDRAW_IN_PHASE_ONE_AND_TWO: u64 = 1;
    const ERROR_INSUFFICIENT_DEPOSIT: u64 = 2;
    const ERROR_NOT_SELLER: u64 = 3;
    const ERROR_DROP_IN_PROGRESS: u64 = 4;
    const ERROR_NOT_CLAIMABLE: u64 = 5;
    const ERROR_SENDER_CANT_BE_SELLER: u64 = 6;

    struct CoinDrop<phantom CoinType> has store, key {
        // total_offering: Coin::Coin<CoinType>,
        total_offering: Option<Coin::Coin<CoinType>>,
        total_offering_amount: u64,
        start_time: u64,
        phase_one_time: u64,
        phase_two_time: u64,
        total_collected: u64,
        participants: IterableTable::IterableTable<address, u64>,
    }
 
    struct TestCoinEscrow<phantom CoinType> has key, store {
        locked_coins: Table<u64, Coin<TestCoin>>, //TODO: change the key somehow to CoinType
    }

    public(script)fun initialize_coin_drop<CoinType>(sender: &signer, coin_amount: u64) {
        let sender_addr = Signer::address_of(sender);
        let start_time = Timestamp::now_microseconds();

        if (!exists<CoinDrop<CoinType>>(sender_addr)) {
            let offered_coins = Coin::withdraw<CoinType>(sender, coin_amount); // TODO: should mint these directly to the accounts of the share holders
            move_to(sender, CoinDrop<CoinType> {
                total_offering: Option::some(offered_coins),
                total_offering_amount: coin_amount,
                start_time: start_time,
                phase_one_time: 10 * 1000000,
                phase_two_time: 10 * 1000000,
                total_collected: 0,
                participants: IterableTable::new<address, u64>(),
            });
        };
    }

    // sender = deposits desired Coin<TestCoin> to the seller 
    // seller = the account which is performing the coin drop
    // can only be called in Phase 1
    public(script) fun deposit<CoinType>(sender: &signer, seller: address, deposit_amount: u64) acquires CoinDrop, TestCoinEscrow {
        let sender_addr = Signer::address_of(sender);
        assert!(sender_addr != seller, ERROR_SENDER_CANT_BE_SELLER);
        
        let curr_time = Timestamp::now_microseconds();
        let coin_drop = borrow_global<CoinDrop<CoinType>>(seller);

        assert!(curr_time >= coin_drop.start_time && curr_time < coin_drop.start_time + coin_drop.phase_one_time, ERROR_CAN_ONLY_DEPOSIT_IN_PHASE_ONE);

        if (!exists<TestCoinEscrow<CoinType>>(sender_addr)) {
            move_to(sender, TestCoinEscrow<CoinType> {
                locked_coins: Table::new<u64, Coin<TestCoin>>()
            });
        };

        let locked_coins = &mut borrow_global_mut<TestCoinEscrow<CoinType>>(sender_addr).locked_coins;
        let deposit = Coin::withdraw<TestCoin>(sender, deposit_amount);
        
        if (Table::contains(locked_coins, &coin_drop.start_time)) {
            let curr_deposit = Table::borrow_mut(locked_coins, &coin_drop.start_time);
            Coin::merge<TestCoin>(curr_deposit, deposit);
        } else {
            Table::add(locked_coins, &coin_drop.start_time, deposit);
        };

        let locked_value = Coin::value(Table::borrow(locked_coins, &coin_drop.start_time));

        let coin_drop_mut = borrow_global_mut<CoinDrop<CoinType>>(seller);
        let participants = &mut coin_drop_mut.participants;
        if(IterableTable::contains(participants, &sender_addr)) {
            IterableTable::remove(participants, &sender_addr);
        };
        IterableTable::add(participants, &sender_addr, locked_value);
    }

    // can only be called in Phase 2
    public(script) fun withdraw<CoinType>(sender: &signer, seller: address, withdraw_amount: u64) acquires CoinDrop, TestCoinEscrow {
        let sender_addr = Signer::address_of(sender);
        assert!(sender_addr != seller, ERROR_SENDER_CANT_BE_SELLER);
        
        let curr_time = Timestamp::now_microseconds();
        let coin_drop = borrow_global<CoinDrop<CoinType>>(seller);

        assert!(curr_time >= coin_drop.start_time && curr_time < coin_drop.start_time + coin_drop.phase_one_time + coin_drop.phase_two_time, ERROR_CAN_ONLY_WITHDRAW_IN_PHASE_ONE_AND_TWO);

        let locked_coins = &mut borrow_global_mut<TestCoinEscrow<CoinType>>(sender_addr).locked_coins;
        let curr_deposit = Table::remove(locked_coins, &coin_drop.start_time);
        
        let remaining = Coin::value(&curr_deposit) - withdraw_amount;
        assert!(remaining >= 0, ERROR_INSUFFICIENT_DEPOSIT);

        // Sending back all the coins for now
        Coin::deposit<TestCoin>(sender_addr, curr_deposit);

        // Book keeping of current value deposit
        if (remaining > 0) {
            deposit<CoinType>(sender, seller, remaining);

            let coin_drop_mut = borrow_global_mut<CoinDrop<CoinType>>(seller);
            let participants = &mut coin_drop_mut.participants;
            IterableTable::remove(participants, &sender_addr);
            IterableTable::add(participants, &sender_addr, remaining);
        } else {
            let coin_drop_mut = borrow_global_mut<CoinDrop<CoinType>>(seller);
            let participants = &mut coin_drop_mut.participants;
            IterableTable::remove(participants, &sender_addr);
        };
    }

    // can be called after Phase 2
    // called by the seller
    public(script) fun claimAsOwner<CoinType>(sender: &signer) acquires CoinDrop, TestCoinEscrow {
        let sender_addr = Signer::address_of(sender);
        assert!(exists<CoinDrop<CoinType>>(sender_addr), ERROR_NOT_SELLER);
        let curr_time = Timestamp::now_microseconds();
        let coin_drop = borrow_global<CoinDrop<CoinType>>(sender_addr);
        assert!(curr_time > coin_drop.start_time + coin_drop.phase_one_time + coin_drop.phase_two_time, ERROR_DROP_IN_PROGRESS);
        let key = IterableTable::head_key(&coin_drop.participants);
        while (Option::is_some(&key)) {
            let key_val = Option::borrow(&key);
            let (_, _, next) = IterableTable::borrow_iter(&coin_drop.participants, key_val);
            
            let locked_coins = &mut borrow_global_mut<TestCoinEscrow<CoinType>>(*key_val).locked_coins;
            let locked_deposit = Table::remove(locked_coins, &coin_drop.start_time);

            Coin::deposit<TestCoin>(sender_addr, locked_deposit);  
            key = next;
        };
    }

    // can be called after Phase 2
    public(script) fun claim<CoinType>(sender: &signer, seller: address) acquires CoinDrop {
        let sender_addr = Signer::address_of(sender);
        assert!(sender_addr != seller, ERROR_SENDER_CANT_BE_SELLER);

        let coin_drop = borrow_global_mut<CoinDrop<CoinType>>(seller);

        let curr_time = Timestamp::now_microseconds();
        assert!(curr_time > coin_drop.start_time + coin_drop.phase_one_time + coin_drop.phase_two_time, ERROR_DROP_IN_PROGRESS);

        let participants = &coin_drop.participants;
        assert!(IterableTable::contains(participants, &sender_addr), ERROR_NOT_CLAIMABLE);

        let deposit_amount = IterableTable::borrow(participants, &sender_addr);

        let total_collected = &mut coin_drop.total_collected; 
        if (*total_collected == 0) { // calculate total_collected for the first time if it's value is not set yet
            let sum = 0;
            let key = IterableTable::head_key(&coin_drop.participants);
            while (Option::is_some(&key)) {
                let key_val = Option::borrow(&key);
                let (val, _, next) = IterableTable::borrow_iter(&coin_drop.participants, key_val);
                sum = sum + *val;
                key = next;
            };
            *total_collected = sum;
        };
        let claimable_amount = (*deposit_amount)/(*total_collected) * coin_drop.total_offering_amount;
        //   let option = coin_drop.total_offering;
        if (!Option::is_none(&(coin_drop.total_offering))) {
            let total_offering: Coin<CoinType> = Option::extract(&mut (coin_drop.total_offering));
            let remaining = Coin::value(&total_offering) - claimable_amount;
            Coin::deposit<CoinType>(sender_addr, total_offering);
            Option::fill(&mut (coin_drop.total_offering), Coin::withdraw<CoinType>(sender, remaining));
        };
    }
}

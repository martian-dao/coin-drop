module NFTMarketplace::CoinDrop {
    use Std::Signer;
    use Std::Option::{Self, Option};
    use AptosFramework::Table::{Self, Table};
    use AptosFramework::TestCoin;
    use AptosFramework::Timestamp;
    use AptosFramework::Coin;
    use AptosFramework::IterableTable;

    const ERROR_CAN_ONLY_DEPOSIT_IN_PHASE_ONE: u64 = 0;
    const ERROR_CAN_ONLY_WITHDRAW_IN_PHASE_ONE_AND_TWO: u64 = 1;
    const ERROR_INSUFFICIENT_DEPOSIT: u64 = 2;
    const ERROR_NOT_SELLER: u64 = 3;
    const ERROR_DROP_IN_PROGRESS: u64 = 4;
    const ERROR_NOT_CLAIMABLE: u64 = 5;

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
        locked_coins: Table<CoinDrop<CoinType>, TestCoin::Coin>,
    }

    public(script)fun initialize_coin_drop<CoinType>(account: &signer, coin_amount: u64) {
        let account_addr = Signer::address_of(account);
        let start_time = Timestamp::now_microseconds();

        if (!exists<CoinDrop<CoinType>>(account_addr)) {
            let offered_coins = Coin::withdraw<CoinType>(account, coin_amount);
            move_to(account, CoinDrop<CoinType> {
                total_offering: Option::some(offered_coins),
                total_offering_amount: coin_amount,
                start_time: start_time,
                phase_one_time: 120 * 1000000,
                phase_two_time: 120 * 1000000,
                total_collected: 0,
                participants: IterableTable::new<address, u64>(),
            });
        };
  }

  public(script) fun deposit<CoinType>(account: &signer, seller: address, deposit_amount: u64) acquires CoinDrop, TestCoinEscrow {
      let account_addr = Signer::address_of(account);
    
      let curr_time = Timestamp::now_microseconds();
      let coin_drop = borrow_global<CoinDrop<CoinType>>(seller);

      assert!(curr_time >= coin_drop.start_time && curr_time < coin_drop.start_time + coin_drop.phase_one_time, ERROR_CAN_ONLY_DEPOSIT_IN_PHASE_ONE);

      if (!exists<TestCoinEscrow<CoinType>>(account_addr)) {
          move_to(account, TestCoinEscrow<CoinType> {
              locked_coins: Table::new<CoinDrop<CoinType>, TestCoin::Coin>()
          });
      };

      let locked_coins = &mut borrow_global_mut<TestCoinEscrow<CoinType>>(account_addr).locked_coins;
      let deposit = TestCoin::withdraw(account, deposit_amount);
      
      if (Table::contains(locked_coins, coin_drop)) {
          let curr_deposit = Table::borrow_mut(locked_coins, coin_drop);
          TestCoin::merge(curr_deposit, deposit);
      } else {
          Table::add(locked_coins, coin_drop, deposit);
      };

      let locked_value = TestCoin::value(Table::borrow(locked_coins, coin_drop));

      let coin_drop_mut = borrow_global_mut<CoinDrop<CoinType>>(seller);
      let participants = &mut coin_drop_mut.participants;
      if(IterableTable::contains(participants, &account_addr)) {
          IterableTable::remove(participants, &account_addr);
      };
      IterableTable::add(participants, &account_addr, locked_value);
  }

  public(script) fun withdraw<CoinType>(account: &signer, seller: address, withdraw_amount: u64) acquires CoinDrop, TestCoinEscrow {
      let account_addr = Signer::address_of(account);
    
      let curr_time = Timestamp::now_microseconds();
      let coin_drop = borrow_global<CoinDrop<CoinType>>(seller);

      assert!(curr_time >= coin_drop.start_time && curr_time < coin_drop.start_time + coin_drop.phase_one_time + coin_drop.phase_two_time, ERROR_CAN_ONLY_WITHDRAW_IN_PHASE_ONE_AND_TWO);

      let locked_coins = &mut borrow_global_mut<TestCoinEscrow<CoinType>>(account_addr).locked_coins;
      let curr_deposit = Table::remove(locked_coins, coin_drop);
      
      let remaining = TestCoin::value(&curr_deposit) - withdraw_amount;
      assert!(remaining > 0, ERROR_INSUFFICIENT_DEPOSIT);

      TestCoin::deposit(account_addr, curr_deposit);

      // Book keeping of current value deposit
      if (remaining > 0) {
          deposit<CoinType>(account, seller, remaining);

          let coin_drop_mut = borrow_global_mut<CoinDrop<CoinType>>(seller);
          let participants = &mut coin_drop_mut.participants;
          IterableTable::remove(participants, &account_addr);
          IterableTable::add(participants, &account_addr, remaining);
      } else {
          let coin_drop_mut = borrow_global_mut<CoinDrop<CoinType>>(seller);
          let participants = &mut coin_drop_mut.participants;
          IterableTable::remove(participants, &account_addr);
      };
  }
  
  public(script) fun claimAsOwner<CoinType>(account: &signer, seller: address) acquires CoinDrop, TestCoinEscrow {
      let account_addr = Signer::address_of(account);      
      assert!(account_addr == seller, ERROR_NOT_SELLER);
      let curr_time = Timestamp::now_microseconds();
      let coin_drop = borrow_global<CoinDrop<CoinType>>(seller);
      assert!(curr_time > coin_drop.start_time + coin_drop.phase_one_time + coin_drop.phase_two_time, ERROR_DROP_IN_PROGRESS);
      let key = IterableTable::head_key(&coin_drop.participants);
      while (Option::is_some(&key)) {
          let key_val = Option::borrow(&key);
          let (_, _, next) = IterableTable::borrow_iter(&coin_drop.participants, key_val);
          
          let locked_coins = &mut borrow_global_mut<TestCoinEscrow<CoinType>>(*key_val).locked_coins;
          let locked_deposit = Table::remove(locked_coins, coin_drop);

          TestCoin::deposit(account_addr, locked_deposit);  
          key = next;
      };
  }

  public(script) fun claim<CoinType>(account: &signer, seller: address) acquires CoinDrop {
      let coin_drop = borrow_global_mut<CoinDrop<CoinType>>(seller);
      let curr_time = Timestamp::now_microseconds();
      assert!(curr_time > coin_drop.start_time + coin_drop.phase_one_time + coin_drop.phase_two_time, ERROR_DROP_IN_PROGRESS);
      let account_addr = Signer::address_of(account);
      let participants = &coin_drop.participants;
      assert!(IterableTable::contains(participants, &account_addr), ERROR_NOT_CLAIMABLE);
      let deposit_amount = IterableTable::borrow(participants, &account_addr);
      let total_collected = &mut coin_drop.total_collected; 
      if (*total_collected == 0) {
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
        let total_offering_value: Coin::Coin<CoinType> = Option::extract(&mut (coin_drop.total_offering));
        let remaining = Coin::value(&total_offering_value) - claimable_amount;
        Coin::deposit(account_addr, total_offering_value);
        Option::fill(&mut (coin_drop.total_offering), Coin::withdraw(account, remaining));
      };
  }
}

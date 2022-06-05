// Copyright (c) The Aptos Foundation
// SPDX-License-Identifier: Apache-2.0


import { Account, RestClient, TESTNET_URL, FAUCET_URL, FaucetClient } from "./first_transaction";

const contractAddress = '0x8fff3fcbdd7eddcdd23acaf260dac4566b5c824726074df27cbbedcba1231f91';

export class CoinDropClient {
  restClient: RestClient;

  constructor(restClient: RestClient) {
    this.restClient = restClient;
  }

  async submitTransactionHelper(account: Account, payload: Record<string, any>) {
    const txn_request = await this.restClient.generateTransaction(account.address(), payload)
    const signed_txn = await this.restClient.signTransaction(account, txn_request)
    const res = await this.restClient.submitTransaction(signed_txn)
    await this.restClient.waitForTransaction(res["hash"])
    return res["hash"];
  }

  async initCoinDrop(account: Account, coin_amount: number) {
    const payload: { function: string; arguments: string[]; type: string; type_arguments: any[] } = {
      type: "script_function_payload",
      function: `${contractAddress}::NFTMarketplace::initialize_coin_drop`,
      type_arguments: [],
      arguments: [
        coin_amount.toString()
      ]
    };
    return await this.submitTransactionHelper(account, payload);
  }

  async deposit(account: Account, seller: string, deposit_amount: number) {
    const payload: { function: string; arguments: string[]; type: string; type_arguments: any[] } = {
      type: "script_function_payload",
      function: `${contractAddress}::NFTMarketplace::deposit`,
      type_arguments: [],
      arguments: [
        seller,
        deposit_amount.toString()
      ]
    };
    return await this.submitTransactionHelper(account, payload);
  }

  async withdraw(account: Account, seller: string, withdraw_amount: number) {
    const payload: { function: string; arguments: string[]; type: string; type_arguments: any[] } = {
      type: "script_function_payload",
      function: `${contractAddress}::NFTMarketplace::withdraw`,
      type_arguments: [],
      arguments: [
        seller,
        withdraw_amount.toString()
      ]
    };
    return await this.submitTransactionHelper(account, payload);
  }

  async claimAsOwner(account: Account) {
    const payload: { function: string; arguments: string[]; type: string; type_arguments: any[] } = {
      type: "script_function_payload",
      function: `${contractAddress}::NFTMarketplace::claimAsOwner`,
      type_arguments: [],
      arguments: [
      ]
    };
    return await this.submitTransactionHelper(account, payload);
  }

  async claim(account: Account, seller: string) {
    const payload: { function: string; arguments: string[]; type: string; type_arguments: any[] } = {
      type: "script_function_payload",
      function: `${contractAddress}::NFTMarketplace::claim`,
      type_arguments: [],
      arguments: [
        seller
      ]
    };
    return await this.submitTransactionHelper(account, payload);
  }
}

async function main() {
    const restClient = new RestClient(TESTNET_URL);
    const client = new CoinDropClient(restClient);
    const faucet_client = new FaucetClient(FAUCET_URL, restClient);


    const seller = new Account();
    const bidder1 = new Account();
    const bidder2 = new Account();
    const bidder3 = new Account();

    console.log("\n=== Addresses ===");
    console.log(`Seller: ${seller.address()}`);
    console.log(`Bidder1: ${bidder1.address()}`);
    console.log(`Bidder2: ${bidder2.address()}`);
    console.log(`Bidder3: ${bidder3.address()}`);

    await faucet_client.fundAccount(seller.address(), 10_000_000);
    await faucet_client.fundAccount(bidder1.address(), 10_000_000);
    await faucet_client.fundAccount(bidder2.address(), 10_000_000);
    await faucet_client.fundAccount(bidder3.address(), 10_000_000);

    console.log("\nAptosCollection and AptosToken created");

    const sellerAddress = `0x${seller.address().toString()}`;
    const creatorAddress = `0x${seller.address().toString()}`;

    console.log("\n=== Initializing Auction ===");
    console.log("transaction hashes");
    console.log(await client.initCoinDrop(seller, 1000)); //10 secs in microseconds

    console.log("\n=== Bidding on the token ===");
    console.log("transaction hashes");
    console.log(await client.deposit(bidder1, sellerAddress, creatorAddress, collection_name, token_name, 10));
    console.log(await client.bid(bidder2, sellerAddress, creatorAddress, collection_name, token_name, 10));
    console.log(await client.bid(bidder3, sellerAddress, creatorAddress, collection_name, token_name, 20));

    function delay(ms: number) {
        return new Promise( resolve => setTimeout(resolve, ms) );
    }
    await delay(10000);

    console.log("\n=== Claiming Token and Coins ===");
    console.log("transaction hashes");
    console.log(await client.claimToken(bidder1, sellerAddress, creatorAddress, collection_name, token_name));
    console.log(await client.claimToken(bidder2, sellerAddress, creatorAddress, collection_name, token_name));
    console.log(await client.claimToken(bidder3, sellerAddress, creatorAddress, collection_name, token_name));
    console.log(await client.claimCoins(seller, creatorAddress, collection_name, token_name));

    var token_balance = await tokenClient.getTokenBalance(sellerAddress, creatorAddress, collection_name, token_name);
    console.log(`\nSeller token balance: ${token_balance}`)

    token_balance = await tokenClient.getTokenBalance(bidder1.address(), creatorAddress, collection_name, token_name);
    console.log(`Bidder 1 token balance: ${token_balance}`)
    
    token_balance = await tokenClient.getTokenBalance(bidder2.address(), creatorAddress, collection_name, token_name);
    console.log(`Bidder 2 token balance: ${token_balance}`)
    
    token_balance = await tokenClient.getTokenBalance(bidder3.address(), creatorAddress, collection_name, token_name);
    console.log(`Bidder 3 token balance: ${token_balance}`)

    // const token_balance = await tokenClient.getTokenBalance('96ac91f63da8514d35c385e76aa5ab5701e5aa13978b35a836feaf31f026aef9', 'f407a02ea4af34410ca0c298eb3e7a43e56bfbc06773d32d15ac6bee5965ee23', collection_name, token_name);
    // console.log(`Bidder 3 token balance: ${token_balance}`)

    return "Test Completed"
}

  if (require.main === module) {
    main().then((resp) => console.log(resp));
  }

# coin-drop
Coin (Fungible Token) Sale for Aptos

This code enables minter of a Coin to make a coin drop to the users. The price of the Coin is decided dynamically using the following protocol

- A seller mints N Coins
- Phase 1: Users deposit TestCoin to the seller's account. User's are allowed to withdraw part/ all of their deposit
- Phase 2: Users can withdraw part/ all of their deposit from the seller's account
- Phase 3: The value of the Coin is decided by the total amount deposited in Phase 1 and 2. Buyer's can claim their share.

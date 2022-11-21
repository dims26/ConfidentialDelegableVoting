## RUNNING THE ELECTION SCRIPT

### Dependencies
1. [Node.js 18.12.1](https://nodejs.org/en/download/releases/)
2. [Remix](https://remix.ethereum.org/)

### Steps
* Navigate to the 'electionScript' directory and create a terminal window
* Install web3 from npm
    > npm install --save web3
* Install ganache from npm
    > npm install --save ganache
* In a separate terminal window, create a blockchain specifying number of accounts(Including Admin, voters, and charity accounts), saving account information to 'accountKeys.json', and locking accounts by default. Take note of the url specified
    > ganache --wallet.accountKeysPath accountKeys.json --wallet.totalAccounts <NUM_ACCOUNTS> -n true
* Using [Remix](https://remix.ethereum.org), compile and deploy (using 'Ganache Provider') the 'AnonymousVoting.sol' and 'Localcrypto.sol' contracts and take note of the contract addresses in the ganache terminal window
* Run the script specifying parameters detailed below

### Script Parameters
* **url**: The url of the ganache blockchain
* **voteAddr**: Address of the deployed 'AnonymousVoting.sol' contract
* **cryptoAddr**: Address of the deployed 'LocalCrypto.sol' contract


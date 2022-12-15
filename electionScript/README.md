## RUNNING THE ELECTION SCRIPT

### Dependencies
1. [Node.js 18.12.1](https://nodejs.org/en/download/releases/)
2. [Remix](https://remix.ethereum.org/)
3. [Web3](https://www.npmjs.com/package/web3)
4. [Ganache](https://www.npmjs.com/package/ganache#documentation)

### Steps
* Create a terminal window and navigate to the 'electionScript' directory
* Install web3 from npm
    > npm install --save web3
* Install ganache from npm
    > npm install --save ganache
* In a separate terminal window, create a blockchain specifying number of accounts(Include the Admin, the voters, and the charity account), saving account information to 'accountKeys.json'. Take note of the url specified in the response
    > ganache --wallet.accountKeysPath accountKeys.json --wallet.totalAccounts <NUM_ACCOUNTS>
* Using [Remix](https://remix.ethereum.org), compile(enable optimization, change compiler version where appropriate) and deploy (selecting 'Ganache Provider') the 'AnonymousVoting.sol' and 'Localcrypto.sol' contracts and take note of the contract addresses in the ganache terminal window.
* The AnonymousVoting smart contract constructor requires the gap parameter (Minimum number of seconds to keep registration open for. Roughly 2*number of voter) and the address of the charity account
* Populate the electionConfig.txt file according to the format specified in the 'Election Config' section with values from 'accountKeys.json'
* Run the script specifying parameters detailed below. Replace the characters between the quotes with the relevant values
    > node election.js --url "http://127.0.0.1:8545" --cryptoAddr "\<crypto address>" --voteAddr "\<vote contract address>"
* As the election runs, a transcript of actions is output onto the terminal console. A log file 'logSummary.txt' is also populated with runtime and gas metrics of relevant operations. 
* Transcripts and logs of the documented elections are provided in the logs folder

### Script Parameters
* **url**: The url of the ganache blockchain
* **voteAddr**: Address of the deployed 'AnonymousVoting.sol' contract
* **cryptoAddr**: Address of the deployed 'LocalCrypto.sol' contract

### Election Config
The electionConfig.txt file specifies the format of the configurable parameters for the election. The file is structured over 5 lines as shown below:

                <Admin address>
                <Charity address>
                <The gap parameter of the AnonymousVoting smart contract>
                <delegator 1 address>: <delegatee address>,<delegator 2 address>: <delegatee address>
                <address of voter voting NO>, <address of voter voting NO>

Replace each angled bracket pair with the relevant information. If there's no information to specify for any line, leave it blank. **Lines 1,2, and 3 are compulsory**

This work adapts an earlier [work](https://github.com/stonecoldpat/anonymousvoting) by Patrick McCorry, Siamak F. Shahandashti, and Feng Hao
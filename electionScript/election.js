import Web3 from 'web3'
import * as fs from 'fs/promises'
import * as fsn from 'fs'
import * as secp256k1 from '@noble/secp256k1'

const CRYPTO_ADDR = '--cryptoAddr'
const VOTE_ADDR = '--voteAddr'
const URL = '--url'
const CRYPTO_ABI_PATH = './abis/cryptoAbi.json'
const VOTE_ABI_PATH = './abis/voteAbi.json'
const WEI_DEPOSIT = '5000000000000000000'
const states = ['SETUP', 'SIGNUP', 'COMMITMENT', 'VOTE', 'FINISHED']
const GAS_LIMIT = 30_000_000

let timeCheck = 0
let gasCheck = 0
let phaseGap = 0

let web3
let rawArgsList
let flags = [URL, VOTE_ADDR, CRYPTO_ADDR]
let flagValues = ['', '', '']
let admin
let charity
let addressMap = {}
let voteAbi
let cryptoAbi
let voteCon
let cryptoCon
let delegations = {}
let deadlines = {}
let noVotes = []
let voters = []

function getVoter(addr) {
    return {
        address: addr,
        x: null,
        xG: null,
        v: null,
        w: null,
        r: null,
        d: null
    }
}

function extractArgs() {
    rawArgsList = process.argv.slice(2)
    
    for (const flag of flags) {
        let index = rawArgsList.indexOf(flag)
        if (index != -1){
            flagValues[flags.indexOf(flag)] = rawArgsList[index + 1]
        }
    }
    console.log('FLAG VALUES')
    console.log(flagValues)
}

function logWriter(value, firstCall = false) {
    if (firstCall)
        fsn.writeFile('logSummary.txt', value, err => {
            if (err) console.error(err)
        })
    else
        fsn.appendFile('logSummary.txt', value, err => {
            if (err) console.error(err)
        })
}

async function readAccountInfo() {
    try {
        let data = await fs.readFile('accountKeys.json', { encoding: 'utf8' })
        let obj = JSON.parse(data)
        let privKeys = obj.private_keys
        console.log('ACCOUNT ADDRESS TO KEYS')
        for (const property in obj.addresses) {
            addressMap[property] = privKeys[property]
        }
        console.log(addressMap)
      } catch (err) {
        console.log('ACCOUNT KEYS ERROR')
        console.log(err)
      }
}

async function readConfig() {
    let data
    try {
        data = (await fs.readFile('electionConfig.txt', { encoding: 'utf8' })).split(/\r?\n/)
    } catch(err) {
        console.log('ELECTION CONFIG READ ERR')
        console.log(err)
    }

    admin = data[0]
    charity = data[1]
    phaseGap = parseInt(data[2])
    if (!Object.keys(addressMap).includes(admin)) throw 'SPECIFIED ADMIN NOT IN "accountKeys.json"'
    if (!Object.keys(addressMap).includes(charity)) throw 'SPECIFIED CHARITY NOT IN "accountKeys.json"'

    if (data[3] && data[3].trim().length !== 0) {
        data[3].split(',').forEach(pair => {
            let p = pair.split(':')
            if (!Object.keys(addressMap).includes(p[0].trim())) throw `Delegator ${p[0].trim()} not in "accountKeys.json`
            if (!Object.keys(addressMap).includes(p[1].trim())) throw `Delegatee ${p[1].trim()} not in "accountKeys.json`
            if (p[1].trim() in delegations) throw `${p[1].trim()} already delegated their vote. Can't delegate to them`
            else delegations[p[0].trim()] = p[1].trim()
        })
    }

    if (data[4] && data[4].trim().length !== 0) {
        data[4].split(',').forEach(addr => {
            if (!Object.keys(addressMap).includes(addr)) throw 'Specified Address not in "accountKeys.json"'
            noVotes.push(addr)
        })
    }

    console.log('ADMIN, CHARITY, AND DELEGATIONS')
    console.log(admin)
    console.log(charity)
    console.log(delegations)

    //read ABIs from ABI folder
    try {
        cryptoAbi = await fs.readFile(CRYPTO_ABI_PATH, {encoding: 'utf8'})
        voteAbi = await fs.readFile(VOTE_ABI_PATH, {encoding: 'utf8'})
    } catch(err) {
        console.log('ABI ERROR')
        console.log(err)
    }
}

function setupConnections() {
    web3 = new Web3(new Web3.providers.HttpProvider(flagValues[flags.indexOf(URL)]))

    voteCon = new web3.eth.Contract(JSON.parse(voteAbi), flagValues[flags.indexOf(VOTE_ADDR)])
    cryptoCon = new web3.eth.Contract(JSON.parse(cryptoAbi), flagValues[flags.indexOf(CRYPTO_ADDR)])
}

//Performed with admin account. Set eligible voters and open registration
async function initElection() {
    let x = await web3.eth.personal.unlockAccount(admin, "")//unlock Admin account
    let now = Math.floor(Date.now()/1000)//timestamp in seconds

    voters = Object.keys(addressMap).filter(add => add != admin && add != charity).map(addr => getVoter(addr))

    //set eligible voters
    timeCheck = Date.now()
    gasCheck = (await voteCon.methods.setEligible(voters.map(v => v.address)).send({from: admin, gas: GAS_LIMIT})).gasUsed
    logWriter(`setEligible duration: ${(Date.now()-timeCheck)} millis and gas used: ${gasCheck} for ${voters.length} voters\n`, true)

    console.log("ELIGIBLE")
    console.log(await voteCon.methods.totaleligible().call())

    //begin voter registration
    if (await voteCon.methods.beginSignUp('Voting question', true,
    (now + phaseGap), (now + (phaseGap * 2)), (now +  (phaseGap * 3)), (now +  (phaseGap * 4)), (now +  (phaseGap * 5)), 
    WEI_DEPOSIT).call({from: admin, value: WEI_DEPOSIT})) {
        timeCheck = Date.now()
        gasCheck = (await voteCon.methods.beginSignUp('Voting question', true, 
        (now + phaseGap), (now + (phaseGap * 2)), (now +  (phaseGap * 3)), (now +  (phaseGap * 4)), (now +  (phaseGap * 5)), 
        WEI_DEPOSIT).send({from: admin, gas: GAS_LIMIT, value: WEI_DEPOSIT})).gasUsed
        logWriter(`beginSignUp duration: ${(Date.now()-timeCheck)}millis and gas used: ${gasCheck}\n`)
    } else {
        throw 'Ethereum rejected deadlines set OR insuffient number of addresses set as eligible'
    }

    console.log("DEPOSIT")
    console.log(await voteCon.methods.depositrequired().call())
    console.log("")

    //deadlines from contract
    console.log("CONTRACT DEADLINES")
    deadlines.votersFinishSignup = (await voteCon.methods.votersFinishSignupPhase().call()) * 1000
    deadlines.endSignup = (await voteCon.methods.endSignupPhase().call()) * 1000
    deadlines.endCommitment = (await voteCon.methods.endCommitmentPhase().call()) * 1000
    deadlines.endVoting = (await voteCon.methods.endVotingPhase().call()) * 1000
    deadlines.endRefund = (await voteCon.methods.endRefundPhase().call()) * 1000
    console.log(deadlines)
    console.log("")
}

async function regVoter(voter) {
    let voterLogin = await web3.eth.personal.unlockAccount(voter.address, "")
    console.log(`voter ${voter.address} logged in : ${voterLogin}`)

    // set voter x, v, r, d and xG. Generate ZKP for voter.
    while(true) {    
        try {
            let xBytes = secp256k1.utils.randomPrivateKey()
            let xHex = secp256k1.utils.bytesToHex(xBytes)
            voter.x = `0x${xHex}`
            let xGPoint = secp256k1.Point.fromPrivateKey(xBytes)
            voter.xG = [`0x${xGPoint.x.toString(16)}`,`0x${xGPoint.y.toString(16)}`]
            voter.v = `0x${secp256k1.utils.bytesToHex(secp256k1.utils.randomPrivateKey())}`
            voter.r = `0x${secp256k1.utils.bytesToHex(secp256k1.utils.randomPrivateKey())}`
            voter.w = `0x${secp256k1.utils.bytesToHex(secp256k1.utils.randomPrivateKey())}`
            voter.d = `0x${secp256k1.utils.bytesToHex(secp256k1.utils.randomPrivateKey())}`

            // We prove knowledge of the voting key
            timeCheck = Date.now()
            var zkp = await cryptoCon.methods.createZKP(voter.x, voter.v, voter.xG).call({from: voter.address, gas: GAS_LIMIT})
            logWriter(`createZKP LOCAL CALL duration: ${(Date.now()-timeCheck)}millis for 1 voter\n`)
            break
        } catch(error) {
            console.log(`voter ${voter.address} zkp error`)
        }
    }
    let vG = [zkp[1], zkp[2], zkp[3]]

    console.log(`CREATED ZKP FOR VOTER ${voter.address}`)

    // Lets make sure the ZKP is valid!
    timeCheck = Date.now()
    let verifyZkp = await cryptoCon.methods.verifyZKP(voter.xG, zkp[0], vG).call({from: voter.address, gas: GAS_LIMIT})
    logWriter(`verifyZKP LOCAL CALL duration: ${(Date.now()-timeCheck)}millis for 1 voter\n`)

    console.log(`ZKP VERIFIED: ${verifyZkp}`)
    if (!verifyZkp) {
        throw `Problem with voting codes. Couldn't verify ZKP for voter ${voter.address}`
    }

    var canRegister = await voteCon.methods.register(voter.xG, vG, zkp[0]).call({from: voter.address, value: WEI_DEPOSIT})
    

    console.log(`CAN REGISTER: ${canRegister}`)

    // Submit voting key to the network
    if (canRegister) {
        timeCheck = Date.now()
        gasCheck = (await voteCon.methods.register(voter.xG, vG, zkp[0]).send({
            from: voter.address,
            gas: GAS_LIMIT,
            value: WEI_DEPOSIT
        })).gasUsed
        logWriter(`register duration: ${(Date.now()-timeCheck)}millis and gas used: ${gasCheck} for 1 voter\n`)
        console.log(`voter ${voter.address} is registered`)
        console.log("")
    } else {
        throw `Registration failed for voter ${voter.address}`
    }
}

async function registerVoters() {
    //for each voter, generate the appropriate values for registration. Save these values in a mapping too and register the voter
    for (const voter of voters){
        await regVoter(voter)
    }

    console.log("VOTERS")
    console.log(voters)
    console.log("")
}

async function registerDelegations() {
    //for each delegator, register delegation   
    let delegators = Object.keys(delegations)

    for (const delegator of delegators) {
        let delegatee = delegations[delegator]
        let delegatorLogin = await web3.eth.personal.unlockAccount(delegator, "")
        console.log(`Delegator ${delegator} logged in : ${delegatorLogin}`)

        let isDelSuccessful = await voteCon.methods.delegate(delegatee).call({from: delegator})
        if (isDelSuccessful) {
            timeCheck = Date.now()
            gasCheck = (await voteCon.methods.delegate(delegatee).send({from: delegator, gas: GAS_LIMIT})).gasUsed
            logWriter(`delegate duration: ${(Date.now()-timeCheck)}millis and gas used: ${gasCheck} for 1 delegator\n`)
            console.log(`Delegator ${delegator} has delegated vote to ${delegatee}`)
            console.log("")
        } else throw `Delegator ${delegator} could not delegate vote to ${delegatee}`
    }
}

async function finishRegistration() {
    //wait till voter registration deadline is reached + buffer
    console.log("WAITING FOR VOTER REGISTRATION DEADLINE...")
    await new Promise(resolve => setTimeout(resolve, (deadlines.votersFinishSignup - Date.now()) + 1000))

    await web3.eth.personal.unlockAccount(admin, "")//unlock Admin account
    //we need a do nothing function to update block number and block time (Only needed on local blockchain),
    //activity on the mainnets and testnets ensure regular block updates
    await voteCon.methods.doNothing().send({from: admin, gas: GAS_LIMIT})

    //admin closes registration once voter registration deadline is reached
    let isRegistrationEnded = await voteCon.methods.finishRegistrationPhase().call({from: admin})
    console.log(`Is registration ended: ${isRegistrationEnded}`)
    if(isRegistrationEnded) {
        timeCheck = Date.now()
        gasCheck = (await voteCon.methods.finishRegistrationPhase().send({from: admin, gas: GAS_LIMIT})).gasUsed
        logWriter(`finishRegistrationPhase (reconstructedKeys) duration: ${(Date.now()-timeCheck)}millis and gas used: ${gasCheck} for ${voters.length} voters\n`)
        console.log('Admin has ended registration')
        console.log(`Election now in state: ${states[await voteCon.methods.state().call({from: admin})]}\n`)
    } else throw `Registration could not be ended`
}

async function subComm(voter) {
    if (delegations[voter.address] != null) {//return if vote delegated
        return
    }
    console.log(`Commitment for voter: ${voter.address}`)
    await web3.eth.personal.unlockAccount(voter.address, "")
    let conVoter = await voteCon.methods.getVoter().call({from: voter.address})
    console.log(`Get voter (Registered keys, reconstructed keys, commitment): ${JSON.stringify(conVoter)}`)

    //get voter registered and reconstructed keys
    let xG = [conVoter[0][0], conVoter[0][1]]
    let yG = [conVoter[1][0], conVoter[1][1]]
    let zkp

    //todo create 1 out of 2 ZKP
    if (noVotes.includes(voter.address)) {
        timeCheck = Date.now()
        zkp = await cryptoCon.methods.create1outof2ZKPNoVote(xG, yG, voter.w, voter.r, voter.d, voter.x).call({from: voter.address})
        logWriter(`create1outof2ZKPNoVote LOCAL CALL duration: ${(Date.now()-timeCheck)}millis for 1 voter\n`)
    } else {
        timeCheck = Date.now()
        zkp = await cryptoCon.methods.create1outof2ZKPYesVote(xG, yG, voter.w, voter.r, voter.d, voter.x).call({from: voter.address})
        logWriter(`create1outof2ZKPYesVote LOCAL CALL duration: ${(Date.now()-timeCheck)}millis for 1 voter\n`)
    }
    // console.log(`One out of two ZKP: ${JSON.stringify(zkp)}`)

    voter.y = [zkp[0][0], zkp[0][1]]
    voter.a1 = [zkp[0][2], zkp[0][3]]
    voter.b1 = [zkp[0][4], zkp[0][5]]
    voter.a2 = [zkp[0][6], zkp[0][7]]
    voter.b2 = [zkp[0][8], zkp[0][9]]
    voter.params = [zkp[1][0], zkp[1][1], zkp[1][2], zkp[1][3]]

    // verify 1 out of 2 ZKP
    let index = await voteCon.methods.addressid(voter.address).call({from: voter.address})
    timeCheck = Date.now()
    let result = await voteCon.methods.verify1outof2ZKP(voter.params, voter.y, voter.a1, voter.b1, voter.a2, voter.b2, index).call({from: voter.address})
    logWriter(`verify1outof2ZKP LOCAL CALL duration: ${(Date.now()-timeCheck)}millis for 1 voter\n`)
    console.log(`ZKP verified: ${JSON.stringify(result)}\n`)

    //submit committment
    let hash = await cryptoCon.methods.commitToVote(voter.params, xG, yG, voter.y, voter.a1, voter.b1, voter.a2, voter.b2).call({from: voter.address})
    timeCheck = Date.now()
    gasCheck = (await voteCon.methods.submitCommitment(hash).send({from: voter.address,gas: GAS_LIMIT})).gasUsed
    logWriter(`submitCommitment duration: ${(Date.now()-timeCheck)}millis and gas used: ${gasCheck} for 1 voter\n`)
}

async function subDelComm(delegator) {
    console.log(`Commitment for delegator: ${delegator}`)
    await web3.eth.personal.unlockAccount(delegator, "")
    let conDelegator = await voteCon.methods.getVoter().call({from: delegator})
    console.log(`Get Delegator (Registered keys, reconstructed keys, commitment): ${JSON.stringify(conDelegator)}`)

    let delegatee = delegations[delegator]
    await web3.eth.personal.unlockAccount(delegatee, "")

    //get delegatee's xG
    let delegateeVals = voters.find(v => v.address === delegatee)
    console.log(`Delegatee's xG: ${delegateeVals.xG}`)

    //get Delegator keys
    let delegatorVals = voters.find(v => v.address === delegator)

    //get delegator reconstructed keys
    let yG = [conDelegator[1][0], conDelegator[1][1]]

    //todo create 1 out of 2 ZKP
    let zkp
    if (noVotes.includes(delegatee)) {
        timeCheck = Date.now()
        zkp = await cryptoCon.methods.create1outof2ZKPNoVote(delegateeVals.xG, yG, delegatorVals.w, delegatorVals.r, delegatorVals.d, delegateeVals.x).call({from: delegatee})
        logWriter(`create1outof2ZKPNoVote LOCAL CALL duration: ${(Date.now()-timeCheck)}millis for 1 delegator\n`)
    } else {
        timeCheck = Date.now()
        zkp = await cryptoCon.methods.create1outof2ZKPYesVote(delegateeVals.xG, yG, delegatorVals.w, delegatorVals.r, delegatorVals.d, delegateeVals.x).call({from: delegatee})
        logWriter(`create1outof2ZKPYesVote LOCAL CALL duration: ${(Date.now()-timeCheck)}millis for 1 delegator\n`)
    }
    // console.log(`One out of two ZKP: ${JSON.stringify(zkp)}`)

    delegatorVals.y = [zkp[0][0], zkp[0][1]]
    delegatorVals.a1 = [zkp[0][2], zkp[0][3]]
    delegatorVals.b1 = [zkp[0][4], zkp[0][5]]
    delegatorVals.a2 = [zkp[0][6], zkp[0][7]]
    delegatorVals.b2 = [zkp[0][8], zkp[0][9]]
    delegatorVals.params = [zkp[1][0], zkp[1][1], zkp[1][2], zkp[1][3]]

    // verify 1 out of 2 ZKP
    let delegatorIndex = await voteCon.methods.addressid(delegator).call({from: delegatee})
    console.log(`Delegator index: ${delegatorIndex}`)
    timeCheck = Date.now()
    let result = await voteCon.methods.verify1outof2ZKP(delegatorVals.params, delegatorVals.y, delegatorVals.a1, delegatorVals.b1, delegatorVals.a2, delegatorVals.b2, delegatorIndex).call({from: delegatee})
    logWriter(`verify1outof2ZKP LOCAL CALL duration: ${(Date.now()-timeCheck)}millis for 1 delegator\n`)
    console.log(`ZKP verified: ${JSON.stringify(result)}\n`)

    //submit committment
    let hash = await cryptoCon.methods.commitToVote(delegatorVals.params, delegateeVals.xG, yG, delegatorVals.y, delegatorVals.a1, delegatorVals.b1, delegatorVals.a2, delegatorVals.b2).call({from: delegatee})
    timeCheck = Date.now()
    gasCheck = (await voteCon.methods.submitCommitment(hash, delegator).send({from: delegatee, gas: GAS_LIMIT})).gasUsed
    logWriter(`submitCommitment duration: ${(Date.now()-timeCheck)}millis and gas used: ${gasCheck} for 1 delegator\n`)
}

async function submitCommitments() {
    //for each voter that has NOT delegated, generate the appropriate values for commitment and commit vote
    for (const voter of voters) {
        await subComm(voter)
    }

    await web3.eth.personal.unlockAccount(admin, "")//unlock Admin account
    console.log(`Num non-delegated commitments: ${await voteCon.methods.totalcommitted().call({from: admin})}\n`)

    //for each voter that has delegated, generate the appropriate values for commitment and commit vote
    for (const delegator of Object.keys(delegations)){
        await subDelComm(delegator)
    }

    await web3.eth.personal.unlockAccount(admin, "")//unlock Admin account
    console.log(`Num total commitments: ${await voteCon.methods.totalcommitted().call({from: admin})}\n`)

    console.log(`Election now in state: ${states[await voteCon.methods.state().call({from: admin})]}\n`)
}

async function subVote(voter) {
    if (delegations[voter.address] != null) {//return if vote delegated
        return
    }
    console.log(`Voting for voter ${voter.address}`)
    await web3.eth.personal.unlockAccount(voter.address, "")

    let canVote = await voteCon.methods.submitVote(voter.params, voter.y, voter.a1, voter.b1, voter.a2, voter.b2)
    .call({from: voter.address})
    console.log(`Can vote: ${canVote}`)
    if (
        canVote
    ) {
        timeCheck = Date.now()
        gasCheck = (await voteCon.methods.submitVote(voter.params, voter.y, voter.a1, voter.b1, voter.a2, voter.b2)
        .send({from: voter.address, gas: GAS_LIMIT})).gasUsed
        logWriter(`submitVote duration: ${(Date.now()-timeCheck)}millis and gas used: ${gasCheck} for 1 voter\n`)
    } else throw `Failed to submit vote for voter ${voter.address}`

    console.log(`Voter ${voter.address} has submitted vote successfully\n`)
}

async function subDelVote(delegator) {
    console.log(`Voting on behalf of delegator ${delegator}`)

    let delegatee = delegations[delegator]
    await web3.eth.personal.unlockAccount(delegatee, "")

    let delegatorVals = voters.find(v => v.address === delegator)

    if (
        await voteCon.methods
        .submitVote(delegatorVals.params, delegatorVals.y, delegatorVals.a1, 
            delegatorVals.b1, delegatorVals.a2, delegatorVals.b2, delegator)
        .call({from: delegatee})
    ) {
        timeCheck = Date.now()
        gasCheck = (await voteCon.methods
        .submitVote(delegatorVals.params, delegatorVals.y, delegatorVals.a1, 
            delegatorVals.b1, delegatorVals.a2, delegatorVals.b2, delegator)
        .send({from: delegatee, gas: GAS_LIMIT})).gasUsed
        logWriter(`submitVote duration: ${(Date.now()-timeCheck)}millis and gas used: ${gasCheck} for 1 delegator\n`)
    } else throw `Failed to submit vote for delegator ${delegator}`

    console.log(`Delegatee ${delegatee} has submitted vote successfully for delegator ${delegator}\n`)
}

async function submitVotes() {
    //for each voter(ignoring delegators), cast vote
    for (const voter of voters) {
        await subVote(voter)
    }

    await web3.eth.personal.unlockAccount(admin, "")//unlock Admin account
    console.log(`Num non-delegated votes: ${await voteCon.methods.totalvoted().call({from: admin})}\n`)

    //for each delegator, delegatee casts vote on behalf of delegator
    for (const delegator of Object.keys(delegations)){
        await subDelVote(delegator)
    }

    await web3.eth.personal.unlockAccount(admin, "")//unlock Admin account
    console.log(`Num total votes: ${await voteCon.methods.totalvoted().call({from: admin})}\n`)
}

async function computeTally() {
    await web3.eth.personal.unlockAccount(admin, "")
    timeCheck = Date.now()
    gasCheck = (await voteCon.methods.computeTally().send({ from: admin, gas: GAS_LIMIT })).gasUsed
    logWriter(`computeTally duration: ${(Date.now()-timeCheck)}millis and gas used: ${gasCheck} for ${voters.length} voters\n`)
    let numYes = await voteCon.methods.finaltally(0).call({from: admin})
    let numTotal = await voteCon.methods.finaltally(1).call({from: admin})
    console.log(`Final tally: ${numYes} Yes votes out of ${numTotal} total votes\n`)

    console.log(`Election now in state: ${states[await voteCon.methods.state().call({from: admin})]}\n`)
}

async function resetElection() {
    await web3.eth.personal.unlockAccount(admin, "")
    let res = await voteCon.methods.deadlinePassed().call({ from: admin, gas: GAS_LIMIT })
    await voteCon.methods.deadlinePassed().send({ from: admin, gas: GAS_LIMIT })
    console.log(`Has election been reset: ${res}\n`)
    console.log(`Election now in state: ${states[await voteCon.methods.state().call({from: admin})]}\n`)
}

async function conductProtocol() {
    extractArgs()
    await readAccountInfo()
    await readConfig()
    setupConnections()

    await initElection()
    await registerVoters()

    await web3.eth.personal.unlockAccount(admin, "")//unlock Admin account
    console.log(`TOTAL REGISTERED: ${await voteCon.methods.totalregistered().call()}`)
    console.log("")

    await registerDelegations()
    console.log('Delegation completed\n')

    //Admin finishes registration
    await finishRegistration()

    //create commitments
    await submitCommitments()

    //cast votes
    await submitVotes()

    //compute tally
    await computeTally()

    //reset election
    await resetElection()
}

await conductProtocol()
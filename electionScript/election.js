import Web3 from 'web3';
import * as fs from 'fs/promises'
import * as secp256k1 from '@noble/secp256k1'
// import BigNumber from "bignumber.js"
import { BigNumber } from "@ethersproject/bignumber";

const CRYPTO_ADDR = '--cryptoAddr';
const VOTE_ADDR = '--voteAddr';
const URL = '--url';
const CRYPTO_ABI_PATH = './abis/cryptoAbi.json';
const VOTE_ABI_PATH = './abis/voteAbi.json';
const PHASE_GAP = 300;
const WEI_DEPOSIT = '5000000000000000000';

let web3;
let rawArgsList;
let flags = [URL, VOTE_ADDR, CRYPTO_ADDR];
let flagValues = ['', '', ''];
let admin;
let charity;
let addressMap = {};
let voteAbi;
let cryptoAbi;
let voteCon;
let cryptoCon;
let delegations = {};
let noVotes = [];
let voters = [];

console.log('ARGS')
console.log(process.argv)

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

async function readAccountInfo() {
    try {
        let data = await fs.readFile('accountKeys.json', { encoding: 'utf8' });
        let obj = JSON.parse(data);
        let privKeys = obj.private_keys
        console.log('ACCOUNT ADDRESS TO KEYS')
        for (const property in obj.addresses) {
            addressMap[property] = privKeys[property]
        }
        console.log(addressMap)
      } catch (err) {
        console.log('ACCOUNT KEYS ERROR')
        console.log(err);
      }
}

async function readConfig() {
    let data;
    try {
        data = (await fs.readFile('electionConfig.txt', { encoding: 'utf8' })).split(/\r?\n/);
    } catch(err) {
        console.log('ELECTION CONFIG READ ERR')
        console.log(err)
    }

    admin = data[0]
    charity = data[1]
    if (!Object.keys(addressMap).includes(admin)) throw 'SPECIFIED ADMIN NOT IN "accountKeys.json"'
    if (!Object.keys(addressMap).includes(charity)) throw 'SPECIFIED CHARITY NOT IN "accountKeys.json"'

    data[2].split(',').forEach(pair => {
        let p = pair.split(':');
        if (!Object.keys(addressMap).includes(p[0].trim())) throw `Delegator ${p[0].trim()} not in "accountKeys.json`
        if (!Object.keys(addressMap).includes(p[1].trim())) throw `Delegatee ${p[1].trim()} not in "accountKeys.json`
        if (p[1].trim() in delegations) throw `${p[1].trim()} already delegated their vote. Can't delegate to them`
        else delegations[p[0].trim()] = p[1].trim()
    })

    data[3].split(',').forEach(addr => {
        if (!Object.keys(addressMap).includes(addr)) throw 'Specified Address not in "accountKeys.json"'
        noVotes.push(addr)
    })

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
    web3 = new Web3(new Web3.providers.HttpProvider(flagValues[flags.indexOf(URL)]));

    voteCon = new web3.eth.Contract(JSON.parse(voteAbi), flagValues[flags.indexOf(VOTE_ADDR)])
    cryptoCon = new web3.eth.Contract(JSON.parse(cryptoAbi), flagValues[flags.indexOf(CRYPTO_ADDR)])
}

//Done using admin account. Set eligible voters and open registration
async function initElection() {
    let x = await web3.eth.personal.unlockAccount(admin, "")//unlock Admin account
    let now = Math.floor(Date.now()/1000)//timestamp in seconds
    
    console.log("DEPOSIT AND ELIGIBLE")
    console.log(await voteCon.methods.depositrequired().call())
    console.log(await voteCon.methods.totaleligible().call())

    voters = Object.keys(addressMap).filter(add => add != admin && add != charity).map(addr => getVoter(addr))

    //set eligible voters
    await voteCon.methods.setEligible(voters.map(v => v.address)).send({from: admin, gas: 4200000})

    console.log(await voteCon.methods.totaleligible().call())
    console.log(await voteCon.methods.depositrequired().call())

    //begin voter registration
    if (await voteCon.methods.beginSignUp('Voting question', true,
    (now + PHASE_GAP), (now + (PHASE_GAP * 2)), (now +  (PHASE_GAP * 3)), (now +  (PHASE_GAP * 4)), (now +  (PHASE_GAP * 5)), 
    WEI_DEPOSIT).call({from: admin, value: WEI_DEPOSIT})) {
        var res = await voteCon.methods.beginSignUp('Voting question', true, 
        (now + PHASE_GAP), (now + (PHASE_GAP * 2)), (now +  (PHASE_GAP * 3)), (now +  (PHASE_GAP * 4)), (now +  (PHASE_GAP * 5)), 
        WEI_DEPOSIT).send({from: admin, gas: 4200000, value: WEI_DEPOSIT});
        console.log(res)
    } else {
        throw 'Ethereum rejected deadlines set OR insuffient number of addresses set as eligible'
    }

    //deadlines from contract
    console.log("CONTRACT DEADLINES")
    console.log(await voteCon.methods.votersFinishSignupPhase().call())
    console.log(await voteCon.methods.endSignupPhase().call())
    console.log(await voteCon.methods.endCommitmentPhase().call())
    console.log(await voteCon.methods.endVotingPhase().call())
    console.log(await voteCon.methods.endRefundPhase().call())
}

async function regVoter(voter) {
    let voterLogin = await web3.eth.personal.unlockAccount(voter.address, "");
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
            var zkp = await cryptoCon.methods.createZKP(voter.x, voter.v, voter.xG).call({from: voter.address, gas: 4200000});
            break
        } catch(error) {
            console.log(`voter ${voter.address} zkp error`)
        }
    }
    let vG = [zkp[1], zkp[2], zkp[3]];

    console.log(`CREATED ZKP FOR VOTER ${voter.address}`)
    // console.log(zkp)
    // console.log(voter)

    // Lets make sure the ZKP is valid!
    let verifyZkp = await cryptoCon.methods.verifyZKP(voter.xG, zkp[0], vG).call({from: voter.address, gas: 4200000});

    console.log(`ZKP VERIFIED: ${verifyZkp}`)
    if (!verifyZkp) {
        throw `Problem with voting codes. Couldn't verify ZKP for voter ${voter.address}`
    }

    var canRegister = await voteCon.methods.register(voter.xG, vG, zkp[0]).call({from: voter.address, value: WEI_DEPOSIT});
    console.log(`CAN REGISTER: ${canRegister}`)

    // Submit voting key to the network
    if (canRegister) {
        await voteCon.methods.register(voter.xG, vG, zkp[0]).send({
            from: voter.address,
            gas: 4200000,
            value: WEI_DEPOSIT
        });
        console.log(`voter ${voter.address} is registered`)
        console.log("")
    } else {
        throw `Registration failed for voter ${voter.address}`;
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


    // while(true) {
    //     try {
    //         let voterLogin = await web3.eth.personal.unlockAccount("0x828c81e01efab5a33417c4e3d1d24b5f521ec30a", "");
    
    //         let xBytes = secp256k1.utils.randomPrivateKey()
    //         let xHex = secp256k1.utils.bytesToHex(xBytes)
    //         let x = `0x${xHex}`
    //         let xGPoint = secp256k1.Point.fromPrivateKey(xBytes)
    //         let xG = [`0x${xGPoint.x.toString(16)}`,`0x${xGPoint.y.toString(16)}`]
    //         let v = `0x${secp256k1.utils.bytesToHex(secp256k1.utils.randomPrivateKey())}`
    
    //         var zkp = await cryptoCon.methods.createZKP(x, v, xG).call({from: "0x828c81e01efab5a33417c4e3d1d24b5f521ec30a", gas: 4200000});
    //         console.log(zkp)
    //         break
    //     } catch(e) {
    //         console.log("ERROR")
    //     }
    // }

    // let voterLogin = await web3.eth.personal.unlockAccount("0x828c81e01efab5a33417c4e3d1d24b5f521ec30a", "");
    // let vZkp = await cryptoCon.methods.verifyZKP(
    //     [
    //         '0x284fa800c5250b202e80419a2c28d6409570260a577d45675a988e6a8d85509',
    //         '0x3032c0aa081ebd19d378d2c8df656ec8a49016c0bd4c988a141256331b5205ac'
    //     ],'54938706834021188046589744708636769752067740673705567682809120311266526672756',
    //     [
    //         '107687742604959417364442391574625660462039785437464552194143255727440619209578',
    //         '95038889093454847267194781371975244360638832316923818587658057514680996717959',
    //         '1'
    //     ]).call({from: "0x828c81e01efab5a33417c4e3d1d24b5f521ec30a", gas: 4200000});
    //     console.log('vZkp:')
    //     console.log(vZkp)
}

await conductProtocol()
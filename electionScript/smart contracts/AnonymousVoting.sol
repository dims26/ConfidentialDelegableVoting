// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title ECCMathLib
 *
 * Functions for working with integers, curve-points, etc.
 *
 * @author Andreas Olofsson (androlo1980@gmail.com)
 * @author Witnet Foundation
 */
library ECCMathLib {
    // From Witnet Foundation lib, previous version relied on int over/underflow
    ///https://github.com/witnet/elliptic-curve-solidity/blob/master/contracts/EllipticCurve.sol#:~:text=function-,invMod,-(uint256%20_x
    /// @dev Modular euclidean inverse of a number (mod p).
    /// @param a The number
    /// @param p The modulus
    /// @return x such that a.x = 1 (mod p)
    function invmod(uint a, uint256 p) internal pure returns (uint) {
        require(a != 0 && a != p && p != 0, "a == 0 || a == p || p == 0");
        uint x = 0;
        uint t2 = 1;
        uint r = p;
        uint t1;
        while (a != 0) {
            t1 = r / a;
            (x, t2) = (t2, addmod(x, (p - mulmod(t1, t2, p)), p));
            (r, a) = (a, r - t1 * a);
        }

        return x;
    }

    /// @dev Modular exponentiation, b^e % m
    /// Basically the same as can be found here:
    /// https://github.com/ethereum/serpent/blob/develop/examples/ecc/modexp.se
    /// @param b The base.
    /// @param e The exponent.
    /// @param m The modulus.
    /// @return r such that x = b**e (mod m)
    function expmod(uint b, uint e, uint m) internal pure returns (uint r) {
        if (b == 0)
            return 0;
        if (e == 0)
            return 1;
        if (m == 0)
            revert();
        r = 1;
        uint bit = 2 ** 255;
        assembly {
           for { } eq(iszero(bit), 0) { bit := div(bit, 16)} {
             r := mulmod(mulmod(r, r, m), exp(b, iszero(iszero(and(e, bit)))), m)
             r := mulmod(mulmod(r, r, m), exp(b, iszero(iszero(and(e, div(bit, 2))))), m)
             r := mulmod(mulmod(r, r, m), exp(b, iszero(iszero(and(e, div(bit, 4))))), m)
             r := mulmod(mulmod(r, r, m), exp(b, iszero(iszero(and(e, div(bit, 8))))), m)
           }
        }
    }

    /// @dev Converts a point (Px, Py, Pz) expressed in Jacobian coordinates to (Px", Py", 1).
    /// Mutates P.
    /// @param P The point.
    /// @param zInv The modular inverse of "Pz".
    /// @param z2Inv The square of zInv
    /// @param prime The prime modulus.
    function toZ1(uint[3] memory P, uint zInv, uint z2Inv, uint prime) internal pure {
        P[0] = mulmod(P[0], z2Inv, prime);
        P[1] = mulmod(P[1], mulmod(zInv, z2Inv, prime), prime);
        P[2] = 1;
    }

    /// @dev See _toZ1(uint[3], uint, uint).
    /// Warning: Computes a modular inverse.
    /// @param PJ The point.
    /// @param prime The prime modulus.
    function toZ1(uint[3] memory PJ, uint prime) internal pure {
        uint zInv = invmod(PJ[2], prime);
        uint zInv2 = mulmod(zInv, zInv, prime);
        PJ[0] = mulmod(PJ[0], zInv2, prime);
        PJ[1] = mulmod(PJ[1], mulmod(zInv, zInv2, prime), prime);
        PJ[2] = 1;
    }

}

library Secp256k1Lib {

    // TODO separate curve from crypto primitives?

    // Field size
    uint constant pp = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F;

    // Base point (generator) G
    uint constant Gx = 0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798;
    uint constant Gy = 0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8;

    // Order of G
    uint constant nn = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;

    // Cofactor
    // uint constant hh = 1;

    // Maximum value of s
    uint constant lowSmax = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;

    // For later
    // uint constant lambda = "0x5363ad4cc05c30e0a5261c028812645a122e22ea20816678df02967c1b23bd72";
    // uint constant beta = "0x7ae96a2b657c07106e64479eac3434e99cf0497512f58995c1396c28719501ee";

    /// @dev See Curve.onCurve
    function onCurve(uint[2] memory P) internal pure returns (bool) {
        uint p = pp;
        if (0 == P[0] || P[0] == p || 0 == P[1] || P[1] == p)
            return false;
        uint LHS = mulmod(P[1], P[1], p);
        uint RHS = addmod(mulmod(mulmod(P[0], P[0], p), P[0], p), 7, p);
        return LHS == RHS;
    }

    /// @dev See Curve.isPubKey
    function isPubKey(uint[2] memory P) internal pure returns (bool isPK) {
        isPK = onCurve(P);
    }

    /// @dev See Curve.isPubKey
    // TODO: We assume we are given affine co-ordinates for now
    function isPubKey(uint[3] memory P) internal pure returns (bool isPK) {
        uint[2] memory a_P;
        a_P[0] = P[0];
        a_P[1] = P[1];
        isPK = onCurve(a_P);
    }

    /// @dev See Curve.compress
    function compress(uint[2] calldata P) internal pure returns (uint8 yBit, uint x) {
        x = P[0];
        yBit = P[1] & 1 == 1 ? 1 : 0;
    }

    /// @dev See Curve.decompress
    function decompress(uint8 yBit, uint x) internal pure returns (uint[2] memory P) {
        uint p = pp;
        uint y2 = addmod(mulmod(x, mulmod(x, x, p), p), 7, p);
        uint y_ = ECCMathLib.expmod(y2, (p + 1) / 4, p);
        uint cmp = yBit ^ y_ & 1;
        P[0] = x;
        P[1] = (cmp == 0) ? y_ : p - y_;
    }

    // Point addition, P + Q
    // inData: Px, Py, Pz, Qx, Qy, Qz
    // outData: Rx, Ry, Rz
    function _add(uint[3] memory P, uint[3] memory Q) internal pure returns (uint[3] memory R) {
        if(P[2] == 0)
            return Q;
        if(Q[2] == 0)
            return P;
        uint p = pp;
        uint[4] memory zs; // Pz^2, Pz^3, Qz^2, Qz^3
        zs[0] = mulmod(P[2], P[2], p);
        zs[1] = mulmod(P[2], zs[0], p);
        zs[2] = mulmod(Q[2], Q[2], p);
        zs[3] = mulmod(Q[2], zs[2], p);
        uint[4] memory us = [
            mulmod(P[0], zs[2], p),
            mulmod(P[1], zs[3], p),
            mulmod(Q[0], zs[0], p),
            mulmod(Q[1], zs[1], p)
        ]; // Pu, Ps, Qu, Qs
        if (us[0] == us[2]) {
            if (us[1] != us[3])
                return R;
            else {
                return _double(P);
            }
        }
        uint h = addmod(us[2], p - us[0], p);
        uint r = addmod(us[3], p - us[1], p);
        uint h2 = mulmod(h, h, p);
        uint h3 = mulmod(h2, h, p);
        uint Rx = addmod(mulmod(r, r, p), p - h3, p);
        Rx = addmod(Rx, p - mulmod(2, mulmod(us[0], h2, p), p), p);
        R[0] = Rx;
        R[1] = mulmod(r, addmod(mulmod(us[0], h2, p), p - Rx, p), p);
        R[1] = addmod(R[1], p - mulmod(us[1], h3, p), p);
        R[2] = mulmod(h, mulmod(P[2], Q[2], p), p);
    }

    // Point addition, P + Q. P Jacobian, Q affine.
    // inData: Px, Py, Pz, Qx, Qy
    // outData: Rx, Ry, Rz
    function _addMixed(uint[3] memory P, uint[2] memory Q) internal pure returns (uint[3] memory R) {
        if(P[2] == 0)
            return [Q[0], Q[1], 1];
        if(Q[1] == 0)
            return P;
        uint p = pp;
        uint[2] memory zs; // Pz^2, Pz^3, Qz^2, Qz^3
        zs[0] = mulmod(P[2], P[2], p);
        zs[1] = mulmod(P[2], zs[0], p);
        uint[4] memory us = [
            P[0],
            P[1],
            mulmod(Q[0], zs[0], p),
            mulmod(Q[1], zs[1], p)
        ]; // Pu, Ps, Qu, Qs
        if (us[0] == us[2]) {
            if (us[1] != us[3]) {
                P[0] = 0;
                P[1] = 0;
                P[2] = 0;
                return R;
            }
            else {
                _double(P);
                return R;
            }
        }
        uint h = addmod(us[2], p - us[0], p);
        uint r = addmod(us[3], p - us[1], p);
        uint h2 = mulmod(h, h, p);
        uint h3 = mulmod(h2, h, p);
        uint Rx = addmod(mulmod(r, r, p), p - h3, p);
        Rx = addmod(Rx, p - mulmod(2, mulmod(us[0], h2, p), p), p);
        R[0] = Rx;
        R[1] = mulmod(r, addmod(mulmod(us[0], h2, p), p - Rx, p), p);
        R[1] = addmod(R[1], p - mulmod(us[1], h3, p), p);
        R[2] = mulmod(h, P[2], p);
    }

    // Same as addMixed but params are different and mutates P.
    function _addMixedM(uint[3] memory P, uint[2] memory Q) internal pure {
        if(P[1] == 0) {
            P[0] = Q[0];
            P[1] = Q[1];
            P[2] = 1;
            return;
        }
        if(Q[1] == 0)
            return;
        uint p = pp;
        uint[2] memory zs; // Pz^2, Pz^3, Qz^2, Qz^3
        zs[0] = mulmod(P[2], P[2], p);
        zs[1] = mulmod(P[2], zs[0], p);
        uint[4] memory us = [
            P[0],
            P[1],
            mulmod(Q[0], zs[0], p),
            mulmod(Q[1], zs[1], p)
        ]; // Pu, Ps, Qu, Qs
        if (us[0] == us[2]) {
            if (us[1] != us[3]) {
                P[0] = 0;
                P[1] = 0;
                P[2] = 0;
                return;
            }
            else {
                _doubleM(P);
                return;
            }
        }
        uint h = addmod(us[2], p - us[0], p);
        uint r = addmod(us[3], p - us[1], p);
        uint h2 = mulmod(h, h, p);
        uint h3 = mulmod(h2, h, p);
        uint Rx = addmod(mulmod(r, r, p), p - h3, p);
        Rx = addmod(Rx, p - mulmod(2, mulmod(us[0], h2, p), p), p);
        P[0] = Rx;
        P[1] = mulmod(r, addmod(mulmod(us[0], h2, p), p - Rx, p), p);
        P[1] = addmod(P[1], p - mulmod(us[1], h3, p), p);
        P[2] = mulmod(h, P[2], p);
    }

    // Point doubling, 2*P
    // Params: Px, Py, Pz
    // Not concerned about the 1 extra mulmod.
    function _double(uint[3] memory P) internal pure returns (uint[3] memory Q) {
        uint p = pp;
        if (P[2] == 0)
            return Q;
        uint Px = P[0];
        uint Py = P[1];
        uint Py2 = mulmod(Py, Py, p);
        uint s = mulmod(4, mulmod(Px, Py2, p), p);
        uint m = mulmod(3, mulmod(Px, Px, p), p);
        uint Qx = addmod(mulmod(m, m, p), p - addmod(s, s, p), p);
        Q[0] = Qx;
        Q[1] = addmod(mulmod(m, addmod(s, p - Qx, p), p), p - mulmod(8, mulmod(Py2, Py2, p), p), p);
        Q[2] = mulmod(2, mulmod(Py, P[2], p), p);
    }

    // Same as double but mutates P and is internal only.
    function _doubleM(uint[3] memory P) internal pure {
        uint p = pp;
        if (P[2] == 0)
            return;
        uint Px = P[0];
        uint Py = P[1];
        uint Py2 = mulmod(Py, Py, p);
        uint s = mulmod(4, mulmod(Px, Py2, p), p);
        uint m = mulmod(3, mulmod(Px, Px, p), p);
        uint PxTemp = addmod(mulmod(m, m, p), p - addmod(s, s, p), p);
        P[0] = PxTemp;
        P[1] = addmod(mulmod(m, addmod(s, p - PxTemp, p), p), p - mulmod(8, mulmod(Py2, Py2, p), p), p);
        P[2] = mulmod(2, mulmod(Py, P[2], p), p);
    }

    // From Witnet Foundation lib
    ///https://github.com/witnet/elliptic-curve-solidity/blob/master/contracts/EllipticCurve.sol#:~:text=function-,ecMul,-(
    /// @dev Multiply point (x1, y1, z1) times d in affine coordinates.
    /// @param _k scalar to multiply
    /// @param _x coordinate x of P1
    /// @param _y coordinate y of P1
    /// @param _pp the modulus
    /// @return (qx, qy) = d*P in affine coordinates
    function ecMul(
      uint256 _k,
      uint256 _x,
      uint256 _y,
      uint256 _pp) internal pure returns(uint256, uint256, uint256) {
      // Jacobian multiplication
      (uint256 x1, uint256 y1, uint256 z1) = jacMul(
        _k,
        _x,
        _y,
        1,
        0,
        _pp);
      
      return (x1, y1, z1);
    }

    //From Witnet Foundation
    ///https://github.com/witnet/elliptic-curve-solidity/blob/master/contracts/EllipticCurve.sol#:~:text=function-,jacMul,-(
    /// @dev Multiply point (x, y, z) times d.
    /// @param _d scalar to multiply
    /// @param _x coordinate x of P1
    /// @param _y coordinate y of P1
    /// @param _z coordinate z of P1
    /// @param _aa constant of curve
    /// @param _pp the modulus
    /// @return (qx, qy, qz) d*P1 in Jacobian
    function jacMul(uint256 _d, uint256 _x, uint256 _y,
      uint256 _z, uint256 _aa, uint256 _pp) internal pure returns (uint256, uint256, uint256) {
        // Early return in case that `_d == 0`
        if (_d == 0) {
          return (_x, _y, _z);
        }

        uint256 remaining = _d;
        uint256 qx = 0;
        uint256 qy = 0;
        uint256 qz = 1;

        // Double and add algorithm
        while (remaining != 0) {
          if ((remaining & 1) != 0) {
            (qx, qy, qz) = jacAdd(
              qx,
              qy,
              qz,
              _x,
              _y,
              _z,
              _pp);
          }
          remaining = remaining / 2;
          (_x, _y, _z) = jacDouble(
            _x,
            _y,
            _z,
            _aa,
            _pp);
        }
        return (qx, qy, qz);
    }

    /// From Witnet Foundation
    /// https://github.com/witnet/elliptic-curve-solidity/blob/master/contracts/EllipticCurve.sol#:~:text=function-,jacAdd,-(
    /// @dev Adds two points (x1, y1, z1) and (x2 y2, z2).
    /// @param _x1 coordinate x of P1
    /// @param _y1 coordinate y of P1
    /// @param _z1 coordinate z of P1
    /// @param _x2 coordinate x of square
    /// @param _y2 coordinate y of square
    /// @param _z2 coordinate z of square
    /// @param _pp the modulus
    /// @return (qx, qy, qz) P1+square in Jacobian
    function jacAdd(uint256 _x1, uint256 _y1, uint256 _z1,
      uint256 _x2, uint256 _y2, uint256 _z2, uint256 _pp) internal pure returns (uint256, uint256, uint256) {
        if (_x1==0 && _y1==0)
          return (_x2, _y2, _z2);
        if (_x2==0 && _y2==0)
          return (_x1, _y1, _z1);

        // We follow the equations described in https://pdfs.semanticscholar.org/5c64/29952e08025a9649c2b0ba32518e9a7fb5c2.pdf Section 5
        uint[4] memory zs; // z1^2, z1^3, z2^2, z2^3
        zs[0] = mulmod(_z1, _z1, _pp);
        zs[1] = mulmod(_z1, zs[0], _pp);
        zs[2] = mulmod(_z2, _z2, _pp);
        zs[3] = mulmod(_z2, zs[2], _pp);

        // u1, s1, u2, s2
        zs = [
          mulmod(_x1, zs[2], _pp),
          mulmod(_y1, zs[3], _pp),
          mulmod(_x2, zs[0], _pp),
          mulmod(_y2, zs[1], _pp)
        ];

        // In case of zs[0] == zs[2] && zs[1] == zs[3], double function should be used
        require(zs[0] != zs[2] || zs[1] != zs[3], "Use jacDouble function instead");

        uint[4] memory hr;
        //h
        hr[0] = addmod(zs[2], _pp - zs[0], _pp);
        //r
        hr[1] = addmod(zs[3], _pp - zs[1], _pp);
        //h^2
        hr[2] = mulmod(hr[0], hr[0], _pp);
        // h^3
        hr[3] = mulmod(hr[2], hr[0], _pp);
        // qx = -h^3  -2u1h^2+r^2
        uint256 qx = addmod(mulmod(hr[1], hr[1], _pp), _pp - hr[3], _pp);
        qx = addmod(qx, _pp - mulmod(2, mulmod(zs[0], hr[2], _pp), _pp), _pp);
        // qy = -s1*z1*h^3+r(u1*h^2 -x^3)
        uint256 qy = mulmod(hr[1], addmod(mulmod(zs[0], hr[2], _pp), _pp - qx, _pp), _pp);
        qy = addmod(qy, _pp - mulmod(zs[1], hr[3], _pp), _pp);
        // qz = h*z1*z2
        uint256 qz = mulmod(hr[0], mulmod(_z1, _z2, _pp), _pp);
        return(qx, qy, qz);
    }

    /// From Witnet Foundation
    /// https://github.com/witnet/elliptic-curve-solidity/blob/master/contracts/EllipticCurve.sol#:~:text=function-,jacDouble,-(
    /// @dev Doubles a points (x, y, z).
    /// @param _x coordinate x of P1
    /// @param _y coordinate y of P1
    /// @param _z coordinate z of P1
    /// @param _aa the a scalar in the curve equation
    /// @param _pp the modulus
    /// @return (qx, qy, qz) 2P in Jacobian
    function jacDouble(uint256 _x, uint256 _y, uint256 _z,
      uint256 _aa, uint256 _pp) internal pure returns (uint256, uint256, uint256) {
        if (_z == 0)
          return (_x, _y, _z);

        // We follow the equations described in https://pdfs.semanticscholar.org/5c64/29952e08025a9649c2b0ba32518e9a7fb5c2.pdf Section 5
        // Note: there is a bug in the paper regarding the m parameter, M=3*(x1^2)+a*(z1^4)
        // x, y, z at this point represent the squares of _x, _y, _z
        uint256 x = mulmod(_x, _x, _pp); //x1^2
        uint256 y = mulmod(_y, _y, _pp); //y1^2
        uint256 z = mulmod(_z, _z, _pp); //z1^2

        // s
        uint s = mulmod(4, mulmod(_x, y, _pp), _pp);
        // m
        uint m = addmod(mulmod(3, x, _pp), mulmod(_aa, mulmod(z, z, _pp), _pp), _pp);

        // x, y, z at this point will be reassigned and rather represent qx, qy, qz from the paper
        // This allows to reduce the gas cost and stack footprint of the algorithm
        // qx
        x = addmod(mulmod(m, m, _pp), _pp - addmod(s, s, _pp), _pp);
        // qy = -8*y1^4 + M(S-T)
        y = addmod(mulmod(m, addmod(s, _pp - x, _pp), _pp), _pp - mulmod(8, mulmod(y, y, _pp), _pp), _pp);
        // qz = 2*y1*z1
        z = mulmod(2, mulmod(_y, _z, _pp), _pp);

        return (x, y, z);
    }
}


contract owned {
    address public owner;

    /* Initialise contract creator as owner */
    constructor() {
        owner = msg.sender;
    }

    /* Function to dictate that only the designated owner can call a function */
	  modifier onlyOwner {
        if(owner != msg.sender) revert();
        _;
    }

    /* Transfer ownership of this contract to someone else */
    function transferOwnership(address newOwner) public onlyOwner() {
        owner = newOwner;
    }
}

/*
 * @title AnonymousVoting
 *  Open Vote Network
 *  A self-talling protocol that supports voter privacy.
 * Portions of the project have been copied from https://github.com/stonecoldpat/anonymousvoting/blob/master/AnonymousVoting.sol
 *
 *  Author: Patrick McCorry
 *  Author: Dimeji Sebiotimo
 */
contract AnonymousVoting is owned {
  // Modulus for public keys
  uint constant pp = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F;

  // Base point (generator) G
  uint constant Gx = 0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798;
  uint constant Gy = 0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8;

  // Modulus for private keys (sub-group)
  uint constant nn = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;

  uint[2] G;

  //Every address has an index
  //This makes looping in the program easier.
  address[] public addresses;
  mapping (address => uint) public addressid; // Address to Counter
  mapping (uint => Voter) public voters;
  mapping (address => bool) public eligible; // White list of addresses allowed to vote
  mapping (address => bool) public registered; // Address registered?
  mapping (address => bool) public votecast; // Address voted?
  mapping (address => bool) public commitment; // Have we received their commitment?
  mapping (address => uint) public refunds; // Have we received their commitment?
  mapping (address => address) public delegations; //Has voter delegated their vote (delegators -> delegatees)
  mapping (address => uint[]) public delegators; //Who has delegated to this address (delegatees -> delegators[])

  struct Voter {
      address addr;
      uint[2] registeredkey;
      uint[2] reconstructedkey;
      bytes32 commitment;
      uint[2] vote;
  }

  // Work around function to fetch details about a voter
  function getVoter() public view returns (uint[2] memory _registeredkey, uint[2] memory _reconstructedkey, bytes32 _commitment){
      uint index = addressid[msg.sender];
      _registeredkey = voters[index].registeredkey;
      _reconstructedkey = voters[index].reconstructedkey;
      _commitment = voters[index].commitment;
  }

  // List of timers that each phase MUST end by an explicit time in UNIX timestamp.
  // Ethereum works in SECONDS. Not milliseconds.
  uint public votersFinishSignupPhase; // Election Authority to transition to next phase.
  uint public endSignupPhase; // Election Authority does not transition to next phase by this time.
  uint public endCommitmentPhase; // Voters have not sent their commitments in by this time.
  uint public endVotingPhase; // Voters have not submitted their vote by this stage.
  uint public endRefundPhase; // Voters must claim their refund by this stage.

  uint public totalregistered; //Total number of participants that have submited a voting key
  uint public totaleligible; //Total number of participants that are white listed as eligible
  uint public totalcommitted; //Total number of participants that have submitted commitments
  uint public totalvoted; //Total number of participants that have submitted votes
  uint public totalrefunded;//Total number of participants that have been refunded
  uint public totaltorefund;//Total amount to be refunded???

  string public question;
  uint[2] public finaltally; // Final tally
  bool public commitmentphase; // OPTIONAL phase.
  uint public depositrequired;
  uint public gap; // Minimum amount of time between time stamps.
  address public charity;

  uint public lostdeposit; // This money is collected from non active voters...

  enum State { SETUP, SIGNUP, COMMITMENT, VOTE, FINISHED }
  State public state;

  modifier inState(State s) {
    if(state != s) {
        revert();
    }
    _;
  }

  // 2 round anonymous voting protocol
  constructor(uint _gap, address _charity) {
    G[0] = Gx;
    G[1] = Gy;
    state = State.SETUP;
    question = "No question set";
    gap = _gap; // Minimum gap period between stages
    charity = _charity;
  }

  // Owner of contract sets a whitelist of addresses that are eligible to vote.
  function setEligible(address[] calldata addr) external onlyOwner {
    // Sign up the addresses
    for(uint i=0; i<addr.length; i++) {

      if(!eligible[addr[i]]) {
        eligible[addr[i]] = true;
        addresses.push(addr[i]);
        totaleligible += 1;
      }
    }

    // New voter limit, if we exceed this, revert
    if(totaleligible > 150) {
      revert("maximum of 150 voters");
    }
  }

  // Owner of contract declares that eligible addresses begin round 1 of the protocol
  function beginSignUp(string calldata _question, bool enableCommitmentPhase, uint _votersFinishSignupPhase, 
    uint _endSignupPhase, uint _endCommitmentPhase, uint _endVotingPhase, uint _endRefundPhase, 
    uint _depositrequired) inState(State.SETUP) external onlyOwner payable returns (bool){

    // We have lots of timers. let's explain each one
    // _votersFinishSignupPhase - Voters should be signed up before this timer

    // Voter is REFUNDED IF any of the timers expire:
    // _endSignUpPhase - Election Authority never finished sign up phase
    // _endCommitmentPhase - One or more voters did not send their commitments in time(Cos of fault intolerant voting)
    // _endVotingPhase - One or more voters did not send their votes in time
    // _endRefundPhase - Provide time for voters to get their money back.(Standard refund time if voting completes)

    // Represented in UNIX time...
    // Make sure 3 people are at least eligible to vote..
    // Deposit is non negative integer
    if(_votersFinishSignupPhase > 0 + gap && //enforce min gap time
     addresses.length >= 3 && //3 or more voters
      _depositrequired >= 0 //non negative deposit
      ) {

        // Ensure each time phase finishes in the future...
        // Ensure there is a gap of 'x time' between each phase.
        if(_endSignupPhase-gap < _votersFinishSignupPhase) {
          return false;
        }

        // We need to check Commitment timestamps if phase is enabled.
        if(enableCommitmentPhase) {

          // Make sure there is a gap between 'end of registration' and 'end of commitment' phases.
          if(_endCommitmentPhase-gap < _endSignupPhase) {
            return false;
          }

          // Make sure there is a gap between 'end of commitment' and 'end of vote' phases.
          if(_endVotingPhase-gap < _endCommitmentPhase) {
            return false;
          }

        } else {

          // We have no commitment phase.
          // Make sure there is a gap between 'end of registration' and 'end of vote' phases.
          if(_endVotingPhase-gap < _endSignupPhase) {
            return false;
          }
        }

        // Provide time for people to get a refund once the voting phase has ended.
        if(_endRefundPhase-gap < _endVotingPhase) {
          return false;
        }


      // Require Election Authority to deposit ether.
      if(msg.value  != _depositrequired) {
        return false;
      }

      // Store the election authority's deposit
      // Note: This deposit is only lost if the
      // election authority does not begin the election
      // or call the tally function before the timers expire.
      refunds[msg.sender] = msg.value;

      // All time stamps are reasonable.
      // We can now begin the signup phase.
      state = State.SIGNUP;

      // All timestamps should be in UNIX..
      votersFinishSignupPhase = _votersFinishSignupPhase;
      endSignupPhase = _endSignupPhase;
      endCommitmentPhase = _endCommitmentPhase;
      endVotingPhase = _endVotingPhase;
      endRefundPhase = _endRefundPhase;
      question = _question;
      commitmentphase = enableCommitmentPhase;
      depositrequired = _depositrequired; // Deposit required from all voters

      return true;
    }

    return false;
  }

  // This function determines if one of the deadlines have been missed
  // If a deadline has been missed - then we finish the election,
  // and allocate refunds to the correct people depending on the situation.
  function deadlinePassed() external returns (bool){

      uint refund = 0;

      // Has the Election Authority missed the signup deadline?
      // Election Authority will forfeit their deposit.
      if(state == State.SIGNUP && block.timestamp > endSignupPhase) {

         // Nothing to do. All voters are refunded.
         state = State.FINISHED;
         totaltorefund = totalregistered;

         // Election Authority forfeits his deposit...
         // If 3 or more voters had signed up...
         if(addresses.length >= 3) {
           // Election Authority forfeits deposit
           refund = refunds[owner];
           refunds[owner] = 0;
           lostdeposit = lostdeposit + refund;

         }
         return true;
      }

      // Has a voter failed to send their commitment?
      // Election Authority DOES NOT forgeit his deposit.
      if(state == State.COMMITMENT && block.timestamp > endCommitmentPhase) {

         // Check which voters have not sent their commitment
         for(uint i=0; i<totalregistered; i++) {

            // Voters forfeit their deposit if failed to send a commitment
            if(!commitment[voters[i].addr]) {
               refund = refunds[voters[i].addr];
               refunds[voters[i].addr] = 0;
               lostdeposit = lostdeposit + refund;
            } else {

              // We will need to refund this person.
              totaltorefund = totaltorefund + 1;
            }
         }

         state = State.FINISHED;
         return true;
      }

      // Has a voter failed to send in their vote?
      // Eletion Authority does NOT forfeit his deposit.
      if(state == State.VOTE && block.timestamp > endVotingPhase) {

         // Check which voters have not cast their vote
         for(uint i=0; i<totalregistered; i++) {

            // Voter forfeits deposit if they have not voted.
            if(!votecast[voters[i].addr]) {
              refund = refunds[voters[i].addr];
              refunds[voters[i].addr] = 0;
              lostdeposit = lostdeposit + refund;
            } else {
              // Lets make sure refund has not already been issued...
              if(refunds[voters[i].addr] > 0) {
                // We will need to refund this person.
                totaltorefund = totaltorefund + 1;
              }
            }
         }

         state = State.FINISHED;
         return true;
      }

      // Has the deadline passed for voters to claim their refund?
      // Only owner can call. Owner must be refunded (or forfeited).
      // Refund period is over or everyone has already been refunded.
      if(state == State.FINISHED && msg.sender == owner && refunds[owner] == 0 && (block.timestamp > endRefundPhase || totaltorefund == totalrefunded)) {

         // Collect all unclaimed refunds. We will send it to charity.
         for(uint i=0; i<totalregistered; i++) {
           refund = refunds[voters[i].addr];
           refunds[voters[i].addr] = 0;
           lostdeposit = lostdeposit + refund;
         }

         uint[2] memory empty;

         for(uint i=0; i<addresses.length; i++) {
            address addr = addresses[i];
            eligible[addr] = false; // No longer eligible
            registered[addr] = false; // Remove voting registration
            voters[i] = Voter({addr: address(0), registeredkey: empty, reconstructedkey: empty, vote: empty, commitment: 0});
            addressid[addr] = 0; // Remove index
            votecast[addr] = false; // Remove that vote was cast
            commitment[addr] = false;
            if (delegations[addr] != address(0x00)){//remove mapping to delegatee
              delete delegations[addr];
            }
            if (delegators[addr].length > 0) {//remove mapping to all its delegators
              delete delegators[addr];
            }
         }

         // Reset timers.
         votersFinishSignupPhase = 0;
         endSignupPhase = 0;
         endCommitmentPhase = 0;
         endVotingPhase = 0;
         endRefundPhase = 0;

         delete addresses;

         // Keep track of voter activity
         totalregistered = 0;
         totaleligible = 0;
         totalcommitted = 0;
         totalvoted = 0;

         // General values that need reset
         question = "No question set";
         finaltally[0] = 0;
         finaltally[1] = 0;
         commitmentphase = false;
         depositrequired = 0;
         totalrefunded = 0;
         totaltorefund = 0;

         state = State.SETUP;
         return true;
      }

      // No deadlines have passed...
      return false;
  }

  // Called by participants to register their voting public key
  // Participant mut be eligible, and can only register the first key sent.
  function register(uint[2] calldata xG, uint[3] calldata vG, uint r) inState(State.SIGNUP) external payable returns (bool) {

     // HARD DEADLINE
     if(block.timestamp > votersFinishSignupPhase) {
       revert('Past registration deadline');
     }

    // Make sure the ether being deposited matches what we expect.
    if(msg.value != depositrequired) {
      return false;
    }

    // Only white-listed addresses can vote
    if(eligible[msg.sender]) {
        if(verifyZKP(xG,r,vG) && !registered[msg.sender]) {

            // Store deposit
            refunds[msg.sender] = msg.value;

            // Update voter's registration
            uint[2] memory empty;
            addressid[msg.sender] = totalregistered;
            voters[totalregistered] = Voter(
              {
                addr: msg.sender, 
                registeredkey: xG, 
                reconstructedkey: empty, 
                vote: empty, 
                commitment: 0
              }
            );
            registered[msg.sender] = true;
            totalregistered += 1;

            return true;
        } revert("Not verified or registered");
    }

    return false;
  }

  // Delegate a voter's vote to another voter. Can only be called in signup phase
  function delegate(address _delegatee) inState(State.SIGNUP) external returns (bool) {
    // HARD DEADLINE
    require(block.timestamp < votersFinishSignupPhase, "Past signup deadline");
    require(registered[msg.sender] && registered[_delegatee] && delegations[_delegatee] == address(0x0),
      "Delegator and delegatee must be registered, and delegatee must not have delegated their vote");

    // delegator and delegatee are both registered, and delegatee has not already delegated their own vote
    delegations[msg.sender] = _delegatee;
    delegators[_delegatee].push(addressid[msg.sender]);

    return true;
  }

  function doNothing() external pure returns (bool) {
    return true;
  }


  // Timer has expired - we want to start computing the reconstructed keys for all voters
  //Afterwards, we move to next phase (commitment or voting)
  function finishRegistrationPhase() inState(State.SIGNUP) external onlyOwner returns(bool) {

      // Make sure at least 3 people have signed up...
      if(totalregistered < 3) {
        return false;
      }

      // We can only compute the public keys once participants
      // have been given an opportunity to register their
      // voting public key.
      if(block.timestamp < votersFinishSignupPhase) {
        return false;
      }

      // Election Authority has a deadline to begin election
      if(block.timestamp > endSignupPhase) {
        return false;
      }

      uint[2] memory temp;
      uint[3] memory yG;
      uint[3] memory beforei;
      uint[3] memory afteri;

      // Step 1 is to compute the index 0 reconstructed key i.e Y subscript 0
      if(delegations[voters[1].addr] == address(0x0)) {
        afteri[0] = voters[1].registeredkey[0];
        afteri[1] = voters[1].registeredkey[1];
        afteri[2] = 1;
      } else {
        //if voter at index 1 has delegated their vote, use the key of the delegatee
        uint delegateIndex = addressid[delegations[voters[1].addr]];
        afteri[0] = voters[delegateIndex].registeredkey[0];
        afteri[1] = voters[delegateIndex].registeredkey[1];
        afteri[2] = 1;
      }

      for(uint i=2; i<totalregistered; i++) {
        if (delegations[voters[i].addr] == address(0x0)) {
          Secp256k1Lib._addMixedM(afteri, voters[i].registeredkey);
        } else {
          //If voter at index i has delegated their vote, use the key of the delegatee
          uint delegateIndex = addressid[delegations[voters[i].addr]];
          Secp256k1Lib._addMixedM(afteri, voters[delegateIndex].registeredkey);
        }
      }

      ECCMathLib.toZ1(afteri,pp);
      voters[0].reconstructedkey[0] = afteri[0];
      voters[0].reconstructedkey[1] = pp - afteri[1];

      // Step 2 is to add to beforei, and subtract from afteri. Setting the reconstructed keys for every i > 0
     for(uint i=1; i<totalregistered; i++) {

       if(i==1) {
        if (delegations[voters[0].addr] == address(0x0)) {
          beforei[0] = voters[0].registeredkey[0];
          beforei[1] = voters[0].registeredkey[1];
          beforei[2] = 1;
        } else {
          //If voter at index has delegated their vote, use the key of the delegatee
          uint delegateIndex = addressid[delegations[voters[0].addr]];
          beforei[0] = voters[delegateIndex].registeredkey[0];
          beforei[1] = voters[delegateIndex].registeredkey[1];
          beforei[2] = 1;
        }
       } else {
        if (delegations[voters[i-1].addr] == address(0x0)) {
          Secp256k1Lib._addMixedM(beforei, voters[i-1].registeredkey);
        } else {
          //If voter at index has delegated their vote, use the key of the delegatee
          uint delegateIndex = addressid[delegations[voters[i-1].addr]];
          Secp256k1Lib._addMixedM(beforei, voters[delegateIndex].registeredkey);
        }
       }

       // If we have reached the end... just store beforei
       // Otherwise, we need to compute a key.
       // Counting from 0 to n-1...
       if(i==(totalregistered-1)) {
         ECCMathLib.toZ1(beforei,pp);
         voters[i].reconstructedkey[0] = beforei[0];
         voters[i].reconstructedkey[1] = beforei[1];
       } else {

          // Subtract 'i' from afteri
          if (delegations[voters[i].addr] == address(0x0)){
            temp[0] = voters[i].registeredkey[0];
            temp[1] = pp - voters[i].registeredkey[1];
          } else {
            //If voter at index has delegated their vote, use the key of the delegatee
            uint delegateIndex = addressid[delegations[voters[i].addr]];
            temp[0] = voters[delegateIndex].registeredkey[0];
            temp[1] = pp - voters[delegateIndex].registeredkey[1];
          }

          // Grab negation of afteri (did not seem to work with Jacob co-ordinates)
          Secp256k1Lib._addMixedM(afteri,temp);
          ECCMathLib.toZ1(afteri,pp);

          temp[0] = afteri[0];
          temp[1] = pp - afteri[1];

          // Now we do beforei - afteri...
          yG = Secp256k1Lib._addMixed(beforei, temp);

          ECCMathLib.toZ1(yG,pp);

          voters[i].reconstructedkey[0] = yG[0];
          voters[i].reconstructedkey[1] = yG[1];
       }
     }

      // We have computed each voter's special voting key.
      // Now we either enter the commitment phase (option) or voting phase.
      if(commitmentphase) {
        state = State.COMMITMENT;
      } else {
        state = State.VOTE;
      }
      return true;
  }

  /*
   * All voters submit the hash of their vote.
   */
  function submitCommitment(bytes32 h) external inState(State.COMMITMENT) {

     //All voters have a deadline to send their commitment
     require(block.timestamp < endCommitmentPhase, "Commitment phase closed");
     require(delegations[msg.sender] == address(0x00), "Can't be called after delegating vote");

    if(!commitment[msg.sender]) {
        commitment[msg.sender] = true;
        uint index = addressid[msg.sender];
        voters[index].commitment = h;
        totalcommitted = totalcommitted + 1;

        // Once we have recorded all commitments... let voters vote!
        if(totalcommitted == totalregistered) {
          state = State.VOTE;
        }
    }
  }

  //Delegatee submits commitment on behalf of delegator
  function submitCommitment(bytes32 h, address delegator) external inState(State.COMMITMENT) {
    //All voters have a deadline to send their commitment
     require(block.timestamp < endCommitmentPhase, "Commitment phase closed");
     require(delegations[delegator] == msg.sender, "You haven't been delegated to vote on their behalf");

     if(!commitment[delegator]) {
      commitment[delegator] = true;
      uint index = addressid[delegator];
      voters[index].commitment = h;
      totalcommitted = totalcommitted + 1;

      // Once we have recorded all commitments... let voters vote!
      if(totalcommitted == totalregistered) {
        state = State.VOTE;
      }
     }
  }

  // Given the 1 out of 2 ZKP, and delegator address submitted by delegatee - record the users vote!
  function submitVote(uint[4] calldata params, uint[2] calldata y, uint[2] calldata a1,
    uint[2] calldata b1, uint[2] calldata a2, uint[2] calldata b2, address delegator) external inState(State.VOTE) returns (bool) {

     //All voters have a deadline to vote
     require(block.timestamp < endVotingPhase, "Voting phase closed");
     require(delegations[delegator] == msg.sender, "You haven't been delegated to vote on their behalf");

     uint c = addressid[delegator];

     // Make sure the sender can vote, and hasn't already voted.
     if(registered[delegator] && !votecast[delegator]) {

       // OPTIONAL Phase: Voters need to commit to their vote in advance.
       // Time to verify if this vote matches the voter's previous commitment.
       if(commitmentphase) {

         // Voter has previously committed to the entire zero knowledge proof...
         bytes32 h = keccak256(abi.encodePacked(msg.sender, params, voters[addressid[delegations[delegator]]].registeredkey, voters[c].reconstructedkey, y, a1, b1, a2, b2));

         // No point verifying the ZKP if it doesn't match the voter's commitment.
         if(voters[c].commitment != h) {
           return false;
         }
       }

       // Verify the ZKP for the vote being cast
       if(verify1outof2ZKP(params, y, a1, b1, a2, b2, c)) {
         voters[c].vote[0] = y[0];
         voters[c].vote[1] = y[1];

         votecast[delegator] = true;

         totalvoted += 1;

         // Refund the sender their ether..
         // Voter has finished their part of the protocol...
         uint refund = refunds[delegator];//send delegator's refund to delegatee (INCENTIVE)
         refunds[delegator] = 0;

         // We can still fail... Safety first.
         // If failed... voter can call withdrawRefund()
         // to collect their money once the election has finished.
         if (!payable(msg.sender).send(refund)) {
            refunds[delegator] = refund;
         }

         return true;
       }
     }

     // Either vote has already been cast, or ZKP verification failed.
     return false;
  }

  // Given the 1 out of 2 ZKP - record the users vote!
  function submitVote(uint[4] calldata params, uint[2] calldata y, uint[2] calldata a1,
    uint[2] calldata b1, uint[2] calldata a2, uint[2] calldata b2) external inState(State.VOTE) returns (bool) {

     //All voters have a deadline to send their vote
     require(block.timestamp < endVotingPhase, "Voting phase closed");
     require(delegations[msg.sender] == address(0x00), "Can't be called after delegating vote");

     uint c = addressid[msg.sender];

     // Make sure the sender can vote, and hasn't already voted.
     if(registered[msg.sender] && !votecast[msg.sender]) {

       // OPTIONAL Phase: Voters need to commit to their vote in advance.
       // Time to verify if this vote matches the voter's previous commitment.
       if(commitmentphase) {

         // Voter has previously committed to the entire zero knowledge proof...
         bytes32 h = keccak256(abi.encodePacked(msg.sender, params, voters[c].registeredkey, voters[c].reconstructedkey, y, a1, b1, a2, b2));

         // No point verifying the ZKP if it doesn't match the voter's commitment.
         if(voters[c].commitment != h) {
           return false;
         }
       }

       // Verify the ZKP for the vote being cast
       if(verify1outof2ZKP(params, y, a1, b1, a2, b2, c)) {
         voters[c].vote[0] = y[0];
         voters[c].vote[1] = y[1];

         votecast[msg.sender] = true;

         totalvoted += 1;

         // Refund the sender their ether..
         // Voter has finished their part of the protocol...
         uint refund = refunds[msg.sender];
         refunds[msg.sender] = 0;

         // We can still fail... Safety first.
         // If failed... voter can call withdrawRefund()
         // to collect their money once the election has finished.
         if (!payable(msg.sender).send(refund)) {
            refunds[msg.sender] = refund;
         }

         return true;
       }
     }

     // Either vote has already been cast, or ZKP verification failed.
     return false;
  }

  // Assuming all votes have been submitted. We can expose the tally.
  // We assume Election Authority performs this function but It could be anyone.
  // Election Authority gets deposit upon tallying.
  // TODO: Anyone can do this function. Perhaps remove refund code - and force Election Authority
  // to explicit withdraw it? Election cannot reset until he is refunded - so that should be OK
  // todo Move election authority refund to its own method and update ABI. Plan is for anybody to call computeTally
  function computeTally() external inState(State.VOTE) onlyOwner {

     uint[3] memory temp;
     uint[2] memory vote;
     uint refund;

     // Sum all votes
     for(uint i=0; i<totalregistered; i++) {

         // Confirm all votes have been cast...
         if(!votecast[voters[i].addr]) {
            revert("All voters have not been cast");
         }

         vote = voters[i].vote;

         if(i==0) {
           temp[0] = vote[0];
           temp[1] = vote[1];
           temp[2] = 1;
         } else {
             Secp256k1Lib._addMixedM(temp, vote);
         }
     }

     // All votes have been accounted for...
     // Get tally, and change state to 'Finished'
     state = State.FINISHED;

     // All voters should already be refunded!
     for(uint i = 0; i<totalregistered; i++) {

       // Sanity check.. make sure refunds have been issued..
       if(refunds[voters[i].addr] > 0) {
         totaltorefund = totaltorefund + 1;
       }
     }

     // Each vote is represented by a G.
     // If there are no votes... then it is 0G = (0,0)...
     if(temp[0] == 0) {
       finaltally[0] = 0;
       finaltally[1] = totalregistered;

       // Election Authority is responsible for calling this....
       // He should not fail his own refund...
       // Make sure tally is computed before refunding...
       // TODO: Move election authority refund to its own method and update ABI. Plan is for anybody to call computeTally
       // todo See if withdrawRefund() is viable for this
       refund = refunds[msg.sender];
       refunds[msg.sender] = 0;

       if (!payable(msg.sender).send(refund)) {
          refunds[msg.sender] = refund;
       }
       return;
     } else {

       // There must be a vote. So lets
       // start adding 'G' until we
       // find the result.
       ECCMathLib.toZ1(temp,pp);
       uint[3] memory tempG;
       tempG[0] = G[0];
       tempG[1] = G[1];
       tempG[2] = 1;

       // Start adding 'G' and looking for a match i.e exhaustive search. 
      for(uint i=1; i <= totalregistered; i++) {
        if(temp[0] == tempG[0]) {
          finaltally[0] = i;
          finaltally[1] = totalregistered;
          // Election Authority is responsible for calling this....
          // He should not fail his own refund...
          // Make sure tally is computed before refunding...
          refund = refunds[msg.sender];
          refunds[msg.sender] = 0;
          if (!payable(msg.sender).send(refund)) {
              refunds[msg.sender] = refund;
          }
          return;
        }

        //Don't run addition on the last loop
        if(i != totalregistered) {
          Secp256k1Lib._addMixedM(tempG, G);
          ECCMathLib.toZ1(tempG,pp);
        }
      }

         // Something bad happened. We should never get here....
         // This represents an error message... best telling people
         // As we cannot recover from it anyway.
         finaltally[0] = 0;
         finaltally[1] = 0;

         // Election Authority is responsible for calling this....
         // He should not fail his own refund...
         refund = refunds[msg.sender];
         refunds[msg.sender] = 0;

         if (!payable(msg.sender).send(refund)) {
            refunds[msg.sender] = refund;
         }
         return;
      }
  }

  // There are two reasons why we might be in a finished state
  // 1. The tally has been computed
  // 2. A deadline has been missed.
  // In the former; everyone gets a refund. In the latter; only active participants get a refund
  // We can assume if the deadline has been missed - then refunds has ALREADY been updated to
  // take that into account. (a transaction is required to indicate a deadline has been missed
  // and in that transaction - we can penalise the non-active participants. lazy sods!)-LOL
  function withdrawRefund() external inState(State.FINISHED){

    uint refund = refunds[msg.sender];
    refunds[msg.sender] = 0;

    address delegatee = delegations[msg.sender];
    // If you delegated and the vote has been cast
    if (delegatee != address(0x00) && votecast[msg.sender]) {
      //Pay Delegatee for their hardwork
      if (!payable(delegatee).send(refund)) {
       refunds[msg.sender] = refund;//Payment failed
      } else {
        // Tell everyone we have issued the refund.
        // Owner is not included in refund counter.
        if(msg.sender != owner) {
          totalrefunded = totalrefunded + 1;
        }
      }
    } else if (!payable(msg.sender).send(refund)) {// All other cases, try to refund
       refunds[msg.sender] = refund;// Refund fails
    } else {
      // Tell everyone we have issued the refund.
      // Owner is not included in refund counter.
      // This is OK - we cannot reset election until
      // the owner has been refunded...
      // Counter only concerns voters!
      if(msg.sender != owner) {
         totalrefunded = totalrefunded + 1;
      }
    }
  }

  //Delegatee can attempt to withdraw their incentive after voting on behalf of delegator
  function withdrawRefund(address delegator) external inState(State.FINISHED){

    require(delegations[delegator] == msg.sender, "Must have been delegated to by delegator");
    require(votecast[delegator], "Vote for delegator must have been cast");

    uint refund = refunds[delegator];
    refunds[delegator] = 0;

    if (!payable(msg.sender).send(refund)) {// All other cases, try to refund
       refunds[delegator] = refund;// If refund fails
    } else {
      // Tell everyone we have issued the refund.
      totalrefunded = totalrefunded + 1;
    }
  }

  

  // Send the lost deposits to a charity. Anyone can call it.
  // Lost Deposit increments for each failed election. It is only
  // reset upon sending to the charity!
  function sendToCharity() external {

    // Only send this money to the owner
    uint profit = lostdeposit;
    lostdeposit = 0;

    // Try to send money
    if(!payable(charity).send(profit)) {

      // We failed to send the money. Record it again.
      lostdeposit = profit;
    }
  }

  // Parameters xG, r where r = v - xc, and vG.
  // Verify that vG = rG + xcG!
  function verifyZKP(uint[2] memory xG, uint256 r, uint[3] memory vG) private view returns (bool){

      // Check both keys are on the curve.
      if(!Secp256k1Lib.isPubKey(xG) || !Secp256k1Lib.isPubKey(vG)) {
        return false; //Must be on the curve!
      }

      // Get c = H(g, g^{x}, g^{v});
      bytes32 b_c = sha256(abi.encodePacked(msg.sender, Gx, Gy, xG, vG));
      uint c = uint(b_c);

      uint x;
      uint y;
      uint z;
      (x,y,z) = Secp256k1Lib.ecMul(r, G[0], G[1], pp);
      // Get g^{r}, and g^{xc}
      uint[3] memory rG = [x, y, z];
      (x,y,z) = Secp256k1Lib.ecMul(c, xG[0], xG[1], pp);
      uint[3] memory xcG = [x, y, z];

      // Add both points together
      uint[3] memory rGxcG = Secp256k1Lib._add(rG,xcG);

      // Convert to Affine Co-ordinates
      ECCMathLib.toZ1(rGxcG, pp);

      // Verify. Do they match?
      if(rGxcG[0] == vG[0] && rGxcG[1] == vG[1]) {
         return true;
      } else {
         return false;
      }
  }

  struct mulRes {
    uint k;
    uint l;
    uint m;
    uint c;
    uint[2] temp1;
    uint[3] temp2;
    uint[3] temp3;
  }

  // We verify that the ZKP is of 0 or 1.
  function verify1outof2ZKP(uint[4] calldata params, uint[2] calldata y, uint[2] calldata a1,
    uint[2] calldata b1, uint[2] calldata a2, uint[2] calldata b2, uint i) public view returns (bool) {
      mulRes memory mR;

      // We already have them stored...
      // TODO: Decide if this should be in SubmitVote or here...
      uint[2] memory yG = voters[i].reconstructedkey;
      uint[2] memory xG;
      if (delegations[voters[i].addr] == address(0x00)) {
        xG = voters[i].registeredkey;
      } else {
        // Delegatee is msg.sender
        xG = voters[addressid[delegations[voters[i].addr]]].registeredkey;
      }

      // Make sure we are only dealing with valid public keys!
      if(!Secp256k1Lib.isPubKey(xG) || !Secp256k1Lib.isPubKey(yG) || !Secp256k1Lib.isPubKey(y) || !Secp256k1Lib.isPubKey(a1) ||
         !Secp256k1Lib.isPubKey(b1) || !Secp256k1Lib.isPubKey(a2) || !Secp256k1Lib.isPubKey(b2)) {
         return false;
      }

      // Does c =? d1 + d2 (mod n)
      if(uint(sha256(abi.encodePacked(msg.sender, xG, y, a1, b1, a2, b2))) != addmod(params[0],params[1],nn)) {
        return false;
      }

      (mR.k,mR.l,mR.m) = Secp256k1Lib.ecMul(params[2], G[0], G[1], pp);
      // a1 =? g^{r1} * x^{d1}
      mR.temp2 = [mR.k,mR.l,mR.m];
      (mR.k,mR.l,mR.m) = Secp256k1Lib.ecMul(params[0], xG[0], xG[1], pp);
      mR.temp3 = Secp256k1Lib._add(mR.temp2, [mR.k,mR.l,mR.m]);//todo fix
      ECCMathLib.toZ1(mR.temp3, pp);

      if(a1[0] != mR.temp3[0] || a1[1] != mR.temp3[1]) {
        return false;
      }

      //b1 =? h^{r1} * y^{d1} (temp = affine 'y')
      (mR.k,mR.l,mR.m) = Secp256k1Lib.ecMul(params[2], yG[0], yG[1], pp);
      mR.temp2 = [mR.k,mR.l,mR.m];//todo fix
      (mR.k,mR.l,mR.m) = Secp256k1Lib.ecMul(params[0], y[0], y[1], pp);
      mR.temp3 = Secp256k1Lib._add(mR.temp2, [mR.k,mR.l,mR.m]);//todo fix
      ECCMathLib.toZ1(mR.temp3, pp);

      if(b1[0] != mR.temp3[0] || b1[1] != mR.temp3[1]) {
        return false;
      }

      //a2 =? g^{r2} * x^{d2}
      (mR.k,mR.l,mR.m) = Secp256k1Lib.ecMul(params[3], G[0], G[1], pp);
      mR.temp2 = [mR.k,mR.l,mR.m];//todo fix
      (mR.k,mR.l,mR.m) = Secp256k1Lib.ecMul(params[1], xG[0], xG[1], pp);
      mR.temp3 = Secp256k1Lib._add(mR.temp2, [mR.k,mR.l,mR.m]);//todo fix
      ECCMathLib.toZ1(mR.temp3, pp);

      if(a2[0] != mR.temp3[0] || a2[1] != mR.temp3[1]) {
        return false;
      }

      // Negate the 'y' co-ordinate of g
      mR.temp1[0] = G[0];
      mR.temp1[1] = pp - G[1];

      // get 'y'
      mR.temp3[0] = y[0];
      mR.temp3[1] = y[1];
      mR.temp3[2] = 1;

      // y-g
      mR.temp2 = Secp256k1Lib._addMixed(mR.temp3,mR.temp1);

      // Return to affine co-ordinates
      ECCMathLib.toZ1(mR.temp2, pp);
      mR.temp1[0] = mR.temp2[0];
      mR.temp1[1] = mR.temp2[1];

      // (y-g)^{d2}
      (mR.k,mR.l,mR.m) = Secp256k1Lib.ecMul(params[1], mR.temp1[0], mR.temp1[1], pp);
      mR.temp2 = [mR.k,mR.l,mR.m];//todo fix

      // Now... it is h^{r2} + temp2..
      (mR.k,mR.l,mR.m) = Secp256k1Lib.ecMul(params[3], yG[0], yG[1], pp);
      mR.temp3 = Secp256k1Lib._add([mR.k,mR.l,mR.m],mR.temp2);//todo fix

      // Convert to Affine Co-ordinates
      ECCMathLib.toZ1(mR.temp3, pp);

      // Should all match up.
      if(b2[0] != mR.temp3[0] || b2[1] != mR.temp3[1]) {
        return false;
      }

      return true;
    }
}

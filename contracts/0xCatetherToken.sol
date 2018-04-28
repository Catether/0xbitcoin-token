pragma solidity ^0.4.23;

// ----------------------------------------------------------------------------

// ERC20 Token, with the addition of symbol, name and decimals and an

// initial fixed supply

// ----------------------------------------------------------------------------

contract _0xCatetherToken is ERC20Interface, Owned {

    using SafeMath for uint;
    using ExtendedMath for uint;


    string public symbol;

    string public  name;

    uint8 public decimals;

    uint public _totalSupply;



    uint public latestDifficultyPeriodStarted;
    uint public latestDifficultyTimeStamp;



    uint public epochCount;//number of 'blocks' mined

    //a little number
    uint public  _MINIMUM_TARGET = 2**16;


    //a big number is easier ; just find a solution that is smaller
    //uint public  _MAXIMUM_TARGET = 2**224;  bitcoin uses 224
    uint public  _MAXIMUM_TARGET = 2**232;


    uint public miningTarget;

    bytes32 public challengeNumber;   //generate a new one when a new reward is minted


    address public lastRewardTo;
    uint public lastRewardAmount;
    uint public lastRewardEthBlockNumber;

    // a bunch of maps to know where this is going (pun intended)
    
    mapping(bytes32 => bytes32) solutionForChallenge;
    mapping(uint => uint) difficultyForEpoch;
    mapping(uint => uint) blockHeightForEpoch;
    mapping(uint => uint) timeStampForEpoch;

    mapping(address => uint) balances;


    mapping(address => mapping(address => uint)) allowed;


    event Mint(address indexed from, uint reward_amount, uint epochCount, bytes32 newChallengeNumber);

    // ------------------------------------------------------------------------

    // Constructor

    // ------------------------------------------------------------------------

    constructor() public{

        symbol = "0xCATE";

        name = "0xCatether Token";

        decimals = 8;
        epochCount = 0;
        _totalSupply = 0;

        miningTarget = _MAXIMUM_TARGET;
        challengeNumber = "GENESIS_BLOCK";
        solutionForChallenge[challengeNumber] = "Yes, this is the Genesis block.";

        latestDifficultyPeriodStarted = block.number;

        _startNewMiningEpoch();


        //The owner gets nothing! You must mine this ERC20 token
        //balances[owner] = _totalSupply;
        //Transfer(address(0), owner, _totalSupply);
    }




        function mint(uint256 nonce, bytes32 challenge_digest) public returns (bool success) {


            //the PoW must contain work that includes a recent ethereum block hash (challenge number) and the msg.sender's address to prevent MITM attacks
            bytes32 digest =  keccak256(challengeNumber, msg.sender, nonce );

            //the challenge digest must match the expected
            if (digest != challenge_digest) revert();

            //the digest must be smaller than the target
            if(uint256(digest) > miningTarget) revert();


            //only allow one reward for each challenge
             bytes32 solution = solutionForChallenge[challengeNumber];
             solutionForChallenge[challengeNumber] = digest;
             if(solution != 0x0) revert();  //prevent the same answer from awarding twice


            uint reward_amount = getMiningReward(digest);

            balances[msg.sender] = balances[msg.sender].add(reward_amount);

            _totalSupply = _totalSupply.add(reward_amount);

            //set readonly diagnostics data
            lastRewardTo = msg.sender;
            lastRewardAmount = reward_amount;
            lastRewardEthBlockNumber = block.number;

             _startNewMiningEpoch();

              emit Mint(msg.sender, reward_amount, epochCount, challengeNumber );

           return true;

        }


    //a new 'block' to be mined
    function _startNewMiningEpoch() internal {
        
        blockHeightForEpoch[epochCount] = block.number;
        timeStampForEpoch[epochCount] = block.timestamp;
        difficultyForEpoch[epochCount] = miningTarget;
        epochCount = epochCount.add(1);
    
      //Difficulty adjustment following the DigiChieldv3 implementation (Tempered-SMA)
      // Allows more thorough protection against multi-pool hash attacks
      // https://github.com/zawy12/difficulty-algorithms/issues/9
        _reAdjustDifficulty();


      //make the latest ethereum block hash a part of the next challenge for PoW to prevent pre-mining future blocks
      //do this last since this is a protection mechanism in the mint() function
      challengeNumber = blockhash(block.number - 1);

    }




    //https://github.com/zawy12/difficulty-algorithms/issues/9
    //readjust the target via a tempered SMA
    function _reAdjustDifficulty() internal {
        
        //we want miners to spend 1 minutes to mine each 'block'
        //for that, we need to approximate as closely as possible the current difficulty, by averaging the 28 last difficulties,
        // compared to the average time it took to mine each block.
        // also, since we can't really do that if we don't even have 28 mined blocks, difficulty will not move until we reach that number.
        
        uint timeTarget = 60;
        
        if(epochCount>28) {
            // counter, difficulty-sum, solve-time-sum, solvetime
            uint i = 0;
            uint sumD = 0;
            uint sumST = 0;  // the first calculation of the timestamp difference can be negative, but it's not that bad (see below)
            uint solvetime;
            
            for(i=epochCount.sub(28); i<epochCount; i++){
                sumD = sumD.add(difficultyForEpoch[i]);
                solvetime = timeStampForEpoch[i] - timeStampForEpoch[i-1];
                if (solvetime > timeTarget.mul(7)) {solvetime = timeTarget.mul(7); }
                //if (solvetime < timeTarget.mul(-6)) {solvetime = timeTarget.mul(-6); }    Ethereum EVM doesn't allow for a timestamp that make time go "backwards" anyway, so, we're good
                sumST += solvetime;                                                   //    (block.timestamp is an uint256 => negative = very very long time, thus rejected by the network)
                // we don't use safeAdd because in sore rare cases, it can underflow. However, the EVM structure WILL make it overflow right after, thus giving a correct SumST after a few loops
            }
            sumST = sumST.mul(10000).div(2523).add(1260); // 1260 seconds is a 75% weighing on what should be the actual time to mine 28 blocks.
            miningTarget = sumD.mul(60).div(sumST); //We add it to the actual time it took with a weighted average (tempering)
        }
        
        latestDifficultyPeriodStarted = block.number;

        if(miningTarget < _MINIMUM_TARGET) //very difficult
        {
          miningTarget = _MINIMUM_TARGET;
        }

        if(miningTarget > _MAXIMUM_TARGET) //very easy
        {
          miningTarget = _MAXIMUM_TARGET;
        }
        difficultyForEpoch[epochCount] = miningTarget;
    }


    //this is a recent ethereum block hash, used to prevent pre-mining future blocks
    function getChallengeNumber() public constant returns (bytes32) {
        return challengeNumber;
    }

    //the number of zeroes the digest of the PoW solution requires.  Auto adjusts
     function getMiningDifficulty() public constant returns (uint) {
        return _MAXIMUM_TARGET.div(miningTarget);
    }

    function getMiningTarget() public constant returns (uint) {
       return miningTarget;
   }



    //There's no limit to the coin supply
    //reward follows the same emmission rate as Dogecoins'
    function getMiningReward(bytes32 digest) public constant returns (uint) {
        
        if(epochCount > 600000) return (10000 * 10**uint(decimals) );
        if(epochCount > 500000) return (15625 * 10**uint(decimals) );
        if(epochCount > 400000) return (31250 * 10**uint(decimals) );
        if(epochCount > 300000) return (62500 * 10**uint(decimals) );
        if(epochCount > 200000) return (125000 * 10**uint(decimals) );
        if(epochCount > 145000) return (250000 * 10**uint(decimals) );
        if(epochCount > 100000) return ((uint256(keccak256(digest, blockhash(block.number - 2))) % 500000) * 10**uint(decimals) );
        return ( (uint256(keccak256(digest, blockhash(block.number - 2))) % 1000000) * 10**uint(decimals) );

    }

    //help debug mining software (even though challenge_digest isn't used, this function is constant and helps troubleshooting mining issues)
    function getMintDigest(uint256 nonce, bytes32 challenge_digest, bytes32 challenge_number) public view returns (bytes32 digesttest) {

        bytes32 digest = keccak256(challenge_number,msg.sender,nonce);

        return digest;

      }

        //help debug mining software
      function checkMintSolution(uint256 nonce, bytes32 challenge_digest, bytes32 challenge_number, uint testTarget) public view returns (bool success) {

          bytes32 digest = keccak256(challenge_number,msg.sender,nonce);

          if(uint256(digest) > testTarget) revert();

          return (digest == challenge_digest);

        }



    // ------------------------------------------------------------------------

    // Total supply

    // ------------------------------------------------------------------------

    function totalSupply() public constant returns (uint) {

        return _totalSupply  - balances[address(0)];

    }



    // ------------------------------------------------------------------------

    // Get the token balance for account `tokenOwner`

    // ------------------------------------------------------------------------

    function balanceOf(address tokenOwner) public constant returns (uint balance) {

        return balances[tokenOwner];

    }



    // ------------------------------------------------------------------------

    // Transfer the balance from token owner's account to `to` account

    // - Owner's account must have sufficient balance to transfer

    // - 0 value transfers are allowed

    // ------------------------------------------------------------------------

    function transfer(address to, uint tokens) public returns (bool success) {

        balances[msg.sender] = balances[msg.sender].sub(tokens);

        balances[to] = balances[to].add(tokens);

        emit Transfer(msg.sender, to, tokens);

        return true;

    }



    // ------------------------------------------------------------------------

    // Token owner can approve for `spender` to transferFrom(...) `tokens`

    // from the token owner's account

    //

    // https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20-token-standard.md

    // recommends that there are no checks for the approval double-spend attack

    // as this should be implemented in user interfaces

    // ------------------------------------------------------------------------

    function approve(address spender, uint tokens) public returns (bool success) {

        allowed[msg.sender][spender] = tokens;

        emit Approval(msg.sender, spender, tokens);

        return true;

    }



    // ------------------------------------------------------------------------

    // Transfer `tokens` from the `from` account to the `to` account

    //

    // The calling account must already have sufficient tokens approve(...)-d

    // for spending from the `from` account and

    // - From account must have sufficient balance to transfer

    // - Spender must have sufficient allowance to transfer

    // - 0 value transfers are allowed

    // ------------------------------------------------------------------------

    function transferFrom(address from, address to, uint tokens) public returns (bool success) {

        balances[from] = balances[from].sub(tokens);

        allowed[from][msg.sender] = allowed[from][msg.sender].sub(tokens);

        balances[to] = balances[to].add(tokens);

        emit Transfer(from, to, tokens);

        return true;

    }



    // ------------------------------------------------------------------------

    // Returns the amount of tokens approved by the owner that can be

    // transferred to the spender's account

    // ------------------------------------------------------------------------

    function allowance(address tokenOwner, address spender) public constant returns (uint remaining) {

        return allowed[tokenOwner][spender];

    }



    // ------------------------------------------------------------------------

    // Token owner can approve for `spender` to transferFrom(...) `tokens`

    // from the token owner's account. The `spender` contract function

    // `receiveApproval(...)` is then executed

    // ------------------------------------------------------------------------

    function approveAndCall(address spender, uint tokens, bytes data) public returns (bool success) {

        allowed[msg.sender][spender] = tokens;

        emit Approval(msg.sender, spender, tokens);

        ApproveAndCallFallBack(spender).receiveApproval(msg.sender, tokens, this, data);

        return true;

    }



    // ------------------------------------------------------------------------

    // Don't accept ETH

    // ------------------------------------------------------------------------

    function () public payable {

        revert();

    }



    // ------------------------------------------------------------------------

    // Owner can transfer out any accidentally sent ERC20 tokens

    // ------------------------------------------------------------------------

    function transferAnyERC20Token(address tokenAddress, uint tokens) public onlyOwner returns (bool success) {

        return ERC20Interface(tokenAddress).transfer(owner, tokens);

    }

}

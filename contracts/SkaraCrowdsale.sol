pragma solidity ^0.4.18;

import 'zeppelin-solidity/contracts/crowdsale/CappedCrowdsale.sol';
import 'zeppelin-solidity/contracts/crowdsale/FinalizableCrowdsale.sol';
import 'zeppelin-solidity/contracts/math/SafeMath.sol';
import './Bonificated.sol';
import './Whitelist.sol';
import './SkaraToken.sol';
import './VestingManager.sol';
import './PreSale.sol';

/**
 * @title SampleCrowdsale
 * @dev This is an example of a fully fledged crowdsale.
 * The way to add new features to a base crowdsale is by multiple inheritance.
 * In this example we are providing following extensions:
 * CappedCrowdsale - sets a max boundary for raised funds
 * RefundableCrowdsale - set a min goal to be reached and returns funds if it's not met
 *
 * After adding multiple features it's good practice to run integration tests
 * to ensure that subcontracts works together as intended.
 */
//contract SkaraCrowdsale is CappedCrowdsale, BonificatedCrowdsale, TokenVesting {
contract SkaraCrowdsale is CappedCrowdsale, FinalizableCrowdsale, Bonificated, Whitelist, VestingManager, PreSale { 
  using SafeMath for uint256;

  //Whitelist
  uint256 public constant WHITELIST_DURATION = 2 days; 

  //Bonificated
  uint256 public constant BONUS_DURATION = 3 days; 
  uint256 public constant BONUS_START_VALUE = 15; //Default bonus percentage at BONUS_START_TIME

  //vesting
  uint256 public constant PRE_SALE_VESTING_CLIFF = 12 weeks; 

  uint256 public constant BOUNTY_VESTING_CLIFF = 12 weeks; 
  uint256 public constant BOUNTY_VESTING_DURATION = 1 years; 

  uint256 public constant TEAM_VESTING_CLIFF = 12 weeks; 
  uint256 public constant TEAM_VESTING_DURATION = 1 years; 

  //final allocation
  uint256 public constant SALE_ALLOCATION_PERCENTAGE = 63; 
  uint256 public constant FINAL_ALLOCATION_PERCENTAGE = 37; 
  
  function SkaraCrowdsale(uint256 _cap, uint256 _startTime, uint256 _endTime, uint256 _rate, address _wallet) public
    CappedCrowdsale(_cap)
    FinalizableCrowdsale()
    Whitelist(_startTime, _cap)
    Bonificated(_startTime, BONUS_DURATION, BONUS_START_VALUE)
    Crowdsale(_startTime, _endTime, _rate, _wallet)
    VestingManager(_endTime)
  {
  }

  function createTokenContract() internal returns (MintableToken) {
    return new SkaraToken();
  }

  // overriding Crowdsale#buyTokens to add presale, whitelist and bonus logic
  function buyTokens(address beneficiary) public payable {
    require(beneficiary != address(0));

    uint256 weiAmount = msg.value;
    
    //handle whitelist logic
    if(isWhitelistPeriod()) {
      require(isWhitelisted(msg.sender));
      
      if(isDayOne()) {
        uint256 senderBoundary = getBoundary(msg.sender);
        require(weiAmount <= senderBoundary);
        _addToDayTwo(msg.sender);
      }
    }
      
    require(validPurchase()); 

    
    // calculate token amount to be created
    uint256 tokens = weiAmount.mul(rate);

    //add bonus
    uint256 currentBonusMultiplier = getBonus(msg.sender).add(10000);
    tokens = tokens.mul(currentBonusMultiplier).div(10000);
    
    //update state
    weiRaised = weiRaised.add(weiAmount);

    //vesting
    if(hasTokenVesting(msg.sender)) {
      TokenVesting vesting = createTokenVesting();
      //mint tokens for vesting contract
      token.mint(vesting, tokens);
    }
    else{
      //mint tokens for beneficiary
      token.transfer(beneficiary, tokens);
    }

    TokenPurchase(msg.sender, beneficiary, weiAmount, tokens);
    forwardFunds();
    
  }

  function setupPresaler(address who, uint256 amount, uint256 vestingDuration) public {
    addVestingConfig(who, PRE_SALE_VESTING_CLIFF, vestingDuration, false);
    _addPresaler(who, amount);
  }

  function addBountyMember(address who) public {
    addVestingConfig(who, PRE_SALE_VESTING_CLIFF, BOUNTY_VESTING_DURATION, false);
  }

  function addTeamMember(address who) public {
    addVestingConfig(who, PRE_SALE_VESTING_CLIFF, TEAM_VESTING_DURATION, true);
  }

  // Override CappedCrowdsale#validPurchase to add presale logic
  //@return true if the transaction can buy tokens
  function validPurchase() internal view returns (bool) {
    bool nonZeroPurchase = msg.value != 0;
    bool withinCap = weiRaised.add(msg.value) <= cap;
    
    if(isPresaler(msg.sender)) {
      return nonZeroPurchase && withinCap;
    } 
    
    return super.validPurchase();
  }
  
  /**
   * @dev Override FinalizableCrowdsale#finalization to add final token allocation
   */
  function finalization() internal {
    uint256 totalSale = token.totalSupply();
    uint256 total = totalSale.div(SALE_ALLOCATION_PERCENTAGE.div(100));
    uint256 finalAllocation = FINAL_ALLOCATION_PERCENTAGE.mul(total);

    token.mint(this, finalAllocation);

    super.finalization();
  }


}


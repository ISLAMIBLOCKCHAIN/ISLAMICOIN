// SPDX-License-Identifier: MIT



pragma solidity ^0.8.4;

import "./ISLAMICOIN.sol";

contract IslamiTeamTokenLock {
    
    ISLAMICOIN public ISLAMI;

mapping(address => bool) TeamMemberBlacklist;
        event Blacklist(address indexed blackListed, bool value);


  address public beneficiary;
  uint256 public releaseTime;
  
  address team1 = address(0x324483939292);
  address team2 = address(0x324483939292);
  address team3 = address(0x324483939292);
  address team4 = address(0x324483939292);
  address team5 = address(0x324483939292);
  address team6 = address(0x324483939292);
  address team7 = address(0x324483939292);
  address team8 = address(0x324483939292);
  address team9 = address(0x324483939292);

  constructor(ISLAMICOIN _token, uint256 _releaseTime) {
    require(_releaseTime > block.timestamp);
    ISLAMI = _token;
   // beneficiary = _beneficiary;
    releaseTime = 1661633999;        //Saturday, August 27, 2022 8:59:59 PM /  Epoch timestamp: 1661633999
  }
  
  function _blackListTeam(address _address, bool _isBlackListedtm) internal returns (bool) {
    require(TeamMemberBlacklist[_address] != _isBlackListedtm);
    TeamMemberBlacklist[_address] = _isBlackListedtm;
    emit Blacklist(_address, _isBlackListedtm);
    return true;
  }

  function release() public {
    require(block.timestamp >= releaseTime);
    require(TeamMemberBlacklist[msg.sender] == false, "ISLAMI allready claimed for this address");
    uint256 amount = ISLAMI.balanceOf(address(this));
    require(amount > 0);
if (msg.sender == team1){
    
    beneficiary = team1;
    ISLAMI.transfer(beneficiary, 200000000 *10** ISLAMI.decimals());
    
}
else if (msg.sender == team2){
    
    beneficiary = team2;
    ISLAMI.transfer(beneficiary, 200000000 *10** ISLAMI.decimals());
}

else {
    return;
}
_blackListTeam(msg.sender, true);
  }

}


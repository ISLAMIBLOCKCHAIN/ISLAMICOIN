// SPDX-License-Identifier: MIT

/*
@dev
contract is audited by solid proof 
*/

/*
@dev: This is a special vesting contract for ISLAMI token partner
*/

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

pragma solidity = 0.8.17;

contract ISLAMIspecialVesting {
    using SafeMath for uint256;
    address private owner;
    ERC20 public ISLAMI;


    address public constant zeroAddress = address(0x0);
    
    
/*
@dev: Private values
*/  
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;
    

/*
@dev: public values
*/
    // Number of Decimals in ISLAMI
    uint256 public constant Sonbola = 10**7;
    uint256 public constant monthly = 30 days;
    uint256 public investorCount;
    uint256 public investorVault;
    //100%
    uint256 public constant hPercent = 100;
    /* Monthy percentage */
    uint256 public mP = 5;
    uint256 public minLock = 100000 * Sonbola;
    
/*
@dev: Events
*/
    event InvestorAdded(address Investor, uint256 Amount);
    event ISLAMIClaimed(address Investor, uint256 Amount);
    event EmergencyWithdraw(address Investor, address NewWallet, uint256 Amount);
    event ChangeOwner(address NewOwner);
    event WithdrawalMatic(uint256 _amount, uint256 decimal, address to); 
    event WithdrawalISLAMI(uint256 _amount,uint256 sonbola, address to);
    event WithdrawalERC20(address _tokenAddr, uint256 _amount,uint256 decimals, address to);
/*
@dev: Investor Vault
*/   
    struct VaultInvestor{
        //represents the actual amount locked in order to keep track of monthly percentage to unlock
        uint256 falseAmount;
        uint256 amount;
        address recoveryWallet;
        uint256 monthLock;
        uint256 lockTime;
        uint256 timeStart;
        bool voted;
        uint256 votedForEvent;
    }


/*
 @dev: Mappings
*/
    mapping(address => bool) public Investor;
    
    mapping(address => VaultInvestor) public investor;

/**/   

/* @dev: Check if contract owner */
    modifier onlyOwner (){
        require(msg.sender == owner, "Only ISLAMICOIN owner can add Investors");
        _;
    }
/*
    @dev: check if user is investor
*/
    modifier isInvestor(address _investor){
        require(Investor[_investor] == true, "Not an Investor!");
        _;
    }

/*
    @dev: prevent reentrancy when function is executed
*/
    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
    constructor(ERC20 _ISLAMI) {
        owner = msg.sender;
        investorCount = 0;
        ISLAMI = _ISLAMI;
        _status = _NOT_ENTERED;
    }
/*
    @dev: Change the contract owner
*/
    function transferOwnership(address _newOwner)external onlyOwner{
        require(_newOwner != zeroAddress,"Zero Address");
        emit ChangeOwner(_newOwner);
        owner = _newOwner;
    }

/*
    @dev: Check if caller has locked tokens
*/    
    function hasLockedTokens(address _investor) public view returns(bool){
        if(Investor[_investor] == true){
            return true;
        }
        else{
            return false;
        }
    }
/*
    @dev: Set monthly percentage allowed
    to collect after the whole period of locking has ended
    minimum 3% maximum 10%
*/
    function setMonthlyPercentage(uint256 _mP) external onlyOwner{
        require(_mP >= 3 && _mP <= 10,"Percentage is less than 3% or more than 10%!");
        mP = _mP;
    }
    function addInvestor(address _investor, uint256 _amount, uint256 _lockTime, address _recoveryWallet) external onlyOwner{
        uint256 amount = _amount.mul(Sonbola);
        uint256 availableAmount = ISLAMI.balanceOf(address(this)).sub(investorVault);
        require(availableAmount >= amount,"No ISLAMI");
        uint256 lockTime = _lockTime.mul(monthly);
        require(amount > 0, "Amount greater than 0!");
        if(investor[_investor].amount > 0){
            investor[_investor].amount += amount;
            investor[_investor].falseAmount = investor[_investor].amount;
            investorVault += amount;
            return;
        }
        require(lockTime > monthly.mul(12), "less than 1 year!");
        emit InvestorAdded(_investor, amount);
        investor[_investor].falseAmount = amount;
        investor[_investor].amount = amount;
        investor[_investor].recoveryWallet = _recoveryWallet;
        investor[_investor].lockTime = lockTime.add(block.timestamp);
        investor[_investor].timeStart = block.timestamp;
        investor[_investor].monthLock = lockTime.add(block.timestamp);
        Investor[_investor] = true;
        investorVault += amount;
        investorCount++;
    }

/*
    @dev: Claim Monthly allowed amount for long term investors
*/
    function claimMonthlyAmount() external isInvestor(msg.sender) nonReentrant{
        uint256 totalTimeLock = investor[msg.sender].monthLock;
        uint256 mainAmount = investor[msg.sender].falseAmount;
        uint256 remainAmount = investor[msg.sender].amount;
        require(totalTimeLock <= block.timestamp, "Not yet");
        require(remainAmount > 0, "No ISLAMI");  
        uint256 amountAllowed = mainAmount.mul(mP).div(hPercent);
        investor[msg.sender].amount = remainAmount.sub(amountAllowed);
        investor[msg.sender].monthLock = monthly.add(block.timestamp);
        investorVault -= amountAllowed;
        if(investor[msg.sender].amount == 0){
            Investor[msg.sender] = false;
            delete investor[msg.sender];
            investorCount--;
        }
        emit ISLAMIClaimed(msg.sender, amountAllowed);
        ISLAMI.transfer(msg.sender, amountAllowed);
    }
/*
    @dev: If their are any leftovers after claiming all allowed amounts
*/
    function claimRemainings() external isInvestor(msg.sender) nonReentrant{
        uint256 fullTime = hPercent.div(mP).mul(monthly);
        uint256 totalTimeLock = investor[msg.sender].lockTime.add(fullTime);
        require(totalTimeLock <= block.timestamp, "Not yet");
        uint256 remainAmount = investor[msg.sender].amount;
        investor[msg.sender].amount = 0;
        investorVault -= remainAmount;
        Investor[msg.sender] = false;
        delete investor[msg.sender];
        emit ISLAMIClaimed(msg.sender, remainAmount);
        ISLAMI.transfer(msg.sender, remainAmount);
        investorCount--;
    }

/*
    @dev: If long term investor wallet was lost!
*/
    function releaseWallet(address _investor) isInvestor(_investor) external nonReentrant{
        uint256 fullTime = hPercent.div(mP).mul(monthly);
        uint256 totalTimeLock = investor[_investor].lockTime.add(fullTime);
        require(msg.sender == investor[_investor].recoveryWallet &&
        totalTimeLock < block.timestamp,"Not yet!");
        uint256 remainAmount = investor[_investor].amount;
        investor[_investor].amount = 0;
        investorVault -= remainAmount;
        Investor[_investor] = false;
        delete investor[_investor];
        investorCount--;
        emit EmergencyWithdraw(_investor, msg.sender, remainAmount);
        ISLAMI.transfer(msg.sender, remainAmount);
    }
/*
    @dev: Withdrwa ISLAMI that are not locked for Investors
    usage: sending ISLAMI by user directly to contract,
    in this function we can return only what is sent by mistake
*/
    function withdrawalISLAMI(uint256 _amount, uint256 sonbola, address to) external onlyOwner() {
        uint256 dcml = 10 ** sonbola;
        uint256 amount = ISLAMI.balanceOf(address(this)).sub(investorVault);
        require(amount > 0 && _amount*dcml <= amount, "No ISLAMI!");
        emit WithdrawalISLAMI( _amount, sonbola, to);
        ISLAMI.transfer(to, _amount*dcml);
    }
/*
    @dev: Withdrwa ERC20 tokens if sent by mistake to contract
    and return back to sender
*/
    function withdrawalERC20(address _tokenAddr, uint256 _amount, uint256 decimal, address to) external onlyOwner() {
        uint256 dcml = 10 ** decimal;
        ERC20 token = ERC20(_tokenAddr);
        require(token != ISLAMI, "No!"); //Can't withdraw ISLAMI using this function!
        emit WithdrawalERC20(_tokenAddr, _amount, decimal, to);
        token.transfer(to, _amount*dcml); 
    }  
/*
    @dev: Withdrwa Matic token!
    return back to sender if sent by mistake
*/
    function withdrawalMatic(uint256 _amount, uint256 decimal, address to) external onlyOwner() {
        require(address(this).balance >= _amount,"Balanace"); //No matic balance available
        require(to != address(0), "Zero Address");
        uint256 dcml = 10 ** decimal;
        emit WithdrawalMatic(_amount, decimal, to);
        payable(to).transfer(_amount*dcml);      
    }
/*
    @dev: contract is payable (can receive Matic)
*/
    receive() external payable {}
}


               /*********************************************************
                  Proudly Developed by MetaIdentity ltd. Copyright 2022
               **********************************************************/

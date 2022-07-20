// SPDX-License-Identifier: MIT

/************************
Metacces Vesting Wallet
************************/

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

pragma solidity = 0.8.15;

contract AccesVesting {
    using SafeMath for uint256;

    address public constant zeroAddress = address(0x0);
    address public constant deadAddress = 0x000000000000000000000000000000000000dEaD;
    address private feeReceiver;
    
    ERC20 public Acces;
    address private owner;
    uint256 public constant monthly = 30 days;
    uint256 public investorCount;
    uint256 private investorID;
    uint256 public investorsVault;
    uint256 public teamVault;
    uint256 public teamCount;
    uint256 public totalLocked;
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 public constant hPercent = 100; //100%
    uint256 private _status;
    uint256 public mP = 5; /* Monthy percentage */
    

    event InvestorAdded(address Investor, uint256 Amount);
    event TeamAdded(address Team, uint256 Amount);
    event AccesClaimed(address Investor, uint256 Amount);
    event ChangeOwner(address NewOwner);
    event MonthlyPercentageChanged(uint256 NewPercentage);
    event WithdrawalBNB(uint256 _amount, uint256 decimal, address to); 
    event WithdrawalAcces(uint256 _amount,uint256 decimal, address to);
    event WithdrawalBEP20(address _tokenAddr, uint256 _amount,uint256 decimals, address to);
    
    struct InvestorSafe{
        uint256 investorID;
        //falseAmount represents the actual amount locked in order to keep track of monthly percentage to unlock
        uint256 falseAmount;
        uint256 amount;
        uint256 monthLock;
        uint256 lockTime;
        uint256 timeStart;
        bool voted;
        uint256 votedForEvent;
        bool isTeam;
    }
 
    mapping(address => bool) public Investor;
    mapping(address => InvestorSafe) public investor;


    mapping(address => bool) public blackList; 
    

    modifier onlyOwner (){
        require(msg.sender == owner, "Only Acces owner can add Investors");
        _;
    }

    modifier isInvestor(address _investor){
        require(Investor[_investor] == true, "Not an Investor!");
        _;
    }

    modifier isNotBlackListed(address _investor){
        require(blackList[_investor] != true, "Your wallet is Blacklisted!");
        _;
    }
    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
    constructor(ERC20 _Acces, address _feeReceiver) {
        owner = msg.sender;
        feeReceiver = _feeReceiver;
        investorCount = 0;
        investorID = 0;
        votingEventID = 0;
        Acces = _Acces;
        _status = _NOT_ENTERED;
    }
    function transferOwnership(address _newOwner)external onlyOwner{
        require(_newOwner != zeroAddress,"Zero Address");
        emit ChangeOwner(_newOwner);
        owner = _newOwner;
    }
    function changeFeeReceiver(address _newReceiver) external onlyOwner{
        feeReceiver = _newReceiver;
    }
    function setMonthlyPercentage(uint256 _mP) external onlyOwner{
        require(_mP > 0 && mP <= 30,"Min 1% Max 30%");
        mP = _mP;
        emit MonthlyPercentageChanged(_mP);
    }
    function addToBlackList(address _investor) external onlyOwner{
        blackList[_investor] = true;
    }
    function removeFromBlackList(address _investor) external onlyOwner{
        blackList[_investor] = false;
    }
    function allVaults() internal{
        totalLocked = investorsVault.add(teamVault);
    }
    function addInvestor(address _investor, bool _isTeam, uint256 _amount, uint256 _lockTime) external onlyOwner{
        require(_investor != zeroAddress && _investor != deadAddress,"Zero Address Dead!");
        uint256 availableAmount = Acces.balanceOf(address(this)).sub(investorsVault);
        require(availableAmount >= _amount,"No Acces");
        uint256 lockTime = _lockTime.mul(1 days);
        require(_amount > 0, "Amount!");
        if(investor[_investor].amount > 0){
            investor[_investor].amount += _amount;
            investor[_investor].falseAmount = investor[_investor].amount;
            investorsVault += _amount;
            return;
        }
        require(lockTime > monthly.mul(3), "Please set a time in the future more than 90 days!");
        emit InvestorAdded(msg.sender, _amount);
        investorID++;
        investor[_investor].investorID = investorID;
        investor[_investor].falseAmount = _amount;
        investor[_investor].amount = _amount;
        investor[_investor].lockTime = lockTime.add(block.timestamp);
        investor[_investor].timeStart = block.timestamp;
        investor[_investor].monthLock = lockTime.add(block.timestamp);
        investor[_investor].isTeam = _isTeam;
        Investor[_investor] = true;
        if(_isTeam == true){
            teamVault += _amount;
            teamCount++;
        }
        else{
           investorsVault += _amount;
           investorCount++; 
        }
    }
    function claimMonthlyAmount() external isInvestor(msg.sender) isNotBlackListed(msg.sender) nonReentrant{
        uint256 totalTimeLock = investor[msg.sender].monthLock;
        uint256 mainAmount = investor[msg.sender].falseAmount;
        uint256 remainAmount = investor[msg.sender].amount;
        require(totalTimeLock <= block.timestamp, "Not yet");
        require(remainAmount > 0, "No Acces");  
        uint256 amountAllowed = mainAmount.mul(mP).div(hPercent);
        investor[msg.sender].amount = remainAmount.sub(amountAllowed);
        investor[msg.sender].monthLock += monthly;
        investorsVault -= amountAllowed;
        if(investor[msg.sender].amount == 0){
            Investor[msg.sender] = false;
            delete investor[msg.sender]; 
            investorCount--;
        }
        emit AccesClaimed(msg.sender, amountAllowed);
        Acces.transfer(msg.sender, amountAllowed);
    }
    function claimRemainings() external isInvestor(msg.sender) isNotBlackListed(msg.sender) nonReentrant{
        uint256 fullTime = hPercent.div(mP).mul(monthly);
        uint256 totalTimeLock = investor[msg.sender].lockTime.add(fullTime);
        require(totalTimeLock <= block.timestamp, "Not yet");
        uint256 remainAmount = investor[msg.sender].amount;
        investor[msg.sender].amount = 0;
        investorsVault -= remainAmount;
        Investor[msg.sender] = false;
        delete investor[msg.sender];
        emit AccesClaimed(msg.sender, remainAmount);
        Acces.transfer(msg.sender, remainAmount);
        investorCount--;
    }

/* Voting... */
    uint256 public constant path = 10**18;
    uint256 private answerCount;
    /* Each 10K Acces equal One Vote!   */
    uint256 private OneVote = 10000 * path;
    uint256 public votingEventID;
    bool public votingEventLive = false;

    event Voted(uint256 VotingEvent, address Voter, uint256 voteFee);
    event VoteResults(uint256 VotingEvent, string projectName,uint256 Result);

    struct VoteOptions{
        string voteOption;
        uint256 voteCount;
    }
    struct VoteEvent{
        uint256 eventID;
        string question;
        mapping(uint256 => VoteOptions) answers;
        uint256 status;
        string winner;
    }

    mapping(uint256 => VoteEvent) public Event; 

    function setOneVote(uint256 _oneVote) external onlyOwner{
        require(_oneVote !=0,"Zero!");
        OneVote = _oneVote;
    }
    function addToVote(uint256 _eventID, string memory _option) internal{
        answerCount++;
        require(votingEventLive == true,"Event!");
        Event[_eventID].answers[answerCount].voteOption = _option;
    }
    function setVotingEvent(string memory _question, string memory o1, string memory o2, string memory o3) external onlyOwner{
        votingEventID++;
        votingEventLive = true;
        Event[votingEventID].eventID = votingEventID;
        Event[votingEventID].question = _question;
        Event[votingEventID].status = 1; //Voting event is Active
        addToVote(votingEventID, o1);
        addToVote(votingEventID, o2);
        addToVote(votingEventID, o3);
    }
    function newVote(uint256 _eventID,uint256 _answer, uint256 _vP) internal{
        Event[_eventID].answers[_answer].voteCount += _vP;
    }
    function checkVoteResult(uint256 _eventID) internal{
        if(Event[_eventID].answers[1].voteCount > 
           Event[_eventID].answers[2].voteCount &&
           Event[_eventID].answers[1].voteCount >
           Event[_eventID].answers[3].voteCount){
               Event[_eventID].winner = Event[_eventID].answers[1].voteOption;
               return();
        }
        else if(Event[_eventID].answers[2].voteCount > 
                Event[_eventID].answers[1].voteCount &&
                Event[_eventID].answers[2].voteCount >
                Event[_eventID].answers[3].voteCount){
                    Event[_eventID].winner = Event[_eventID].answers[2].voteOption;
                    return();
        }
        else if(Event[_eventID].answers[3].voteCount > 
                Event[_eventID].answers[1].voteCount &&
                Event[_eventID].answers[3].voteCount >
                Event[_eventID].answers[2].voteCount){
                    Event[_eventID].winner = Event[_eventID].answers[3].voteOption;
                    return();
        }
        else{
            Event[_eventID].winner = "N/A";
        }
    }
    function eventResults() public view returns(uint256, string memory, string memory,uint,string memory,uint,string memory,uint){
        uint256 _eventID = votingEventID;
        string memory _question = Event[_eventID].question;
        return(_eventID, _question,
        Event[_eventID].answers[1].voteOption,
        Event[_eventID].answers[1].voteCount,
        Event[_eventID].answers[2].voteOption,
        Event[_eventID].answers[2].voteCount,
        Event[_eventID].answers[3].voteOption,
        Event[_eventID].answers[3].voteCount);
    }    
    function endVotingEvent() external onlyOwner{
        require(Event[votingEventID].status != 0,"Already ended");
        answerCount = 0;
        Event[votingEventID].status = 0; //Zero means voting event has ended
        checkVoteResult(votingEventID);
        votingEventLive = false;
    }
    function voteFor(uint256 _answer, uint256 _votingFee) isNotBlackListed(msg.sender) public nonReentrant{
        uint256 _eventID = votingEventID;
        require(votingEventLive == true,"No voting event");
        require(Investor[msg.sender] == true,"not allowed");
        address voter = msg.sender;
        uint256 votePower;
        uint256 votingFee = _votingFee;
        uint256 lockedBasePower;
        uint256 mainPower;
         if(_eventID > investor[msg.sender].votedForEvent){
                investor[msg.sender].voted = false;
        }
            require(investor[msg.sender].voted != true,"Already Voted!");
            lockedBasePower = investor[voter].amount;
            require(lockedBasePower > votingFee,"Need more Acces");
            investor[voter].amount -= votingFee;
            investor[msg.sender].voted = true;
            investor[msg.sender].votedForEvent = _eventID;
            if(investor[msg.sender].isTeam == true){
                teamVault -= votingFee;
            }
            else{
                investorsVault -= votingFee;
            }
        // results will show with two decimals
        mainPower = lockedBasePower*10**2;
        if(votingFee > 0){
            Acces.transfer(feeReceiver, votingFee);
        }
        votePower = mainPower.div(OneVote);
        newVote(_eventID, _answer, votePower);
        emit Voted(_eventID, msg.sender, votingFee);
    }
/*End Voting...*/

    function withdrawalAcces(uint256 _amount, uint256 decimal, address to) external onlyOwner() {
        allVaults();
        uint256 amount = Acces.balanceOf(address(this)).sub(totalLocked);
        uint256 dcml = 10 ** decimal;
        // can only withdraw what is not locked for investors.
        require(amount > 0 && _amount&dcml >= amount, "No Acces!");
        emit WithdrawalAcces( _amount, decimal, to);
        Acces.transfer(to, _amount*dcml);
    }
    function withdrawalBEP20(address _tokenAddr, uint256 _amount, uint256 decimal, address to) external onlyOwner() {
        uint256 dcml = 10 ** decimal;
        ERC20 token = ERC20(_tokenAddr);
        require(token != Acces, "No!"); //Can't withdraw Acces using this function!
        emit WithdrawalBEP20(_tokenAddr, _amount, decimal, to);
        token.transfer(to, _amount*dcml); 
    }  
    function withdrawalBNB(uint256 _amount, uint256 decimal, address to) external onlyOwner() {
        require(address(this).balance >= _amount,"Balanace"); //No BNB balance available
        uint256 dcml = 10 ** decimal;
        emit WithdrawalBNB(_amount, decimal, to);
        payable(to).transfer(_amount*dcml);      
    }
    receive() external payable {}
}


/**********************************
 Proudly Developed by Metacces Team
***********************************/

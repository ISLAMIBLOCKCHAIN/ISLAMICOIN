// SPDX-License-Identifier: MIT

/*
@dev: P2P smart contract ISLAMI
*/

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

pragma solidity = 0.8.17;
   using SafeMath for uint256;
 
contract ISLAMIp2p {

/*
@dev: Private values
*/  
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    address public feeReceiver;

    IERC20 ISLAMI = IERC20(0x4Cd922196d3b7f253152a1Ba3eD582F0c3c8b260);
    IERC20 USDT = IERC20(0xFc72D3C5b895601a717d78dAe2Be257e716A1573);
    IERC20 USDC = IERC20(0x254Eb2Eb0544D250aBA210A838a62FEd548C9723);

    error notOk(string);

    uint256 public orN; //represents order number created
    uint256 public sellOrders;
    uint256 public buyOrders;
    uint256 public totalOrders;
    uint256 public maxOrders = 30;
    uint256 public canceledOrders;
    uint256 public ISLAMIinOrder;
    uint256 public USDinOrder;
    uint256 constant private ISLAMIdcml = 10**7;
    uint256 constant private USDdcml = 10**6;

    uint256 public activationFee = 1000*10**7;
    uint256 public p2pFee = 1;
    uint256 public feeFactor = 1000;

    uint256 _at = 1234;
    uint256 _cr = 32;

    struct orderDetails{
        //uint256 orderIndex;
        uint256 orderType; // 1 = sell , 2 = buy
        uint256 orderNumber;
        address sB; //seller or buyer
        IERC20 orderCurrency;
        uint256 orderFalseAmount;
        uint256 remainAmount;
        uint256 orderPrice;
        uint256 currencyFalseAmount;
        uint256 remainCurrency;
        uint256 orderLife;
        bool orderStatus; // represents if order is completed or not
    }

    event orderCreated(uint256 Order, uint256 Type, uint256 Amount, uint256 Price, IERC20 Currency);
    event orderCancelled(uint256 OrderNumber, uint256 OrderIndex, address User);

    mapping(address => orderDetails) public p2p;
    mapping(address => uint256) public monopoly;
    mapping(address => bool) public canCreateOrder;
    mapping(address => uint256) private isActivated;

    orderDetails[] public OrderDetails;
    /*
    @dev: prevent reentrancy when function is executed
*/
    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    constructor(){
        feeReceiver = msg.sender;
        orN = 0;
    }
    function changeFee(uint256 _activationFee, uint256 _p2pFee, uint256 _feeFactor) external {
        require(msg.sender == feeReceiver, "Not authorized to change fee");
        require(_p2pFee >= 1 && _feeFactor >= 100,"Fee can't be zero");
        activationFee = _activationFee.mul(ISLAMIdcml);
        p2pFee = _p2pFee;
        feeFactor = _feeFactor;
    }
    function activateP2P() external nonReentrant{
        require(isActivated[msg.sender] != 1, "User P2P is already activated!");
        //require approve from ISLAMI smart contract
        ISLAMI.transferFrom(msg.sender, feeReceiver, activationFee);
        canCreateOrder[msg.sender] = true;
        isActivated[msg.sender] = 1;
    }
    function sampleOrder() external{
        _at += 536;
        _cr += 3;
        createOrder(1, _at, _cr, USDT);
    }
    function createOrder(
        uint256 _type, 
        uint256 _islamiAmount, 
        uint256 _currencyAmount, 
        IERC20 _currency
        ) 
        public 
        nonReentrant 
        returns(uint256 Order, uint256 Type)
        {
        /*if(totalOrders == maxOrders){
            superCancel();
        }*/
        require(monopoly[msg.sender] < block.timestamp, "Monopoly not allowed");
        require(canCreateOrder[msg.sender] == true, "User have an active order");
        require(_type == 1 || _type == 2, "Type not found (Buy or Sell)");
        totalOrders++;
        orN++;
        uint256 _price;
        uint256 _p2pFee;
        p2p[msg.sender].orderLife = block.timestamp.add(380);//(3 days);
        monopoly[msg.sender] = block.timestamp.add(440);//(4 days);
        p2p[msg.sender].orderNumber = orN;
        p2p[msg.sender].sB = msg.sender;
        p2p[msg.sender].orderType = _type;

        p2p[msg.sender].orderFalseAmount = _islamiAmount;
        p2p[msg.sender].orderCurrency = _currency;
        p2p[msg.sender].currencyFalseAmount = _currencyAmount;
        uint256 currencyAmount = _currencyAmount.mul(USDdcml);
        _price = currencyAmount.div(_islamiAmount);
        p2p[msg.sender].orderPrice = _price;
        if(_type == 1){ //sell ISLAMI
            p2p[msg.sender].remainAmount = _islamiAmount.mul(ISLAMIdcml);
            _p2pFee = _islamiAmount.mul(ISLAMIdcml).mul(p2pFee).div(feeFactor);
            //require approve from ISLAMICOIN contract
            ISLAMI.transferFrom(msg.sender, address(this), _islamiAmount.mul(ISLAMIdcml));
            ISLAMI.transferFrom(msg.sender, feeReceiver, _p2pFee);
            ISLAMIinOrder += _islamiAmount.mul(ISLAMIdcml);
            sellOrders++;
        }
        else if(_type == 2){ //buy ISLAMI
            p2p[msg.sender].remainCurrency = _currencyAmount.mul(USDdcml);
            _p2pFee = _currencyAmount.mul(USDdcml).mul(p2pFee).div(feeFactor);
            _currency.transferFrom(msg.sender, address(this), _currencyAmount.mul(USDdcml));
            _currency.transferFrom(msg.sender, feeReceiver, _p2pFee);
            USDinOrder += _currencyAmount.mul(USDdcml);
            buyOrders++;
        }
        OrderDetails.push(orderDetails
        (
                _type,
                orN, 
                msg.sender,
                _currency, 
                _islamiAmount.mul(ISLAMIdcml), 
                _islamiAmount.mul(ISLAMIdcml),
                _price,
                _currencyAmount.mul(USDdcml),
                _currencyAmount.mul(USDdcml),
                p2p[msg.sender].orderLife,
                false
                )
                );
        canCreateOrder[msg.sender] = false;
        emit orderCreated(orN, _type, _islamiAmount, _price, _currency);
        return (orN, _type);
    }
    function getOrders() public view returns (orderDetails[] memory){
        return OrderDetails;
    }
    function superCancel() public nonReentrant{
        uint256 _orderCancelled = 0;
        for(uint i = 0; i < OrderDetails.length -1; i++){
            if(OrderDetails[i].orderLife < block.timestamp){
                fixOrders(i);
                deleteOrder(OrderDetails[i].sB);
                canceledOrders++;
                _orderCancelled = 1;
            }
        }
        if(_orderCancelled != 1){
            revert notOk("Orders life is normal");
        }
    }
    function cancelOrder() external nonReentrant{
        uint256 _orderCancelled = 0;
        for(uint i = 0; i < OrderDetails.length -1; i++){
            if(OrderDetails[i].sB == msg.sender){
                fixOrders(i);
                deleteOrder(msg.sender);
                _orderCancelled = 1;
                if(block.timestamp < p2p[msg.sender].orderLife.sub(410)){ // (45 hours){
                    monopoly[msg.sender] = block.timestamp.add(60);//(1 hours);
                }
                break;
            }
        }
        if(_orderCancelled != 1){
            revert notOk("No user order found");
        }
        else{
            canceledOrders++;
        }
    }
    //user can cancel order and retrive remaining amounts
    function deleteOrder(address _orderOwner) internal{
        if(p2p[_orderOwner].orderType == 1){
            uint256 amount = p2p[_orderOwner].remainAmount;
            ISLAMI.transfer(_orderOwner, amount);
            sellOrders--;
        }
        else if(p2p[_orderOwner].orderType == 2){
            uint256 amount = p2p[_orderOwner].remainCurrency;
            IERC20 currency = p2p[_orderOwner].orderCurrency;
            currency.transfer(_orderOwner, amount);
            buyOrders--;
        }
        delete p2p[_orderOwner];
        canCreateOrder[_orderOwner] = true;
        //emit orderCancelled(_orderNumber, _orderIndex, msg.sender);
    }
    function fixOrders(uint256 _orderIndex) internal {
        OrderDetails[_orderIndex] = OrderDetails[OrderDetails.length - 1];
        OrderDetails.pop();
        totalOrders--;
    }
    function orderFilled() internal{
        for(uint i = 0; i < OrderDetails.length - 1; i++){
            if(OrderDetails[i].orderStatus == true){
                fixOrders(i);
            }
        }
    }
    //user can take full order or partial
    function takeOrder(address _orderOwner, uint256 _amount) external nonReentrant{
        IERC20 _currency = p2p[_orderOwner].orderCurrency;
        address seller = p2p[_orderOwner].sB;
        uint256 priceUSD = p2p[_orderOwner].orderPrice;
        uint256 toPay = _amount.mul(priceUSD);//.mul(ISLAMIdcml);
        uint256 amountUSD = _amount.mul(USDdcml);
        uint256 amountISLAMI = _amount.mul(ISLAMIdcml);
        uint256 toReceive = amountUSD.div(priceUSD).mul(ISLAMIdcml);
        uint256 _p2pFee;
        require(_currency.balanceOf(msg.sender) >= toPay, "Not enought USD");
        require(p2p[_orderOwner].orderStatus != true, "Order was completed");
        if(p2p[_orderOwner].orderType == 1){//Take sell
        require(amountISLAMI <= p2p[_orderOwner].remainAmount, "Seller has less ISLAMI than order");
        _p2pFee = amountISLAMI.mul(p2pFee).div(feeFactor);
        ISLAMI.transfer(feeReceiver, _p2pFee);
        ISLAMIinOrder -= amountISLAMI;
        p2p[_orderOwner].remainAmount -= amountISLAMI;
        //require approve from currency(USDT, USDC) contract
        _currency.transferFrom(msg.sender, seller, toPay);
        ISLAMI.transfer(msg.sender, amountISLAMI.sub(_p2pFee));
          if(amountISLAMI == p2p[_orderOwner].remainAmount){
                p2p[_orderOwner].orderStatus = true;
                canCreateOrder[p2p[_orderOwner].sB] = true;
                orderFilled();
                sellOrders--;
            }
        }
        else if(p2p[_orderOwner].orderType == 2){//Take buy
        require(amountUSD <= p2p[_orderOwner].remainCurrency, "Seller has less USD than order");
        _p2pFee = amountUSD.mul(p2pFee).div(feeFactor);
        _currency.transfer(feeReceiver, _p2pFee);
        USDinOrder -= amountUSD;
        p2p[_orderOwner].remainCurrency -= amountUSD;
        //require approve from ISLAMICOIN contract
        ISLAMI.transferFrom(msg.sender, seller, toReceive);
        _currency.transfer(msg.sender, amountUSD.sub(_p2pFee));
          if(amountUSD == p2p[_orderOwner].remainCurrency){
                p2p[_orderOwner].orderStatus = true;
                canCreateOrder[p2p[_orderOwner].sB] = true;
                orderFilled();
                buyOrders--;
            }
        }
    }
}
 

// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface iGoldContract {
    function getIGoldPrice() external returns (int256);
    function getIslamiPrice(uint256 payQuoteAmount) external returns (uint256 _price);
    function sell(uint256 _iGoldAmount) external;
}

contract iQrad_V1 is Ownable {
    iGoldContract public iGoldc =
        iGoldContract(0x9440146ea1dF0142eE1892602416DA896c7876E8);

    address public deadWallet = 0x000000000000000000000000000000000000dEaD;

    address public islamiToken = 0x9c891326Fd8b1a713974f73bb604677E1E63396D;
    address public iGoldToken = 0x9440146ea1dF0142eE1892602416DA896c7876E8;
    address public usdtToken = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F;

    address public feeReceiver = 0x1be6cF82aC405cC46D35895262Fa83f582D42884;

    uint256 public oneTimeFee = 10000 * (1e7); // 10,000 ISLAMI

    uint256 public usdtVault;
    uint256 public usdtInLoans;
    uint256 public iGoldVault;
    uint256 public iGoldSold;
    address[] investors;

    enum LoanStatus {
        NONE,
        ACTIVE,
        DEFAULTED,
        CLOSED
    }
    enum LoanTenure {
        NONE,
        SIX_MONTHS,
        ONE_YEAR,
        TWO_YEARS
    }

    struct AngelInvestor {
        uint256 vault;
        uint256 depositAmount;
        uint256 depositTime;
        uint256 duration;
    }

    struct User {
        bool hasFile;
        uint256 collateral;
        uint256 loanAmount;
        uint256 monthlyFee;
        uint256 lastPaymentTime;
        address angel;
        uint256 vaultUsed;
        LoanStatus status;
        LoanTenure tenure;
    }

    mapping(address => mapping(uint256 => AngelInvestor)) public angelInvestors;
    mapping(address => uint256) private nextVaultId;
    mapping(address => User) public users;
    mapping(address => bool) public isInvestor;

    event AngelInvestorDeposited(
        address indexed investor,
        uint256 vaultID,
        uint256 amount
    );
    event AngelInvestorWithdrawn(
        address indexed investor,
        uint256 vaultID,
        uint256 amount
    );
    event FileOpened(address indexed user);
    event CollateralDeposited(address indexed user, uint256 amount);
    event LoanTaken(address indexed user, uint256 amount);
    event MonthlyPaymentMade(address indexed user, uint256 amount);
    event LoanDefaulted(address indexed user);
    event LoanClosed(address indexed user);
    event LoanRepaid(address indexed user);
    event CollateralWithdrawn(address indexed user, uint256 amount);

    modifier hasFile(address _user) {
        require(users[_user].hasFile, "File not opened");
        _;
    }

    modifier hasActiveLoan(address _user) {
        require(users[_user].status == LoanStatus.ACTIVE, "No active loan");
        _;
    }

    constructor() {
        IERC20(islamiToken).approve(iGoldToken, type(uint256).max);
    }

    function approveISLAMI() external {
        // Approve the iGoldToken contract to spend the caller's ISLAMI tokens
        bool success = IERC20(islamiToken).approve(
            iGoldToken,
            type(uint256).max
        );
        require(success, "ISLAMI approval failed");
    }

    function depositAsAngelInvestor(uint256 amount, uint256 _duration)
        external
    {
        require(amount > 0, "Deposit amount must be greater than 0");
        require(_duration >= 9, "Deposite should be at least for 9 Months");
        uint256 vaultId = nextVaultId[msg.sender];
        if (vaultId == 0) {
            vaultId = 1;
        }

        require(
            IERC20(usdtToken).transferFrom(msg.sender, address(this), amount),
            "Deposit failed"
        );

        AngelInvestor storage investor = angelInvestors[msg.sender][vaultId];
        investor.depositAmount += amount;
        investor.vault = vaultId; // Set the vault ID
        investor.depositTime = block.timestamp; // Set the deposit time
        investor.duration = (_duration * 30 days) + block.timestamp;

        usdtVault += amount;
        nextVaultId[msg.sender]++; // Increment the vault ID for the next deposit

        if (!isInvestor[msg.sender]) {
            isInvestor[msg.sender] = true;
            investors.push(msg.sender);
        }

        emit AngelInvestorDeposited(msg.sender, vaultId, amount);
    }

    function getInvestorVaults(address investor)
        external
        view
        returns (AngelInvestor[] memory)
    {
        uint256 vaultCount = nextVaultId[investor];
        AngelInvestor[] memory investorVaults = new AngelInvestor[](vaultCount);

        for (uint256 i = 0; i < vaultCount; i++) {
            AngelInvestor storage vault = angelInvestors[investor][i];
            investorVaults[i] = vault;
        }

        return investorVaults;
    }

    function withdrawFromAngelInvestor(uint256 vaultId, uint256 amount)
        external
    {
        require(vaultId < nextVaultId[msg.sender], "Invalid vault ID");
        AngelInvestor storage investor = angelInvestors[msg.sender][vaultId];
        require(
            investor.depositAmount >= amount,
            "Insufficient deposit amount"
        );
        require(block.timestamp >= investor.duration, "Withdraw is not yet");

        require(
            IERC20(usdtToken).transfer(msg.sender, amount),
            "Withdrawal failed"
        );

        usdtVault -= amount;
        investor.depositAmount -= amount;

        if (investor.depositAmount == 0) {
            investor.depositTime = 0;
            investor.vault = 0; // Consider resetting the vault ID if needed
        }

        emit AngelInvestorWithdrawn(msg.sender, vaultId, amount);
    }

    function takeLoan(uint256 collateralAmount, LoanTenure tenure) external {
        // Step 1: Open File
        if(!users[msg.sender].hasFile){
            _openFile(msg.sender);
        }

        // Step 2: Deposit Collateral
        _depositCollateral(msg.sender, collateralAmount);

        // Step 3: Take Loan
        _takeLoan(msg.sender, collateralAmount, tenure);
    }

    function _openFile(address user) internal {
        uint256 toBurn = (oneTimeFee * 40) / 100;
        uint256 toFee = (oneTimeFee * 60) / 100;
        require(
            IERC20(islamiToken).transferFrom(user, address(this), oneTimeFee),
            "Fee transfer failed"
        );
        IERC20(islamiToken).transfer(deadWallet, toBurn);
        IERC20(islamiToken).transfer(feeReceiver, toFee);
        users[user].hasFile = true;
        emit FileOpened(user);
    }

    function _depositCollateral(address user, uint256 amount)
        internal
        hasFile(user)
    {
        require(
            IERC20(iGoldToken).transferFrom(user, address(this), amount),
            "Transfer failed"
        );
        iGoldVault += amount;
        users[user].collateral += amount;
        emit CollateralDeposited(user, amount);
    }

    function _takeLoan(
        address user,
        uint256 collateralAmount,
        LoanTenure tenure
    ) internal hasFile(user) {
        uint256 iGoldPrice = uint256(iGoldContract(iGoldToken).getIGoldPrice());
        require(iGoldPrice > 0, "Invalid iGold price");

        // Calculate the total value of the iGold collateral
        uint256 collateralValue = collateralAmount * iGoldPrice;

        // Calculate the maximum loan amount as 70% of the collateral value
        uint256 amount = ((collateralValue * 70) / 100) / (1e2); //(1e2) to handel the decimal difference

        // uint256 islamiFee = iGoldc.getIslamiPrice(amount / 100);

        // require(IERC20(islamiToken).transferFrom(user, address(this), islamiFee));

        require(
            IERC20(usdtToken).balanceOf(address(this)) >= amount,
            "Insufficient USDT in vaults"
        );

        // Select a vault from which to take the loan
        (, uint256 selectedVaultId) = _selectVaultForLoan(amount, tenure);
        (address _angel, ) = _selectVaultForLoan(amount, tenure);
        require(selectedVaultId != 0, "No suitable vault found for loan");

        uint256 monthlyFee = amount / uint256(tenure);

        // Deduct the loan amount from the selected vault
        AngelInvestor storage investor = angelInvestors[_angel][
            selectedVaultId
        ];
        investor.depositAmount -= amount;

        usdtInLoans += amount;
        usdtVault -= amount;

        users[user].loanAmount = amount;
        users[user].monthlyFee = monthlyFee;
        users[user].lastPaymentTime = block.timestamp;
        users[user].vaultUsed = selectedVaultId;
        users[user].angel = _angel;
        users[user].status = LoanStatus.ACTIVE;
        users[user].tenure = tenure;

        emit LoanTaken(user, amount);
        IERC20(usdtToken).transfer(user, amount);
    }

    function _selectVaultForLoan(uint256 loanAmount, LoanTenure tenure)
        internal
        view
        returns (address, uint256)
    {
        uint256 tenureDuration = _getTenureDuration(tenure);
        uint256 earliestEndTime = block.timestamp + tenureDuration;
        uint256 selectedVaultId = 0;
        address investorAddress;
        uint256 selectedVaultEndTime = type(uint256).max;

        // Iterate over all investors
        for (uint256 i = 0; i < investors.length; i++) {
            investorAddress = investors[i];
            uint256 vaultCount = nextVaultId[investorAddress];

            // Iterate over all vaults for each investor
            for (uint256 vaultId = 1; vaultId <= vaultCount; vaultId++) {
                AngelInvestor storage vault = angelInvestors[investorAddress][
                    vaultId
                ];

                // Check if the vault has enough USDT and the duration is suitable
                if (
                    vault.depositAmount >= loanAmount &&
                    vault.duration >= earliestEndTime
                ) {
                    // Select the vault with the earliest end time that meets the criteria
                    if (vault.duration < selectedVaultEndTime) {
                        selectedVaultId = vaultId;
                        selectedVaultEndTime = vault.duration;
                    }
                }
            }
        }

        return (investorAddress, selectedVaultId);
    }

    function _getTenureDuration(LoanTenure tenure)
        internal
        pure
        returns (uint256)
    {
        if (tenure == LoanTenure.SIX_MONTHS) {
            return 180 days;
        } else if (tenure == LoanTenure.ONE_YEAR) {
            return 365 days;
        } else if (tenure == LoanTenure.TWO_YEARS) {
            return 730 days;
        } else {
            revert("Invalid loan tenure");
        }
    }

    function makeMonthlyPayment() external hasActiveLoan(msg.sender) {
        User storage user = users[msg.sender];
        require(
            block.timestamp >= users[msg.sender].lastPaymentTime + 30 days,
            "Too early"
        );
        require(
            IERC20(usdtToken).transferFrom(
                msg.sender,
                address(this),
                user.monthlyFee
            ),
            "Payment failed"
        );

        // Update the state to reflect the payment
        usdtInLoans -= user.monthlyFee;
        usdtVault += user.monthlyFee;
        user.lastPaymentTime = block.timestamp;
        emit MonthlyPaymentMade(msg.sender, users[msg.sender].monthlyFee);

        AngelInvestor storage investor = angelInvestors[user.angel][
            user.vaultUsed
        ];
        investor.depositAmount += user.monthlyFee;

        user.loanAmount -= user.monthlyFee;

        // Check if this is the last payment
        if (user.loanAmount == 0) {
            closeLoan(msg.sender);
        }
    }

    function handleDefault(address _user) public hasActiveLoan(_user) {
        User storage user = users[_user];
        require(
            block.timestamp >= user.lastPaymentTime + 30 days,
            "Not a default case"
        );

        // Get the current price of iGold in terms of USDT
        int256 iGoldPrice = iGoldc.getIGoldPrice() / (1e2);
        require(iGoldPrice > 0, "Invalid iGold price");

        // Calculate the amount of iGold needed to cover the unpaid monthly fee
        uint256 iGoldNeeded = (user.monthlyFee / uint256(iGoldPrice)) * (1e8);

        // Ensure the user has enough iGold collateral to cover the unpaid monthly fee
        require(
            user.collateral >= iGoldNeeded,
            "Insufficient iGold collateral to cover unpaid fee"
        );

        // Execute the sell function in the iGold contract
        iGoldc.sell(iGoldNeeded);

        // Update the iGold and USDT vault balances
        iGoldVault -= iGoldNeeded;
        usdtVault += user.monthlyFee;

        // Update investor vault
        AngelInvestor storage investor = angelInvestors[user.angel][
            user.vaultUsed
        ];
        investor.depositAmount += user.monthlyFee;

        // Update the user's iGold collateral and last payment time
        user.collateral -= iGoldNeeded;
        user.lastPaymentTime = block.timestamp;

        // Check if this is the last payment
        if (user.loanAmount == 0) {
            closeLoan(_user);
        } else {
            emit LoanDefaulted(_user);
        }
    }

    function closeLoan(address _user) internal hasActiveLoan(_user) {
        User storage user = users[_user];

        // Check if the entire loan amount has been repaid
        require(
            user.loanAmount == 0,
            "Loan amount must be fully repaid to close the loan"
        );

        // Calculate the remaining collateral to be returned
        uint256 remainingCollateral = user.collateral;

        // Transfer the remaining collateral back to the user
        require(
            IERC20(iGoldToken).transfer(_user, remainingCollateral),
            "Collateral transfer failed"
        );

        // Update the user's loan status to CLOSED
        user.status = LoanStatus.CLOSED;

        // Reset other loan-related variables
        user.collateral = 0;
        user.loanAmount = 0;
        user.monthlyFee = 0;
        user.lastPaymentTime = 0;
        user.vaultUsed = 0;
        user.angel = address(0);
        user.tenure = LoanTenure.NONE;

        emit LoanClosed(_user);
    }

    function repayLoan() external hasActiveLoan(msg.sender) {
        uint256 remainingLoan = users[msg.sender].loanAmount;
        require(
            IERC20(usdtToken).transferFrom(
                msg.sender,
                address(this),
                remainingLoan
            ),
            "Repayment failed"
        );

        users[msg.sender].loanAmount = 0;
        users[msg.sender].status = LoanStatus.CLOSED;

        // Transfer back the collateral to the user
        uint256 collateral = users[msg.sender].collateral;
        require(
            IERC20(iGoldToken).transfer(msg.sender, collateral),
            "Collateral transfer failed"
        );

        users[msg.sender].collateral = 0;

        emit LoanRepaid(msg.sender);
    }

    function withdrawCollateral(uint256 amount) external hasFile(msg.sender) {
        require(
            users[msg.sender].status == LoanStatus.CLOSED,
            "Loan not closed"
        );
        require(
            users[msg.sender].collateral >= amount,
            "Insufficient collateral"
        );

        require(
            IERC20(iGoldToken).transfer(msg.sender, amount),
            "Collateral withdrawal failed"
        );
        users[msg.sender].collateral -= amount;

        emit CollateralWithdrawn(msg.sender, amount);
    }

    function updateOneTimeFee(uint256 newFee) external onlyOwner {
        oneTimeFee = newFee;
    }
}

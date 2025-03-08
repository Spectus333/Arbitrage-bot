// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IDexRouter {
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
}

interface IERC20 {
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract ArbitrageBot {
    address public owner;
    mapping(address => bool) public allowedDexRouters;
    uint256 public gasPrice = 20 gwei; // Default gas price (adjust based on network conditions)
    uint256 public dexFee = 30; // 0.3% fee (e.g., PancakeSwap fee)

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    // Add a DEX router to the allowed list
    function addDexRouter(address _router) external onlyOwner {
        allowedDexRouters[_router] = true;
    }

    // Remove a DEX router from the allowed list
    function removeDexRouter(address _router) external onlyOwner {
        allowedDexRouters[_router] = false;
    }

    // Set gas price (in wei)
    function setGasPrice(uint256 _gasPrice) external onlyOwner {
        gasPrice = _gasPrice;
    }

    // Set DEX fee (in basis points, e.g., 30 = 0.3%)
    function setDexFee(uint256 _dexFee) external onlyOwner {
        dexFee = _dexFee;
    }

    // Calculate gas cost for a transaction
    function calculateGasCost(uint256 _gasLimit) internal view returns (uint256) {
        return _gasLimit * gasPrice;
    }

    // Check for simple arbitrage within a single DEX
    function checkSimpleArbitrage(
        address _router,
        uint256 _amountIn,
        address[] memory _path
    ) external view returns (bool, uint256) {
        require(allowedDexRouters[_router], "Router not allowed");

        // Get amounts out
        uint256[] memory amounts = IDexRouter(_router).getAmountsOut(_amountIn, _path);
        uint256 amountOut = amounts[amounts.length - 1];

        // Deduct DEX fee (0.3%)
        uint256 fee = (amountOut * dexFee) / 10000;
        uint256 amountAfterFee = amountOut - fee;

        // Deduct gas cost (estimate gas for 2 transactions: approve + swap)
        uint256 gasCost = calculateGasCost(200000); // Adjust gas limit as needed
        uint256 profit = amountAfterFee - _amountIn - gasCost;

        return (profit > 0, profit);
    }

    // Check for triangular arbitrage across multiple DEXs
    function checkTriangularArbitrage(
        address _routerA,
        address _routerB,
        address _routerC,
        uint256 _amountIn,
        address[] memory _pathA,
        address[] memory _pathB,
        address[] memory _pathC
    ) external view returns (bool, uint256) {
        require(allowedDexRouters[_routerA], "Router A not allowed");
        require(allowedDexRouters[_routerB], "Router B not allowed");
        require(allowedDexRouters[_routerC], "Router C not allowed");

        // Get amounts out for each path
        uint256[] memory amountsA = IDexRouter(_routerA).getAmountsOut(_amountIn, _pathA);
        uint256[] memory amountsB = IDexRouter(_routerB).getAmountsOut(amountsA[amountsA.length - 1], _pathB);
        uint256[] memory amountsC = IDexRouter(_routerC).getAmountsOut(amountsB[amountsB.length - 1], _pathC);

        // Deduct DEX fees (0.3% per swap)
        uint256 feeA = (amountsA[amountsA.length - 1] * dexFee) / 10000;
        uint256 feeB = (amountsB[amountsB.length - 1] * dexFee) / 10000;
        uint256 feeC = (amountsC[amountsC.length - 1] * dexFee) / 10000;

        uint256 amountAfterFees = amountsC[amountsC.length - 1] - feeA - feeB - feeC;

        // Deduct gas cost (estimate gas for 6 transactions: 3 approves + 3 swaps)
        uint256 gasCost = calculateGasCost(600000); // Adjust gas limit as needed
        uint256 profit = amountAfterFees - _amountIn - gasCost;

        return (profit > 0, profit);
    }

    // Execute simple arbitrage
    function executeSimpleArbitrage(
        address _router,
        uint256 _amountIn,
        address[] memory _path
    ) external onlyOwner {
        require(allowedDexRouters[_router], "Router not allowed");

        // Transfer tokens to the bot (assumes the bot has approval to spend the tokens)
        IERC20(_path[0]).transferFrom(msg.sender, address(this), _amountIn);

        // Approve and swap
        IERC20(_path[0]).approve(_router, _amountIn);
        IDexRouter(_router).swapExactTokensForTokens(
            _amountIn,
            0, // Accept any amount out (no slippage protection for simplicity)
            _path,
            msg.sender, // Send profit to the owner
            block.timestamp + 300
        );
    }

    // Execute triangular arbitrage
    function executeTriangularArbitrage(
        address _routerA,
        address _routerB,
        address _routerC,
        uint256 _amountIn,
        address[] memory _pathA,
        address[] memory _pathB,
        address[] memory _pathC
    ) external onlyOwner {
        require(allowedDexRouters[_routerA], "Router A not allowed");
        require(allowedDexRouters[_routerB], "Router B not allowed");
        require(allowedDexRouters[_routerC], "Router C not allowed");

        // Transfer tokens to the bot (assumes the bot has approval to spend the tokens)
        IERC20(_pathA[0]).transferFrom(msg.sender, address(this), _amountIn);

        // Swap on Router A
        IERC20(_pathA[0]).approve(_routerA, _amountIn);
        IDexRouter(_routerA).swapExactTokensForTokens(
            _amountIn,
            0, // Accept any amount out
            _pathA,
            address(this),
            block.timestamp + 300
        );

        // Swap on Router B
        uint256 amountOutA = IERC20(_pathA[_pathA.length - 1]).balanceOf(address(this));
        IERC20(_pathA[_pathA.length - 1]).approve(_routerB, amountOutA);
        IDexRouter(_routerB).swapExactTokensForTokens(
            amountOutA,
            0, // Accept any amount out
            _pathB,
            address(this),
            block.timestamp + 300
        );

        // Swap on Router C
        uint256 amountOutB = IERC20(_pathB[_pathB.length - 1]).balanceOf(address(this));
        IERC20(_pathB[_pathB.length - 1]).approve(_routerC, amountOutB);
        IDexRouter(_routerC).swapExactTokensForTokens(
            amountOutB,
            0, // Accept any amount out
            _pathC,
            msg.sender, // Send profit to the owner
            block.timestamp + 300
        );
    }

    // Withdraw tokens (emergency use)
    function withdrawToken(address _token, uint256 _amount) external onlyOwner {
        IERC20(_token).transfer(owner, _amount);
    }
}

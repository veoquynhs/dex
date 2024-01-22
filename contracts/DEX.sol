// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./ERC20.sol";

contract DEX {
    // Declare 2 tokens
    IERC20Metadata public immutable token0;
    IERC20Metadata public immutable token1;

    // Declare the balance of 2 tokens in the contract
    uint public reserve0;
    uint public reserve1;

    // When a user provide or remove liquidity, we will need to mint/burn shares
    uint public totalShares; // Total shares
    mapping(address => uint) public sharesOf; // Shares per user

    // Constructor
    constructor(address _token0, address _token1) {
        token0 = IERC20Metadata(_token0);
        token1 = IERC20Metadata(_token1);
    }

    ////////////////////////
    // Internal functions //
    ////////////////////////

    // Mint shares to an address
    function _mint(address _to, uint _amount) private {
        sharesOf[_to] += _amount;
        totalShares += _amount;
    }

    // Burn shares from an address
    function _burn(address _from, uint _amount) private {
        sharesOf[_from] -= _amount;
        totalShares -= _amount;
    }

    // Update the reserves
    function _update(uint _reserve0, uint _reserve1) private {
        reserve0 = _reserve0;
        reserve1 = _reserve1;
    }

    // Get the square of a number
    function _sqrt(uint y) private pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    // Get the smaller one between 2 numbers
    function _min(uint x, uint y) private pure returns (uint) {
        return x <= y ? x : y;
    }

    ////////////////////////
    // External functions //
    ////////////////////////

    // Swap function
    // Users can call swap to do a trade between token 0 and token 1 or vice versa
    function swap(address _tokenIn, uint _amountIn) external returns (uint amountOut) {
        // Check token in
        require(_tokenIn == address(token0) || _tokenIn == address(token1), "invalid token");

        // Check amount in
        require(_amountIn > 0, "amount in must greater than zero");

        // Point the token that the seller is selling
        bool isToken0 = _tokenIn == address(token0);
        (
            IERC20Metadata tokenIn,
            IERC20Metadata tokenOut,
            uint reserveIn,
            uint reserveOut
        ) = isToken0 ? (token0, token1, reserve0, reserve1) : (token1, token0, reserve1, reserve0);

        // Transfer token in
        tokenIn.transferFrom(
            msg.sender,
            address(this),
            _amountIn * 10 ** uint256(tokenIn.decimals())
        );

        // Calculate token out (include fees), fee 0.3%
        /*
        How much dy for dx?

        // x = current x's balance
        // y = current y's balance
        // dx = amount x in
        // dy = amount y out

        => dy = ydx / (x + dx)
        */

        // 0.3% fee
        // amountInWithFee = (_amountIn * 997) / 1000;
        amountOut =
            ((reserveOut * (_amountIn * 997)) / 1000) /
            (reserveIn + (_amountIn * 997) / 1000);

        // Transfer token out
        tokenOut.transfer(msg.sender, amountOut * 10 ** uint256(tokenOut.decimals()));

        // Update the reserves
        _update(
            token0.balanceOf(address(this)) / (10 ** uint256(token0.decimals())),
            token1.balanceOf(address(this)) / (10 ** uint256(token1.decimals()))
        );
    }

    function addLiquidity(uint _amount0, uint _amount1) external returns (uint shares) {
        // Check amount in
        require(_amount0 > 0 && _amount1 > 0, "amount in must greater than zero");

        // Pull in token 0 and token 1
        token0.transferFrom(msg.sender, address(this), _amount0 * 10 ** uint256(token0.decimals()));
        token1.transferFrom(msg.sender, address(this), _amount1 * 10 ** uint256(token1.decimals()));

        // Check amount in
        /*
        How much dx, dy to add?

        => dx / dy = x / y
        */
        if (reserve0 > 0 || reserve1 > 0) {
            require(reserve0 * _amount1 == reserve1 * _amount0, "dx / dy != x / y");
        }

        /*
        How much shares to mint?

        f(x, y) = value of liquidity = sqrt(xy)

        L0 = f(x, y)
        L1 = f(x + dx, y + dy)
        T = total shares
        s = shares to mint

        => s = (dx / x) * T = (dy / y) * T
        */

        // If T = 0 => s = sqrt(dx * dy)
        if (totalShares == 0) {
            shares = _sqrt(_amount0 * _amount1);
        } else {
            shares = _min((_amount0 * totalShares) / reserve0, (_amount1 * totalShares) / reserve1);
        }

        // Check shares
        require(shares > 0, "shares must greater than zero");

        // Mint shares
        _mint(msg.sender, shares);

        // Update the reserves
        _update(
            token0.balanceOf(address(this)) / (10 ** uint256(token0.decimals())),
            token1.balanceOf(address(this)) / (10 ** uint256(token1.decimals()))
        );
    }

    function removeLiquidity(uint _shares) external returns (uint amount0, uint amount1) {
        // Check shares
        require(_shares > 0, "shares must greater than zero");
        require(_shares <= sharesOf[msg.sender], "not enough shares");

        /*
        Claim
        dx, dy = amount of token to remove

        => dx = x * s / T
        => dy = y * s / T
        */

        // Get balance
        uint bal0 = token0.balanceOf(address(this)) / (10 ** uint256(token0.decimals()));
        uint bal1 = token1.balanceOf(address(this)) / (10 ** uint256(token1.decimals()));

        // Calculate amount out
        amount0 = (bal0 * _shares) / totalShares;
        amount1 = (bal1 * _shares) / totalShares;

        // Check amount out
        require(amount0 > 0 && amount1 > 0, "amount out must greater than zero");

        // Burn shares
        _burn(msg.sender, _shares);

        // Update the reserves
        _update(bal0 - amount0, bal1 - amount1);

        // Transfer the token out
        token0.transfer(msg.sender, amount0 * 10 ** token0.decimals());
        token1.transfer(msg.sender, amount1 * 10 ** token1.decimals());
    }
}

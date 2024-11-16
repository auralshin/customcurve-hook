// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {FixedPointMathLib} from "./libraries/FixedPointMathLib.sol";

contract LammbertHook is BaseHook {
    using PoolIdLibrary for PoolKey;
    using SafeCast for uint256;
    using CurrencySettler for Currency;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {
        poolManager = _poolManager;
    }

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: true,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function calcOneOverC(
        uint256 constantValue
    ) internal pure returns (int256) {
        return FixedPointMathLib.sDivWad(1, int256(constantValue));
    }

    function calcExpInput(
        uint256 constantValue,
        uint256 value
    ) internal pure returns (uint256) {
        return FixedPointMathLib.rawSub((2 * constantValue), value);
    }

    function calcLambertInput(
        uint256 constantValue,
        uint256 value,
        uint256 expTerm
    ) internal pure returns (uint256) {
        return
            uint256(
                FixedPointMathLib.sDivWad(
                    int256(
                        (uint256(constantValue) * uint256(expTerm / 10000e60))
                    ),
                    int256(value)
                )
            );
    }

    function getAmountOutFromExactInput(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut,
        Currency,
        Currency,
        bool
    ) internal pure returns (uint256 amountOut) {
        require(reserveIn > 0 && reserveOut > 0, "Reserves must be positive");
        require(
            reserveIn <= type(uint256).max / reserveOut,
            "Reserve product overflow"
        );
        uint256 c = uint256(
            FixedPointMathLib.sDivWad(int256(reserveIn * reserveOut), 1e36)
        );
        int256 oneOverC = calcOneOverC(c);

        uint256 expInput = calcExpInput(c, amountIn);

        uint256 maxExpInput = 135305999368893231588; // Safe cap
        if (expInput > maxExpInput) {
            expInput = maxExpInput;
        }

        int256 expTerm = FixedPointMathLib.expWad(int256(expInput));

        uint256 lambertInput = calcLambertInput(c, amountIn, uint256(expTerm));

        int256 lambertResult = FixedPointMathLib.lambertW0Wad(
            int256(lambertInput)
        );

        amountOut = (uint256(oneOverC) * uint256(lambertResult));
    }

    function getAmountInForExactOutput(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut,
        Currency,
        Currency,
        bool
    ) internal pure returns (uint256 amountIn) {
        require(reserveIn > 0 && reserveOut > 0, "Reserves must be positive");
        require(
            reserveIn <= type(uint256).max / reserveOut,
            "Reserve product overflow"
        );
        uint256 c = (reserveIn * reserveOut) / 1e36;

        uint256 scaledOutput = (amountOut * uint256(c));

        int256 lambertResult = FixedPointMathLib.lambertW0Wad(
            int256(scaledOutput)
        );

        uint256 expArgument = FixedPointMathLib.rawSub(
            (2 * uint256(c)),
            uint256(lambertResult)
        );

        int256 expTerm = FixedPointMathLib.expWad(int256(expArgument));

        amountIn = uint256(
            FixedPointMathLib.divWad(
                (uint256(c) * uint256(expTerm / 10000e60)),
                uint256(lambertResult)
            )
        );
    }

    // -----------------------------------------------
    // NOTE: see IHooks.sol for function documentation
    // -----------------------------------------------

    function beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata
    ) external override returns (bytes4, BeforeSwapDelta, uint24) {
        bool exactInput = params.amountSpecified < 0;
        (Currency specified, Currency unspecified) = (params.zeroForOne ==
            exactInput)
            ? (key.currency0, key.currency1)
            : (key.currency1, key.currency0);

        uint256 specifiedAmount = exactInput
            ? uint256(-params.amountSpecified)
            : uint256(params.amountSpecified);

        uint256 balanceOfSpecified = specified.balanceOf(address(this));
        uint256 balanceOfUnspecified = unspecified.balanceOf(address(this));

        uint256 unspecifiedAmount;
        BeforeSwapDelta returnDelta;
        if (exactInput) {
            unspecifiedAmount = getAmountOutFromExactInput(
                specifiedAmount,
                balanceOfSpecified,
                balanceOfUnspecified,
                specified,
                unspecified,
                params.zeroForOne
            );

            poolManager.take(specified, address(this), specifiedAmount);

            unspecified.settle(
                poolManager,
                address(this),
                unspecifiedAmount,
                false
            );
            returnDelta = toBeforeSwapDelta(
                specifiedAmount.toInt128(),
                -unspecifiedAmount.toInt128()
            );
        } else {
            unspecifiedAmount = getAmountInForExactOutput(
                specifiedAmount,
                balanceOfUnspecified,
                balanceOfSpecified,
                unspecified,
                specified,
                params.zeroForOne
            );
            poolManager.take(unspecified, address(this), unspecifiedAmount);
            specified.settle(
                poolManager,
                address(this),
                specifiedAmount,
                false
            );

            returnDelta = toBeforeSwapDelta(
                -specifiedAmount.toInt128(),
                unspecifiedAmount.toInt128()
            );
        }

        return (BaseHook.beforeSwap.selector, returnDelta, 0);
    }
}

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

contract StableHook is BaseHook {
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

    /**
     * lambert equation :
     * y = ( 1 / c ) * (LambertW((c * e ** (2c - x)) / x))
     */

    // Constant for Lammber
    /**
     * c = (reserve of x * reserve of y) / Price
     */

    // function getAmountOutFromExactInput(
    //     uint256 amountIn,
    //     uint256 reserveIn,
    //     uint256 reserveOut,
    //     Currency,
    //     Currency,
    //     bool
    // ) internal pure returns (uint256 amountOut) {
    //     int256 c = 100 ether;

    //     int256 oneOverC = FixedPointMathLib.sDivWad(1 ether, c); // Scaled for precision

    //     int256 expInput = int256(
    //         FixedPointMathLib.rawSub(
    //             FixedPointMathLib.mulWad(2 ether, uint256(c)),
    //             amountIn
    //         )
    //     );
    //     int256 maxExpInput = 135305999368893231588;
    //     if (expInput > maxExpInput) {
    //         expInput = maxExpInput;
    //     }

    //     int256 expTerm = FixedPointMathLib.expWad(expInput);

    //     int256 lambertInput = FixedPointMathLib.sDivWad(
    //         int256(FixedPointMathLib.mulWad(uint256(c), uint256(expTerm))),
    //         int256(amountIn)
    //     );

    //     int256 lambertResult = FixedPointMathLib.lambertW0Wad(
    //         int256(lambertInput)
    //     );

    //     amountOut = FixedPointMathLib.mulWad(
    //         uint256(oneOverC),
    //         uint256(lambertResult)
    //     );
    // }

    // function getAmountInForExactOutput(
    //     uint256 amountOut,
    //     uint256 reserveIn,
    //     uint256 reserveOut,
    //     Currency,
    //     Currency,
    //     bool
    // ) internal pure returns (uint256 amountIn) {
    //     int256 c = 100000 ether;

    //     uint256 scaledOutput = FixedPointMathLib.mulWad(amountOut, uint256(c));

    //     int256 lambertResult = FixedPointMathLib.lambertW0Wad(
    //         int256(scaledOutput)
    //     );

    //     uint256 expArgument = FixedPointMathLib.rawSub(
    //         FixedPointMathLib.mulWad(2 ether, uint256(c)),
    //         uint256(lambertResult)
    //     );

    //     int256 expTerm = FixedPointMathLib.expWad(int256(expArgument));

    //     amountIn = uint256(
    //         FixedPointMathLib.divWad(
    //             FixedPointMathLib.mulWad(uint256(c), uint256(expTerm)),
    //             uint256(lambertResult)
    //         )
    //     );
    // }

    function getAmountOutFromExactInput(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut,
        Currency,
        Currency,
        bool
    ) internal pure returns (uint256 amountOut) {
        uint256 weightA = 5e17; // 0.5 * 1e18
        uint256 weightB = 5e17; // 0.5 * 1e18
        // invariant: R_in^w_in * R_out^w_out = k
        uint256 newReserveIn = reserveIn + amountIn;

        uint256 invariant = FixedPointMathLib.mulWad(
            uint256(
                FixedPointMathLib.powWad(int256(reserveIn), int256(weightA))
            ),
            uint256(
                FixedPointMathLib.powWad(int256(reserveOut), int256(weightB))
            )
        );

        int256 newReserveOut = FixedPointMathLib.powWad(
            int256(
                FixedPointMathLib.divWad(
                    invariant,
                    uint256(
                        FixedPointMathLib.powWad(
                            int256(newReserveIn),
                            int256(weightA)
                        )
                    )
                )
            ),
            int256(FixedPointMathLib.divWad(1 ether, weightB))
        );

        amountOut = reserveOut - uint256(newReserveOut);
    }

    function getAmountInForExactOutput(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut,
        Currency,
        Currency,
        bool
    ) internal pure returns (uint256 amountIn) {
        uint256 weightA = 5e17; // 0.5 * 1e18
        uint256 weightB = 5e17; // 0.5 * 1e18
        // invariant: R_in^w_in * R_out^w_out = k
        uint256 newReserveOut = reserveOut - amountOut;

        uint256 invariant = FixedPointMathLib.mulWad(
            uint256(
                FixedPointMathLib.powWad(int256(reserveIn), int256(weightA))
            ),
            uint256(
                FixedPointMathLib.powWad(int256(reserveOut), int256(weightB))
            )
        );
        int256 newReserveIn = FixedPointMathLib.powWad(
            int256(
                FixedPointMathLib.divWad(
                    invariant,
                    uint256(
                        FixedPointMathLib.powWad(
                            int256(newReserveOut),
                            int256(weightB)
                        )
                    )
                )
            ),
            int256(FixedPointMathLib.divWad(1 ether, weightA))
        );
        amountIn = uint256(newReserveIn) - reserveIn;
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

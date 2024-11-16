// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";
import {LammbertHook} from "../src/Lammbert.sol";
import {HookMiner} from "./utils/HookMiner.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {MockERC20} from "@uniswap/v4-core/lib/solmate/src/test/utils/mocks/MockERC20.sol";
import {LammbertHookImplementation} from "./utils/LammbertHookImplementation.sol";
import {HookEnabledSwapRouter} from "./utils/HookEnabledRouter.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {FixedPointMathLib} from "../src/libraries/FixedPointMathLib.sol";

import {console2} from "forge-std/console2.sol";

contract LammbertTest is Test, Deployers {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using SafeCast for uint256;
    using StateLibrary for IPoolManager;

    HookEnabledSwapRouter router;
    event Swap(
        PoolId indexed id,
        address indexed sender,
        int128 amount0,
        int128 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick,
        uint24 fee
    );

    MockERC20 token0;
    MockERC20 token1;
    MockERC20 token2;

    int24 internal constant MIN_TICK = -120;
    int24 internal constant MAX_TICK = -MIN_TICK;

    int24 constant TICK_SPACING = 60;
    uint16 constant LOCKED_LIQUIDITY = 1000;
    uint256 constant MAX_DEADLINE = 12329839823;
    uint256 constant MAX_TICK_LIQUIDITY = 11505069308564788430434325881101412;
    uint8 constant DUST = 30;

    LammbertHookImplementation lammbert =
        LammbertHookImplementation(
            address(
                uint160(
                    Hooks.BEFORE_SWAP_FLAG |
                        Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
                )
            )
        );

    PoolId id;

    // For a pool that gets initialized with liquidity in setUp()
    PoolKey keyWithLiq;
    PoolId idWithLiq;

    function setUp() public {
        deployFreshManagerAndRouters();
        (currency0, currency1) = deployMintAndApprove2Currencies();
        router = new HookEnabledSwapRouter(manager);

        token0 = MockERC20(Currency.unwrap(currency0));
        token1 = MockERC20(Currency.unwrap(currency1));

        LammbertHookImplementation impl = new LammbertHookImplementation(
            manager,
            lammbert
        );
        vm.etch(address(lammbert), address(impl).code);

        key = createPoolKey(token0, token1);
        id = key.toId();

        token0.approve(address(lammbert), type(uint256).max);
        token1.approve(address(lammbert), type(uint256).max);
        token0.approve(address(router), type(uint256).max);
        token1.approve(address(router), type(uint256).max);

        (key, id) = initPoolAndAddLiquidity(
            currency0,
            currency1,
            lammbert,
            3000,
            SQRT_PRICE_1_1
        );
    }

    function test_swap_beforeSwapCustomCurveLammbert_exactInput() public {
        key.currency0.transfer(address(lammbert), 1000e18); // Reserve for Token 0
        key.currency1.transfer(address(lammbert), 1000e18); // Reserve for Token 1

        uint256 balanceBefore0 = currency0.balanceOf(address(this));
        uint256 balanceBefore1 = currency1.balanceOf(address(this));

        uint256 amountToSwap = 1 ether; // Input amount (amountIn)

        uint256 reserveA = key.currency0.balanceOf(address(manager));
        uint256 reserveB = key.currency1.balanceOf(address(manager));

        // Lambert curve calculation for expected output
        int256 c = FixedPointMathLib.sDivWad(
            int256(reserveA * reserveB),
            int256(1e36)
        ); // Constant 'c'\

        int256 oneOverC = FixedPointMathLib.sDivWad(1, int256(c)); // Calculate 1/c

        // Calculate the exponent input for e^(2c - x)
        uint256 expInput = FixedPointMathLib.rawSub(
            uint256(2 * c),
            amountToSwap
        );

        // Cap expInput to avoid overflow
        uint256 maxExpInput = 135305999368893231588; // Safe cap
        if (expInput > maxExpInput) {
            expInput = maxExpInput;
        }
        // Compute exponential term
        int256 expTerm = FixedPointMathLib.expWad(int256(expInput));

        int256 lambertInput = FixedPointMathLib.sDivWad(
            int256((uint256(c) * uint256(expTerm / 10000e60))),
            int256(amountToSwap)
        );
        // Lambert W result
        int256 lambertResult = FixedPointMathLib.lambertW0Wad(
            int256(lambertInput)
        );
        // Expected output based on Lambert W and 1/c
        uint256 expectedAmountOut = (uint256(oneOverC) *
            uint256(lambertResult));
        // Swap parameters
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest
            .TestSettings({takeClaims: true, settleUsingBurn: true});
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: int256(amountToSwap),
            sqrtPriceLimitX96: SQRT_PRICE_1_2
        });

        // Perform the swap
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);

        // Check currency0 balance
        uint256 actualBalance0 = currency0.balanceOf(address(this));
        uint256 expectedBalance0 = balanceBefore0 - amountToSwap;
        // Check currency1 balance
        uint256 actualBalance1 = currency1.balanceOf(address(this));
        uint256 expectedBalance1 = balanceBefore1 + expectedAmountOut;

        console2.log(actualBalance0);
        console2.log(expectedBalance0);

        console2.log(actualBalance1);
        console2.log(expectedBalance1);

        assertEq(actualBalance0 / 10e70, expectedBalance0 / 10e70, "Balance 0 is not equal");

        assertEq(actualBalance1 / 10e70, expectedBalance1 / 10e70, "Balance 1 is not equal");
    }

    function createPoolKey(
        MockERC20 tokenA,
        MockERC20 tokenB
    ) internal view returns (PoolKey memory) {
        if (address(tokenA) > address(tokenB))
            (tokenA, tokenB) = (tokenB, tokenA);
        return
            PoolKey(
                Currency.wrap(address(tokenA)),
                Currency.wrap(address(tokenB)),
                3000,
                TICK_SPACING,
                lammbert
            );
    }

    function abs(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }
}

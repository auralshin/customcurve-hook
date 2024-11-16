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
import {StableHook} from "../src/Stable.sol";
import {HookMiner} from "./utils/HookMiner.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {MockERC20} from "@uniswap/v4-core/lib/solmate/src/test/utils/mocks/MockERC20.sol";
import {StableHookImplementation} from "./utils/StableHookImplementation.sol";
import {HookEnabledSwapRouter} from "./utils/HookEnabledRouter.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {FixedPointMathLib} from "../src/libraries/FixedPointMathLib.sol";

contract StableTest is Test, Deployers {
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

    StableHookImplementation stable =
        StableHookImplementation(
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

        StableHookImplementation impl = new StableHookImplementation(
            manager,
            stable
        );
        vm.etch(address(stable), address(impl).code);

        key = createPoolKey(token0, token1);
        id = key.toId();

        token0.approve(address(stable), type(uint256).max);
        token1.approve(address(stable), type(uint256).max);
        token0.approve(address(router), type(uint256).max);
        token1.approve(address(router), type(uint256).max);

        (key, id) = initPoolAndAddLiquidity(
            currency0,
            currency1,
            stable,
            3000,
            SQRT_PRICE_1_1
        );
    }

    // function test_swap_beforeSwapNoOpsSwap_exactOutput() public {
    //     key.currency0.transfer(address(stable), 10e18);
    //     key.currency1.transfer(address(stable), 10e18);

    //     uint256 balanceBefore0 = currency0.balanceOf(address(this));
    //     uint256 balanceBefore1 = currency1.balanceOf(address(this));

    //     uint256 amountToSwap = 123456;
    //     PoolSwapTest.TestSettings memory testSettings = PoolSwapTest
    //         .TestSettings({takeClaims: false, settleUsingBurn: false});
    //     IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
    //         zeroForOne: true,
    //         amountSpecified: int256(amountToSwap),
    //         sqrtPriceLimitX96: SQRT_PRICE_1_2
    //     });
    //     swapRouter.swap(key, params, testSettings, ZERO_BYTES);

    //     // the custom curve hook is 1-1 linear
    //     assertEq(
    //         currency0.balanceOf(address(this)),
    //         balanceBefore0 - amountToSwap,
    //         "amount 0"
    //     );
    //     assertEq(
    //         currency1.balanceOf(address(this)),
    //         balanceBefore1 + amountToSwap,
    //         "amount 1"
    //     );
    // }

    function test_swap_beforeSwapCustomCurve_exactInput() public {
        // Setup initial balances for the pool
        key.currency0.transfer(address(stable), 1000e18); // Reserve for Token 0
        key.currency1.transfer(address(stable), 1000e18); // Reserve for Token 1

        uint256 balanceBefore0 = currency0.balanceOf(address(this));
        uint256 balanceBefore1 = currency1.balanceOf(address(this));

        uint256 amountToSwap = 1000; // Input amount (amountIn)
        uint256 weightA = 5e17; // 0.5 * 1e18 (50% weight for Token 0)
        uint256 weightB = 5e17; // 0.5 * 1e18 (50% weight for Token 1)

        uint256 reserveA = key.currency0.balanceOf(address(manager));
        uint256 reserveB = key.currency1.balanceOf(address(manager));

        // Expected output calculation using the weighted product formula
        uint256 newReserveA = reserveA + amountToSwap;

        // Calculate the invariant (constant product of weighted reserves)
        uint256 invariant = FixedPointMathLib.mulWad(
            uint256(
                FixedPointMathLib.powWad(int256(reserveA), int256(weightA))
            ),
            uint256(FixedPointMathLib.powWad(int256(reserveB), int256(weightB)))
        );

        // Calculate the new reserve for Token B using the invariant
        int256 newReserveB = FixedPointMathLib.powWad(
            int256(
                FixedPointMathLib.divWad(
                    invariant,
                    uint256(
                        FixedPointMathLib.powWad(
                            int256(newReserveA),
                            int256(weightA)
                        )
                    )
                )
            ),
            int256(FixedPointMathLib.divWad(1 ether, weightB))
        );

        uint256 expectedAmountOut = reserveB - uint256(newReserveB);

        // Swap parameters
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest
            .TestSettings({takeClaims: false, settleUsingBurn: false});
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: int256(amountToSwap),
            sqrtPriceLimitX96: SQRT_PRICE_1_1
        });

        // Perform the swap
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);

        uint256 tolerance = 1e4;

        uint256 actualBalance0 = currency0.balanceOf(address(this));
        uint256 expectedBalance0 = balanceBefore0 - amountToSwap;

        assertTrue(
            abs(actualBalance0, expectedBalance0) <= tolerance,
            "amount 0: balance mismatch"
        );

        // Check currency1 balance
        uint256 actualBalance1 = currency1.balanceOf(address(this));
        uint256 expectedBalance1 = balanceBefore1 + expectedAmountOut;
        assertTrue(
            abs(actualBalance1, expectedBalance1) <= tolerance,
            "amount 1: balance mismatch"
        );
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
                stable
            );
    }

    function abs(uint256 a, uint256 b) internal pure returns (uint256) {
    return a > b ? a - b : b - a;
}
}

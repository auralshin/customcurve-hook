# StableHook: Invariant Curve Hook for Uniswap v4

**StableHook is a custom Invariant Curve Hook built for Uniswap v4, designed to enable trading on a custom invariant curve while leveraging the existing Uniswap pool and routing infrastructure.**

## Introduction

The StableHook modifies the trading behavior of a Uniswap pool by replacing its constant-product curve with a custom invariant curve based on reserves and token weights. While Uniswap's router finds routes and initializes swaps, the trading itself occurs on the custom curve defined within the hook.

This approach retains the efficiency and flexibility of Uniswap's infrastructure while allowing for a more tailored trading experience suited to specific use cases.

## Core Features

1. **Custom Invariant Curve:**

   - Implements a **weighted reserve invariant** similar to Balancer:
     \[
     R_A^{w_A} \cdot R_B^{w_B} = k
     \]
     Where:
     - \( R_A, R_B \): Reserves of the tokens in the pool.
     - \( w_A, w_B \): Weights of the tokens, defining their relative importance in the pool.
     - \( k \): Constant invariant maintained during swaps.

2. **Uniswap Integration:**

   - Leverages the **Uniswap v4 Pool Manager** and router for route discovery and token transfers.
   - The hook intercepts the trade logic, ensuring swaps execute on the custom curve.

3. **Efficient Trading:**
   - Supports exact input and exact output swaps.
   - Calculates swap amounts (`amountOut` and `amountIn`) based on the invariant curve logic.

---

## How It Works

1. **Pool Initialization:**

   - A Uniswap pool is initialized using the standard Uniswap v4 infrastructure.

2. **Hook Integration:**

   - The `StableHook` is deployed and linked to the pool.
   - The hook is configured to handle pre-swap logic (`beforeSwap`).

3. **Trade Execution:**
   - When a swap is routed through the Uniswap router:
     - The `StableHook` intercepts the trade.
     - Executes the swap on the **custom invariant curve** based on the pool's reserves and token weights.

---

## Curve Details

The hook uses a **weighted invariant formula** to calculate swap amounts:
\[
R_A^{w_A} \cdot R_B^{w_B} = k
\]

- **Exact Input Swap:**
  - Calculates the new reserves of the tokens after adding the input amount.
  - Computes the corresponding output amount by maintaining the invariant.
- **Exact Output Swap:**
  - Determines the required input amount by solving for the reserves that maintain the invariant.

---

## Technical Overview

### Key Functions

1. **`beforeSwap`:**

   - Intercepts the swap call from the Uniswap router.
   - Computes the `amountOut` or `amountIn` based on the invariant curve logic.
   - Adjusts token balances in the pool accordingly.

2. **`getAmountOutFromExactInput`:**

   - Computes the output amount for a given input using the invariant curve:
     \[
     \text{amountOut} = R_B - R_B'
     \]
     Where:
     - \( R_B' \): New reserve of Token B calculated by solving the invariant.

3. **`getAmountInForExactOutput`:**
   - Computes the required input amount for a desired output:
     \[
     \text{amountIn} = R_A' - R_A
     \]
     Where:
     - \( R_A' \): New reserve of Token A calculated by solving the invariant.

---

## Configuration

- **Weights:** Both tokens in the pool are assigned equal weights (50:50).
- **Precision:** Fixed-point arithmetic with \( 10^{18} \) scaling is used for calculations.

---

## Installation

### Prerequisites

- **Foundry** or a compatible Solidity development environment.
- Access to Uniswap v4 contracts.

### Setup

1. Clone the repository:

   ```bash
   git clone <repository-url>
   cd stable-hook
   ```

   #### **Install Dependencies**

   Run the following command to install all required dependencies:

```bash
forge install
```

#### **Compile Contract**

Compile the StableHook contract and other associated files:

```bash
forge build --evm-version cancun --via-ir
```

#### **Test Contract**

Use the following command to test the StableHook contract:

```bash
forge test --evm-version cancun --via-ir  -vvvv
```

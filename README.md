# CurveHooks: Custom Invariant Curve Hooks for Uniswap v4

**CurveHooks is a customizable hook-based solution for Uniswap v4, enabling trading on custom invariant curves while leveraging Uniswap's efficient pool and routing infrastructure.**

This repository contains two distinct curve implementations:

1. **Lambert Curve Hook (Lammbert):**

   - Implements a curve derived from the Lambert W function.
   - Suitable for concentrated liquidity scenarios where trades require dynamic pricing.

2. **Weighted Product Curve Hook (StableHook):**
   - Implements a weighted reserve invariant similar to Balancer.
   - Ideal for use cases requiring token weights to adjust relative importance in the pool.

---

## Introduction

The hooks modify the trading behavior of a Uniswap pool by replacing the constant-product \( x \cdot y = k \) curve with custom invariant curves. While Uniswap's router determines routes and initializes swaps, the trade itself executes on the selected custom curve.

This approach retains Uniswap's flexibility and efficiency while enabling tailored trading experiences for specific use cases.

---

## Core Features

1. **Custom Invariant Curves:**

   - Choose between two distinct invariant curve options:
     - **Lambert Curve:**  
       Uses the Lambert W function for precise and dynamic liquidity management.
     - **Weighted Product Curve:**  
       Implements a **weighted reserve invariant**:
       \[
       R_A^{w_A} \cdot R_B^{w_B} = k
       \]
       Where:
       - \( R_A, R_B \): Reserves of tokens A and B in the pool.
       - \( w_A, w_B \): Weights of tokens A and B, defining their relative importance.
       - \( k \): Constant invariant maintained during swaps.

2. **Uniswap Integration:**

   - Fully integrated with the **Uniswap v4 Pool Manager** and router for seamless route discovery and token transfers.
   - The hooks intercept trade logic, ensuring swaps execute on the selected curve.

3. **Efficient and Flexible Trading:**
   - Supports exact input and exact output swaps.
   - Dynamically computes swap amounts (`amountOut` and `amountIn`) based on the invariant curve logic.

---

## Curve Details

### 1. Lambert Curve (Lammbert Hook)

The Lambert curve uses the Lambert W function to dynamically adjust liquidity and pricing based on pool state. This curve is especially useful for concentrated liquidity and stable assets.

Key formula:
![Alt Text](https://raw.githubusercontent.com/auralshin/customcurve-hook/main/images/SCR-20241117-gmvu.png)


Where:

- \( W \): Lambert W function.
- \( c \): Liquidity concentration factor based on reserves.
- \( x, y \): Input and output amounts.

![Alt Text](https://raw.githubusercontent.com/auralshin/customcurve-hook/main/images/lammbert.svg)



---

### 2. Weighted Product Curve (StableHook)

The weighted product curve generalizes the constant-product curve by introducing token weights

Key formula:
![Alt Text](https://raw.githubusercontent.com/auralshin/customcurve-hook/main/images/SCR-20241117-gmsu.png)


  ![Alt Text](https://raw.githubusercontent.com/auralshin/customcurve-hook/main/images/weighted.svg)

---

## Configuration

- **Lambert Curve:**
  - Dynamic liquidity management based on input amounts and reserve states.
- **Weighted Product Curve:**
  - Configured with equal weights (50:50) by default. Token weights can be adjusted as needed.

---

## Installation

### Prerequisites

- **Foundry** or a compatible Solidity development environment.
- Access to Uniswap v4 contracts.

---

### Setup

1. Clone the repository:

   ```bash
   git clone https://github.com/auralshin/customcurve-hook
   cd curve-hooks
   ```

2. Install dependencies:

   ```bash
   forge install
   ```

3. Compile contracts:

   ```bash
   forge build --evm-version cancun --via-ir
   ```

4. Test the contracts:

   ```bash
   forge test --evm-version cancun --via-ir -vvvv
   ```

---

## How It Works

1. **Pool Initialization:**

   - Pools are initialized using the standard Uniswap v4 infrastructure.

2. **Hook Selection:**

   - Deploy either `LammbertHook` or `StableHook` and attach it to the pool.

3. **Trade Execution:**
   - Swaps routed through Uniswap are intercepted by the selected hook.
   - The hook executes the trade based on its custom invariant curve logic.

---

## Example Use Cases

1. **Lambert Curve Hook:**

   - Concentrated liquidity pools for stablecoins or tightly correlated assets.
   - Dynamic pricing based on reserve concentration.

2. **Weighted Product Curve Hook:**
   - Multi-token pools with variable weights for token pair importance.
   - Enhanced flexibility for liquidity providers.

---

## Results

![Result](https://raw.githubusercontent.com/auralshin/customcurve-hook/main/images/SCR-20241117-golt.png)



---

## Contributions

Contributions to enhance or extend the hook implementations are welcome! Feel free to open issues or submit pull requests.

---

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

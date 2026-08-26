# 🏛️ Fibonacci ICT Expert Advisor (MetaTrader 5)

> **Institutional-Grade Algorithmic Trading Robot combining Multi-Timeframe Fibonacci Retracement Zones with ICT (Inner Circle Trader) Price Action Concepts.**

---

<p align="center">
  <img src="https://img.shields.io/badge/Platform-MetaTrader%205-blue?style=for-the-badge&logo=metatrader5" />
  <img src="https://img.shields.io/badge/Language-MQL5-orange?style=for-the-badge" />
  <img src="https://img.shields.io/badge/Strategy-Fibonacci%20%2B%20ICT-emerald?style=for-the-badge" />
  <img src="https://img.shields.io/badge/Version-2.0.0%20Enterprise-purple?style=for-the-badge" />
  <img src="https://img.shields.io/badge/License-MIT-green?style=for-the-badge" />
</p>

## 📋 Table of Contents
- [Executive Strategy Summary](#-executive-strategy-summary)
- [System Architecture & Core Modules](#-system-architecture--core-modules)
- [Detailed Strategy Rules](#-detailed-strategy-rules)
- [Risk & Trade Management Engine](#-risk--trade-management-engine)
- [On-Chart HUD Dashboard & Visuals](#-on-chart-hud-dashboard--visuals)
- [Input Parameters Reference](#-input-parameters-reference)
- [Installation & Quick Start](#-installation--quick-start)
- [Backtesting & Optimization](#-backtesting--optimization)
- [Frequently Asked Questions (FAQ)](#-frequently-asked-questions-faq)
- [Disclaimer](#-disclaimer)

---

## 🎯 Executive Strategy Summary

The **Fibonacci ICT Expert Advisor** is a high-performance algorithmic trading robot engineered in MQL5 for MetaTrader 5. Built for institutional precision, it eliminates emotional trading by fusing two of the most powerful price action methodologies in modern technical analysis:

1. **Fibonacci Retracement Discount & Premium Pricing:** Identifying high-probability equilibrium and deep pullback levels (38.2%, 50.0%, 61.8%).
2. **Inner Circle Trader (ICT) Market Structure Concepts:** Confirming high-volume liquidity sweeps, Fair Value Gaps (FVG), Break of Structure (BOS), and Change of Character (CHoCH).

Designed specifically for **intraday trend continuation**, the system operates with multi-timeframe precision across major currency pairs and commodities including **EURUSD**, **XAUUSD (Gold)**, and **AUDJPY**.

## ⚡ System Highlights & Key Features

- 🕒 **Multi-Timeframe Structural Alignment:** 1H/4H Macro Trend Bias combined with 15M / 5M precision entry execution.
- 📐 **Dynamic Fibonacci Engine:** Real-time calculation and plotting of 38.2%, 50.0%, 61.8%, and 78.6% levels from genuine market structure swings.
- 🕯️ **ICT Confirmation Matrix:** Micro Break of Structure (BOS), Fair Value Gap (FVG) retests, Liquidity sweeps, and multi-candlestick validation.
- 🛡️ **Institutional Capital Protection:** Pre-calculated risk-per-trade percentage, automatic 1:1 Breakeven stop-lock, and 50% partial profit banking at TP1.
- 📈 **ATR Dynamic Trailing Stop:** Ride trend expansions with adaptive volatility-based trailing stops.
- 📊 **Real-Time On-Chart HUD Panel:** Dedicated 1-second timer rendering live GMT time, active session, trend bias, fib status, equity, and open positions.

## 🧭 Multi-Timeframe Trend Bias Engine

Trend direction is determined using a dual-confirmation structural model:

```
[1H / 4H Market Structure]  -->  Higher Highs (HH) & Higher Lows (HL)  -->  BULLISH BIAS
[1H / 4H Market Structure]  -->  Lower Highs (LH) & Lower Lows (LL)    -->  BEARISH BIAS
```

- **Moving Average Alignment (Optional):** When `InpUseMA = true`, price must additionally confirm trend direction against the 50 Exponential Moving Average (EMA) and 200 Simple Moving Average (SMA).
- **Responsive Intraday Adaptation:** If 4H structure is in consolidation, the EA automatically evaluates 1H structural impulses to capture intraday trends without lag.

## 📐 Fibonacci Retracement & Golden Zones

Once the macro trend is confirmed, the EA tracks the active impulse swing on the structure timeframe:

| Fibonacci Level | Ratio | Role & Strategic Significance |
| :--- | :--- | :--- |
| **Swing High / Low** | `0.0% / 100.0%` | Origin of the impulse leg and primary Take Profit target. |
| **Entry Threshold** | `38.2%` | Minimum required retracement for shallow, high-momentum trends. |
| **Equilibrium Level** | `50.0%` | Fair value midpoint where institutional liquidity accumulates. |
| **Deep Discount / OTE** | `61.8%` | Optimal Trade Entry (OTE) offering the highest Risk:Reward ratios. |
| **Invalidation Barrier** | `78.6%` | Structural invalidation threshold; breaches trigger trend reversal checks. |

### ❌ 78.6% Invalidation & Trend Shift Protocol

If price violates the 78.6% Fibonacci level during a pullback:
1. The active pullback setup is immediately cancelled.
2. The EA triggers `HandleTrendChange()`, monitoring for a **Change of Character (CHoCH)** or **Opposing BOS**.
3. If confirmed with Fair Value Gap formation, the EA transitions to the new counter-trend direction with reduced initial transition risk.

## 🔍 ICT Confirmation Matrix

The EA requires at least one primary institutional ICT trigger before entry:

### 1. Break of Structure (BOS)
- **Bullish BOS:** 15M candle closes with momentum above the high of the pullback candle, confirming buyers have re-entered the market.
- **Bearish BOS:** 15M candle closes with momentum below the low of the pullback candle, confirming seller dominance.

### 2. Change of Character (CHoCH)
- Identifies early trend reversal shifts by detecting when price breaks the most recent structural lower high in a downtrend, or structural higher low in an uptrend.
- Serves as a primary transition filter for new trend waves.

### 3. Fair Value Gap (FVG) Retests
- Detects 3-candle price imbalances where a gap exists between Candle 1's wick and Candle 3's wick.
- Price returning to fill the Fair Value Gap within the 38.2%–61.8% Fibonacci zone triggers high-probability institutional order block entries.

### 4. Candlestick Confirmation Engine
The EA validates rejection candles on the entry timeframe (15M / 5M):
- **Bullish Setups:** Pin Bar / Hammer (lower wick >= 100% of body), Bullish Engulfing, or Strong Bullish Close (> 50% range).
- **Bearish Setups:** Shooting Star (upper wick >= 100% of body), Bearish Engulfing, or Strong Bearish Close (> 50% range).

## ⏰ Trading Sessions & Timing Windows

Institutional volume is heavily concentrated in specific trading sessions. The EA includes a built-in GMT session filter:

- **London / European & NY Overlap Session:** `07:00 – 17:00 GMT` *(Ideal for EURUSD and XAUUSD)*
- **Asian / Tokyo Session:** `23:00 – 09:00 GMT` *(Ideal for AUDJPY)*
- **Session Filter Toggle:** Set `InpUseSessionFilter = false` to enable 24/5 price-action operation.

## 🛡️ Risk Management & Capital Preservation

The EA is built with an institutional risk management core:

### Dynamic Position Sizing Formula
$$\text{Lot Size} = \frac{\text{Account Equity} \times \text{Risk \%}}{\text{Stop Loss Distance (points)} \times \text{Point Value}}$$

- Prevents overleveraging on large Stop Losses.
- Automatically adjusts lot size for currency pairs, Gold (XAUUSD), and account currency denominations.

### 🔒 1:1 Breakeven Stop-Lock
- When unrealized profit reaches **1:1 Risk:Reward**, the Stop Loss is automatically shifted to **Entry Price + 10 points profit**.
- Completely eliminates downside capital risk while allowing the trade to reach maximum target extensions.

### 💰 50% Partial Close at TP1
- When price achieves TP1 (default **1:1.5 RR**), the EA executes an automated single partial close of **50% of the position volume**.
- Guaranteed profit is banked into the account balance immediately.

### 📈 Volatility-Based ATR Trailing Stop
- Following Breakeven and TP1, the remaining 50% position volume is protected by an adaptive **ATR(14) Trailing Stop** (multiplier `1.5x`).
- Lets profitable trends run freely toward higher timeframe structural resistance/support levels.

### 🚫 Anti-Overtrading Session Limits
- Maximum allowed trades per session per symbol is capped (default: `2 trades`).
- Prevents overtrading during choppy market consolidation or unexpected macroeconomic news events.

## ⚙️ Input Parameter Reference

| Category | Parameter | Default | Description |
| :--- | :--- | :--- | :--- |
| **General** | `InpMagicNumber` | `112233` | Unique identifier for EA orders. |
| | `InpRiskPercent` | `2.0` | Risk percentage per trade based on account equity. |
| | `InpMaxTradesPerSession` | `2` | Max trades per symbol per active session. |
| | `InpSlippage` | `30` | Maximum slippage allowed in points. |
| **Symbols** | `InpSymbol1` | `EURUSDm` | Primary London session pair. |
| | `InpSymbol2` | `XAUUSDm` | Secondary London session pair (Gold). |
| | `InpSymbol3` | `AUDJPYm` | Asian session pair. |
| **Sessions** | `InpUseSessionFilter` | `true` | Enable/disable session hour limits. |
| | `InpLondonStartHour / End` | `7 / 17` | London + NY volume trading window (GMT). |
| | `InpAsianStartHour / End` | `23 / 9` | Asian session trading window (GMT). |
| **Timeframes** | `InpHTF_Period` | `PERIOD_H1` | Trend bias timeframe (H1 for active intraday). |
| | `InpStructureTF` | `PERIOD_M15` | Fibonacci market structure timeframe. |
| | `InpEntryTF` | `PERIOD_M15` | Execution and ICT trigger timeframe. |
| **Trade Mgmt** | `InpMinRR` | `1.5` | Minimum Risk:Reward ratio to accept setup. |
| | `InpBreakevenRR` | `1.0` | RR distance to move SL to Breakeven. |
| | `InpPartialClosePercent`| `50.0` | Percentage of lots closed at TP1. |
| | `InpUseTrailingStop` | `true` | Activate ATR-based trailing stop. |

## 🖥️ On-Chart HUD Dashboard & Visual Guide

The EA includes a high-performance visual display powered by a dedicated 1-second timer:

- 📊 **Live Dashboard Panel:** Real-time display of GMT Clock, Session status, 1H/4H Trend Bias, Live Bid/Ask & Spread, Fibonacci Level Prices, Active Zone state, Session Trade Count, Open Positions, and Account Equity.
- 📏 **Fibonacci Trend Lines:** Color-coded levels with right-aligned price tags (38.2% DodgerBlue, 50% Gold, 61.8% Orange, 78.6% Red).
- 🟩 **Shaded Entry Box:** Highlights the optimal pullback zone on the chart.
- 📦 **Session Boxes:** Visual background framing of historical and active London and Asian sessions.
- 🎯 **Trade Entry Markers:** Real Buy/Sell execution arrows with dashed SL and TP projection lines.

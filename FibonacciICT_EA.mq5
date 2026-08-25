//+------------------------------------------------------------------+
//|                                            FibonacciICT_EA.mq5   |
//|                         Fibonacci Pullback + ICT Trading Strategy |
//|                                                                  |
//|  - 4H/Daily trend bias + 1H market structure                     |
//|  - Fibonacci 38.2%-50% pullback entries on 15M                   |
//|  - BOS, CHoCH, FVG confirmations                                 |
//|  - Session filtering (London/Asian)                              |
//|  - 2% max risk, breakeven, partial TP, trailing                  |
//+------------------------------------------------------------------+
#property copyright "Fibonacci ICT EA"
#property link      ""
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| ENUMS                                                            |
//+------------------------------------------------------------------+
enum ENUM_TREND_BIAS
{
   TREND_BULLISH = 1,
   TREND_BEARISH = -1,
   TREND_NEUTRAL = 0
};

enum ENUM_ICT_SIGNAL
{
   ICT_NONE = 0,
   ICT_BOS_BULLISH = 1,
   ICT_BOS_BEARISH = 2,
   ICT_CHOCH_BULLISH = 3,
   ICT_CHOCH_BEARISH = 4
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
input group "=== General Settings ==="
input int         InpMagicNumber        = 112233;       // Magic Number
input double      InpRiskPercent        = 2.0;          // Risk Percent per Trade
input int         InpMaxTradesPerSession= 2;            // Max Trades per Session per Symbol
input int         InpSlippage           = 30;           // Slippage (points)

input group "=== Symbol Settings ==="
input string      InpSymbol1            = "EURUSDm";    // Symbol 1 (London)
input string      InpSymbol2            = "XAUUSDm";    // Symbol 2 (London)
input string      InpSymbol3            = "AUDJPYm";    // Symbol 3 (Asian)

input group "=== Session Settings (GMT Hours) ==="
input int         InpLondonStartHour    = 8;            // London Session Start (GMT)
input int         InpLondonEndHour      = 12;           // London Session End (GMT)
input int         InpAsianStartHour     = 23;           // Asian Session Start (GMT)
input int         InpAsianEndHour       = 8;            // Asian Session End (GMT)

input group "=== Fibonacci Settings ==="
input double      InpFibEntryHigh       = 50.0;         // Fib Entry Zone Upper (%)
input double      InpFibEntryLow        = 38.2;         // Fib Entry Zone Lower (%)
input double      InpFibCautionLevel    = 61.8;         // Fib Caution Zone (%)
input double      InpFibInvalidation    = 78.6;         // Fib Invalidation Level (%)

input group "=== Trend Detection Settings ==="
input ENUM_TIMEFRAMES InpHTF_Period     = PERIOD_H4;    // Higher Timeframe (Trend Bias)
input ENUM_TIMEFRAMES InpStructureTF    = PERIOD_H1;    // Structure Timeframe
input ENUM_TIMEFRAMES InpEntryTF        = PERIOD_M15;   // Entry Timeframe
input int         InpSwingLookback      = 20;           // Swing Point Lookback Bars
input bool        InpUseMA              = true;         // Use Moving Averages for Trend
input int         InpMA_Fast            = 20;           // Fast MA Period
input int         InpMA_Mid             = 50;           // Mid MA Period
input int         InpMA_Slow            = 200;          // Slow MA Period

input group "=== Trade Management ==="
input double      InpMinRR              = 2.0;          // Minimum Risk:Reward Ratio
input double      InpBreakevenRR        = 1.0;          // Move SL to BE at RR
input double      InpPartialClosePercent= 50.0;         // Partial Close Percent at TP1
input bool        InpUseTrailingStop    = true;         // Use Trailing Stop
input int         InpTrailingATRPeriod  = 14;           // Trailing ATR Period
input double      InpTrailingATRMult    = 1.5;          // Trailing ATR Multiplier

input group "=== ICT Settings ==="
input int         InpBOS_Lookback       = 10;           // BOS Lookback Bars
input int         InpFVG_MinSize        = 5;            // FVG Minimum Size (points)

input group "=== Visualization Settings ==="
input bool        InpShowDashboard      = true;         // Show Dashboard Panel
input bool        InpShowFibLines       = true;         // Show Fibonacci Lines
input bool        InpShowSwings         = true;         // Show Swing Points
input bool        InpShowBOS            = true;         // Show BOS/CHoCH Labels
input bool        InpShowFVG            = true;         // Show FVG Zones
input bool        InpShowSessions       = true;         // Show Session Boxes
input bool        InpShowTradeArrows    = true;         // Show Trade Entry Arrows
input color       InpFibColor382        = clrDodgerBlue; // Fib 38.2% Color
input color       InpFibColor500        = clrGold;       // Fib 50.0% Color
input color       InpFibColor618        = clrOrange;     // Fib 61.8% Color
input color       InpFibColor786        = clrRed;        // Fib 78.6% Color
input color       InpBullColor          = clrLime;       // Bullish Color
input color       InpBearColor          = clrCrimson;    // Bearish Color
input color       InpFVGBullColor       = C'0,100,0';    // FVG Bullish Color
input color       InpFVGBearColor       = C'100,0,0';    // FVG Bearish Color
input color       InpSessionLondonColor = C'30,60,90';   // London Session Color
input color       InpSessionAsianColor  = C'90,60,30';   // Asian Session Color
input color       InpDashBgColor        = C'20,20,30';   // Dashboard Background
input color       InpDashTextColor      = clrWhite;      // Dashboard Text Color
input int         InpDashFontSize       = 9;             // Dashboard Font Size

//+------------------------------------------------------------------+
//| STRUCTURES                                                       |
//+------------------------------------------------------------------+
struct SwingPoint
{
   double   price;
   datetime time;
   int      bar_index;
   bool     is_high;  // true = swing high, false = swing low
};

struct FibLevels
{
   double   swing_high;
   double   swing_low;
   double   level_382;
   double   level_500;
   double   level_618;
   double   level_786;
   bool     is_valid;
   bool     is_bullish; // true = fib drawn for long, false = for short
};

struct TradeSetup
{
   string   symbol;
   int      direction;     // 1 = buy, -1 = sell
   double   entry_price;
   double   stop_loss;
   double   take_profit;
   double   lot_size;
   string   comment;
};

struct SymbolData
{
   string            symbol;
   int               session_type;     // 0 = London, 1 = Asian
   bool              enabled;          // false if symbol not found on broker
   int               ma_fast_handle;
   int               ma_mid_handle;
   int               ma_slow_handle;
   int               atr_handle;
   ENUM_TREND_BIAS   htf_bias;
   FibLevels         fib;
   int               trades_this_session;
   datetime          last_trade_time;
   bool              breakeven_applied[];
   bool              partial_closed[];
};

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                 |
//+------------------------------------------------------------------+
CTrade         trade;
CPositionInfo  posInfo;
CSymbolInfo    symInfo;

SymbolData     g_symbols[3];
int            g_total_symbols = 3;
datetime       g_last_bar_time[];
bool           g_initialized = false;
string         g_obj_prefix = "FibICT_";

//+------------------------------------------------------------------+
//| Detect the correct order filling mode for the broker              |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING GetFillingMode(string sym)
{
   long filling_mode = SymbolInfoInteger(sym, SYMBOL_FILLING_MODE);
   
   if((filling_mode & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      return ORDER_FILLING_FOK;
   if((filling_mode & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      return ORDER_FILLING_IOC;
   
   return ORDER_FILLING_RETURN;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // Setup trade object
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage);
   
   // Initialize symbols
   g_symbols[0].symbol = InpSymbol1;
   g_symbols[0].session_type = 0; // London
   
   g_symbols[1].symbol = InpSymbol2;
   g_symbols[1].session_type = 0; // London
   
   g_symbols[2].symbol = InpSymbol3;
   g_symbols[2].session_type = 1; // Asian
   
   ArrayResize(g_last_bar_time, g_total_symbols);
   
   int enabled_count = 0;
   
   // Initialize handles for each symbol
   for(int i = 0; i < g_total_symbols; i++)
   {
      string sym = g_symbols[i].symbol;
      g_symbols[i].enabled = false;
      g_symbols[i].ma_fast_handle = INVALID_HANDLE;
      g_symbols[i].ma_mid_handle = INVALID_HANDLE;
      g_symbols[i].ma_slow_handle = INVALID_HANDLE;
      g_symbols[i].atr_handle = INVALID_HANDLE;
      
      // Check if symbol exists — skip if not found (don't crash)
      if(!SymbolSelect(sym, true))
      {
         PrintFormat("WARNING: Symbol %s not found on this broker — skipping. Check your symbol names in inputs.", sym);
         continue;
      }
      
      // Auto-detect filling mode for this broker
      trade.SetTypeFilling(GetFillingMode(sym));
      
      // Create MA handles
      if(InpUseMA)
      {
         g_symbols[i].ma_fast_handle = iMA(sym, InpHTF_Period, InpMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
         g_symbols[i].ma_mid_handle  = iMA(sym, InpHTF_Period, InpMA_Mid, 0, MODE_EMA, PRICE_CLOSE);
         g_symbols[i].ma_slow_handle = iMA(sym, InpHTF_Period, InpMA_Slow, 0, MODE_SMA, PRICE_CLOSE);
         
         if(g_symbols[i].ma_fast_handle == INVALID_HANDLE || 
            g_symbols[i].ma_mid_handle == INVALID_HANDLE || 
            g_symbols[i].ma_slow_handle == INVALID_HANDLE)
         {
            PrintFormat("WARNING: Failed to create MA handles for %s — skipping this symbol.", sym);
            continue;
         }
      }
      
      // ATR handle for trailing
      g_symbols[i].atr_handle = iATR(sym, InpEntryTF, InpTrailingATRPeriod);
      if(g_symbols[i].atr_handle == INVALID_HANDLE)
      {
         PrintFormat("WARNING: Failed to create ATR handle for %s — skipping this symbol.", sym);
         continue;
      }
      
      // If we reach here, symbol is fully ready
      g_symbols[i].enabled = true;
      enabled_count++;
      
      g_symbols[i].htf_bias = TREND_NEUTRAL;
      g_symbols[i].fib.is_valid = false;
      g_symbols[i].trades_this_session = 0;
      g_symbols[i].last_trade_time = 0;
      g_last_bar_time[i] = 0;
      
      ArrayResize(g_symbols[i].breakeven_applied, 0);
      ArrayResize(g_symbols[i].partial_closed, 0);
      
      PrintFormat("OK: Symbol %s initialized successfully.", sym);
   }
   
   if(enabled_count == 0)
   {
      Alert("FibonacciICT EA: No valid symbols found! Check your symbol names in the inputs (e.g. XAUUSD vs XAUUSDm vs GOLD).");
      PrintFormat("ERROR: No valid symbols found. Check Inputs tab for correct symbol names on your broker.");
      return INIT_SUCCEEDED; // Return SUCCEEDED so EA stays on chart and shows the alert
   }
   
   g_initialized = true;
   PrintFormat("FibonacciICT EA initialized. Magic: %d, Risk: %.1f%%, Active Symbols: %d/%d", 
      InpMagicNumber, InpRiskPercent, enabled_count, g_total_symbols);
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   for(int i = 0; i < g_total_symbols; i++)
   {
      if(g_symbols[i].ma_fast_handle != INVALID_HANDLE) IndicatorRelease(g_symbols[i].ma_fast_handle);
      if(g_symbols[i].ma_mid_handle != INVALID_HANDLE)  IndicatorRelease(g_symbols[i].ma_mid_handle);
      if(g_symbols[i].ma_slow_handle != INVALID_HANDLE) IndicatorRelease(g_symbols[i].ma_slow_handle);
      if(g_symbols[i].atr_handle != INVALID_HANDLE)     IndicatorRelease(g_symbols[i].atr_handle);
   }
   // Clean up all visual objects
   ObjectsDeleteAll(0, g_obj_prefix);
   PrintFormat("FibonacciICT EA deinitialized. Reason: %d", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!g_initialized) return;
   
   // Process each symbol
   for(int i = 0; i < g_total_symbols; i++)
   {
      string sym = g_symbols[i].symbol;
      
      // Skip symbols that weren't found on this broker
      if(!g_symbols[i].enabled) continue;
      
      // ---- TRADE MANAGEMENT (every tick) ----
      ManageOpenTrades(i);
      
      // ---- NEW BAR CHECK (entry logic only on new bar) ----
      datetime current_bar_time = iTime(sym, InpEntryTF, 0);
      if(current_bar_time == g_last_bar_time[i]) continue;
      g_last_bar_time[i] = current_bar_time;
      
      // ---- SESSION FILTER ----
      if(!IsInSession(g_symbols[i].session_type))
      {
         // Reset trade count when session ends
         ResetSessionTradeCount(i);
         continue;
      }
      
      // ---- MAX TRADES CHECK ----
      if(g_symbols[i].trades_this_session >= InpMaxTradesPerSession)
         continue;
      
      // ---- ALREADY HAS POSITION? ----
      if(HasOpenPosition(sym))
         continue;
      
      // ---- STEP 1: HTF TREND BIAS ----
      g_symbols[i].htf_bias = GetHTFTrendBias(i);
      
      // ---- Draw visuals for current chart symbol ----
      if(sym == Symbol())
      {
         // Draw session boxes
         if(InpShowSessions) DrawSessionBoxes();
         
         // Draw swing points
         if(InpShowSwings) DrawSwingPoints(i);
         
         // Draw dashboard (always update)
         if(InpShowDashboard) DrawDashboard(i);
      }
      
      if(g_symbols[i].htf_bias == TREND_NEUTRAL)
         continue;
      
      // ---- STEP 2: FIBONACCI LEVELS FROM 1H STRUCTURE ----
      g_symbols[i].fib = CalculateFibonacciLevels(i);
      if(!g_symbols[i].fib.is_valid)
         continue;
      
      // ---- Draw Fibonacci Lines ----
      if(sym == Symbol() && InpShowFibLines)
         DrawFibonacciLevels(g_symbols[i].fib, g_symbols[i].htf_bias);
      
      // ---- STEP 3: CHECK IF PRICE IS IN FIB ZONE ----
      double current_price = SymbolInfoDouble(sym, SYMBOL_BID);
      if(!IsPriceInFibZone(current_price, g_symbols[i].fib, g_symbols[i].htf_bias))
         continue;
      
      // ---- STEP 4: CHECK FIB INVALIDATION (78.6%) ----
      if(IsFibInvalidated(current_price, g_symbols[i].fib))
      {
         // Trend change detected — handle separately
         HandleTrendChange(i, current_price);
         continue;
      }
      
      // ---- STEP 5: ICT CONFIRMATIONS ON 15M ----
      if(!HasICTConfirmation(i))
         continue;
      
      // ---- STEP 6: CANDLESTICK CONFIRMATION ----
      if(!HasCandlestickConfirmation(i))
         continue;
      
      // ---- STEP 7: CALCULATE ENTRY, SL, TP ----
      TradeSetup setup;
      if(!BuildTradeSetup(i, setup))
         continue;
      
      // ---- STEP 8: EXECUTE TRADE ----
      ExecuteTrade(setup, i);
      
      // ---- Draw trade arrow ----
      if(sym == Symbol() && InpShowTradeArrows)
         DrawTradeArrow(setup);
   }
}

//+------------------------------------------------------------------+
//| SESSION MANAGEMENT                                               |
//+------------------------------------------------------------------+
bool IsInSession(int session_type)
{
   MqlDateTime dt;
   TimeGMT(dt);
   int hour = dt.hour;
   
   if(session_type == 0) // London
   {
      return (hour >= InpLondonStartHour && hour < InpLondonEndHour);
   }
   else // Asian
   {
      // Asian session wraps around midnight
      if(InpAsianStartHour > InpAsianEndHour)
         return (hour >= InpAsianStartHour || hour < InpAsianEndHour);
      else
         return (hour >= InpAsianStartHour && hour < InpAsianEndHour);
   }
}

void ResetSessionTradeCount(int sym_index)
{
   // Reset when we detect session has ended
   MqlDateTime dt;
   TimeGMT(dt);
   int hour = dt.hour;
   
   bool in_session = IsInSession(g_symbols[sym_index].session_type);
   if(!in_session && g_symbols[sym_index].trades_this_session > 0)
   {
      // Check if enough time has passed since session end
      g_symbols[sym_index].trades_this_session = 0;
   }
}

//+------------------------------------------------------------------+
//| HTF TREND BIAS DETECTION                                         |
//+------------------------------------------------------------------+
ENUM_TREND_BIAS GetHTFTrendBias(int sym_index)
{
   string sym = g_symbols[sym_index].symbol;
   
   // Get swing points on HTF
   SwingPoint swings[];
   int swing_count = DetectSwingPoints(sym, InpHTF_Period, InpSwingLookback, swings);
   
   if(swing_count < 4) return TREND_NEUTRAL;
   
   // Analyze structure: HH/HL = Bullish, LH/LL = Bearish
   ENUM_TREND_BIAS structure_bias = AnalyzeMarketStructure(swings, swing_count);
   
   // MA confirmation (optional)
   if(InpUseMA)
   {
      ENUM_TREND_BIAS ma_bias = GetMABias(sym_index);
      
      // Both must agree
      if(structure_bias == TREND_BULLISH && ma_bias == TREND_BULLISH)
         return TREND_BULLISH;
      else if(structure_bias == TREND_BEARISH && ma_bias == TREND_BEARISH)
         return TREND_BEARISH;
      else
         return TREND_NEUTRAL;
   }
   
   return structure_bias;
}

ENUM_TREND_BIAS GetMABias(int sym_index)
{
   double ma_fast[], ma_mid[], ma_slow[];
   ArraySetAsSeries(ma_fast, true);
   ArraySetAsSeries(ma_mid, true);
   ArraySetAsSeries(ma_slow, true);
   
   if(CopyBuffer(g_symbols[sym_index].ma_fast_handle, 0, 0, 3, ma_fast) < 3) return TREND_NEUTRAL;
   if(CopyBuffer(g_symbols[sym_index].ma_mid_handle, 0, 0, 3, ma_mid) < 3)   return TREND_NEUTRAL;
   if(CopyBuffer(g_symbols[sym_index].ma_slow_handle, 0, 0, 3, ma_slow) < 3) return TREND_NEUTRAL;
   
   double price = SymbolInfoDouble(g_symbols[sym_index].symbol, SYMBOL_BID);
   
   // Bullish: Price > all MAs, Fast > Mid > Slow
   if(price > ma_fast[0] && price > ma_mid[0] && price > ma_slow[0] &&
      ma_fast[0] > ma_mid[0] && ma_mid[0] > ma_slow[0])
      return TREND_BULLISH;
   
   // Bearish: Price < all MAs, Fast < Mid < Slow
   if(price < ma_fast[0] && price < ma_mid[0] && price < ma_slow[0] &&
      ma_fast[0] < ma_mid[0] && ma_mid[0] < ma_slow[0])
      return TREND_BEARISH;
   
   return TREND_NEUTRAL;
}

//+------------------------------------------------------------------+
//| MARKET STRUCTURE ANALYSIS                                        |
//+------------------------------------------------------------------+
ENUM_TREND_BIAS AnalyzeMarketStructure(SwingPoint &swings[], int count)
{
   // Find the last 2 swing highs and 2 swing lows
   double last_sh1 = 0, last_sh2 = 0, last_sl1 = 0, last_sl2 = 0;
   int sh_count = 0, sl_count = 0;
   
   for(int i = 0; i < count && (sh_count < 2 || sl_count < 2); i++)
   {
      if(swings[i].is_high && sh_count < 2)
      {
         if(sh_count == 0) last_sh1 = swings[i].price;
         else last_sh2 = swings[i].price;
         sh_count++;
      }
      else if(!swings[i].is_high && sl_count < 2)
      {
         if(sl_count == 0) last_sl1 = swings[i].price;
         else last_sl2 = swings[i].price;
         sl_count++;
      }
   }
   
   if(sh_count < 2 || sl_count < 2) return TREND_NEUTRAL;
   
   // HH + HL = Bullish
   bool higher_high = last_sh1 > last_sh2;
   bool higher_low  = last_sl1 > last_sl2;
   
   // LH + LL = Bearish
   bool lower_high  = last_sh1 < last_sh2;
   bool lower_low   = last_sl1 < last_sl2;
   
   if(higher_high && higher_low)  return TREND_BULLISH;
   if(lower_high && lower_low)    return TREND_BEARISH;
   
   return TREND_NEUTRAL;
}

//+------------------------------------------------------------------+
//| SWING POINT DETECTION                                            |
//+------------------------------------------------------------------+
int DetectSwingPoints(string sym, ENUM_TIMEFRAMES tf, int lookback, SwingPoint &swings[])
{
   int bars_needed = lookback * 3;
   
   double high[], low[];
   datetime time[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(time, true);
   
   if(CopyHigh(sym, tf, 0, bars_needed, high) < bars_needed) return 0;
   if(CopyLow(sym, tf, 0, bars_needed, low) < bars_needed) return 0;
   if(CopyTime(sym, tf, 0, bars_needed, time) < bars_needed) return 0;
   
   int count = 0;
   ArrayResize(swings, 0);
   int swing_strength = 3; // bars on each side to confirm swing
   
   for(int i = swing_strength; i < bars_needed - swing_strength; i++)
   {
      // Check for swing high
      bool is_swing_high = true;
      for(int j = 1; j <= swing_strength; j++)
      {
         if(high[i] <= high[i-j] || high[i] <= high[i+j])
         {
            is_swing_high = false;
            break;
         }
      }
      
      if(is_swing_high)
      {
         count++;
         ArrayResize(swings, count);
         swings[count-1].price = high[i];
         swings[count-1].time = time[i];
         swings[count-1].bar_index = i;
         swings[count-1].is_high = true;
      }
      
      // Check for swing low
      bool is_swing_low = true;
      for(int j = 1; j <= swing_strength; j++)
      {
         if(low[i] >= low[i-j] || low[i] >= low[i+j])
         {
            is_swing_low = false;
            break;
         }
      }
      
      if(is_swing_low)
      {
         count++;
         ArrayResize(swings, count);
         swings[count-1].price = low[i];
         swings[count-1].time = time[i];
         swings[count-1].bar_index = i;
         swings[count-1].is_high = false;
      }
   }
   
   return count;
}

//+------------------------------------------------------------------+
//| FIBONACCI CALCULATION                                            |
//+------------------------------------------------------------------+
FibLevels CalculateFibonacciLevels(int sym_index)
{
   FibLevels fib;
   fib.is_valid = false;
   
   string sym = g_symbols[sym_index].symbol;
   ENUM_TREND_BIAS bias = g_symbols[sym_index].htf_bias;
   
   // Get swing points on 1H structure timeframe
   SwingPoint swings[];
   int swing_count = DetectSwingPoints(sym, InpStructureTF, InpSwingLookback, swings);
   
   if(swing_count < 2) return fib;
   
   // Find the most recent swing high and swing low
   double recent_high = 0, recent_low = 0;
   bool found_high = false, found_low = false;
   
   for(int i = 0; i < swing_count; i++)
   {
      if(swings[i].is_high && !found_high)
      {
         recent_high = swings[i].price;
         found_high = true;
      }
      else if(!swings[i].is_high && !found_low)
      {
         recent_low = swings[i].price;
         found_low = true;
      }
      if(found_high && found_low) break;
   }
   
   if(!found_high || !found_low) return fib;
   if(recent_high <= recent_low) return fib;
   
   double range = recent_high - recent_low;
   
   fib.swing_high = recent_high;
   fib.swing_low = recent_low;
   
   if(bias == TREND_BULLISH)
   {
      // Fib from swing low to swing high — pullback down
      fib.is_bullish = true;
      fib.level_382 = recent_high - range * (InpFibEntryLow / 100.0);
      fib.level_500 = recent_high - range * (InpFibEntryHigh / 100.0);
      fib.level_618 = recent_high - range * (InpFibCautionLevel / 100.0);
      fib.level_786 = recent_high - range * (InpFibInvalidation / 100.0);
   }
   else
   {
      // Fib from swing high to swing low — pullback up
      fib.is_bullish = false;
      fib.level_382 = recent_low + range * (InpFibEntryLow / 100.0);
      fib.level_500 = recent_low + range * (InpFibEntryHigh / 100.0);
      fib.level_618 = recent_low + range * (InpFibCautionLevel / 100.0);
      fib.level_786 = recent_low + range * (InpFibInvalidation / 100.0);
   }
   
   fib.is_valid = true;
   return fib;
}

//+------------------------------------------------------------------+
//| FIBONACCI ZONE CHECK                                             |
//+------------------------------------------------------------------+
bool IsPriceInFibZone(double price, FibLevels &fib, ENUM_TREND_BIAS bias)
{
   if(!fib.is_valid) return false;
   
   if(bias == TREND_BULLISH)
   {
      // For longs: price should be between 38.2% and 50% (pullback zone)
      // level_382 > level_500 for bullish (both below swing high)
      double upper = fib.level_382;
      double lower = fib.level_500;
      return (price <= upper && price >= lower);
   }
   else if(bias == TREND_BEARISH)
   {
      // For shorts: price should be between 38.2% and 50% (pullback zone)
      // level_382 < level_500 for bearish (both above swing low)
      double lower = fib.level_382;
      double upper = fib.level_500;
      return (price >= lower && price <= upper);
   }
   
   return false;
}

bool IsFibInvalidated(double price, FibLevels &fib)
{
   if(!fib.is_valid) return false;
   
   if(fib.is_bullish)
   {
      // Invalidation: price breaks below 78.6% level
      return (price < fib.level_786);
   }
   else
   {
      // Invalidation: price breaks above 78.6% level
      return (price > fib.level_786);
   }
}

//+------------------------------------------------------------------+
//| BOS DETECTION (Break of Structure)                               |
//+------------------------------------------------------------------+
bool DetectBOS(string sym, ENUM_TIMEFRAMES tf, ENUM_TREND_BIAS expected_direction)
{
   SwingPoint swings[];
   int count = DetectSwingPoints(sym, tf, InpBOS_Lookback, swings);
   
   if(count < 3) return false;
   
   double close[];
   datetime time[];
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(time, true);
   if(CopyClose(sym, tf, 0, 3, close) < 3) return false;
   if(CopyTime(sym, tf, 0, 3, time) < 3) return false;
   
   double current_close = close[1]; // Previous completed candle
   datetime candle_time = time[1];
   
   if(expected_direction == TREND_BULLISH)
   {
      // BOS Bullish: Price breaks above previous swing high
      for(int i = 0; i < count; i++)
      {
         if(swings[i].is_high && swings[i].bar_index > 1)
         {
            if(current_close > swings[i].price)
            {
               DrawBOSLabel(sym, candle_time, swings[i].price, true);
               return true;
            }
            break;
         }
      }
   }
   else if(expected_direction == TREND_BEARISH)
   {
      // BOS Bearish: Price breaks below previous swing low
      for(int i = 0; i < count; i++)
      {
         if(!swings[i].is_high && swings[i].bar_index > 1)
         {
            if(current_close < swings[i].price)
            {
               DrawBOSLabel(sym, candle_time, swings[i].price, false);
               return true;
            }
            break;
         }
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| CHoCH DETECTION (Change of Character)                            |
//+------------------------------------------------------------------+
bool DetectCHoCH(string sym, ENUM_TIMEFRAMES tf, ENUM_TREND_BIAS new_direction)
{
   SwingPoint swings[];
   int count = DetectSwingPoints(sym, tf, InpBOS_Lookback * 2, swings);
   
   if(count < 4) return false;
   
   // Find the last 2 swing highs and 2 swing lows
   double sh[2], sl[2];
   int sh_idx = 0, sl_idx = 0;
   
   for(int i = 0; i < count && (sh_idx < 2 || sl_idx < 2); i++)
   {
      if(swings[i].is_high && sh_idx < 2)
      {
         sh[sh_idx] = swings[i].price;
         sh_idx++;
      }
      else if(!swings[i].is_high && sl_idx < 2)
      {
         sl[sl_idx] = swings[i].price;
         sl_idx++;
      }
   }
   
   if(sh_idx < 2 || sl_idx < 2) return false;
   
   double close[];
   datetime time[];
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(time, true);
   if(CopyClose(sym, tf, 0, 2, close) < 2) return false;
   if(CopyTime(sym, tf, 0, 2, time) < 2) return false;
   
   datetime candle_time = time[1];
   
   if(new_direction == TREND_BULLISH)
   {
      // CHoCH to bullish: Was making LH/LL, now makes HL or HH
      bool was_bearish = (sh[0] < sh[1]) || (sl[0] < sl[1]);
      
      // Current price broke above the most recent lower high
      if(was_bearish && close[1] > sh[0])
      {
         DrawCHoCHLabel(sym, candle_time, sh[0], true);
         return true;
      }
   }
   else if(new_direction == TREND_BEARISH)
   {
      // CHoCH to bearish: Was making HH/HL, now makes LH or LL
      bool was_bullish = (sh[0] > sh[1]) || (sl[0] > sl[1]);
      
      // Current price broke below the most recent higher low
      if(was_bullish && close[1] < sl[0])
      {
         DrawCHoCHLabel(sym, candle_time, sl[0], false);
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| FVG DETECTION (Fair Value Gap)                                   |
//+------------------------------------------------------------------+
bool DetectFVG(string sym, ENUM_TIMEFRAMES tf, ENUM_TREND_BIAS direction, double &fvg_high, double &fvg_low)
{
   double high[], low[], open_arr[], close[];
   datetime time[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(open_arr, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(time, true);
   
   int bars_to_check = 10;
   if(CopyHigh(sym, tf, 0, bars_to_check, high) < bars_to_check) return false;
   if(CopyLow(sym, tf, 0, bars_to_check, low) < bars_to_check) return false;
   if(CopyOpen(sym, tf, 0, bars_to_check, open_arr) < bars_to_check) return false;
   if(CopyClose(sym, tf, 0, bars_to_check, close) < bars_to_check) return false;
   if(CopyTime(sym, tf, 0, bars_to_check, time) < bars_to_check) return false;
   
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   double min_gap = InpFVG_MinSize * point;
   
   // Check the last several 3-candle patterns (skip bar 0 as it's forming)
   for(int i = 1; i < bars_to_check - 2; i++)
   {
      // FVG: Gap between candle [i+1] and candle [i-1] (middle candle is [i])
      if(direction == TREND_BULLISH)
      {
         // Bullish FVG: Low of candle before gap > High of candle after gap
         double gap_top = low[i-1];    // Low of the candle after the middle
         double gap_bottom = high[i+1]; // High of the candle before the middle
         
         if(gap_bottom < gap_top && (gap_top - gap_bottom) >= min_gap)
         {
            fvg_high = gap_top;
            fvg_low = gap_bottom;
            
            // Draw FVG zone on chart
            DrawFVGZone(sym, time[i], gap_top, gap_bottom, true);
            
            // Check if current price is near this FVG
            double current = SymbolInfoDouble(sym, SYMBOL_BID);
            if(current >= gap_bottom && current <= gap_top)
               return true;
         }
      }
      else if(direction == TREND_BEARISH)
      {
         // Bearish FVG: High of candle before gap < Low of candle after gap
         double gap_bottom = high[i-1];  // High of candle after middle
         double gap_top = low[i+1];      // Low of candle before middle
         
         if(gap_top > gap_bottom && (gap_top - gap_bottom) >= min_gap)
         {
            fvg_high = gap_top;
            fvg_low = gap_bottom;
            
            // Draw FVG zone on chart
            DrawFVGZone(sym, time[i], gap_top, gap_bottom, false);
            
            double current = SymbolInfoDouble(sym, SYMBOL_BID);
            if(current >= gap_bottom && current <= gap_top)
               return true;
         }
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| ICT CONFIRMATION CHECK                                           |
//+------------------------------------------------------------------+
bool HasICTConfirmation(int sym_index)
{
   string sym = g_symbols[sym_index].symbol;
   ENUM_TREND_BIAS bias = g_symbols[sym_index].htf_bias;
   
   // Check for BOS on entry timeframe
   bool has_bos = DetectBOS(sym, InpEntryTF, bias);
   
   // Check for FVG
   double fvg_high = 0, fvg_low = 0;
   bool has_fvg = DetectFVG(sym, InpEntryTF, bias, fvg_high, fvg_low);
   
   // Check for CHoCH (for trend change scenarios)
   bool has_choch = DetectCHoCH(sym, InpEntryTF, bias);
   
   // Need at least BOS or (CHoCH + FVG) for confirmation
   if(has_bos)
   {
      PrintFormat("[%s] ICT Confirmation: BOS detected on %s", sym, EnumToString(InpEntryTF));
      return true;
   }
   
   if(has_choch && has_fvg)
   {
      PrintFormat("[%s] ICT Confirmation: CHoCH + FVG detected on %s", sym, EnumToString(InpEntryTF));
      return true;
   }
   
   if(has_fvg)
   {
      PrintFormat("[%s] ICT Confirmation: FVG detected on %s (partial)", sym, EnumToString(InpEntryTF));
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| CANDLESTICK CONFIRMATION                                         |
//+------------------------------------------------------------------+
bool HasCandlestickConfirmation(int sym_index)
{
   string sym = g_symbols[sym_index].symbol;
   ENUM_TREND_BIAS bias = g_symbols[sym_index].htf_bias;
   
   double open_arr[], high[], low[], close[];
   ArraySetAsSeries(open_arr, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   
   if(CopyOpen(sym, InpEntryTF, 0, 5, open_arr) < 5) return false;
   if(CopyHigh(sym, InpEntryTF, 0, 5, high) < 5) return false;
   if(CopyLow(sym, InpEntryTF, 0, 5, low) < 5) return false;
   if(CopyClose(sym, InpEntryTF, 0, 5, close) < 5) return false;
   
   // Check the last completed candle (index 1)
   int idx = 1;
   double body = MathAbs(close[idx] - open_arr[idx]);
   double total_range = high[idx] - low[idx];
   
   if(total_range == 0) return false;
   
   double upper_wick = high[idx] - MathMax(close[idx], open_arr[idx]);
   double lower_wick = MathMin(close[idx], open_arr[idx]) - low[idx];
   
   if(bias == TREND_BULLISH)
   {
      // Bullish rejection: Pin bar / Hammer
      // Long lower wick, small body, close near high
      bool is_hammer = (lower_wick >= body * 2.0) && (close[idx] > open_arr[idx]);
      
      // Strong bullish candle
      bool is_strong_bull = (close[idx] > open_arr[idx]) && (body > total_range * 0.6);
      
      // Check previous candle (index 2) for engulfing
      bool is_engulfing = (close[idx] > open_arr[idx]) &&
                          (close[2] < open_arr[2]) &&
                          (close[idx] > high[2]) &&
                          (open_arr[idx] < low[2]);
      
      return (is_hammer || is_strong_bull || is_engulfing);
   }
   else if(bias == TREND_BEARISH)
   {
      // Bearish rejection: Shooting star
      bool is_shooting_star = (upper_wick >= body * 2.0) && (close[idx] < open_arr[idx]);
      
      // Strong bearish candle
      bool is_strong_bear = (close[idx] < open_arr[idx]) && (body > total_range * 0.6);
      
      // Bearish engulfing with previous candle
      bool is_engulfing = (close[idx] < open_arr[idx]) &&
                          (close[2] > open_arr[2]) &&
                          (close[idx] < low[2]) &&
                          (open_arr[idx] > high[2]);
      
      return (is_shooting_star || is_strong_bear || is_engulfing);
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| BUILD TRADE SETUP                                                |
//+------------------------------------------------------------------+
bool BuildTradeSetup(int sym_index, TradeSetup &setup)
{
   string sym = g_symbols[sym_index].symbol;
   ENUM_TREND_BIAS bias = g_symbols[sym_index].htf_bias;
   FibLevels fib = g_symbols[sym_index].fib;
   
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   
   setup.symbol = sym;
   
   // Get 1H structure target (previous swing H/L for TP)
   SwingPoint target_swings[];
   int target_count = DetectSwingPoints(sym, InpStructureTF, InpSwingLookback, target_swings);
   
   if(bias == TREND_BULLISH)
   {
      setup.direction = 1;
      setup.entry_price = ask;
      
      // SL: Below the 61.8% fib level or recent swing low (whichever is closer)
      double sl_fib = fib.level_618 - 10 * point;
      setup.stop_loss = sl_fib;
      
      // TP: Target 1H market structure (previous swing high)
      setup.take_profit = fib.swing_high; // Default to swing high
      
      // Look for a higher 1H swing high as target
      for(int i = 0; i < target_count; i++)
      {
         if(target_swings[i].is_high && target_swings[i].price > ask)
         {
            setup.take_profit = target_swings[i].price;
            break;
         }
      }
      
      // Validate minimum RR
      double risk = ask - setup.stop_loss;
      double reward = setup.take_profit - ask;
      
      if(risk <= 0 || reward <= 0) return false;
      if(reward / risk < InpMinRR) return false;
      
      setup.comment = StringFormat("FibICT Buy [%.1f-%.1f%%]", InpFibEntryLow, InpFibEntryHigh);
   }
   else if(bias == TREND_BEARISH)
   {
      setup.direction = -1;
      setup.entry_price = bid;
      
      // SL: Above the 61.8% fib level
      double sl_fib = fib.level_618 + 10 * point;
      setup.stop_loss = sl_fib;
      
      // TP: Target 1H market structure (previous swing low)
      setup.take_profit = fib.swing_low; // Default to swing low
      
      for(int i = 0; i < target_count; i++)
      {
         if(!target_swings[i].is_high && target_swings[i].price < bid)
         {
            setup.take_profit = target_swings[i].price;
            break;
         }
      }
      
      // Validate minimum RR
      double risk = setup.stop_loss - bid;
      double reward = bid - setup.take_profit;
      
      if(risk <= 0 || reward <= 0) return false;
      if(reward / risk < InpMinRR) return false;
      
      setup.comment = StringFormat("FibICT Sell [%.1f-%.1f%%]", InpFibEntryLow, InpFibEntryHigh);
   }
   else return false;
   
   // Calculate lot size based on risk
   setup.lot_size = CalculateLotSize(sym, MathAbs(setup.entry_price - setup.stop_loss));
   
   if(setup.lot_size <= 0) return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| POSITION SIZING                                                  |
//+------------------------------------------------------------------+
double CalculateLotSize(string sym, double sl_distance)
{
   if(sl_distance <= 0) return 0;
   
   double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_amount = account_balance * (InpRiskPercent / 100.0);
   
   double tick_value = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   
   if(tick_value == 0 || tick_size == 0) return 0;
   
   double lot_size = risk_amount / (sl_distance / tick_size * tick_value);
   
   // Normalize lot size
   double min_lot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double lot_step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   
   lot_size = MathMax(min_lot, lot_size);
   lot_size = MathMin(max_lot, lot_size);
   lot_size = NormalizeDouble(MathFloor(lot_size / lot_step) * lot_step, 2);
   
   return lot_size;
}

//+------------------------------------------------------------------+
//| EXECUTE TRADE                                                    |
//+------------------------------------------------------------------+
void ExecuteTrade(TradeSetup &setup, int sym_index)
{
   string sym = setup.symbol;
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   
   double entry = NormalizeDouble(setup.entry_price, digits);
   double sl = NormalizeDouble(setup.stop_loss, digits);
   double tp = NormalizeDouble(setup.take_profit, digits);
   
   bool result = false;
   
   if(setup.direction == 1)
   {
      result = trade.Buy(setup.lot_size, sym, entry, sl, tp, setup.comment);
   }
   else
   {
      result = trade.Sell(setup.lot_size, sym, entry, sl, tp, setup.comment);
   }
   
   if(result)
   {
      g_symbols[sym_index].trades_this_session++;
      g_symbols[sym_index].last_trade_time = TimeCurrent();
      
      PrintFormat("TRADE OPENED: %s %s | Lots: %.2f | Entry: %.*f | SL: %.*f | TP: %.*f | RR: %.1f",
         (setup.direction == 1) ? "BUY" : "SELL", sym, setup.lot_size,
         digits, entry, digits, sl, digits, tp,
         MathAbs(tp - entry) / MathAbs(entry - sl));
   }
   else
   {
      PrintFormat("TRADE FAILED: %s %s | Error: %d - %s", 
         (setup.direction == 1) ? "BUY" : "SELL", sym,
         trade.ResultRetcode(), trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| TRADE MANAGEMENT                                                 |
//+------------------------------------------------------------------+
void ManageOpenTrades(int sym_index)
{
   string sym = g_symbols[sym_index].symbol;
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != sym) continue;
      if(posInfo.Magic() != InpMagicNumber) continue;
      
      ulong ticket = posInfo.Ticket();
      double open_price = posInfo.PriceOpen();
      double current_sl = posInfo.StopLoss();
      double current_tp = posInfo.TakeProfit();
      double current_price = posInfo.PriceCurrent();
      double volume = posInfo.Volume();
      ENUM_POSITION_TYPE pos_type = posInfo.PositionType();
      
      double risk_distance = MathAbs(open_price - current_sl);
      if(risk_distance == 0) continue;
      
      // ---- BREAKEVEN AT 1:1 RR ----
      double be_target = risk_distance * InpBreakevenRR;
      bool should_be = false;
      
      if(pos_type == POSITION_TYPE_BUY)
      {
         should_be = (current_price >= open_price + be_target) && (current_sl < open_price);
      }
      else
      {
         should_be = (current_price <= open_price - be_target) && (current_sl > open_price);
      }
      
      if(should_be)
      {
         double new_sl = NormalizeDouble(open_price + (pos_type == POSITION_TYPE_BUY ? 1 : -1) * SymbolInfoDouble(sym, SYMBOL_POINT) * 5, digits);
         
         if(trade.PositionModify(ticket, new_sl, current_tp))
         {
            PrintFormat("BREAKEVEN: %s Ticket %d | SL moved to %.*f", sym, ticket, digits, new_sl);
            current_sl = new_sl;
         }
      }
      
      // ---- PARTIAL CLOSE AT TP1 (50%) ----
      double partial_target = risk_distance * InpMinRR; // TP1 at minimum RR
      bool should_partial = false;
      
      if(pos_type == POSITION_TYPE_BUY)
         should_partial = (current_price >= open_price + partial_target);
      else
         should_partial = (current_price <= open_price - partial_target);
      
      if(should_partial && volume > SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN))
      {
         double close_volume = NormalizeDouble(volume * (InpPartialClosePercent / 100.0), 2);
         double min_vol = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
         double lot_step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
         
         close_volume = MathMax(min_vol, close_volume);
         close_volume = NormalizeDouble(MathFloor(close_volume / lot_step) * lot_step, 2);
         
         // Only partial close if remaining would be >= min lot
         if((volume - close_volume) >= min_vol)
         {
            if(trade.PositionClosePartial(ticket, close_volume))
            {
               PrintFormat("PARTIAL CLOSE: %s Ticket %d | Closed %.2f lots (%.0f%%)", 
                  sym, ticket, close_volume, InpPartialClosePercent);
            }
         }
      }
      
      // ---- TRAILING STOP ----
      if(InpUseTrailingStop && current_sl >= open_price - SymbolInfoDouble(sym, SYMBOL_POINT))
      {
         // Only trail after breakeven
         double atr[];
         ArraySetAsSeries(atr, true);
         if(CopyBuffer(g_symbols[sym_index].atr_handle, 0, 0, 2, atr) >= 2)
         {
            double trail_distance = atr[1] * InpTrailingATRMult;
            double new_trail_sl = 0;
            
            if(pos_type == POSITION_TYPE_BUY)
            {
               new_trail_sl = NormalizeDouble(current_price - trail_distance, digits);
               if(new_trail_sl > current_sl && new_trail_sl > open_price)
               {
                  trade.PositionModify(ticket, new_trail_sl, current_tp);
                  PrintFormat("TRAIL: %s Ticket %d | SL trailed to %.*f", sym, ticket, digits, new_trail_sl);
               }
            }
            else
            {
               new_trail_sl = NormalizeDouble(current_price + trail_distance, digits);
               if(new_trail_sl < current_sl && new_trail_sl < open_price)
               {
                  trade.PositionModify(ticket, new_trail_sl, current_tp);
                  PrintFormat("TRAIL: %s Ticket %d | SL trailed to %.*f", sym, ticket, digits, new_trail_sl);
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| TREND CHANGE HANDLING (78.6% Break)                              |
//+------------------------------------------------------------------+
void HandleTrendChange(int sym_index, double current_price)
{
   string sym = g_symbols[sym_index].symbol;
   ENUM_TREND_BIAS old_bias = g_symbols[sym_index].htf_bias;
   ENUM_TREND_BIAS new_bias = (old_bias == TREND_BULLISH) ? TREND_BEARISH : TREND_BULLISH;
   
   PrintFormat("[%s] TREND CHANGE DETECTED: 78.6%% broken. Old bias: %s, Potential new: %s",
      sym, (old_bias == TREND_BULLISH) ? "BULLISH" : "BEARISH",
      (new_bias == TREND_BULLISH) ? "BULLISH" : "BEARISH");
   
   // Step 1: Wait for BOS confirmation in new direction
   bool bos_confirm = DetectBOS(sym, InpEntryTF, new_bias);
   if(!bos_confirm) return;
   
   // Step 2: Look for CHoCH
   bool choch_confirm = DetectCHoCH(sym, InpEntryTF, new_bias);
   
   // Step 3: Look for FVG created during the break
   double fvg_high = 0, fvg_low = 0;
   bool fvg_found = DetectFVG(sym, InpEntryTF, new_bias, fvg_high, fvg_low);
   
   // Step 4: Need BOS + (CHoCH or FVG) for trend change entry
   if(!bos_confirm || (!choch_confirm && !fvg_found)) return;
   
   PrintFormat("[%s] TREND CHANGE CONFIRMED: BOS + %s in %s direction",
      sym, choch_confirm ? "CHoCH" : "FVG",
      (new_bias == TREND_BULLISH) ? "BULLISH" : "BEARISH");
   
   // Update bias
   g_symbols[sym_index].htf_bias = new_bias;
   
   // Recalculate fib with new structure
   g_symbols[sym_index].fib = CalculateFibonacciLevels(sym_index);
   
   // Build and execute setup in new direction with reduced risk
   TradeSetup setup;
   if(BuildTradeSetup(sym_index, setup))
   {
      // Reduce risk during transition (use half the normal risk)
      setup.lot_size = NormalizeDouble(setup.lot_size * 0.5, 2);
      double min_lot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
      if(setup.lot_size >= min_lot)
      {
         setup.comment = "FibICT TrendChange";
         ExecuteTrade(setup, sym_index);
      }
   }
}

//+------------------------------------------------------------------+
//| UTILITY FUNCTIONS                                                |
//+------------------------------------------------------------------+
bool HasOpenPosition(string sym)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() == sym && posInfo.Magic() == InpMagicNumber)
         return true;
   }
   return false;
}

int CountOpenPositions(string sym)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() == sym && posInfo.Magic() == InpMagicNumber)
         count++;
   }
   return count;
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                    V I S U A L I Z A T I O N S                   |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Helper: Create/Update a horizontal line                          |
//+------------------------------------------------------------------+
void CreateHLine(string name, double price, color clr, int width, ENUM_LINE_STYLE style)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   }
   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| Helper: Create/Update a text label on chart                      |
//+------------------------------------------------------------------+
void CreateLabel(string name, int x, int y, string text, color clr, int font_size, ENUM_ANCHOR_POINT anchor = ANCHOR_LEFT_UPPER)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, font_size);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| Helper: Create a rectangle background for dashboard              |
//+------------------------------------------------------------------+
void CreateRectLabel(string name, int x, int y, int width, int height, color bg_color)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg_color);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrDimGray);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| DRAW DASHBOARD PANEL                                             |
//+------------------------------------------------------------------+
void DrawDashboard(int sym_index)
{
   int x = 15, y = 30;
   int line_height = (int)(InpDashFontSize * 1.8);
   int panel_width = 260;
   string sym = g_symbols[sym_index].symbol;
   ENUM_TREND_BIAS bias = g_symbols[sym_index].htf_bias;
   FibLevels fib = g_symbols[sym_index].fib;
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   
   // Determine active session
   string session_str = "None";
   color session_clr = clrGray;
   if(IsInSession(0)) { session_str = "LONDON"; session_clr = clrDodgerBlue; }
   if(IsInSession(1)) { session_str = "ASIAN"; session_clr = clrOrangeRed; }
   
   // Trend bias text
   string bias_str = "NEUTRAL";
   color bias_clr = clrGray;
   if(bias == TREND_BULLISH) { bias_str = "▲ BULLISH"; bias_clr = InpBullColor; }
   else if(bias == TREND_BEARISH) { bias_str = "▼ BEARISH"; bias_clr = InpBearColor; }
   
   // Price in fib zone?
   double price = SymbolInfoDouble(sym, SYMBOL_BID);
   string zone_str = "Outside";
   color zone_clr = clrGray;
   if(fib.is_valid)
   {
      if(IsPriceInFibZone(price, fib, bias)) { zone_str = "IN ZONE ✓"; zone_clr = InpBullColor; }
      else if(IsFibInvalidated(price, fib)) { zone_str = "INVALIDATED ✗"; zone_clr = InpBearColor; }
      else { zone_str = "Waiting..."; zone_clr = clrYellow; }
   }
   
   // Count total panel lines
   int total_lines = 12;
   if(fib.is_valid) total_lines += 4;
   int panel_height = total_lines * line_height + 15;
   
   // Background panel
   CreateRectLabel(g_obj_prefix + "dash_bg", x - 5, y - 5, panel_width, panel_height, InpDashBgColor);
   
   int row = 0;
   
   // Title
   CreateLabel(g_obj_prefix + "d_title", x, y + row * line_height, "══ FibonacciICT EA ══", clrGold, InpDashFontSize + 1);
   row++;
   CreateLabel(g_obj_prefix + "d_sep1", x, y + row * line_height, "─────────────────────────", clrDimGray, InpDashFontSize - 1);
   row++;
   
   // Symbol info
   double spread = SymbolInfoInteger(sym, SYMBOL_SPREAD) * SymbolInfoDouble(sym, SYMBOL_POINT);
   CreateLabel(g_obj_prefix + "d_sym", x, y + row * line_height, 
      StringFormat("Symbol:  %s", sym), InpDashTextColor, InpDashFontSize);
   row++;
   CreateLabel(g_obj_prefix + "d_price", x, y + row * line_height, 
      StringFormat("Price:   %.*f  Spread: %.1f", digits, price, SymbolInfoInteger(sym, SYMBOL_SPREAD) * 0.1), InpDashTextColor, InpDashFontSize);
   row++;
   
   // Trend
   CreateLabel(g_obj_prefix + "d_sep2", x, y + row * line_height, "─────────────────────────", clrDimGray, InpDashFontSize - 1);
   row++;
   CreateLabel(g_obj_prefix + "d_trend", x, y + row * line_height, 
      StringFormat("HTF Bias: %s", bias_str), bias_clr, InpDashFontSize);
   row++;
   
   // Session
   CreateLabel(g_obj_prefix + "d_session", x, y + row * line_height, 
      StringFormat("Session:  %s", session_str), session_clr, InpDashFontSize);
   row++;
   
   // Fib Zone Status
   CreateLabel(g_obj_prefix + "d_zone", x, y + row * line_height, 
      StringFormat("Fib Zone: %s", zone_str), zone_clr, InpDashFontSize);
   row++;
   
   // Trades
   CreateLabel(g_obj_prefix + "d_trades", x, y + row * line_height, 
      StringFormat("Trades:   %d / %d", g_symbols[sym_index].trades_this_session, InpMaxTradesPerSession), InpDashTextColor, InpDashFontSize);
   row++;
   
   // Fibonacci Levels
   if(fib.is_valid)
   {
      CreateLabel(g_obj_prefix + "d_sep3", x, y + row * line_height, "─────────────────────────", clrDimGray, InpDashFontSize - 1);
      row++;
      CreateLabel(g_obj_prefix + "d_fib_title", x, y + row * line_height, "Fibonacci Levels:", clrGold, InpDashFontSize);
      row++;
      CreateLabel(g_obj_prefix + "d_fib382", x, y + row * line_height, 
         StringFormat("  38.2%%:  %.*f", digits, fib.level_382), InpFibColor382, InpDashFontSize);
      row++;
      CreateLabel(g_obj_prefix + "d_fib500", x, y + row * line_height, 
         StringFormat("  50.0%%:  %.*f", digits, fib.level_500), InpFibColor500, InpDashFontSize);
      row++;
      CreateLabel(g_obj_prefix + "d_fib618", x, y + row * line_height, 
         StringFormat("  61.8%%:  %.*f", digits, fib.level_618), InpFibColor618, InpDashFontSize);
      row++;
      CreateLabel(g_obj_prefix + "d_fib786", x, y + row * line_height, 
         StringFormat("  78.6%%:  %.*f", digits, fib.level_786), InpFibColor786, InpDashFontSize);
      row++;
   }
   else
   {
      CreateLabel(g_obj_prefix + "d_sep3", x, y + row * line_height, "─────────────────────────", clrDimGray, InpDashFontSize - 1);
      row++;
      CreateLabel(g_obj_prefix + "d_fib_title", x, y + row * line_height, "Fibonacci: Calculating...", clrGray, InpDashFontSize);
      row++;
      // Clear old fib labels
      ObjectDelete(0, g_obj_prefix + "d_fib382");
      ObjectDelete(0, g_obj_prefix + "d_fib500");
      ObjectDelete(0, g_obj_prefix + "d_fib618");
      ObjectDelete(0, g_obj_prefix + "d_fib786");
   }
   
   // Open positions
   CreateLabel(g_obj_prefix + "d_sep4", x, y + row * line_height, "─────────────────────────", clrDimGray, InpDashFontSize - 1);
   row++;
   int open_pos = CountOpenPositions(sym);
   color pos_clr = (open_pos > 0) ? InpBullColor : clrGray;
   CreateLabel(g_obj_prefix + "d_pos", x, y + row * line_height, 
      StringFormat("Positions: %d", open_pos), pos_clr, InpDashFontSize);
   row++;
   
   // Account info
   CreateLabel(g_obj_prefix + "d_bal", x, y + row * line_height, 
      StringFormat("Balance:   $%.2f", AccountInfoDouble(ACCOUNT_BALANCE)), InpDashTextColor, InpDashFontSize);
   row++;
   CreateLabel(g_obj_prefix + "d_equity", x, y + row * line_height, 
      StringFormat("Equity:    $%.2f", AccountInfoDouble(ACCOUNT_EQUITY)), InpDashTextColor, InpDashFontSize);
   
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| DRAW FIBONACCI LINES                                             |
//+------------------------------------------------------------------+
void DrawFibonacciLevels(FibLevels &fib, ENUM_TREND_BIAS bias)
{
   if(!fib.is_valid) return;
   
   int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
   
   // Swing High/Low lines
   CreateHLine(g_obj_prefix + "fib_sh", fib.swing_high, clrSilver, 1, STYLE_SOLID);
   CreateHLine(g_obj_prefix + "fib_sl", fib.swing_low, clrSilver, 1, STYLE_SOLID);
   
   // Fib level lines
   CreateHLine(g_obj_prefix + "fib_382", fib.level_382, InpFibColor382, 1, STYLE_DASH);
   CreateHLine(g_obj_prefix + "fib_500", fib.level_500, InpFibColor500, 2, STYLE_DASH);
   CreateHLine(g_obj_prefix + "fib_618", fib.level_618, InpFibColor618, 1, STYLE_DOT);
   CreateHLine(g_obj_prefix + "fib_786", fib.level_786, InpFibColor786, 2, STYLE_DASHDOT);
   
   // Price labels on right side
   datetime label_time = iTime(Symbol(), InpEntryTF, 0) + PeriodSeconds(InpEntryTF) * 3;
   
   string labels[][2];
   ArrayResize(labels, 6);
   
   // Create text objects at price levels
   CreatePriceLabel(g_obj_prefix + "fib_lbl_sh", label_time, fib.swing_high, 
      StringFormat("── Swing High %.*f", digits, fib.swing_high), clrSilver);
   CreatePriceLabel(g_obj_prefix + "fib_lbl_sl", label_time, fib.swing_low, 
      StringFormat("── Swing Low %.*f", digits, fib.swing_low), clrSilver);
   CreatePriceLabel(g_obj_prefix + "fib_lbl_382", label_time, fib.level_382, 
      StringFormat("── 38.2%% %.*f", digits, fib.level_382), InpFibColor382);
   CreatePriceLabel(g_obj_prefix + "fib_lbl_500", label_time, fib.level_500, 
      StringFormat("── 50.0%% %.*f", digits, fib.level_500), InpFibColor500);
   CreatePriceLabel(g_obj_prefix + "fib_lbl_618", label_time, fib.level_618, 
      StringFormat("── 61.8%% %.*f", digits, fib.level_618), InpFibColor618);
   CreatePriceLabel(g_obj_prefix + "fib_lbl_786", label_time, fib.level_786, 
      StringFormat("── 78.6%% %.*f", digits, fib.level_786), InpFibColor786);
   
   // Entry zone rectangle (shaded area between 38.2% and 50%)
   double zone_top, zone_bottom;
   if(bias == TREND_BULLISH)
   {
      zone_top = fib.level_382;
      zone_bottom = fib.level_500;
   }
   else
   {
      zone_top = fib.level_500;
      zone_bottom = fib.level_382;
   }
   
   datetime rect_start = iTime(Symbol(), InpStructureTF, InpSwingLookback);
   datetime rect_end = iTime(Symbol(), InpEntryTF, 0) + PeriodSeconds(InpEntryTF) * 5;
   
   string rect_name = g_obj_prefix + "fib_zone";
   if(ObjectFind(0, rect_name) < 0)
      ObjectCreate(0, rect_name, OBJ_RECTANGLE, 0, rect_start, zone_top, rect_end, zone_bottom);
   else
   {
      ObjectSetInteger(0, rect_name, OBJPROP_TIME, 0, rect_start);
      ObjectSetDouble(0, rect_name, OBJPROP_PRICE, 0, zone_top);
      ObjectSetInteger(0, rect_name, OBJPROP_TIME, 1, rect_end);
      ObjectSetDouble(0, rect_name, OBJPROP_PRICE, 1, zone_bottom);
   }
   ObjectSetInteger(0, rect_name, OBJPROP_COLOR, (bias == TREND_BULLISH) ? C'0,80,0' : C'80,0,0');
   ObjectSetInteger(0, rect_name, OBJPROP_FILL, true);
   ObjectSetInteger(0, rect_name, OBJPROP_BACK, true);
   ObjectSetInteger(0, rect_name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, rect_name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| Helper: Price label at a specific time and price                  |
//+------------------------------------------------------------------+
void CreatePriceLabel(string name, datetime time, double price, string text, color clr)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, time, price);
   
   ObjectSetInteger(0, name, OBJPROP_TIME, time);
   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| DRAW SWING POINTS                                                |
//+------------------------------------------------------------------+
void DrawSwingPoints(int sym_index)
{
   string sym = g_symbols[sym_index].symbol;
   
   // Only draw on the chart's symbol
   if(sym != Symbol()) return;
   
   // Remove old swing arrows
   int obj_total = ObjectsTotal(0, 0);
   for(int k = obj_total - 1; k >= 0; k--)
   {
      string obj_name = ObjectGetString(0, ObjectName(0, k), OBJPROP_NAME);
      if(StringFind(obj_name, g_obj_prefix + "swing_") == 0)
         ObjectDelete(0, obj_name);
   }
   
   SwingPoint swings[];
   int count = DetectSwingPoints(sym, InpStructureTF, InpSwingLookback, swings);
   
   int max_display = MathMin(count, 20); // Limit display count
   
   for(int i = 0; i < max_display; i++)
   {
      string arrow_name = g_obj_prefix + StringFormat("swing_%d", i);
      
      if(swings[i].is_high)
      {
         // Swing High — down arrow above the high
         ObjectCreate(0, arrow_name, OBJ_ARROW, 0, swings[i].time, swings[i].price);
         ObjectSetInteger(0, arrow_name, OBJPROP_ARROWCODE, 218); // ▼ down triangle
         ObjectSetInteger(0, arrow_name, OBJPROP_COLOR, InpBearColor);
         ObjectSetInteger(0, arrow_name, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, arrow_name, OBJPROP_ANCHOR, ANCHOR_BOTTOM);
      }
      else
      {
         // Swing Low — up arrow below the low
         ObjectCreate(0, arrow_name, OBJ_ARROW, 0, swings[i].time, swings[i].price);
         ObjectSetInteger(0, arrow_name, OBJPROP_ARROWCODE, 217); // ▲ up triangle
         ObjectSetInteger(0, arrow_name, OBJPROP_COLOR, InpBullColor);
         ObjectSetInteger(0, arrow_name, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, arrow_name, OBJPROP_ANCHOR, ANCHOR_TOP);
      }
      
      ObjectSetInteger(0, arrow_name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, arrow_name, OBJPROP_HIDDEN, true);
   }
}

//+------------------------------------------------------------------+
//| DRAW BOS / CHoCH LABELS (called from detection functions)        |
//+------------------------------------------------------------------+
void DrawBOSLabel(string sym, datetime time, double price, bool is_bullish)
{
   if(!InpShowBOS || sym != Symbol()) return;
   
   static int bos_count = 0;
   bos_count++;
   string name = g_obj_prefix + StringFormat("bos_%d", bos_count);
   
   ObjectCreate(0, name, OBJ_TEXT, 0, time, price);
   ObjectSetString(0, name, OBJPROP_TEXT, is_bullish ? "BOS ▲" : "BOS ▼");
   ObjectSetInteger(0, name, OBJPROP_COLOR, is_bullish ? InpBullColor : InpBearColor);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, is_bullish ? ANCHOR_LOWER : ANCHOR_UPPER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void DrawCHoCHLabel(string sym, datetime time, double price, bool is_bullish)
{
   if(!InpShowBOS || sym != Symbol()) return;
   
   static int choch_count = 0;
   choch_count++;
   string name = g_obj_prefix + StringFormat("choch_%d", choch_count);
   
   ObjectCreate(0, name, OBJ_TEXT, 0, time, price);
   ObjectSetString(0, name, OBJPROP_TEXT, is_bullish ? "CHoCH ▲" : "CHoCH ▼");
   ObjectSetInteger(0, name, OBJPROP_COLOR, is_bullish ? clrCyan : clrMagenta);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, is_bullish ? ANCHOR_LOWER : ANCHOR_UPPER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| DRAW FVG ZONE                                                    |
//+------------------------------------------------------------------+
void DrawFVGZone(string sym, datetime time, double fvg_top, double fvg_bottom, bool is_bullish)
{
   if(!InpShowFVG || sym != Symbol()) return;
   
   static int fvg_count = 0;
   fvg_count++;
   string name = g_obj_prefix + StringFormat("fvg_%d", fvg_count);
   
   datetime end_time = time + PeriodSeconds(InpEntryTF) * 10;
   
   ObjectCreate(0, name, OBJ_RECTANGLE, 0, time, fvg_top, end_time, fvg_bottom);
   ObjectSetInteger(0, name, OBJPROP_COLOR, is_bullish ? InpFVGBullColor : InpFVGBearColor);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   
   // FVG label
   string lbl_name = g_obj_prefix + StringFormat("fvg_lbl_%d", fvg_count);
   ObjectCreate(0, lbl_name, OBJ_TEXT, 0, time, (fvg_top + fvg_bottom) / 2.0);
   ObjectSetString(0, lbl_name, OBJPROP_TEXT, "FVG");
   ObjectSetInteger(0, lbl_name, OBJPROP_COLOR, is_bullish ? clrLime : clrRed);
   ObjectSetInteger(0, lbl_name, OBJPROP_FONTSIZE, 7);
   ObjectSetString(0, lbl_name, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, lbl_name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, lbl_name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| DRAW SESSION BOXES                                               |
//+------------------------------------------------------------------+
void DrawSessionBoxes()
{
   // Draw session boxes for the last 5 days
   datetime current_time = TimeCurrent();
   
   for(int day = 0; day < 5; day++)
   {
      MqlDateTime dt;
      TimeToStruct(current_time - day * 86400, dt);
      
      // Skip weekends
      if(dt.day_of_week == 0 || dt.day_of_week == 6) continue;
      
      // London session box
      datetime london_start, london_end;
      dt.hour = InpLondonStartHour;
      dt.min = 0;
      dt.sec = 0;
      london_start = StructToTime(dt);
      dt.hour = InpLondonEndHour;
      london_end = StructToTime(dt);
      
      string lon_name = g_obj_prefix + StringFormat("session_lon_%d", day);
      double chart_high = ChartGetDouble(0, CHART_PRICE_MAX, 0);
      double chart_low = ChartGetDouble(0, CHART_PRICE_MIN, 0);
      
      if(ObjectFind(0, lon_name) < 0)
         ObjectCreate(0, lon_name, OBJ_RECTANGLE, 0, london_start, chart_high, london_end, chart_low);
      else
      {
         ObjectSetInteger(0, lon_name, OBJPROP_TIME, 0, london_start);
         ObjectSetDouble(0, lon_name, OBJPROP_PRICE, 0, chart_high);
         ObjectSetInteger(0, lon_name, OBJPROP_TIME, 1, london_end);
         ObjectSetDouble(0, lon_name, OBJPROP_PRICE, 1, chart_low);
      }
      ObjectSetInteger(0, lon_name, OBJPROP_COLOR, InpSessionLondonColor);
      ObjectSetInteger(0, lon_name, OBJPROP_FILL, true);
      ObjectSetInteger(0, lon_name, OBJPROP_BACK, true);
      ObjectSetInteger(0, lon_name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, lon_name, OBJPROP_HIDDEN, true);
      
      // Asian session box  
      datetime asian_start, asian_end;
      MqlDateTime dt2;
      TimeToStruct(current_time - day * 86400, dt2);
      
      // Asian wraps midnight
      dt2.hour = InpAsianStartHour;
      dt2.min = 0;
      dt2.sec = 0;
      if(InpAsianStartHour > InpAsianEndHour)
      {
         // Previous day start
         asian_start = StructToTime(dt2) - 86400;
         dt2.hour = InpAsianEndHour;
         asian_end = StructToTime(dt2);
      }
      else
      {
         asian_start = StructToTime(dt2);
         dt2.hour = InpAsianEndHour;
         asian_end = StructToTime(dt2);
      }
      
      string asia_name = g_obj_prefix + StringFormat("session_asia_%d", day);
      if(ObjectFind(0, asia_name) < 0)
         ObjectCreate(0, asia_name, OBJ_RECTANGLE, 0, asian_start, chart_high, asian_end, chart_low);
      else
      {
         ObjectSetInteger(0, asia_name, OBJPROP_TIME, 0, asian_start);
         ObjectSetDouble(0, asia_name, OBJPROP_PRICE, 0, chart_high);
         ObjectSetInteger(0, asia_name, OBJPROP_TIME, 1, asian_end);
         ObjectSetDouble(0, asia_name, OBJPROP_PRICE, 1, chart_low);
      }
      ObjectSetInteger(0, asia_name, OBJPROP_COLOR, InpSessionAsianColor);
      ObjectSetInteger(0, asia_name, OBJPROP_FILL, true);
      ObjectSetInteger(0, asia_name, OBJPROP_BACK, true);
      ObjectSetInteger(0, asia_name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, asia_name, OBJPROP_HIDDEN, true);
   }
}

//+------------------------------------------------------------------+
//| DRAW TRADE ENTRY ARROW                                           |
//+------------------------------------------------------------------+
void DrawTradeArrow(TradeSetup &setup)
{
   if(setup.symbol != Symbol()) return;
   
   static int trade_arrow_count = 0;
   trade_arrow_count++;
   
   int digits = (int)SymbolInfoInteger(setup.symbol, SYMBOL_DIGITS);
   datetime time = TimeCurrent();
   
   // Entry arrow
   string entry_name = g_obj_prefix + StringFormat("trade_entry_%d", trade_arrow_count);
   ObjectCreate(0, entry_name, OBJ_ARROW, 0, time, setup.entry_price);
   
   if(setup.direction == 1) // BUY
   {
      ObjectSetInteger(0, entry_name, OBJPROP_ARROWCODE, 233); // ▲ big up arrow
      ObjectSetInteger(0, entry_name, OBJPROP_COLOR, InpBullColor);
      ObjectSetInteger(0, entry_name, OBJPROP_ANCHOR, ANCHOR_TOP);
   }
   else // SELL
   {
      ObjectSetInteger(0, entry_name, OBJPROP_ARROWCODE, 234); // ▼ big down arrow
      ObjectSetInteger(0, entry_name, OBJPROP_COLOR, InpBearColor);
      ObjectSetInteger(0, entry_name, OBJPROP_ANCHOR, ANCHOR_BOTTOM);
   }
   ObjectSetInteger(0, entry_name, OBJPROP_WIDTH, 3);
   ObjectSetInteger(0, entry_name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, entry_name, OBJPROP_HIDDEN, true);
   
   // SL line
   string sl_name = g_obj_prefix + StringFormat("trade_sl_%d", trade_arrow_count);
   datetime sl_end = time + PeriodSeconds(InpEntryTF) * 20;
   ObjectCreate(0, sl_name, OBJ_TREND, 0, time, setup.stop_loss, sl_end, setup.stop_loss);
   ObjectSetInteger(0, sl_name, OBJPROP_COLOR, InpBearColor);
   ObjectSetInteger(0, sl_name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, sl_name, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, sl_name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, sl_name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, sl_name, OBJPROP_HIDDEN, true);
   
   // TP line
   string tp_name = g_obj_prefix + StringFormat("trade_tp_%d", trade_arrow_count);
   ObjectCreate(0, tp_name, OBJ_TREND, 0, time, setup.take_profit, sl_end, setup.take_profit);
   ObjectSetInteger(0, tp_name, OBJPROP_COLOR, InpBullColor);
   ObjectSetInteger(0, tp_name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, tp_name, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, tp_name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, tp_name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, tp_name, OBJPROP_HIDDEN, true);
   
   // Trade info label
   string info_name = g_obj_prefix + StringFormat("trade_info_%d", trade_arrow_count);
   double label_price = (setup.direction == 1) ? setup.entry_price - 10 * SymbolInfoDouble(setup.symbol, SYMBOL_POINT) 
                                               : setup.entry_price + 10 * SymbolInfoDouble(setup.symbol, SYMBOL_POINT);
   double rr = MathAbs(setup.take_profit - setup.entry_price) / MathAbs(setup.entry_price - setup.stop_loss);
   
   ObjectCreate(0, info_name, OBJ_TEXT, 0, time, label_price);
   ObjectSetString(0, info_name, OBJPROP_TEXT, 
      StringFormat("%s %.2f lots | RR: %.1f", (setup.direction == 1) ? "BUY" : "SELL", setup.lot_size, rr));
   ObjectSetInteger(0, info_name, OBJPROP_COLOR, (setup.direction == 1) ? InpBullColor : InpBearColor);
   ObjectSetInteger(0, info_name, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, info_name, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, info_name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, info_name, OBJPROP_HIDDEN, true);
   
   ChartRedraw(0);
}
//+------------------------------------------------------------------+

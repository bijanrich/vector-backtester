import pandas as pd
import numpy as np
from datetime import datetime, time
import traceback
import argparse
import time as time_lib

# Import strategies
from strategies.intraday.trend.intraday_trend import IntradayTrendStrategy
from strategies.intraday.breakout.orb import OpenRangeBreakoutStrategy
from strategies.intraday.breakout.range_extension import RangeExtensionStrategy
from strategies.intraday.hooks.bull_hook import BullHookStrategy
from strategies.intraday.hooks.bear_hook import BearHookStrategy
from strategies.intraday.breakout.adaptive_orb import AdaptiveORB
from strategies.intraday.volatility.nr7_breakout import NR7BreakoutStrategy
from strategies.intraday.volatility.inside_day_breakout import InsideDayBreakoutStrategy
from strategies.intraday.volatility.stretch_breakout import StretchBreakoutStrategy
from strategies.intraday.breakout.range_extension_vectorized import RangeExtensionVectorized
from strategies.intraday.bollinger_volume_strategy import BollingerVolumeStrategy

# Strategy mapping
STRATEGIES = {
    'intraday_trend': IntradayTrendStrategy,
    'orb': OpenRangeBreakoutStrategy,
    'range_extension': RangeExtensionStrategy,
    'range_extension_vectorized': RangeExtensionVectorized,
    'bull_hook': BullHookStrategy,
    'bear_hook': BearHookStrategy,
    'adaptive_orb': AdaptiveORB,
    'nr7_breakout': NR7BreakoutStrategy,
    'inside_day_breakout': InsideDayBreakoutStrategy,
    'stretch_breakout': StretchBreakoutStrategy,
    'bollinger_volume': BollingerVolumeStrategy
}

def calculate_portfolio_metrics(signals, data):
    """Calculate portfolio performance metrics."""
    print("\nCalculating portfolio metrics...")
    start_time = time_lib.time()
    
    # Calculate returns based on signals
    print("Calculating position returns...")
    data['position'] = signals.shift(1).fillna(0)
    data['returns'] = data['close'].pct_change()
    data['strategy_returns'] = data['position'] * data['returns']
    
    # Calculate metrics
    print("Computing performance metrics...")
    total_return = (1 + data['strategy_returns']).prod() - 1
    daily_returns = data.groupby(data.index.date)['strategy_returns'].sum()
    
    # Risk metrics
    excess_returns = daily_returns - 0.0  # Assuming 0% risk-free rate
    downside_returns = excess_returns[excess_returns < 0]
    
    sharpe_ratio = np.sqrt(252) * excess_returns.mean() / excess_returns.std() if len(excess_returns) > 0 else 0
    sortino_ratio = np.sqrt(252) * excess_returns.mean() / downside_returns.std() if len(downside_returns) > 0 else 0
    
    # Drawdown calculation
    print("Calculating drawdowns...")
    cum_returns = (1 + data['strategy_returns']).cumprod()
    rolling_max = cum_returns.expanding().max()
    drawdowns = (cum_returns - rolling_max) / rolling_max
    max_drawdown = drawdowns.min()
    
    # Trade analysis
    print("Analyzing trades...")
    trades = signals[signals != 0]
    n_trades = len(trades)
    
    # Win rate calculation
    trade_returns = []
    current_position = 0
    entry_price = 0
    
    for i in range(len(data)):
        if signals.iloc[i] != 0 and current_position == 0:  # Entry
            current_position = signals.iloc[i]
            entry_price = data['close'].iloc[i]
        elif signals.iloc[i] == 0 and current_position != 0:  # Exit
            exit_price = data['close'].iloc[i]
            returns = (exit_price - entry_price) / entry_price * current_position
            trade_returns.append(returns)
            current_position = 0
    
    winning_trades = sum(1 for r in trade_returns if r > 0)
    win_rate = winning_trades / len(trade_returns) if trade_returns else 0
    
    # Calculate profit factor
    gross_profits = sum(r for r in trade_returns if r > 0)
    gross_losses = abs(sum(r for r in trade_returns if r < 0))
    profit_factor = gross_profits / gross_losses if gross_losses != 0 else float('inf')
    
    # Calculate average trade duration
    trade_durations = []
    entry_time = None
    
    for i in range(len(data)):
        if signals.iloc[i] != 0 and entry_time is None:  # Entry
            entry_time = data.index[i]
        elif signals.iloc[i] == 0 and entry_time is not None:  # Exit
            exit_time = data.index[i]
            duration = (exit_time - entry_time).total_seconds() / 60  # Convert to minutes
            trade_durations.append(duration)
            entry_time = None
    
    avg_trade_duration = np.mean(trade_durations) if trade_durations else 0
    
    end_time = time_lib.time()
    print(f"Performance calculation completed in {end_time - start_time:.1f} seconds")
    
    return {
        'total_return': float(total_return),
        'sharpe_ratio': float(sharpe_ratio),
        'sortino_ratio': float(sortino_ratio),
        'max_drawdown': float(max_drawdown),
        'win_rate': float(win_rate * 100),  # Convert to percentage
        'profit_factor': float(profit_factor),
        'n_trades': n_trades,
        'avg_trade_duration': float(avg_trade_duration)
    }

def run_strategy(strategy, data):
    """Run a single strategy and return performance metrics."""
    try:
        start_time = time_lib.time()
        signals = strategy.generate_signals(data)
        metrics = calculate_portfolio_metrics(signals, data.copy())
        metrics_copy = metrics.copy()
        metrics_copy['strategy'] = strategy.name
        
        end_time = time_lib.time()
        print(f"\nStrategy execution completed in {end_time - start_time:.1f} seconds")
        return metrics_copy
    except Exception as e:
        print(f"Error running {strategy.name}:")
        traceback.print_exc()
        return None

def main():
    parser = argparse.ArgumentParser(description='Run backtests on cryptocurrency data')
    parser.add_argument('--strategies', nargs='+', choices=list(STRATEGIES.keys()) + ['all'],
                      default=['all'], help='Strategies to run (default: all)')
    args = parser.parse_args()
    
    total_start_time = time_lib.time()
    
    # Load data
    print("Loading data...")
    data = pd.read_csv('data/btc_all_features.csv')
    data['timestamp'] = pd.to_datetime(data['timestamp'])
    data.set_index('timestamp', inplace=True)
    print(f"Loaded {len(data)} bars from {data.index[0]} to {data.index[-1]}")
    
    # Initialize strategies
    if 'all' in args.strategies:
        strategies = [cls() for cls in STRATEGIES.values()]
    else:
        strategies = [STRATEGIES[name]() for name in args.strategies]
    
    # Run each strategy
    results = []
    for strategy in strategies:
        print(f"\nRunning {strategy.name}...")
        metrics = run_strategy(strategy, data)
        if metrics:
            results.append(metrics)
            print("\nPerformance Metrics:")
            print("=" * 50)
            print(f"Total Return: {metrics['total_return']*100:.2f}%")
            print(f"Sharpe Ratio: {metrics['sharpe_ratio']:.2f}")
            print(f"Sortino Ratio: {metrics['sortino_ratio']:.2f}")
            print(f"Max Drawdown: {metrics['max_drawdown']*100:.2f}%")
            print(f"Win Rate: {metrics['win_rate']:.2f}%")
            print(f"Profit Factor: {metrics['profit_factor']:.2f}")
            print(f"Number of Trades: {metrics['n_trades']}")
            print(f"Avg Trade Duration: {metrics['avg_trade_duration']:.2f} minutes")
    
    # Save results to CSV
    if results:
        results_df = pd.DataFrame(results)
        results_df.to_csv('backtest_results.csv', index=False)
        print("\nResults have been saved to 'backtest_results.csv'")
    
    total_end_time = time_lib.time()
    print(f"\nTotal execution time: {total_end_time - total_start_time:.1f} seconds")

if __name__ == "__main__":
    main() 
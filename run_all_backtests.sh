#!/bin/bash

# Default date range
START_DATE=${1:-2023-01-01}
END_DATE=${2:-2024-01-01}

# Get all available strategies
STRATEGIES=$(ls strategies/ | sed 's/_strategy.sql//g')

# Get all available symbols
SYMBOLS=$(clickhouse client --query "SELECT DISTINCT symbol FROM binance.klines" --format CSV | tr -d '"')

# Create results directory if it doesn't exist
mkdir -p results

# Clear previous results
echo "strategy,symbol,trades,long_trades,short_trades,avg_pnl,avg_pnl_percent,total_pnl,avg_duration_hours" > results/backtest_results.csv

echo "Running all strategies on all symbols..."
echo "Date Range: $START_DATE to $END_DATE"
echo "========================================"

# First, clear all trades
clickhouse client --query "TRUNCATE TABLE backtest.trades"

# Loop through all strategies and symbols
for STRATEGY in $STRATEGIES; do
    for SYMBOL in $SYMBOLS; do
        echo "Running $STRATEGY on $SYMBOL..."
        
        # Run the backtest
        ./run_backtest.sh "$STRATEGY" "$SYMBOL" "$START_DATE" "$END_DATE" > /dev/null
        
        # Get the results and append to CSV
        clickhouse client --query "
        SELECT 
            '$STRATEGY' AS strategy,
            '$SYMBOL' AS symbol,
            count(*) AS trades,
            countIf(direction = 'LONG') AS long_trades,
            countIf(direction = 'SHORT') AS short_trades,
            round(avg(pnl), 2) AS avg_pnl,
            round(avg(pnl_percent), 2) AS avg_pnl_percent,
            round(sum(pnl), 2) AS total_pnl,
            round(avg(trade_duration_hours), 2) AS avg_duration_hours
        FROM backtest.trades
        WHERE strategy = '$STRATEGY' AND symbol = '$SYMBOL'
        FORMAT CSV
        " >> results/backtest_results.csv
        
        echo "  Done."
    done
done

echo "========================================"
echo "All backtests completed."
echo "Results saved to results/backtest_results.csv"

# Display top performing strategy-symbol combinations
echo "Top 10 performing strategy-symbol combinations:"
cat results/backtest_results.csv | sort -t, -k8,8nr | head -11 | column -t -s,

echo "Bottom 10 performing strategy-symbol combinations:"
cat results/backtest_results.csv | sort -t, -k8,8n | head -11 | column -t -s, 
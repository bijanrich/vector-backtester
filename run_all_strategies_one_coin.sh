#!/bin/bash

# Check if symbol is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <symbol> [start_date] [end_date]"
    echo "Available symbols: $(clickhouse client --query "SELECT DISTINCT symbol FROM binance.klines" --format CSV | tr -d '"' | tr '\n' ' ')"
    exit 1
fi

SYMBOL=$1
START_DATE=${2:-2023-01-01}
END_DATE=${3:-2024-01-01}

# Get all available strategies
STRATEGIES=$(ls strategies/ | sed 's/_strategy.sql//g')

# Create results directory if it doesn't exist
mkdir -p results

# Clear previous results for this symbol
echo "strategy,trades,long_trades,short_trades,avg_pnl,avg_pnl_percent,total_pnl,avg_duration_hours" > "results/${SYMBOL}_results.csv"

echo "Running all strategies on $SYMBOL..."
echo "Date Range: $START_DATE to $END_DATE"
echo "========================================"

# Loop through all strategies
for STRATEGY in $STRATEGIES; do
    echo "Running $STRATEGY on $SYMBOL..."
    
    # Run the backtest
    ./run_backtest.sh "$STRATEGY" "$SYMBOL" "$START_DATE" "$END_DATE" > /dev/null
    
    # Get the results and append to CSV
    clickhouse client --query "
    SELECT 
        '$STRATEGY' AS strategy,
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
    " >> "results/${SYMBOL}_results.csv"
    
    echo "  Done."
done

echo "========================================"
echo "All strategy backtests for $SYMBOL completed."
echo "Results saved to results/${SYMBOL}_results.csv"

# Display top performing strategies for this symbol
echo "Top performing strategies for $SYMBOL:"
cat "results/${SYMBOL}_results.csv" | sort -t, -k7,7nr | head -11 | column -t -s, 
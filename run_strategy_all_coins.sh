#!/bin/bash

# Check if strategy name is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <strategy_name> [start_date] [end_date]"
    echo "Available strategies: $(ls strategies/ | sed 's/_strategy.sql//g' | tr '\n' ' ')"
    exit 1
fi

STRATEGY=$1
START_DATE=${2:-2023-01-01}
END_DATE=${3:-2024-01-01}

# Check if strategy file exists
STRATEGY_FILE="strategies/${STRATEGY}_strategy.sql"
if [ ! -f "$STRATEGY_FILE" ]; then
    echo "Strategy file not found: $STRATEGY_FILE"
    echo "Available strategies: $(ls strategies/ | sed 's/_strategy.sql//g' | tr '\n' ' ')"
    exit 1
fi

# Get all available symbols
SYMBOLS=$(clickhouse client --query "SELECT DISTINCT symbol FROM binance.klines" --format CSV | tr -d '"')

# Create results directory if it doesn't exist
mkdir -p results

# Clear previous results for this strategy
echo "symbol,trades,long_trades,short_trades,avg_pnl,avg_pnl_percent,total_pnl,avg_duration_hours" > "results/${STRATEGY}_results.csv"

echo "Running $STRATEGY on all symbols..."
echo "Date Range: $START_DATE to $END_DATE"
echo "========================================"

# Loop through all symbols
for SYMBOL in $SYMBOLS; do
    echo "Running $STRATEGY on $SYMBOL..."
    
    # Run the backtest
    ./run_backtest.sh "$STRATEGY" "$SYMBOL" "$START_DATE" "$END_DATE" > /dev/null
    
    # Get the results and append to CSV
    clickhouse client --query "
    SELECT 
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
    " >> "results/${STRATEGY}_results.csv"
    
    echo "  Done."
done

echo "========================================"
echo "All backtests for $STRATEGY completed."
echo "Results saved to results/${STRATEGY}_results.csv"

# Display top performing symbols for this strategy
echo "Top performing symbols for $STRATEGY:"
cat "results/${STRATEGY}_results.csv" | sort -t, -k7,7nr | head -11 | column -t -s, 
#!/bin/bash

# Check if strategy name is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <strategy_name> [symbol] [start_date] [end_date]"
    echo "Available strategies: $(ls strategies/ | sed 's/_strategy.sql//g' | tr '\n' ' ')"
    echo "Default symbol: BTCUSDT"
    echo "Default start_date: 2023-01-01"
    echo "Default end_date: 2024-01-01"
    exit 1
fi

STRATEGY=$1
SYMBOL=${2:-BTCUSDT}
START_DATE=${3:-2023-01-01}
END_DATE=${4:-2024-01-01}
STRATEGY_FILE="strategies/${STRATEGY}_strategy.sql"

# Check if strategy file exists
if [ ! -f "$STRATEGY_FILE" ]; then
    echo "Strategy file not found: $STRATEGY_FILE"
    echo "Available strategies: $(ls strategies/ | sed 's/_strategy.sql//g' | tr '\n' ' ')"
    exit 1
fi

# Create backtest database if it doesn't exist
echo "Creating backtest database if it doesn't exist..."
clickhouse client --query "CREATE DATABASE IF NOT EXISTS backtest"

# Ensure trades table exists
echo "Ensuring trades table exists..."
clickhouse client --multiquery < create_trades_table.sql

# Create tmp directory if it doesn't exist
mkdir -p tmp

# Create a temporary file with the parameters replaced
TEMP_STRATEGY_FILE="tmp/${STRATEGY}_${SYMBOL}.sql"
cat "$STRATEGY_FILE" > "$TEMP_STRATEGY_FILE"

# Replace symbol placeholders
sed -i '' "s/\[SYMBOL\]/$SYMBOL/g" "$TEMP_STRATEGY_FILE"
sed -i '' "s/symbol = '[A-Z]*USDT'/symbol = '$SYMBOL'/g" "$TEMP_STRATEGY_FILE"
sed -i '' "s/strategy = '[a-z_]*' AND symbol = '\[SYMBOL\]'/strategy = '$STRATEGY' AND symbol = '$SYMBOL'/g" "$TEMP_STRATEGY_FILE"

# Replace date ranges - first attempt with specific pattern
sed -i '' "s/open_time >= toDateTime('2023-01-01/open_time >= toDateTime('$START_DATE/g" "$TEMP_STRATEGY_FILE"
sed -i '' "s/open_time < toDateTime('2024-01-01/open_time < toDateTime('$END_DATE/g" "$TEMP_STRATEGY_FILE"

# Replace date ranges - second attempt with more general pattern
sed -i '' "s/open_time >= toDateTime('[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}/open_time >= toDateTime('$START_DATE/g" "$TEMP_STRATEGY_FILE"
sed -i '' "s/open_time < toDateTime('[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}/open_time < toDateTime('$END_DATE/g" "$TEMP_STRATEGY_FILE"

# Run the strategy
echo "Running $STRATEGY strategy backtest..."
echo "Symbol: $SYMBOL"
echo "Date Range: $START_DATE to $END_DATE"
echo "Executing query from $TEMP_STRATEGY_FILE..."
clickhouse client --multiquery < "$TEMP_STRATEGY_FILE"

# Display summary of trades for this strategy
echo "Trade summary for $STRATEGY:"
clickhouse client --query "
SELECT 
    count(*) AS total_trades,
    countIf(direction = 'LONG') AS long_trades,
    countIf(direction = 'SHORT') AS short_trades,
    round(avg(pnl), 2) AS avg_pnl,
    round(avg(pnl_percent), 2) AS avg_pnl_percent,
    round(sum(pnl), 2) AS total_pnl,
    round(avg(trade_duration_hours), 2) AS avg_duration_hours,
    formatDateTime(min(entry_time), '%Y-%m-%d %H:%M:%S') AS first_trade,
    formatDateTime(max(exit_time), '%Y-%m-%d %H:%M:%S') AS last_trade
FROM backtest.trades
WHERE strategy = '$STRATEGY' AND symbol = '$SYMBOL'
" --format PrettyCompactMonoBlock

# Display recent trades
echo "Recent trades:"
clickhouse client --query "
SELECT 
    formatDateTime(entry_time, '%Y-%m-%d %H:%M:%S') AS entry_time,
    formatDateTime(exit_time, '%Y-%m-%d %H:%M:%S') AS exit_time,
    entry_price,
    exit_price,
    direction,
    round(pnl, 2) AS pnl,
    round(pnl_percent, 2) AS pnl_percent,
    trade_duration_hours
FROM backtest.trades
WHERE strategy = '$STRATEGY' AND symbol = '$SYMBOL'
ORDER BY entry_time DESC
LIMIT 10
" --format PrettyCompactMonoBlock

echo "Backtest completed. Results stored in backtest database."
echo "To view all trades, run:"
echo "  clickhouse client --query \"SELECT * FROM backtest.trades WHERE strategy = '$STRATEGY' AND symbol = '$SYMBOL' ORDER BY entry_time\""
echo ""
echo "To view all strategies' performance, run:"
echo "  clickhouse client --query \"SELECT strategy, symbol, count(*) as trades, round(avg(pnl_percent), 2) as avg_pnl_pct, round(sum(pnl), 2) as total_pnl FROM backtest.trades GROUP BY strategy, symbol ORDER BY total_pnl DESC\"" 
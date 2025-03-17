-- Create a single trades table to store results from all strategies
CREATE TABLE IF NOT EXISTS backtest.trades (
    strategy String,
    symbol String,
    entry_time DateTime,
    exit_time DateTime,
    entry_price Float64,
    exit_price Float64,
    direction String, -- 'LONG' or 'SHORT'
    pnl Float64,
    pnl_percent Float64,
    trade_duration_hours Float64
) ENGINE = MergeTree()
ORDER BY (strategy, entry_time); 
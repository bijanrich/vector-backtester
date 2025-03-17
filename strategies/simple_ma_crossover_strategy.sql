-- Simple Moving Average Crossover Strategy
-- Parameters:
-- Symbol: [SYMBOL]
-- Timeframe: 15m
-- Fast MA: 20 periods
-- Slow MA: 50 periods
-- Date Range: 2023-06-01 to 2023-12-31

-- First, clear any existing trades for this strategy
ALTER TABLE backtest.trades DELETE WHERE strategy = 'simple_ma_crossover' AND symbol = '[SYMBOL]';

-- Calculate signals and insert trades directly
WITH 
resampled AS (
    SELECT
        symbol,
        toStartOfInterval(open_time, INTERVAL 15 MINUTE) AS interval_start,
        argMin(open, open_time) AS open,
        max(high) AS high,
        min(low) AS low,
        argMax(close, open_time) AS close,
        sum(volume) AS volume,
        count() AS candle_count
    FROM binance.klines
    WHERE symbol = '[SYMBOL]'
    AND open_time >= toDateTime('2023-06-01 00:00:00')
    AND open_time < toDateTime('2024-01-01 00:00:00')
    GROUP BY symbol, interval_start
    HAVING candle_count > 0
    ORDER BY interval_start
),
moving_averages AS (
    SELECT
        symbol,
        interval_start,
        open,
        high,
        low,
        close,
        volume,
        avg(close) OVER (PARTITION BY symbol ORDER BY interval_start ROWS BETWEEN 19 PRECEDING AND CURRENT ROW) AS fast_ma,
        avg(close) OVER (PARTITION BY symbol ORDER BY interval_start ROWS BETWEEN 49 PRECEDING AND CURRENT ROW) AS slow_ma
    FROM resampled
),
numbered_ma AS (
    SELECT
        symbol,
        interval_start,
        open,
        high,
        low,
        close,
        volume,
        fast_ma,
        slow_ma,
        row_number() OVER (PARTITION BY symbol ORDER BY interval_start) AS row_num
    FROM moving_averages
    WHERE fast_ma IS NOT NULL AND slow_ma IS NOT NULL
),
signals AS (
    SELECT
        a.symbol,
        a.interval_start,
        a.close,
        a.fast_ma > a.slow_ma AS uptrend,
        a.fast_ma > a.slow_ma AND b.fast_ma <= b.slow_ma AS entry_long,
        a.fast_ma < a.slow_ma AND b.fast_ma >= b.slow_ma AS entry_short,
        a.fast_ma < a.slow_ma AND b.fast_ma >= b.slow_ma AS exit_long,
        a.fast_ma > a.slow_ma AND b.fast_ma <= b.slow_ma AS exit_short
    FROM numbered_ma a
    JOIN numbered_ma b ON a.row_num = b.row_num + 1 AND a.symbol = b.symbol
),
-- Insert LONG trades
long_entries AS (
    SELECT 
        interval_start AS entry_time,
        symbol,
        close AS entry_price,
        row_number() OVER (ORDER BY interval_start) AS entry_id
    FROM signals
    WHERE entry_long = 1
),
long_exits AS (
    SELECT 
        interval_start AS exit_time,
        symbol,
        close AS exit_price,
        row_number() OVER (ORDER BY interval_start) AS exit_id
    FROM signals
    WHERE exit_long = 1
),
long_paired_trades AS (
    SELECT
        e.symbol,
        e.entry_time,
        e.entry_price,
        min(x.exit_time) AS exit_time,
        min(x.exit_price) AS exit_price
    FROM long_entries e
    JOIN long_exits x ON x.exit_time > e.entry_time AND x.symbol = e.symbol
    GROUP BY e.symbol, e.entry_time, e.entry_price
    HAVING exit_time IS NOT NULL
),
-- Insert SHORT trades
short_entries AS (
    SELECT 
        interval_start AS entry_time,
        symbol,
        close AS entry_price,
        row_number() OVER (ORDER BY interval_start) AS entry_id
    FROM signals
    WHERE entry_short = 1
),
short_exits AS (
    SELECT 
        interval_start AS exit_time,
        symbol,
        close AS exit_price,
        row_number() OVER (ORDER BY interval_start) AS exit_id
    FROM signals
    WHERE exit_short = 1
),
short_paired_trades AS (
    SELECT
        e.symbol,
        e.entry_time,
        e.entry_price,
        min(x.exit_time) AS exit_time,
        min(x.exit_price) AS exit_price
    FROM short_entries e
    JOIN short_exits x ON x.exit_time > e.entry_time AND x.symbol = e.symbol
    GROUP BY e.symbol, e.entry_time, e.entry_price
    HAVING exit_time IS NOT NULL
)
-- Insert all trades into the trades table
INSERT INTO backtest.trades
-- LONG trades
SELECT
    'simple_ma_crossover' AS strategy,
    symbol,
    entry_time,
    exit_time,
    entry_price,
    exit_price,
    'LONG' AS direction,
    (exit_price - entry_price) AS pnl,
    (exit_price - entry_price) / entry_price * 100 AS pnl_percent,
    dateDiff('hour', entry_time, exit_time) AS trade_duration_hours
FROM long_paired_trades

UNION ALL

-- SHORT trades
SELECT
    'simple_ma_crossover' AS strategy,
    symbol,
    entry_time,
    exit_time,
    entry_price,
    exit_price,
    'SHORT' AS direction,
    (entry_price - exit_price) AS pnl, -- For shorts, profit is entry - exit
    (entry_price - exit_price) / entry_price * 100 AS pnl_percent,
    dateDiff('hour', entry_time, exit_time) AS trade_duration_hours
FROM short_paired_trades
ORDER BY entry_time; 
-- Intraday Trend Following Strategy
-- Parameters:
-- Symbol: [SYMBOL]
-- Timeframe: 5m
-- Session time: 09:00 - 11:00
-- Entry time: 10:00
-- Trend period: Morning session (09:00 - 10:00)
-- Momentum threshold: 0.001 (0.1%)
-- Date Range: 2023-01-01 to 2023-12-31

-- First, clear any existing trades for this strategy
ALTER TABLE backtest.trades DELETE WHERE strategy = 'intraday_trend' AND symbol = '[SYMBOL]';

-- Calculate signals and insert trades directly
WITH 
resampled AS (
    SELECT
        symbol,
        toStartOfInterval(open_time, INTERVAL 5 MINUTE) AS interval_start,
        toDate(open_time) AS trade_date,
        concat(toString(toHour(interval_start)), ':', toString(toMinute(interval_start))) AS time_of_day,
        argMin(open, open_time) AS open,
        max(high) AS high,
        min(low) AS low,
        argMax(close, open_time) AS close,
        count() AS candle_count
    FROM binance.klines
    WHERE symbol = '[SYMBOL]'
    AND open_time >= toDateTime('2023-01-01 00:00:00')
    AND open_time < toDateTime('2024-01-01 00:00:00')
    GROUP BY symbol, interval_start, trade_date
    HAVING candle_count > 0
    ORDER BY interval_start
),
daily_data AS (
    SELECT
        symbol,
        trade_date,
        interval_start,
        time_of_day,
        open,
        high,
        low,
        close,
        toHour(interval_start) >= 9 AND toHour(interval_start) < 11 AS in_session,
        toHour(interval_start) >= 10 AS after_entry_time,
        toHour(interval_start) = 10 AND toMinute(interval_start) = 0 AS is_entry_time,
        toHour(interval_start) = 11 AND toMinute(interval_start) = 0 AS is_exit_time
    FROM resampled
    ORDER BY interval_start
),
morning_trends AS (
    SELECT
        symbol,
        trade_date,
        max(high) - min(low) AS morning_range,
        (max(close) - min(open)) / min(open) AS momentum,
        CASE
            WHEN (max(close) - min(open)) / min(open) > 0.001 THEN 1
            WHEN (max(close) - min(open)) / min(open) < -0.001 THEN -1
            ELSE 0
        END AS trade_direction
    FROM daily_data
    WHERE in_session AND NOT after_entry_time
    GROUP BY symbol, trade_date
    HAVING morning_range > 0
),
entry_signals AS (
    SELECT
        d.interval_start AS entry_time,
        d.trade_date,
        d.symbol,
        d.close AS entry_price,
        m.trade_direction,
        CASE
            WHEN d.is_entry_time AND m.trade_direction = 1 THEN 'BUY'
            WHEN d.is_entry_time AND m.trade_direction = -1 THEN 'SELL'
            ELSE NULL
        END AS signal
    FROM daily_data d
    JOIN morning_trends m ON d.trade_date = m.trade_date AND d.symbol = m.symbol
    WHERE d.is_entry_time AND m.trade_direction != 0
),
exit_signals AS (
    SELECT
        symbol,
        interval_start AS exit_time,
        trade_date,
        close AS exit_price
    FROM daily_data
    WHERE is_exit_time
),
paired_trades AS (
    SELECT
        e.symbol,
        e.entry_time,
        e.entry_price,
        e.signal,
        x.exit_time,
        x.exit_price
    FROM entry_signals e
    JOIN exit_signals x ON e.trade_date = x.trade_date AND e.symbol = x.symbol
)
-- Insert trades into the trades table
INSERT INTO backtest.trades
SELECT
    'intraday_trend' AS strategy,
    symbol,
    entry_time,
    exit_time,
    entry_price,
    exit_price,
    CASE
        WHEN signal = 'BUY' THEN 'LONG'
        WHEN signal = 'SELL' THEN 'SHORT'
    END AS direction,
    CASE
        WHEN signal = 'BUY' THEN (exit_price - entry_price)
        WHEN signal = 'SELL' THEN (entry_price - exit_price)
    END AS pnl,
    CASE
        WHEN signal = 'BUY' THEN (exit_price - entry_price) / entry_price * 100
        WHEN signal = 'SELL' THEN (entry_price - exit_price) / entry_price * 100
    END AS pnl_percent,
    dateDiff('hour', entry_time, exit_time) AS trade_duration_hours
FROM paired_trades
ORDER BY entry_time; 
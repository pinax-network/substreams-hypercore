-- OHLCV view for fills --
-- Provides a convenient interface for querying OHLCV data with merged aggregates
CREATE VIEW IF NOT EXISTS ohlcv_fills AS
SELECT
    -- bar interval --
    timestamp,
    interval_min,

    -- timestamp & block number --
    min(min_timestamp) AS min_timestamp,
    max(max_timestamp) AS max_timestamp,
    min(min_block_num) AS min_block_num,
    max(max_block_num) AS max_block_num,

    -- trading identity --
    coin,

    -- OHLC --
    argMinMerge(open) AS open,
    quantileDeterministicMerge(0.95)(quantile) AS high,
    quantileDeterministicMerge(0.05)(quantile) AS low,
    argMaxMerge(close) AS close,

    -- volume by side --
    sum(t.buy_volume) AS buy_volume,
    sum(t.ask_volume) AS ask_volume,

    -- volume by direction --
    sum(open_long_volume) AS open_long_volume,
    sum(close_long_volume) AS close_long_volume,
    sum(open_short_volume) AS open_short_volume,
    sum(close_short_volume) AS close_short_volume,

    -- derived volume --
    sum(t.buy_volume) + sum(t.ask_volume) AS gross_volume,
    sum(t.buy_volume) - sum(t.ask_volume) AS net_volume,

    -- fees --
    sum(total_fees) AS total_fees,

    -- trade counts --
    sum(buy_count) AS buy_count,
    sum(sell_count) AS sell_count,
    sum(transactions) AS transactions,

    -- unique counts --
    uniqMerge(uniq_user) AS uniq_user

FROM state_ohlcv_fills AS t
GROUP BY
    interval_min,
    coin,
    timestamp;

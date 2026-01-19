-- OHLCV view for liquidation fills --
-- Provides a convenient interface for querying liquidation OHLCV data with merged aggregates
CREATE VIEW IF NOT EXISTS ohlcv_liquidation AS
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

    -- mark price OHLC --
    argMinMerge(mark_px_open) AS mark_px_open,
    quantileDeterministicMerge(0.95)(mark_px_quantile) AS mark_px_high,
    quantileDeterministicMerge(0.05)(mark_px_quantile) AS mark_px_low,
    argMaxMerge(mark_px_close) AS mark_px_close,

    -- volume --
    sum(buy_volume) AS buy_volume,
    sum(sell_volume) AS sell_volume,
    sum(gross_volume) AS gross_volume,
    sum(net_volume) AS net_volume,

    -- fees --
    sum(total_fees) AS total_fees,

    -- trade counts --
    sum(buy_count) AS buy_count,
    sum(sell_count) AS sell_count,
    sum(transactions) AS transactions,

    -- unique counts --
    uniqMerge(uniq_user) AS uniq_user,
    uniqMerge(uniq_liquidated_user) AS uniq_liquidated_user

FROM state_ohlcv_liquidation
GROUP BY
    interval_min,
    coin,
    timestamp;

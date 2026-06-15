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

    -- DEX/coin identity --
    dex,
    coin,

    -- OHLC --
    argMinMerge(open) AS open,
    quantileDeterministicMerge(0.95)(quantile) AS high,
    quantileDeterministicMerge(0.05)(quantile) AS low,
    argMaxMerge(close) AS close,

    -- volume by side (each side equals true total under double-emission) --
    sum(t.side_buy_volume) AS side_buy_volume,
    sum(t.side_ask_volume) AS side_ask_volume,

    -- aggressor (taker) directional volume --
    sum(t.taker_buy_volume) AS taker_buy_volume,
    sum(t.taker_sell_volume) AS taker_sell_volume,

    -- volume by perp direction --
    sum(open_long_volume) AS open_long_volume,
    sum(close_long_volume) AS close_long_volume,
    sum(open_short_volume) AS open_short_volume,
    sum(close_short_volume) AS close_short_volume,

    -- derived from aggressor directional volume --
    sum(t.taker_buy_volume) + sum(t.taker_sell_volume) AS gross_volume,
    sum(t.taker_buy_volume) - sum(t.taker_sell_volume) AS net_volume,

    -- fees --
    sum(total_fees) AS total_fees,

    -- true match count --
    sum(transactions) AS transactions

FROM state_ohlcv_fills AS t
GROUP BY
    interval_min,
    dex,
    coin,
    timestamp;

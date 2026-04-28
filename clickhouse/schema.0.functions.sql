CREATE FUNCTION IF NOT EXISTS dex_from_coin AS coin -> multiIf(
    position(coin, ':') > 0, splitByChar(':', coin)[1],
    startsWith(coin, '@'), 'spot',
    'perps'
);

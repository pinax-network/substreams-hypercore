-- Derive the ClickHouse dex namespace from the raw Hypercore coin symbol.
-- Custom dexes use `dex:COIN`, outcomes use `#...`, spot assets use `@...`,
-- and plain symbols remain perp markets.
CREATE OR REPLACE FUNCTION dex_from_coin AS coin -> multiIf(
    position(coin, ':') > 0, splitByChar(':', coin)[1],
    startsWith(coin, '#'), 'outcome',
    startsWith(coin, '@'), 'spot',
    'perps'
);

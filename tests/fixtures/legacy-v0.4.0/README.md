# Published Hypercore fill package corpus

The oracle is the unmodified
[hypercore-clickhouse-v0.4.0 release asset](https://github.com/pinax-network/substreams-hypercore/releases/download/v0.4.0/hypercore-clickhouse-v0.4.0.spkg).
Its 2,107,924 bytes have SHA-256
`0754d1ed93a49f8252864e6c8428ca584cfc61d9f9e50555a09636fa08a700d3`.
The `db_out` module hash is `54e96ad423d10f94cfc9d9be1cf1afa9717212ee`;
its 340,409-byte binary hash is
`d73fcc101bf792d6635563adc9bb95259f5c1ff2a193fa94443594032f0b5744`.
`extract_oracle.py` verifies package, declaration, entrypoint and binary identity
before extracting. It never downloads, rebuilds or overwrites differing fixtures.

The bounded test-only Wasmi host calls `db_out(Clock, Block)` in a fresh instance:
64 MiB memory, one billion fuel units, 4 MiB per input/output, one memory and
instance. Only the explicit Substreams output/panic/log/skip imports exist. No
stores, WASI, network or filesystem are available. Unexpected host/trap/fuel
failures fail the test. The interpreter is absent from normal dependencies.

`corpus.json` contains 25 synthetic blocks with SHA-256, the encoded clock, exact
historical DatabaseChanges output and retained row fields in emission order.
Cases cover regular, liquidation and outcome-first selection, all direction/side
values plus unknowns, malformed outcome identifiers, missing values/times,
nanosecond and invalid fill timestamps, large IDs, decimal precision, zero,
negative/negative-zero, scientific notation, invalid numbers, NaN and infinity.
All retained `fills` and `fills_liquidation` fields and row order match after the
native bounded fill-only decoder and row formatter. Hidden
database primary keys and field map order are not WebSocket contract checks;
the current-wrapper test separately compares database keys and ordinals.

The legacy formatter's floating-point conversion and invalid-number defaults
are intentionally preserved. Exact native observations remain separate. Outcome
rows are not relabeled as ordinary fills or liquidations. No live provider,
continuity, transport or schema-completeness qualification follows from this
corpus; upstream schema issue #49 remains separate.

```sh
python3 tests/fixtures/legacy-v0.4.0/extract_oracle.py /path/to/hypercore-clickhouse-v0.4.0.spkg
cargo test --locked published_v040_fill_corpus
```

Set `UPDATE_HYPERCORE_LEGACY_CORPUS=1` only for intentional corpus maintenance,
then review the resulting bytes and rerun without regeneration.

# Action Ledger — explorer lean storage

Goal: cut explorer MySQL storage cost (11 hcloud volumes, 8,460 GiB provisioned) without changing what explorer.thxnet.org shows or what lml tx-counter counts.

## Scope (aligned with Noel 2026-10-03, "ok go")

- Done now: fork `polkascan/harvester` -> `thxnet/blockchain-explorer-harvester` and `polkascan/explorer-api` -> `thxnet/blockchain-explorer-api`; read code; measure lean storage on `.9` by re-harvesting testnet ECQ from its public archive RPC.
- Must not: mutate hetprod (k8s, the 11 explorer MySQL DBs, PVCs). Prod MySQL is read-only.
- Must not change: lml tx-counter results; `explorer_block.number`; `explorer_event` rows for `Nfts.Issued`, `Balances.Transfer`, `*.Transferred`, including `attributes` and `block_datetime`.
- Later (needs Noel alignment, PRD): new smaller volume + lean DB + cutover; old PVC kept until Noel says delete.

## Facts

- Fork HEADs equal deployed code: harvester `1d01f44` (image `230825-c6fe5d3` = meta polkascan/explorer `c6fe5d3`), explorer-api `50bf56b`. Api image `240129-ca4e443` source commit unknown.
- Pipeline: `node_*` raw SCALE -> `codec_*` decoded JSON (ScaleDecode reads node_* per block) -> stored procedure `etl_range` in harvester DB and in each `INSTALLED_ETL_DATABASES` (explorer_api) -> `explorer_*`.
- Events stored 4 times: `node_block_storage` (System.Events raw), `codec_block_storage` (decoded array), `codec_block_event` (per event), `explorer_event`.
- explorer-api at serve time reads `explorer_*` plus harvester `codec_event_index_account` and `runtime_*` only. `node_*`, `codec_block_extrinsic/event/storage/header_digest_log` are ETL intermediates only (ETL reads the 1000-block window being processed; harvester progress uses MAX(block_number)).
- Biggest payloads: `ParachainSystem.set_validation_data` (~8 KB decoded per copy, every leafchain block), `ParaInherent.enter` (~10 KB, every rootchain block). ~10% of blocks carry a user tx.
- Projected full (2026-10-01 estimate): testnet ECQ ~34 days, mainnet THX ~51 days.

## Log

- 2026-10-03: forks created; branch `thxnet/lean-storage`; code read (above).
- 2026-10-03: `PruneIntermediate` job added (off by default, env `PRUNE_INTERMEDIATE_ENABLED/PRUNE_KEEP_BLOCKS/PRUNE_BATCH_BLOCKS`). Commit 03685be.
- 2026-10-03: stock `docker build` of harvester fails today: unpinned `substrate-interface` deps resolve `py-sr25519-bindings 0.2.4` (sdist, needs Rust). Lean image = `FROM ghcr.io/thxnet/blockchain-explorer-harvester:230825-c6fe5d3` + `COPY app` (`rbv/Dockerfile.lean`), same libs as prod.
- 2026-10-03: .9 experiment running: `rbv/up.sh base|lean`, `rbv/measure.sh`, `rbv/compare.sh`. Testnet ECQ blocks 2,300,000..2,304,999 over public RPC (~3 s/block, RTT-bound). Docker network `xlean-net` on subnet 10.241.77.0/24 (default pools exhausted on .9). Docker Hub pulls must run on .9 via ssh (Mac keychain locked).
- 2026-10-03: explorer-ui extrinsic page shows `callArguments` from explorer-api only (no RPC fallback) -> stripping inherent args blanks that page for inherents. Needs Noel decision.
- 2026-10-03: rootchain explorer layer per block: `ParaInherent.enter` ~9.6 KB + ~5.5 `ParaInclusion.Candidate*` events x ~1.36 KB.

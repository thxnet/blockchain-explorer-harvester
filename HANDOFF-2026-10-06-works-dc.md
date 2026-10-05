# HANDOFF 2026-10-06 — works-dc（explorer MySQL 瘦身 / harvester fork）

## a. Identity

| 項目 | 值 |
|---|---|
| Session name | `works-dc`（ListAgents 顯示 `works-dc [4c3815]`） |
| sessionId | `3ca8d72d-7a8c-4757-9187-e0becbc031b6` |
| 啟動 cwd | `/Users/noelbao/Works` |
| 主要工作 repo | `/Users/noelbao/Works/thxnet-explorer-stack/blockchain-explorer-harvester`（branch `thxnet/lean-storage`） |
| tmux pane | `thx:@107.%283`（`TMUX_PANE=%283`） |
| Transcript | `/Users/noelbao/.claude-thx/projects/-Users-noelbao-Works/3ca8d72d-7a8c-4757-9187-e0becbc031b6.jsonl` |
| Scratchpad | `/private/tmp/claude-501/-Users-noelbao-Works/3ca8d72d-7a8c-4757-9187-e0becbc031b6/scratchpad` |
| 寫入時間 | 2026-10-05 20:42 UTC（2026-10-06 04:42 CST） |
| 回覆語言 | 繁體中文（台灣）；Noel 不讀日文 |

## b. Mission（Noel 原話與範圍）

1. 2026-10-01 原始要求（原文）：
   > if you go to thxnet org (github) , you can see public repos related to explorer and panel , check them
   - 已完成盤點：`thxnet/blockchain-explorer-ui`（fork of polkascan/explorer-ui）、`thxnet/blockchain-panel`（fork of polkadot-js/apps）、`thxnet/thxnet-explorer`（已封存，fork of polkascan/explorer）。
2. 2026-10-01 追加（原文）：
   > but before that , 我在思索的是, 要不要 noelcc: CUMI for panel repo , and , explorer repos (畢竟 polkascan explorer 好像有一個 meta repo https://github.com/polkascan/explorer) , 感覺可以 fork 到 thxnet org , 然後我們可以進行改造，因為 explorer mysql db 造成我們很多大量的... 成本，快瘋了哈哈哈，感覺可以做 old blocks' data optimization 之類的
   - NoelCC `CUMI` 定義在 `/Users/noelbao/NoelCC.md`（Check upstream and integrate it completely into our fork…）。
   - 我的回覆結論：panel 的 CUMI 可做但不省錢、排後面；explorer 的上游已停更，CUMI 無東西可整合；真正要做的是接手 harvester / explorer-api 原始碼改造以降低 MySQL 成本。
3. 2026-10-03 Noel：「ok go」= 核准我提出的第 2 點（只限非 production）：
   - fork `polkascan/harvester` 與 `polkascan/explorer-api` 到 thxnet；讀程式碼；讀 lml tx-counter SQL；在 `.9`（boai-10-66-0-9）用修改過的 harvester 從 testnet ECQ 公開 archive RPC 重新收割一段 block，實測精簡後每 block 大小。
   - 我採用的預設（Noel 未反對）：panel CUMI 排在 explorer 之後；lml tx-counter 計數結果絕對不能變。
4. 2026-10-06 Noel：「what are your 建議」— 我已回覆一份依優先順序的建議（見 j、k），**Noel 尚未回答**。

Definition of done（目前這一階段）：
- 非 production 部分：fork + 改造 + `.9` 實驗 + RBV 證據 → 已完成。
- 下一階段（需 Noel 對齊）：擴容快滿的 volume、部署斷線修正、補 rootchain 缺洞、逐鏈搬遷到精簡 DB（真正省錢）。

## c. Constraints from Noel

Must do：
- 每一步 RBV（真實執行、觀察輸出/狀態）；規劃 observability；不要 magic numbers（設定集中在 env / constants）；不寫測試、不寫註解；活用 git commit；維護 Action Ledger。
- 任何 production mutation 前先盤點並與 Noel 對齊（NoelCC DYUWIM）。

Must avoid：
- 任何 production mutation 未經 Noel 逐項核准。production = hetprod k8s、11 個 explorer MySQL、PVC、mainnet/testnet chain 節點與狀態。
- `git reset --hard`、`git rm`、`git clean`、force removal、broad deletion。
- 在 `.9` 上做 broad prune / 刪除不屬於本 session 的資源。
- 刪除任何 PVC / volume（含非 production）需要 Noel 逐次明確同意（memory `feedback-never-delete-pvc-without-confirm.md`）。
- spawn subagent 時不得使用 terra / sonnet / haiku。

Must not mutate：
- hetprod 上所有 explorer MySQL 資料（唯讀查詢可）；hetprod k8s 物件（唯讀可）；lml tx-counter 依賴的 `explorer_block.number` 與 `explorer_event` 的 `Nfts.Issued`、`Balances.Transfer`、`*.Transferred` 列（含 `attributes`、`block_datetime`）；AVATECT 的 explorer MySQL（保留給 tx-counter poller）。

Production approvals：
- **已給：無**（沒有任何 prod mutation 核准）。唯讀查詢屬常規允許（memory `feedback-hetprod-k8s-mutation-gate.md`：hetprod 任何寫入需逐項核准，唯讀自由）。
- **未給**：PVC 擴容、harvester image 更新、prod DB 修補、搬遷、刪除舊 PVC — 全部未核准。

本 session 對外（非 production）已做的 mutation：
- 在 GitHub `thxnet` org 建立兩個 public fork（見 e）。
- push branch `thxnet/lean-storage` 到 `thxnet/blockchain-explorer-harvester`。
- 在 `.9` 建立 `xlean-*` 容器、volume、network（見 f）。

## d. Current state

### 已完成（verified）

1. 盤點 thxnet 三個 explorer/panel repo 與 hetprod 部署（verified，GitHub API + `kubectl --context hetprod get` 唯讀）：
   - explorer 鏈清單在 runtime 由 ConfigMap `mainnet/explorer-ui-config-v2`、`testnet/rootchain-explorer-ui-config-v2`（key `network-endpoints.json`）掛到 `/usr/share/nginx/html/assets/config.json`；live 已無 AVATECT；repo `ui-config.json` 仍有 AVATECT（不影響 live）。
   - panel 鏈清單寫死在 `packages/apps-config/src/endpoints/thxMainnet.ts` / `thxTestnet.ts`；hetprod 跑 `ghcr.io/thxnet/blockchain-panel:build-2026.09.29-904d40c`。
   - hetprod explorer/panel manifest **不在** `thxnet/deployment` git（該 repo 只有 `lke-thxnet-prod/`）；本機 `/Users/noelbao/Works/deployment/hetzner-thxnet-prod/` 不是 git checkout 且過時（仍列 AVATECT、舊 panel image），重新 apply 會讓 AVATECT 回來。
2. fork 建立（verified：`gh repo view thxnet/blockchain-explorer-harvester --json parent` → parent `polkascan/harvester`）：
   - `thxnet/blockchain-explorer-harvester` ← `polkascan/harvester`，fork HEAD `1d01f44` = hetprod harvester image `230825-c6fe5d3`（= meta repo `polkascan/explorer` commit `c6fe5d3` 的 submodule）。
   - `thxnet/blockchain-explorer-api` ← `polkascan/explorer-api`，HEAD `50bf56b`（未修改）。hetprod api image `240129-ca4e443` 的原始碼 commit 在任何 repo 都找不到。
3. 程式碼結論（verified by reading code）：
   - 管線：`node_*`（原始 SCALE）→ `codec_*`（解碼 JSON，ScaleDecode 逐 block 讀 node_*）→ MySQL stored procedure `etl_range`（harvester DB 與每個 `INSTALLED_ETL_DATABASES` explorer_api DB）→ `explorer_*`。
   - events 存四份：`node_block_storage`、`codec_block_storage`、`codec_block_event`、`explorer_event`。
   - explorer-api 服務時只讀 `explorer_*` + harvester 的 `codec_event_index_account`、`runtime_*`；`node_*`、`codec_block_extrinsic/event/storage/header_digest_log` 只是 ETL 中間料（ETL 只讀正在處理的 1000-block 視窗）。
   - lml 讀 explorer MySQL 的位置：`/Users/noelbao/Works/lml/helpers/common/listen_to_total_counts.ts`（COUNT on `explorer_event`、`explorer_block.number`）與 `/Users/noelbao/Works/lml/helpers/common/nft_get_blockchain_things.ts`（`explorer_event` 的 `Nfts.Issued` + `JSON_EXTRACT(attributes, ...)`）。
   - explorer-ui 的 extrinsic 詳細頁只用 explorer-api 回傳的 `callArguments`，沒有 RPC 備援。
4. 新功能 `PruneIntermediate`（commit `03685be`，verified on `.9`）：ETL 後刪 harvester 中間列，上界 = min(`PROCESS_ETL`, `EVENT_INDEX_ACCOUNTID_MAX_BLOCKNUMBER`, 每個 explorer_api DB 的 `MAX(explorer_block.number)`) − `PRUNE_KEEP_BLOCKS`；有 retry 列的 block 前停止；預設關閉（`PRUNE_INTERMEDIATE_ENABLED=1` 才開）；metrics `prune_rows_deleted{table}`、`prune_max_blocknumber`。
   - RBV：testnet ECQ #2,300,000..#2,304,999，base（prod 原版 image）vs lean，`rbv/compare.sh` → explorer_block/extrinsic/event/log + codec_event_index_account 逐列雜湊 SAME（排除 #2300000 與 #2303650，原因見 i）。prune 三輪各 1,000 blocks，1.1–2.0 秒。證據檔：`rbv/results/compare-main-20261004.txt`、`rbv/results/measure-{base,lean}-20261004.txt`。
   - 每 block：base 約 67 KB（中間料約 45 KB、explorer_api 約 20 KB）。
5. upstream bug 修正（commit `cc14ee4`，verified by fault-injection A/B）：RPC 失敗時主迴圈重連後 commit，留下只有 header 的半個 block，之後從 `MAX(header)+1` 繼續 → explorer 永久缺該 block。修法：except 分支先 `self.session.rollback()`。
   - RBV：proxy 每第 37 個 RPC 回 `{"code":-32050,"message":"Upstream response unavailable"}`，#2,310,000..#2,310,299，311 次注入：stock 丟 99 個 block（93 個半寫入 header）；修正版 0 個（只缺起點 #2310000）。共同 200 block 逐列 SAME。證據：`rbv/results/measure-{base,lean}-fault-20261004.txt`、`rbv/results/fault-injections-20261004.txt`。
6. prod 唯讀發現（verified，`kubectl exec ... mysql -e SELECT`）：
   - hetprod mainnet rootchain explorer 缺 7 個 block：17395748、17408797、17408873、17410778、17418733、17424657、17425409（2026-09-30..10-02），特徵 = `node_block_header` 存在、`count_extrinsics=2`、`node_block_extrinsic` 0 筆、無 `codec_block_timestamp`。2026-10-05 20:36 UTC 複查仍 7 個，未增加。其他 9 條鏈 0 缺洞。
   - 觸發來源：`ws://rootchain-archive-001-rpc-firewall.mainnet.svc.cluster.local:80/` 回 -32050（上一個容器 5 小時 95 次）；harvester pod `rootchain-explorer-harvester-v2-*` restartCount 17；目前容器（10-02 09:13 UTC 起）-32050 次數 0。
   - prune-only 預估（information_schema）：10 條鏈 5,434.6 GiB → 保留 1,474.1 GiB（27%）。各鏈表見 `AI_MEMORIES/ACTION_LEDGER.md` 與下方 i。
7. Action Ledger、AGENTS.md、CLAUDE.md、README 指標已建立並 push。

### 進行中
- 無。停在「已回覆建議，等待 Noel 回答」的安全點。沒有正在跑的變更。

### 未開始（需 Noel 決定或待做）
- 擴容 3 顆 PVC、部署修正 image、補 7 個缺洞、搬遷、拿掉 inherent 參數、panel CUMI、fork CI 改 GHCR、單一 block 修補工具、匯出 hetprod manifest 到 git、explorer-ui `ui-config.json` 清理 PR。

## e. Repo state

| Repo（絕對路徑） | Remote | Branch | HEAD | 狀態 |
|---|---|---|---|---|
| `/Users/noelbao/Works/thxnet-explorer-stack/blockchain-explorer-harvester` | `git@github.com:thxnet/blockchain-explorer-harvester.git` | `thxnet/lean-storage`（追蹤 origin，已同步） | `7cf764b57dbbda46889c9509a0bae44a6ddea4a1`（加上本 handoff commit） | clean；無 stash；無額外 worktree |
| `/Users/noelbao/Works/thxnet-explorer-stack/blockchain-explorer-api` | `git@github.com:thxnet/blockchain-explorer-api.git` | `main` | `50bf56bfa4e69355981e6dd16e90e03576b2832f` | 未修改 |

`thxnet/lean-storage` 上的 commits（舊→新）：`dab3b48` ledger → `03685be` prune → `efd82f7` ledger/compare → `cc14ee4` rollback fix → `dcc353a` fault proxy/RUN_TAG/integrity → `7cf764b` results。

- 無 PR、無 issue。建 PR 網址：`https://github.com/thxnet/blockchain-explorer-harvester/pull/new/thxnet/lean-storage`（**PR 目標要選 `thxnet/blockchain-explorer-harvester` 的 `main`，不是 polkascan 上游**）。
- 非 git 工作區檔案：`/Users/noelbao/Works/thxnet-explorer-stack/AGENTS.md`、`/Users/noelbao/Works/thxnet-explorer-stack/CLAUDE.md`（指標）。
- Scratchpad 唯讀 clone（可丟棄）：`.../scratchpad/blockchain-explorer-ui`（已 init `polkadapt` submodule）、`.../scratchpad/blockchain-panel`（blob:none）、`.../scratchpad/thxnet-explorer`。
- Memory 已更新：`/Users/noelbao/.claude-thx/projects/-Users-noelbao-Works/memory/thxnet-explorer-panel-repos.md` 與 `MEMORY.md` 對應那一行。

## f. Runtime state

背景 shell task：**無在跑**（`b0gf8cgby`、`bpuo4n9qj`、`bsgmi6bs1` 已完成；`bfv4nao8a` 已停止）。monitor / cron / loop：無。

SSH tunnel：本 session **沒有建立任何 tunnel**。Mac 上現有兩條不屬於本 session（PID 64439 `-L 127.0.0.1:8001`、PID 26346 `macstudio-wg`），不要動。

`.9`（`docker --context boai-10-66-0-9`）上本 session 建立的資源（全部 `xlean-*`）：

| 名稱 | 類型 / image | 狀態 | 用途 | 建議 |
|---|---|---|---|---|
| `xlean-net` | network，subnet `10.241.77.0/24` | — | 實驗網路（.9 預設 IP pool 已用盡才指定 subnet） | 保留 |
| `xlean-redis` | `redis:7-alpine` | Up | explorer-api broadcast | 保留 |
| `xlean-mysql-base` | `mysql:8.0.33`，volume `xlean-mysql-base-data` | Up | base 結果 DB（`testnet_leafchain_ecq_*`、`testnet_leafchain_ecq_fault_*`） | **保留**（比對基準） |
| `xlean-mysql-lean` | `mysql:8.0.33`，volume `xlean-mysql-lean-data` | Up | lean 結果 DB；含半寫入 block #2303650，是修補工具的演練目標 | **保留** |
| `xlean-api-base` / `xlean-api-lean` / `xlean-api-base-fault` / `xlean-api-lean-fault` | `ghcr.io/thxnet/blockchain-explorer-api:240129-ca4e443` | Up（無 published port） | 建 explorer_api schema；可查 GraphQL | 可停 |
| `xlean-harvester-base` / `xlean-harvester-base-fault` | `ghcr.io/thxnet/blockchain-explorer-harvester:230825-c6fe5d3` | Exited | base 收割 | 保留（停止中） |
| `xlean-harvester-lean` | image id `c7c1baef7134`（prune only，無 rollback 修正） | Exited | lean 收割 | 保留 |
| `xlean-harvester-lean-fault` | `xlean/harvester:lean`（`25e3f4f348ab`，含修正） | Exited | 故障注入 | 保留 |
| `xlean-fault-proxy` | `xlean/fault-proxy:1` | Exited | -32050 注入 | 保留 |
| images | `xlean/harvester:lean`、`xlean/fault-proxy:1` | — | — | 保留 |

指令：
- 查看：`docker --context boai-10-66-0-9 ps -a --filter name=xlean`
- 停 api（省資源，安全）：`docker --context boai-10-66-0-9 stop xlean-api-base xlean-api-lean xlean-api-base-fault xlean-api-lean-fault`
- 全部移除容器（只在 Noel 同意後；volume 刪除需 Noel 逐次同意）：`docker --context boai-10-66-0-9 rm -f $(docker --context boai-10-66-0-9 ps -aq --filter name=xlean)`；volume：`docker --context boai-10-66-0-9 volume rm xlean-mysql-base-data xlean-mysql-lean-data`（**需 Noel 同意**）。
- `.9` 磁碟：根分割區 93G，實驗前剩約 23G。

## g. Environment and access

- hetprod k8s：`kubectl --context hetprod`（kubeconfig 預設位置；context 名稱 `hetprod`，cluster `hetzner-prod-master2`）。explorer MySQL pod 名稱樣式 `<chain>-explorer-mysql-*`，namespace `mainnet` / `testnet`；root 密碼在 pod 環境變數 `MYSQL_ROOT_PASSWORD`（來自 Secret `<chain>-explorer-mysql`），查詢方式：`kubectl --context hetprod -n mainnet exec <pod> -- sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -N -e "SELECT ..."'`（只做唯讀 SELECT）。
- DB 名稱樣式：`<net>_<rootchain|leafchain_xxx>_harvester`、`<net>_<...>_explorer_api`。
- hetprod harvester RPC：mainnet rootchain `ws://rootchain-archive-001-rpc-firewall.mainnet.svc.cluster.local:80/`；testnet ECQ `ws://leafchain-ecq-rpc-service-internal-loadbalancer.testnet.svc.cluster.local:80/`。
- 公開 RPC（`.9` 實驗用）：`wss://node.ecq.testnet.thxnet.org/archive-001/ws`（從台灣約 0.3 s RTT，約 3 秒/ block）。
- `.9`：`ssh noel@10.66.0.9`；docker context `boai-10-66-0-9`。**Docker Hub pull 必須在 .9 上直接跑**：`ssh noel@10.66.0.9 'docker pull <image>'`（Mac 端 credential helper 因 keychain 鎖住會失敗）。GHCR public image 可直接 pull。
- 實驗設定：`/Users/noelbao/Works/thxnet-explorer-stack/blockchain-explorer-harvester/rbv/xlean.env`（含 `.9` 本機實驗用 MySQL 密碼，僅限 .9 實驗容器）。
- GitHub：`gh` 登入帳號 `kumanoko24`（thxnet org admin，scopes 含 `admin:org`、`repo`、`write:packages`）。
- 本機舊 deployment 副本：`/Users/noelbao/Works/deployment/hetzner-thxnet-prod/`（非 git、過時，不可直接 apply）。
- Hetzner Volume 價格：€0.044–0.057 / GB / 月（2026-04 漲價，來源不一致）。

## h. Decisions, rejected approaches, dead ends

- 不對 explorer 做 CUMI：polkascan 上游停更（harvester 最後 push 2023-04、explorer-api 2023-06、polkadapt 2023-11、meta repo 2024-01、explorer-ui 2024-03）。
- 不 fork `polkascan/explorer` meta repo：`thxnet/thxnet-explorer` 已是它的 fork（同 org 不能再 fork 同一網路）；而且 meta repo 只有 docker-compose + submodule，真正要改的是 harvester。
- 不用原 Dockerfile build：`docker build` 今天失敗，錯誤 `ERROR: No matching distribution found for puccinialin`（`substrate-interface` 依賴未釘死 → 解析到 `py-sr25519-bindings 0.2.4` sdist，需要 Rust）。改用 `rbv/Dockerfile.lean`：`FROM ghcr.io/thxnet/blockchain-explorer-harvester:230825-c6fe5d3` + `COPY app /usr/src/app`（與 prod 同樣的函式庫）。
- `.9` 上 legacy builder 不支援 `--progress`；Mac 沒有 `timeout` 指令；BSD `seq` 大數字會輸出科學記號（用 `seq -f '%.0f'`）；bash 3.2 + `set -u` 空陣列要用 `${ARR[@]+"${ARR[@]}"}`。
- 實驗視窗從 20,000 縮到 5,000 block：RTT 造成約 3 秒/ block。
- fault proxy 必須 `ping_interval=None`（兩端），否則 proxy 自己的 keepalive 斷線會變成不受控的故障。
- 不建議在 prod 舊 DB 上直接跑 prune 騰空間：等於在 prod 刪幾百 GB（不可逆），且 row-based binlog（prod `--binlog-expire-logs-seconds=259200`）會先把磁碟塞滿。搬遷採「新 DB + 複製 + 切換，舊 PVC 保留」。
- 拿掉 inherent 參數（`ParachainSystem.set_validation_data`、`ParaInherent.enter`、`ParaInclusion.CandidateBacked/CandidateIncluded`）延後：UI 該頁會空白，屬產品決定。
- panel CUMI 延後：panel 正常；落後上游 1,847 commits、領先 13；若做，用「把 13 個 THXNET commit 重放到上游最新版」而非硬 merge。

## i. Known problems

1. **快滿的 prod volume**（2026-10-05 20:36 UTC 實測，成長以 10-01→10-05 差值算）：
   - testnet ECQ：157G 用 137G、剩 21G、約 1 GB/天 → 約 2026-10-26 滿。
   - mainnet ECQ：157G 用 127G、剩 31G、約 1.2 GB/天 → 約 2026-10-30 滿。
   - mainnet THX：472G 用 444G、剩 28G、約 1 GB/天 → 約 2026-11-02 滿。
   - testnet SAND：492G 用 410G、剩 82G → 約 12 月底。
   - StorageClass `hcloud-volumes` `allowVolumeExpansion=true`（可線上擴容）。
2. **prod mainnet rootchain 7 個缺洞**（見 d.6），根因 = upstream 半個 block bug（confidence 高：特徵一致 + .9 重現）。修正已在 `cc14ee4`，未部署。
3. **upstream 起點行為**：harvester 以 `BLOCK_START=S` 起跑時，block S 的 extrinsic 解碼失敗（`'NoneType' object has no attribute 'portable_registry'`，之後 cron retry 失敗 `No runtime information for block`），所以 explorer 永遠缺 S。**搬遷設計必須讓新 harvester 的起點落在已複製過的 block 上**（ETL 是 upsert，已存在的 explorer 列不受影響）。
4. fork 的 `.github/workflows/docker-image.yml` 仍是 upstream 設定（push `main` 時推 Docker Hub `polkascan/harvester:latest`，需要不存在的 secrets）。目前只 push 到 `thxnet/lean-storage`，所以沒觸發。
5. explorer-ui repo CI：2026-03-29 的 run 跑滿 6 小時被取消；Dockerfile 用滾動的 `node:lts`。
6. `rbv/measure.sh` 在某些 pipe 組合下回傳 exit 1（`sed | rg -v` 無輸出）；直接執行 `./measure.sh <variant>` 正常。

prune-only 各鏈預估（GiB，total → keep）：mainnet rootchain 1232.7→301.7、mainnet THX 400.5→121.5、mainnet LMT 367.7→110.5、mainnet ECQ 112→35.5、testnet rootchain 1723.6→429.9、testnet THX 383.8→113.4、testnet LMT 384.1→113.3、testnet SAND 392.3→115.9、testnet IZUTSUYA 315.7→94.7、testnet ECQ 122.2→37.7。

## j. Open questions for Noel（含 Noel 不在時的預設）

1. 擴容 testnet ECQ、mainnet ECQ、mainnet THX 三顆 PVC，各加 80 GiB（提議值，約多撐 2.5 個月，合計每月多約 €11–14）？
   - 預設：**不動 prod**。每天唯讀量一次 `df`；準備好確切的 `kubectl patch pvc` 指令等 Noel 核准。
2. 部署 rollback 修正到 10 個 harvester（prune 關閉）並補 7 個缺洞？
   - 預設：只做非 prod 前置（fork CI 改推 GHCR、修補工具在 .9 演練），prod 不動。
3. 四項非 prod 工作要不要現在做（fork CI→GHCR、單一 block 修補工具 + .9 演練、匯出 hetprod manifest 開 PR 到 `thxnet/deployment`、寫 testnet ECQ 搬遷計畫）？
   - 預設：**做**（屬非 production，CLAUDE.md 允許自律執行）。
4. 拿掉 inherent 參數：「頁面空白」或「改 explorer-ui 向 archive node 查詢」？
   - 預設：延後，等搬遷完成再問。
5. prod 用的 `PRUNE_KEEP_BLOCKS`（實驗 2000）、`PRUNE_BATCH_BLOCKS`（實驗 1000）、新 volume 餘裕倍數（提議 1.5）。
   - 預設：沿用實驗值寫進計畫，標記「待 Noel 確認」。
6. panel CUMI。預設：延後。

## k. Next steps（依序）

1. **（非 prod）fork CI 改推 GHCR**
   - 新增 `.github/workflows/ghcr.yml`：push 到 `thxnet/lean-storage` 時以 `rbv/Dockerfile.lean`（`BASE_IMAGE=ghcr.io/thxnet/blockchain-explorer-harvester:230825-c6fe5d3`）build，推 `ghcr.io/thxnet/blockchain-explorer-harvester:lean-<YYYY.MM.DD>-<sha>`，`permissions: packages: write`。把 `docker-image.yml` 的 `on:` 改成只有 `workflow_dispatch`（不要 `git rm`）。
   - RBV：`gh run list -R thxnet/blockchain-explorer-harvester --limit 3`；`gh api orgs/thxnet/packages/container/blockchain-explorer-harvester/versions --jq '.[0].metadata.container.tags'`；`ssh noel@10.66.0.9 docker pull ghcr.io/thxnet/blockchain-explorer-harvester:<tag>`，再 `docker --context boai-10-66-0-9 run --rm --entrypoint grep <image> -c 'Uncommitted work rolled back' /usr/src/app/harvester.py` 應為 1。
2. **（非 prod）單一 block 修補工具**
   - 在 `app/cli.py` 加 `repair-block --block N`：刪除 block N 在 `node_block_header`、`node_block_extrinsic`、`node_block_header_digest_log`、`node_block_runtime`、`node_block_storage`、`codec_block_extrinsic`、`codec_block_header_digest_log`、`codec_block_storage`、`codec_block_event`、`codec_block_timestamp`、`codec_event_index_account` 的列 → 用 `RetrieveBlocks.add_block(N)` → `RetrieveRuntimeState.storage_block_runtime_data` → ScaleDecode 的 `decode_extrinsic/decode_log_item/decode_storage_item` → 事件索引 → `CALL etl_range(N, N, 0)`（harvester DB 與每個 explorer_api DB；**update_status 必須是 0**，否則會把進度標記改回 N）。全程一個 transaction、失敗 rollback、log 每步列數。
   - .9 演練目標：`xlean-mysql-lean` 的 `testnet_leafchain_ecq_harvester`，block 2303650。
   - RBV：`cd /Users/noelbao/Works/thxnet-explorer-stack/blockchain-explorer-harvester/rbv && ./measure.sh lean` 的 integrity 區段 `missing_blocks` 只剩 2300000、`partial_blocks` = 0；`COMPARE_EXCLUDE_OVERRIDE=2300000 ./compare.sh` 全部 SAME。
3. **（非 prod）匯出 hetprod explorer/panel manifest 到 git**
   - `kubectl --context hetprod -n mainnet|testnet get deploy,svc,cm,pvc,ingress -o yaml`（只取 explorer/panel 物件；**不要匯出 Secret 內容**），去掉 `status`、`metadata.managedFields/uid/resourceVersion/creationTimestamp`，放到 `thxnet/deployment` 的 `hetzner-thxnet-prod/{mainnet,testnet}/explorer-v2|panel/`，開 PR。
   - RBV：`kubectl --context hetprod diff -f <dir>` 無差異（server-side dry run，唯讀）。
4. **（非 prod）testnet ECQ 搬遷計畫**（給 Noel 做 DYUWIM）：新 PVC（大小 = keep 37.7 GiB × 餘裕）、新 MySQL deployment、複製 `explorer_*` 全部 + harvester 小表（`node_block_header`、`node_block_runtime`、`codec_block_timestamp`、`codec_event_index_account`、`runtime_*`、`codec_metadata`、`node_metadata`、`node_runtime`、`harvester_status`）+ 最近 `PRUNE_KEEP_BLOCKS` 的中間表；新 harvester（修正 + prune 開）從已複製的 block 起跑（避開 i.3）；切換 = 把 service `leafchain-ecq-explorer-mysql` 指到新 MySQL（lml/api/polling 不用改設定）；回退 = service 指回舊 MySQL；舊 PVC 保留。驗證：`explorer_block` 缺洞數、lml 三條計數 SQL 新舊一致、explorer.testnet.thxnet.org 網頁操作。
5. **每日唯讀監看**：
   - `for spec in "testnet leafchain-ecq" "mainnet leafchain-ecq" "mainnet leafchain-thx"; do set -- ${=spec}; P=$(kubectl --context hetprod -n $1 get pods -o name | rg "^pod/$2-explorer-mysql"); kubectl --context hetprod -n $1 exec $P -- sh -c 'df -B1G /var/lib/mysql | tail -1'; done`（zsh；bash 用 `set -- $spec`）
   - rootchain 缺洞：`SELECT MAX(number)-MIN(number)+1-COUNT(*) FROM mainnet_rootchain_explorer_api.explorer_block`（目前 7）。

## l. Pointers

- Action Ledger：`/Users/noelbao/Works/thxnet-explorer-stack/blockchain-explorer-harvester/AI_MEMORIES/ACTION_LEDGER.md`
- RBV / 觀測腳本：`/Users/noelbao/Works/thxnet-explorer-stack/blockchain-explorer-harvester/rbv/`
  - `xlean.env`（全部實驗設定）、`up.sh base|lean`（支援 `RUN_TAG`、`RPC_URL_OVERRIDE`、`BLOCK_START_OVERRIDE`、`BLOCK_END_OVERRIDE`）、`measure.sh base|lean`（進度、各表大小、integrity：explorer 缺洞 + 半寫入 block）、`compare.sh`（explorer_* 逐列雜湊 + lml 計數 SQL；`COMPARE_EXCLUDE_OVERRIDE`）、`fault_proxy.py` + `Dockerfile.fault-proxy`、`Dockerfile.lean`、`results/`
- 程式改動：`app/jobs.py`（`PruneIntermediate`）、`app/harvester.py`（job 接線、metrics、rollback 修正）、`app/settings.py`（`PRUNE_*` env）
- Memory：`/Users/noelbao/.claude-thx/projects/-Users-noelbao-Works/memory/thxnet-explorer-panel-repos.md`；相關：`thxnet-11-missioning-chains.md`、`lml-tx-counter-pipeline-and-incident.md`、`feedback-never-delete-pvc-without-confirm.md`、`feedback-hetprod-k8s-mutation-gate.md`、`feedback-prod-db-read-only.md`
- AVATECT 下架 runbook（hetprod explorer/panel 物件名稱來源）：`/Users/noelbao/Works/deployment/AI_MEMORIES/avatect-mainnet-decommission-runbook-2026-09-30.md`
- NoelCC 定義：`/Users/noelbao/NoelCC.md`（CUMI、DYUWIM、MIC 等）
- 相關 session：`claude-thx-sessions-3f`（轉達本 handoff 要求）

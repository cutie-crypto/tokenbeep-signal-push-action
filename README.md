# tokenbeep-signal-push-action

把机器人写出的 `signals_feed.json`（schema=1）推送到 TokenBeep 的官方 GitHub Action。
Official GitHub Action that pushes a bot-generated `signals_feed.json` (schema=1) to TokenBeep.

**适用场景**：信号仓库私有 + 平台「GitHub Action 推送」订阅（没有 URL）。仓库转私有后，没订阅你的人拿不到信号文件；平台只在收到推送时同步，不再定时拉取。
**Use case**: a private signal repo plus a URL-less "GitHub Action push" subscription on TokenBeep. After the repo goes private, non-subscribers can no longer get your signal file, and the platform only syncs when the Action pushes.

## 你会做的事 / What you will do

1. **把信号仓库改成私有** — Make your signal repo private
2. **在 TokenBeep 建「GitHub Action 推送」订阅**（不填 URL）— Create a push-only subscription
3. **在仓库加 secret 与 workflow** — Add the secret and a workflow
4. **推一次，看到信号进来** — Push once and watch signals arrive

> 前置：你的 TokenBeep 账号能发布信号；feed 保持原格式（Feed v1 / `schema=1`，≤1 MiB）。
> Prerequisites: your account can publish signals; your bot keeps producing the same Feed v1 file (`schema=1`, ≤1 MiB).

### 1. 仓库改私有 / Make the repo private

GitHub → 仓库 **Settings → General → 页面底部 Danger Zone → Change repository visibility → Private**。

私有之后，`signals_feed.json` 只有仓库成员能看：没有在 TokenBeep 订阅你的用户再也拿不到你的信号（此前公开仓库等于把信号免费公开）——这正是本方案的目的。私有仓库的 Actions 照常运行（用量按 GitHub 计费规则计入你的账号）。

After this, only repo collaborators can read `signals_feed.json`; users who do not subscribe to you on TokenBeep can no longer get the data. Actions keeps working on private repos.

如果你原来用的是「公开 raw 地址 + URL 拉取」订阅：**先不要转私有**，按文末「从 URL 拉取迁移」的顺序操作（先暂停旧订阅、接好推送，再转私有）。
If you migrated from a public raw URL subscription, do **not** make the repo private first — follow "Migrating from a URL pull subscription" below (pause the old subscription, get push working, then go private).

### 2. 建「GitHub Action 推送」订阅 / Create the push subscription

1. 打开 TokenBeep Web 端「量化机器人」→ 新建（或给已有机器人重新接入）。
2. 「接入方式」选 **GitHub Action 推送**——不填、也不需要 URL。
3. 上传机器人**当前**产出的 `signals_feed.json`（≤1 MiB，合法 JSON），点「检查文件」。平台用它建立初始持仓快照；历史事件不回放，之后的新事件靠 Action 推送。
4. 通过后按向导完成创建（策略名称、来源策略映射等与 URL 订阅相同）。

1. Open TokenBeep Web → Quant bots → create a new bot (or reconnect an existing one).
2. Set delivery method to **GitHub Action push** — no URL is needed.
3. Upload your bot's **current** `signals_feed.json` (≤1 MiB, valid JSON) so the platform can bootstrap the position snapshot; past events are not replayed.
4. Finish the wizard as usual.

创建后平台不再定时拉取这条订阅（来源显示「GitHub Action 推送」）。重复推送同一份文件是安全的，服务端幂等。
After creation the platform stops polling this subscription; re-pushing the same file is safe (idempotent).

### 3. 加 secret 与 workflow / Add the secret and workflow

1. TokenBeep「外部接入」新建 API Key，权限选「发信号」（`write:signals`）。Key 只显示一次，立即保存。
2. 仓库 **Settings → Secrets and variables → Actions → New repository secret**，名字填 `TOKENBEEP_API_KEY`，值粘贴上一步的 Key。
3. 把下面的示例保存为 `.github/workflows/tokenbeep-push.yml`，替换机器人生成命令后提交。

1. In TokenBeep, create an API key with the "publish signals" (`write:signals`) scope under "External access". The key is shown once.
2. In your repo, add a secret named `TOKENBEEP_API_KEY` under Settings → Secrets and variables → Actions.
3. Save the workflow below as `.github/workflows/tokenbeep-push.yml`, replace the bot step, and commit.

```yaml
name: Push signals to TokenBeep

on:
  schedule:
    - cron: "*/15 * * * *"   # 换成你的机器人节奏 / adjust to your bot cadence
  workflow_dispatch: {}

permissions:
  contents: read

jobs:
  push-signals:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # 换成你机器人的命令；这一步要写出 signals_feed.json
      # replace with your bot command; it must write signals_feed.json
      - name: 生成信号文件 / Generate signals
        run: python your_bot.py

      - name: 推送到 TokenBeep / Push to TokenBeep
        uses: cutie-crypto/tokenbeep-signal-push-action@v1
        with:
          api_key: ${{ secrets.TOKENBEEP_API_KEY }}
          # 多条进行中订阅时必填：换成你的订阅 ID（示例数字仅占位）/
          # required when several subscriptions are active; replace with your ID
          # subscription_id: "123456789012345678"
```

- `file:` 默认是工作目录里的 `signals_feed.json`，路径不同就加 `file: 你的路径`。
  `file:` defaults to `signals_feed.json` in the working directory; set it when your path differs.
- workflow 需要 runner 有 `bash` 与 `jq`（GitHub 托管 Ubuntu / macOS runner 自带）。
  The runner needs `bash` and `jq` (GitHub-hosted Ubuntu/macOS runners have both).

### 4. 推一次，看到信号进来 / Push once and verify

在仓库 **Actions** 页选你的 workflow，手动 **Run workflow** 一次。成功时日志末尾是 `accepted=… skipped=… rejected=… last_event_id=…`；平台订阅详情的「最近成功 / 同步水位」随之后移，新事件生成的信号出现在你的主页。

Trigger the workflow once from the Actions tab. On success the log ends with `accepted=... skipped=...`; the subscription's last-success time and watermark advance, and new signals show up on your profile.

- 同一文件重推不会重复发信号（都计入 `skipped`）。Re-pushing the same file only counts `skipped`.
- 服务端返回 `err_code=2057`（订阅正被拉取或另一次推送占用）时，Action 自动退避重试 3 次（5s / 10s / 20s）。When the server returns `err_code=2057` (subscription busy), the Action retries automatically 3 times with 5s / 10s / 20s backoff.

## 输入 / Inputs

| 输入 Input | 必填 Required | 默认 Default | 说明 Description |
|---|---|---|---|
| `api_key` | 是 yes | - | 持「发信号」（`write:signals`）权限的 API Key，必须来自 secrets / key with the `write:signals` scope, must come from secrets |
| `file` | 否 no | `signals_feed.json` | feed 文件路径，≤1 MiB / feed file path, max 1 MiB |
| `subscription_id` | 否 no | 空 empty | 目标订阅 ID（数字）；账号下恰好一条进行中的订阅时可省略，多条时必须填 / target subscription ID; optional with exactly one active subscription, required with several |
| `endpoint` | 否 no | `https://server.tokenbeep.com/v1/app/signal-feed/push` | 推送地址，正常不用改 / push endpoint, normally leave as is |

> 账号下有多条进行中的订阅时，推送必须指明目标订阅：请向平台获取该机器人对应订阅的数字 ID 后填入 `subscription_id`（一个机器人一条，各填各的）。
> With several active subscriptions you must target one: get the numeric subscription ID for that bot from the platform and set `subscription_id`.

## 输出 / Outputs

| 输出 Output | 说明 Description |
|---|---|
| `accepted` | 本次新增事件数 / newly accepted events |
| `skipped` | 低于水位或已处理过的旧事件数 / already-known events |
| `rejected` | 被拒事件数 / rejected events |
| `last_event_id` | 服务端已提交水位 / committed watermark |

## 常见报错 / Troubleshooting

按日志里的关键词对号入座：

| 日志 / Log | 含义 / Meaning | 怎么办 / Fix |
|---|---|---|
| `api_key 为空` | 没配 secret，或 workflow 里名字写错 | 仓库 Actions secret 名用 `TOKENBEEP_API_KEY`，workflow 用 `api_key: ${{ secrets.TOKENBEEP_API_KEY }}` |
| `subscription_id 必须是纯数字` | `subscription_id` 填了非数字 | 填目标订阅的数字 ID |
| `文件不存在或不可读` | `file` 路径不对，或机器人没写出文件 | 让 `file:` 与生成步骤的输出路径一致 |
| `文件超过 1 MiB` | feed 超限 | 按平台容量规则瘦身：只裁已消费事件，`next_event_id` 不重置 |
| `不是合法 JSON` | 半截或非法 JSON | 本地 `jq . signals_feed.json` 通过后再提交 |
| `请求失败（curl 退出码 N）` | 网络问题，平台不可达 | 稍后重跑一次 |
| `HTTP 状态码非 200` | 网关或服务异常 | 稍后重跑；持续出现联系平台 |
| `响应不是 JSON` | 请求打到了非预期地址（endpoint 被改或走错代理） | 检查 `endpoint` 输入，默认官方地址一般不用改 |
| `err_code=202` | 无效 token：Key 错了、已撤销或过期 | 到「外部接入」重新生成「发信号」Key，更新仓库 secret |
| `err_code=1603` | Key 缺 `write:signals` 权限 | 换用「发信号」权限的 Key |
| `err_code=210` | 账号当前没有发信号权限 | 联系平台确认发布资格 |
| `err_code=1990` | 订阅不存在，或不属于这个账号 | 核对 `subscription_id` 是本账号名下、未断开的订阅 |
| `err_code=1991` | 事件格式错：feed 不符 Feed v1（字段、断档、半截 JSON） | 按返回的 `err_msg` 修 feed 后重推 |
| `err_code=1994` | 风控闸拒：订阅暂停、冲突或事件处理失败 | 看订阅详情「最近错误」，处理后重推（重推安全） |
| `err_code=2057` | 订阅正被拉取或另一次推送占用 | Action 已自动重试 3 次；仍失败稍后重跑 workflow |
| `err_code=901` | 参数不对：多条进行中订阅没填 `subscription_id`、订阅未在运行（暂停/断开/到期）或文件超限 | 按 `err_msg` 处理：补 ID、恢复订阅或瘦身 |

## 从 URL 拉取迁移 / Migrating from a URL pull subscription

原本「公开 raw 文件 + URL 拉取」的用户**不要**按上面的顺序先转私有，按这里的顺序走：

1. **先暂停**旧的 URL 订阅（订阅详情 → 暂停）。暂停会立即停止拉取、保留进度，不是终态；旧订阅暂停前不要执行推送——新旧两个订阅同时运行会把同一条事件各发一次。
2. 按第 2 步新建「GitHub Action 推送」订阅（上传当前 feed），按第 3 步配好 secret 与 workflow。旧订阅暂停后不算「进行中」，若账号下没有其它进行中的订阅，首次推送可以不填 `subscription_id`。
3. 把仓库转私有（第 1 步），触发首次推送（第 4 步），确认信号按预期进来。
4. 确认无误后再断开旧订阅（终态）。**断开前想清楚**：旧订阅产生的未平仓信号会被标记为手动、不再自动更新，跟随这些信号的用户也不会自动迁到新订阅；若此时还有未平仓仓位，先和平台确认迁移方式。

补充：切换期间的历史事件不补发；当前未平仓仓位在新建推送订阅时以「接入时已持有」快照导入，之后的加仓 / 移止损 / 平仓事件经推送正常同步。

For an existing public raw URL feed, do **not** start with "make the repo private". Instead: 1) pause the old URL subscription first (stops polling, keeps its watermark) and do not push while it is still running — running both publishes the same event twice; 2) create the push subscription and set up the secret/workflow; a paused subscription does not count as active, so if no other subscription is active the first push does not need `subscription_id`; 3) make the repo private and trigger the first push; 4) only after everything looks right, disconnect the old subscription (terminal). Note: disconnecting marks its open signals as manual — they stop updating automatically and their followers do not migrate to the new subscription; if positions are still open, check with the platform first. Events from the transition window are not replayed; open positions are imported as an "already held at setup" snapshot and continue through pushes.

## 安全 / Security

- Key 只放仓库 Secret，不要写进 workflow 文件、代码或日志；本 Action 会把 Key 从日志输出里隐去。
- Key 泄露时，到「外部接入」撤销并新建，然后更新仓库 Secret。
- Keep the key in repository secrets only. The Action masks it from logs. If leaked, revoke and recreate it, then update the secret.

## 开发 / Development

`bash tests/run.sh`（离线，要求 `jq`）；CI 另外跑 `shellcheck push.sh tests/run.sh`。
Offline tests, requires `jq`; CI also runs shellcheck.

## License

MIT

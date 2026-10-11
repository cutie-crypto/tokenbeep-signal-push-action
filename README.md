# tokenbeep-signal-push-action

把机器人写出的 `signals_feed.json`（schema=1）推送到 TokenBeep 的官方 GitHub Action。
Official GitHub Action that pushes a bot-generated `signals_feed.json` (schema=1) to TokenBeep.

## 接入 / Setup

1. 先在 TokenBeep 用 feed 地址建好信号源订阅（一期只支持推给已有地址的订阅，定时拉取照常进行，推送只是让新事件更快到达）；
   再到「外部接入」创建一个勾选「发布信号」（`write:signals`）权限的 API Key（只显示一次，请立即保存）。
   First create a feed subscription in TokenBeep with your feed URL (phase 1 only pushes to existing URL subscriptions;
   scheduled polling keeps running, push just delivers new events sooner). Then create an API key with the
   "publish signals" (`write:signals`) scope under "External access" (shown only once).
2. 在你的仓库 Settings → Secrets and variables → Actions 新建 `TOKENBEEP_API_KEY`。
   Create a repository secret named `TOKENBEEP_API_KEY`.
3. 在机器人写完 `signals_feed.json` 的那一步之后加上：
   Add this step right after the step that writes `signals_feed.json`:

```yaml
- uses: cutie-crypto/tokenbeep-signal-push-action@v1
  with:
    api_key: ${{ secrets.TOKENBEEP_API_KEY }}
```

- 你的仓库可以设为私有。 Your repository can be private.
- 重复推送是安全的，服务端幂等。 Pushing the same feed twice is safe (idempotent).
- 账号下有多条订阅时必须填 `subscription_id`（订阅详情页可见）。 Set `subscription_id` if your account has more than one subscription.
- 订阅正在同步时服务端会回「稍后重试」，Action 自动退避重试 3 次（5s / 10s / 20s）。 When the subscription is busy syncing, the Action retries 3 times with backoff (5s / 10s / 20s).
- 失败时看 Action 日志里的 `err_msg`。 On failure, read `err_msg` in the Action log.

## 输入 / 输出 (Inputs / Outputs)

| 输入 Input | 必填 Required | 默认 Default | 说明 Description |
|---|---|---|---|
| `api_key` | 是 yes | - | 必须来自 secrets / must come from secrets |
| `file` | 否 no | `signals_feed.json` | feed 文件路径，不超过 1 MiB / feed file path, max 1 MiB |
| `subscription_id` | 否 no | 空 empty | 目标订阅 ID；账号下恰好一条进行中的订阅时可不填 / target subscription; optional with exactly one active subscription |
| `endpoint` | 否 no | `https://server.tokenbeep.com/v1/app/signal-feed/push` | 推送地址 / push endpoint |

| 输出 Output | 说明 Description |
|---|---|
| `accepted` | 接受条数 / accepted events |
| `skipped` | 跳过条数 / skipped events |
| `rejected` | 拒绝条数 / rejected events |
| `last_event_id` | 服务端最新事件 ID / last event id on the server |

## 开发 / Development

`bash tests/run.sh`（不联网，需要 `jq`）。 Offline tests, requires `jq`.

## License

MIT

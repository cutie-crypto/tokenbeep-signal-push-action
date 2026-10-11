# tokenbeep-signal-push-action

把机器人写出的 `signals_feed.json`（schema=1）推送到 TokenBeep 的官方 GitHub Action。
Official GitHub Action that pushes a bot-generated `signals_feed.json` (schema=1) to TokenBeep.

## 接入 / Setup

1. 在 TokenBeep「添加信号源」里选「推送」，拿到 API Key（只显示一次，请立即保存）。
   In TokenBeep "Add signal source", choose "Push" and copy the API key (shown only once).
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
- 失败时看 Action 日志里的 `err_msg`。 On failure, read `err_msg` in the Action log.

## 输入 / 输出 (Inputs / Outputs)

| 输入 Input | 必填 Required | 默认 Default | 说明 Description |
|---|---|---|---|
| `api_key` | 是 yes | - | 必须来自 secrets / must come from secrets |
| `file` | 否 no | `signals_feed.json` | feed 文件路径，不超过 1 MiB / feed file path, max 1 MiB |
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

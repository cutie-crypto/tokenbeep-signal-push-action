#!/usr/bin/env bash
echo "::add-mask::${API_KEY-}"
set -euo pipefail

# 输入全部来自环境变量：FEED_FILE / API_KEY / ENDPOINT（由 action.yml 的 env: 传入）。
FEED_FILE=${FEED_FILE:-signals_feed.json}
ENDPOINT=${ENDPOINT:-https://server.tokenbeep.com/v1/app/signal-feed/push}
API_KEY=${API_KEY-}
MAX_BYTES=1048576

fail() { echo "::error::$1" >&2; exit 1; }

# 把文本里的 key 替换掉，再输出。
redact() { local s=$1; printf '%s' "${s//"$API_KEY"/***}"; }

[[ -n $API_KEY ]] || fail "api_key 为空 / api_key is empty"
[[ -f $FEED_FILE && -r $FEED_FILE ]] || fail "文件不存在或不可读 / file missing or unreadable: $FEED_FILE"

size=$(wc -c < "$FEED_FILE" | tr -d ' ')
if (( size > MAX_BYTES )); then
  fail "文件超过 1 MiB，请先瘦身 / file exceeds 1 MiB (${size} bytes), please slim it down"
fi
jq -e . "$FEED_FILE" > /dev/null 2>&1 || fail "不是合法 JSON / not valid JSON: $FEED_FILE"

tmp_root=${RUNNER_TEMP:-${TMPDIR:-/tmp}}
work=$(mktemp -d "${tmp_root%/}/tokenbeep-push.XXXXXX")
trap 'rm -rf "$work"' EXIT
umask 077
# key 只写入临时头文件，不出现在 curl 的 argv 里
printf 'Authorization: Bearer %s\n' "$API_KEY" > "$work/headers"
resp="$work/resp"

rc=0
status=$(curl -sS --max-time 60 --retry 3 --retry-all-errors \
  -o "$resp" -w '%{http_code}' \
  -H "@$work/headers" \
  -F "feed=@${FEED_FILE};type=application/json" \
  "$ENDPOINT") || rc=$?
if (( rc != 0 )); then
  fail "请求失败（curl 退出码 ${rc}）/ request failed (curl exit ${rc})"
fi

body=$(cat "$resp")
red=$(redact "$body")
if [[ $status != 200 ]]; then
  echo "HTTP $status" >&2
  head -c 500 <<< "$red" >&2
  echo >&2
  fail "HTTP 状态码非 200 / non-200 HTTP status: $status"
fi

jq -e . > /dev/null 2>&1 <<< "$body" || fail "响应不是 JSON / response is not JSON"

err_code=$(jq -r '.err_code // empty' <<< "$body")
if [[ $err_code != 100 ]]; then
  err_msg=$(jq -r '.err_msg // empty' <<< "$body")
  echo "err_code=$err_code" >&2
  echo "err_msg=$(redact "$err_msg")" >&2
  fail "推送被拒绝 / push rejected by server"
fi

accepted=$(jq -r '.data.accepted // 0' <<< "$body")
skipped=$(jq -r '.data.skipped // 0' <<< "$body")
rejected=$(jq -r '.data.rejected // 0' <<< "$body")
last_event_id=$(jq -r '.data.last_event_id // 0' <<< "$body")
echo "accepted=$accepted skipped=$skipped rejected=$rejected last_event_id=$last_event_id"
if [[ -n ${GITHUB_OUTPUT-} ]]; then
  {
    echo "accepted=$accepted"
    echo "skipped=$skipped"
    echo "rejected=$rejected"
    echo "last_event_id=$last_event_id"
  } >> "$GITHUB_OUTPUT"
fi

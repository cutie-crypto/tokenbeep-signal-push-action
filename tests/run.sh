#!/usr/bin/env bash
# FAKE_BODY 等变量是原样交给假 curl 的 JSON 响应体（经环境变量传递，不做词法展开），引号是数据本身。
# shellcheck disable=SC2089,SC2090
# 不联网的单元测试：PATH 前面放一个假 curl，按环境变量返回预设状态码和响应体。
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PUSH="$ROOT/push.sh"
DEFAULT_ENDPOINT="https://server.tokenbeep.com/v1/app/signal-feed/push"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0
total=0
check() { # check <描述> <命令...>
  local desc=$1; shift
  total=$((total + 1))
  if "$@"; then
    pass=$((pass + 1))
    echo "ok   - $desc"
  else
    echo "FAIL - $desc"
  fi
}
contains() { grep -qF -- "$2" "$1"; }
not_contains() { ! grep -qF -- "$2" "$1"; }
equals() { [[ $1 == "$2" ]]; }

# 假 curl：记 argv、头文件内容；按 FAKE_STATUS / FAKE_BODY / FAKE_CURL_EXIT 返回。
mkdir -p "$TMP/bin"
cat > "$TMP/bin/curl" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_LOG.argv"
args=("$@")
out=""; w=""
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[i]}" in
    -o) out=${args[i+1]} ;;
    -w) w=${args[i+1]} ;;
    -H) h=${args[i+1]}; if [[ $h == @* ]]; then cat "${h#@}" >> "$FAKE_LOG.hdr"; fi ;;
  esac
done
if [[ -n ${FAKE_CURL_EXIT-} ]]; then exit "$FAKE_CURL_EXIT"; fi
[[ -n $out ]] && printf '%s' "${FAKE_BODY-}" > "$out"
[[ $w == *http_code* ]] && printf '%s' "${FAKE_STATUS:-200}"
exit 0
FAKE
chmod +x "$TMP/bin/curl"

new_key() { echo "tbk_$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')"; }

# run_case <名称>：用当前环境变量 FEED / KEY / EP / FAKE_* 跑 push.sh
# 产物：$TMP/<名称>/{out,err,argv,hdr,gh,rc}
run_case() {
  local d="$TMP/$1"
  mkdir -p "$d/rt"
  : > "$d/gh"
  (
    export PATH="$TMP/bin:$PATH"
    export FAKE_LOG="$d/fake" RUNNER_TEMP="$d/rt" GITHUB_OUTPUT="$d/gh"
    export FEED_FILE="$FEED" API_KEY="$KEY"
    if [[ -n ${EP-} ]]; then export ENDPOINT="$EP"; else unset ENDPOINT; fi
    bash "$PUSH" > "$d/out" 2> "$d/err"
    echo $? > "$d/rc"
  )
  touch "$d/fake.argv" "$d/fake.hdr"
  RC=$(cat "$d/rc")
  # add-mask 行本来就是要把 key 交给 runner 的，不算泄露；其余输出一律不许出现 key
  grep -v '^::add-mask::' "$d/out" > "$d/out.filtered"
  cat "$d/out.filtered" "$d/err" "$d/fake.argv" > "$d/visible"
}

echo '{"schema":1,"events":[]}' > "$TMP/feed.json"
FEED="$TMP/feed.json"
OK_BODY='{"err_code":100,"err_msg":"ok","data":{"accepted":3,"skipped":2,"rejected":1,"last_event_id":42}}'

# 1. 成功
KEY=$(new_key); EP=""; FAKE_STATUS=200; FAKE_BODY=$OK_BODY; unset FAKE_CURL_EXIT
export FAKE_STATUS FAKE_BODY
run_case ok
check "成功：退出 0" equals "$RC" 0
check "成功：打印四个值" contains "$TMP/ok/out" "accepted=3 skipped=2 rejected=1 last_event_id=42"
check "成功：GITHUB_OUTPUT 内容正确" equals "$(tr '\n' ' ' < "$TMP/ok/gh")" "accepted=3 skipped=2 rejected=1 last_event_id=42 "
check "成功：第一行是 add-mask" equals "$(head -n1 "$TMP/ok/out")" "::add-mask::$KEY"
check "成功：临时头文件已清理" equals "$(find "$TMP/ok/rt" -type f | wc -l | tr -d ' ')" 0
check "成功：以 feed 文件字段上传" contains "$TMP/ok/fake.argv" "feed=@$FEED;type=application/json"

# 5. key 不在 argv / stdout / stderr，只在头文件里
check "key 不在 argv 与输出里" not_contains "$TMP/ok/visible" "$KEY"
check "key 通过头文件传给 curl" contains "$TMP/ok/fake.hdr" "Authorization: Bearer $KEY"

# 6. endpoint
check "默认 endpoint 正确" contains "$TMP/ok/fake.argv" "$DEFAULT_ENDPOINT"
KEY=$(new_key); EP="https://example.invalid/custom/push"
run_case ep
check "自定义 endpoint 生效" contains "$TMP/ep/fake.argv" "$EP"
check "自定义 endpoint 时不再用默认地址" not_contains "$TMP/ep/fake.argv" "$DEFAULT_ENDPOINT"
EP=""

# 2. 业务失败 err_code=4xx（响应里故意带上 key，验证脱敏）
KEY=$(new_key)
FAKE_BODY="{\"err_code\":403,\"err_msg\":\"bad key $KEY\",\"data\":null}"; export FAKE_BODY
run_case biz
check "err_code=403：退出 1" equals "$RC" 1
check "err_code=403：打印 err_msg" contains "$TMP/biz/err" "bad key"
check "err_code=403：打印 err_code" contains "$TMP/biz/err" "err_code=403"
check "err_code=403：响应里的 key 已脱敏" not_contains "$TMP/biz/visible" "$KEY"
check "err_code=403：不写 GITHUB_OUTPUT" equals "$(wc -c < "$TMP/biz/gh" | tr -d ' ')" 0

# 3. HTTP 502
KEY=$(new_key); FAKE_STATUS=502; FAKE_BODY="<html>bad gateway $KEY</html>"; export FAKE_STATUS FAKE_BODY
run_case gw
check "HTTP 502：退出 1" equals "$RC" 1
check "HTTP 502：打印状态码" contains "$TMP/gw/err" "HTTP 502"
check "HTTP 502：响应体里的 key 已脱敏" not_contains "$TMP/gw/visible" "$KEY"
FAKE_STATUS=200

# 响应不是 JSON
KEY=$(new_key); FAKE_BODY="not json at all"; export FAKE_BODY
run_case notjson
check "响应不是 JSON：退出 1" equals "$RC" 1

# 网络错误（curl 自身非 0 退出）
KEY=$(new_key); FAKE_BODY=$OK_BODY; FAKE_CURL_EXIT=28; export FAKE_BODY FAKE_CURL_EXIT
run_case net
check "curl 网络错误：退出 1" equals "$RC" 1
unset FAKE_CURL_EXIT
FAKE_BODY=$OK_BODY; export FAKE_BODY

# 4. 前置检查
KEY=$(new_key); FEED="$TMP/nope.json"
run_case nofile
check "文件缺失：退出 1" equals "$RC" 1
check "文件缺失：没有调用 curl" equals "$(wc -c < "$TMP/nofile/fake.argv" | tr -d ' ')" 0

head -c 1048577 /dev/zero | tr '\0' ' ' > "$TMP/big.json"
FEED="$TMP/big.json"
run_case big
check "超 1 MiB：退出 1" equals "$RC" 1
check "超 1 MiB：提示瘦身" contains "$TMP/big/err" "瘦身"

echo '{not json' > "$TMP/bad.json"
FEED="$TMP/bad.json"
run_case badjson
check "非法 JSON：退出 1" equals "$RC" 1
check "非法 JSON：提示不是合法 JSON" contains "$TMP/badjson/err" "不是合法 JSON"

FEED="$TMP/feed.json"; KEY=""
run_case nokey
check "key 为空：退出 1" equals "$RC" 1
check "key 为空：没有调用 curl" equals "$(wc -c < "$TMP/nokey/fake.argv" | tr -d ' ')" 0

echo "PASS $pass/$total"
[[ $pass == "$total" ]]

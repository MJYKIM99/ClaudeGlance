#!/bin/bash
#
# claude-glance-reporter.sh
# Claude Glance Hook Reporter
#
# 这个脚本通过 Claude Code hooks 将状态信息发送给 Claude Glance HUD
#
# 使用方法:
#   1. 将此脚本复制到 ~/.claude/hooks/
#   2. 在 ~/.claude/settings.json 中配置 hooks
#

set -e

# 配置
GLANCE_SOCKET="/tmp/claude-glance.sock"
GLANCE_HTTP="http://localhost:19847/api/status"
PROTOCOL_VERSION=1

# 获取会话标识
get_session_id() {
    # 优先使用 Claude 提供的会话 ID
    if [[ -n "$CLAUDE_SESSION_ID" ]]; then
        echo "$CLAUDE_SESSION_ID"
        return
    fi

    # 否则基于 TTY 生成
    if command -v md5 &> /dev/null; then
        tty 2>/dev/null | md5 | head -c 8
    elif command -v md5sum &> /dev/null; then
        tty 2>/dev/null | md5sum | head -c 8
    else
        echo "session-$$"
    fi
}

# 获取终端名称
get_terminal_name() {
    if [[ -n "$TERM_PROGRAM" ]]; then
        echo "$TERM_PROGRAM"
    elif [[ -n "$TERMINAL_EMULATOR" ]]; then
        echo "$TERMINAL_EMULATOR"
    elif [[ -n "$ITERM_SESSION_ID" ]]; then
        echo "iTerm2"
    else
        echo "Terminal"
    fi
}

# 主逻辑
main() {
    local hook_event="$1"

    # 从 stdin 读取 hook 输入
    local hook_input
    hook_input=$(cat)

    # 如果输入为空，使用空对象
    if [[ -z "$hook_input" ]]; then
        hook_input="{}"
    fi

    # 获取元数据
    local session_id
    session_id=$(get_session_id)

    local terminal_name
    terminal_name=$(get_terminal_name)

    local project_name
    project_name=$(basename "$(pwd)")

    local cwd
    cwd=$(pwd)

    # ms timestamp; macOS BSD date does not support %3N, so use python3
    # (already required by this script). Fallback to seconds * 1000.
    local timestamp
    timestamp=$(python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null \
                || echo "$(date +%s)000")

    # 构建 JSON payload（通过环境变量传入 python3 安全编码）
    if ! command -v python3 &>/dev/null; then
        exit 0
    fi

    local payload
    payload=$(
        _GLANCE_SID="$session_id" \
        _GLANCE_TERM="$terminal_name" \
        _GLANCE_PROJ="$project_name" \
        _GLANCE_CWD="$cwd" \
        _GLANCE_EVT="$hook_event" \
        _GLANCE_INPUT="$hook_input" \
        _GLANCE_TS="$timestamp" \
        _GLANCE_PROTO="$PROTOCOL_VERSION" \
        python3 -c '
import json, os
e = os.environ.get
try: data = json.loads(e("_GLANCE_INPUT", "{}"))
except Exception: data = {}
print(json.dumps({
    "protocol_version": int(e("_GLANCE_PROTO", "1")),
    "session_id": e("_GLANCE_SID", ""),
    "terminal": e("_GLANCE_TERM", "Terminal"),
    "project": e("_GLANCE_PROJ", ""),
    "cwd": e("_GLANCE_CWD", ""),
    "timestamp": int(e("_GLANCE_TS", "0")),
    "event": e("_GLANCE_EVT", ""),
    "data": data,
}))
'
    )

    # 发送到 HUD
    send_to_hud "$payload"
}

send_to_hud() {
    local payload="$1"

    # 优先使用 Unix Socket
    if [[ -S "$GLANCE_SOCKET" ]]; then
        echo "$payload" | nc -U "$GLANCE_SOCKET" 2>/dev/null && return 0
    fi

    # 降级到 HTTP
    if command -v curl &> /dev/null; then
        curl -s -X POST "$GLANCE_HTTP" \
            -H "Content-Type: application/json" \
            -d "$payload" \
            --connect-timeout 1 \
            --max-time 2 \
            2>/dev/null || true
    fi
}

# 运行
main "$@"

exit 0

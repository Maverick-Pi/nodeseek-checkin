#!/usr/bin/env bash
# 安装定时任务：交互式设置签到的最早时间和随机区间（均按北京时间）。
#
# 用法：
#   ./install_cron.sh                          交互式：提示输入，直接回车采用默认值
#   START=00:01 WINDOW=4 ./install_cron.sh     非交互：直接指定（不合法会报错退出）
#   DRY_RUN=1 ./install_cron.sh                只检查并打印，不修改 crontab
#   ./install_cron.sh --uninstall              卸载
#
# 可选环境变量：PYTHON、MEM_LIMIT、SWAP_LIMIT（含义见 run.sh）
set -eu

# 优先获取当前环境的 python，如果没有则获取 python3
if command -v python &> /dev/null; then
    PYTHON="${PYTHON:-$(command -v python)}"
else
    PYTHON="${PYTHON:-$(command -v python3)}"
fi

echo "👉 检测到当前环境的 Python 绝对路径：$PYTHON"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON="${PYTHON:-$(command -v python3)}"
MEM_LIMIT="${MEM_LIMIT:-}"
SWAP_LIMIT="${SWAP_LIMIT:-}"

TAG="# nodeseek-checkin"
DEFAULT_START="00:01"   # 默认最早签到时间
DEFAULT_WINDOW=4        # 默认随机区间（分钟）
MARGIN=40               # 预留给"启动浏览器并点击"的秒数
MIN_START=1             # 最早开始时间：00:01（当天 0 点起算的分钟数）
MAX_END=1439            # 区间必须在 23:59 之前结束
START_MIN=0

die() { echo "错误：$*" >&2; exit 1; }

if [ "${1:-}" = "--uninstall" ]; then
    ( crontab -l 2>/dev/null | grep -v "$TAG" || true ) | crontab -
    echo "已卸载"
    exit 0
fi

# ---- 校验函数：通过返回 0；不通过打印原因并返回 1 ----
check_start() {
    local s="$1"
    if ! [[ "$s" =~ ^([01]?[0-9]|2[0-3]):([0-5][0-9])$ ]]; then
        echo "  ✗ 时间格式应为 HH:MM，例如 00:01" >&2
        return 1
    fi
    local h=$((10#${BASH_REMATCH[1]})) m=$((10#${BASH_REMATCH[2]}))
    START_MIN=$((h * 60 + m))
    if [ "$START_MIN" -lt "$MIN_START" ]; then
        echo "  ✗ 不能早于 00:01。NodeSeek 以北京时间 0 点为界，离得太近容易因时钟偏差落到前一天。" >&2
        return 1
    fi
    if [ "$START_MIN" -ge "$MAX_END" ]; then
        echo "  ✗ 太晚了，当天剩余时间放不下随机区间，最晚可选 23:58。" >&2
        return 1
    fi
}

check_window() {
    local w="$1" max=$((MAX_END - START_MIN))
    if ! [[ "$w" =~ ^[0-9]{1,4}$ ]] || [ "$w" -lt 1 ]; then
        echo "  ✗ 请输入不小于 1 的整数（分钟）。" >&2
        return 1
    fi
    if [ "$w" -gt "$max" ]; then
        echo "  ✗ 区间不能跨过 0 点：从 $START 开始，最多只能选 $max 分钟。" >&2
        return 1
    fi
}

# prompt_loop 变量名 提示语 默认值 校验函数：回车用默认值，不通过则重新输入
prompt_loop() {
    local name="$1" prompt="$2" default="$3" checker="$4" value
    while true; do
        read -r -p "$prompt [默认 $default，直接回车采用]: " value || die "输入被中断"
        value="${value:-$default}"
        if "$checker" "$value"; then
            printf -v "$name" '%s' "$value"
            return 0
        fi
    done
}

INTERACTIVE=0
if [ -t 0 ]; then INTERACTIVE=1; fi

# ---- 1. 最早签到时间 ----
if [ -n "${START:-}" ]; then
    check_start "$START" || die "START 参数无效"
elif [ "$INTERACTIVE" = 1 ]; then
    prompt_loop START "最早签到时间（北京时间 HH:MM）" "$DEFAULT_START" check_start
else
    START="$DEFAULT_START"
    check_start "$START" || die "默认开始时间无效"
fi

# ---- 2. 随机区间 ----
MAX_WINDOW=$((MAX_END - START_MIN))
DEF_W=$DEFAULT_WINDOW
if [ "$DEF_W" -gt "$MAX_WINDOW" ]; then DEF_W=$MAX_WINDOW; fi

if [ -n "${WINDOW:-}" ]; then
    check_window "$WINDOW" || die "WINDOW 参数无效"
elif [ "$INTERACTIVE" = 1 ]; then
    prompt_loop WINDOW "随机区间长度（分钟，1~${MAX_WINDOW}）" "$DEF_W" check_window
else
    WINDOW="$DEF_W"
fi

# ---- 3. 计算并安装 ----
JITTER=$((WINDOW * 60 - MARGIN))
END_MIN=$((START_MIN + WINDOW))
END_H=$((END_MIN / 60)); END_M=$((END_MIN % 60))

# 把北京时间的开始时刻换算成本机时区的分和时（GNU date）
read -r MIN HOUR < <(date -d "TZ=\"Asia/Shanghai\" $START" '+%-M %-H')

echo
echo "签到将发生在北京时间 $START ~ $(printf '%02d:%02d' "$END_H" "$END_M") 之间"
echo "  cron 触发时刻（本机时区 $(date +%Z)）：$(printf '%02d:%02d' "$HOUR" "$MIN")，随后随机等待 0~${JITTER} 秒"
echo "  使用的 Python：$PYTHON"

LINE="$MIN $HOUR * * * PYTHON=\"$PYTHON\" JITTER=$JITTER MEM_LIMIT=\"$MEM_LIMIT\" SWAP_LIMIT=\"$SWAP_LIMIT\" \"$DIR/run.sh\" $TAG"

if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[DRY_RUN] 将写入：$LINE"
    exit 0
fi

# 先删掉旧的同名条目，再追加新的，重复运行不会产生多条
( crontab -l 2>/dev/null | grep -v "$TAG" || true; echo "$LINE" ) | crontab -
echo "已安装：$LINE"

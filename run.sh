#!/usr/bin/env bash
# 用法：
#   ./run.sh              正常运行（先随机等待一会儿）
#   JITTER=1 ./run.sh     测试用，几乎不等待
set -u

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR" || exit 1

# ==========================================
# 🔒 核心修改：使用 flock 实现互斥锁
# 如果已经有一个 run.sh 在运行，这次直接静默退出，避免并发冲突
# ==========================================
LOCK_FILE="/tmp/nodeseek_checkin.lock"
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 已有签到任务在运行，跳过本次执行。" >> "$DIR/checkin.log"
    exit 0
fi

PYTHON="${PYTHON:-python3}"
JITTER="${JITTER:-220}"
MEM_LIMIT="${MEM_LIMIT:-}"
SWAP_LIMIT="${SWAP_LIMIT:-}"

if [ "$JITTER" -gt 0 ]; then
    sleep $((RANDOM % JITTER))
fi

CMD=("$PYTHON" checkin.py)

# 有界面模式需要显示器：没有就用 xvfb 提供一个虚拟的
if command -v xvfb-run >/dev/null 2>&1; then
    CMD=(xvfb-run -a "${CMD[@]}")
fi

if [ -n "$MEM_LIMIT" ] && command -v systemd-run >/dev/null 2>&1; then
    LIMITS=(-p "MemoryMax=$MEM_LIMIT")
    if [ -n "$SWAP_LIMIT" ]; then
        LIMITS+=(-p "MemorySwapMax=$SWAP_LIMIT")
    fi
    CMD=(systemd-run --scope -q "${LIMITS[@]}" -p RuntimeMaxSec=900 "${CMD[@]}")
fi

# ==========================================
# 🧹 日志防撑爆（保留最后 500 行）
# ==========================================
if [ -f "$DIR/checkin.log" ]; then
    # 只有当日志超过一定行数（比如 1000 行）才触发截断，提升性能
    if [ "$(wc -l < "$DIR/checkin.log")" -gt 1000 ]; then
        tail -n 500 "$DIR/checkin.log" > "$DIR/checkin.log.tmp" && mv "$DIR/checkin.log.tmp" "$DIR/checkin.log"
    fi
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] ===== 开始执行任务 =====" >> "$DIR/checkin.log"
exec "${CMD[@]}" >> "$DIR/checkin.log" 2>&1

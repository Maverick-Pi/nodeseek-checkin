#!/usr/bin/env bash
set -e

echo "========================================="
echo "  NodeSeek 自动签到 - 一键安装脚本"
echo "========================================="

# 判断是否需要 sudo 前缀
if [ "$EUID" -ne 0 ]; then
  SUDO="sudo"
else
  SUDO=""
fi

# 1. 检查系统环境
if ! command -v apt-get &> /dev/null; then
    echo "❌ 目前一键脚本仅支持 Debian/Ubuntu 系统。"
    exit 1
fi

# 2. 检查 Python 版本 (必须 >= 3.10)
if ! command -v python &> /dev/null; then
    echo "❌ 未检测到 python 命令，请先激活你的 conda 或 venv 环境。"
    exit 1
fi

PYTHON_VERSION=$(python -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
PY_MAJOR=$(echo "$PYTHON_VERSION" | cut -d. -f1)
PY_MINOR=$(echo "$PYTHON_VERSION" | cut -d. -f2)

if [ "$PY_MAJOR" -lt 3 ] || { [ "$PY_MAJOR" -eq 3 ] && [ "$PY_MINOR" -lt 10 ]; }; then
    echo "❌ 错误：检测到 Python 版本为 $PYTHON_VERSION，但 Patchright 需要 Python >= 3.10"
    exit 1
fi
echo "✅ Python 版本符合要求 ($PYTHON_VERSION)，路径：$(which python)"

# 3. 安装系统依赖 (自动使用 sudo)
echo "⏳ 正在安装系统依赖 (可能需要输入密码)..."
$SUDO apt-get update -qq
$SUDO apt-get install -y wget xvfb libappindicator3-1 libasound2 fonts-liberation libnss3 \
    libxss1 libgbm-dev lsb-release xdg-utils > /dev/null 2>&1

# 4. 安装 Google Chrome (如果尚未安装)
if ! command -v google-chrome &> /dev/null; then
    echo "⏳ 未检测到 Chrome，正在下载并安装..."
    wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
    $SUDO apt-get install -y ./google-chrome-stable_current_amd64.deb > /dev/null 2>&1
    rm -f google-chrome-stable_current_amd64.deb
else
    echo "✅ 已安装 Chrome，跳过。"
fi

# 5. 安装 Python 依赖 (绝不加 sudo，直接装进当前 conda 环境)
echo "⏳ 正在向当前环境安装 Python 依赖..."
python -m pip install patchright

echo "⏳ 正在下载 Patchright 所需的 Chromium 内核..."
python -m patchright install chromium

# 6. 初始化配置文件
if [ ! -f .env ]; then
    cp .env.example .env
    echo "⚠️  已生成 .env 配置文件。"
    echo "👉 请先编辑 .env 文件（vi .env 或 nano .env），填入你的 NS_COOKIE！"
else
    echo "✅ .env 文件已存在，跳过生成。"
fi

echo "========================================="
echo "🎉 安装完成！"
echo "接下来的步骤："
echo "1. 编辑 .env 文件，填入你的 Cookie。"
echo "2. 运行 ./install_cron.sh 设置定时任务。"
echo "========================================="
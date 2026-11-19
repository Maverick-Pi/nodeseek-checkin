# NodeSeek 自动签到脚本

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Python](https://img.shields.io/badge/python-%3E%3D3.10-blue)
![Platform](https://img.shields.io/badge/platform-Linux-lightgrey)

NodeSeek 论坛每日自动签到脚本，部署在自己的 Linux 服务器上，由 Cron 定时执行，支持「试试手气」和「固定 5 鸡腿」两种模式。

本项目基于 **Patchright**（指纹修补版 Playwright），配合真实的 **Google Chrome** 和 **Xvfb** 虚拟显示环境，尽可能还原真人浏览器环境，以通过 Cloudflare Turnstile 人机验证。

> [!WARNING]
> 非官方项目，与 NodeSeek 无关。自动化操作可能不符合论坛规则，账号风险自负，详见文末[免责声明](#⚠️-免责声明)。

## ✨ 特性

- 🛡️ **提高过盾率**：不使用容易被识别的无头浏览器，采用 Patchright 补丁与原生 Chrome，浏览器指纹更接近真人。
- 🐧 **Linux 友好**：适配 Ubuntu/Debian 等无桌面环境的服务器，自动调用 Xvfb 提供虚拟屏幕。
- 🚀 **一键部署**：提供 `install.sh`，自动安装 Chrome、系统依赖和 Python 库。
- ⏰ **随机定时**：支持设置北京时间的时间段，自动随机延迟，避免固定时间被风控。
- 🔒 **防并发重复签到**：内置 `flock` 文件锁与幂等检测，Cron 与手动触发同时发生时也不会重复签到。
- 🪵 **日志管理**：自动截断日志防止塞满硬盘，签到失败自动截图便于排查。

## 📋 环境要求

- **Linux 服务器**（推荐 Ubuntu / Debian），能访问 nodeseek.com。
- **Python >= 3.10**（底层依赖 Patchright 的要求，推荐使用 Conda 或 Venv 管理）。
- 内存建议 1GB 以上并开启 Swap。

## 🚀 快速开始

### 1. 获取代码

```bash
git clone https://github.com/Maverick-Pi/nodeseek-checkin.git
cd nodeseek-checkin
```

### 2. 一键安装依赖

> [!IMPORTANT]
> 如果你使用 Miniconda/Anaconda 或 Venv，请先激活环境，再直接运行脚本，**不要加 sudo**。脚本内部会自动使用 `sudo` 安装系统级软件（如 Chrome），同时把 Python 库安装到你当前的虚拟环境中。

```bash
# 1. 激活你的环境（系统自带 Python 可跳过此步）
conda activate <你的环境名>

# 2. 赋予执行权限
chmod +x install.sh run.sh install_cron.sh

# 3. 运行安装脚本（不需要加 sudo！）
./install.sh
```

### 3. 配置 Cookie

1. 浏览器登录 NodeSeek。
2. 使用 Cookie-Editor 等插件，点击 Export，选择 **Header String**，内容会复制到剪贴板。
3. 将 `.env.example` 文件复制为 `.env`，把内容填入 `NS_COOKIE=` 后面（保持在同一行，不要加引号）。
4. 执行 `chmod 600 .env` 确保安全。

> [!WARNING]
> `.env` 中的注释必须单独占一行，不要写在配置项的行尾，否则会导致运行出错。详见下方[`.env` 书写规范](#env-书写规范)。

### 4. 手动测试

```bash
# 测试运行，跳过随机等待
JITTER=1 ./run.sh

# 查看运行日志
tail -n 20 checkin.log
```

日志输出示例（具体内容以实际为准）：

```text
2026-11-19 00:03:12 第 1/3 次：签到成功：{...}
```

### 5. 安装定时任务

```bash
# 如果你用的是 conda，请确保此时环境仍处于激活状态
./install_cron.sh
```

脚本会交互式询问你最早签到时间和随机区间（北京时间），并自动换算成本机时区写入 Crontab，同时自动捕获你当前 Python 的绝对路径。

## ⚙️ 配置项

### `.env` 配置

在 `.env` 中设置：

| 变量         | 默认     | 说明                                                           |
| :----------- | :------- | :------------------------------------------------------------- |
| `NS_COOKIE`  | 必填     | 登录 Cookie                                                    |
| `NS_MODE`    | `random` | `random`＝试试手气；`fixed`＝固定 5 鸡腿（两种模式均已验证可用） |
| `RETRIES`    | `3`      | 失败重试次数                                                   |
| `RETRY_WAIT` | `60`     | 重试前等待的秒数                                               |

### 脚本运行时的环境变量

运行 `install_cron.sh` 或 `run.sh` 时支持：

| 变量                       | 说明                                                       |
| :------------------------- | :--------------------------------------------------------- |
| `START` / `WINDOW`         | 非交互指定签到最早时间（北京时间 HH:MM）和随机区间（分钟） |
| `MEM_LIMIT` / `SWAP_LIMIT` | 限制 Chromium 的内存，如 `600M`（需要 systemd-run）        |
| `JITTER`                   | 随机等待的秒数，测试时可设为 `1`                           |

### `.env` 书写规范

脚本读取 `.env` 时，会把 `=` 后面的整行内容当作配置值，**不会自动剔除行尾注释**。因此配置和注释必须各占一行：

```ini
# ❌ 错误：注释和配置在同一行，值会变成 "fixed   # 固定 5 鸡腿"，运行报错
NS_MODE=fixed   # 固定 5 鸡腿

# ✅ 正确：注释独占一行，配置独占一行
# fixed = 固定 5 鸡腿；random = 试试手气
NS_MODE=fixed
```

## 🕒 签到时间

`install_cron.sh` 会询问两项：

- **最早签到时间**：默认北京时间 `00:01`。
- **随机区间**：默认 `4` 分钟（即签到发生在 00:01 ~ 00:05 之间的随机秒数）。

```bash
DRY_RUN=1 ./install_cron.sh      # 只检查并预览，不修改 crontab
./install_cron.sh --uninstall    # 卸载定时任务
```

## 🔄 更新与卸载

```bash
# 更新：拉取最新代码（.env 已被 .gitignore 忽略，不会被覆盖）
git pull

# 卸载定时任务
./install_cron.sh --uninstall
```

## 🔍 排错与日志

日志在项目根目录的 `checkin.log`：

- **没找到签到按钮**：Cookie 多半已过期，或页面改版。项目目录会生成 `fail.png`，打开查看当时的页面状态。
- **`ModuleNotFoundError`**：定时任务没找到 Python。请检查 `crontab -l` 里的 Python 路径是否正确。
- **内存不够 / 浏览器被杀**：开启 Swap，或调大 `MEM_LIMIT`。
- **验证一直卡住**：服务器 IP 可能被 CF 风控，脚本会自动截图 `fail.png`。

## ⚠️ 免责声明

本项目仅供个人学习和管理自己的账号使用。自动化操作可能违反 NodeSeek 的使用规则，可能导致账号受限，风险由使用者自行承担。请妥善保管 Cookie，不要泄露 `.env` 文件。作者不对任何后果负责。

## 📄 许可证

本项目基于 [MIT License](LICENSE) 开源。


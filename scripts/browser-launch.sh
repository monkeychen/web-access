#!/usr/bin/env zsh
# browser-launch.sh — 管理 web-access 的专用 Chrome 实例
#
# 设计原则（重要）：
#   本脚本 **只操作自己创建的实例**（独立 profile），绝不触碰用户的日常 Chrome
#   —— 不改它的数据、不改它的启动方式、不改它的生命周期。
#   用户的浏览器想开就开、想关就关，与本 skill 完全无关。
#
# 为什么需要专用实例：
#   Chrome 136+ 起，指向默认 profile 的 --remote-debugging-port 会被静默忽略
#   （chrome_paths.cc 里是路径相等比较）；退而求其次用 chrome://inspect 的
#   toggle 模式则是 approval 模式 —— 每次新连接都要人工点「允许」。
#   所以"无弹窗的 CDP"必须由一个「非默认 profile + 显式端口」的实例提供。
#
# 为什么不用 launchd 常驻：
#   常驻 + KeepAlive 会让浏览器"关不掉"，那是用户的浏览器不该承受的代价。
#   这里是按需启动、随时可停。
#
# 用法：
#   browser-launch.sh start        启动（静默，无窗口）
#   browser-launch.sh open         打开可见窗口（首次登录 / 人工操作）
#   browser-launch.sh stop         关闭实例
#   browser-launch.sh status       查看状态
#   browser-launch.sh port         输出 CDP 端口（供外部工具使用）
#   browser-launch.sh sync-login   从日常 Chrome 导入登录态（无需关闭 Chrome）
#   browser-launch.sh install-browser  安装专用浏览器（Chrome for Testing）

set -u

PROFILE="${WEB_ACCESS_PROFILE:-$HOME/.web-access/browser-profile}"
PORTFILE="$PROFILE/DevToolsActivePort"
LOGDIR="$HOME/.web-access"
LOG="$LOGDIR/chrome.log"
BROWSER_APPS_DIR="$LOGDIR/browser"

# ---------- 基础工具 ----------

# 专用浏览器的可执行文件。
#
# ⚠️ 为什么**绝不**用 /Applications/Google Chrome.app：
#   它与用户的日常 Chrome 是**同一个应用**（bundle id 均为 com.google.Chrome）。
#   macOS 的 LaunchServices 认为「Chrome 已在运行」，于是点 Dock 图标 /
#   open -a "Google Chrome" 全被路由到本实例；而本实例以 --no-startup-window
#   启动、不会开窗口 —— 用户看到的症状就是「Chrome 开不了也关不掉」，
#   日常浏览器根本起不来。（2026-09-12 实际踩到过）
#   所以专用实例必须用**应用身份独立**的构建：Chrome for Testing
#   （bundle id com.google.chrome.for.testing）。
find_chrome() {
  if [ -n "${WEB_ACCESS_CHROME:-}" ] && [ -x "${WEB_ACCESS_CHROME}" ]; then
    printf '%s' "${WEB_ACCESS_CHROME}"; return 0
  fi
  local c
  # 1) 私有副本（首选，身份独立）
  for c in \
    "$BROWSER_APPS_DIR/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing" \
    "$BROWSER_APPS_DIR/Chromium.app/Contents/MacOS/Chromium"; do
    [ -x "$c" ] && { printf '%s' "$c"; return 0; }
  done
  # 2) 系统上其它 Chromium 系（bundle id 不同，不会抢日常 Chrome 的路由）
  for c in \
    "/Applications/Chromium.app/Contents/MacOS/Chromium" \
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"; do
    [ -x "$c" ] && { printf '%s' "$c"; return 0; }
  done
  for c in chromium chromium-browser microsoft-edge; do
    if command -v "$c" >/dev/null 2>&1; then command -v "$c"; return 0; fi
  done
  return 1
}

instance_pids() { pgrep -f -- "user-data-dir=$PROFILE" 2>/dev/null; }
is_running()   { [ -n "$(instance_pids)" ]; }

# 找「源 Chrome」：用于解密日常 Chrome 的快照。
# 只有它持有 "Chrome Safe Storage" 密钥 —— 专用浏览器（Chrome for Testing）
# 用的是 "Chromium Safe Storage"，解不开源快照里的 Cookie。
find_source_chrome() {
  local c
  for c in \
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    "/Applications/Chromium.app/Contents/MacOS/Chromium"; do
    [ -x "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}

# 日常 Chrome 是否在运行。
# 注意：不能用 pgrep -f "Google Chrome.app/..." 判断 —— 专用实例是同一个
# 二进制启动的，会被一并命中，导致 sync-login 永远误报"请先退出日常 Chrome"。
# 判据：Chrome 主进程（无 --type=）且未指定任何 --user-data-dir（默认启动特征）。
daily_chrome_running() {
  local pid args
  for pid in $(pgrep -f "Google Chrome.app/Contents/MacOS/Google Chrome" 2>/dev/null); do
    args=$(ps -o command= -p "$pid" 2>/dev/null) || continue
    case "$args" in
      *--type=*)              continue ;;   # 渲染/GPU 等子进程
      *user-data-dir=*)       continue ;;   # 任何自定义 profile（含本 skill 专用实例）
    esac
    return 0
  done
  return 1
}
cdp_port()     { [ -f "$PORTFILE" ] && head -1 "$PORTFILE" 2>/dev/null; }
cdp_ready() {
  local p; p=$(cdp_port)
  [ -n "$p" ] && curl -sf "http://127.0.0.1:$p/json/version" >/dev/null 2>&1
}

# ---------- 命令 ----------

cmd_start() {
  if cdp_ready; then
    echo "browser: 专用实例已在线（端口 $(cdp_port)）"
    return 0
  fi
  local bin
  bin=$(find_chrome) || {
    print -u2 "✗ 找不到可用的专用浏览器。"
    print -u2 "  运行 '$0 install-browser' 从 Playwright 缓存复制 Chrome for Testing。"
    return 1
  }

  mkdir -p "$PROFILE" "$LOGDIR"
  rm -f "$PORTFILE"
  echo "browser: 启动专用实例…（profile: $PROFILE）"

  nohup "$bin" \
    --remote-debugging-port=0 \
    --remote-allow-origins='*' \
    --user-data-dir="$PROFILE" \
    --no-first-run \
    --no-default-browser-check \
    --no-startup-window \
    >> "$LOG" 2>&1 &
  disown 2>/dev/null || true

  local i
  for i in {1..60}; do
    if cdp_ready; then
      echo "browser: ready（端口 $(cdp_port)）"
      return 0
    fi
    sleep 0.5
  done
  print -u2 "✗ 启动超时。日志：$LOG"
  return 1
}

cmd_stop() {
  if ! is_running; then
    echo "browser: 专用实例未在运行"
    return 0
  fi
  pkill -f -- "user-data-dir=$PROFILE" 2>/dev/null
  local i
  for i in {1..20}; do is_running || break; sleep 0.5; done
  rm -f "$PORTFILE"
  echo "browser: 专用实例已关闭"
}

cmd_status() {
  local p; p=$(cdp_port)
  if cdp_ready; then
    echo "✓ 专用实例在线（端口 $p）"
    curl -s "http://127.0.0.1:$p/json/version" | sed -n '2p'
    local pages
    pages=$(curl -s "http://127.0.0.1:$p/json" \
      | python3 -c 'import sys,json;print(sum(1 for t in json.load(sys.stdin) if t.get("type")=="page"))' 2>/dev/null || echo "?")
    echo "  标签页数: $pages"
  else
    echo "✗ 专用实例未运行"
  fi
  echo "  profile : $PROFILE"
  local b
  b=$(find_chrome 2>/dev/null)
  if [ -n "$b" ]; then
    echo "  浏览器  : ${b//$HOME/~}"
  else
    echo "  浏览器  : ✗ 未找到（跑 install-browser 安装）"
  fi
  if is_running; then echo "  进程    : 存活"; else echo "  进程    : 无"; fi
}

cmd_port() {
  if cdp_ready; then cdp_port; else print -u2 "实例未运行"; return 1; fi
}

# 打开可见窗口：向已在运行的实例发一个"新窗口"请求（同 profile 会转发给现有实例）
cmd_open() {
  cmd_start >/dev/null || return 1
  local bin
  bin=$(find_chrome) || return 1
  "$bin" --user-data-dir="$PROFILE" >/dev/null 2>&1 &
  echo "browser: 已请求打开窗口（用于登录 / 人工操作）"
}

# 安装专用浏览器：从本机 Playwright 缓存复制 Chrome for Testing。
# 用 APFS 写时复制（cp -c），瞬间完成且不额外占用磁盘。
# 为什么要有这一步：专用实例必须用应用身份独立的浏览器（见 find_chrome 上方说明），
# 而 Chrome for Testing 是 Google 官方为自动化发布的构建，正好满足。
cmd_install_browser() {
  local dst="$BROWSER_APPS_DIR/Google Chrome for Testing.app"
  if [ -x "$dst/Contents/MacOS/Google Chrome for Testing" ]; then
    echo "✓ 专用浏览器已就位：$dst"
    return 0
  fi
  mkdir -p "$BROWSER_APPS_DIR"
  local src
  src=$(find "$HOME/Library/Caches/ms-playwright" -maxdepth 4 \
        -name "Google Chrome for Testing.app" -type d 2>/dev/null | sort -r | head -1)
  if [ -z "$src" ]; then
    print -u2 "✗ 本机 Playwright 缓存中没有 Chrome for Testing。"
    print -u2 "  可用以下任一方式获取后重跑本命令："
    print -u2 "    npx playwright install chromium"
    print -u2 "    npx @puppeteer/browsers install chrome@stable"
    return 1
  fi
  echo "browser: 从 $src 复制（APFS 写时复制）…"
  cp -Rc "$src" "$BROWSER_APPS_DIR/" || { print -u2 "✗ 复制失败"; return 1; }
  if [ -x "$dst/Contents/MacOS/Google Chrome for Testing" ]; then
    echo "✓ 已安装：$dst"
    echo "  bundle id: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$dst/Contents/Info.plist" 2>/dev/null)"
  else
    print -u2 "✗ 复制后不可执行"; return 1
  fi
}

# 从日常 Chrome 导入登录态（只读源、不改源）
#
# 为什么不直接复制 Cookies 文件：
#   专用浏览器（Chrome for Testing）与日常 Chrome 用的 Keychain 条目不同
#   （"Chromium Safe Storage" vs "Chrome Safe Storage"），复制过去的加密
#   Cookie 解不开 —— Chrome 甚至会把它当损坏数据清掉，表现为登录态直接丢失。
#   所以这里走 **CDP 明文搬运**：先用「源 Chrome + 快照」起一个临时实例拿到明文，
#   再让专用浏览器以自己的密钥写回。全程不读取、不修改任何 Keychain 条目。
cmd_sync_login() {
  local SRC
  case "$(uname -s)" in
    Darwin) SRC="$HOME/Library/Application Support/Google/Chrome" ;;
    Linux)  SRC="$HOME/.config/google-chrome" ;;
    *)      SRC="$HOME/Library/Application Support/Google/Chrome" ;;
  esac

  [ -d "$SRC" ] || { print -u2 "✗ 找不到日常 Chrome 的 profile：$SRC"; return 1; }

  # 源 Chrome 运行中也能同步：Cookies 是 SQLite 库，允许并发读，
  # 复制一份快照（含 WAL）即可，用户无需关闭浏览器。
  # 运行中复制理论上可能拿到不一致的快照，但实测稳定 —— 334 条库中导出
  # 210 条有效 cookie，x.com / 公众号 / GitHub 等登录态均可用。
  # 关掉 Chrome 后再跑会更完整，但不是必须。
  if daily_chrome_running; then
    echo "browser: 日常 Chrome 正在运行 —— 复制其快照（无需关闭）"
  fi

  local src_chrome node_bin script_dir
  src_chrome=$(find_source_chrome) || {
    print -u2 "✗ 找不到可用于解密的 Chrome —— 快照的 Cookie 由它加密，只能由它解密"
    return 1
  }
  node_bin=$(command -v node) || { print -u2 "✗ 需要 Node.js（用于 CDP 搬运 Cookie）"; return 1; }
  script_dir="${0:A:h}"

  # 覆盖前先停掉专用实例，避免写入正在使用的文件
  is_running && { echo "browser: 先关闭专用实例…"; cmd_stop >/dev/null; }

  # 清掉旧的 Cookie，避免 Chrome 加密的旧条目与新的混杂
  rm -f "$PROFILE/Default/Cookies" "$PROFILE/Default/Cookies-journal"
  rm -f "$PROFILE/Default/Network/Cookies" "$PROFILE/Default/Network/Cookies-journal"

  mkdir -p "$PROFILE"
  local copied=0 f rel
  # Cookie 在新版 Chrome 位于 Default/Network/，旧版在 Default/ 下，两者都试。
  # -wal 一并复制，否则可能丢掉最近的写入。
  for rel in \
    "Local State" \
    "Default/Preferences" \
    "Default/Network/Cookies" \
    "Default/Network/Cookies-wal" \
    "Default/Cookies" \
    "Default/Cookies-wal"; do
    f="$SRC/$rel"
    if [ -f "$f" ]; then
      mkdir -p "$PROFILE/$(dirname "$rel")"
      cp -f "$f" "$PROFILE/$rel" && echo "  ✓ $rel"
    fi
  done
  # 只要拿到了 Cookies 就算成功（-wal 可能不存在）
  if [ -f "$PROFILE/Default/Cookies" ] || [ -f "$PROFILE/Default/Network/Cookies" ]; then
    copied=1
  fi
  if [ "$copied" -eq 0 ]; then
    print -u2 "⚠ 没找到 Cookies 文件 —— 源可能不是 Chrome 默认 profile"
    return 1
  fi

  # ---- 第一步：源 Chrome + 快照，导出明文 ----
  echo "browser: 启动解密实例（源 Chrome + 快照，无窗口）…"
  rm -f "$PORTFILE"
  nohup "$src_chrome" --remote-debugging-port=0 --remote-allow-origins='*' \
    --user-data-dir="$PROFILE" --no-first-run --no-default-browser-check \
    --no-startup-window >> "$LOG" 2>&1 &
  disown 2>/dev/null || true

  local i
  for i in {1..60}; do cdp_ready && break; sleep 0.5; done
  if ! cdp_ready; then
    print -u2 "✗ 解密实例未就绪（日志：$LOG）"
    cmd_stop >/dev/null
    return 1
  fi

  echo "browser: 导出明文 cookie…"
  if ! "$node_bin" "$script_dir/cookie-transfer.mjs" export "$(cdp_port)" "$LOGDIR/cookies.json"; then
    print -u2 "✗ 导出失败"
    cmd_stop >/dev/null
    return 1
  fi

  echo "browser: 关闭解密实例…"
  cmd_stop >/dev/null

  # ---- 第二步：专用浏览器，写入明文 ----
  echo "browser: 启动专用实例并写回…"
  cmd_start >/dev/null || return 1
  if ! "$node_bin" "$script_dir/cookie-transfer.mjs" import "$(cdp_port)" "$LOGDIR/cookies.json"; then
    print -u2 "✗ 写入失败"
    return 1
  fi

  rm -f "$LOGDIR/cookies.json"
  echo "browser: 登录态已同步。"
  echo "  注意：这是快照，与日常 Chrome 之间不会自动同步。"
}

case "${1:-start}" in
  start)      cmd_start ;;
  stop)       cmd_stop ;;
  status)     cmd_status ;;
  port)       cmd_port ;;
  open)       cmd_open ;;
  sync-login) cmd_sync_login ;;
  install-browser) cmd_install_browser ;;
  restart)    cmd_stop && cmd_start ;;
  *)
    print -u2 "用法: browser-launch.sh [start|stop|status|port|open|sync-login|install-browser|restart]"
    exit 1
    ;;
esac

<div align="right">
  <details>
    <summary>🌐 Language</summary>
    <div>
      <div align="center">
        <a href="https://openaitx.github.io/view.html?user=eze-is&project=web-access&lang=en">English</a>
        | <a href="https://openaitx.github.io/view.html?user=eze-is&project=web-access&lang=zh-CN">简体中文</a>
        | <a href="https://openaitx.github.io/view.html?user=eze-is&project=web-access&lang=zh-TW">繁體中文</a>
        | <a href="https://openaitx.github.io/view.html?user=eze-is&project=web-access&lang=ja">日本語</a>
        | <a href="https://openaitx.github.io/view.html?user=eze-is&project=web-access&lang=ko">한국어</a>
        | <a href="https://openaitx.github.io/view.html?user=eze-is&project=web-access&lang=fr">Français</a>
        | <a href="https://openaitx.github.io/view.html?user=eze-is&project=web-access&lang=de">Deutsch</a>
        | <a href="https://openaitx.github.io/view.html?user=eze-is&project=web-access&lang=es">Español</a>
        | <a href="https://openaitx.github.io/view.html?user=eze-is&project=web-access&lang=pt">Português</a>
        | <a href="https://openaitx.github.io/view.html?user=eze-is&project=web-access&lang=ru">Русский</a>
      </div>
    </div>
  </details>
</div>

<img width="879" height="376" alt="image" src="https://github.com/user-attachments/assets/a87fd816-a0b5-4264-b01c-9466eae90723" />

<p align="center">
  <b>给 AI Agent 装上完整联网能力的 Skill。</b><br/>
  <a href="https://web-access.eze.is">🌐 官网</a> · <a href="https://mp.weixin.qq.com/s/rps5YVB6TchT9npAaIWKCw">📖 设计详解</a> · <a href="#安装">⚡ 快速安装</a>
</p>

AI Agent 原本的联网能力（WebSearch、WebFetch）缺少调度策略和浏览器自动化能力。这个 Agent Skill 补上的是：**联网策略 + CDP 浏览器操作 + 站点经验积累**。兼容所有支持 SKILL.md 的 Agent（Claude Code、Cursor、Gemini CLI、Codex CLI 等）。

> 推荐必读：[Web Access：一个 Skill，拉满 Agent 联网和浏览器能力](https://mp.weixin.qq.com/s/rps5YVB6TchT9npAaIWKCw) ，完整介绍了 Web-Access Skill 的开发细节与 Agent Skill 设计哲学，帮助你也能写出类似通用、高上限的 Skill

---

## v2.5.4 能力

| 能力 | 说明 |
|------|------|
| 联网工具自动选择 | WebSearch / WebFetch / curl / Jina / CDP，按场景自主判断，可任意组合 |
| CDP Proxy 浏览器操作 | 连接 skill 自管的专用浏览器实例（Chrome for Testing，独立 profile，与日常浏览器完全隔离），支持动态页面、交互操作、视频截帧 |
| 三种点击方式 | `/click`（JS click）、`/clickAt`（CDP 真实鼠标事件）、`/setFiles`（文件上传） |
| 本地浏览器书签/历史检索 | `find-url.mjs` 跨 Chrome / Edge 查询公网搜不到的目标（内部系统）或用户访问过的页面，支持关键词/时间窗/访问频度排序 |
| 并行分治 | 多目标时分发子 Agent 并行执行，共享一个 Proxy，tab 级隔离 |
| 站点经验积累 | 按域名存储操作经验（URL 模式、平台特征、已知陷阱），跨 session 复用 |
| 媒体提取 | 从 DOM 直取图片/视频 URL，或对视频任意时间点截帧分析 |

**v2.5.4 更新：**
- **修复新标签页空白竞态** — `/new` 先创建 `about:blank` 并完成 CDP attach，再显式导航；不再把浏览器初始空白文档误判为目标页面
- **目标内容就绪契约** — 导航成功或 `readyState` 完成不等于任务完成；遇到验证页、登录跳转和异步渲染时继续观察，直到目标内容出现或确认受阻
- **完整 URL 安全传输** — `/new` 和 `/navigate` 从 v2.5.3 起使用 POST body 传 URL，查询参数中的 `&` 不再被错误切分

<details><summary>v2.5.2 更新</summary>

- **Microsoft Edge 支持** — CDP Proxy 不再绑定 Chrome，新增 Edge 适配（及 Chromium、Chrome Canary 等 Chromium 系，通过同一套自动发现机制接入）。在 `edge://inspect/#remote-debugging` 勾选 "Allow remote debugging for this browser instance" 即可
- **浏览器偏好持久化** — 新增 `config.env`（gitignored，首次运行从模板创建），通过 `WEB_ACCESS_BROWSER` 固定默认浏览器；多浏览器同时开启 toggle 时 Agent 会询问偏好。也支持单次覆盖 `--browser <chrome|edge>`
- **不擅自降级** — 偏好/指定的浏览器没启动或没开 toggle 时硬错并给出明确处理步骤，不会悄悄连到别的浏览器；proxy 首次成功连接后 pin 住浏览器 id，避免运行中漂移
- **find-url 也支持 Edge** — 本地书签/历史检索默认遍历 Chrome 与 Edge，可用 `--browser <chrome|edge>` 限定单一浏览器
</details>

<details><summary>v2.5.0 更新</summary>

- **本地 Chrome 资源检索** — 新增 `scripts/find-url.mjs`，从本地 Chrome 书签/历史按关键词/时间窗/访问频度定位 URL。典型场景：用户提到组织内部系统（"我们的 XX 平台"等公网搜不到的目标）、回查之前访问过但不记得地址的页面、查看最近高频访问网站等（场景感谢 @MVPGFC 在 #60 提出）
</details>

<details><summary>v2.4.3 更新</summary>

- **修复 CLAUDE_SKILL_DIR 路径问题** — bash 代码块改用 `${CLAUDE_SKILL_DIR}` 字符串替换语法，修复 Windows Git Bash 路径转换错误和变量未设置问题（#47 #46）
- **站点经验列表合并到前置检查** — 启动检查通过后自动输出已有站点经验列表，移除不可靠的 `!` 内联注入
</details>

<details><summary>v2.4.1 更新</summary>

- **跨平台支持** — 脚本从 bash 迁移到 Node.js，Windows / Linux / macOS 均可使用
- **DOM 边界穿透** — 新增技术事实：eval 递归遍历可穿透 Shadow DOM、iframe 等选择器不可跨越的边界
</details>

<details><summary>v2.4 更新</summary>

- **站点内 URL 可靠性** — 新增事实说明：站点生成的链接自带完整上下文，手动构造的 URL 可能缺失隐式必要参数
- **平台错误提示不可信** — 新增技术事实：平台返回的"内容不存在"等提示可能是访问方式问题而非内容本身问题
- **小红书站点经验增强** — xsec_token 机制、创作者平台状态校验、暂存草稿流程
</details>

<details><summary>v2.3 更新</summary>

- **浏览哲学重构** — 更清晰的「像人一样思考」框架，强调目标驱动而非步骤驱动
- **Jina 积极推荐** — 明确鼓励在合适场景主动使用 Jina 节省 token
- **子 Agent prompt 指引优化** — 明确加载写法，增加避免动词暗示执行方式的说明
</details>

## 安装

**方式一：npx skills 一键安装（推荐）**

```bash
npx skills add eze-is/web-access
```

> [skills CLI](https://github.com/vercel-labs/skills) 是开源的 Agent Skill 包管理器，自动检测你的 Agent 环境并安装到正确位置。

**方式二：让 Agent 自动安装**

```
帮我安装这个 skill：https://github.com/eze-is/web-access
```

**方式三：Plugin 安装（Claude Code）**

```bash
claude plugin marketplace add https://github.com/eze-is/web-access
claude plugin install web-access@web-access --scope user
```

**方式四：手动**

```bash
git clone https://github.com/eze-is/web-access ~/.claude/skills/web-access
```

## 前置配置

CDP 模式需要 **Node.js 22+**。

浏览器侧有两条接入路径：

- **推荐：skill 自管的专用实例** —— 零弹窗、不改动日常浏览器、登录态可跨会话复用，装好即用。见下文「专用浏览器：无弹窗 CDP」。
- **备选：直连日常浏览器**（Chrome / Edge / Chromium 系）—— 需手动开启 toggle 开关，且**每个新 CDP 连接都要人工点「允许」**（approval 机制，官方无"记住"选项）：
  1. 在浏览器地址栏打开 inspect 页面：Chrome 用 `chrome://inspect/#remote-debugging`，Edge 用 `edge://inspect/#remote-debugging`
  2. 勾选 **Allow remote debugging for this browser instance**（可能需要重启浏览器）

### 浏览器偏好（config.env）

skill 长期偏好保存在 `${CLAUDE_SKILL_DIR}/config.env`（首次运行自动从 `config.env.template` 创建，gitignored）：

```bash
# 留空 = 每次启动都询问偏好；设值 = 固定使用该浏览器
WEB_ACCESS_BROWSER=edge
```

合法值：`chrome` / `chrome-canary` / `chromium` / `edge` / `web-access`

其中 `web-access` 指本 skill 自管的专用实例（独立 profile，与日常浏览器完全隔离），由 `scripts/browser-launch.sh` 按需启动 —— 这也是推荐值。

**临时用别的浏览器**（不修改 config.env）：

```bash
node "${CLAUDE_SKILL_DIR}/scripts/check-deps.mjs" --browser chrome
```

**切换浏览器**（proxy 已连接旧的）：

```bash
pkill -f cdp-proxy.mjs && node "${CLAUDE_SKILL_DIR}/scripts/check-deps.mjs"
```

环境检查（Agent 运行时会自动完成前置检查，无需手动执行）：

```bash
node "${CLAUDE_SKILL_DIR}/scripts/check-deps.mjs"
# $CLAUDE_SKILL_DIR 是 skill 加载时自动设置的环境变量
# 手动运行请替换为实际路径，如 ~/.claude/skills/web-access
```

## 专用浏览器：无弹窗 CDP

### 为什么需要它

想用 CDP 操作浏览器，常见的两条路都有坑：

| 路径 | 问题 |
|------|------|
| 给日常 Chrome 加 `--remote-debugging-port` | Chrome 136+ 起，**指向默认 profile 的调试端口会被静默忽略**（`chrome_paths.cc` 中是路径相等比较，显式传默认路径同样被拒），且不报错、不弹窗，只在 stderr 留一行 |
| `chrome://inspect` 的 toggle 开关 | 走 **approval 机制** —— 每个新 CDP 连接都要人工点「允许」，官方不提供"记住" |

前者的唯一解法是改动日常浏览器的数据目录 / 启动方式 / 生命周期（已被否决，代价全压在用户身上）；后者无法做到无人值守。

⇒ 本 skill 改为**自管一个专用浏览器实例**：独立 profile、按需启停、与日常浏览器完全隔离。用户的浏览器想开就开、想关就关，不受任何影响。

> **⚠️ 专用实例必须使用「应用身份独立」的浏览器**（默认 `Google Chrome for Testing`，bundle id `com.google.chrome.for.testing`）。
> **绝不能直接跑 `/Applications/Google Chrome.app`** —— 它与日常 Chrome 是同一个应用（bundle id 均为 `com.google.Chrome`），macOS LaunchServices 会把点 Dock 图标 / `open -a "Google Chrome"` 全部路由到这个无窗口实例上，用户看到的现象是「Chrome 开不了、也关不掉」。`--headless` 模式同样会被抢占，只有应用身份独立才能避免。

完整机制、踩坑记录与回滚档案见 [`references/cdp-persistent.md`](./references/cdp-persistent.md)。

### 脚本一览

| 脚本 | 职责 |
|------|------|
| `scripts/browser-launch.sh` | 专用实例的生命周期管理（安装 / 启停 / 状态 / 端口 / 开窗 / 同步登录态） |
| `scripts/cookie-transfer.mjs` | 在两个 CDP 实例间搬运 Cookie（`export` / `import`，走明文，绕开 Keychain 密钥差异） |
| `scripts/activate-tab.mjs` | 把标签页切到前台（`Target.activateTarget`），解决后台标签页不加载懒内容的问题 |

### browser-launch.sh

**只操作自己创建的实例，绝不触碰日常浏览器。**

```bash
${CLAUDE_SKILL_DIR}/scripts/browser-launch.sh install-browser   # 安装专用浏览器（Chrome for Testing）
${CLAUDE_SKILL_DIR}/scripts/browser-launch.sh start             # 启动（静默，无窗口）
${CLAUDE_SKILL_DIR}/scripts/browser-launch.sh stop              # 关闭实例
${CLAUDE_SKILL_DIR}/scripts/browser-launch.sh restart           # 重启
${CLAUDE_SKILL_DIR}/scripts/browser-launch.sh status            # 查看状态
${CLAUDE_SKILL_DIR}/scripts/browser-launch.sh port              # 输出 CDP 端口
${CLAUDE_SKILL_DIR}/scripts/browser-launch.sh open              # 打开可见窗口（人工登录 / 查看）
${CLAUDE_SKILL_DIR}/scripts/browser-launch.sh sync-login        # 从日常 Chrome 导入登录态
```

| 子命令 | 说明 |
|--------|------|
| `install-browser` | 从本机 Playwright 缓存（`~/Library/Caches/ms-playwright`）复制 `Google Chrome for Testing.app` 到 `~/.web-access/browser/`。用 APFS 写时复制（`cp -Rc`），瞬间完成且**不额外占磁盘**。缓存里没有时会提示先用 `npx playwright install chromium` 获取 |
| `start` | 以 `--remote-debugging-port=0 --no-startup-window --remote-allow-origins=*` 启动，无窗口、无弹窗；等待至 CDP 就绪（最长 30 秒）。端口由 Chrome 自选，写入 `<profile>/DevToolsActivePort`。已在线时直接返回，不重复启动 |
| `stop` | 关闭专用实例。按 `--user-data-dir` 精确匹配，**不会误杀日常 Chrome** |
| `restart` | 等价于 `stop && start` |
| `status` | 打印在线状态、CDP 端口、浏览器版本、标签页数、profile 路径、浏览器路径、进程存活情况 |
| `port` | 只输出端口号，便于外部工具取值：`PORT=$(${CLAUDE_SKILL_DIR}/scripts/browser-launch.sh port)` |
| `open` | 打开可见窗口，用于人工登录或查看。向已运行的实例发新窗口请求，不会另起进程 |
| `sync-login` | 从日常 Chrome 导入 Cookie，详见下节 |

**可覆盖的环境变量**：

| 变量 | 默认值 | 作用 |
|------|--------|------|
| `WEB_ACCESS_PROFILE` | `~/.web-access/browser-profile` | 专用 profile 路径 |
| `WEB_ACCESS_CHROME` | 空 | 显式指定专用浏览器可执行文件（跳过自动探测） |

专用浏览器的自动探测顺序：`WEB_ACCESS_CHROME` → `~/.web-access/browser/` 下的私有副本 → 系统 Chromium / Edge（bundle id 不同，安全）。**刻意不包含 `/Applications/Google Chrome.app`。**

### 首次使用（4 步）

```bash
S="${CLAUDE_SKILL_DIR}/scripts/browser-launch.sh"

$S install-browser    # 1. 安装专用浏览器（只需一次）
$S sync-login         # 2. 从日常 Chrome 导入登录态（无需关闭 Chrome）
$S start              # 3. 启动实例（check-deps.mjs 也会自动拉起）
$S status             # 4. 确认就绪
```

之后 `check-deps.mjs` 检测到实例未运行会**自动拉起**，日常使用无需手动 `start`；也没有 launchd 常驻或开机自启项。

### 登录态同步（sync-login）

专用浏览器与日常 Chrome 使用的 Keychain 条目不同（`Chromium Safe Storage` vs `Chrome Safe Storage`），**直接复制加密的 Cookies 文件解不开** —— Chrome 会把解不开的记录当损坏数据清理掉，表现为"同步完登录态反而没了"。

所以 `sync-login` 走 **CDP 明文搬运**，全程不读取、不修改任何 Keychain 条目：

```
1. 复制日常 Chrome 的 Cookies(含 -wal) + Local State 到专用 profile
   ← 运行中的 Chrome 也能复制：Cookies 是 SQLite 库，允许并发读，无需关闭浏览器
2. 用「源 Chrome 二进制 + 该快照」起临时实例（它持有 Chrome Safe Storage，能解密）
3. CDP Storage.getCookies → 明文 JSON
4. 关掉临时实例
5. 用 Chrome for Testing 起正式实例
6. CDP Storage.clearCookies + Storage.setCookies → 由 CFT 用自己的密钥写回
```

实测（Chrome 全程运行未重启，PID 不变）：导出 308 条 cookie / 55 个域名，写入 308/308，x.com、微信公众号、GitHub 等登录态均可用。**注意 `-wal` 必须一并复制**，否则会丢掉最近的写入（实测少复制 -wal 时只有 210 条 / 47 域名）。

> **这是快照，不会与日常 Chrome 自动同步。** Cookie 过期或某站点登录态失效时，重跑一次即可。
> 明文中间产物 `cookies.json` 写在 `~/.web-access/`（不在 `/tmp`），脚本用完即删。

### cookie-transfer.mjs

通用的 CDP Cookie 搬运工具。`sync-login` 内部调用它，也可以单独使用：

```bash
node "${CLAUDE_SKILL_DIR}/scripts/cookie-transfer.mjs" export <port> <out.json>   # 导出明文 cookie
node "${CLAUDE_SKILL_DIR}/scripts/cookie-transfer.mjs" import <port> <in.json>   # 写回明文 cookie
```

- `export` 调 `Storage.getCookies`，导出全部 cookie 到 JSON（含 domain / path / expires / httpOnly / secure / sameSite），并打印条数与域名数
- `import` 先 `Storage.clearCookies` 清空目标实例已有 cookie（避免新旧混杂），再按 50 条一批 `Storage.setCookies` 写入
- 整批失败时**自动逐条重试**，定位个别不兼容的 cookie（如 `__Host-` 前缀约束）；失败的会列出前 8 条但不中断
- 退出码：有任意一条写入成功即为 0

### activate-tab.mjs

**把指定标签页切到前台。**

```bash
node "${CLAUDE_SKILL_DIR}/scripts/activate-tab.mjs" <targetId>          # 端口自动发现
node "${CLAUDE_SKILL_DIR}/scripts/activate-tab.mjs" <targetId> 9222     # 显式指定端口
WEB_ACCESS_PORT=9222 node "${CLAUDE_SKILL_DIR}/scripts/activate-tab.mjs" <targetId>
```

**为什么需要它**：专用实例的标签页 `document.visibilityState` **默认是 `hidden`**，即使实例里只有这一个标签页。不少站点的长列表 / 时间线**只在页面前台可见时才加载下一页** —— 标签页处于后台时滚动完全不触发新请求，表现为 `scrollHeight` 卡死、`scrollY` 顶到上限不动，极易被误判成「站点限制了访问」。已知受影响：X 的首页时间线与关注 / 粉丝列表。

它的做法是直连 browser 级 WebSocket 发 `Target.activateTarget`（**Proxy 未暴露 `/activate` 端点**），成功后 `visibilityState` 立刻变 `visible`、`hasFocus` 变 `true`。依赖 Node.js 22+ 自带的 WebSocket，无第三方依赖。

端口发现顺序：显式参数 → `WEB_ACCESS_PORT` 环境变量 → `<profile>/DevToolsActivePort` 引导文件 → 兜底 `9222`。

> 滚动采集长列表时，建议在每轮循环复查 `document.visibilityState`，一旦回到 `hidden` 就重新激活。

### 排查

| 现象 | 原因与处理 |
|------|-----------|
| 「Chrome 开不了、也关不掉」 | 专用实例误用了 `/Applications/Google Chrome.app`（bundle id 与日常 Chrome 撞车）。跑 `install-browser` 换成 Chrome for Testing，再 `restart` |
| `start` 报「找不到可用的专用浏览器」 | 先 `install-browser`；本机 Playwright 缓存为空时用 `npx playwright install chromium` 获取 |
| 登录态丢失 | 跑一次 `sync-login`。**不要**试图直接复制 Cookies 文件（见上文 Keychain 说明） |
| 滚动加载不动 | 用 `activate-tab.mjs` 把标签页切到前台 |
| `status` 显示离线但进程还在 | 引导文件被残留进程占着，`stop` 后重新 `start` |
| 外部工具要连专用实例 | 用 `browser-launch.sh port` 取端口（实例端口是 Chrome 自选的，不能硬编码 9222） |

### 与直连日常浏览器方式的取舍

直连日常浏览器（Chrome / Edge / Chromium 系）的方式仍然支持，只需把 `config.env` 的 `WEB_ACCESS_BROWSER` 设为 `chrome` / `edge`，并按上文「前置配置」开启 toggle 开关。代价是**每次新建 CDP 连接都要人工点「允许」**，无法无人值守。

本 skill 默认使用专用实例（`WEB_ACCESS_BROWSER=web-access`），因为它同时做到：零弹窗、不改动日常浏览器、登录态可跨会话复用。

## CDP Proxy API

Proxy 通过 WebSocket 直连浏览器 —— 既支持 skill 专用实例（`--remote-debugging-port`，零弹窗，推荐），也兼容 `chrome://inspect` / `edge://inspect` 的 toggle 模式（需人工授权）。连接目标由 `config.env` 的 `WEB_ACCESS_BROWSER` 决定。提供 HTTP API：

```bash
# 启动（Agent 会自动管理 Proxy 生命周期，无需手动启动）
node "${CLAUDE_SKILL_DIR}/scripts/cdp-proxy.mjs" &

# 页面操作
curl -s -X POST --data-raw 'https://example.com' http://localhost:3456/new  # 新建 tab（v2.5.3 起 URL 走 POST body）
curl -s -X POST "http://localhost:3456/eval?target=ID" -d 'document.title'  # 执行 JS
curl -s -X POST "http://localhost:3456/click?target=ID" -d 'button.submit'  # JS 点击
curl -s -X POST "http://localhost:3456/clickAt?target=ID" -d '.upload-btn'  # 真实鼠标点击
curl -s -X POST "http://localhost:3456/setFiles?target=ID" \
  -d '{"selector":"input[type=file]","files":["/path/to/file.png"]}'        # 文件上传
curl -s "http://localhost:3456/screenshot?target=ID&file=/tmp/shot.png"     # 截图
curl -s "http://localhost:3456/scroll?target=ID&direction=bottom"           # 滚动
curl -s "http://localhost:3456/close?target=ID"                             # 关闭 tab
curl -s "http://localhost:3456/health"                                      # 查看状态（含 managedTabs 数量）
```

Proxy 会自动追踪通过 `/new` 创建的 tab，闲置 15 分钟后自动关闭，防止 Agent 异常退出时留下孤儿 tab。可通过环境变量 `CDP_TAB_IDLE_TIMEOUT`（单位毫秒）调整超时时间。

## ⚠️ 使用前提醒

通过浏览器自动化操作社交平台（如小红书）存在账号被平台限流或封禁的风险。**强烈建议使用小号进行操作。**

## 使用

安装后直接让 Agent 执行联网任务，skill 自动接管：

- "帮我搜索 xxx 最新进展"
- "读一下这个页面：[URL]"
- "去小红书搜索 xxx 的账号"
- "帮我在创作者平台发一篇图文"
- "同时调研这 5 个产品的官网，给我对比摘要"

## 设计哲学

> Skill = 哲学 + 技术事实，不是操作手册。讲清 tradeoff 让 AI 自己选，不替它推理。

详见 [SKILL.md](./SKILL.md) 中的浏览哲学部分。

## License

MIT · 作者：[一泽 Eze](https://github.com/eze-is) · [官网](https://web-access.eze.is)

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=eze-is/web-access&type=Date)](https://star-history.com/#eze-is/web-access&Date)

## Clawhub Download History

[![Download History](https://skill-history.com/chart/eze-is/web-access.svg)](https://skill-history.com/eze-is/web-access)

<img width="1280" height="306" alt="image" src="https://github.com/user-attachments/assets/2afa25c2-3730-413e-b40f-94e52567249d" />

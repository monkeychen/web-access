# Chrome CDP 接入：机制、约束与当前方案

修订：2026-09-12（当日三次修订：① 回滚 launchd 常驻 ② 改为 skill 自管专用实例 ③ 换用独立应用身份的浏览器 + Cookie 明文搬运）
适用：macOS（Chrome 153 日常 / Chrome for Testing 151 专用）

---

## 一、Chrome 的硬性机制（实测 + 源码，勿重复踩坑）

### 1. 默认 profile 一律拒绝调试端口

`chrome/common/chrome_paths.cc`：

```cpp
std::optional<bool> IsUsingDefaultDataDirectory() {
  ...
  return user_data_dir == default_user_data_dir;   // 路径相等比较
}
```

是**路径比较**，不是"有没有传 `--user-data-dir`"。显式传默认路径同样被拒，
且被拒时**不报错、不弹窗**，只在 stderr 留一行。

### 2. toggle 模式 = approval 模式（"每次弹窗"的根源）

`chrome://inspect/#remote-debugging` 的开关（对应 `Local State` 的
`devtools.remote_debugging.user-enabled`）勾选后，Chrome **普通启动**就会在
`127.0.0.1:9222` 监听；实测此模式下 `/json/version`、`/json/list` 均返回 **HTTP 404**，
即 HTTP 端点本身不可用。

它对应 `remote_debugging_server.cc` 的 `kWithApprovalOnly`：
**每个新 CDP 连接都要用户在原生对话框点「允许」**，官方无"记住"选项。

### 3. `DevToolsActivePort` 只在写 0 端口时生成

| 启动参数 | 写 `<profile>/DevToolsActivePort`？ |
|---|---|
| `--remote-debugging-port=0` | **写** |
| `--remote-debugging-port=9222` | **不写** |

格式两行：第一行端口、第二行 wsPath。这是 `browser-discovery.mjs` 的 `detectAll()` 的发现入口。

### 4. 同一 profile 单例锁

一个 profile 只能有一个 Chrome 实例。已有实例在跑时，新进程把命令行参数转交后自己退出
—— **新参数不会生效**。

### 5. ⚠️ 同一 bundle id 的两个实例会互相抢「打开」事件（本日踩到）

macOS 的 LaunchServices 按 **bundle identifier** 识别已运行的应用。
`/Applications/Google Chrome.app` 的 bundle id 是 `com.google.Chrome` ——
用它启动的专用实例与用户的日常 Chrome **是同一个应用**，于是：

- 点 Dock 图标 / `open -a "Google Chrome"` → 系统认为"Chrome 已在运行"，
  事件被交给那个 `--no-startup-window` 启动、不会开窗口的专用实例；
- 用户看到的现象是 **「Chrome 开不了、也关不掉」**（日常浏览器根本起不来）；
- `--headless=new` 也一样会被抢占 —— 只要 bundle id 相同就逃不掉。

**解法：专用实例必须用应用身份独立的浏览器。** 详见第四节。

### 6. 不同浏览器构建的 Keychain 密钥条目不同

macOS 上 Cookie 用 Keychain 里的密码派生的密钥加密（PBKDF2 + AES-128-CBC，`v10` 前缀）：

| 构建 | Keychain 条目 |
|---|---|
| Google Chrome | `Chrome Safe Storage` |
| Chrome for Testing / Chromium | `Chromium Safe Storage` |

后果：**直接把日常 Chrome 的 `Cookies` 文件复制给专用实例，Cookie 解不开**。
更糟的是 Chrome 会把解不开的记录当作损坏数据清理掉 —— 表现为"同步过去后登录态直接没了"
（实测：复制后启动一次，323 条记录被清成 0 条）。

解法见第五节（CDP 明文搬运），**不需要读取或修改任何 Keychain 条目**。

---

## 二、约束推论

"无弹窗的 CDP"要求实例同时满足：**非默认 `--user-data-dir`** + **`--remote-debugging-port`**。

日常 Chrome 是「默认 profile + 默认启动」，两者都不满足。而让它满足的唯一办法是
改动它的启动方式 / 数据目录 / 生命周期 —— **代价过高，已否决**。

⇒ 只能由 skill **自己维护一个独立实例**，且该实例必须用**应用身份独立**的浏览器。

---

## 三、已回滚方案（备查，勿重蹈）

**曾做法**：launchd 常驻 + profile 整体迁移到 `Chrome-CDP` + 默认路径建 symlink +
脚本补写引导文件。技术上通（已验证零弹窗、登录态完整）。

**否决原因**：代价全压在用户的浏览器上 ——

- Chrome 数据目录被搬走，默认路径被 symlink 劫持
- launchd `KeepAlive` 导致 Cmd+Q 后自动重启，**用户关不掉自己的浏览器**
- `Local State` 的开关被改写

回滚后相关脚本已废弃并本地归档，不随 skill 分发。

---

## 四、当前方案：skill 自管专用实例（独立应用身份）

### 浏览器选型：Chrome for Testing

| 项 | 值 |
|---|---|
| 来源 | 从本机 Playwright 缓存复制（`Google Chrome for Testing.app`） |
| 落地位置 | `~/.web-access/browser/Google Chrome for Testing.app` |
| bundle id | `com.google.chrome.for.testing`（**与日常 Chrome 无关**） |
| 复制方式 | `cp -Rc`（APFS 写时复制，体积约 350M 但**不额外占磁盘** —— 实测可用空间前后无变化） |
| 获取命令 | `browser-launch.sh install-browser` |

`find_chrome()` 的优先级：`WEB_ACCESS_CHROME` 环境变量 → 私有副本 →
系统 Chromium / Edge（bundle id 不同，安全）。**刻意不包含 `/Applications/Google Chrome.app`。**

### 组成

| 件 | 位置 | 职责 |
|---|---|---|
| 启动脚本 | `scripts/browser-launch.sh` | start / stop / status / port / open / sync-login / install-browser |
| Cookie 搬运 | `scripts/cookie-transfer.mjs` | CDP 导出/导入明文 cookie（`Storage.getCookies` / `Storage.setCookies`） |
| 激活标签页 | `scripts/activate-tab.mjs` | 发 `Target.activateTarget` 把 tab 切到前台（见第六节） |
| 专用 profile | `~/.web-access/browser-profile` | 与用户日常浏览器完全隔离 |
| 实例参数 | `--remote-debugging-port=0 --no-startup-window --remote-allow-origins=*` | 启动时不弹初始窗口（首个 tab 由 CDP 创建时正常开窗）；无授权弹窗；Chrome 自选端口并写引导文件 |
| 发现 | `browser-discovery.mjs` 的 `knownBrowsers()` 新增 `web-access` 项 | 读专用 profile 下的 `DevToolsActivePort` |
| 偏好 | `config.env` → `WEB_ACCESS_BROWSER=web-access` | 精确选中专用实例，不碰日常 Chrome |
| 按需启动 | `check-deps.mjs`：偏好为 `web-access` 且未检测到 → 自动拉起后重试 | 无常驻、无自启服务 |

### 数据流

```
check-deps.mjs
  └→ selectBrowser() 命中 web-access（config.env 偏好）
       └→ 未命中则 browser-launch.sh start 拉起实例（port=0，Chrome 写引导文件）
            └→ cdp-proxy 连接 ws://127.0.0.1:<随机端口>/devtools/browser/<uuid>   ← 零弹窗
```

### 端口为什么是随机的

`--remote-debugging-port=0` 是 Chrome 唯一会写 `DevToolsActivePort` 的模式，
本 skill 的发现路径就靠它。端口随机的代价仅在于"外部工具无法硬编码"——
需要时用 `scripts/browser-launch.sh port` 查询。

> 历史：中途曾改成固定 9222 + 脚本补写引导文件（为了让 `connectOverCDP('localhost:9222')`
> 这类硬编码工具能用）。但那个方案服务于"直连日常浏览器"，而当前架构下专用实例
> 本来就不是用户的浏览器，外部工具要连它应显式查端口，故回到 `port=0` 的简洁做法。

---

## 五、登录态同步（sync-login）：CDP 明文搬运

**为什么不能直接复制文件**：见第一节第 6 条 —— 密钥条目不同，Cookie 解不开，
还会被当损坏数据清掉。

**做法**（`browser-launch.sh sync-login`，全程不碰 Keychain）：

```
1. 复制日常 Chrome 的 Cookies(+wal) 与 Local State 到专用 profile
   ← 运行中的 Chrome 也能复制：Cookies 是 SQLite 库，允许并发读
2. 用「源 Chrome 二进制 + 该快照」起临时实例 ── 它持有 Chrome Safe Storage，能解密
3. CDP Storage.getCookies → 明文 JSON
4. 关掉临时实例
5. 用 Chrome for Testing 起正式实例
6. CDP Storage.clearCookies + Storage.setCookies → 由 CFT 用自己的密钥写回
```

**实测**（2026-09-12，日常 Chrome 全程运行中未重启，PID 不变）：

| 项 | 结果 |
|---|---|
| 导出 | 308 条 cookie / 55 个域名（首次未复制 -wal 时是 210 条 / 47 域名 —— **-wal 必须带上**） |
| 写入 | 308/308 |
| x.com | `a[data-testid=AppTabBar_Profile_Link]` 的 href 指向当前登录账号主页，时间线正常加载 |
| 微信公众号 | 直接进入 `/cgi-bin/home?t=home/index&token=...`（内容管理/草稿箱/数据分析） |

**注意**：`Storage.setCookies` 返回成功时，SQLite 文件可能尚未落盘
（`immutable=1` 直读文件会看到 0 条）。**验证要以 CDP 视角为准**。

**边界**：这是快照，与日常 Chrome 之间不自动同步；Cookie 过期后重跑一次即可。
`cookies.json` 是明文，脚本用完即删（在 `~/.web-access/` 下，不留在 /tmp）。

---

## 六、标签页可见性（采集长列表必读）

标签页在**不是窗口的活动标签页**时（或窗口被完全遮挡 / 最小化 / 在其他 Space），
`document.visibilityState` 会是 `hidden`。

**反直觉的一点**：`hidden` 与「用户能否看到窗口」**不是一回事** —— 窗口就在屏幕最前、
用户看得清清楚楚，只要切到另一个 tab，原 tab 立刻变 `hidden`。2026-09-12 实测：同一窗口内
用 `activate-tab.mjs` 切换活动 tab，旧 tab 变 `hidden:true` / `hasFocus:false`，
**窗口全程在前台未动**；关闭新 tab 后旧 tab 回到 `visible`。

后果：首屏能加载（约 5 条），但**滚动完全不触发新请求** —— `scrollHeight` 卡死、
`scrollY` 顶到上限不动，极易误判成"站点限制了访问"。

处理：`node scripts/activate-tab.mjs <targetId>`（端口自动发现），实测立刻变
`visible` / `hasFocus: true`。X 等站点的时间线与关注/粉丝列表都受影响。

> 可见性**只影响页面自身的懒加载策略**，不影响 CDP 的读写能力 —— `hidden` 状态下
> `/eval`、`/navigate`、`/screenshot` 全部照常工作（实测 `hidden` 时仍能读到页面文本）。

**`Target.activateTarget` 的实际行为**（比"切标签页"更多）：它**不模拟点击** —— 参数只有
`targetId`，无坐标、无鼠标事件、不经过输入管线。Chromium 内部走 `WebContents::Activate()`，
**会把窗口从最小化状态一并恢复**。实测：窗口 `minimized` 时发该命令，`windowState` 变
`normal`、`visibilityState` 变 `visible`；窗口最小化（标签栏根本点不到）时它照样生效。

---

## 七、落地状态与验证

| 项 | 状态 |
|---|---|
| 日常 Chrome | 默认 profile `~/Library/Application Support/Google/Chrome`，默认启动，可随时 Cmd+Q；toggle 开关保留（原值）；**始终未被我方方案改动** |
| 专用浏览器 | `~/.web-access/browser/Google Chrome for Testing.app`（bundle id `com.google.chrome.for.testing`） |
| 专用 profile | `~/.web-access/browser-profile`，`browser-launch.sh` 按需启停；无 launchd、无自启 |
| config.env | `WEB_ACCESS_BROWSER=web-access` |
| Keychain | **未做任何改动**（Chrome Safe Storage / Chromium Safe Storage 均保持原值） |
| 实测结果 | 专用实例运行时点 Dock 正常打开用户日常 Chrome（原有标签页完整保留）；proxy 零弹窗；`/new → /eval → /close` 通过；sync-login 无需关闭 Chrome 且登录态可用；滚动加载正常 |

---

## 附：相关源码 / 位置

- `chrome/common/chrome_paths.cc` — `IsUsingDefaultDataDirectory()` 的路径比较
- `chrome/browser/devtools/remote_debugging_server.cc` — 允许性判定、approval 模式、`kDefaultDevToolsPort`
- `components/os_crypt/sync/keychain_password_mac.mm` — Keychain 服务名的来源（编译期 branding 标志）

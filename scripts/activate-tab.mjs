#!/usr/bin/env node
// activate-tab.mjs — 把指定 tab 切到前台，让 document.visibilityState 变成 "visible"
//
// 为什么需要它：不少站点的长列表 / 时间线**只在页面前台可见时才加载下一页**。
// 标签页处于后台（visibilityState === "hidden"）时，滚动完全不触发新请求 ——
// docH 会卡死、scrollY 顶到上限不动，极易被误判成「站点限制了访问」。
// 已知受影响：x.com 的首页时间线、following / followers 长列表。
//
// proxy（cdp-proxy.mjs）没有暴露 /activate 端点，所以这里直连 browser 级 WebSocket
// 发 Target.activateTarget。
//
// 用法：
//   node activate-tab.mjs <targetId> [port]
//   node activate-tab.mjs <targetId>            # 端口自动发现
//   WEB_ACCESS_PORT=9222 node activate-tab.mjs <targetId>
//
// 退出码：0 成功 / 1 失败

import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const targetId = process.argv[2];
const argPort = process.argv[3] || process.env.WEB_ACCESS_PORT;

if (!targetId) {
  console.error("用法: node activate-tab.mjs <targetId> [port]");
  process.exit(1);
}
if (typeof WebSocket === "undefined") {
  console.error("需要 Node.js 22+（依赖原生 WebSocket）");
  process.exit(1);
}

// 端口发现：显式参数 > 专用实例引导文件 > 常见端口兜底
function resolvePort() {
  if (argPort) return Number(argPort);
  const candidates = [
    path.join(os.homedir(), ".web-access/browser-profile/DevToolsActivePort"),
  ];
  for (const f of candidates) {
    try {
      const line = fs.readFileSync(f, "utf8").split("\n")[0].trim();
      if (/^\d+$/.test(line)) return Number(line);
    } catch {}
  }
  return 9222;
}

const port = resolvePort();

async function main() {
  let wsUrl;
  try {
    const res = await fetch(`http://127.0.0.1:${port}/json/version`);
    wsUrl = (await res.json()).webSocketDebuggerUrl;
  } catch (e) {
    console.error(`✗ 无法连接 CDP 端口 ${port}：${e.message}`);
    process.exit(1);
  }
  if (!wsUrl) {
    console.error(`✗ 端口 ${port} 未返回 webSocketDebuggerUrl`);
    process.exit(1);
  }

  const ws = new WebSocket(wsUrl);
  const done = (code, msg) => {
    if (msg) (code === 0 ? console.log : console.error)(msg);
    try { ws.close(); } catch {}
    process.exit(code);
  };
  const timer = setTimeout(() => done(1, "✗ 激活超时"), 6000);

  ws.addEventListener("open", () => {
    ws.send(JSON.stringify({ id: 1, method: "Target.activateTarget", params: { targetId } }));
  });
  ws.addEventListener("message", (ev) => {
    let msg;
    try { msg = JSON.parse(ev.data); } catch { return; }
    if (msg.id !== 1) return;
    clearTimeout(timer);
    if (msg.error) done(1, `✗ 激活失败：${msg.error.message}`);
    else done(0, `✓ 已切到前台（target ${targetId}，端口 ${port}）`);
  });
  ws.addEventListener("error", () => {
    clearTimeout(timer);
    done(1, "✗ WebSocket 连接失败");
  });
}

main();

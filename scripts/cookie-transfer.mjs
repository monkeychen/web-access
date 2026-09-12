#!/usr/bin/env node
// cookie-transfer.mjs — 在两个 CDP 实例之间搬运 Cookie（经由明文）
//
// 为什么需要它：
//   不同浏览器构建使用的 Keychain 条目不同 ——
//     日常 Chrome         → "Chrome Safe Storage"
//     Chrome for Testing  → "Chromium Safe Storage"
//   所以直接复制加密的 Cookies 文件，换浏览器后解不开（表现为"登录态丢失"）。
//   走 CDP 取明文再写回去，就绕开了密钥差异，且**不需要读取/修改任何 Keychain 条目**。
//
// 用法：
//   node cookie-transfer.mjs export <port> <out.json>
//   node cookie-transfer.mjs import <port> <in.json>
//
// 退出码：0 成功 / 1 失败

import fs from "node:fs";

const [mode, portArg, fileArg] = process.argv.slice(2);
const port = Number(portArg);

if (!["export", "import"].includes(mode || "") || !Number.isFinite(port) || !fileArg) {
  console.error("用法: node cookie-transfer.mjs <export|import> <port> <file.json>");
  process.exit(1);
}
if (typeof WebSocket === "undefined") {
  console.error("需要 Node.js 22+（依赖原生 WebSocket）");
  process.exit(1);
}

async function connect(p) {
  let wsUrl;
  try {
    const res = await fetch(`http://127.0.0.1:${p}/json/version`);
    wsUrl = (await res.json()).webSocketDebuggerUrl;
  } catch (e) {
    throw new Error(`无法连接 CDP 端口 ${p}：${e.message}`);
  }
  if (!wsUrl) throw new Error(`端口 ${p} 未返回 webSocketDebuggerUrl`);

  const ws = new WebSocket(wsUrl);
  await new Promise((resolve, reject) => {
    ws.addEventListener("open", resolve, { once: true });
    ws.addEventListener("error", () => reject(new Error("WebSocket 连接失败")), { once: true });
  });

  let seq = 0;
  const pending = new Map();
  ws.addEventListener("message", (ev) => {
    let msg;
    try { msg = JSON.parse(ev.data); } catch { return; }
    const p2 = pending.get(msg.id);
    if (!p2) return;
    pending.delete(msg.id);
    msg.error ? p2.reject(new Error(msg.error.message)) : p2.resolve(msg.result);
  });

  return {
    call(method, params = {}) {
      const id = ++seq;
      return new Promise((resolve, reject) => {
        pending.set(id, { resolve, reject });
        ws.send(JSON.stringify({ id, method, params }));
        setTimeout(() => {
          if (pending.delete(id)) reject(new Error(`超时: ${method}`));
        }, 30000);
      });
    },
    close() { try { ws.close(); } catch {} },
  };
}

const cdp = await connect(port);

if (mode === "export") {
  const { cookies } = await cdp.call("Storage.getCookies");
  fs.writeFileSync(fileArg, JSON.stringify(cookies, null, 1));
  cdp.close();
  const hosts = new Set(cookies.map((c) => c.domain.replace(/^\./, "")));
  console.log(`✓ 导出 ${cookies.length} 条 cookie（${hosts.size} 个域名）→ ${fileArg}`);
  process.exit(0);
}

// import
const cookies = JSON.parse(fs.readFileSync(fileArg, "utf8"));
if (!Array.isArray(cookies) || cookies.length === 0) {
  console.error("✗ 输入文件里没有 cookie");
  process.exit(1);
}

// 先清空目标实例已有的 cookie，避免新旧混杂
try {
  await cdp.call("Storage.clearCookies");
} catch {
  // 某些构建不支持，忽略 —— 逐条 set 会覆盖同名项
}

const BATCH = 50;
let ok = 0;
const failures = [];

for (let i = 0; i < cookies.length; i += BATCH) {
  const batch = cookies.slice(i, i + BATCH);
  try {
    await cdp.call("Storage.setCookies", { cookies: batch });
    ok += batch.length;
  } catch {
    // 整批失败时逐条重试，定位个别不兼容的 cookie（如 __Host- 前缀约束）
    for (const c of batch) {
      try {
        await cdp.call("Storage.setCookies", { cookies: [c] });
        ok++;
      } catch (e) {
        failures.push(`${c.domain}${c.path} ${c.name}: ${e.message}`);
      }
    }
  }
}

cdp.close();
console.log(`✓ 写入 ${ok}/${cookies.length} 条 cookie`);
if (failures.length) {
  console.log(`  ${failures.length} 条失败（通常无影响）：`);
  for (const f of failures.slice(0, 8)) console.log(`   - ${f}`);
}
process.exit(ok > 0 ? 0 : 1);

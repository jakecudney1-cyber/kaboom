#!/usr/bin/env node
// Stream live L2 order book data from Hyperliquid.
//
// Uses the Quicknode HyperCore WebSocket endpoint when QUICKNODE_WSS_URL is set
// (hl_subscribe / l2Book), and falls back to Hyperliquid's public WS otherwise.
// Runs on Node 18+ (native global WebSocket).
//
// Usage: node hyperliquid-orderbook.mjs [COIN] [DEPTH]
//        node hyperliquid-orderbook.mjs BTC 10

const coin = (process.argv[2] || "BTC").toUpperCase();
const depth = Number(process.argv[3] || 10);

const qnBase = process.env.QUICKNODE_WSS_URL; // e.g. https://xxx.hype-mainnet.quiknode.pro/<token>/
const useQuicknode = Boolean(qnBase);

// Build the WS URL + subscribe frame for whichever backend we have.
const url = useQuicknode
  ? qnBase.replace(/^http/, "ws").replace(/\/?$/, "/") + "hypercore/ws"
  : "wss://api.hyperliquid.xyz/ws";

const subscribeFrame = useQuicknode
  ? { jsonrpc: "2.0", id: 1, method: "hl_subscribe", params: { streamType: "l2Book", coin } }
  : { method: "subscribe", subscription: { type: "l2Book", coin } };

console.log(`Connecting to ${useQuicknode ? "Quicknode HyperCore" : "Hyperliquid public"} WS for ${coin}...`);

const ws = new WebSocket(url);

function render(book) {
  // book: { coin, levels: [ bids[], asks[] ], time }
  const [bids = [], asks = []] = book.levels || [];
  const rows = [];
  for (let i = 0; i < depth; i++) {
    const b = bids[i];
    const a = asks[i];
    const bid = b ? `${(+b.px).toFixed(2).padStart(12)}  ${(+b.sz).toFixed(4).padStart(10)}` : "".padStart(24);
    const ask = a ? `${(+a.px).toFixed(2).padStart(12)}  ${(+a.sz).toFixed(4).padStart(10)}` : "";
    rows.push(`${bid}  |  ${ask}`);
  }
  const ts = new Date(book.time || Date.now()).toISOString().slice(11, 23);
  console.clear();
  console.log(`${book.coin || coin} L2 order book @ ${ts}`);
  console.log(`${"BID px".padStart(12)}  ${"size".padStart(10)}  |  ${"ASK px".padStart(12)}  size`);
  console.log("-".repeat(56));
  console.log(rows.join("\n"));
}

ws.addEventListener("open", () => {
  ws.send(JSON.stringify(subscribeFrame));
});

ws.addEventListener("message", (ev) => {
  let msg;
  try { msg = JSON.parse(ev.data); } catch { return; }
  // Public WS: { channel: "l2Book", data: {...} }
  // Quicknode: { params: { ... } } (or { result } for the sub ack)
  const book = msg?.data ?? msg?.params?.result ?? msg?.params;
  if (book && book.levels) render(book);
});

ws.addEventListener("error", (e) => console.error("WS error:", e.message || e));
ws.addEventListener("close", () => console.error("Connection closed."));

process.on("SIGINT", () => { ws.close(); process.exit(0); });

#!/usr/bin/env node
import { randomBytes, randomUUID } from "node:crypto";
import { realpathSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { createServer } from "node:http";
import { fileURLToPath } from "node:url";
import { WebSocket, WebSocketServer } from "ws";

const assets = new Map([
  ["/", ["index.html", "text/html; charset=utf-8"]],
  ["/app.js", ["app.js", "text/javascript; charset=utf-8"]],
  ["/style.css", ["style.css", "text/css; charset=utf-8"]],
]);

export function createApp({
  origin,
  iceServers = [{ urls: "stun:stun.l.google.com:19302" }],
  maxRooms = 100,
  maxViewers = 8,
  maxClients = 1000,
} = {}) {
  const rooms = new Map();
  const server = createServer(async (req, res) => {
    res.setHeader(
      "Content-Security-Policy",
      "default-src 'self'; connect-src 'self'; media-src 'self' blob:; object-src 'none'; base-uri 'none'; frame-ancestors 'none'",
    );
    res.setHeader("Referrer-Policy", "no-referrer");
    res.setHeader("X-Content-Type-Options", "nosniff");
    res.setHeader("Cache-Control", "no-store");
    const asset = assets.get(req.url);
    if (req.method !== "GET" || !asset) {
      res.writeHead(404).end();
      return;
    }
    try {
      const body = await readFile(
        new URL(`./public/${asset[0]}`, import.meta.url),
      );
      res.writeHead(200, { "Content-Type": asset[1] }).end(body);
    } catch {
      res.writeHead(500).end();
    }
  });
  const wss = new WebSocketServer({ noServer: true, maxPayload: 64 * 1024 });
  server.on("upgrade", (req, socket, head) => {
    const expectedOrigin = origin ?? `http://${req.headers.host}`;
    if (
      req.url !== "/signal" ||
      req.headers.origin !== expectedOrigin ||
      wss.clients.size >= maxClients
    ) {
      socket.end("HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n");
      return;
    }
    wss.handleUpgrade(req, socket, head, (ws) => wss.emit("connection", ws));
  });

  function send(ws, message) {
    if (ws.readyState !== WebSocket.OPEN) return;
    if (ws.bufferedAmount > 1024 * 1024) return ws.terminate();
    ws.send(JSON.stringify(message));
  }
  function reject(ws, message) {
    send(ws, { type: "error", message });
    ws.close(1008, message);
  }

  wss.on("connection", (ws) => {
    ws.id = randomUUID();
    ws.alive = true;
    let room;
    let messages = 0;
    let windowStart = Date.now();
    const joinTimer = setTimeout(
      () => ws.close(1008, "Join timed out"),
      10_000,
    );
    ws.on("error", () => {});
    ws.on("pong", () => {
      ws.alive = true;
    });
    ws.on("message", (data, binary) => {
      if (ws.readyState !== WebSocket.OPEN) return;
      if (Date.now() - windowStart > 10_000) {
        windowStart = Date.now();
        messages = 0;
      }
      if (++messages > 500) return reject(ws, "Too many messages");
      let msg;
      try {
        if (binary) throw new Error();
        msg = JSON.parse(data.toString());
        if (!msg || typeof msg !== "object") throw new Error();
      } catch {
        return reject(ws, "Invalid message");
      }
      if (!room) {
        if (msg.type === "create") {
          if (rooms.size >= maxRooms) return reject(ws, "Server is full");
          const token = randomBytes(24).toString("base64url");
          room = { token, host: ws, viewers: new Map() };
          rooms.set(token, room);
          send(ws, { type: "created", token, iceServers });
        } else if (msg.type === "join") {
          const target = rooms.get(msg.token);
          if (!target)
            return reject(ws, "This share has ended or the link is invalid");
          if (target.viewers.size >= maxViewers)
            return reject(ws, "This share is full");
          room = target;
          room.viewers.set(ws.id, ws);
          send(ws, { type: "joined", id: ws.id, iceServers });
          send(room.host, { type: "viewer", id: ws.id });
        } else {
          return reject(ws, "Create or join a share first");
        }
        clearTimeout(joinTimer);
        return;
      }
      // Only the sharer can offer; viewers cannot signal each other or impersonate peers.
      const isHost = room.host === ws;
      const target = isHost ? room.viewers.get(msg.to) : room.host;
      const validDescription =
        msg.type === "description" &&
        msg.description?.type === (isHost ? "offer" : "answer") &&
        typeof msg.description.sdp === "string";
      const validCandidate =
        msg.type === "candidate" &&
        msg.candidate &&
        typeof msg.candidate.candidate === "string";
      if (!target || (!validDescription && !validCandidate)) {
        return reject(ws, "Invalid signal");
      }
      send(
        target,
        validDescription
          ? { type: "description", from: ws.id, description: msg.description }
          : { type: "candidate", from: ws.id, candidate: msg.candidate },
      );
    });
    ws.on("close", () => {
      clearTimeout(joinTimer);
      if (!room) return;
      if (room.host === ws) {
        rooms.delete(room.token);
        for (const viewer of room.viewers.values()) {
          send(viewer, { type: "ended" });
          viewer.close(1000, "Share ended");
        }
      } else {
        room.viewers.delete(ws.id);
        send(room.host, { type: "left", id: ws.id });
      }
    });
  });
  const heartbeat = setInterval(() => {
    for (const ws of wss.clients) {
      if (!ws.alive) ws.terminate();
      else {
        ws.alive = false;
        ws.ping();
      }
    }
  }, 15_000);
  heartbeat.unref();
  return {
    server,
    async close() {
      clearInterval(heartbeat);
      for (const ws of wss.clients) ws.terminate();
      await new Promise((resolve) => wss.close(resolve));
      await new Promise((resolve, reject) =>
        server.close((error) => (error ? reject(error) : resolve())),
      );
    },
  };
}

if (
  process.argv[1] &&
  realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  const app = createApp({
    origin: process.env.PUBLIC_ORIGIN,
    iceServers: process.env.ICE_SERVERS_JSON
      ? JSON.parse(process.env.ICE_SERVERS_JSON)
      : undefined,
  });
  const host = process.env.HOST ?? "127.0.0.1";
  const port = Number(process.env.PORT ?? 3000);
  app.server.listen(port, host, () =>
    console.log(`Screenshare listening on http://${host}:${port}`),
  );
  for (const signal of ["SIGTERM", "SIGINT"])
    process.once(signal, () => app.close());
}

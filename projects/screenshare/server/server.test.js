import assert from "node:assert/strict";
import { once } from "node:events";
import test from "node:test";
import { WebSocket } from "ws";
import { createApp } from "./server.js";

async function setup(t, options = {}) {
  const app = createApp({ iceServers: [], ...options });
  app.server.listen(0, "127.0.0.1");
  await once(app.server, "listening");
  t.after(() => app.close());
  const origin = `http://127.0.0.1:${app.server.address().port}`;
  async function client() {
    const ws = new WebSocket(`${origin.replace("http", "ws")}/signal`, {
      origin,
    });
    const messages = [];
    const waiting = [];
    ws.on("message", (data) => {
      const message = JSON.parse(data);
      if (waiting.length) waiting.shift()(message);
      else messages.push(message);
    });
    await once(ws, "open");
    return {
      ws,
      send: (message) => ws.send(JSON.stringify(message)),
      next: () =>
        messages.length
          ? Promise.resolve(messages.shift())
          : new Promise((resolve) => waiting.push(resolve)),
    };
  }
  return { origin, client };
}

test(
  "serves only app assets with restrictive headers",
  { timeout: 5000 },
  async (t) => {
    const { origin } = await setup(t);
    for (const path of ["/", "/app.js", "/style.css"]) {
      const response = await fetch(origin + path);
      assert.equal(response.status, 200);
      assert.match(
        response.headers.get("content-security-policy"),
        /frame-ancestors 'none'/,
      );
      assert.equal(response.headers.get("referrer-policy"), "no-referrer");
    }
    assert.equal((await fetch(`${origin}/server.js`)).status, 404);
    assert.equal((await fetch(origin, { method: "POST" })).status, 404);
  },
);

test(
  "routes offer, answer and ICE, removes viewers, and invalidates ended rooms",
  { timeout: 5000 },
  async (t) => {
    const { client } = await setup(t);
    const host = await client();
    host.send({ type: "create" });
    const created = await host.next();
    assert.equal(created.type, "created");
    assert.match(created.token, /^[\w-]{32}$/);
    assert.deepEqual(created.iceServers, []);
    const viewer = await client();
    viewer.send({ type: "join", token: created.token });
    const joined = await viewer.next();
    assert.equal(joined.type, "joined");
    assert.deepEqual(await host.next(), { type: "viewer", id: joined.id });
    const offer = { type: "offer", sdp: "test offer" };
    host.send({ type: "description", to: joined.id, description: offer });
    const forwarded = await viewer.next();
    assert.deepEqual(forwarded.description, offer);
    const answer = { type: "answer", sdp: "test answer" };
    viewer.send({
      type: "description",
      to: "ignored",
      from: "forged",
      description: answer,
    });
    assert.deepEqual(await host.next(), {
      type: "description",
      from: joined.id,
      description: answer,
    });
    const candidate = { candidate: "test candidate", sdpMid: "0" };
    viewer.send({ type: "candidate", candidate });
    assert.deepEqual(await host.next(), {
      type: "candidate",
      from: joined.id,
      candidate,
    });
    host.send({ type: "candidate", to: joined.id, candidate });
    assert.deepEqual(await viewer.next(), {
      type: "candidate",
      from: forwarded.from,
      candidate,
    });
    viewer.ws.close();
    assert.deepEqual(await host.next(), { type: "left", id: joined.id });
    const second = await client();
    second.send({ type: "join", token: created.token });
    await second.next();
    await host.next();
    host.ws.close();
    assert.deepEqual(await second.next(), { type: "ended" });
    const late = await client();
    late.send({ type: "join", token: created.token });
    assert.equal((await late.next()).type, "error");
  },
);

test(
  "rejects unknown rooms, malformed input, and viewer offers",
  { timeout: 5000 },
  async (t) => {
    const { client } = await setup(t);
    const missing = await client();
    missing.send({ type: "join", token: "missing" });
    assert.equal((await missing.next()).type, "error");
    const malformed = await client();
    malformed.ws.send("not json");
    assert.equal((await malformed.next()).message, "Invalid message");
    const host = await client();
    host.send({ type: "create" });
    const { token } = await host.next();
    const viewer = await client();
    viewer.send({ type: "join", token });
    await viewer.next();
    await host.next();
    viewer.send({
      type: "description",
      description: { type: "offer", sdp: "nope" },
    });
    assert.equal((await viewer.next()).message, "Invalid signal");
  },
);

test("enforces room and viewer limits", { timeout: 5000 }, async (t) => {
  const { client } = await setup(t, { maxRooms: 1, maxViewers: 1 });
  const host = await client();
  host.send({ type: "create" });
  const { token } = await host.next();
  const extraHost = await client();
  extraHost.send({ type: "create" });
  assert.equal((await extraHost.next()).message, "Server is full");
  const viewer = await client();
  viewer.send({ type: "join", token });
  assert.equal((await viewer.next()).type, "joined");
  const extraViewer = await client();
  extraViewer.send({ type: "join", token });
  assert.equal((await extraViewer.next()).message, "This share is full");
});

test(
  "rejects cross-origin WebSocket connections",
  { timeout: 5000 },
  async (t) => {
    const { origin } = await setup(t);
    const ws = new WebSocket(`${origin.replace("http", "ws")}/signal`, {
      origin: "https://untrusted.example",
    });
    ws.on("error", () => {});
    const response = await new Promise((resolve) =>
      ws.once("unexpected-response", (_, res) => resolve(res)),
    );
    assert.equal(response.statusCode, 403);
    response.resume();
    ws.terminate();
  },
);

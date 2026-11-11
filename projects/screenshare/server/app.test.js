import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const code = await readFile(
  new URL("./public/app.js", import.meta.url),
  "utf8",
);
function track(kind) {
  return {
    kind,
    readyState: "live",
    stop() {
      this.readyState = "ended";
    },
  };
}
function media(...tracks) {
  return {
    getTracks: () => [...tracks],
    getAudioTracks: () => tracks.filter((track) => track.kind === "audio"),
    getVideoTracks: () => tracks.filter((track) => track.kind === "video"),
    addTrack: (track) => tracks.push(track),
    removeTrack: (track) => {
      tracks = tracks.filter((item) => item !== track);
    },
  };
}
function setup() {
  const elements = new Map();
  function element(id) {
    if (!elements.has(id))
      elements.set(id, {
        value: "screen",
        textContent: "",
        hidden: false,
        disabled: false,
        selectedOptions: [{ textContent: "Screenshare audio" }],
        replaceChildren(...options) {
          this.options = options;
        },
        play: async () => {},
      });
    return elements.get(id);
  }
  const calls = { display: [], input: [], sockets: [], peers: [] };
  const video = track("video");
  const screenAudio = track("audio");
  const inputAudio = track("audio");
  const devices = {
    async getDisplayMedia(options) {
      calls.display.push(options);
      return media(video, screenAudio);
    },
    async getUserMedia(options) {
      calls.input.push(options);
      return media(inputAudio);
    },
    async enumerateDevices() {
      return [
        { kind: "audioinput", deviceId: "default", label: "Default" },
        { kind: "audioinput", deviceId: "virtual", label: "Screenshare audio" },
      ];
    },
  };
  class Socket {
    constructor() {
      calls.sockets.push(this);
    }
    close() {}
  }
  class Peer {
    constructor() {
      this.signalingState = "stable";
      calls.peers.push(this);
    }
    addTrack(track) {
      return {
        track,
        async replaceTrack(next) {
          this.track = next;
        },
      };
    }
    addTransceiver() {
      return { sender: this.addTrack(null) };
    }
    close() {
      this.signalingState = "closed";
    }
  }
  const context = vm.createContext({
    RTCPeerConnection: Peer,
    document: { getElementById: element },
    navigator: { mediaDevices: devices },
    location: {
      hash: "",
      protocol: "http:",
      host: "localhost",
      origin: "http://localhost",
    },
    window: { isSecureContext: true, addEventListener() {} },
    WebSocket: Socket,
    Option: class {
      constructor(text, value) {
        this.textContent = text;
        this.value = value;
      }
    },
    setTimeout() {},
    clearTimeout() {},
  });
  vm.runInContext(code, context);
  return { element, calls, devices, video, screenAudio, inputAudio, context };
}

test("screen capture remains the default and never opens a microphone", async () => {
  const app = setup();
  await app.element("start").onclick();
  assert.equal(app.calls.input.length, 0);
  assert.equal(app.calls.display[0].audio.echoCancellation, false);
  assert.equal(app.calls.sockets.length, 1);
  app.element("stop").onclick();
  assert.equal(app.video.readyState, "ended");
  assert.equal(app.screenAudio.readyState, "ended");
});

test("input discovery stops the permission stream and does not select a microphone", async () => {
  const app = setup();
  await app.element("load-inputs").onclick();
  assert.equal(app.inputAudio.readyState, "ended");
  assert.equal(app.element("audio-source").value, "screen");
  assert.deepEqual(
    Array.from(app.element("audio-source").options, (option) => option.value),
    ["screen", "none", "virtual"],
  );
  assert.equal(app.calls.sockets.length, 0);
});

test("selected input replaces screen audio and all tracks stop together", async () => {
  const app = setup();
  app.element("audio-source").value = "virtual";
  await app.element("start").onclick();
  assert.equal(app.calls.display[0].audio, false);
  assert.equal(app.calls.input[0].audio.deviceId.exact, "virtual");
  assert.equal(app.calls.input[0].audio.echoCancellation, false);
  assert.equal(app.calls.input[0].audio.noiseSuppression, false);
  assert.equal(app.calls.input[0].audio.autoGainControl, false);
  assert.equal(app.screenAudio.readyState, "ended");
  assert.equal(
    vm.runInContext("stream.getAudioTracks().length", app.context),
    1,
  );
  assert.equal(app.element("audio-source").disabled, true);
  app.element("stop").onclick();
  assert.equal(app.video.readyState, "ended");
  assert.equal(app.inputAudio.readyState, "ended");
  assert.equal(app.element("audio-source").disabled, false);
});

test("no-audio mode neither retains screen audio nor requests microphone access", async () => {
  const app = setup();
  app.element("audio-source").value = "none";
  await app.element("start").onclick();
  assert.equal(app.calls.input.length, 0);
  assert.equal(app.screenAudio.readyState, "ended");
  assert.equal(
    vm.runInContext("stream.getAudioTracks().length", app.context),
    0,
  );
  app.element("stop").onclick();
});

test("an unavailable selected input aborts rather than falling back to the default mic", async () => {
  const app = setup();
  app.element("audio-source").value = "missing";
  app.devices.getUserMedia = async () => {
    throw new Error("Device unavailable");
  };
  await app.element("start").onclick();
  assert.equal(app.video.readyState, "ended");
  assert.equal(app.screenAudio.readyState, "ended");
  assert.equal(app.calls.sockets.length, 0);
  assert.match(app.element("status").textContent, /Device unavailable/);
});

test("stopping during the audio permission prompt cleans up the late stream", async () => {
  const app = setup();
  app.element("audio-source").value = "virtual";
  let resolve;
  let notify;
  const opened = new Promise((done) => {
    notify = done;
  });
  app.devices.getUserMedia = () =>
    new Promise((done) => {
      resolve = done;
      notify();
    });
  const pending = app.element("start").onclick();
  await opened;
  app.element("stop").onclick();
  resolve(media(app.inputAudio));
  await pending;
  assert.equal(app.video.readyState, "ended");
  assert.equal(app.inputAudio.readyState, "ended");
  assert.equal(app.calls.sockets.length, 0);
});

async function ready(app) {
  await app.element("start").onclick();
  await vm.runInContext(
    'handleMessage({type: "created", token: "room-token", iceServers: []}, generation)',
    app.context,
  );
}
function addPeer(app, id = "viewer") {
  return vm.runInContext(`makePeer(${JSON.stringify(id)})`, app.context);
}
function deferred() {
  let resolve;
  const promise = new Promise((done) => {
    resolve = done;
  });
  return { promise, resolve };
}

test("changing capture replaces tracks without changing the room or peer connections", async () => {
  const app = setup();
  await ready(app);
  const peer = addPeer(app);
  const nextVideo = track("video");
  const nextAudio = track("audio");
  const originalLink = app.element("link").value;
  app.devices.getDisplayMedia = async () => media(nextVideo, nextAudio);
  await app.element("change-screen").onclick();
  assert.equal(peer.senders.video.track, nextVideo);
  assert.equal(peer.senders.audio.track, nextAudio);
  assert.equal(app.video.readyState, "ended");
  assert.equal(app.screenAudio.readyState, "ended");
  assert.equal(app.calls.sockets.length, 1);
  assert.equal(app.calls.peers.length, 1);
  assert.equal(app.element("link").value, originalLink);
  assert.equal(app.element("invite").hidden, false);
  const newcomer = addPeer(app, "late-viewer");
  assert.equal(newcomer.senders.video.track, nextVideo);
  app.element("stop").onclick();
  assert.equal(nextVideo.readyState, "ended");
  assert.equal(nextAudio.readyState, "ended");
});

test("changing windows preserves the selected virtual input without recapturing it", async () => {
  const app = setup();
  app.element("audio-source").value = "virtual";
  await ready(app);
  const peer = addPeer(app);
  const nextVideo = track("video");
  app.devices.getDisplayMedia = async () => media(nextVideo);
  await app.element("change-screen").onclick();
  assert.equal(peer.senders.video.track, nextVideo);
  assert.equal(peer.senders.audio.track, app.inputAudio);
  assert.equal(app.inputAudio.readyState, "live");
  assert.equal(app.calls.input.length, 1);
  app.element("stop").onclick();
  assert.equal(app.inputAudio.readyState, "ended");
});

test("reserved audio sender supports silent-to-audio and audio-to-silent switches", async () => {
  const app = setup();
  app.devices.getDisplayMedia = async () => media(track("video"));
  await ready(app);
  const peer = addPeer(app);
  const sender = peer.senders.audio;
  assert.equal(sender.track, null);
  const audio = track("audio");
  app.devices.getDisplayMedia = async () => media(track("video"), audio);
  await app.element("change-screen").onclick();
  assert.equal(sender.track, audio);
  app.devices.getDisplayMedia = async () => media(track("video"));
  await app.element("change-screen").onclick();
  assert.equal(peer.senders.audio, sender);
  assert.equal(sender.track, null);
  assert.equal(audio.readyState, "ended");
  app.element("stop").onclick();
});

test("cancelling the picker leaves the original capture and link intact", async () => {
  const app = setup();
  await ready(app);
  const originalLink = app.element("link").value;
  app.devices.getDisplayMedia = async () => {
    const error = new Error("Cancelled");
    error.name = "NotAllowedError";
    throw error;
  };
  await app.element("change-screen").onclick();
  assert.equal(app.video.readyState, "live");
  assert.equal(app.screenAudio.readyState, "live");
  assert.equal(app.element("link").value, originalLink);
  assert.equal(app.element("change-screen").disabled, false);
  assert.match(app.element("status").textContent, /cancelled/);
  app.element("stop").onclick();
});

test("failed replacement rolls all peers back and stops the rejected capture", async () => {
  const app = setup();
  await ready(app);
  const first = addPeer(app, "first");
  const second = addPeer(app, "second");
  const nextVideo = track("video");
  const nextAudio = track("audio");
  second.senders.video.replaceTrack = async function (next) {
    if (next === nextVideo) throw new Error("Codec limits");
    this.track = next;
  };
  app.devices.getDisplayMedia = async () => media(nextVideo, nextAudio);
  await app.element("change-screen").onclick();
  for (const peer of [first, second]) {
    assert.equal(peer.senders.video.track, app.video);
    assert.equal(peer.senders.audio.track, app.screenAudio);
  }
  assert.equal(app.video.readyState, "live");
  assert.equal(nextVideo.readyState, "ended");
  assert.equal(nextAudio.readyState, "ended");
  assert.match(app.element("status").textContent, /Codec limits/);
  app.element("stop").onclick();
});

test("stopping while the picker is open disposes of its eventual capture", async () => {
  const app = setup();
  await ready(app);
  const selected = deferred();
  app.devices.getDisplayMedia = () => selected.promise;
  const changing = app.element("change-screen").onclick();
  app.element("stop").onclick();
  const nextVideo = track("video");
  const nextAudio = track("audio");
  selected.resolve(media(nextVideo, nextAudio));
  await changing;
  assert.equal(nextVideo.readyState, "ended");
  assert.equal(nextAudio.readyState, "ended");
  assert.equal(app.element("change-screen").hidden, true);
  assert.equal(app.element("invite").hidden, true);
});

test("stopping during track replacement releases both captures", async () => {
  const app = setup();
  await ready(app);
  const peer = addPeer(app);
  const entered = deferred();
  const replaced = deferred();
  peer.senders.video.replaceTrack = () => {
    entered.resolve();
    return replaced.promise;
  };
  const nextVideo = track("video");
  const nextAudio = track("audio");
  app.devices.getDisplayMedia = async () => media(nextVideo, nextAudio);
  const changing = app.element("change-screen").onclick();
  await entered.promise;
  app.element("stop").onclick();
  replaced.resolve();
  await changing;
  for (const t of [app.video, app.screenAudio, nextVideo, nextAudio])
    assert.equal(t.readyState, "ended");
  assert.equal(app.element("invite").hidden, true);
});

test("viewers joining during replacement receive the new capture too", async () => {
  const app = setup();
  await ready(app);
  const first = addPeer(app, "first");
  const entered = deferred();
  const replaced = deferred();
  first.senders.video.replaceTrack = async function (next) {
    entered.resolve();
    await replaced.promise;
    this.track = next;
  };
  const nextVideo = track("video");
  app.devices.getDisplayMedia = async () => media(nextVideo);
  const changing = app.element("change-screen").onclick();
  await entered.promise;
  const second = addPeer(app, "second");
  replaced.resolve();
  await changing;
  assert.equal(first.senders.video.track, nextVideo);
  assert.equal(second.senders.video.track, nextVideo);
  app.element("stop").onclick();
});

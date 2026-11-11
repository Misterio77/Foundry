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
  const calls = { display: [], input: [], sockets: [] };
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
  const context = vm.createContext({
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

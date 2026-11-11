const $ = (id) => document.getElementById(id);
const token = location.hash.slice(1);
const watching = Boolean(token);
const peers = new Map();
let stream;
let pendingStream;
let socket;
let iceServers = [];
let generation = 0;
let busy = false;
let inputRequest = 0;
const audioConstraints = {
  echoCancellation: false,
  noiseSuppression: false,
  autoGainControl: false,
};

async function loadInputs() {
  if (busy || socket) return;
  if (!navigator.mediaDevices?.getUserMedia)
    return status("Audio inputs need HTTPS and browser microphone support.");
  const request = ++inputRequest;
  busy = true;
  $("start").disabled = true;
  $("load-inputs").disabled = true;
  try {
    const permission = await navigator.mediaDevices.getUserMedia({
      audio: audioConstraints,
    });
    permission.getTracks().forEach((track) => track.stop());
    if (request !== inputRequest) return;
    const devices = await navigator.mediaDevices.enumerateDevices();
    if (request !== inputRequest) return;
    const selected = $("audio-source").value;
    const options = [
      new Option("From screen capture, if available", "screen"),
      new Option("No audio", "none"),
    ];
    for (const device of devices) {
      if (
        device.kind === "audioinput" &&
        device.deviceId &&
        !["default", "communications"].includes(device.deviceId)
      )
        options.push(
          new Option(device.label || "Unnamed audio input", device.deviceId),
        );
    }
    if (!options.some((option) => option.value === selected))
      options.push(
        new Option("Previously selected input (unavailable)", selected),
      );
    $("audio-source").replaceChildren(...options);
    $("audio-source").value = selected;
    status(
      options.length > 2
        ? "Select the virtual input carrying your application audio."
        : "No audio inputs found. Create a virtual input, then list inputs again.",
    );
  } catch (error) {
    if (request === inputRequest)
      status(`Couldn’t list audio inputs: ${error.message}`);
  } finally {
    if (request === inputRequest) {
      busy = false;
      $("start").disabled = false;
      $("load-inputs").disabled = false;
    }
  }
}

function status(message) {
  $("status").textContent = message;
}
function updateCount() {
  $("count").textContent =
    !watching && socket
      ? `${peers.size} viewer${peers.size === 1 ? "" : "s"}`
      : "";
}
function reset(message) {
  generation++;
  inputRequest++;
  busy = false;
  const oldSocket = socket;
  socket = undefined;
  oldSocket?.close();
  for (const { pc } of peers.values()) pc.close();
  peers.clear();
  stopMedia(stream);
  stopMedia(pendingStream);
  stream = undefined;
  pendingStream = undefined;
  $("video").srcObject = null;
  $("video").hidden = true;
  $("placeholder").hidden = false;
  $("play").hidden = true;
  $("invite").hidden = true;
  $("stop").hidden = true;
  $("change-screen").hidden = true;
  $("change-screen").disabled = false;
  $("start").hidden = watching;
  $("watch").hidden = !watching;
  $("start").disabled = false;
  $("watch").disabled = false;
  $("audio").textContent = "";
  $("audio-source").disabled = false;
  $("load-inputs").disabled = false;
  updateCount();
  status(message);
}
function send(message) {
  if (socket?.readyState === WebSocket.OPEN)
    socket.send(JSON.stringify(message));
}
async function play() {
  try {
    await $("video").play();
    $("play").hidden = true;
  } catch {
    $("play").hidden = false;
  }
}
function showVideo(media, muted) {
  $("video").muted = muted;
  $("video").srcObject = media;
  $("video").hidden = false;
  $("placeholder").hidden = true;
  void play();
}
function stopMedia(media, keep) {
  const retained = keep?.getTracks() ?? [];
  for (const track of media?.getTracks() ?? []) {
    if (!retained.includes(track)) track.stop();
  }
}
function captureScreen() {
  const source = $("audio-source").value;
  return navigator.mediaDevices.getDisplayMedia({
    video: {
      width: { ideal: 1920 },
      height: { ideal: 1080 },
      frameRate: { ideal: 30, max: 60 },
    },
    audio: source === "screen" ? audioConstraints : false,
    systemAudio: source === "screen" ? "include" : "exclude",
  });
}
function prepareCapture(media) {
  const video = media.getVideoTracks()[0];
  if (!video || video.readyState !== "live")
    throw new Error("No live video track was provided.");
  video.contentHint = "motion";
  video.onended = () => {
    if (stream === media) reset("Screen sharing stopped.");
  };
  if ($("audio-source").value !== "screen") {
    for (const track of media.getAudioTracks()) {
      track.stop();
      media.removeTrack(track);
    }
  }
}
function previewCapture() {
  const source = $("audio-source").value;
  const sourceLabel = $("audio-source").selectedOptions[0].textContent;
  $("audio").textContent = stream
    .getAudioTracks()
    .some((track) => track.readyState === "live")
    ? `${source === "screen" ? "Screen audio" : sourceLabel}. Preview muted.`
    : source === "none"
      ? "Audio disabled."
      : "No audio available. Choose an audio-enabled screen or restart sharing with a separate audio input.";
  for (const track of stream.getAudioTracks())
    track.onended = () => {
      $("audio").textContent =
        "Audio capture stopped. Restart sharing to restore sound.";
    };
  showVideo(stream, true);
}
async function replaceTracks(peer, media) {
  const results = await Promise.allSettled([
    peer.senders.video.replaceTrack(media.getVideoTracks()[0]),
    peer.senders.audio.replaceTrack(media.getAudioTracks()[0] ?? null),
  ]);
  const failure = results.find((result) => result.status === "rejected");
  if (failure && peer.pc.signalingState !== "closed") throw failure.reason;
}
async function changeScreen() {
  if (busy || watching || !socket || !stream) return;
  busy = true;
  $("change-screen").disabled = true;
  const current = generation;
  const previous = stream;
  let replacement;
  try {
    status(
      "Choose a new screen or window. The current share stays live until you select one.",
    );
    replacement = await captureScreen();
    if (current !== generation) return;
    pendingStream = replacement;
    prepareCapture(replacement);
    if (!["screen", "none"].includes($("audio-source").value)) {
      for (const track of previous.getAudioTracks())
        replacement.addTrack(track);
    }
    // Viewers joining while replaceTrack awaits must also receive the new capture.
    const updated = new Set();
    while (current === generation) {
      const batch = [...peers.values()].filter((peer) => !updated.has(peer));
      if (!batch.length) break;
      const results = await Promise.allSettled(
        batch.map((peer) => replaceTracks(peer, replacement)),
      );
      if (current !== generation) return;
      const failure = results.find((result) => result.status === "rejected");
      if (failure) throw failure.reason;
      for (const peer of batch) updated.add(peer);
    }
    if (replacement.getVideoTracks()[0].readyState !== "live")
      throw new Error("The new capture ended before switching completed.");
    stream = replacement;
    pendingStream = undefined;
    stopMedia(previous, stream);
    previewCapture();
    status("Screen changed. The invite link is unchanged.");
  } catch (error) {
    if (current !== generation) return;
    const rollback = replacement
      ? await Promise.allSettled(
          [...peers.values()].map((peer) => replaceTracks(peer, previous)),
        )
      : [];
    if (current !== generation) return;
    status(
      rollback.some((result) => result.status === "rejected")
        ? "Couldn’t restore every viewer’s stream. Affected viewers may need to reconnect."
        : error.name === "NotAllowedError"
          ? "Screen change cancelled. The original share is still live."
          : `Couldn’t change screen: ${error.message}. The original share is still live.`,
    );
  } finally {
    if (replacement !== stream) stopMedia(replacement, stream);
    if (current === generation) {
      pendingStream = undefined;
      busy = false;
      $("change-screen").disabled = false;
    }
  }
}
function makePeer(id) {
  const pc = new RTCPeerConnection({ iceServers });
  const peer = { pc, candidates: [] };
  peers.set(id, peer);
  updateCount();
  pc.onicecandidate = ({ candidate }) => {
    if (candidate)
      send({ type: "candidate", to: id, candidate: candidate.toJSON() });
  };
  pc.onconnectionstatechange = () => {
    if (pc.connectionState === "connected") {
      status(watching ? "Connected." : "Sharing. Keep this tab open.");
    } else if (pc.connectionState === "failed") {
      if (watching)
        reset(
          "Couldn’t connect to the sharer. Try again; some networks require a TURN relay.",
        );
      else
        status(
          "A viewer couldn’t connect. Some networks require a TURN relay.",
        );
    } else if (pc.connectionState === "disconnected") {
      status("Connection interrupted. Waiting for the network…");
    }
  };
  if (watching) {
    const received = new MediaStream();
    pc.ontrack = ({ track }) => {
      received.addTrack(track);
      showVideo(received, false);
      $("audio").textContent = received.getAudioTracks().length
        ? "Use the player’s volume control for stream audio."
        : "Waiting for audio; the sharer may be sending video only.";
    };
  } else {
    const audio = stream.getAudioTracks()[0];
    peer.senders = {
      video: pc.addTrack(stream.getVideoTracks()[0], stream),
      // Reserve audio even for a silent capture so a later switch needs no renegotiation.
      audio: audio
        ? pc.addTrack(audio, stream)
        : pc.addTransceiver("audio", {
            direction: "sendonly",
            streams: [stream],
          }).sender,
    };
  }
  return peer;
}
async function handleMessage(msg, current) {
  if (msg.type === "error") return reset(msg.message);
  if (msg.type === "ended") return reset("The sharer stopped sharing.");
  if (msg.type === "created" || msg.type === "joined") {
    iceServers = msg.iceServers;
    busy = false;
    $("stop").hidden = false;
    $("start").hidden = true;
    $("watch").hidden = true;
    if (msg.type === "created") {
      $("link").value = `${location.origin}/#${msg.token}`;
      $("invite").hidden = false;
      $("change-screen").hidden = false;
      status("Sharing. Keep this tab open.");
      updateCount();
    } else status("Connecting to the sharer…");
    return;
  }
  if (msg.type === "left") {
    peers.get(msg.id)?.pc.close();
    peers.delete(msg.id);
    updateCount();
    return;
  }
  if (msg.type === "viewer") {
    const { pc } = makePeer(msg.id);
    await pc.setLocalDescription(await pc.createOffer());
    if (current === generation)
      send({
        type: "description",
        to: msg.id,
        description: pc.localDescription,
      });
    return;
  }
  const peer =
    peers.get(msg.from) ?? (watching ? makePeer(msg.from) : undefined);
  if (!peer) return;
  if (msg.type === "description") {
    await peer.pc.setRemoteDescription(msg.description);
    for (const candidate of peer.candidates.splice(0))
      await peer.pc.addIceCandidate(candidate);
    if (watching) {
      await peer.pc.setLocalDescription(await peer.pc.createAnswer());
      if (current === generation)
        send({
          type: "description",
          to: msg.from,
          description: peer.pc.localDescription,
        });
    }
  } else if (msg.type === "candidate") {
    if (peer.pc.remoteDescription) await peer.pc.addIceCandidate(msg.candidate);
    else peer.candidates.push(msg.candidate);
  }
}
function connect(current) {
  const ws = new WebSocket(
    `${location.protocol === "https:" ? "wss:" : "ws:"}//${location.host}/signal`,
  );
  socket = ws;
  let queue = Promise.resolve();
  const timeout = setTimeout(() => {
    if (current === generation)
      reset("The signaling server didn’t respond. Try again.");
  }, 12_000);
  ws.onopen = () =>
    send(watching ? { type: "join", token } : { type: "create" });
  ws.onmessage = ({ data }) => {
    queue = queue
      .then(async () => {
        if (current !== generation) return;
        const msg = JSON.parse(data);
        if (["created", "joined", "error"].includes(msg.type))
          clearTimeout(timeout);
        await handleMessage(msg, current);
      })
      .catch(() => {
        if (current === generation)
          reset("Couldn’t negotiate the stream. Please try again.");
      });
  };
  ws.onclose = () => {
    clearTimeout(timeout);
    if (current === generation)
      reset(
        "Disconnected from the signaling server. Start again to reconnect.",
      );
  };
  ws.onerror = () => {
    if (current === generation)
      reset("Couldn’t reach the signaling server. Please try again.");
  };
}
async function start() {
  if (busy || socket) return;
  if (!window.isSecureContext)
    return status("Screen sharing needs HTTPS (or localhost for testing).");
  if (!watching && !navigator.mediaDevices?.getDisplayMedia)
    return status("This browser doesn’t support screen capture.");
  busy = true;
  const current = ++generation;
  $(watching ? "watch" : "start").disabled = true;
  $("audio-source").disabled = true;
  $("load-inputs").disabled = true;
  $("stop").hidden = false;
  try {
    if (!watching) {
      const source = $("audio-source").value;
      const sourceLabel = $("audio-source").selectedOptions[0].textContent;
      status("Choose a screen or window to share.");
      const captured = await captureScreen();
      if (current !== generation) {
        captured.getTracks().forEach((track) => track.stop());
        return;
      }
      stream = captured;
      prepareCapture(stream);
      if (source !== "screen" && source !== "none") {
        status(`Opening audio input: ${sourceLabel}…`);
        const input = await navigator.mediaDevices.getUserMedia({
          audio: {
            ...audioConstraints,
            deviceId: { exact: source },
            channelCount: { ideal: 2 },
          },
        });
        if (current !== generation) {
          input.getTracks().forEach((track) => track.stop());
          return;
        }
        for (const track of input.getAudioTracks()) stream.addTrack(track);
        if (!input.getAudioTracks().length)
          throw new Error("The selected input supplied no audio track.");
      }
      previewCapture();
    }
    status("Connecting…");
    $("stop").hidden = false;
    connect(current);
  } catch (error) {
    if (current === generation)
      reset(
        error.name === "NotAllowedError"
          ? "Capture cancelled or permission denied. Nothing was shared."
          : `Couldn’t start sharing: ${error.message}`,
      );
  }
}
$("change-screen").onclick = changeScreen;
$("load-inputs").onclick = loadInputs;
$("start").onclick = start;
$("watch").onclick = start;
$("stop").onclick = () =>
  reset(
    watching
      ? "You left the stream."
      : "Screen sharing stopped. The invite link is now closed.",
  );
$("play").onclick = () => {
  $("video").muted = false;
  void play();
};
$("copy").onclick = async () => {
  try {
    await navigator.clipboard.writeText($("link").value);
    status("Viewer link copied.");
  } catch {
    $("link").select();
    status("Copy the selected link manually.");
  }
};
window.addEventListener("pagehide", () => reset("Disconnected."));
if (watching) {
  $("audio-settings").hidden = true;
  $("placeholder").textContent = "Not connected";
  $("stop").textContent = "Leave stream";
}
reset(
  watching
    ? "Select Watch stream to connect."
    : "Select a screen or window to share.",
);

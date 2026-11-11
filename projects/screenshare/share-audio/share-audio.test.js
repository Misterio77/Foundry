import assert from "node:assert/strict";
import test from "node:test";
import {
  label,
  playbackNodes,
  routes,
  sameNode,
  selectNode,
} from "./share-audio.js";

function node(id, name, serial = id) {
  return {
    id,
    type: "PipeWire:Interface:Node",
    info: {
      props: {
        "application.name": name,
        "media.class": "Stream/Output/Audio",
        "object.serial": serial,
      },
    },
  };
}
function port(id, node, channel, direction) {
  return {
    id,
    type: "PipeWire:Interface:Port",
    info: {
      props: {
        "node.id": node.id,
        "audio.channel": channel,
        "port.direction": direction,
      },
    },
  };
}

test("selects playback streams by ID or unique case-insensitive name", () => {
  const game = node(42, "Hollow Knight");
  const browser = node(43, "Firefox 42");
  const input = node(44, "Microphone");
  input.info.props["media.class"] = "Audio/Source";
  const nodes = playbackNodes([game, browser, input]);
  assert.deepEqual(nodes, [game, browser]);
  assert.equal(selectNode(nodes, "42"), game);
  assert.equal(selectNode(nodes, "KNIGHT"), game);
  assert.throws(() => selectNode(nodes, "missing"), /No matching/);
  assert.throws(
    () => selectNode([game, node(45, "Hollow Knight")], "knight"),
    /More than one/,
  );
});

test("node serial prevents accidentally attaching to a reused ID", () => {
  const selected = node(42, "Game", 100);
  assert.equal(sameNode([selected], selected), selected);
  assert.equal(sameNode([node(42, "Different app", 101)], selected), undefined);
});

test("stereo routing uses channel labels, not port order", () => {
  const source = node(42, "Game");
  const capture = node(43, "Capture");
  const graph = [
    port(1, source, "FR", "out"),
    port(2, source, "FL", "out"),
    port(3, capture, "FL", "in"),
    port(4, capture, "FR", "in"),
  ];
  assert.deepEqual(routes(graph, source, capture), [
    [2, 3],
    [1, 4],
  ]);
});

test("mono feeds both channels; unsupported layouts fail instead of dropping audio", () => {
  const source = node(42, "Game");
  const capture = node(43, "Capture");
  const graph = [
    port(1, source, "MONO", "out"),
    port(3, capture, "FL", "in"),
    port(4, capture, "FR", "in"),
  ];
  assert.deepEqual(routes(graph, source, capture), [
    [1, 3],
    [1, 4],
  ]);
  graph.push(port(2, source, "LFE", "out"));
  assert.throws(() => routes(graph, source, capture), /mono and stereo/);
  assert.deepEqual(routes([], source, capture), []);
});

test("picker labels strip terminal control characters", () => {
  assert.doesNotMatch(label(node(1, "Game\n\x1b\t\u202e")), /[\p{Cc}\p{Cf}]/u);
});

#!/usr/bin/env node
import { execFileSync, spawn, spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { realpathSync } from "node:fs";
import { setTimeout as sleep } from "node:timers/promises";
import { fileURLToPath } from "node:url";

const props = (object) => object.info?.props ?? {};
const clean = (text) => String(text).replace(/[\p{Cc}\p{Cf}]/gu, " ");
export function playbackNodes(graph) {
  return graph.filter(
    (object) =>
      object.type === "PipeWire:Interface:Node" &&
      props(object)["media.class"] === "Stream/Output/Audio",
  );
}
export function label(node) {
  const p = props(node);
  return clean(
    `${p["application.name"] ?? p["node.name"] ?? "Unknown app"} · ${p["media.name"] ?? "audio"} [${p["application.process.binary"] ?? "unknown process"}]`,
  );
}
export function applicationKey(node) {
  const identity = [
    "application.id",
    "application.process.binary",
    "application.name",
  ].flatMap((key) => (props(node)[key] ? [[key, props(node)[key]]] : []));
  return identity.length ? JSON.stringify(identity) : undefined;
}
export function selectNode(nodes, query) {
  const matches = nodes.filter((node) =>
    /^\d+$/.test(query)
      ? String(node.id) === query
      : [
          "application.name",
          "application.process.binary",
          "node.name",
          "media.name",
        ].some((key) =>
          String(props(node)[key] ?? "")
            .toLowerCase()
            .includes(query.toLowerCase()),
        ),
  );
  const identity = matches.length && applicationKey(matches[0]);
  if (
    matches.length !== 1 &&
    !(identity && matches.every((node) => applicationKey(node) === identity))
  )
    throw new Error(
      matches.length
        ? `More than one application matches. Use a more specific name or a node ID:\n${matches.map((node) => `${node.id}\t${label(node)}`).join("\n")}`
        : "No matching playback stream. Start audio in the app first; use --list to see streams.",
    );
  return matches[0];
}
export function sameNode(graph, selected) {
  return graph.find(
    (object) =>
      object.type === "PipeWire:Interface:Node" &&
      object.id === selected.id &&
      props(object)["object.serial"] === props(selected)["object.serial"],
  );
}
export function routes(graph, source, capture) {
  const ports = (node, direction) =>
    graph.filter(
      (object) =>
        object.type === "PipeWire:Interface:Port" &&
        Number(props(object)["node.id"]) === node.id &&
        props(object)["port.direction"] === direction &&
        props(object)["audio.channel"],
    );
  const outputs = ports(source, "out");
  const inputs = ports(capture, "in");
  if (!outputs.length || inputs.length !== 2) return [];
  const channels = outputs.map((port) => props(port)["audio.channel"]);
  const mono = channels.length === 1 && channels[0] === "MONO";
  if (
    !mono &&
    !(
      channels.length === 2 &&
      channels.includes("FL") &&
      channels.includes("FR")
    )
  )
    throw new Error(
      "Only mono and stereo streams are supported. Set the game’s output to stereo.",
    );
  return inputs.map((input) => {
    const output = mono
      ? outputs[0]
      : outputs.find(
          (port) =>
            props(port)["audio.channel"] === props(input)["audio.channel"],
        );
    if (!output) throw new Error("Unexpected loopback channel layout.");
    return [output.id, input.id];
  });
}
function dump() {
  return JSON.parse(
    execFileSync("pw-dump", [], {
      encoding: "utf8",
      timeout: 5000,
      maxBuffer: 16 * 1024 * 1024,
    }),
  );
}
function pick(nodes) {
  if (!process.stdin.isTTY)
    throw new Error(
      "Pass an app name or node ID, or run in a terminal for the picker.",
    );
  const result = spawnSync(
    "fzf",
    [
      "--prompt=Share audio > ",
      "--delimiter=\t",
      "--with-nth=2..",
      "--header=Follow the selected app: all its streams/tabs are shared; Esc cancels",
    ],
    {
      input: nodes.map((node) => `${node.id}\t${label(node)}`).join("\n"),
      encoding: "utf8",
      stdio: ["pipe", "pipe", "inherit"],
    },
  );
  if (result.error)
    throw new Error(
      "The picker needs fzf. Install it or pass an app name/node ID instead.",
    );
  if ([1, 130].includes(result.status)) return null;
  if (result.status !== 0) throw new Error("Audio picker failed.");
  return nodes.find((node) => String(node.id) === result.stdout.split("\t")[0]);
}
export async function share(selected, { follow = true } = {}) {
  const identity = applicationKey(selected);
  if (follow && !identity)
    throw new Error(
      "This stream has no application identity. Use its numeric node ID to share only that stream.",
    );
  const app = clean(
    props(selected)["application.name"] ??
      props(selected)["application.process.binary"] ??
      selected.id,
  );
  const name = `screenshare_${randomUUID().replaceAll("-", "")}`;
  const description = `Screenshare audio (${clean(props(selected)["application.name"] ?? props(selected)["node.name"] ?? selected.id)})`;
  let stopping = false;
  const stop = () => {
    stopping = true;
  };
  for (const signal of ["SIGINT", "SIGTERM", "SIGHUP"])
    process.on(signal, stop);
  const child = spawn(
    "pw-loopback",
    [
      "--name",
      name,
      "--channels",
      "2",
      "--capture-props",
      JSON.stringify({
        "node.name": `${name}_capture`,
        "node.description": "Screenshare capture",
        "node.autoconnect": false,
      }),
      "--playback-props",
      JSON.stringify({
        "media.class": "Audio/Source",
        "node.name": `${name}_audio`,
        "node.description": description,
      }),
    ],
    { stdio: ["ignore", "ignore", "inherit"] },
  );
  let childError;
  child.on("error", (error) => {
    childError = error;
  });
  const exited = new Promise((resolve) => child.once("close", resolve));
  let announced = false;
  let connected;
  let everConnected = false;
  let deadline = Date.now() + 5000;
  const failures = new Map();
  try {
    while (!stopping) {
      if (childError) throw childError;
      if (child.exitCode !== null || child.signalCode !== null)
        throw new Error("PipeWire loopback exited unexpectedly.");
      const graph = dump();
      const sources = follow
        ? playbackNodes(graph).filter(
            (node) => applicationKey(node) === identity,
          )
        : [sameNode(graph, selected)].filter(Boolean);
      if (!follow && !sources.length) {
        console.log("Selected playback stream ended. Stopping audio sharing.");
        break;
      }
      const capture = graph.find(
        (object) =>
          object.type === "PipeWire:Interface:Node" &&
          props(object)["node.name"] === `${name}_capture`,
      );
      if (!capture) {
        if (Date.now() > deadline)
          throw new Error("The virtual input did not become available.");
        await sleep(500);
        continue;
      }
      deadline = Date.now() + 5000;
      if (!announced) {
        console.log(
          `${follow ? `Following ${app}: all of this application's streams/tabs are shared.` : `Sharing only: ${label(selected)}`}\nIn the website, list audio inputs and select: ${description}\nExisting speaker connections are unchanged. Ctrl+C stops sharing.`,
        );
        announced = true;
      }
      const serials = new Set(
        sources.map((source) => props(source)["object.serial"]),
      );
      for (const serial of failures.keys())
        if (!serials.has(serial)) failures.delete(serial);
      let attached = 0;
      for (const source of sources) {
        const serial = props(source)["object.serial"];
        const pairs = routes(graph, source, capture);
        if (!pairs.length) {
          failures.delete(serial);
          continue;
        }
        try {
          for (const [output, input] of pairs) {
            const linked = graph.some(
              (object) =>
                object.type === "PipeWire:Interface:Link" &&
                object.info["output-port-id"] === output &&
                object.info["input-port-id"] === input &&
                object.info.state !== "error",
            );
            if (!linked)
              execFileSync(
                "pw-link",
                ["--wait", String(output), String(input)],
                {
                  timeout: 5000,
                  stdio: ["ignore", "ignore", "pipe"],
                },
              );
          }
          failures.delete(serial);
          attached++;
        } catch (error) {
          // Streams can vanish between the graph snapshot and pw-link. Retry a fresh graph.
          if (!failures.has(serial)) failures.set(serial, Date.now());
          if (Date.now() - failures.get(serial) >= 5000) throw error;
        }
      }
      if (Boolean(attached) !== connected) {
        if (attached) {
          console.log(
            `${everConnected ? "Reconnected" : "Sharing"}: ${app} audio.`,
          );
          everConnected = true;
        } else console.log(`Waiting for ${app} audio…`);
        connected = Boolean(attached);
      }
      await sleep(500);
    }
  } finally {
    // The links terminate at our private node, so removing it removes only our routes.
    child.kill("SIGTERM");
    const force = setTimeout(() => child.kill("SIGKILL"), 2000);
    await exited;
    clearTimeout(force);
    for (const signal of ["SIGINT", "SIGTERM", "SIGHUP"])
      process.off(signal, stop);
  }
}
async function main(args) {
  if (args[0] === "--") args = args.slice(1);
  if (args.includes("--help") || args.includes("-h")) {
    console.log(
      "Usage: share-audio.js [--list | APP_OR_NODE_ID]\n\nNo argument opens an fzf picker. Names/picker follow one application: ALL its streams/tabs are shared.\nThe virtual input stays alive between tracks and reconnects automatically.\nNumeric node IDs share only that exact stream and stop when it ends.\nStart audio in the app before selecting it. Supports mono/stereo; keeps speaker connections.\nCtrl+C removes the virtual input.\nRequires Node.js, pw-dump, pw-link, pw-loopback, and fzf for the picker.",
    );
    return;
  }
  if (args.length > 1 || (args[0]?.startsWith("-") && args[0] !== "--list"))
    throw new Error("Use --help for usage; quote app names containing spaces.");
  const nodes = playbackNodes(dump());
  if (args[0] === "--list") {
    console.log(nodes.map((node) => `${node.id}\t${label(node)}`).join("\n"));
    return;
  }
  if (!nodes.length)
    throw new Error(
      "No playback streams found. Start audio in the game first.",
    );
  const selected = args.length ? selectNode(nodes, args[0]) : pick(nodes);
  if (selected) await share(selected, { follow: !/^\d+$/.test(args[0] ?? "") });
}
if (
  process.argv[1] &&
  realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  main(process.argv.slice(2)).catch((error) => {
    console.error(`share-audio: ${error.message}`);
    process.exitCode = 1;
  });
}

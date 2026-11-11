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
  if (matches.length !== 1)
    throw new Error(
      matches.length
        ? `More than one stream matches. Use a node ID:\n${matches.map((node) => `${node.id}\t${label(node)}`).join("\n")}`
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
      "--header=Select one playback stream; Esc cancels",
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
export async function share(selected) {
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
  let ready = false;
  let deadline = Date.now() + 5000;
  try {
    while (!stopping) {
      if (childError) throw childError;
      if (child.exitCode !== null || child.signalCode !== null)
        throw new Error("PipeWire loopback exited unexpectedly.");
      const graph = dump();
      if (!sameNode(graph, selected)) {
        console.log("Selected playback stream ended. Stopping audio sharing.");
        break;
      }
      const capture = graph.find(
        (object) =>
          object.type === "PipeWire:Interface:Node" &&
          props(object)["node.name"] === `${name}_capture`,
      );
      const pairs = capture ? routes(graph, selected, capture) : [];
      if (pairs.length) {
        for (const [output, input] of pairs) {
          const linked = graph.some(
            (object) =>
              object.type === "PipeWire:Interface:Link" &&
              object.info["output-port-id"] === output &&
              object.info["input-port-id"] === input &&
              object.info.state !== "error",
          );
          if (!linked)
            execFileSync("pw-link", ["--wait", String(output), String(input)], {
              timeout: 5000,
              stdio: ["ignore", "ignore", "pipe"],
            });
        }
        deadline = Date.now() + 5000;
        if (!ready) {
          console.log(
            `Sharing: ${label(selected)}\nIn the website, list audio inputs and select: ${description}\nExisting speaker connections are unchanged. Ctrl+C stops sharing.`,
          );
          ready = true;
        }
      } else if (Date.now() > deadline)
        throw new Error("Audio ports did not become available.");
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
  if (args.includes("--help") || args.includes("-h")) {
    console.log(
      "Usage: share-audio.js [--list | APP_OR_NODE_ID]\n\nNo argument opens an fzf picker. Name matches must identify one playback stream.\nSupports mono/stereo; keeps speaker connections. Ctrl+C removes the virtual input.\nIf the app recreates its playback stream, run this command again.\nRequires Node.js, pw-dump, pw-link, pw-loopback, and fzf for the picker.",
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
  if (selected) await share(selected);
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

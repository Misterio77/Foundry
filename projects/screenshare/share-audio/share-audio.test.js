import assert from "node:assert/strict";
import test from "node:test";
import { spawn } from "node:child_process";
import { mkdtemp, readFile, writeFile, rename, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { setTimeout as sleep } from "node:timers/promises";
import {
  applicationKey,
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
  assert.equal(selectNode([game, node(45, "Hollow Knight")], "knight"), game);
  assert.throws(
    () => selectNode([game, node(45, "Knight Online")], "knight"),
    /More than one application/,
  );
});

test("application identity ignores stream titles and process IDs, not app boundaries", () => {
  const first = node(42, "Firefox");
  const second = node(43, "Firefox");
  first.info.props["application.process.id"] = 100;
  second.info.props["application.process.id"] = 200;
  first.info.props["media.name"] = "Video one";
  second.info.props["media.name"] = "Video two";
  assert.equal(applicationKey(first), applicationKey(second));
  assert.notEqual(
    applicationKey(first),
    applicationKey(node(44, "Firefox Nightly")),
  );
  second.info.props["application.process.binary"] = "different-app";
  assert.notEqual(applicationKey(first), applicationKey(second));
  assert.throws(
    () => selectNode([first, second], "firefox"),
    /More than one application/,
  );
  assert.equal(applicationKey({}), undefined);
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

function streamGraph(...nodes) {
  return nodes.flatMap((source) => [
    source,
    port(source.id * 10, source, "FL", "out"),
    port(source.id * 10 + 1, source, "FR", "out"),
  ]);
}

async function runningHelper(t, args, graph) {
  const dir = await mkdtemp(join(tmpdir(), "share-audio-test-"));
  let child;
  let exited;
  t.after(async () => {
    if (child) {
      child.kill("SIGTERM");
      await exited;
    }
    await rm(dir, { recursive: true, force: true });
  });
  const graphFile = join(dir, "graph.json");
  const setGraph = async (next) => {
    await writeFile(`${graphFile}.next`, JSON.stringify(next));
    await rename(`${graphFile}.next`, graphFile);
  };
  await setGraph(graph);
  const fake = `#!${process.execPath}
import { readFileSync, writeFileSync, appendFileSync, existsSync, unlinkSync } from 'node:fs';
import { basename, join } from 'node:path';
const file = name => join(process.env.FAKE_PIPEWIRE, name);
const read = name => JSON.parse(readFileSync(file(name), 'utf8'));
const graph = read('graph.json');
const tool = basename(process.argv[1]);
if (tool === 'pw-loopback') {
  const props = JSON.parse(process.argv[process.argv.indexOf('--capture-props') + 1]);
  writeFileSync(file('loopback.json'), JSON.stringify(props));
  appendFileSync(file('starts'), 'started\\n');
  process.on('SIGTERM', () => { writeFileSync(file('stopped'), 'yes'); process.exit(0); });
  setInterval(() => {}, 1000);
} else if (tool === 'pw-dump') {
  if (existsSync(file('loopback.json'))) {
    graph.push({id:9000, type:'PipeWire:Interface:Node', info:{props:read('loopback.json')}});
    for (const [id, channel] of [[9001,'FL'],[9002,'FR']]) graph.push({id, type:'PipeWire:Interface:Port', info:{props:{'node.id':9000,'port.direction':'in','audio.channel':channel}}});
  }
  if (existsSync(file('links'))) {
    const links = readFileSync(file('links'), 'utf8').trim().split('\\n').filter(Boolean).map(JSON.parse);
    for (const [output, input] of links) if (graph.some(o => o.id === output)) graph.push({type:'PipeWire:Interface:Link',info:{'output-port-id':output,'input-port-id':input,state:'active'}});
  }
  console.log(JSON.stringify(graph));
} else if (tool === 'pw-link') {
  if (existsSync(file('fail-once'))) { unlinkSync(file('fail-once')); process.exit(1); }
  const [output, input] = process.argv.slice(-2).map(Number);
  if (!graph.some(o => o.id === output)) process.exit(1);
  appendFileSync(file('links'), JSON.stringify([output,input]) + '\\n');
}
`;
  for (const tool of ["pw-loopback", "pw-dump", "pw-link"])
    await writeFile(join(dir, tool), fake, { mode: 0o755 });
  child = spawn(
    process.execPath,
    [new URL("./share-audio.js", import.meta.url).pathname, ...args],
    {
      env: {
        ...process.env,
        PATH: `${dir}:${process.env.PATH}`,
        FAKE_PIPEWIRE: dir,
      },
      stdio: ["ignore", "pipe", "pipe"],
    },
  );
  let output = "";
  child.stdout.on("data", (chunk) => {
    output += chunk;
  });
  child.stderr.on("data", (chunk) => {
    output += chunk;
  });
  exited = new Promise((resolve) =>
    child.once("exit", (code, signal) => resolve({ code, signal })),
  );
  const text = async (name) =>
    readFile(join(dir, name), "utf8").catch((error) => {
      if (error.code === "ENOENT") return "";
      throw error;
    });
  const waitFor = async (predicate) => {
    const deadline = Date.now() + 8000;
    while (!(await predicate())) {
      if (
        Date.now() > deadline ||
        child.exitCode !== null ||
        child.signalCode !== null
      )
        assert.fail(`Helper did not reach expected state: ${output}`);
      await sleep(20);
    }
  };
  return {
    child,
    exited,
    setGraph,
    text,
    waitFor,
    output: () => output,
    failLink: () => writeFile(join(dir, "fail-once"), "yes"),
  };
}

test(
  "follows all app streams across silence and recreation without restarting the virtual input",
  { timeout: 20000 },
  async (t) => {
    const app = await runningHelper(
      t,
      ["--", "Firefox"],
      streamGraph(node(42, "Firefox"), node(43, "Firefox")),
    );
    await app.waitFor(() => app.output().includes("Sharing: Firefox audio."));
    assert.match(app.output(), /all of this application's streams\/tabs/);
    assert.equal((await app.text("links")).trim().split("\n").length, 4);
    const virtualInput = await app.text("loopback.json");

    await app.setGraph(
      streamGraph(node(42, "Unrelated app", 200), node(44, "Firefox Nightly")),
    );
    await app.waitFor(() => app.output().includes("Waiting for Firefox audio"));
    const replacement = node(45, "Firefox", 300);
    replacement.info.props["media.name"] = "Next YouTube video";
    await app.setGraph(streamGraph(replacement));
    await app.waitFor(() =>
      app.output().includes("Reconnected: Firefox audio."),
    );
    assert.match(await app.text("links"), /\[450,9001\]/);
    assert.doesNotMatch(await app.text("links"), /\[440,/);

    await app.failLink();
    await app.setGraph(streamGraph(replacement, node(46, "Firefox", 301)));
    await app.waitFor(async () =>
      (await app.text("links")).includes("[461,9002]"),
    );
    assert.equal(await app.text("loopback.json"), virtualInput);
    assert.equal(await app.text("starts"), "started\n");
    assert.equal(app.output().match(/Waiting for Firefox audio/g).length, 1);
    app.child.kill("SIGINT");
    assert.deepEqual(await app.exited, { code: 0, signal: null });
    assert.equal(await app.text("stopped"), "yes");
  },
);

test(
  "exact numeric selection stops on ID reuse rather than following another stream",
  { timeout: 15000 },
  async (t) => {
    const app = await runningHelper(
      t,
      ["--", "42"],
      streamGraph(node(42, "Firefox", 100), node(43, "Firefox", 101)),
    );
    await app.waitFor(() => app.output().includes("Sharing: Firefox audio."));
    assert.equal((await app.text("links")).trim().split("\n").length, 2);
    await app.setGraph(
      streamGraph(node(42, "Firefox", 200), node(43, "Firefox", 101)),
    );
    assert.deepEqual(await app.exited, { code: 0, signal: null });
    assert.match(app.output(), /Selected playback stream ended/);
    assert.equal(await app.text("stopped"), "yes");
  },
);

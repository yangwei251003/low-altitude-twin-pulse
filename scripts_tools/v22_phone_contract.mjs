/**
 * V2.2 phone contract: executes the unmodified production app.js in a Node VM.
 * Run: node scripts_tools/v22_phone_contract.mjs
 * No packages, sockets, Godot process, browser window, or physical phone required.
 * DOM/pointer capture/WebSocket/time are deterministic fakes. GDScript checks are
 * explicitly source contracts, NOT engine or network execution evidence.
 * All results go to stdout; this runner writes no artifacts or application data.
 */
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {fileURLToPath} from "node:url";
import path from "node:path";
import vm from "node:vm";
import {createHash, webcrypto} from "node:crypto";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const files = {
  app: "phone/app.js", html: "phone/index.html",
  server: "scripts/v2/phone_server.gd", pilot: "scripts/v2/pilot_input.gd",
};
const source = Object.fromEntries(Object.entries(files).map(([key, name]) =>
  [key, readFileSync(path.join(root, name), "utf8")]));
const results = [];
const near = (actual, expected, message) => assert.ok(Math.abs(actual - expected) < 1e-9,
  `${message}: expected ${expected}, got ${actual}`);
const plain = value => JSON.parse(JSON.stringify(value));
function check(name, test, kind = "production_client_vm") {
  try { test(); results.push({name, kind, passed: true}); }
  catch (error) { results.push({name, kind, passed: false, error: error.message}); }
}
function scenario(name, run) {
  try { run(); }
  catch (error) { results.push({name: `${name}: harness/setup`, kind: "harness", passed: false, error: error.stack}); }
}

class Target {
  constructor(id = "") {
    this.id = id; this.listeners = new Map(); this.attributes = {}; this.captures = new Set();
    this.style = {setProperty(key, value) {this[key] = value;}};
    const classes = new Set();
    this.classList = {add: key => classes.add(key), remove: key => classes.delete(key),
      contains: key => classes.has(key), toggle(key, force) {
        const next = force === undefined ? !classes.has(key) : !!force;
        next ? classes.add(key) : classes.delete(key); return next;
      }};
    this.clientWidth = 168; this.value = ""; this.textContent = "";
    this.open = false; this.disabled = false; this.checked = false;
    this.rect = {left: id === "right-stick" ? 400 : 0, top: 0, width: 168, height: 168};
    this.thumb = {style: {}};
  }
  addEventListener(type, listener) {
    if (!this.listeners.has(type)) this.listeners.set(type, []);
    this.listeners.get(type).push(listener);
  }
  dispatch(type, detail = {}) {
    const event = {type, target: this, currentTarget: this, defaultPrevented: false,
      preventDefault() {this.defaultPrevented = true;}, ...detail};
    for (const listener of this.listeners.get(type) || []) listener(event);
    return event;
  }
  setAttribute(key, value) {this.attributes[key] = String(value);}
  getAttribute(key) {return this.attributes[key] ?? null;}
  querySelector(selector) {assert.equal(selector, ".thumb"); return this.thumb;}
  getBoundingClientRect() {return this.rect;}
  setPointerCapture(id) {this.captures.add(id);}
  hasPointerCapture(id) {return this.captures.has(id);}
  releasePointerCapture(id) {
    if (this.captures.delete(id)) this.dispatch("lostpointercapture", {pointerId: id});
  }
  showModal() {this.open = true;}
  close(value) {this.open = false; this.returnValue = value; this.dispatch("close");}
}

function client(mode = "assisted", resumeThrottle = 0) {
  const elements = new Map([...source.html.matchAll(/\bid="([^"]+)"/g)].map(match =>
    [match[1], new Target(match[1])]));
  const element = id => {assert.ok(elements.has(id), `Missing DOM node ${id}`); return elements.get(id);};
  const document = new Target("document");
  document.getElementById = element;
  document.hidden = false;
  document.documentElement = new Target("html");
  document.documentElement.dataset = {wsPort: "9999", session: "isolated-vm-session"};
  const window = new Target("window");
  const landscape = new Target("landscape"); landscape.matches = true;
  let now = 1000, raf;
  const sockets = [];
  class Socket {
    static OPEN = 1;
    constructor(url, protocol) {
      this.url = url; this.protocol = protocol; this.readyState = Socket.OPEN;
      this.bufferedAmount = 0; this.sent = []; sockets.push(this);
    }
    send(message) {this.sent.push(JSON.parse(message));}
    incoming(message) {this.onmessage?.({data: JSON.stringify(message)});}
    close() {this.readyState = 3; this.onclose?.();}
  }
  const sandbox = {document, window, matchMedia: () => landscape, WebSocket: Socket,
    location: {hostname: "127.0.0.1"}, crypto: webcrypto,
    performance: {now: () => now}, localStorage: {getItem: () => null, setItem() {}},
    requestAnimationFrame: callback => {raf = callback;}, console};
  vm.runInNewContext(source.app, sandbox, {filename: files.app, timeout: 1000});
  element("pair-code").value = "123456";
  element("pair-form").dispatch("submit");
  assert.equal(sockets.length, 1);
  const socket = sockets[0];
  socket.incoming({type: "hello", protocol: 2});
  socket.incoming({type: "paired", token: "f".repeat(64), control_epoch: 1});
  let state = "TakingControl", epoch = 1, target = resumeThrottle;
  function status(options = {}) {
    state = options.state ?? state; epoch = options.epoch ?? epoch;
    mode = options.mode ?? mode; target = options.target ?? target;
    socket.incoming({type: "status", state, control_epoch: epoch,
      lease_nonce: `lease-${epoch}`, reason: state === "Active" ? "" : "CENTER_STICKS",
      rtt_ms: 8, telemetry: {mode, resume_throttle: target}});
  }
  status();
  element("resume").dispatch("click");
  status({state: "Active"});
  function frame() {
    const before = socket.sent.length;
    now += 40; const callback = raf; raf = null; callback(now);
    const sent = socket.sent.slice(before).filter(message => message.type === "input");
    assert.equal(sent.length, 1, "Expected exactly one outgoing input frame");
    return plain(sent[0].frame);
  }
  function pointer(name, type, pointerId, x = 0, y = 0) {
    const node = element(name + "-stick"), rect = node.rect;
    return node.dispatch(type, {pointerId,
      clientX: rect.left + rect.width / 2 + x * (rect.width / 2 - 20),
      clientY: rect.top + rect.height / 2 - y * (rect.height / 2 - 20)});
  }
  return {element, socket, status, frame, pointer, document, window, landscape,
    click: id => element(id).dispatch("click"),
    ack: frame => socket.incoming({type: "ack", seq: frame.seq,
      edge_ack: Math.max(0, ...frame.edges.map(edge => edge.id))}),
    jumpTime: elapsed => {now += elapsed;},
    mode: () => mode, target: () => target,
  };
}

const axesNames = JSON.parse(source.server.match(/const AXES\s*:?=\s*(\[[^\n]+\])/)[1]);
const heldNames = JSON.parse(source.server.match(/const HELD\s*:?=\s*(\[[^\n]+\])/)[1]);
const edgeNames = JSON.parse(source.server.match(/const EDGES\s*:?=\s*(\[[^\n]+\])/)[1]);
function schemaCompatible(frame) {
  assert.equal(frame.schema, 2); assert.equal(frame.context, "flight");
  assert.equal(typeof frame.neutral, "boolean");
  for (const key of ["seq", "sample_ms", "control_epoch"]) assert.ok(Number.isSafeInteger(frame[key]) && frame[key] >= 0);
  assert.deepEqual(Object.keys(frame.axes).sort(), [...axesNames].sort());
  for (const value of Object.values(frame.axes)) assert.ok(Number.isFinite(value) && Math.abs(value) <= 1);
  assert.ok(frame.held.length <= 16 && frame.held.every(action => heldNames.includes(action)));
  assert.ok(frame.edges.length <= 8 && frame.edges.every(edge => edgeNames.includes(edge.action) &&
    edge.kind === "pressed" && Number.isSafeInteger(edge.id) && edge.id >= 0));
}
// Independent acceptance oracle for documented manual resume tolerance. This is
// not a translation/runtime execution of the production GDScript server.
function manualTargetMatches(frame, target) {
  return !frame.neutral && frame.held.length === 0 &&
    ["left_x", "right_x", "right_y"].every(axis => Math.abs(frame.axes[axis]) <= .001) &&
    Math.abs((frame.axes.left_y + 1) * .5 - target) <= .06;
}

scenario("four axes and independent touches", () => {
  const c = client();
  c.pointer("left", "pointerdown", 11, .6, .4);
  c.pointer("right", "pointerdown", 22, -.5, .7);
  const both = c.frame();
  check("Four axes travel in one authenticated schema-2 frame", () => {
    schemaCompatible(both);
    assert.ok(both.axes.left_x > 0 && both.axes.left_y > 0 && both.axes.right_x < 0 && both.axes.right_y > 0);
    assert.equal(c.socket.sent.at(-1).token.length, 64);
  });
  check("Two different touches are captured independently", () => {
    assert.ok(c.element("left-stick").hasPointerCapture(11));
    assert.ok(c.element("right-stick").hasPointerCapture(22));
  });
  c.pointer("left", "pointerdown", 33, -1, -1);
  c.pointer("left", "pointermove", 33, -1, -1);
  c.pointer("left", "pointerup", 33);
  const ignored = c.frame();
  check("Unowned third touch cannot replace, move or release the left stick", () => assert.deepEqual(ignored.axes, both.axes));
  c.pointer("left", "pointerup", 11);
  const release = c.frame();
  check("Assisted left release centers only left axes and keeps right touch", () => {
    assert.equal(release.axes.left_x, 0); assert.equal(release.axes.left_y, 0);
    near(release.axes.right_x, both.axes.right_x, "right roll");
    near(release.axes.right_y, both.axes.right_y, "right pitch");
    assert.ok(c.element("right-stick").hasPointerCapture(22));
  });
  check("Normal pointer release/lost-capture event does not suspend", () => assert.equal(c.socket.sent.filter(m => m.type === "suspend").length, 0));
  c.pointer("right", "pointerup", 22);
  check("Assisted right release centers all four axes", () => assert.ok(Object.values(c.frame().axes).every(value => value === 0)));
});

scenario("manual stick hold", () => {
  const c = client("manual_throttle", .2);
  c.pointer("left", "pointerdown", 1, .8, .5);
  c.pointer("right", "pointerdown", 2, -.6, .4);
  const held = c.frame();
  c.pointer("left", "pointerup", 1);
  const released = c.frame();
  check("Manual left release retains 75% throttle while yaw recenters", () => {
    near(released.axes.left_y, .5, "retained manual Y"); assert.equal(released.axes.left_x, 0);
    assert.ok(held.axes.left_x > 0); assert.equal(released.neutral, false);
  });
  check("Manual throttle release leaves right roll/pitch untouched", () => {
    near(released.axes.right_x, held.axes.right_x, "roll"); near(released.axes.right_y, held.axes.right_y, "pitch");
  });
  c.pointer("right", "pointerup", 2);
  c.pointer("left", "pointerdown", 3, 1, 1);
  const corner = c.frame();
  check("Manual yaw keeps full range at full throttle", () => {near(corner.axes.left_x, 1, "yaw"); near(corner.axes.left_y, 1, "throttle");});
  c.pointer("left", "pointermove", 3, 4, -4);
  check("Manual pointer outside stick clamps throttle and yaw to legal limits", () => {
    const frame = c.frame(); schemaCompatible(frame); near(frame.axes.left_x, 1, "yaw clamp"); near(frame.axes.left_y, -1, "throttle clamp");
  });
});

scenario("camera edge isolation", () => {
  const c = client("manual_throttle", .65);
  c.pointer("left", "pointerdown", 1, .4, .3);
  c.pointer("right", "pointerdown", 2, -.3, .6);
  c.click("fire");
  const before = c.frame();
  for (const id of ["zoom-in", "zoom-out", "map", "recenter"]) c.click(id);
  const edges = c.frame();
  check("Zoom/map/recenter affect edges only, preserving all axes and held flight actions", () => {
    assert.deepEqual(edges.axes, before.axes); assert.deepEqual(edges.held, before.held);
    assert.deepEqual(edges.edges.map(edge => edge.action), ["zoom_in", "zoom_out", "map", "recenter"]);
    schemaCompatible(edges);
  });
  const repeat = c.frame();
  check("Unacknowledged camera edges retransmit with identical IDs", () => assert.deepEqual(repeat.edges, edges.edges));
  c.ack(repeat);
  check("Acknowledged camera edges do not repeat", () => assert.deepEqual(c.frame().edges, []));
  for (let index = 0; index < 12; index++) c.click("zoom-in");
  check("Queued edge burst is bounded by protocol limit of eight", () => {const f = c.frame(); assert.equal(f.edges.length, 8); schemaCompatible(f);});
  c.click("pause");
  for (const id of ["zoom-in", "zoom-out", "map", "recenter", "fire", "utility"]) c.click(id);
  check("Paused camera/action buttons emit no flight edges or held actions", () => {
    const frame = c.frame(); assert.deepEqual(frame.edges, []); assert.deepEqual(frame.held, []);
    assert.equal(frame.axes.left_x, 0); assert.equal(frame.axes.right_x, 0); assert.equal(frame.axes.right_y, 0);
  });
});

scenario("independent ability and guard", () => {
  const c = client();
  c.pointer("left", "pointerdown", 1, .5, .4); c.pointer("right", "pointerdown", 2, -.6, .4);
  const before = c.frame();
  c.click("utility"); c.click("target");
  const sent = c.frame();
  check("Ability and guard produce distinct authenticated edges without changing sticks", () => {
    schemaCompatible(sent); assert.deepEqual(sent.edges.map(e => e.action), ["utility", "target"]);
    assert.deepEqual(sent.axes, before.axes); assert.deepEqual(sent.held, before.held);
  });
  check("Ability/guard edges retransmit identically until acknowledged", () => assert.deepEqual(c.frame().edges, sent.edges));
  c.ack(sent);
  check("Ability/guard edges clear on acknowledgment", () => assert.deepEqual(c.frame().edges, []));
  c.click("pause"); c.click("utility"); c.click("target");
  check("Ability and guard are inhibited while paused", () => assert.deepEqual(c.frame().edges, []));
});

scenario("manual server pause target", () => {
  const c = client("manual_throttle", .2);
  c.pointer("left", "pointerdown", 1, .6, .3); c.pointer("left", "pointerup", 1);
  c.status({state: "Stale", epoch: 2, target: .65});
  const paused = c.frame();
  check("Epoch/status transition uses the NEW authoritative resume throttle", () => {
    near(paused.axes.left_y, .3, "65% resume target"); assert.ok(manualTargetMatches(paused, .65));
  });
  check("Pause clears directions/edges while keeping matching frame non-neutral", () => {
    assert.equal(paused.axes.left_x, 0); assert.equal(paused.axes.right_x, 0); assert.equal(paused.axes.right_y, 0);
    assert.deepEqual(paused.held, []); assert.deepEqual(paused.edges, []); assert.equal(paused.neutral, false);
  });
  c.click("resume");
  const afterResume = c.frame();
  check("Manual resume request does not erase chosen throttle", () => {
    assert.equal(c.socket.sent.filter(message => message.type === "resume").length, 2);
    near(afterResume.axes.left_y, paused.axes.left_y, "resume does not reset Y");
  });
});

scenario("manual local pause followed by late host telemetry", () => {
  const c = client("manual_throttle", .2);
  c.pointer("left", "pointerdown", 1, .5, .3); c.pointer("left", "pointerup", 1); c.frame();
  c.click("pause");
  c.status({state: "Stale", epoch: 2, target: .2});
  c.status({state: "Stale", epoch: 2, target: .65});
  check("Late paused telemetry target change is reflected without a second epoch", () => {
    const frame = c.frame(); near(frame.axes.left_y, .3, "late 65% resume target"); assert.ok(manualTargetMatches(frame, .65));
  });
  c.pointer("left", "pointerdown", 3, 0, .4); c.pointer("left", "pointerup", 3);
  c.status({state: "Stale", epoch: 2, target: .65});
  check("Unchanged status preserves the user's manual matching adjustment", () => near(c.frame().axes.left_y, .4, "user matching Y"));
  c.pointer("right", "pointerdown", 4, 1, 1);
  check("Paused manual matching accepts only left stick, not right flight input", () => {
    const frame = c.frame(); assert.equal(frame.axes.right_x, 0); assert.equal(frame.axes.right_y, 0);
  });
});

scenario("mode change and interruptions", () => {
  const c = client();
  c.status({mode: "manual_throttle", target: .75});
  check("Entering manual mode initializes Y from server throttle target", () => near(c.frame().axes.left_y, .5, "mode target"));
  c.status({mode: "assisted"});
  check("Returning to assisted mode centers held throttle", () => assert.ok(Object.values(c.frame().axes).every(value => value === 0)));
  c.pointer("left", "pointerdown", 1, .6, .4); c.pointer("right", "pointerdown", 2, -.5, .6);
  c.click("fire"); c.click("map"); c.pointer("left", "pointercancel", 1);
  const canceled = c.frame();
  check("Touch cancellation releases both captures and clears axes/actions", () => {
    assert.ok(Object.values(canceled.axes).every(value => value === 0)); assert.equal(canceled.neutral, true);
    assert.deepEqual(canceled.held, []); assert.deepEqual(canceled.edges, []);
    assert.equal(c.element("left-stick").captures.size, 0); assert.equal(c.element("right-stick").captures.size, 0);
    assert.equal(c.socket.sent.filter(message => message.type === "suspend").length, 1);
  });
});

scenario("brake third touch", () => {
  const c = client();
  c.pointer("left", "pointerdown", 11, .5, .5); c.pointer("right", "pointerdown", 22, -.5, .5);
  const before = c.frame();
  c.element("brake").dispatch("pointerdown", {pointerId: 33});
  check("A third brake touch leaves both captured sticks unchanged", () => {
    const frame = c.frame(); assert.deepEqual(frame.axes, before.axes); assert.deepEqual(frame.held, ["brake"]);
  });
  c.element("brake").dispatch("pointerup", {pointerId: 44});
  check("Unowned pointer cannot release brake", () => assert.deepEqual(c.frame().held, ["brake"]));
  c.element("brake").dispatch("pointerup", {pointerId: 33});
  check("Brake release removes brake without suspending or clearing stick axes", () => {
    const frame = c.frame(); assert.deepEqual(frame.axes, before.axes); assert.deepEqual(frame.held, []);
    assert.equal(c.socket.sent.filter(message => message.type === "suspend").length, 0);
  });
});

scenario("visibility/orientation safety", () => {
  const c = client("manual_throttle", .65);
  c.landscape.matches = false; c.landscape.dispatch("change");
  check("Portrait blocks manual matching and sends neutral axes", () => {
    const frame = c.frame(); assert.equal(frame.neutral, true); assert.ok(Object.values(frame.axes).every(value => value === 0));
    assert.equal(c.element("resume").disabled, true);
  });
  c.document.hidden = true; c.document.dispatch("visibilitychange");
  check("Backgrounding closes transport and clears control credentials", () => {
    assert.equal(c.socket.readyState, 3); assert.equal(c.element("resume").disabled, true);
  });
});

// Structural contracts are separate from behavior above and do not imply Godot ran.
function gdFunction(text, name) {
  const match = text.match(new RegExp(`^func ${name}\\([^]*?(?=^func |$(?![^]))`, "m"));
  assert.ok(match, `Missing GDScript function ${name}`); return match[0];
}
check("Server and pilot share four-axis vocabulary", () => {
  assert.deepEqual(axesNames, ["left_x", "left_y", "right_x", "right_y"]);
  for (const axis of axesNames) assert.ok(source.pilot.includes(`"${axis}"`));
}, "gdscript_source_contract");
check("Camera actions are server edges and are excluded from held action whitelist", () => {
  for (const action of ["zoom_in", "zoom_out", "map", "recenter"]) {
    assert.ok(edgeNames.includes(action)); assert.ok(!heldNames.includes(action));
  }
}, "gdscript_source_contract");
check("Server resume gate requires fresh approved matching input", () => {
  const resume = gdFunction(source.server, "resume_control");
  for (const fragment of ["not _approved", "not _connected()", "not _neutral", "_last_input > TIMEOUT_MS"])
    assert.ok(resume.includes(fragment), fragment);
  const receive = gdFunction(source.server, "_receive_input");
  assert.match(receive, /manual_throttle/); assert.match(receive, /resume_throttle/); assert.match(receive, /<=\s*0\.06/);
  assert.match(receive, /not bool\(frame\.neutral\)/);
}, "gdscript_source_contract");
check("Pilot maps yaw/throttle to left and roll/pitch to right in body coordinates", () => {
  const command = gdFunction(source.pilot, "command");
  assert.match(command, /"body_relative"\s*:\s*true/);
  for (const [key, axis] of [["yaw", "left_x"], ["vertical", "left_y"], ["roll", "right_x"], ["pitch", "right_y"]])
    assert.match(command, new RegExp(`"${key}"\\s*:\\s*float\\(axes\\.${axis}\\)`));
  assert.match(command, /"edges"\s*:\s*actions/);
}, "gdscript_source_contract");
check("Pilot preserves throttle across clear/pause and separates edge deduplication", () => {
  const clear = gdFunction(source.pilot, "clear");
  assert.ok(!/\b(?:resume_)?throttle\s*=/.test(clear));
  const sample = gdFunction(source.pilot, "sample");
  assert.match(sample, /if active:/); assert.match(sample, /if not edge_ids\.has\(id\)/);
  assert.match(sample, /if active and mode == "manual_throttle"/);
}, "gdscript_source_contract");

for (const result of results) console.log(`${result.passed ? "PASS" : "FAIL"} [${result.kind}] ${result.name}${result.error ? `\n  ${result.error}` : ""}`);
const report = {
  passed: results.every(result => result.passed), checks: results.length,
  failed: results.filter(result => !result.passed),
  groups: Object.fromEntries([...new Set(results.map(result => result.kind))].map(kind =>
    [kind, {checks: results.filter(result => result.kind === kind).length,
      failed: results.filter(result => result.kind === kind && !result.passed).length}])),
  source_sha256: Object.fromEntries(Object.entries(files).map(([key, name]) =>
    [name, createHash("sha256").update(source[key]).digest("hex")])),
  evidence: "Unmodified production phone/app.js executed in Node VM with deterministic fake DOM/pointer capture and WebSocket. GDScript source contracts only.",
  not_tested: ["Godot server/pilot execution", "real TCP/WebSocket", "browser layout/event dispatch", "physical phone", "touch latency"],
};
console.log("V22_PHONE_CONTRACT " + JSON.stringify(report));
process.exitCode = report.passed ? 0 : 1;

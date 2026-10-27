/* Offline controller. Session credentials are intentionally kept in page memory. */
(() => {
  "use strict";
  function shapeStick(x, y, deadzone = .08, sensitivity = 1, expo = .25) {
    const length = Math.hypot(x, y);
    if (length <= deadzone || !Number.isFinite(length)) return {x: 0, y: 0};
    const radius = Math.min(1, (Math.min(length, 1) - deadzone) / (1 - deadzone));
    const curve = Math.min(1, ((1 - expo) * radius + expo * radius ** 3) * sensitivity);
    return {x: x / length * curve, y: y / length * curve};
  }
  function clearStick(sticks, name) { sticks[name].x = 0; sticks[name].y = 0; }
  if (typeof module !== "undefined") module.exports = {shapeStick, clearStick};
  if (typeof document === "undefined") return;

  const $ = id => document.getElementById(id);
  const sticks = {left: {x: 0, y: 0, pointer: null}, right: {x: 0, y: 0, pointer: null}};
  let preferences = {deadzone: .08, sensitivity: 1, rightSensitivity: 1, size: 84, swap: false};
  try { preferences = {...preferences, ...JSON.parse(localStorage.getItem("las-controller-settings") || "{}")}; } catch (_) {}
  preferences.deadzone = Math.max(.02, Math.min(.30, Number(preferences.deadzone) || .08));
  preferences.sensitivity = Math.max(.4, Math.min(1.5, Number(preferences.sensitivity) || 1));
  preferences.rightSensitivity = Math.max(.4, Math.min(1.5, Number(preferences.rightSensitivity) || 1));
  preferences.size = Math.max(72, Math.min(110, Number(preferences.size) || 84));
  preferences.swap = preferences.swap === true;
  let socket = null, token = "", lease = "", epoch = 0, seq = 0, edgeId = 0, edges = [];
  let state = "Stopped", lastStatus = 0, lastSend = 0, lastAck = 0, pairCode = "", autoFire = true;
  let interrupted = false, pendingPair = false, brakePointer = null;
  let controlMode = "assisted", resumeThrottle = 0;
  const held = new Set();
  const landscape = matchMedia("(orientation: landscape)");
  const names = {Stopped:"尚未连接",Listening:"等待配对",ConnectedIdle:"已连接 · 等待电脑确认",TakingControl:"回中后恢复控制",Active:"正在控制",Stale:"安全暂停",Disconnected:"连接中断"};
  const reasons = {CENTER_STICKS:"松开双杆，再恢复控制",COMPUTER_APPROVAL_REQUIRED:"请在电脑上确认接管",INPUT_STALE:"输入超时，已安全暂停",PHONE_INTERRUPTED:"触控中断，已安全暂停",PHONE_PAUSED:"已暂停",DISCONNECTED:"连接断开，请重新配对",CONTROL_BUSY:"已有手机连接，请在电脑切换",PAIR_COOLDOWN:"配对尝试过多，请等待 30 秒",PAIR_DENIED:"配对码错误或已过期",CENTER_STICKS_OR_COMPUTER_APPROVAL:"先在电脑确认，然后回中",PORTS_BUSY:"端口被占用",SEND_BACKLOG:"网络拥堵，已停止控制"};

  function send(message) {
    if (!socket || socket.readyState !== WebSocket.OPEN) return false;
    if (socket.bufferedAmount > 16384) { interrupt("网络拥堵，重新连接", true); return false; }
    socket.send(JSON.stringify(message)); return true;
  }
  function authenticated(type, extra = {}) { return send({type, token, ...extra}); }
  function showState(reason = "") {
    $("status").textContent = names[state] || state;
    $("reason").textContent = reasons[reason] || reason || (state === "Active" ? "" : "松开双杆后恢复");
    $("resume").disabled = !token || !landscape.matches || state === "ConnectedIdle" || state === "Active";
    $("resume").textContent = state === "Active" ? "控制中" : state === "ConnectedIdle" ? "等待电脑确认" : "恢复控制";
    $("pause").disabled = !token;
  }
  function resetControls() {
    for (const name of ["left", "right"]) {
      const stick = sticks[name], node = $(name + "-stick");
      const pointer = stick.pointer; stick.pointer = null; clearStick(sticks, name);
      if (name === "left" && controlMode === "manual_throttle") stick.y = resumeThrottle * 2 - 1;
      if (pointer !== null && node.hasPointerCapture?.(pointer)) node.releasePointerCapture(pointer);
      renderStick(name);
    }
    brakePointer = null; held.clear(); edges = []; renderButtons();
  }
  function interrupt(reason, disconnect = false) {
    resetControls();
    if (!interrupted && token && socket?.readyState === WebSocket.OPEN && socket.bufferedAmount <= 16384) {
      socket.send(JSON.stringify({type:"suspend", token}));
    }
    interrupted = true;
    if (token) state = "Stale";
    showState(reason);
    if (disconnect && socket) { socket.close(1000, "controller interrupted"); token = ""; lease = ""; }
  }
  function connect() {
    if (socket) { socket.onclose = null; socket.close(); }
    resetControls(); token = ""; lease = ""; epoch = 0; seq = 0; pendingPair = true;
    $("pair-note").textContent = "正在连接…";
    const url = "ws://" + location.hostname + ":" + document.documentElement.dataset.wsPort + "/control";
    socket = new WebSocket(url, "las-v2");
    socket.onmessage = event => {
      let message; try { message = JSON.parse(event.data); } catch (_) { interrupt("通信格式错误", true); return; }
      if (message.type === "hello") {
        const nonce = new Uint8Array(16); crypto.getRandomValues(nonce);
        send({type:"hello",protocol:2,session_id:document.documentElement.dataset.session,page_nonce:Array.from(nonce,b=>b.toString(16).padStart(2,"0")).join("")});
        if (pendingPair) { pendingPair = false; send({type:"pair",code:pairCode,requested_role:"controller"}); }
      } else if (message.type === "paired") {
        token = message.token; epoch = message.control_epoch; seq = 0; edgeId = 0; edges = [];
        state = "ConnectedIdle"; interrupted = false; lastAck = performance.now(); lastStatus = lastAck;
        $("pair-panel").classList.add("hidden"); $("pair-code").value = ""; pairCode = ""; showState("COMPUTER_APPROVAL_REQUIRED");
      } else if (message.type === "status") {
        const t = message.telemetry || {};
        const modeChanged = controlMode !== (t.mode || "assisted");
        const oldTarget = resumeThrottle;
        controlMode = t.mode || "assisted";
        if (Number.isFinite(t.resume_throttle)) resumeThrottle = Math.max(0, Math.min(1, t.resume_throttle));
        if (message.control_epoch !== epoch) { epoch = message.control_epoch; seq = 0; edgeId = 0; resetControls(); }
        lease = message.lease_nonce; lastStatus = performance.now();
        const wasActive = state === "Active";
        state = message.state;
        if (wasActive && state !== "Active") resetControls();
        if (state === "Active") interrupted = false;
        $("rtt").textContent = "RTT " + (message.rtt_ms >= 0 ? Math.round(message.rtt_ms) + " ms" : "--");
        if (Number.isFinite(t.altitude_agl_m)) $("altitude").textContent = "高度 " + t.altitude_agl_m.toFixed(1) + " m";
        if (Number.isFinite(t.health)) $("health").textContent = "机况 " + Math.round(t.health);
        if (Number.isFinite(t.heat)) $("heat").textContent = "热量 " + Math.round(t.heat);
        if (typeof t.auto_fire === "boolean") autoFire = t.auto_fire;
        if (modeChanged) resetControls();
        else if (state !== "Active" && controlMode === "manual_throttle" && sticks.left.pointer === null && oldTarget !== resumeThrottle) {
          sticks.left.y = resumeThrottle * 2 - 1; sticks.left.x = 0; renderStick("left");
        }
        $("mode").textContent = controlMode === "manual_throttle" ? "手动油门 " + Math.round((sticks.left.y + 1) * 50) + "%" : "辅助 Mode 2";
        $("left-label").textContent = controlMode === "manual_throttle" ? "油门保持 · 偏航" : "升降 · 偏航";
        $("right-label").textContent = "横滚 · 俯仰";
        $("tutorial").textContent = t.tutorial_text || "";
        $("left-stick").classList.toggle("tutorial-active", /lift|hover|yaw|land/.test(t.tutorial_step || ""));
        $("right-stick").classList.toggle("tutorial-active", /forward|strafe|brake/.test(t.tutorial_step || ""));
        showState(message.reason); renderButtons();
      } else if (message.type === "ack") {
        lastAck = performance.now(); edges = edges.filter(edge => edge.id > message.edge_ack);
      } else if (message.type === "ping") {
        if (token) authenticated("pong", {nonce:message.nonce});
      } else if (message.type === "error") {
        const detail = reasons[message.code] || "连接状态异常，请在电脑检查";
        $("pair-note").textContent = detail; showState(detail);
      }
    };
    socket.onerror = () => { $("pair-note").textContent = "连接失败：确认同一 Wi-Fi，并检查电脑上的地址和防火墙提示"; };
    socket.onclose = () => {
      resetControls(); token = ""; lease = ""; state = "Disconnected";
      $("pair-panel").classList.remove("hidden"); $("pair-note").textContent = "连接已断开，请使用电脑上的新配对码"; showState("DISCONNECTED");
    };
  }
  function renderStick(name) {
    const node = $(name + "-stick"), stick = sticks[name];
    const travel = Math.max(30, node.clientWidth / 2 - 28);
    node.querySelector(".thumb").style.transform = `translate(${stick.x * travel}px,${-stick.y * travel}px)`;
    node.classList.toggle("engaged", stick.pointer !== null);
    node.setAttribute("aria-valuenow", stick.y.toFixed(2));
  }
  function updateStick(name, event) {
    const node = $(name + "-stick"), rect = node.getBoundingClientRect();
    const sensitivity = name === "left" ? preferences.sensitivity : preferences.rightSensitivity;
    const shaped = shapeStick((event.clientX - rect.left - rect.width / 2) / (rect.width / 2 - 20), -(event.clientY - rect.top - rect.height / 2) / (rect.height / 2 - 20), preferences.deadzone, sensitivity);
    if (name === "left" && controlMode === "manual_throttle") {
      shaped.x = shapeStick((event.clientX - rect.left - rect.width / 2) / (rect.width / 2 - 20), 0, preferences.deadzone, sensitivity).x;
      shaped.y = Math.max(-1, Math.min(1, -(event.clientY - rect.top - rect.height / 2) / (rect.height / 2 - 20)));
    }
    Object.assign(sticks[name], shaped); renderStick(name);
  }
  for (const name of ["left", "right"]) {
    const node = $(name + "-stick");
    node.addEventListener("pointerdown", event => {
      if ((state !== "Active" && !(token && controlMode === "manual_throttle" && name === "left")) || sticks[name].pointer !== null || !landscape.matches) return;
      event.preventDefault(); sticks[name].pointer = event.pointerId; node.setPointerCapture(event.pointerId); updateStick(name, event);
    });
    node.addEventListener("pointermove", event => {
      if (sticks[name].pointer !== event.pointerId) return;
      event.preventDefault(); updateStick(name, event);
    });
    node.addEventListener("pointerup", event => {
      if (sticks[name].pointer !== event.pointerId) return;
      sticks[name].pointer = null; const throttleY = sticks[name].y; clearStick(sticks, name);
      if (name === "left" && controlMode === "manual_throttle") sticks[name].y = throttleY;
      renderStick(name);
      if (node.hasPointerCapture(event.pointerId)) node.releasePointerCapture(event.pointerId);
    });
    node.addEventListener("pointercancel", () => interrupt("触控取消，已暂停"));
    node.addEventListener("lostpointercapture", event => {
      if (sticks[name].pointer === event.pointerId) interrupt("触控捕获丢失，已暂停");
    });
  }
  function renderButtons() {
    $("fire").setAttribute("aria-pressed", String(held.has("fire")));
    $("fire").textContent = held.has("fire") ? "停止手动开火" : autoFire ? "自动开火 · 手动开" : "手动开火：关";
    $("interact").setAttribute("aria-pressed", String(held.has("interact")));
    $("interact").textContent = held.has("interact") ? "取消作业" : "作业";
    $("brake").setAttribute("aria-pressed", String(held.has("brake")));
  }
  function toggle(action) { if (state !== "Active") return; held.has(action) ? held.delete(action) : held.add(action); renderButtons(); }
  $("fire").addEventListener("click", () => toggle("fire"));
  $("interact").addEventListener("click", () => toggle("interact"));
  for (const action of ["utility", "target"]) $(action).addEventListener("click", () => { if (state === "Active" && edges.length < 8) edges.push({id:++edgeId,action,kind:"pressed"}); });
  $("pause").addEventListener("click", () => interrupt("PHONE_PAUSED"));
  for (const [id, action] of [["zoom-in","zoom_in"],["zoom-out","zoom_out"],["map","map"],["recenter","recenter"]]) {
    $(id).addEventListener("click", () => { if (state === "Active" && edges.length < 8) edges.push({id:++edgeId,action,kind:"pressed"}); });
  }
  $("brake").style.touchAction = "none";
  $("brake").addEventListener("pointerdown", event => { if (state !== "Active" || brakePointer !== null) return; brakePointer = event.pointerId; event.currentTarget.setPointerCapture(event.pointerId); held.add("brake"); renderButtons(); });
  $("brake").addEventListener("pointerup", event => { if (event.pointerId !== brakePointer) return; brakePointer = null; held.delete("brake"); renderButtons(); });
  $("brake").addEventListener("pointercancel", () => interrupt("制动触控中断"));
  $("brake").addEventListener("lostpointercapture", event => { if (event.pointerId === brakePointer) interrupt("制动触控丢失"); });
  $("resume").addEventListener("click", () => { if (controlMode !== "manual_throttle") resetControls(); if (token && landscape.matches) authenticated("resume"); });
  $("pair-form").addEventListener("submit", event => { event.preventDefault(); pairCode = $("pair-code").value.trim(); if (/^\d{6}$/.test(pairCode)) connect(); });
  $("fullscreen").addEventListener("click", async () => {
    try {
      if (document.fullscreenElement) await document.exitFullscreen();
      else if (document.documentElement.requestFullscreen) await document.documentElement.requestFullscreen();
      else showState("此浏览器不支持全屏，基础控制仍可用");
    } catch (_) { showState("全屏未获允许，基础控制仍可用"); }
  });
  function applyPreferences() {
    document.documentElement.style.setProperty("--radius", preferences.size + "px");
    $("sticks").classList.toggle("swapped", preferences.swap);
  }
  function settingLabels() {
    $("deadzone-value").value = $("deadzone").value + "%";
    $("sensitivity-value").value = $("sensitivity").value + "%";
    $("right-sensitivity-value").value = $("right-sensitivity").value + "%";
    $("size-value").value = $("size").value + " px";
  }
  $("settings-open").addEventListener("click", () => {
    interrupt("手柄设置，控制已暂停");
    $("deadzone").value = preferences.deadzone * 100; $("sensitivity").value = preferences.sensitivity * 100;
    $("right-sensitivity").value = preferences.rightSensitivity * 100;
    $("size").value = preferences.size; $("swap").checked = preferences.swap; settingLabels(); $("settings").showModal();
  });
  for (const id of ["deadzone", "sensitivity", "right-sensitivity", "size"]) $(id).addEventListener("input", settingLabels);
  $("settings").addEventListener("close", () => {
    if ($("settings").returnValue !== "save") return;
    preferences = {deadzone:Number($("deadzone").value) / 100,sensitivity:Number($("sensitivity").value) / 100,rightSensitivity:Number($("right-sensitivity").value) / 100,size:Number($("size").value),swap:$("swap").checked};
    try { localStorage.setItem("las-controller-settings", JSON.stringify(preferences)); } catch (_) {}
    applyPreferences(); resetControls();
  });
  $("disconnect").addEventListener("click", () => { authenticated("release"); interrupt("已断开", true); $("settings").close(); });
  function orientationChanged() { $("portrait").classList.toggle("hidden", landscape.matches); if (token) interrupt("旋转屏幕后请重新恢复控制"); }
  if (landscape.addEventListener) landscape.addEventListener("change", orientationChanged); else landscape.addListener(orientationChanged);
  document.addEventListener("visibilitychange", () => { if (document.hidden) interrupt("页面进入后台", true); });
  window.addEventListener("pagehide", () => interrupt("页面关闭", true));
  window.addEventListener("blur", () => { if (state === "Active") interrupt("页面失去焦点"); });
  function animate(now) {
    if (token && lease && !document.hidden && now - lastSend >= 1000 / 30) {
      lastSend = now;
      if (state === "Active" && (now - lastStatus > 350 || now - lastAck > 500)) interrupt("连接延迟过高", true);
      else {
        const active = state === "Active" && landscape.matches && !$("settings").open;
        const matching = !active && controlMode === "manual_throttle" && landscape.matches && !$("settings").open;
        const axes = (active || matching) ? {left_x:sticks.left.x,left_y:sticks.left.y,right_x:sticks.right.x,right_y:sticks.right.y} : {left_x:0,left_y:0,right_x:0,right_y:0};
        authenticated("input", {lease_nonce:lease,frame:{schema:2,control_epoch:epoch,seq:++seq,sample_ms:Math.floor(now),axes,held:active ? [...held] : [],edges:active ? edges : [],context:"flight",neutral:!(active || matching)}});
      }
    }
    requestAnimationFrame(animate);
  }
  applyPreferences(); orientationChanged(); showState(); requestAnimationFrame(animate);
})();

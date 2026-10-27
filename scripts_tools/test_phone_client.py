"""Isolated Godot phone-service integration, without importing/starting the game."""
import argparse
import json
import os
from pathlib import Path
import queue
import socket
import subprocess
import threading
import time
import tempfile
import urllib.request

import websocket


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default=str(Path(os.environ["LOCALAPPDATA"]) / "Programs/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe"))
    parser.add_argument("--browser", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    process = subprocess.Popen([args.godot, "--headless", "--path", str(root / "phone"), "--script", str(root / "tests_v2/test_phone.gd"), "--", "--serve"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
    lines = queue.Queue()
    log = []
    def read_output():
        for line in process.stdout:
            log.append(line.rstrip())
            lines.put(line.rstrip())
    threading.Thread(target=read_output, daemon=True).start()
    checks = []
    connections = []
    def check(ok, label):
        checks.append({"name": label, "passed": bool(ok)})
        print(("PASS " if ok else "FAIL ") + label, flush=True)
        if not ok:
            raise AssertionError(label)
    try:
        limit = time.monotonic() + 15
        status = None
        while time.monotonic() < limit:
            try: line = lines.get(timeout=.5)
            except queue.Empty:
                if process.poll() is not None: break
                continue
            if line.startswith("PHONE_READY "):
                status = json.loads(line[12:]); break
        if status is None:
            raise RuntimeError("Godot did not start isolated service: " + "\n".join(log))
        port, ws_port = status["http_port"], status["ws_port"]
        base = f"http://127.0.0.1:{port}"
        with urllib.request.urlopen(base + "/", timeout=3) as response:
            html = response.read().decode()
            check(response.status == 200 and str(ws_port) in html and "__WS_PORT__" not in html, "HTTP page has real connection configuration")
            session = html.split('data-session="')[1].split('"')[0]
        if args.browser:
            browser_checks(base, status["pair_code"], root, check)
            print(json.dumps({"passed": True, "checks": checks, "evidence": "Chromium synthetic touch; not Android/iPhone physical validation"}, ensure_ascii=False))
            return
        request = urllib.request.Request(base + "/app.js", method="HEAD")
        with urllib.request.urlopen(request, timeout=3) as response:
            check(response.status == 200 and not response.read(), "HEAD has no body")
        def raw_request(payload):
            with socket.create_connection(("127.0.0.1", port), timeout=2) as stream:
                stream.sendall(payload)
                try: return stream.recv(4096)
                except ConnectionResetError: return b""
        check(not raw_request(b"GET / HTTP/1.1\r\nHost: attacker.test\r\n\r\n"), "DNS rebinding Host rejected")
        check(not raw_request(f"GET /../project.godot HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\n\r\n".encode()), "path traversal rejected over TCP")
        check(not raw_request(f"POST / HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\n\r\n".encode()), "POST rejected over TCP")
        check(not raw_request(f"GET / HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nX-Long: {'x' * 8300}\r\n\r\n".encode()), "oversized header rejected over TCP")
        try:
            urllib.request.urlopen(base + "/vendor/qr_code/qr_code.gd", timeout=2)
            check(False, "static whitelist")
        except urllib.error.HTTPError as error:
            check(error.code == 404, "non-whitelisted source file is not served")
        try:
            rejected = websocket.create_connection(f"ws://127.0.0.1:{ws_port}/control", origin="http://attacker.test", subprotocols=["las-v2"], timeout=2)
            rejected.close(); check(False, "unknown Origin rejected")
        except (websocket.WebSocketException, OSError):
            check(True, "unknown Origin rejected before upgrade")
        ws = websocket.create_connection(f"ws://127.0.0.1:{ws_port}/control", origin=base, subprotocols=["las-v2"], timeout=3)
        connections.append(ws)
        def receive_type(connection, wanted, seconds=3):
            end = time.monotonic() + seconds
            while time.monotonic() < end:
                message = json.loads(connection.recv())
                if message.get("type") == wanted: return message
            raise TimeoutError(wanted)
        check(receive_type(ws, "hello")["protocol"] == 2, "engine WebSocket handshake")
        ws.send(json.dumps({"type":"hello", "protocol":2, "session_id":session, "page_nonce":"integration-test"}))
        ws.send(json.dumps({"type":"pair", "code":"wrong", "requested_role":"controller"}))
        check(receive_type(ws, "error")["code"] == "PAIR_DENIED", "wrong pairing code rejected")
        ws.send(json.dumps({"type":"pair", "code":status["pair_code"], "requested_role":"controller"}))
        paired = receive_type(ws, "paired")
        token = paired["token"]
        check(len(token) == 64, "256-bit session token")
        other = websocket.create_connection(f"ws://127.0.0.1:{ws_port}/control", origin=base, subprotocols=["las-v2"], timeout=2)
        connections.append(other)
        receive_type(other, "hello")
        other.send(json.dumps({"type":"hello","protocol":2,"session_id":session,"page_nonce":"other"}))
        other.send(json.dumps({"type":"pair","code":status["pair_code"],"requested_role":"controller"}))
        check(receive_type(other, "error")["code"] == "CONTROL_BUSY", "second controller cannot take over")
        other.close()
        epoch, lease, seq = paired["control_epoch"], "", 0
        def next_status(wanted=None):
            nonlocal epoch, lease, seq
            for _ in range(60):
                message = json.loads(ws.recv())
                if message.get("type") == "ping":
                    ws.send(json.dumps({"type":"pong","token":token,"nonce":message["nonce"]}))
                if message.get("type") == "status":
                    if epoch != message["control_epoch"]: seq = 0
                    epoch = message["control_epoch"]; lease = message["lease_nonce"]
                    if wanted is None or message["state"] == wanted: return message
            raise AssertionError("missing status " + str(wanted))
        next_status("TakingControl")
        def input_message(neutral=True, axis=0, override=None):
            nonlocal seq
            seq += 1
            message = {"type":"input","token":token,"lease_nonce":lease,"frame":{"schema":2,"control_epoch":epoch,"seq":seq,"sample_ms":int(time.monotonic()*1000),"axes":{"left_x":0,"left_y":0,"right_x":axis,"right_y":0},"held":[],"edges":[],"context":"flight","neutral":neutral}}
            if override: override(message)
            ws.send(json.dumps(message))
            return message
        input_message()
        receive_type(ws, "ack")
        ws.send(json.dumps({"type":"resume","token":token}))
        check(next_status("Active")["state"] == "Active", "computer approval plus neutral plus explicit resume")
        input_message(False, .5)
        ack = receive_type(ws, "ack")
        check(ack["state"] == "Active", "active axis input accepted")
        input_message(True)
        check(receive_type(ws, "ack")["state"] == "Active", "ordinary neutral release does not pause")
        last = input_message(False, .4)
        receive_type(ws, "ack")
        ws.send(json.dumps(last))
        check(next_status("Stale")["reason"] == "INPUT_STALE", "duplicate sequence cannot refresh watchdog")
        input_message()
        receive_type(ws, "ack")
        ws.send(json.dumps({"type":"resume","token":token}))
        next_status("Active")
        old_nonce = lease
        time.sleep(.35)
        next_status("Stale")
        input_message(override=lambda message: message.update(lease_nonce=old_nonce))
        time.sleep(.08)
        ws.send(json.dumps({"type":"resume","token":token}))
        check(receive_type(ws, "error")["code"] == "CENTER_STICKS_OR_COMPUTER_APPROVAL", "expired nonce cannot establish neutral or resume")
        next_status()
        input_message()
        receive_type(ws, "ack")
        ws.send(json.dumps({"type":"resume","token":token}))
        next_status("Active")
        input_message(False, 2)
        check(next_status("Stale")["reason"] == "BAD_AXIS", "invalid active input suspends and clears control")
        def closed(connection):
            try:
                for _ in range(20):
                    if connection.recv() == "": return True
            except (websocket.WebSocketConnectionClosedException, ConnectionResetError):
                return True
            return False
        ws.send(json.dumps({"type":"resume", "token":"0" * 64}))
        check(closed(ws), "invalid token closes connection")
        ws.close()
        oversized = websocket.create_connection(f"ws://127.0.0.1:{ws_port}/control", origin=base, subprotocols=["las-v2"], timeout=2)
        connections.append(oversized)
        receive_type(oversized, "hello")
        oversized.send("x" * 4100)
        check(closed(oversized), "oversized WebSocket message closes connection")
        cooldown = websocket.create_connection(f"ws://127.0.0.1:{ws_port}/control", origin=base, subprotocols=["las-v2"], timeout=2)
        connections.append(cooldown)
        receive_type(cooldown, "hello")
        cooldown.send(json.dumps({"type":"hello", "protocol":2, "session_id":session, "page_nonce":"cooldown-test"}))
        for _ in range(5):
            cooldown.send(json.dumps({"type":"pair", "code":"wrong", "requested_role":"controller"}))
            receive_type(cooldown, "error")
        cooldown.send(json.dumps({"type":"pair", "code":"wrong", "requested_role":"controller"}))
        response = receive_type(cooldown, "error")
        check(response["code"] == "PAIR_COOLDOWN" and response["retry_ms"] > 29000, "five failed codes rotate code and trigger thirty-second cooldown")
        cooldown.close()
        with tempfile.TemporaryDirectory(prefix="las-qr-check-") as temporary:
            qr_path = Path(temporary) / "qr.png"
            output = subprocess.run([args.godot, "--headless", "--path", str(root / "phone"), "--script", str(root / "tests_v2/test_phone.gd"), "--", "--qr-output=" + str(qr_path)], capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=10)
            check(output.returncode == 0, "isolated GDScript validation plus QR artifact")
            import cv2
            decoded, _, _ = cv2.QRCodeDetector().detectAndDecode(cv2.imread(str(qr_path)))
            check(decoded.startswith("http://127.0.0.1:") and decoded.endswith("/") and "token" not in decoded, "QR independently decoded to LAN address only")
        print(json.dumps({"passed":True,"checks":checks,"evidence":"local TCP and WebSocket automation; no physical phone or touch latency validation"},ensure_ascii=False),flush=True)
    finally:
        for connection in connections:
            try: connection.close()
            except OSError: pass
        if process.poll() is None: process.terminate()
        process.wait(timeout=10)
        evidence = root / "phone" / "evidence"
        evidence.mkdir(exist_ok=True)
        label = "browser" if args.browser else "network"
        (evidence / (label + "-result.json")).write_text(json.dumps({"checks":checks,"engine":"Godot 4.7.2","method":label,"physical_phone_tested":False},ensure_ascii=False,indent=2),encoding="utf-8")
        (evidence / (label + "-godot.log")).write_text("\n".join(log),encoding="utf-8")
        for index, line in enumerate(log):
            if "ERROR" in line or "SCRIPT" in line:
                print("\n".join(log[index:index + 9]))


def browser_checks(base, code, root, check):
    from playwright.sync_api import sync_playwright, expect
    evidence = root / "phone" / "evidence"
    evidence.mkdir(exist_ok=True)
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True)
        context = browser.new_context(viewport={"width": 844, "height": 390}, has_touch=True, is_mobile=True, device_scale_factor=1)
        page = context.new_page()
        errors = []
        page.on("pageerror", lambda error: errors.append(str(error)))
        page.goto(base)
        page.locator("#pair-code").fill(code)
        page.locator("#connect").click()
        page.locator("#pair-panel").wait_for(state="hidden")
        expect(page.locator("#resume")).to_be_enabled()
        page.locator("#resume").click()
        expect(page.locator("#status")).to_have_text("正在控制")
        check(True, "browser pairing and resume")
        cdp = context.new_cdp_session(page)
        left = page.locator("#left-stick").bounding_box()
        right = page.locator("#right-stick").bounding_box()
        def point(box, identity, dx=0, dy=0):
            return {"id": identity, "x": box["x"] + box["width"] / 2 + dx, "y": box["y"] + box["height"] / 2 + dy, "radiusX": 4, "radiusY": 4, "force": 1}
        cdp.send("Input.dispatchTouchEvent", {"type":"touchStart", "touchPoints":[point(left,1),point(right,2)]})
        cdp.send("Input.dispatchTouchEvent", {"type":"touchMove", "touchPoints":[point(left,1,0,-30),point(right,2,35,0)]})
        page.wait_for_timeout(100)
        check(page.locator(".stick.engaged").count() == 2, "two independent captured touches")
        cdp.send("Input.dispatchTouchEvent", {"type":"touchEnd", "touchPoints":[point(left,1,0,-30)]})
        page.wait_for_timeout(100)
        check(page.locator("#left-stick").get_attribute("class") == "stick" and "engaged" in page.locator("#right-stick").get_attribute("class"), "lifting one touch leaves other stick engaged")
        check(page.locator("#status").inner_text() == "正在控制", "normal pointer release does not suspend")
        cdp.send("Input.dispatchTouchEvent", {"type":"touchCancel", "touchPoints":[]})
        expect(page.locator("#status")).to_have_text("安全暂停")
        check(page.locator(".stick.engaged").count() == 0, "pointer cancel clears both sticks and suspends")
        page.locator("#resume").click()
        expect(page.locator("#status")).to_have_text("正在控制")
        page.locator("#fire").click()
        check(page.locator("#fire").get_attribute("aria-pressed") == "true", "manual fire latches without holding a third finger")
        page.locator("#fire").click()
        check(page.locator("#fire").get_attribute("aria-pressed") == "false", "manual fire can be stopped")
        for width, height in [(844,390),(740,360),(568,320),(960,540)]:
            page.set_viewport_size({"width":width,"height":height})
            page.wait_for_timeout(100)
            boxes = page.locator("#left-stick,#right-stick,#resume,#pause,#utility,#interact,#fire,#brake").evaluate_all("nodes => nodes.map(node => { const r=node.getBoundingClientRect(); return {id:node.id,x:r.x,y:r.y,w:r.width,h:r.height,sw:node.scrollWidth,cw:node.clientWidth}; })")
            inside = all(box["x"] >= 0 and box["y"] >= 0 and box["x"]+box["w"] <= width+.5 and box["y"]+box["h"] <= height+.5 and box["sw"] <= box["cw"]+1 for box in boxes)
            check(inside, f"controller layout fits {width}x{height}")
            page.screenshot(path=str(evidence / f"controller-{width}x{height}.png"))
        page.locator("#settings-open").click()
        page.locator("#swap").check()
        page.locator("#settings-save").click()
        page.locator("#sticks.swapped").wait_for()
        check("swapped" in page.locator("#sticks").get_attribute("class"), "explicit left-hand preset applies")
        page.set_viewport_size({"width":390,"height":844})
        page.wait_for_timeout(100)
        check(page.locator("#portrait").is_visible(), "portrait blocks control with clear state")
        check(not errors, "no browser script errors")
        context.close()
        browser.close()


if __name__ == "__main__":
    main()

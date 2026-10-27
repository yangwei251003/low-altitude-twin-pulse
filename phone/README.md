# Offline Phone Controller

`PhoneServerV2` is a Godot 4.7.2 Node. Instantiate it once, add it to the scene tree, and call `start_server()` only after the player opens phone pairing. It keeps networking alive while the scene tree is paused. It does not modify the game pause state itself: the host must handle `suspended(reason)` and use a collection of pause reasons so a phone resume never clears an unrelated pause.

## Host integration

- `start_server(bind_address = "0.0.0.0") -> int`: returns Godot Error. HTTP/WS try port pairs 8765/8766 through 8773/8774. A third ephemeral listener binds only to loopback for validated handshake forwarding.
- `stop_server()`: immediately clears input, destroys credentials, closes all listeners. Desktop takeover should call this, or add a new approved device arbiter epoch before continuing.
- `approve_control() -> bool`: call only after a computer-side player action. Starts a new epoch and waits for centered sticks. It does not resume simulation.
- `resume_control() -> bool`: accepts only an approved, connected controller with a current neutral frame. The phone's explicit Resume button calls this too. The host may resume the phone pause reason after observing `active == true`; other forced pause reasons remain intact.
- `suspend_control(reason = "manual")`: call when the computer pauses, opens settings/map, or otherwise interrupts the phone owner. Active/taking-control sessions enter Stale, advance their epoch, discard leases/queued edges, and emit one zero frame. Repeated or reentrant calls do nothing. The same connected phone must send a fresh neutral frame in the new epoch before an explicit resume can succeed.
- `input_frame(frame)`: normalized InputFrame schema 2. Four axes are right-positive/up-positive; left stick is yaw/vertical and right stick is planar input. Active snapshots are emitted on physics ticks. Abnormal transitions emit one immediate all-zero frame. Held actions: fire, brake, interact. Edge actions: pause, utility, tool. IDs are acknowledged and deduplicated.
- `get_status()`: state, address, addresses, actual ports, temporary pairing code/expiry, paired, active, neutral, RTT, reason, epoch and reject count. Never returns the session token. Offer the player the listed addresses if multiple adapters are present.
- `set_telemetry(Dictionary)`: accepts altitude_agl_m, speed_mps, health, heat, cargo_kg, tool_state, mode, auto_fire. Only these fields enter phone status, at 10 Hz.
- `get_pair_qr_image(address = "") -> Image`: cached offline QR for a current listed address. It contains only the HTTP URL, with a four-module quiet zone. Use nearest filtering; do not crop its white border. No token or pairing code is encoded.

Include `phone/index.html`, `phone/app.js`, and `phone/style.css` in the Windows export non-resource filter. Include the third-party license and source manifest with the source/release notices. Do not expose evidence, source GDScript or vendor files through HTTP; the server's fixed routes only serve the three webpage files.

## Protocol and safety

Browser handshake requires exact HTTP Origin, literal current IPv4 Host, `/control`, WebSocket version 13, and `las-v2` subprotocol. The original headers are validated before a bounded loopback TCP relay feeds the engine WebSocketPeer; no custom WebSocket frame parser is used. Source addresses are private/link-local IPv4 or loopback. This is an unencrypted trusted-LAN controller, not a public service.

The protocol is the documented hello/pair/paired/input/ack flow, plus authenticated suspend/resume/release and server ping/client pong. A six-digit code lasts 120 seconds. Five failed attempts rotate it and impose 30 seconds of cooldown. A single paired connection owns a random 256-bit token held only in page memory. A new control epoch starts at each approved takeover or safety suspension. Server-issued nonces rotate every 100 ms and expire after 250 ms; old sequence, old epoch and stale lease input never renew the watchdog. No valid input for 250 ms suspends once and clears every axis/action. A close/error clears immediately.

HTTP headers are capped at 8 KiB with a 3-second connection lifetime. Static page bytes total at most 2 MiB. WebSocket messages are capped at 4 KiB; more than 120 messages in a one-second window disconnects. The two relay directions each cap at 16 KiB, engine input/output each at 8 KiB, keeping application-owned pending data below 64 KiB per connection. Browser send backlog above 16 KiB closes and requires pairing again.

Ordinary pointer release clears only its stick. Pointer cancellation/lost capture, page background, orientation change and network faults clear both sticks and all latched buttons; resumption requires a deliberate action. Fire and work are explicit toggles so normal play does not require three fingers. Settings persist only deadzone, sensitivity, stick size and the explicit left-hand layout preset. Fullscreen is optional; no motion sensor or haptic permission is required.

## Verification

From the repository root, with the existing Python `websocket-client`, `opencv-python` and optional Playwright environment:

```powershell
python scripts_tools/test_phone_client.py
python scripts_tools/test_phone_client.py --browser
```

The scripts start an isolated headless service with `--path phone --script tests_v2/test_phone.gd`, never import the whole project and never start the game scene. The integration harness deliberately pauses the scene tree, so communication and recovery run through the always-processing service while the game would be paused. All service processes are shut down when the tests finish. Generated results/logs and Chromium screenshots live in `phone/evidence/`. Chromium uses synthetic touch input, which is useful for pointer lifecycle tests but is not a physical phone test.

Validated: malformed frames, sequence/lease/epoch bounds, edge deduplication, HTTP whitelist/Host/path/header bounds, WebSocket Origin/protocol/pairing/ownership, neutral handover, stale input, invalid token/message handling, five-attempt cooldown, offline QR decoded independently with OpenCV, synthetic dual pointer release/cancellation, manual fire toggle, left-hand preset, portrait blocking, four viewport sizes and browser script errors.

Manual computer suspension regression: 41 isolated Godot checks include callback reentry/idempotence and a real loopback WebSocket. It verifies that immediate resume, queued old-epoch neutral input, and a fresh-epoch deflected stick all fail after manual pause; a fresh centered frame stays paused until explicit resume. The existing 23 HTTP/WebSocket checks and 15 Chromium synthetic-touch checks were rerun successfully after this change.

NOT_TESTED: real Android two-thumb reach/comfort, Wi-Fi loss/lockscreen behavior on a device, 500-sample Wi-Fi RTT distributions, synchronized touch-to-display latency, physical iPhone (explicitly deferred by the user), and integration with the main flight/saving/game pause systems. A localhost RTT or generated QR is not evidence of physical scan/control latency.

QR implementation: Kenyoni Godot Addons, pinned revision and hashes in `vendor/qr_code/SOURCE.json`, MIT license in `vendor/qr_code/LICENSE.md`. Only relative preload paths were changed. Official API references used: https://docs.godotengine.org/en/stable/classes/class_websocketpeer.html and https://docs.godotengine.org/en/stable/classes/class_tcpserver.html; actual compilation and execution used Godot 4.7.2.

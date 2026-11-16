# XUNSHE / YJX transport notes

Observed locally on 2026-11-14. Experimental active querying and event reception are implemented; hardware battery support remains unverified until the input-monitoring block is resolved.

## Evidence

- Official page: https://xunshe.yjx2012.com/?productName=USB%20Receiver (title XUNSHE-M2).
- Official script: https://cdn.yjx2012.com/xunshe/_next/static/chunks/app/page-6e30f3e08d1d747b.js
- Hardware: VID A8A5, PID 2255, product USB Receiver. Composite HID includes a mouse collection with vendor collections FFAB/report AB and FF01/usage 10/report F0. The separate FF03/report 0A collection is not used.
- Official battery display component returns an empty element. Its input listener still handles status command 30 (hex).

## Transport

The official WebHID adapter uses the first array byte as report ID and sends the remaining bytes as payload. The F0 report has 63 payload bytes. The official `getDeviceOnline` request is report F0 with payload ED 01 followed by zero padding. This request reads online state; it is not evidence of an active battery query.

The official listener reads command 30 at payload offset 0, battery at offset 7, charge flag at offset 8. Native input can include the report ID; the parser normalizes that prefix and rejects wrong IDs, truncated frames, percentages above 100 and charge flags outside 0/1. Flag semantics remain pending hardware verification; only 0/1 are accepted as not charging/charging.

BatteryBridge keeps this channel open on its HID worker run loop and listens between scans. A valid battery event updates the sample and wakes reconciliation. Removing the receiver releases the listener and sample. Version 0.5.2 also sends the read-only F0 battery query documented by https://github.com/mimuruu/EWEADN-GS02-Pro-Control: a 63-byte payload beginning `30 A5 0B 2E 01 01 01 00 00`, zero padded. Its receiver and transport match this protocol branch. It is not evidence that every OEM firmware answers it; no AA/55 packets or settings writes are sent.

## Verification boundary

Read-only descriptor inspection succeeded. Version 0.5.2 was installed at /Applications/BatteryBridge.app. Its GUI diagnostic snapshot (not just the terminal) confirms E00002E2 when opening the YJX interface, with HID access denied. The keyboard succeeds through its separate vendor interface, so a readable keyboard cannot be used as evidence that the mouse is authorized. The battery command has not been transmitted on this unit yet. No real battery response has been captured. Protocol tests use synthetic fixtures. The USB product name does not identify the exact mouse model, so the card uses a neutral receiver name.

The authorization UI now remains visible when any online device is denied, even if another device has a valid battery sample. The mouse card also provides a direct Settings action. The Settings switch was also inspected: it is on, and Reveal in Finder points to /Applications/BatteryBridge.app, despite the runtime denial. A stale signing/authorization match after updates is a hypothesis, not a proven cause. Next verification requires rebinding the current application in Input Monitoring and relaunching. A system privacy permission change requires explicit user confirmation.

The GUI saves a bounded latest diagnostics.json snapshot in its Application Support directory, containing open errors, read-only query counters, reply IDs/lengths and up to 12 bytes from battery-command responses only. It never records key/motion reports or uploads diagnostics.

Other products reuse A8A5:2255. The G7 AA/55 protocol documented at https://github.com/HeyOkay/HaloBattery/blob/main/docs/protocols.md is a different transport and is intentionally not sent to this receiver.


## Hardware result after controlled permission refresh

On 2026-11-14, the running process was fully terminated. Only its Input Monitoring entry was removed and restored against the exact /Applications/BatteryBridge.app path; then Finder opened that same unchanged 0.5.3 executable. The runtime access changed to granted. Open succeeded and the first F0 battery query returned a valid payload beginning `30 a5 95 2e 01 01 01 64 00`: battery 100%, not charging. The source was published and appeared in pmset accessory power output. This proves the current transport and parser on this unit; it does not prove behavior on every YJX OEM firmware.

Earlier paragraphs describe the diagnostic stage before this successful test. They must not be read as a claim that the hardware lacks battery support. The 0.5.4 display name uses ASCII `USB Receiver (YJX)` so CLI consumers can also show the generic receiver name. The exact marketing model remains unconfirmed.


## Charging display and publication (0.5.5)

The card displays charging independently of connection state. Unknown/stale/offline samples never become a fabricated not-charging state. The publication builder derives Is Charging, Is Charged and Power Source State from the same protocol reading. A charging source cannot simultaneously be marked charged. The real 100%/flag-0 response is verified on hardware; flag-1 rendering and publication are covered by protocol-to-publication checks but not by a physical cable insertion in this run.

The app communicates locally with HID receivers. Official web pages are protocol references, not a runtime dependency, cache or remote battery service.

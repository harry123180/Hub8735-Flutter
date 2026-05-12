# Flash/Camera Race Bug Research — Supplement: 2026-05-12 Update 2

> **This file** covers Findings 111–113 from the 2026-05-12 Update 2 (second 6-hour cycle) research run.
> Prior findings: `docs/FLASH_CAMERA_RACE_RESEARCH.md` (local, base64-encoded) and prior supplements.
> Created because the main research log cannot be pushed via the GitHub MCP API.
> New findings appended to local log in this commit.

---

## Cycle Summary

**Nothing new of technical significance found.** All tracked repositories remain static.
Bug is unpatched. No public reports in any language or channel.

One new data point: forum thread #4811 ("Camera_2_Lcd_JPEGDEC.ino error/warning") appeared
in a Google search result and was logged, but it is unrelated to the FCS flash race bug and
its thread number (#4811) is lower than the already-known #4834.

---

## Finding 111 — Both Repositories Confirmed Static Since Morning Update; No New Commits

**Source:** GitHub compare endpoints — ameba-arduino-pro2/dev, ameba-rtos-pro2/main
- https://github.com/Ameba-AIoT/ameba-arduino-pro2/compare/13961cc...dev
- https://github.com/Ameba-AIoT/ameba-rtos-pro2/compare/1c1c8b7...main
**Priority:** LOW — Status confirmation

Both compare endpoints return "identical." No changes since the first 2026-05-12 research cycle:

| Repository | Last commit SHA | Last commit date | Message |
|---|---|---|---|
| ameba-arduino-pro2 (dev) | `13961cc` | May 5, 2026 | "Update API for AMB82-zero and SWD off logic" |
| ameba-rtos-pro2 (main) | `1c1c8b7` | May 1, 2026 | "Sync upstream — wowlan dhcp renew" |

`FlashMemory.cpp` (SHA `4fdfbec`) re-confirmed unpatched: zero calls to `device_mutex_lock`,
`device_mutex_unlock`, or `RT_DEV_LOCK_FLASH`. All write/erase functions remain mutex-free.

ameba-arduino-pro2: 12 open issues (highest #398, Mar 2026); 0 open PRs; releases unchanged.
ameba-rtos-pro2: 3 open issues (highest #16, Jan 2026); 0 open PRs.
ideashatch/HUB-8735: 1 open issue (#10, Aug 13, 2025 — PS5268 sensor ID fail; unrelated).

---

## Finding 112 — Forum Thread #4811 Newly Indexed: Camera_2_Lcd_JPEGDEC.ino Warning; Unrelated to FCS Bug

**Source:** forum.amebaiot.com thread #4811 (HTTP 403; Google snippet only)
https://forum.amebaiot.com/t/camera-2-lcd-jpegdec-ino-error-warning/4811
**Priority:** LOW — New thread number logged; unrelated to flash/FCS/cold-boot bug

Thread #4811 surfaced in a Google search result this cycle. Title: "Camera_2_Lcd_JPEGDEC.ino
error/warning." This is a compile-time warning/error in an example sketch — not a cold-boot or
FCS flash race report. Direct fetch returns HTTP 403 (login required).

Thread #4811 is lower-numbered than the already-known thread #4834 ("Boot failure after OTA update").
The highest publicly indexed forum thread remains approximately #4847. No Google-indexed snippet
for #4811 mentions FlashMemory, FCS KM_status, sensor initial process, VOE_OPEN_CMD, or
cold-boot failure after flash writes.

---

## Finding 113 — Complete Status Sweep: Bug Unpatched as of 2026-05-12 (Update 2)

**Source:** Exhaustive sweep of all tracked sources (2026-05-12, second 6-hour run)
**Priority:** LOW — Status confirmation

| Repository / Source | Last activity | Status |
|---|---|---|
| ameba-arduino-pro2 (dev branch) | May 5, 2026 — SHA `13961cc` | **No new commits — compare `13961cc...dev` = identical** |
| ameba-arduino-pro2 (releases) | V4.1.0 stable (Mar 2, 2026); V4.1.1-QC-V05 pre-release | **No new release** |
| ameba-rtos-pro2 (main branch) | May 1, 2026 — SHA `1c1c8b7` | **No new commits — compare `1c1c8b7...main` = identical** |
| ameba-arduino-pro2 pull requests | 0 open; 319 closed | **No fix under review** |
| ameba-arduino-pro2 issues | 12 open; highest: #398 (Mar 2026) | **Zero new FCS/FlashMemory/VOE issues** |
| ameba-rtos-pro2 issues | 3 open; highest: #16 (Jan 2026) | **Zero new relevant issues** |
| ideashatch/HUB-8735 | Issue #10 (Aug 2025 — PS5268 sensor ID; unrelated) | **Inactive; no FCS issues** |
| forum.amebaiot.com | Thread #4811 logged (unrelated; 403); highest indexed ~#4847 | **No new FCS/flash bug threads** |
| CSDN / Zhihu / 21ic / EEWorld | — | **Zero Chinese-language reports — reconfirmed** |
| bbs.aithinker.com (BW21-CBV) | Thread #47223 highest known (BW21 camera DIY) | **No FCS/flash bug content** |
| FlashMemory.cpp (dev, SHA `4fdfbec`) | Sept 30, 2025 (>10.5 months unmodified) | **Still NO mutex fix** |
| video_api.c (main) | March 3, 2026 | **Unguarded `ftl_common_write()` / `ftl_common_read()` remain** |
| All bug-signature strings | — | **Zero results in English or Chinese** |

**No HIGH priority confirmed fix found. Bug status: publicly undocumented and unpatched as of
2026-05-12 (Update 2).**

---

## Sources Added (Update 2026-05-12, Update 2)

- ameba-arduino-pro2 compare `13961cc...dev` (re-confirmed identical — no new commits): https://github.com/Ameba-AIoT/ameba-arduino-pro2/compare/13961cc...dev
- ameba-rtos-pro2 compare `1c1c8b7...main` (re-confirmed identical — no new commits): https://github.com/Ameba-AIoT/ameba-rtos-pro2/compare/1c1c8b7...main
- ameba-arduino-pro2 issues (12 open; highest #398; no FCS issues): https://github.com/Ameba-AIoT/ameba-arduino-pro2/issues
- ameba-rtos-pro2 issues (3 open; highest #16; no new issues): https://github.com/Ameba-AIoT/ameba-rtos-pro2/issues
- ideashatch/HUB-8735 issues (issue #10 Aug 2025 — PS5268; unrelated): https://github.com/ideashatch/HUB-8735/issues
- FlashMemory.cpp raw (re-confirmed zero mutex calls; SHA `4fdfbec`): https://raw.githubusercontent.com/Ameba-AIoT/ameba-arduino-pro2/dev/Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.cpp
- forum.amebaiot.com thread #4811 (Camera_2_Lcd_JPEGDEC warning; 403-blocked; unrelated): https://forum.amebaiot.com/t/camera-2-lcd-jpegdec-ino-error-warning/4811

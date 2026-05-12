# Flash/Camera Race Bug Research — Supplement: 2026-05-12 Update 3

> **This file** covers Findings 114–118 from the 2026-05-12 Update 3 (third 6-hour cycle) research run.
> Prior findings: `docs/FLASH_CAMERA_RACE_RESEARCH.md` (local, one-line format) and prior supplements.
> Created because the main research log cannot be pushed via the GitHub MCP API.
> New findings appended to local log in this commit.

---

## Cycle Summary

**Nothing new of technical significance found.** All tracked repositories remain static since
the morning cycle (U2, 06:02). Bug is unpatched. No public reports in any language or channel.

One new informational data point: the full content of `hal_video_release_note.txt` was retrieved
this cycle, confirming the VOE 1.7.1.0 "Fix dual sensor id FCS mirror/flip issue" fix (LOW
priority, unrelated to the flash mutex race condition). The FCS fix history in the VOE release
notes does NOT include any fix for concurrent flash write / FCS sector corruption.

Forum thread #4302 ("[VOE]frame_end: sensor didn't initialize done!") noted for manual review —
title suggests sensor initialization failure — but access is 403-blocked.

---

## Finding 114 — Both Repositories Confirmed Static Since U2; No New Commits

**Source:** GitHub compare endpoints and direct commit pages
- https://github.com/Ameba-AIoT/ameba-arduino-pro2/compare/13961cc...dev
- https://github.com/Ameba-AIoT/ameba-rtos-pro2/commits/main
**Priority:** LOW — Status confirmation

Compare endpoint for ameba-arduino-pro2 returns "13961cc and dev are **identical**."
ameba-rtos-pro2 HEAD remains `1c1c8b7` (May 1, 2026 — "Sync upstream — wowlan dhcp renew").

| Repository | Last commit SHA | Last commit date | Message |
|---|---|---|---|
| ameba-arduino-pro2 (dev) | `13961cc` | May 5, 2026 | "Update API for AMB82-zero and SWD off logic" |
| ameba-rtos-pro2 (main) | `1c1c8b7` | May 1, 2026 | "Sync upstream — wowlan dhcp renew" |

FlashMemory.cpp (SHA `4fdfbec`) re-confirmed unpatched by direct raw fetch this cycle:
zero calls to `device_mutex_lock`, `device_mutex_unlock`, or `RT_DEV_LOCK_FLASH`.

ameba-arduino-pro2: 11 open issues (highest confirmed #398, Mar 2026); 0 open PRs.
ameba-rtos-pro2: 3 open issues (highest #16, Jan 2026); 0 open PRs.
ideashatch/HUB-8735: 1 open issue (#10, Aug 2025 — PS5268 sensor ID; unrelated).

---

## Finding 115 — VOE 1.7.1.0 Release Notes Full Content Retrieved; FCS History Documented

**Source:** `hal_video_release_note.txt` — ameba-rtos-pro2 main branch (commit `d54e1a8`, May 1, 2026)
https://github.com/Ameba-AIoT/ameba-rtos-pro2/blob/main/component/soc/8735b/fwlib/rtl8735b/lib/source/ram/video/hal_video_release_note.txt
**Priority:** LOW — FCS fix history documented; none address flash mutex race

Finding 158 (2026-05-09 U4) noted that the VOE 1.7.1.0 sync "none touch mutex or flash locking"
but did not record the specific release note text. Full content retrieved this cycle.

Complete FCS-related entries in the VOE release notes (RTL8735B_VOE, v1.0.0.0 Dec 2021 through
v1.7.1.0 April 2026):

| VOE Version | FCS-related fix / feature |
|---|---|
| **1.7.1.0** (April 2026) | **"Fix dual sensor id FCS mirror/flip issue"** |
| 1.5.1.0 | "FCS RGB stream drop frame" support |
| 1.5.0.0 | "FCS NV12+RGB" capability |
| 1.4.7.0 | "HDR sensor FCS fail issue" fix |
| 1.4.3.1 | "terminating FCS flow weak func and example code" |

**Interpretation:** Realtek has acknowledged and patched multiple FCS bugs over 12 major VOE
version increments. NONE of these fixes address concurrent flash SPI access (the mutex race).
The 1.7.1.0 fix "dual sensor id FCS mirror/flip" corrects FCS image data content for two-sensor
configurations — unrelated to the `KM_status 0x00002081` / `sensor initial process` failure
caused by a bare `flash_erase_sector()` / `flash_stream_write()` racing with
`ftl_common_write()` / `ftl_common_read()` during FCS save/load.

The VOE binary (`voe.bin`, `libvideo_ns.a`, `libvideo_ntz.a`) is closed-source; the fix is
embedded in the precompiled blob. No source patch is available or visible.

---

## Finding 116 — Forum Thread #4302 "[VOE]frame_end: sensor didn't initialize done!" Noted for Manual Inspection

**Source:** forum.amebaiot.com/t/voe-frame-end-sensor-didnt-initialize-done/4302 (HTTP 403)
https://forum.amebaiot.com/t/voe-frame-end-sensor-didnt-initialize-done/4302
**Priority:** LOW — 403-blocked; title is suggestive but cannot confirm content relates to FCS flash race

Thread #4302 surfaced prominently in this cycle's searches combining "VOE", "flash", "camera",
"FCS", and "cold boot". Its title — "[VOE]frame_end: sensor didn't initialize done!" — closely
matches the `It don't do the sensor initial process` Boot ROM message in our bug. However:

- Access returns HTTP 403 (login required)
- No Google snippet is available mentioning "FCS", "flash write", "KM_status", or cold boot
- Thread number #4302 is in the mid-range (~early 2025), predating V4.0.8 FlashMemory addition

**Action:** Manual login required to inspect full thread. Low probability of matching our bug
given the date and the absence of flash-related Google snippets, but the title warrants a
direct inspection by a forum-authenticated researcher.

---

## Finding 117 — No New Forum Threads Above #4847 Indexed; Forum /new Returns 403

**Source:** Web searches, direct forum URL probes
**Priority:** LOW — Access wall unchanged; highest visible thread confirmed

Forum.amebaiot.com /new returns HTTP 403. Direct probes of threads #4848–#4850 return HTTP 403.
No Google-indexed thread above #4847 ("I2C1 for MPU6050") found in any search query this cycle.
No Google snippet for any thread above #4840 ("OTA via HTTPS") mentions FlashMemory, FCS,
KM_status, cold boot, or concurrent flash/video operations.

---

## Finding 118 — Complete Status Sweep: Bug Unpatched as of 2026-05-12 (Update 3)

**Source:** Exhaustive sweep of all tracked sources (2026-05-12, third 6-hour run)
**Priority:** LOW — Status confirmation

| Repository / Source | Last activity | Status |
|---|---|---|
| ameba-arduino-pro2 (dev branch) | May 5, 2026 — SHA `13961cc` | **No new commits — compare identical** |
| ameba-arduino-pro2 (releases) | V4.1.0 stable (Mar 2, 2026); V4.1.1-QC-V05 pre-release | **No new release** |
| ameba-rtos-pro2 (main branch) | May 1, 2026 — SHA `1c1c8b7` | **No new commits** |
| ameba-arduino-pro2 pull requests | 0 open; 319 closed | **No fix under review** |
| ameba-arduino-pro2 issues | 11 open; highest: #398 (Mar 2026) | **Zero new FCS/FlashMemory/VOE issues** |
| ameba-rtos-pro2 issues | 3 open; highest: #16 (Jan 2026) | **Zero new relevant issues** |
| ideashatch/HUB-8735 | Issue #10 (Aug 2025 — PS5268; unrelated) | **Inactive; no FCS issues** |
| forum.amebaiot.com | Highest indexed ~#4847; #4848+ all HTTP 403 | **No new FCS/flash bug threads** |
| forum thread #4302 | HTTP 403; title: "[VOE]frame_end: sensor didn't initialize done!" | **Requires manual login to inspect** |
| CSDN / Zhihu / 21ic / EEWorld | — | **Zero Chinese-language reports — reconfirmed** |
| bbs.aithinker.com (BW21-CBV) | Various DIY camera threads | **No FCS/flash bug content** |
| FlashMemory.cpp (dev, SHA `4fdfbec`) | Sept 30, 2025 (>10.5 months unmodified) | **Still NO mutex fix** |
| video_api.c (main) | March 3, 2026 | **Unguarded `ftl_common_write()` / `ftl_common_read()` remain** |
| VOE release notes (1.7.1.0, Apr 2026) | — | **No flash mutex fix; FCS mirror/flip fix is unrelated** |
| All bug-signature strings | — | **Zero results in English or Chinese** |

**No HIGH priority confirmed fix found. Bug status: publicly undocumented and unpatched as of
2026-05-12 (Update 3).**

---

## Sources Added (Update 2026-05-12, Update 3)

- ameba-arduino-pro2 compare `13961cc...dev` (confirmed identical — no new commits): https://github.com/Ameba-AIoT/ameba-arduino-pro2/compare/13961cc...dev
- ameba-rtos-pro2 commits/main (HEAD re-confirmed `1c1c8b7`, May 1, 2026): https://github.com/Ameba-AIoT/ameba-rtos-pro2/commits/main
- ameba-arduino-pro2 issues (11 open; highest #398; no FCS issues): https://github.com/Ameba-AIoT/ameba-arduino-pro2/issues
- ameba-rtos-pro2 issues (3 open; highest #16; no new issues): https://github.com/Ameba-AIoT/ameba-rtos-pro2/issues
- ideashatch/HUB-8735 issues (only issue #10 Aug 2025): https://github.com/ideashatch/HUB-8735/issues
- FlashMemory.cpp raw dev (re-confirmed zero mutex calls; SHA `4fdfbec`): https://raw.githubusercontent.com/Ameba-AIoT/ameba-arduino-pro2/dev/Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.cpp
- hal_video_release_note.txt (VOE 1.7.1.0 FCS mirror/flip fix; full FCS history retrieved): https://github.com/Ameba-AIoT/ameba-rtos-pro2/blob/main/component/soc/8735b/fwlib/rtl8735b/lib/source/ram/video/hal_video_release_note.txt
- VOE 1.7.1.0 sync commit d54e1a8 (binary: voe.bin, libvideo_ns.a, libvideo_ntz.a; no mutex source): https://github.com/Ameba-AIoT/ameba-rtos-pro2/commit/d54e1a8
- forum.amebaiot.com thread #4302 (403-blocked; "[VOE]frame_end: sensor didn't initialize done!"): https://forum.amebaiot.com/t/voe-frame-end-sensor-didnt-initialize-done/4302
- forum.amebaiot.com threads #4848–#4850 (all HTTP 403; no new indexed content): https://forum.amebaiot.com/t/4848 (representative URL)

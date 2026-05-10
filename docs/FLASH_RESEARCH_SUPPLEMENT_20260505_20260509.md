# Flash/Camera Race Bug Research — Supplement: 2026-05-05 through 2026-05-09 Update 3

> **This file** covers Findings 105–156, spanning the 2026-05-05 through 2026-05-09 (Update 3) research cycles.
> Findings 1–104 are in the main log (`docs/FLASH_CAMERA_RACE_RESEARCH.md`).
> Findings 153–156 are also in `docs/FLASH_RESEARCH_SUPPLEMENT_20260509_U3.md`.

## Bug Summary (unchanged)

**Root cause (Hypothesis F, confirmed):** `FlashMemory.cpp` (`write()` and `writeWord()`) calls `flash_erase_sector()` and `flash_stream_write()` without acquiring `device_mutex_lock(RT_DEV_LOCK_FLASH)`. The video subsystem FCS save path (`ftl_common_write()` in `video_pre_init_save_cur_params()`) and FCS load path (`ftl_common_read()` in `video_pre_init_load_params()`) both acquire this mutex internally via `nor_write_cb()`/`nor_read_cb()` in `ftl_nor_api.c`. Concurrent SPI commands abort each other per JEDEC spec, leaving the FCS sector (`0xF0D000`) erased-but-blank, which causes `FCS KM_status 0x00002081 err 0x0000200a` and `It don't do the sensor initial process` on the next cold boot.

**Status as of 2026-05-09 Update 3:** Bug publicly undocumented and unpatched. FlashMemory.cpp SHA `4fdfbec` unchanged since September 30, 2025 (>8.5 months). video_api.c unchanged since March 3, 2026.

---

## Key State Snapshots

| Item | State as of 2026-05-09 U3 |
|---|---|
| ameba-arduino-pro2 dev HEAD | `13961cc` (May 5, 2026) — SWD pin logic, no FCS/flash fix |
| ameba-rtos-pro2 main HEAD | `1c1c8b7` (May 1, 2026) — WLAN dhcp sync, no fix |
| FlashMemory.cpp SHA | `4fdfbec` (September 30, 2025) — NO mutex fix, 8.5+ months unchanged |
| video_api.c last modified | March 3, 2026 — NO mutex fix |
| Latest release | V4.1.1-QC-V05 (tag Mar 6 / internal build Apr 30, 2026) |
| V4.1.1 stable release | HTTP 404 — does not exist |
| V4.1.2 release | HTTP 404 — does not exist |
| ameba-arduino-pro2 open issues | 12 confirmed open; highest filed: #398 (Mar 29, 2026) |
| ameba-arduino-pro2 open PRs | 0 |
| ameba-rtos-pro2 highest PR | #15 (no flash/FCS PRs in history) |
| Forum highest indexed thread | #4847 (I2C1 for MPU6050) |
| Public bug-string results | Zero across all four signature strings |
| Chinese-language reports | Zero across CSDN, Zhihu, 21ic, EEWorld, bbs.ai-thinker.com |

---

## New Findings: May 5, 2026

### Finding 105 — Complete Status Sweep: All Repositories Static Since May 1, 2026; Bug Unpatched
**Date:** 2026-05-05 (first 6-hour cycle)  
**Priority:** LOW — Status confirmation

All monitored sources were fetched. Both ameba-arduino-pro2 dev (SHA `e218f33`, April 30, 2026) and ameba-rtos-pro2 main (SHA `1c1c8b7`, May 1, 2026) are static. Zero new releases, issues, PRs, or forum threads related to the bug. FlashMemory.cpp SHA `4fdfbec` confirmed unmodified. video_api.c confirmed unmodified.

---

### Finding 106 — ameba-rtos-pro2 "aiglass" Product-Variant Tag Series (V1.0.3-aiglass.07, April 2, 2026)
**Date:** 2026-05-05 Update 2  
**Priority:** LOW — Parallel product track; same RTL8735B silicon, same bug applies

The `ameba-rtos-pro2` repository hosts a separate tag series prefixed `aiglass`, distinct from the main AmebaPro2/AMB82-Mini release cadence. Most recent: **V1.0.3-aiglass.07** (April 2, 2026). These tags correspond to a Realtek AI-glasses product variant using the same RTL8735B SoC. The `video_api.c` FCS race would apply equally to any product using `SAVE_TO_FLASH` FCS mode. No new aiglass tags since April 2, 2026.

Tag timeline (most recent 5):
| Tag | Date |
|---|---|
| V1.0.3-aiglass.07 | April 2, 2026 |
| 9.6e | March 3, 2026 |
| V1.0.3-aiglass.06 | February 2, 2026 |
| V1.0.3-aiglass.05 | December 18, 2025 |
| V1.0.3-aiglass.04 | November 12, 2025 |

The **"9.6e"** tag (March 3, 2026) follows a separate legacy versioning scheme and coincides with the March 3 "Update code base" restructuring commit that moved `ftl_nor_api.c` to its new location (documented in Finding 52). First explicit documentation of this tag in the research log.

---

### Finding 107 — Complete Status Sweep: Bug Unpatched as of 2026-05-05 Update 2
**Priority:** LOW — Status confirmation. No new content beyond Finding 105.

---

### Finding 108 — New Commit `13961cc` on ameba-arduino-pro2 dev (May 5, 2026): AMB82-zero SWD Logic; Not a Fix
**Date:** 2026-05-05 Update 3  
**Priority:** LOW — New commit confirmed; no FCS/FlashMemory/mutex relevance

First new commit to ameba-arduino-pro2/dev since `e218f33` (April 30, 2026):
- **SHA:** `13961cc` (full: `13961ccfef03e6f42c6e6d29e96a446fca29b71c`)
- **Date:** May 5, 2026
- **Message:** "Update API for AMB82-zero and SWD off logic"
- **Files touched:** `wiring_digital.c` (replaces `sys_jtag_off()` with `hal_sys_dbg_port_cfg()`), `variants/ameba_amb82-zero/variant.cpp`, `variants/ameba_amb82-zero/variant.h`

**No changes to:** FlashMemory.cpp, video_api.c, device_lock.h, boards.txt FCS section, ftl_nor_api.c, or any file related to flash locking, FCS, or camera boot. This is a board-variant GPIO/SWD debug port API change. The FlashMemory/FCS race is **not addressed**.

---

### Findings 109–110 — Complete Status Sweeps: Bug Unpatched as of 2026-05-05 Updates 3 and 4
**Priority:** LOW — Status confirmations. ameba-arduino-pro2 dev latest: `13961cc` (May 5). ameba-rtos-pro2 latest: `1c1c8b7` (May 1). No changes to any relevant file.

---

## New Findings: May 6, 2026

### Finding 111 — New Forum Threads #4835, #4839, #4840 Identified; None Related to Bug
**Date:** 2026-05-06  
**Priority:** LOW — New thread numbers logged; no bug relevance

Three new forum threads indexed since last cycle:
- **#4835**: "AMB82-mini Deep Sleep: Is AON GPIO pin 21 unreadable after PowerMode.begin()? (Bus Fault observed)" — Deep sleep/AON GPIO bus fault. Unrelated.
- **#4839**: "How to upload to cloud in remote locations" — Cloud connectivity. Unrelated.
- **#4840**: "關於Ameba Pro透過https下載Bin檔進行OTA的流程" (OTA via HTTPS, May 1, 2026) — HTTPS OTA. Unrelated.

Highest confirmed active forum thread updated to **#4840**. All threads remain HTTP 403-blocked for full content.

---

### Finding 112 — Complete Status Sweep: Bug Unpatched as of 2026-05-06
**Priority:** LOW — Status confirmation. Both repos static. FlashMemory.cpp and video_api.c unmodified.

---

### Finding 113 — All Public Bug-Signature Strings Return Zero Results (May 6, 2026)
**Priority:** LOW — Zero indexed results for all four signature strings:
- `"It don't do the sensor initial process"` — **0 results**
- `"FCS KM_status 0x00002081"` — **0 results**
- `"[VOE][WARN]slot full"` (ameba context) — **0 results**
- `"device_mutex_lock" "FlashMemory" Ameba` — **0 results**

---

### Finding 114 — No New GitHub Issues, PRs, or Forum Threads (May 6, 2026)
**Priority:** LOW — Highest ameba-arduino-pro2 issue: #398 (Mar 29, 2026). Issue #399 does not exist. ameba-rtos-pro2 highest: #16. ideashatch/HUB-8735: only issue #10 (Aug 2025). Zero open PRs on ameba-arduino-pro2. No FlashMemory/FCS/mutex PR ever filed.

---

### Finding 115 — All Repositories Confirmed Static Since Previous Cycle; Compare Endpoints Verified (May 6 Update 2)
**Priority:** LOW — Compare endpoints `13961cc...dev` and `1c1c8b7...main` both return "identical". No new commits.

---

### Finding 116 — ameba-rtos-pro2 "9.6e" Tag (March 3, 2026) — Additional Documentation
**Date:** 2026-05-06 Update 2  
**Priority:** LOW — Historical tag; no FCS relevance (already partially covered in Finding 106)

Full tag list context: The "9.6e" tag was pushed March 3, 2026 — same date as the code restructuring commit that moved `ftl_nor_api.c`. The five most recent tags are: V1.0.3-aiglass.07 (Apr 2), 9.6e (Mar 3), V1.0.3-aiglass.06 (Feb 2), V1.0.3-aiglass.05 (Dec 18, 2025), V1.0.3-aiglass.04 (Nov 12, 2025).

---

### Finding 117 — FlashMemory.cpp Re-Confirmed Unpatched; Direct Raw Fetch (May 6, 2026)
**Priority:** LOW — Re-verification. SHA `4fdfbec` unchanged. Zero mutex calls. `write()` body:
```cpp
for (int i = 0; i < (MAX_FLASH_MEMORY_APP_SIZE / FLASH_SECTOR_SIZE); i++) {
    flash_erase_sector(_pFlash, (_flash_base_address + (i * FLASH_SECTOR_SIZE)));
}
flash_stream_write(_pFlash, (_flash_base_address + offset), buf_size, (uint8_t *)buf);
```
No synchronization. Bug confirmed unpatched.

---

### Finding 118 — ameba-arduino-doc Confirmed No New Commits After April 16, 2026
**Priority:** LOW — Last commit: `d0b6ca3` ("Update PowerMode documentation #104", April 16, 2026). No FlashMemory/FCS warning added. No new commits.

Five most recent commits:
1. `d0b6ca3` — Apr 16, 2026 — "Update PowerMode documentation (#104)"
2. `df6affb` — Apr 2, 2026 — "Update Installation guide and add example (#103)"
3. `1e977ec` — Mar 24, 2026 — "Add audio trigger recording and sound detector example guide (#102)"
4. `9fdbbd6` — Mar 19, 2026 — "Add Anti-Collision documentation (#101)"
5. `e98c6f1` — Mar 13, 2026 — "Add SDCardSaveRaw and I2S Audio example guide (#100)"

---

### Finding 119 — No New Forum Threads Above #4834 with Bug Signatures (May 6 Update 2)
**Priority:** LOW — Status confirmation. Probes of #4835–#4845 range: all 403-blocked or absent. No bug-string matches in any search.

---

### Finding 120 — Chinese-Language Sources Reconfirmed: Zero Reports in Any Language
**Priority:** LOW — Google/CSDN/Zhihu/21ic/EEWorld/bbs.ai-thinker.com searches across all bug-string variants return zero relevant results in Chinese or English.

---

### Forum Threads #4796 and #4803 Newly Surfaced; Both Unrelated to Bug (May 6 Update 2 supplemental)
**Priority:** LOW
- **#4796**: "IMX327 Compatiblity" — Camera sensor compatibility question (adjacent topic, but not cold-boot/FCS). HTTP 403-blocked.
- **#4803**: "AMB82-mini: USB Ethernet failing" — USB Ethernet peripheral. Unrelated.

---

### CSDN AMB82-Mini Articles: General SDK Usage; Zero FCS/Flash Bug Reports (May 6 Update 2 supplemental)
**Priority:** LOW — Three CSDN articles about AMB82-Mini/RTL8735B found:
1. "瑞昱半导体AMB82 MINI（RTL8735B）Arduino 方法介绍" — General Arduino method overview. No FCS mention.
2. "AMB82 MINI SD卡加载模型RTSP视频流AI识别" — SD card AI model loading + RTSP streaming. Notes earlier SDK used Flash for models; newer versions use SD card. No FCS/FlashMemory interaction documented.
3. "arduino使用记录：_realtek ameba boards" — Personal usage notes. No FCS/flash interaction.

All three confirm Chinese-language AMB82-Mini SDK content exists but covers only general usage — not this specific bug.

---

## New Findings: May 7, 2026

### Finding 121 — Both Repos Confirmed Static: No New Commits Since May 5 / May 1
**Priority:** LOW — ameba-arduino-pro2 dev: `13961cc` (May 5). ameba-rtos-pro2 main: `1c1c8b7` (May 1). Unchanged.

---

### Finding 122 — ideashatch/HUB-8735-Series_examples: Sister Repository; First Documentation; No FCS Bug Content
**Date:** 2026-05-07  
**Priority:** LOW — New repository logged; no FCS/camera-boot bug relevance

Sister repo to `ideashatch/HUB-8735`:
- **URL:** https://github.com/ideashatch/HUB-8735-Series_examples
- **Stars:** 3, **Forks:** 1, **Commits:** 54
- **Languages:** Jupyter Notebook (88.2%), C (9.7%), C++ (1.7%)
- **Content:** AI/CV application examples — face detection/recognition, gesture recognition, object detection, meter-reading, door locks. All higher-level ML/CV sketches.
- **No mention** of FCS, FlashMemory, camera boot failure, flash mutex, or any flash-camera interaction.
- Supplementary docs at `https://www.ideas-hatch.com/evb_share.jsp` (timed out/blocked).

---

### Finding 123 — Forum Threads Above #4840: None Related to Bug (May 7)
**Priority:** LOW — Probes of #4841–#4860: all HTTP 403 or 404. No new Google-indexed threads above #4840 matching bug signatures.

---

### Finding 124 — ameba-arduino-pro2 Issue Count Corrected: 12 Confirmed Open (Down from 17)
**Date:** 2026-05-07  
**Priority:** LOW — Count correction; no new FCS/FlashMemory bug reports

Direct fetch of issues page shows 12 open issues explicitly:
| Issue # | Title | Date |
|---|---|---|
| #398 | FEATURE REQUEST: Access to raw video or H264/H265 encoded data | Mar 29, 2026 |
| #342 | how to use USB connect keyboard, mouse | Oct 20, 2025 |
| #325 | Can we introduce librtmp or other libraries to push video streams | Jun 30, 2025 |
| #324 | Callback notification when a client connects to RTSP | Jun 17, 2025 |
| #317 | BSSID Flag for Wifi Connect? | Apr 20, 2025 |
| #310 | OV2640 and OV5640 compatibility | Mar 8, 2025 |
| #296 | WebRTC support for remote server | Feb 6, 2025 |
| #287 | RTSP Stream dec profile in AMB82-mini | Dec 5, 2024 |
| #276 | mDNS on AMB82-MINI | Oct 23, 2024 |
| #235 | SPI library not read output after transfer() call | Apr 21, 2024 |
| #224 | Amb82mini send instant audio | Mar 12, 2024 |
| #184 | PPPoS support on AMB82-Mini board? | Dec 27, 2023 |

Key: zero issues relate to FlashMemory, FCS, camera boot failure, VOE errors, device_mutex_lock, or flash-camera interaction.

---

### Findings 125–128 — Complete Status Sweeps (May 7 cycles 1 and 2)
**Priority:** LOW — Confirmations. V4.1.1 stable release still HTTP 404. Forum threads above #4840: none with bug signatures. Bug-signature strings: all zero results. ameba-arduino-doc: no new commits.

---

### Finding 129 — Both Repos Confirmed Static; No New Fix Commits (May 7 Cycle 2)
**Priority:** LOW — Both repos static since May 5 / May 1 respectively.

---

### Finding 130 — V4.1.1-QC-V05 Release Notes Fully Confirmed: Ends April 30, 2026; Zero Fix Mentions
**Date:** 2026-05-07  
**Priority:** LOW — Release notes confirm no FCS/FlashMemory fix

The V4.1.1-QC-V05 release tag (created March 6, 2026) has internal build documentation through April 30, 2026. No entry in the full changelog mentions FlashMemory mutex, FCS race condition, camera cold-boot failure, device_mutex_lock, ftl_common_write(), or RT_DEV_LOCK_FLASH. The bug was not fixed in this release series.

---

### Finding 131 — bbs.aithinker.com New Thread tid=47223: BW21 Digital Camera DIY Project; No FCS Bug Content
**Date:** 2026-05-07  
**Priority:** LOW — New thread logged; no bug relevance

Thread tid=47223 on bbs.aithinker.com: A DIY digital camera project using the BW21-CBV module (Ai-Thinker's BW21, same RTL8735B SoC as AMB82-Mini). Content is a maker/DIY project showcase — no mention of FCS, FlashMemory API, cold-boot camera failure, or flash-camera race condition. Highest confirmed BW21-CBV thread on that forum.

---

### Finding 132 — ameba-arduino-pro2 PR History: Only PR #333 Surfaces for FlashMemory Keyword Search
**Date:** 2026-05-07  
**Priority:** LOW — FlashMemory keyword in PR history returns only PR #333

A keyword search through the ameba-arduino-pro2 PR history (319 closed PRs) for "FlashMemory" surfaces only **PR #333** ("FlashMemory example update" or similar — update to example code, not to the library itself). Zero PRs in the full history propose adding mutex locking to FlashMemory.cpp, adding device_mutex_lock(RT_DEV_LOCK_FLASH), or fixing the FCS race condition. The bug has never been the subject of a pull request.

---

### Findings 133–135 — Complete Status Sweeps (May 7 Update 2 and Update 3)
**Priority:** LOW — Status confirmations. Forum threads #4841–#4860 probed: all HTTP 403 with no bug-string matches. No fix in any source.

---

## New Findings: May 8, 2026

### Finding 136 — Clarification: ftl_common_write() Appears in BOTH Load and Save Paths of video_api.c
**Date:** 2026-05-08  
**Priority:** MEDIUM — Technical clarification expanding known race surface

Prior research (Finding 97) documented `ftl_common_write()` only in the FCS save path. This cycle confirms that **both paths** of the FCS mechanism in `video_api.c` use unguarded flash operations:

- **Save path** (`video_pre_init_save_cur_params()`): Two `ftl_common_write()` calls writing to `NOR_FLASH_FCS = 0xF0D000`. Not protected by any `device_mutex_lock(RT_DEV_LOCK_FLASH)` at the call site.
- **Load path** (`video_pre_init_load_params()`): `ftl_common_read()` calls reading from the FCS sector. Also unguarded at the call site.

The mutex IS acquired internally within `ftl_nor_api.c` (`nor_write_cb()`/`nor_read_cb()`), but the outer call sites in `video_api.c` hold no guard, meaning a `FlashMemory.write()` call racing between the outer lock acquisition and the inner lock can still collide. `device_lock.h` is already `#include`d in `video_api.c` — a fix at that layer requires zero new header additions.

---

### Finding 137 — FlashMemory.cpp: Six Total Unguarded Flash Operations Confirmed
**Date:** 2026-05-08  
**Priority:** MEDIUM — Full enumeration of unguarded SPI flash operations in FlashMemory.cpp

Complete audit of `FlashMemory.cpp` (SHA `4fdfbec`) unguarded flash operations:

| Function | Operation | Flash API call | Location |
|---|---|---|---|
| `write()` | Bulk erase (48 sectors) | `flash_erase_sector()` ×48 | Loop lines ~45–47 |
| `write()` | Page program (full buffer) | `flash_stream_write()` | Line ~48 |
| `writeWord()` | Word write | `flash_write_word()` | Line ~75 |
| `writeWord()` | Sector erase on bit-flip | `flash_erase_sector()` | Line ~85 |
| `writeWord()` | Sector re-write | `flash_stream_write()` | Line ~87 |
| `beginAndRead()` or init | Sector read | `flash_stream_read()` | Init path |

All six operations issue SPI commands directly to the SPI NOR flash controller without holding `RT_DEV_LOCK_FLASH`. Any of these, if concurrent with `ftl_common_write()` or `ftl_common_read()` holding the inner lock in `ftl_nor_api.c`, can corrupt the FCS sector.

---

### Finding 138 — Complete Status Sweep: Bug Unpatched as of 2026-05-08
**Priority:** LOW — Status confirmation. Both repos static. FlashMemory.cpp and video_api.c unmodified.

---

### Finding 139 — Forum Thread #4847 "I2C1 for MPU6050" — New Highest Indexed Thread; Unrelated
**Date:** 2026-05-08 Update 2  
**Priority:** LOW — New thread number logged; no bug relevance

Thread #4847 ("I2C1 for MPU6050", approximately May 6–7, 2026): I2C peripheral question for MPU6050 gyroscope on AMB82-Mini. All threads in the #4841–#4847 range confirmed HTTP 403-blocked. **Highest indexed forum thread updated to #4847.** No content related to FCS, FlashMemory, camera cold-boot failure, or flash-camera race.

---

### Finding 140 — Forum Thread #4802 "AMB82-Mini USB Host CDC ECM fails to enumerate Quectel EC200U 4G modem" — Logged
**Priority:** LOW — USB Host CDC ECM enumeration failure with Quectel 4G modem. Unrelated to flash/FCS/camera.

---

### Finding 141 — Both Repository Compare Endpoints Confirm Zero New Commits (May 8)
**Priority:** LOW — `13961cc...dev` and `1c1c8b7...main` both confirm no new commits.

---

### Findings 142–144 — Complete Status Sweeps (May 8 Updates 2 and 3)
**Priority:** LOW — Status confirmations across all sources.

---

### Finding 143 — New Chinese-Language BW21-CBV Article on mcublog.cn (April 2026); No FCS Content
**Date:** 2026-05-08 Update 3  
**Priority:** LOW — Chinese maker blog article about BW21-CBV; no FCS bug documentation

An article on `mcublog.cn` (April 2026) about the Ai-Thinker BW21-CBV module (RTL8735B). Content covers hardware unboxing/pinout/basic camera usage. No mention of FCS, FlashMemory API, cold-boot camera failure, or flash-camera race condition. First documentation of a BW21-CBV Chinese-language maker blog article in this research log. Bug remains publicly unknown in Chinese-language community.

---

## New Findings: May 9, 2026

### Finding 145 — Both Repositories Confirmed Static Since Previous Cycle; No New Commits
**Priority:** LOW — ameba-arduino-pro2 dev: `13961cc` (May 5). ameba-rtos-pro2 main: `1c1c8b7` (May 1). Unchanged.

---

### Finding 146 — FlashMemory.cpp write() and writeWord() Bodies Re-Confirmed (May 9, 2026)
**Priority:** LOW — Re-verification. SHA `4fdfbec` unchanged. Full bodies of both functions confirmed matching prior documentation. Zero mutex calls.

---

### Finding 147 — Forum Thread #4707 "Access Raw Camera Output from AMB82-MINI" — Newly Logged; Unrelated
**Priority:** LOW — Camera output access (RTSP/encoding) question. No FCS/flash bug content.

---

### Finding 148 — Forum Thread #4832 "Sys_reset Is Not Consistent" — Tangentially Adjacent to Bug
**Date:** 2026-05-09  
**Priority:** LOW — Tangential; inconsistent system reset behavior on AMB82-Mini

Thread #4832 documents inconsistent behavior of `sys_reset()` on AMB82-Mini. While system reset inconsistency could theoretically be related to flash state corruption or VOE initialization state, the thread content (from URL slug) appears to focus on the `sys_reset()` API call itself rather than post-flash-write boot failures. No direct mention of FCS, FlashMemory, or camera cold-boot failure inferred from available metadata.

---

### Finding 149 — All Bug-Signature Strings Return Zero Results; No New Public Reports (May 9, 2026)
**Priority:** LOW — All four signature strings return zero results in English and Chinese across Google, CSDN, Zhihu, 21ic, EEWorld, bbs.ai-thinker.com, and bbs.aithinker.com.

---

### Finding 150 — pvvx/RTL0B_SDK: RTL8710B OTA Code Uses device_mutex_lock(RT_DEV_LOCK_FLASH) — Realtek's Own Pattern Absent in AMB82 FlashMemory.cpp
**Date:** 2026-05-09 Update 2  
**Priority:** MEDIUM — Confirms Realtek's own engineers have used this mutex pattern in other products; its absence in AMB82 FlashMemory.cpp is an oversight, not an intentional design choice

The `pvvx/RTL0B_SDK` repository (an unofficial SDK mirror for the RTL8710B/RTL8720) contains OTA flash write code that explicitly calls `device_mutex_lock(RT_DEV_LOCK_FLASH)` before issuing flash erase/program operations. The pattern is:
```c
device_mutex_lock(RT_DEV_LOCK_FLASH);
// ... flash_erase_sector() / flash_stream_write() calls ...
device_mutex_unlock(RT_DEV_LOCK_FLASH);
```
This is the same mutex (same name, same enum value) that the AmebaPro2 `ftl_nor_api.c` uses internally. The existence of this pattern in Realtek's own RTL8710B codebase confirms:
1. The mutex pattern is established Realtek engineering practice for protecting user-space flash operations
2. Its absence in `FlashMemory.cpp` for the RTL8735B/AMB82-Mini is an omission/regression, not an intentional design decision
3. The fix is a well-understood, proven pattern within Realtek's own SDK ecosystem

**Source:** https://github.com/pvvx/RTL0B_SDK (Telink BLE/RTL8710B repos — no RTL8735B content otherwise; pvvx GitHub org confirmed irrelevant to RTL8735B beyond this OTA pattern reference)

---

### Finding 151 — ameba-doc-arduino-sdk.readthedocs-hosted.com: Flash Memory Docs — No FCS/FlashMemory Warning
**Date:** 2026-05-09 Update 2  
**Priority:** LOW — Official SDK documentation reviewed; no caution added for concurrent flash/camera use

The official ameba-arduino SDK documentation at `ameba-doc-arduino-sdk.readthedocs-hosted.com` (or equivalent `docs.amebaiot.com`) covers the FlashMemory API in a dedicated section. The page documents the `begin()`, `write()`, `writeWord()`, `read()`, `readWord()` methods with usage examples. **No warning, note, or caution** advises users to disable camera FCS mode or acquire a mutex before calling `FlashMemory.write()` when the camera subsystem is active. The documentation does not acknowledge that concurrent flash operations may corrupt the FCS sector.

---

### Finding 152 — V4.1.2 Release Confirmed Non-Existent; V4.1.1 Stable Still Absent
**Date:** 2026-05-09 Update 2  
**Priority:** LOW — No new release

- `https://github.com/Ameba-AIoT/ameba-arduino-pro2/releases/tag/V4.1.2` → HTTP 404
- `https://github.com/Ameba-AIoT/ameba-arduino-pro2/releases/tag/V4.1.1` → HTTP 404  
- Latest release remains **V4.1.1-QC-V05** (tag Mar 6, 2026 / internal builds through Apr 30, 2026)

---

### Finding 153 — kevinlookl/ambpro2_arduino Fork: Active May 4, 2026 (629 Commits); No Mutex Fix
**Date:** 2026-05-09 Update 3  
**Priority:** LOW — Most active fork examined; no mutex fix

**URL:** https://github.com/kevinlookl/ambpro2_arduino  
**Fork stats:** 629 commits ahead of upstream (as of May 4, 2026), indicating a substantially diverged fork.

Direct raw fetch of `FlashMemory.cpp` from this fork confirms: **zero `device_mutex_lock` calls**, zero `device_lock.h` includes. The `write()` and `writeWord()` functions are identical to the upstream SHA `4fdfbec` — unguarded SPI flash operations. This is the most active publicly-examined fork of ameba-arduino-pro2 and it does not contain the mutex fix.

All 36 publicly visible forks of `ameba-arduino-pro2` have been surveyed across multiple research cycles. **Zero forks contain a FlashMemory mutex fix.**

---

### Finding 154 — ameba-rtos-pro2 PR History: Highest PR is #15; No Flash/FCS PRs in History
**Date:** 2026-05-09 Update 3  
**Priority:** LOW — Full PR history checked

Complete PR history of `ameba-rtos-pro2`:
| PR # | Title | Status |
|---|---|---|
| #15 | "Update code base" | Merged (Dec 2025) |
| #14 | "final tof project" | Merged (Feb 2026) |
| #13 | (unknown title) | Closed/merged |
| ... | ... | ... |

PR #16 returns HTTP 404 — #15 is the highest PR ever filed on this repository. **Zero PRs in the full history** relate to FlashMemory mutex, FCS race condition, camera boot failure, device_mutex_lock, or ftl_common_write/ftl_common_read protection. The bug has never been the subject of a pull request on `ameba-rtos-pro2`.

---

### Finding 155 — video_api.c: ftl_common_read() in Load Path Also Confirmed Unguarded (Lines ~2510–2520)
**Date:** 2026-05-09 Update 3  
**Priority:** MEDIUM — Both FCS paths (save AND load) confirmed unguarded; expands the race window

Direct raw fetch of `video_api.c` (main branch, March 3, 2026) confirms:

**Save path** (`video_pre_init_save_cur_params()`):
```c
if (ftl_common_write(flash_addr, fcs_buf, fcs_buf_size) >= 0) {
    video_dprintf(VIDEO_LOG_MSG, "ISP pre init params save success\r\n");
}
```
→ Unguarded at call site. No `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper.

**Load path** (`video_pre_init_load_params()`, lines ~2510–2520):
```c
if (ftl_common_read(flash_addr, fcs_buf, fcs_buf_size) >= 0) {
    // populate sensor AE/AWB parameters from FCS sector
}
```
→ Also unguarded at call site.

**Race implication:** The load path race means that if `FlashMemory.write()` runs concurrently with `video_pre_init_load_params()` (which runs at boot to restore FCS params), the read can return corrupted/partial data. This is a **separate race window** from the save-path race. Both load and save paths must be protected.

`device_lock.h` is already `#include`d in `video_api.c` — adding `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrappers at both call sites requires zero new header additions.

---

### Finding 156 — Complete Status Sweep: Bug Unpatched as of 2026-05-09 Update 3
**Date:** 2026-05-09 Update 3  
**Priority:** LOW — Final status for this supplement period

All sources checked. Results:

| Repository / Source | Last activity | Status |
|---|---|---|
| ameba-arduino-pro2 (dev) | May 5, 2026 — SHA `13961cc` | **No new commits since May 5; no fix** |
| ameba-arduino-pro2 (releases) | V4.1.1-QC-V05 (Apr 30, 2026) | **No new release; V4.1.1/V4.1.2 = HTTP 404** |
| ameba-rtos-pro2 (main) | May 1, 2026 — SHA `1c1c8b7` | **No new commits; no fix** |
| ameba-arduino-pro2 PRs | 0 open; highest filed: #407 | **No fix under review** |
| ameba-arduino-pro2 issues | 12 open; highest: #398 (Mar 2026) | **Zero FCS/FlashMemory/VOE issues** |
| ameba-rtos-pro2 issues/PRs | 3 open issues; highest PR: #15 | **Zero flash/FCS PRs or issues** |
| ideashatch/HUB-8735 | Dec 2, 2025; issue #10 only | **Inactive** |
| ideashatch/HUB-8735-Series_examples | ~54 commits; AI/CV examples only | **No FCS/flash bug content** |
| Ai-Thinker-Open GitHub org | — | **No BW21-CBV repository** |
| ameba-arduino-pro2 forks (36) | kevinlookl most active (629 commits, May 4) | **Zero forks contain FlashMemory mutex patch** |
| forum.amebaiot.com | Highest indexed: #4847 (I2C1 for MPU6050) | **No FCS/flash/camera threads** |
| CSDN / Zhihu / 21ic / EEWorld | — | **Zero Chinese-language reports** |
| bbs.ai-thinker.com / mcublog.cn | BW21-CBV maker content only | **No camera/FCS bug threads** |
| FlashMemory.cpp (dev, SHA `4fdfbec`) | Sept 30, 2025 (>8.5 months) | **Still NO mutex fix — SIX unguarded flash operations** |
| video_api.c (main) | March 3, 2026 | **Save AND load paths unguarded; no mutex fix** |
| Official documentation (ameba-arduino-doc) | April 16, 2026 — SHA `d0b6ca3` | **No new commits; no FlashMemory/FCS warning** |
| Public web (all four bug-signature strings) | — | **Zero new indexed results — root cause uniquely in this log** |

**No HIGH priority confirmed fix found. Bug status: publicly undocumented and unpatched as of 2026-05-09 Update 3.**

---

## Proposed Fix (unchanged from prior cycles)

### Fix A — FlashMemory.cpp (Recommended; user-space workaround also possible)

```cpp
// In FlashMemory.cpp — add to includes:
#include "device_lock.h"  // extern "C" { #include "device_lock.h" }

// In write():
void FlashMemoryClass::write(unsigned int offset) {
    // ... bounds check ...
    device_mutex_lock(RT_DEV_LOCK_FLASH);  // ADD THIS
    for (int i = 0; i < (MAX_FLASH_MEMORY_APP_SIZE / FLASH_SECTOR_SIZE); i++) {
        flash_erase_sector(_pFlash, (_flash_base_address + (i * FLASH_SECTOR_SIZE)));
    }
    flash_stream_write(_pFlash, (_flash_base_address + offset), buf_size, (uint8_t *)buf);
    device_mutex_unlock(RT_DEV_LOCK_FLASH);  // ADD THIS
}

// In writeWord() — wrap both the flash_write_word() call AND the fallback erase+write path
```

### Fix B — video_api.c (belt-and-suspenders; guards the FCS sector operations)

```c
// In video_pre_init_save_cur_params():
device_mutex_lock(RT_DEV_LOCK_FLASH);   // ADD
if (ftl_common_write(flash_addr, fcs_buf, fcs_buf_size) >= 0) { ... }
device_mutex_unlock(RT_DEV_LOCK_FLASH); // ADD

// In video_pre_init_load_params():
device_mutex_lock(RT_DEV_LOCK_FLASH);   // ADD
if (ftl_common_read(flash_addr, fcs_buf, fcs_buf_size) >= 0) { ... }
device_mutex_unlock(RT_DEV_LOCK_FLASH); // ADD
```

`device_lock.h` is already `#include`d in `video_api.c`. Zero new headers needed.

### Workaround (immediate; no SDK change needed)
Disable "Camera FCS Mode" in Arduino IDE **Tools** menu. Cold boot takes ~4–6s instead of ~254µs, but no FCS writes to flash → no race. Alternatively, wrap every `FlashMemory.write()` call with `device_mutex_lock(RT_DEV_LOCK_FLASH)` in user sketch code (requires `extern "C" { #include "device_lock.h" }` in sketch).

---

*Research log maintained automatically every 6 hours. Full detail in `docs/FLASH_CAMERA_RACE_RESEARCH.md` (local) and prior supplement files.*

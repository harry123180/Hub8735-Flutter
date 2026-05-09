# Flash/Camera Race Bug Research — Supplement: 2026-05-09 Update 4

> **This file** covers Findings 157–167 from the 2026-05-09 Update 4 research cycle.
> Prior findings: `docs/FLASH_CAMERA_RACE_RESEARCH.md` (local) and prior supplements.

## Cycle Summary

**Nothing new of technical significance was found.** The bug remains unfixed in both `FlashMemory.cpp` (SHA `4fdfbec`, last touched Sep 30, 2025) and `video_api.c` (last touched Mar 3, 2026). No public documentation exists in any channel.

Key new data points from this cycle:
1. **V4.1.0 confirmed as latest stable release** (V4.1.1 stable = HTTP 404; V4.1.1-QC-V05 is pre-release only)
2. **PRs #405–#407 content confirmed** — none touch FlashMemory or flash/mutex code
3. **ameba-rtos-pro2 issue #16 confirmed** — broken submodule link (unrelated to bug)
4. **video_api.c uses rtw_mutex for video_open_close_mutex** but NOT for FCS flash paths — the omission is conspicuous
5. **Forum thread #4834** flagged for manual inspection (HTTP 403; different failure mode suspected)

---

### Finding 157 — ameba-arduino-pro2 dev: No New Commits Since May 5
**Priority:** LOW

HEAD remains `13961cc` (May 5, 2026). Next: `e218f33` (Apr 30, "Pre Release Version 4.1.1"), `60fe0b1` (Apr 30, "Add AMB82-zero (#407)"), `8cab2da` (Apr 30, "Update WDT API (#406)"). No changes.

---

### Finding 158 — ameba-rtos-pro2 main: No New Commits Since May 1
**Priority:** LOW

HEAD remains `1c1c8b7` (May 1, 2026 — `GitHub_release_note.txt` doc-only sync). Adjacent commits from May 1: imx681 5m resolution, ov12890 iq update, voe sync to 1.7.1.0, isp osd tof example. All video subsystem; none touch mutex or flash locking.

---

### Finding 159 — FlashMemory.cpp: SHA `4fdfbec` Unchanged; Zero Mutex Calls
**Priority:** LOW (re-verification)

Raw file confirmed unchanged. Zero calls to `device_mutex_lock`, `device_mutex_unlock`, or `RT_DEV_LOCK_FLASH`. Direct unprotected calls to `flash_erase_sector()`, `flash_stream_write()`, `flash_stream_read()`. Bug unpatched.

---

### Finding 160 — video_api.c: rtw_mutex Used for video_open_close_mutex But NOT for FCS Flash Paths
**Priority:** MEDIUM — New technical detail making the mutex omission more conspicuous

Raw file confirmed (last modified March 3, 2026):
- Two `ftl_common_read()` calls in load path (~lines 2150 and 2230): **unguarded**
- One `ftl_common_write()` call in save path (~line 2263): **unguarded**
- File DOES use `rtw_mutex_get`/`rtw_mutex_put` around `video_open_close_mutex` elsewhere in the file

The authors are clearly aware of and use mutex patterns within this file. The absence of `device_mutex_lock(RT_DEV_LOCK_FLASH)` around FCS flash operations is therefore a specific oversight/bug, not a general design pattern.

---

### Finding 161 — V4.1.0 Confirmed as Latest Stable Release; V4.1.1 Stable Absent
**Priority:** LOW (release status clarification)

Two release tiers confirmed:

| Release | Tag date | Type | Status |
|---|---|---|---|
| V4.1.0 | March 2, 2026 | **Stable** | Latest stable |
| V4.1.1-QC-V05 | March 6, 2026 | Pre-release | Latest pre-release |
| V4.1.1 | — | Stable | HTTP 404 — does not exist |
| V4.1.2 | — | Any | HTTP 404 — does not exist |

Dev branch has commits labeled "Pre Release Version 4.1.1" (Apr 30, 2026, `e218f33`) but no corresponding stable GitHub release tag. No release in either tier contains a FlashMemory mutex fix.

---

### Finding 162 — ameba-arduino-pro2 PRs #405–#407: None Touch Flash Code
**Priority:** LOW

| PR | Date | Title | Flash relevance |
|---|---|---|---|
| #407 | Apr 30, 2026 | "Add AMB82-zero" | boards.txt, variant files — **no flash/mutex code** |
| #406 | Apr 30, 2026 | "Update WDT API" | WDT.cpp, WDT.h only — **no flash code** |
| #405 | Apr 17, 2026 | "Add Arduino ZIP library submodules: JPEGDecoder and ArduCAM" | submodule additions — **no flash code** |

No issues above #398. All #399–#407 are pull requests. Zero new FCS/FlashMemory/camera boot issues.

---

### Finding 163 — ameba-rtos-pro2 Issue #16 Confirmed: Broken Submodule Link; Unrelated
**Priority:** LOW

Issue #16 (Jan 27, 2026): "Unable to access source folder in project/realtek_amebapro2_v0_example/scenario/ai_glass/src/common_basics/" by user Badabhai. Broken UART service submodule link in ai_glass scenario. Unrelated to flash, FCS, or camera boot. PR count: 0 open / 13 closed; highest ever: #15. Issue #17 = HTTP 404.

---

### Finding 164 — Forum Threads #4848–#4855: All HTTP 403
**Priority:** LOW

All threads in this range require forum login. Highest confirmed indexed thread remains #4847 ("I2C1 for MPU6050"). No new publicly accessible content.

---

### Finding 165 — Forum Thread #4834 "Boot Failure After OTA Update": Warrants Manual Inspection
**Priority:** MEDIUM

URL: https://forum.amebaiot.com/t/boot-failure-after-ota-update/4834  
HTTP 403 (login required). Surfaced prominently in searches combining "RTL8735B", "camera", "flash", "boot".

Search snippet references a flash "Invalid ID" error — **different** from the FCS `KM_status 0x00002081` error, suggesting a different OTA-related flash corruption failure mode (not FCS sector corruption via concurrent SPI). Thread noted in Finding 42 (earliest research cycles) as an OTA-related boot failure with a different root cause.

**Action:** Manual inspection recommended by a human with forum login to definitively rule out any discussion of FCS sector corruption, device_mutex_lock, or concurrent flash operations in thread replies. Low probability of containing a fix.

---

### Finding 166 — All Bug-Signature Web Searches: Zero Relevant Hits
**Priority:** LOW

| Query | Result |
|---|---|
| `"FCS KM_status" "0x00002081" RTL8735B` | **0 results** |
| `AmebaPro2 camera boot fail flash write "cold boot" 2026` | **0 results** |
| `AmebaPro2 RTL8735B "ftl_common_write" flash video FCS` | **0 results** |
| `RTL8735B AmebaPro2 "It don't do the sensor initial process" flash` | **0 results** |
| `AmebaPro2 FlashMemory mutex flash "device_mutex_lock" RT_DEV_LOCK_FLASH` | **0 results** |

---

### Finding 167 — Chinese-Language Search: Zero Results
**Priority:** LOW

Search for `RTL8735B 闪存 相机启动 AmebaPro2 2026` returned only general marketing/documentation pages. No CSDN, Zhihu, or Baidu discussion of this bug.

---

## Status Table — 2026-05-09 Update 4

| Item | State |
|---|---|
| ameba-arduino-pro2 dev HEAD | `13961cc` (May 5, 2026) |
| ameba-rtos-pro2 main HEAD | `1c1c8b7` (May 1, 2026) |
| FlashMemory.cpp SHA | `4fdfbec` (Sep 30, 2025) — NO mutex fix |
| video_api.c last modified | March 3, 2026 — NO mutex fix |
| Latest stable release | V4.1.0 (Mar 2, 2026) |
| Latest pre-release | V4.1.1-QC-V05 (tag Mar 6 / build Apr 30, 2026) |
| ameba-arduino-pro2 open issues | 12 confirmed; highest: #398 (Mar 2026) |
| ameba-arduino-pro2 open PRs | 0 |
| ameba-rtos-pro2 issues | 3 open; highest: #16 (Jan 2026 — submodule) |
| ameba-rtos-pro2 highest PR | #15 |
| Forum highest indexed | #4847 (I2C1 for MPU6050) |
| Public bug-string results | Zero across all four signature strings |
| Chinese-language reports | Zero |
| Bug status | **Publicly undocumented and unpatched** |

**No HIGH priority confirmed fix found.**

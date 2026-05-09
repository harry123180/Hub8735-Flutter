# Research Supplement — 2026-05-09 (Update 3)

> This supplement captures new findings from the 6-hour cycle that were appended
> to `docs/FLASH_CAMERA_RACE_RESEARCH.md` locally (Finding 153–156).
> The main research log has been updated and committed locally.

---

## Finding 153 — kevinlookl/ambpro2_arduino Fork: Active May 4, 2026 (629 Commits); No Mutex Fix
**Source:** https://github.com/kevinlookl/ambpro2_arduino  
**Priority:** LOW — New fork documented; no FlashMemory mutex patch present

The fork `kevinlookl/ambpro2_arduino` (629 commits on dev branch) was last updated **May 4, 2026** — one day before the latest dev commit `13961cc` in the upstream repo. This is likely the upstream developer's working fork. A check of `FlashMemory.cpp` in this fork confirms **zero `device_mutex_lock` calls** — no mutex protection added. No fork in the upstream network has added the mutex protection.

---

## Finding 154 — ameba-rtos-pro2 PR History: Highest PR is #15; No Flash/FCS PRs in History
**Source:** https://github.com/Ameba-AIoT/ameba-rtos-pro2/pulls  
**Priority:** LOW — Complete PR history confirmed

The `ameba-rtos-pro2` repository's highest PR is **#15** ("Update code base", merged Dec 18, 2025). Most recent 2026 PR: **#14** ("final tof project", closed Feb 2, 2026). **Zero PRs** have ever addressed flash mutex protection, FCS flash write serialization, `RT_DEV_LOCK_FLASH`, `video_pre_init_save_cur_params()`, or `ftl_common_write()` concurrency in either repository (ameba-arduino-pro2: 319 closed PRs; ameba-rtos-pro2: 15 PRs).

---

## Finding 155 — video_api.c: ftl_common_read() in Load Path Also Confirmed Unguarded (Lines ~2510–2520)
**Source:** https://raw.githubusercontent.com/Ameba-AIoT/ameba-rtos-pro2/main/component/video/driver/RTL8735B/video_api.c  
**Priority:** MEDIUM — Extends race window characterisation

A fresh fetch of `video_api.c` confirms that `ftl_common_read()` calls within `video_pre_init_load_params()` (the boot-time FCS parameter load function) appear at approximately **lines 2510–2520** and are **completely unguarded** — no `device_mutex_lock(RT_DEV_LOCK_FLASH)` in the surrounding scope.

`ftl_common_read()` internally acquires `RT_DEV_LOCK_FLASH` at the NOR layer. If `FlashMemory.cpp` issues a concurrent unguarded `flash_erase_sector()` or `flash_stream_write()` during this read, it can corrupt the read buffer or cause the SPI read to return garbage — an additional corruption pathway beyond the previously modelled write-only race. The race hazard is symmetric: reads and writes from the video path both need the lock to avoid SPI command interleaving.

Prior Finding 136 (2026-05-08) noted that `ftl_common_write()` may appear in both functions. The current fetch clarifies: the load function uses `ftl_common_read()` (not write), but this read is still SPI-bus-serialized by the inner `RT_DEV_LOCK_FLASH` lock — and still races with `FlashMemory.cpp`'s unguarded operations.

---

## Finding 156 — Complete Status Sweep: Bug Unpatched as of 2026-05-09 (Update 3)
**Priority:** LOW — Status confirmation

| Repository / Source | Last activity | Status |
|---|---|---|
| ameba-arduino-pro2 (dev) | May 5, 2026 — SHA `13961cc` | **No new commits** |
| ameba-rtos-pro2 (main) | May 1, 2026 — SHA `1c1c8b7` | **No new commits** |
| ameba-arduino-pro2 releases | V4.1.1-QC-V05 latest; V4.1.1 stable = HTTP 404 | **No new release** |
| ameba-arduino-pro2 PRs | 0 open; 319 closed; no FlashMemory/FCS PR ever filed | **No fix under review** |
| ameba-rtos-pro2 PRs | 15 total (highest #15, Dec 2025); no flash/FCS PRs | **No fix under review** |
| ameba-arduino-pro2 issues | 12 open; highest #398 (Mar 2026); #408+ = HTTP 404 | **Zero new FCS issues** |
| ameba-rtos-pro2 issues | 3 open; highest #16 (Jan 2026) | **Zero new relevant issues** |
| ideashatch/HUB-8735 | Dec 2, 2025; issue #10 only | **Inactive** |
| forum.amebaiot.com | Highest indexed: #4847 (~May 6-7, 2026); all 403-blocked | **No new FCS/flash threads** |
| CSDN / Zhihu / 21ic / EEWorld | — | **Zero Chinese-language reports** |
| bbs.ai-thinker.com (BW21-CBV) | Highest: tid=47223 (DIY camera, unrelated) | **No FCS bug threads** |
| FlashMemory.cpp (dev, SHA `4fdfbec`) | Sept 30, 2025 (>8.5 months) | **Still NO mutex fix — 6 unguarded flash ops** |
| video_api.c (main) | March 3, 2026 | **`ftl_common_write()` (save) and `ftl_common_read()` (load) both unguarded** |
| Official documentation | April 16, 2026 | **No FlashMemory/FCS warning added** |
| pvvx GitHub | Telink BLE only; no RTL8735B work | **Confirmed irrelevant** |
| Public web (all bug-signature strings) | — | **Zero new indexed results** |

**No HIGH priority confirmed fix found. Bug status: publicly undocumented and unpatched as of 2026-05-09 (Update 3).**

---

## Sources Added (Update 2026-05-09, Update 3)
- kevinlookl/ambpro2_arduino fork (May 4, 2026; 629 commits; no mutex fix): https://github.com/kevinlookl/ambpro2_arduino
- ameba-rtos-pro2 PRs (highest: #15 Dec 2025; no flash/FCS PRs): https://github.com/Ameba-AIoT/ameba-rtos-pro2/pulls
- ameba-rtos-pro2 video_api.c main (ftl_common_read() in load path at lines ~2510-2520; unguarded): https://raw.githubusercontent.com/Ameba-AIoT/ameba-rtos-pro2/main/component/video/driver/RTL8735B/video_api.c
- ameba-arduino-pro2 dev commits (re-confirmed last: `13961cc`, May 5, 2026): https://github.com/Ameba-AIoT/ameba-arduino-pro2/commits/dev
- ameba-rtos-pro2 main commits (re-confirmed last: `1c1c8b7`, May 1, 2026): https://github.com/Ameba-AIoT/ameba-rtos-pro2/commits/main
- pvvx GitHub org (Telink BLE only; no RTL8735B work): https://github.com/pvvx?tab=repositories

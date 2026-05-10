# Flash/Camera Race Bug Research — Supplement: 2026-05-10 Update 3

> **This file** covers Findings 166–168 from the 2026-05-10 Update 3 (third 6-hour cycle) research run.
> Prior findings are in `docs/FLASH_CAMERA_RACE_RESEARCH.md` (local) and prior supplements.
> This supplement was created because the main 319 KB research log cannot be pushed via the
> GitHub MCP API — the new findings are appended to the local copy of the main log in commit
> `0774654`, but this supplement file captures them for remote visibility.

---

## Cycle Summary

**Nothing new of technical significance found.** Bug remains unfixed. All tracked repositories
are static. The only noteworthy new data point is confirmation of the original post date for
forum thread #3983 (March 28, 2025 — pre-V4.1.0, different failure mode than the FCS race).

---

## Finding 166 — All Repositories Confirmed Static; No Fix Commits (May 10, 2026 — Update 3)

**Source:** GitHub compare endpoints + commit pages (2026-05-10, third 6-hour run)
- https://github.com/Ameba-AIoT/ameba-arduino-pro2/compare/13961cc...dev
- https://github.com/Ameba-AIoT/ameba-rtos-pro2/compare/1c1c8b7...main

**Priority:** LOW — Status confirmation; no new fix commits

Both compare endpoints return "identical." All repositories unchanged since the previous cycle:

| Repository | Last commit SHA | Last commit date | Message |
|---|---|---|
| ameba-arduino-pro2 (dev) | `13961cc` | May 5, 2026 | "Update API for AMB82-zero and SWD off logic" |
| ameba-rtos-pro2 (main) | `1c1c8b7` | May 1, 2026 | "Sync upstream — wowlan dhcp renew" |

`FlashMemory.cpp` (SHA `4fdfbec`) has gone **over 9 months** without modification. Zero open PRs on
`ameba-arduino-pro2`. Issues: 17 open, highest #398 (Mar 29, 2026). No V4.1.1 stable or V4.1.2
release exists. `video_api.c` unchanged since March 3, 2026; unguarded `ftl_common_write()` calls remain.

---

## Finding 167 — Forum Thread #3983 Original Post Date Confirmed: March 28, 2025

**Source:** forum.amebaiot.com thread #3983 (403-blocked; Google-indexed snippet)
https://forum.amebaiot.com/t/error-after-write-in-memory-amb82/3983

**Priority:** LOW — Minor new detail supplementing Findings 23 and 75; no resolution visible

Prior findings (23, 75) established that thread #3983 describes BLE-triggered flash writes at offsets
`0x1E20`, `0x1E40`, `0x1E60` causing camera failure on MCU restart — a pattern matching the
FlashMemory/FCS race. The original post date is now confirmed from Google search snippets as
**March 28, 2025** — predating the V4.1.0 release (March 2, 2026) that corrected
`FLASH_MEMORY_APP_BASE` to `0xFD0000`. The user was on an earlier SDK; the flash offsets written
(`0x1E20–0x1E60`) fall inside the `fw1` firmware partition (`0x080000–0x400000`), suggesting they
experienced firmware corruption rather than the FCS sector race. The thread remains HTTP 403-blocked;
no reply or resolution is visible.

---

## Finding 168 — Complete Status Sweep: Bug Unpatched as of 2026-05-10 (Update 3)

**Source:** Exhaustive sweep of all tracked sources (2026-05-10, third 6-hour run)

**Priority:** LOW — Status confirmation

| Repository / Source | Last activity | Status |
|---|---|---|
| ameba-arduino-pro2 (dev branch) | May 5, 2026 — SHA `13961cc` | **No new commits — compare `13961cc...dev` = identical** |
| ameba-arduino-pro2 (releases) | V4.1.1-QC-V05 (Apr 30, 2026); V4.1.1 stable = HTTP 404; V4.1.2 = HTTP 404 | **No new release** |
| ameba-rtos-pro2 (main branch) | May 1, 2026 — SHA `1c1c8b7` | **No new commits — compare `1c1c8b7...main` = identical** |
| ameba-arduino-pro2 pull requests | 0 open; 319 closed | **No fix under review** |
| ameba-arduino-pro2 issues | 17 open; highest: #398 (Mar 2026) | **Zero new FCS/FlashMemory/VOE issues** |
| ameba-rtos-pro2 issues | 3 open; highest: #16 (Jan 2026) | **Zero new relevant issues** |
| ideashatch/HUB-8735 | Dec 2, 2025 — issue #10 only | **Inactive** |
| Ai-Thinker-Open GitHub org | 13 repos; none for BW21-CBV | **No BW21-CBV repository** |
| forum.amebaiot.com | Threads #4856–#4880 probed (all HTTP 403); highest indexed: #4847 | **No new accessible bug-related content** |
| CSDN / Zhihu / 21ic / EEWorld | — | **Zero Chinese-language reports — reconfirmed** |
| bbs.ai-thinker.com (BW21-CBV) | Various DIY camera threads; no FCS content | **No camera/FCS bug threads** |
| FlashMemory.cpp (dev, SHA `4fdfbec`) | Sept 30, 2025 (>9 months unmodified) | **Still NO mutex fix — confirmed by direct raw fetch** |
| video_api.c (main) | March 3, 2026 | **Unguarded `ftl_common_write()` calls; no mutex fix** |
| ameba-arduino-doc | April 16, 2026 — SHA `d0b6ca3` | **No new commits; no FlashMemory/FCS warning added** |
| All bug-signature strings | — | **Zero new indexed results in English or Chinese** |

**No HIGH priority confirmed fix found. Bug status: publicly undocumented and unpatched as of
2026-05-10 (third 6-hour run).**

---

## Sources Added (Update 2026-05-10, Update 3)

- ameba-arduino-pro2 compare `13961cc...dev` (re-confirmed identical — no new commits since May 5, 2026): https://github.com/Ameba-AIoT/ameba-arduino-pro2/compare/13961cc...dev
- ameba-rtos-pro2 compare `1c1c8b7...main` (re-confirmed identical — no new commits since May 1, 2026): https://github.com/Ameba-AIoT/ameba-rtos-pro2/compare/1c1c8b7...main
- ameba-arduino-pro2 pulls (0 open; 319 closed; no FlashMemory/FCS PR exists): https://github.com/Ameba-AIoT/ameba-arduino-pro2/pulls
- ameba-arduino-pro2 issues (17 open; highest #398 Mar 2026; no new FCS issues): https://github.com/Ameba-AIoT/ameba-arduino-pro2/issues
- ameba-rtos-pro2 issues (3 open; highest #16 Jan 2026; no new issues): https://github.com/Ameba-AIoT/ameba-rtos-pro2/issues
- ideashatch/HUB-8735 issues (only issue #10 Aug 2025): https://github.com/ideashatch/HUB-8735/issues
- forum.amebaiot.com thread #3983 (original post date confirmed March 28, 2025; still 403-blocked): https://forum.amebaiot.com/t/error-after-write-in-memory-amb82/3983
- Ai-Thinker-Open GitHub org (13 repos; no BW21-CBV repository): https://github.com/Ai-Thinker-Open
- forum.amebaiot.com threads #4848–#4880 (all HTTP 403 / unindexed; no FCS/flash camera content): https://forum.amebaiot.com/t/4848 (representative URL)

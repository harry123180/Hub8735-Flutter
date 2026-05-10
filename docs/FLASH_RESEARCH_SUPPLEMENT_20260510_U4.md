# Flash/Camera Race Bug Research — Supplement: 2026-05-10 Update 4

> **This file** covers Findings 169–173 from the 2026-05-10 Update 4 (fourth 6-hour cycle) research run.
> Prior findings: `docs/FLASH_CAMERA_RACE_RESEARCH.md` (local) and prior supplements.
> Created because the main 319 KB research log cannot be pushed via the GitHub MCP API.
> New findings appended to local log in commit `26d9991`.

---

## Cycle Summary

**Nothing new of technical significance found.** All tracked repositories remain static.
Bug is unpatched. No public reports in any language or channel.

---

## Finding 169 — All Repositories Confirmed Static; No Fix Commits (May 10, 2026 — Update 4)

**Source:** GitHub commit pages — ameba-arduino-pro2/dev, ameba-rtos-pro2/main
**Priority:** LOW — Status confirmation

No changes on any tracked repository since Update 3:

| Repository | Last commit SHA | Last commit date | Message |
|---|---|---|---|
| ameba-arduino-pro2 (dev) | `13961cc` | May 5, 2026 | "Update API for AMB82-zero and SWD off logic" |
| ameba-rtos-pro2 (main) | `1c1c8b7` | May 1, 2026 | "Sync upstream — wowlan dhcp renew" |

FlashMemory.cpp (SHA `4fdfbec`) confirmed unpatched on direct raw fetch: zero calls to `device_mutex_lock`,
`device_mutex_unlock`, or `RT_DEV_LOCK_FLASH`. All `write()`, `writeWord()`, `eraseSector()`, `eraseWord()`
functions remain mutex-free.

---

## Finding 170 — No New Releases, PRs, or Issues

**Source:** GitHub releases, pulls, issues pages for ameba-arduino-pro2 and ameba-rtos-pro2
**Priority:** LOW — Status confirmation

| Item | State |
|---|---|
| ameba-arduino-pro2 latest pre-release | V4.1.1-QC-V05 (Apr 30, 2026) |
| ameba-arduino-pro2 latest stable | V4.1.0 (Mar 2, 2026) |
| ameba-arduino-pro2 open PRs | 0 (319 closed) |
| ameba-arduino-pro2 open issues | 17; highest #398 (Mar 29, 2026) |
| ameba-rtos-pro2 open issues | 3; highest #16 (Jan 2026) |

No issues or PRs related to FlashMemory, FCS, mutex, or cold boot failure.

---

## Finding 171 — Forum Threads #4881–#4900 All HTTP 403; No New Indexed Content

**Source:** forum.amebaiot.com threads #4881–#4900 (direct fetch)
**Priority:** LOW — Access wall unchanged

All threads in range #4881–#4900 returned HTTP 403. Google-indexed threads top out around #4834.
No publicly accessible new thread discusses the FCS/flash race condition.

---

## Finding 172 — All Bug-Signature Web Searches: Zero Results (Update 4)

**Priority:** LOW — Null result reconfirmed

| Query | Result |
|---|---|
| `AmebaPro2 FlashMemory "device_mutex_lock" RT_DEV_LOCK_FLASH` | **0 results** |
| `RTL8735B "FCS KM_status" 0x00002081` | **0 results** |
| `AmebaPro2 camera boot fail flash concurrent 2026` | **0 results** |
| `RTL8735B FlashMemory camera "cold boot" fix 2026` | **0 results** |
| `RTL8735B 闪存 相机 竞争 AmebaPro2 修复` | **0 results** |

Forum thread #4834 ("Boot failure after OTA update") surfaced in searches; confirmed HTTP 403 and
likely describes OTA brick (boot ROM cannot detect NOR flash), not the FCS mutex race condition.

---

## Finding 173 — Complete Status Sweep: Bug Unpatched as of 2026-05-10 (Update 4)

**Priority:** LOW — Status confirmation

| Repository / Source | Last activity | Status |
|---|---|---|
| ameba-arduino-pro2 (dev branch) | May 5, 2026 — SHA `13961cc` | **No new commits** |
| ameba-arduino-pro2 (releases) | V4.1.1-QC-V05 (Apr 30, 2026) | **No new release** |
| ameba-rtos-pro2 (main branch) | May 1, 2026 — SHA `1c1c8b7` | **No new commits** |
| ameba-arduino-pro2 PRs | 0 open; 319 closed | **No fix under review** |
| ameba-arduino-pro2 issues | 17 open; highest #398 | **Zero new FCS issues** |
| ameba-rtos-pro2 issues | 3 open; highest #16 | **Zero new relevant issues** |
| forum.amebaiot.com | Threads #4881–#4900 all HTTP 403 | **No new accessible content** |
| FlashMemory.cpp (dev, SHA `4fdfbec`) | Sept 30, 2025 (>9 months) | **Still NO mutex fix** |
| video_api.c (main) | March 3, 2026 | **Unguarded ftl_common_write/read** |
| All bug-signature strings | — | **Zero results in English or Chinese** |

**No HIGH priority confirmed fix found. Bug status: publicly undocumented and unpatched as of
2026-05-10 (Update 4).**

---

## Sources Added (Update 2026-05-10, Update 4)

- ameba-arduino-pro2 commits/dev (HEAD re-confirmed `13961cc`, May 5, 2026): https://github.com/Ameba-AIoT/ameba-arduino-pro2/commits/dev
- ameba-rtos-pro2 commits/main (HEAD re-confirmed `1c1c8b7`, May 1, 2026): https://github.com/Ameba-AIoT/ameba-rtos-pro2/commits/main
- FlashMemory.cpp raw dev (re-confirmed zero mutex calls, SHA `4fdfbec`): https://raw.githubusercontent.com/Ameba-AIoT/ameba-arduino-pro2/dev/Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.cpp
- ameba-arduino-pro2 releases (no new release; V4.1.1-QC-V05 remains latest): https://github.com/Ameba-AIoT/ameba-arduino-pro2/releases
- ameba-arduino-pro2 issues (17 open; highest #398; no FCS issues): https://github.com/Ameba-AIoT/ameba-arduino-pro2/issues
- ameba-arduino-pro2 pulls (0 open; 319 closed): https://github.com/Ameba-AIoT/ameba-arduino-pro2/pulls
- ameba-rtos-pro2 issues (3 open; highest #16): https://github.com/Ameba-AIoT/ameba-rtos-pro2/issues
- forum.amebaiot.com threads #4881–#4900 (all HTTP 403): https://forum.amebaiot.com/t/4881 (representative URL)

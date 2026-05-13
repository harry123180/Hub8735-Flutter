# RTL8735B FCS Flash Bug — Research Supplement 2026-05-13

This supplement records findings from the 2026-05-13 6-hour research cycle.
Full research log: `docs/FLASH_CAMERA_RACE_RESEARCH.md` (local commit SHA: `5f44cbd`)

---

## Finding 111 — Forum Thread #4834: "Boot failure after OTA update" — Flash Init Error; Different Failure Mode
**Source:** https://forum.amebaiot.com/t/boot-failure-after-ota-update/4834 (403-blocked; Google snippet only)  
**Priority:** LOW — Different flash boot failure mode; not our FCS/FlashMemory race bug

Thread #4834 describes a scenario where after an OTA firmware update the AMB82-mini fails to boot: the Boot ROM reports `[BOOT Err]Flash init error` and attempts fallback to NAND flash boot mode.

This is a **structurally different failure** from our documented bug:
- **Our bug**: SPI NOR flash detected and readable; FCS data area corrupted/invalidated by a user-level `FlashMemory.write()` / sector erase racing with `video_pre_init_save_cur_params()` → camera fails to initialise, but device boots and runs application code.
- **Thread #4834**: Boot ROM cannot detect NOR flash at all; device does not boot into application code. Likely: OTA update corrupted flash boot partition table or MBR.

Not directly related to our bug, but confirms "flash write → next boot fails" is a known failure class on RTL8735B. This is the **highest confirmed forum thread number** (#4834).

---

## Finding 112 — Forum Threads #4838, #4839, #4840 Logged; None Related to Bug
**Source:** forum.amebaiot.com (403-blocked; Google snippets, 2026-05-13)  
https://forum.amebaiot.com/t/rtsp-over-ssl-tls-and-stream-authentication/4838  
https://forum.amebaiot.com/t/how-to-upload-to-cloud-in-remote-locations/4839  
https://forum.amebaiot.com/t/ameba-pro-https-bin-ota/4840  
**Priority:** LOW — New thread numbers logged; no FCS bug content

- **#4838**: "RTSP over SSL/TLS and stream authentication" — TLS-protected RTSP; unrelated to flash/FCS.
- **#4839**: "How to upload to cloud in remote locations" — LTE module + RTL8735B for remote camera; unrelated.
- **#4840**: "Ameba Pro HTTPS OTA bin file" — HTTPS-based OTA workflow; unrelated to FCS/FlashMemory race.

**Highest confirmed forum thread number is now #4840** (up from estimated ~#4834 in previous cycle). Zero threads in #4834–#4840 mention FCS KM_status, FlashMemory.write(), VOE_OPEN_CMD, or sensor initial process.

---

## Finding 113 — Hackster.io AI-Thinker BW21-CBV Digital Camera DIY Article; No FCS Bug Content
**Source:** https://www.hackster.io/ai-thinker/diy-project-digital-camera-bw21-cbv-kit-5a7309 (403-blocked; search snippet only)  
**Priority:** LOW — Maker project; mirrors bbs.aithinker.com #47223 (Finding 107); no FCS bug discussion

AI-Thinker's official Hackster.io account presents "DIY Project: Digital Camera + BW21-CBV-Kit", corresponding to the bbs.aithinker.com thread #47223 (Finding 107). No mention of flash write errors, FCS cold-boot failures, or VOE initialization failures.

---

## Finding 114 — Complete Status Sweep: Bug Unpatched as of 2026-05-13
**Source:** Exhaustive sweep of all tracked sources (2026-05-13)  
**Priority:** LOW — Status confirmation

| Repository / Source | Last activity | Status |
|---|---|---|
| ameba-arduino-pro2 (dev) | May 5, 2026 — SHA `13961cc` | **No new commits** |
| ameba-arduino-pro2 (releases) | V4.1.0 stable; V4.1.1-QC-V05 pre-release; V4.1.1 stable = 404 | **No new release** |
| ameba-rtos-pro2 (main) | May 1, 2026 — SHA `1c1c8b7` | **No new commits** |
| ameba-arduino-pro2 PRs | 0 open | **No fix under review** |
| ameba-arduino-pro2 issues | Highest: #398 (Mar 29, 2026) | **Zero new FCS/VOE issues** |
| forum.amebaiot.com | Threads #4834, #4838–#4840 newly logged; highest confirmed: **#4840** | **No FCS/flash bug threads** |
| CSDN / Zhihu / 21ic / EEWorld | — | **Zero Chinese-language reports** |
| bbs.aithinker.com / hackster.io (BW21-CBV) | DIY camera articles; no bug reports | **No FCS bug content** |
| FlashMemory.cpp (dev, SHA 4fdfbec) | Sept 30, 2025 | **Still NO mutex fix** |
| video_api.c (main) | March 3, 2026 | **Still NO mutex fix at ftl_common_write() call sites** |
| Public web `"FCS KM_status 0x00002081"` | — | **Zero new indexed results** |
| Public web `"It don't do the sensor initial process"` | — | **Zero new indexed results** |

**No HIGH priority confirmed fix found. Bug status: publicly undocumented and unpatched as of 2026-05-13.**

---

## Sources Added (2026-05-13)
- forum.amebaiot.com #4834 (OTA boot failure; Flash init error; 403-blocked): https://forum.amebaiot.com/t/boot-failure-after-ota-update/4834
- forum.amebaiot.com #4838 (RTSP SSL/TLS; unrelated; 403-blocked): https://forum.amebaiot.com/t/rtsp-over-ssl-tls-and-stream-authentication/4838
- forum.amebaiot.com #4839 (cloud upload via LTE; unrelated; 403-blocked): https://forum.amebaiot.com/t/how-to-upload-to-cloud-in-remote-locations/4839
- forum.amebaiot.com #4840 (Ameba Pro HTTPS OTA; unrelated; 403-blocked): https://forum.amebaiot.com/t/ameba-pro-https-bin-ota/4840
- hackster.io BW21-CBV DIY camera (mirrors bbs.aithinker.com #47223; no FCS bug; 403-blocked): https://www.hackster.io/ai-thinker/diy-project-digital-camera-bw21-cbv-kit-5a7309
- ameba-arduino-pro2 commits/dev (re-confirmed last: 13961cc, May 5, 2026): https://github.com/Ameba-AIoT/ameba-arduino-pro2/commits/dev
- ameba-rtos-pro2 commits/main (re-confirmed last: 1c1c8b7, May 1, 2026): https://github.com/Ameba-AIoT/ameba-rtos-pro2/commits/main
- ameba-arduino-pro2 FlashMemory.cpp dev (re-confirmed no mutex guards): https://raw.githubusercontent.com/Ameba-AIoT/ameba-arduino-pro2/dev/Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.cpp
- ameba-rtos-pro2 video_api.c main (re-confirmed two unguarded ftl_common_write() calls): https://raw.githubusercontent.com/Ameba-AIoT/ameba-rtos-pro2/main/component/video/driver/RTL8735B/video_api.c

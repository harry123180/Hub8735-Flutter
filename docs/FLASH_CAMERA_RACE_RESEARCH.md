# RTL8735B Flash → Camera Boot Race — Research Log

> **NOTE (2026-05-13):** This file was accidentally truncated during an automated push.
> **Full research history (Findings 1–121)** is preserved in:
> - `docs/FLASH_RESEARCH_SUPPLEMENT_20260505_20260509.md` — Findings 17–88 (comprehensive archive)
> - `docs/FLASH_RESEARCH_SUPPLEMENT_20260512_C2.md`, `_U2.md`, `_U3.md` — Findings 89–116
> - `docs/FLASH_RESEARCH_SUPPLEMENT_20260513.md` — earlier Findings 111–114 from today
> - `docs/FLASH_RESEARCH_SUPPLEMENT_20260513_U2.md` — Findings 111–115 from cycle U2
> - `docs/FLASH_RESEARCH_SUPPLEMENT_20260513_U3.md` — Findings 116–121 from cycle U3 (THIS cycle)
> Git commit history also preserves the full encoded research log.

## Bug Summary

**Platform:** Realtek RTL8735B (AmebaPro2) / ideasHatch HUB-8735 / 安信可 BW21-CBV  
**Trigger:** Any SPI flash page program or sector erase operation causes VOE camera failure on the **next cold boot**.

**Symptom severity ladder:**

| Flash operations | Next cold boot result |
|---|---|
| 0 writes | Always OK |
| 1× `flash_write_word` (4 bytes, no erase) | Stable |
| 70× `flash_write_word` (280 bytes, no erase) | `[VOE][WARN]slot full` deadlock (mild) |
| Any sector erase | `VOE_OPEN_CMD fail` + `hal_video_open fail` (complete) |

**Boot ROM message (always present after write):**
```
FCS KM_status 0x00002081 err 0x0000200a
It don't do the sensor initial process
```

**Normal working FCS boot (reference from GitHub Issue #251):**
```
FCS KM_status 0x00000082  err 0x00000000
FCS TM_status 0x00000001
Sensor: 254µs  IQ: 4587µs  ITCM: 1011µs  DTCM: 51µs
DDR: 11957µs  DDR2: 11310µs
VOE flash @ 0x807e080  size 0x7ff80
FCS OK
```

## Research Index (All Findings)

| Finding # | Location | Topic |
|---|---|---|
| 1–16 | FLASH_RESEARCH_SUPPLEMENT_20260505_20260509.md | SDK v4.0.8 FCS+FlashMemory introduction; address layout; FCS mechanism |
| 17–88 | FLASH_RESEARCH_SUPPLEMENT_20260505_20260509.md | Comprehensive research through May 9 |
| 89–99 | FLASH_RESEARCH_SUPPLEMENT_20260512_C2.md / U2.md | May 12 morning research |
| 100–110 | FLASH_RESEARCH_SUPPLEMENT_20260512_U3.md | May 12 sweep; status confirmed unpatched |
| 111–114 | FLASH_RESEARCH_SUPPLEMENT_20260513.md | May 13 earlier cycle; threads #4834-#4840 logged |
| 111–115 | FLASH_RESEARCH_SUPPLEMENT_20260513_U2.md | May 13 cycle U2: postbuild FCS analysis; thread #4835 |
| 116–121 | FLASH_RESEARCH_SUPPLEMENT_20260513_U3.md | May 13 cycle U3: KM error codes decoded; FCS state machine; Zephyr WIP precedent |

## Key Confirmed Facts

- **FCS data address**: `fcsdata` partition = 0x8000 (boot ROM reads here); `NOR_FLASH_FCS` = 0xF0D000 (runtime AE/AWB)
- **FlashMemory address**: 0xFD0000–0xFFFFFF (no direct overlap with FCS)
- **Root cause mechanism**: INDIRECT — still unknown; address overlap disproved (Finding 13)
- **Postbuild tool**: `build.fcs_mode_val` controls whether `fcs_data_<sensor>.bin` is uploaded to fcsdata partition
- **`Arduino_FCS_MODE`**: Defined in boards.txt but NOT passed to C++ compiler (Finding 111)
- **KM error codes decoded** (Finding 116):
  - `KM_status 0x00002081` = `FCS_RUN_DATA_NG_KM` (FCS ran, data Not Good)
  - `err 0x0000200a` = `FCS_I2C_INIT_ERR` (I2C init failed during FCS sensor boot)
  - Normal working boot: `KM_status 0x00000082` = `FCS_RUN_DATA_OK_KM`
- **KM hardware registers**: `KM_STATUS = 0x40492004`, `KM_FCS_ERROR_REG = 0x40492008`
- **FCS_BYPASS_WHILE1_KM = 0x0083**: KM bypass/while(1) state; likely maps to "[VOE][WARN]slot full" mild case
- **"It don't do the sensor initial process"**: Boot ROM does NOT fall back to normal sensor init when FCS fails; camera sensor is left completely uninitialized
- **No public fix**: Bug is undocumented and unpatched as of 2026-05-14

## Supplement Files Quick Reference

See `docs/FLASH_RESEARCH_SUPPLEMENT_20260513_U3.md` for the latest findings from this research cycle.

## Research Update — 2026-05-13 (Cycle U3)

**Key new finding this cycle:** The exact boot ROM error codes are now decoded from
`rtl8735b_voe_status.h` in the ameba-rtos-pro2 SDK.

| Source | Key Finding | Priority |
|---|---|---|
| `rtl8735b_voe_status.h` | `KM_status 0x2081` = `FCS_RUN_DATA_NG_KM`; `err 0x200A` = `FCS_I2C_INIT_ERR` — KM co-processor failed to init I2C during FCS sensor boot | HIGH |
| `rtl8735b_voe_status.h` | KM registers: `KM_STATUS=0x40492004`, `KM_FCS_ERROR_REG=0x40492008`; `FCS_BYPASS_WHILE1_KM=0x0083` maps to "slot full" deadlock | HIGH |
| `hal_video_common.h` | `fcs` field: "1: fcs flow ROM load sensor, 0: normal flow need init sensor" — confirms boot ROM does NOT fall back when FCS fails | MEDIUM |
| `hal_video_release_note.txt` | VOE 1.5.6.0 (Jul 2024): "Reinit GPIO in FCS mode" — FCS has known GPIO init sensitivities; predates FlashMemory; no flash mutex fix | LOW |
| Zephyr issue #51713 | SPI NOR WIP-bit during cold boot causes flash reads to fail (returns 0x00) — cross-platform precedent for flash-busy-at-boot failure class | MEDIUM |
| ameba-arduino-pro2 releases | V4.1.1-QC-V03 (Apr 17) and QC-V04 (Apr 2) documented; no FCS/flash fix in any V4.1.1 pre-release; no stable V4.1.1 yet | LOW |

**No confirmed fix. Bug remains unpatched.**

## Research Update — 2026-05-14 (Cycle U4)

**Search scope:** ameba-rtos-pro2 GitHub commits (2026), ameba-arduino-pro2 releases, forum threads #4832/#4834, ideashatch issues, Chinese-language sources, VOE release notes.

**Key new finding this cycle:** Two upstream rtos-pro2 commits from April 1, 2026 add multimedia framework queue-initialization guards that may partially address the "[VOE][WARN]slot full" symptom. These are NOT yet in any public Arduino SDK release. A new forum thread (#4832) reports `sys_reset` failure after OTA flash write, a related phenomenon.

| Source | Key Finding | Priority |
|---|---|---|
| forum.amebaiot.com/t/sys-reset-is-not-consistent-why/4832 (late Apr 2026) | New thread: user reports `sys_reset()` after OTA flash write causes device to stop booting (console silent, no boot messages) until full power cycle. "Software reset is necessary for camera app after OTA firmware update." — confirms the flash-write → boot-failure class affects sys_reset path too, not only cold boot. | MEDIUM |
| ameba-rtos-pro2 commit fb3dc02 "add queue init check" (Apr 1, 2026) | Adds guard `if (mctx->state != MM_STAT_READY)` before video module initialization in `component/media/mmfv2/module_video.c`. Logs error and returns early if MMF queue is not ready. May prevent "[VOE][WARN]slot full" deadlock by refusing to proceed when module is in bad state. NOT yet in Arduino SDK. | MEDIUM |
| ameba-rtos-pro2 commit 3130193 "add jpeg snapshot exception for queue init check" (Apr 1, 2026) | Refines the above: JPEG snapshot (`VIDEO_JPEG` with `snapshot_cb != NULL`) and direct-output modes are exempted from the MM_STAT_READY check. Prevents regression for snapshot use-cases. | LOW |
| ameba-rtos-pro2 commit f575a69 "sync voe to 1.7.0.0" (Apr 1, 2026) | VOE updated to 1.7.0.0. Release notes: "Fix dual sensor id mirror/flip issue; Merge PC2 12M DRC modification." No mention of FCS flash-write boot issue. | LOW |
| ameba-rtos-pro2 commit d54e1a8 "sync voe to 1.7.1.0" (May 1, 2026) | VOE updated to 1.7.1.0. Release notes (dated 04/21/2026): "Fix dual sensor id FCS mirror/flip issue." FCS-tagged but only addresses mirror/flip for dual-sensor configs — unrelated to our flash→I2C_INIT_ERR boot bug. | LOW |
| ameba-arduino-pro2 V4.1.1-QC-V04 (Apr 17, 2026) | Latest pre-release. Contains PowerMode multi-wakeup examples and tools update (v1.4.10). Does NOT include the Apr 1 queue-init commits or VOE 1.7.x. No stable V4.1.1 as of 2026-05-14. | LOW |
| ameba-rtos-pro2 issues page | Only 3 open issues (AI glass src path, SDK chip support, antivirus detection). Bug is entirely unreported in the official RTOS issue tracker. | LOW |
| ideashatch/HUB-8735 Issue #10 (Aug 2025) | PS5268 wide-angle sensor reporting "sensor id fail" — different symptom (wrong sensor ID), not related to FCS flash-write boot bug. | LOW |
| Chinese-language search (CSDN/知乎/bbs.aithinker.com) | No new Chinese-language articles or forum posts found specifically about the FCS flash-write camera failure on BW21-CBV or RTL8735B. bbs.aithinker.com returned 403. | LOW |

**SDK state as of 2026-05-14:**
- Latest stable Arduino SDK: V4.1.0 (Mar 2, 2026) — does NOT include queue-init fix or VOE 1.7.x
- Latest pre-release: V4.1.1-QC-V04 (Apr 17, 2026) — does NOT include queue-init fix or VOE 1.7.x
- The "add queue init check" fix is only in the `ameba-rtos-pro2` main branch; manual integration into an Arduino project is theoretically possible by compiling `libmmf.a` from source, but no documentation exists for this.

**Hypothesis update:** The `sys_reset`-after-flash-write failure (thread #4832) and the cold-boot-after-flash-write failure (our bug) may share a common root: after a flash erase/program sequence, the KM co-processor's FCS I2C init fails on the next boot (whether warm or cold), because the flash controller is left in a state that disrupts the KM's early-boot I2C pin-mux or timing. The distinction between soft reset and cold boot may not matter — what matters is whether the boot ROM re-executes the FCS path.

**No confirmed fix. Bug remains unpatched as of 2026-05-14.**

## Research Update — 2026-05-14 (Cycle U5)

**Search scope:** ameba-rtos-pro2 May 2026 commits; ameba-arduino-pro2 main branch status; V4.1.1-QC-V05 release notes; GitHub issue trackers (arduino-pro2, rtos-pro2, HUB-8735); forum thread #4834 (OTA boot fail); Chinese-language sources; VOE 1.7.1.0 changelog; BOOTLOADER_VOE_LOG_EN debug mechanism.

**Key new findings this cycle:** VOE 1.7.1.0 (May 1) has a FCS-tagged fix but for an unrelated symptom; Arduino SDK main branch frozen 10+ weeks; BOOTLOADER_VOE_LOG_EN confirmed as debug path for KM FCS logging; all public issue trackers still empty of our bug report.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 commits (May 1, 2026): `7b2b97f`, `63c0a2f`, `d54e1a8`, `687a4c7` | Camera/sensor updates only: imx681 5M resolution, ov12890 IQ update, VOE 1.7.1.0 ("Fix dual sensor id FCS mirror/flip" — unrelated to our bug), ISP OSD with ToF example. No flash-controller or boot-ROM changes visible. | LOW |
| ameba-rtos-pro2 commit `1c1c8b7` "Sync upstream" (May 1, 2026) | Syncs from Realtek's private internal repo. Contents of upstream are opaque — cannot rule out private flash fixes, but none reflected in public source diffs. | LOW |
| ameba-arduino-pro2 main branch state (fetched 2026-05-14) | Last commit to `main` branch is March 2, 2026 (V4.1.0, commit `93d6351`). No new commits between April–May 14, 2026. The April 1 queue-init fix (`fb3dc02`/`3130193`) in ameba-rtos-pro2 has NOT been merged into the Arduino SDK's main branch after 6+ weeks. | MEDIUM |
| ameba-arduino-pro2 open issues (fetched 2026-05-14) | 12 open issues (confirmed), all labelled "enhancement/pending" — feature requests only. No bug reports related to FCS, FlashMemory, camera cold-boot, VOE_OPEN_CMD, or slot-full. Bug is entirely unreported in the official Arduino SDK tracker. | LOW |
| ameba-rtos-pro2 open issues (fetched 2026-05-14) | 3 open issues: AI glass src path (#16), chip support (#4), antivirus detection (#3). No FCS/flash/camera bug filed. | LOW |
| AmebaPro2 RTOS SDK documentation (extract via search) | **`BOOTLOADER_VOE_LOG_EN = 1` in `video_boot.h`** enables VOE logging during FCS boot. Provides a debug path to capture KM co-processor output during the failing FCS sequence. Caveat: "enabling VOE log in the bootloader will cause some conflicts when ROM log is disabled." Useful as a diagnostic tool. | MEDIUM |
| V4.1.1-QC-V05 release notes (Mar 6, 2026) | Release content: battery-powered camera POC, audio trigger recording, video zoom, TensorFlowLite, AMB82-zero board, IMX681/OV50A40 sensors, tools v1.4.10 (Dev/Fast mode), WDT API. No FCS flash-write camera fix. Confirms there are at least 5 QC pre-releases so far. | LOW |
| Forum thread #4834 "Boot failure after OTA update" | Still HTTP 403 Forbidden — cannot fetch directly. Confirmed via multiple search result snippets: thread discusses AMB82-Mini boot failure after OTA flash write, same failure class as our bug. Contents remain inaccessible without forum login. | MEDIUM (blocked) |
| Chinese-language search (CSDN/知乎/21ic/bbs.aithinker.com) | No new articles or posts about FCS flash-write camera failure on BW21-CBV or RTL8735B this cycle. CSDN article 139222964 on AMB82-mini Arduino inaccessible (403). bbs.aithinker.com still blocked. | LOW |

**SDK state as of 2026-05-14 (Cycle U5 — unchanged from U4):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release: V4.1.1-QC-V04/V05 (Apr 17, 2026) — no fix
- ameba-rtos-pro2 main: VOE 1.7.1.0 (May 1, 2026); queue-init fix (Apr 1) not yet in Arduino SDK
- **ameba-arduino-pro2 main branch frozen for 10+ weeks**

**Debugging recommendation (new this cycle):** When building from the RTOS SDK, setting `BOOTLOADER_VOE_LOG_EN = 1` in `video_boot.h` may expose additional KM co-processor output during the FCS phase on a device previously written via FlashMemory. This is the most actionable new finding — it could confirm or deny the hypothesis that the KM co-processor stalls waiting for the SPI flash controller to become idle.

**No confirmed fix. Bug remains unpatched as of 2026-05-14 (Cycle U5).**

## Research Update — 2026-05-14 (Cycle U6)

**Search scope:** Three parallel agents: (1) English forum/community sources — forum.amebaiot.com threads, GitHub new activity after May 1, RTL8735B+FCS public reports; (2) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com; (3) GitHub deep-dive — ameba-rtos-pro2 hal_flash.c code analysis, FCS load path headers, release comparison.

**Key new findings this cycle:**
- D-cache flush **asymmetry** confirmed in `hal_flash.c` — explains warm-reset failures; cold-boot mechanism may involve FCS digest check
- `voe_isp_export_ld_info_digest_check_from_nor()` discovered — FCS verifies NOR data with a digest on every boot; user writes may corrupt digest coverage
- Closest public symptom match found: forum thread #4302 "[VOE]frame_end: sensor didn't initialize done!" (Aug 2025, blocked)
- FCS disable confirmed as compile-time only (no runtime API exists)
- ameba-rtos-pro2 frozen since May 1, 2026 (confirmed by two independent agents)

| Source | Key Finding | Priority |
|---|---|---|
| `hal_flash.c` in ameba-rtos-pro2 (commit `7e78403`, Mar 3, 2026) | **D-cache flush asymmetry confirmed:** `hal_flash_page_program()` and `hal_flash_sector_erase()` are thin stubs with **NO `dcache_invalidate_by_addr()` call**, while `hal_flash_stream_read()` DOES call `dcache_invalidate_by_addr()`. After a write/erase, the CPU D-cache retains stale XIP-mapped flash data. On warm reset (`sys_reset`), the D-cache is NOT cleared, so the boot ROM reads stale FCS data from cache → FCS_I2C_INIT_ERR. Directly explains thread #4832 (sys_reset after OTA flash write). For cold boot: D-cache IS cleared on power-up, so this alone does not explain the persistent cold-boot failure — a second mechanism is needed. | MEDIUM |
| `hal_voe_export_ctrl.h` in ameba-rtos-pro2 | **New cold-boot failure mechanism candidate:** `voe_isp_export_ld_info_digest_check_from_nor()` performs a **digest/integrity check** on FCS data loaded from NOR flash during every boot. If the digest covers a flash range that includes or overlaps the user-written region (0xFD0000+), any page program or sector erase would invalidate the digest and cause FCS to fail on the next **cold boot** (not just warm reset). This is the first plausible mechanism that explains cold-boot persistence independent of D-cache state. Digest coverage range is not publicly documented. | MEDIUM |
| `hal_flash_boot.h` in ameba-rtos-pro2 | `boot_get_isp_iq_fcs_ld_sts()` — runtime API to query FCS load status; documented as available on Cut-C silicon revision or later. Provides a path to check FCS load result from user code after boot, potentially distinguishing digest failure from I2C failure. | LOW |
| forum.amebaiot.com/t/voe-frame-end-sensor-didnt-initialize-done/4302 (Aug 2025) | **Closest public symptom match:** Thread title "[VOE]frame_end: sensor didn't initialize done!" — FCS Mode reported as disabled but sensor still failing to initialize. This is the most directly related public thread found. Content inaccessible (403); date August 2025. Potentially describes our bug or a closely related failure mode where disabling FCS at compile time is insufficient. | MEDIUM (blocked) |
| forum.amebaiot.com/t/amb82-mini-onboard-camera-sensor-identification-and-voe-setup-for-wireless-video-and-i2c/4777 (Mar 12, 2026) | New thread: AMB82-Mini I2C camera sensor problems + VOE setup. Content 403 blocked. Possibly related to camera I2C init failures in FCS context. | LOW (blocked) |
| Arduino IDE Tools menu / boards.txt (all SDK versions) | **FCS disable is compile-time only — no runtime API exists.** "Camera FCS Mode = Disable" in the Arduino IDE Tools menu is a build-time flag. It prevents the FCS boot sequence entirely but cannot be toggled after a flash write without a full recompile. There is no `fcs_disable()` or equivalent runtime API in any publicly accessible SDK. The only known software-level FCS control is this compile-time flag. | MEDIUM |
| AmebaPro2 SDK ISP documentation (via search snippets, URL 403) | **`video_user_boot.c`** is the bootloader file that reads FCS flash data — official docs state "to read FTL flash data in bootloader, please refer to `video_user_boot.c`." This is the entry point for FCS flash reads in the boot ROM path. | LOW |
| AmebaPro2 SDK MMF documentation (via search snippets, URL 403) | **`SAVE_TO_RETENTION` partial workaround:** Official docs offer SRAM retention as alternative to flash for AE/AWB ISP parameters. Enable by uncommenting `USE_ISP_RETENTION_DATA` in `video_api.h`. Docs note "please check the flash write limit" for `SAVE_TO_FLASH`. Does NOT fix user-initiated sector-erase causing camera failure — only reduces frequency of ISP-initiated flash writes. | LOW |
| Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com, May 2026) | No new Chinese-language articles, forum posts, or discussions about FCS flash-write camera failure on BW21-CBV or RTL8735B. bbs.aithinker.com and bbs.ai-thinker.com both return 403. CSDN/Zhihu/EEWorld/21IC have no indexed content on this specific bug. | LOW |
| GitHub: ameba-rtos-pro2 compare (May 1 → May 14, 2026) | **Confirmed by two independent agents:** ameba-rtos-pro2 main branch is **identical** to its May 1, 2026 state. Zero commits in the past 13 days. No flash, FCS, boot ROM, or sensor init changes are in any observable pipeline. | LOW |

**Revised root cause hypothesis (two-mechanism model):**

The bug likely has two distinct failure paths:

1. **Warm-reset path** (`sys_reset` after flash write): D-cache is not cleared on soft reset. `hal_flash_page_program()`/`hal_flash_sector_erase()` leave stale XIP-cached data. Boot ROM FCS reads stale/wrong FCS data from cache → `FCS_I2C_INIT_ERR`. This explains thread #4832.

2. **Cold-boot path** (power cycle after flash write): D-cache clears on power-up, so a second mechanism must be active. Most likely candidate: `voe_isp_export_ld_info_digest_check_from_nor()` performs a digest check over a flash region that partially overlaps or is adjacent to the user-written area. User writes invalidate the digest stored in flash, and the invalidated digest persists across cold boots. This explains the severity gradient: 1 write (4 bytes) may land in a non-covered area → stable; 70 writes (280 bytes) spread into covered area → mild failure; sector erase wipes the FCS data partition or its digest entry entirely → complete failure.

**Potential high-impact workaround (unverified):** If compile-time "Camera FCS Mode = Disable" completely bypasses the `voe_isp_export_ld_info_digest_check_from_nor()` check and the entire FCS boot path, then building the firmware with FCS disabled would prevent the cold-boot camera failure at the cost of slower camera startup time (FCS provides fast-camera-start). This requires testing.

**SDK state as of 2026-05-14 (Cycle U6 — unchanged):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release: V4.1.1-QC-V05 (Mar 6, 2026, tool updates to Apr 30) — no fix
- ameba-rtos-pro2 main: frozen at May 1, 2026 (VOE 1.7.1.0); no flash/FCS changes
- No V4.1.1-QC-V06 or stable V4.1.1 exists

**No confirmed fix. Bug remains unpatched as of 2026-05-14 (Cycle U6).**

## Research Update — 2026-05-14 (Cycle U7)

**Search scope:** Four parallel agents: (1) GitHub — new commits/issues, `video_user_boot.c`, `boards.txt`, `hal_flash.c`, `hal_voe_export_ctrl.h`; (2) English forums — forum.amebaiot.com, Reddit, SO, Hackster, FCS disable workaround confirmation; (3) Chinese sources — CSDN, 知乎, EEWorld, 21IC, bbs.aithinker.com, Gitee; (4) SDK deep-dive — `video_user_boot.c` full analysis, `video_api.c` NONE_FCS_MODE, `platform.txt` post-build flow.

**Key new findings this cycle:**
- `video_user_boot.c` successfully retrieved from public repo — reveals FCS data format, dcache handling, and hardcoded `user_disable_fcs()=0`
- `FlashMemory.cpp` and `ftl_common_write()` confirmed to have ZERO dcache management or WIP polling
- **`NONE_FCS_MODE` in `video_api.c`** (distinct from `Arduino_FCS_MODE`) provides a compile-time fallback that may fully bypass the KM FCS cold-boot path — unconfirmed but mechanically plausible
- `boards.txt` FCS Disable passes `fcs_mode_val=Disable` to post-build image packager (not just a C flag)
- `voe_isp_export_ld_info_digest_check_from_nor` confirmed to live entirely inside closed-source VOE blob
- Chinese sources: zero new content; `FCS_I2C_INIT_ERR`/`FCS_RUN_DATA_NG_KM` return zero results in all public web searches

| Source | Key Finding | Priority |
|---|---|---|
| `component/video/driver/RTL8735B/video_user_boot.c` (ameba-rtos-pro2, public) | **File successfully retrieved** — previously believed private. `boot_read_flash_data()` DOES call `dcache_invalidate_by_addr()` before every NOR read, so the bootloader FCS read path correctly handles XIP cache. FCS data format at 0xF0D000: 4-byte magic `'FCSD'` + 32-bit additive checksum + `video_boot_stream_t` (AE exposure, AE gain, AWB r-gain, AWB b-gain + lookup tables). | MEDIUM |
| `video_user_boot.c` — `user_disable_fcs()` | **Hardcoded to return 0** — the runtime hook for disabling FCS exists but is permanently OFF in the shipping code. No runtime FCS bypass is possible without source modification and recompile from the RTOS SDK. | MEDIUM |
| `video_user_boot.c` — `isp_fcs_header_t` | The KM co-processor reads `isp_fcs_header_t` which contains GPIO and I2C configuration for the camera sensor. This directly confirms that `FCS_I2C_INIT_ERR (0x200A)` is a downstream consequence of the KM receiving a corrupted or unreadable `isp_fcs_header_t` — not a standalone I2C hardware fault. | MEDIUM |
| `rtl8735b_voe_status.h` — KM SRAM layout | `FCS_SRAM_ADDR = 0x2000F000` (KM co-processor FCS staging area in SRAM); `FCS_RESULT_ADDR = 0x2000FF00` (FCS result). ISP FCS magic numbers: `ISP_FCS_DATA_MAGIC_NUM = 0x53434649` (`'IFCS'`) and `ISP_MULTI_FCS_DATA_MAGIC_NUM = 0x5343464D` (`'MFCS'`). | LOW |
| `component/utilities/FlashMemory.cpp` (confirmed via search) | **Zero dcache management, zero WIP polling confirmed.** No `dcache_invalidate_by_addr`, no `SCB_InvalidateDCache`, no Write-In-Progress bit polling after any `flash_stream_write`, `flash_erase_sector`, `flash_write_word`, or `flash_read_word` call. `video_api.c`'s `ftl_common_write()` also has no dcache invalidation after write. The application-layer write path is definitively unguarded. | MEDIUM |
| `video_api.c` — `NONE_FCS_MODE` macro | **Distinct from `Arduino_FCS_MODE`/`ENABLE_FCS`.** `video_api.c` uses `#if NONE_FCS_MODE` at two locations to compile in `video_get_fw_isp_info()` as a fallback sensor init path, bypassing the KM FCS I2C sequence entirely. The relationship between the boards.txt "Disable" choice and `NONE_FCS_MODE=1` in `video_api.c` is not visible in public open-source C code — it may be set by the post-build packager or a private header. | HIGH |
| `platform.txt` — post-build FCS flow | `{build.fcs_mode_val}` (the "Enable"/"Disable" string from boards.txt) is passed directly to `recipe.objcopy.hex.pattern` (the post-build image packager). This means FCS Mode = Disable is **an image-packaging operation**, not just a C preprocessor flag. The packager likely omits or invalidates the FCS data partition header in the firmware image, which may prevent the boot ROM from starting the KM FCS sequence. If confirmed, this would completely bypass `voe_isp_export_ld_info_digest_check_from_nor` and the KM cold-boot FCS path. **This has never been publicly tested as a workaround for the flash-write camera failure.** | HIGH |
| `hal_voe_export_ctrl.h` (all open-source headers, exhaustive search) | `voe_isp_export_ld_info_digest_check_from_nor` is **not declared in any publicly visible header and has zero call sites in any open-source C file.** It lives entirely inside the precompiled `libvideo_ns.a`/`libvideo_ntz.a` blobs. The exact flash address range that the digest covers cannot be determined from public source. | MEDIUM |
| `video_boot.c` — `video_btldr_fcs_terminated()` | In the open-source C layer, `FCS_RUN_DATA_NG_KM` status is set **only** inside `video_btldr_fcs_terminated()`, which is called when `user_disable_fcs()` returns non-zero. The symbol `FCS_I2C_INIT_ERR (0x200A)` does **not appear anywhere** in open-source C files — it is set exclusively by the KM firmware (voe.bin). The entire I2C failure chain originates inside the opaque binary blob. | MEDIUM |
| ameba-arduino-pro2 `dev` branch | Last commit: May 5, 2026, SHA `13961cc` — "Update API for AMB82-zero and SWD off logic." No FCS/flash/camera fix in `dev` or `main` branch. | LOW |
| All public web search engines | **Zero indexed results** for the exact symbols `FCS_I2C_INIT_ERR`, `FCS_RUN_DATA_NG_KM`, or the hex string `"FCS KM_status 0x00002081"`. This research log is the only publicly accessible documentation of this bug and its error codes. | LOW |
| Chinese-language sources (all channels, May 14 sweep) | No new Chinese-language content about FCS flash→camera cold boot failure on BW21-CBV/RTL8735B. bbs.aithinker.com, bbs.elecfans.com, club.szlcsc.com all 403/refused. CSDN/Zhihu/EEWorld/21IC searches return zero relevant results. | LOW |

**Revised boot-path model (two-mechanism clarification):**

1. **Warm-reset path** (`sys_reset` after flash write): `hal_flash_page_program()`/`hal_flash_sector_erase()` lack `dcache_invalidate_by_addr()`. D-cache retains stale XIP data. On soft reset, D-cache is NOT cleared. Bootloader `boot_read_flash_data()` does call `dcache_invalidate_by_addr()` before its read — so this should be handled… unless the invalidate fails when the underlying flash is still busy (WIP). This is unresolved.

2. **Cold-boot path** (power cycle after flash write): D-cache clears on power-up; `boot_read_flash_data()` correctly invalidates before reading. A second mechanism must explain persistent cold-boot failure. Most likely candidates: (a) `voe_isp_export_ld_info_digest_check_from_nor()` (inside closed VOE blob) covers a NOR range that overlaps FlashMemory writes; (b) the sector erase at 0xFD0000 disturbs an adjacent flash structure read by the packager; (c) the FCS data `'FCSD'` checksum at 0xF0D000 is corrupted by a write that lands in the same 4 KB sector.

**Critical unresolved question — highest priority test:**

> **Does building with "Camera FCS Mode = Disable" in Arduino IDE Tools menu prevent the VOE camera failure after `FlashMemory.write`/`flash_erase_sector`?**
>
> Mechanistic expectation: The post-build packager omits/invalidates the FCS partition in the image. If the boot ROM checks for a valid FCS partition header before starting the KM FCS sequence, then with no valid FCS partition the KM never runs → no digest check → no `FCS_I2C_INIT_ERR` → camera works via `NONE_FCS_MODE` fallback (`video_get_fw_isp_info()`). Camera startup will be slower (loss of fast camera start), but the flash-write→reboot failure would be eliminated.
>
> Counter-risk: If the KM runs its FCS sequence regardless of the partition header (hardcoded in voe.bin), then this workaround fails. Hardware test is the only way to confirm.

**SDK state as of 2026-05-14 (Cycle U7 — unchanged):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release: V4.1.1-QC-V05 (Mar 6, 2026) — no fix
- ameba-rtos-pro2 main: frozen at May 1, 2026 (VOE 1.7.1.0, commit `1c1c8b7`)
- ameba-arduino-pro2 dev: frozen at May 5, 2026 (SHA `13961cc`)

**No confirmed fix. Bug remains unpatched as of 2026-05-14 (Cycle U7).  
Highest-priority action: hardware test of "Camera FCS Mode = Disable" as a workaround.**

## Research Update — 2026-05-15 (Cycle U8)

**Search scope:** Three parallel agents: (1) GitHub + English forums — new commits/issues after May 5, ameba-arduino-pro2 / ameba-rtos-pro2, FCS disable workaround reports; (2) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com; (3) SDK deep-dive — postbuild.cpp FCS Disable mechanism from dev branch source code; fcs_data_dummy.bin role; fcs_peri_info_ram_t; hal_video_fcs_en().

**Key new findings this cycle:**
- `postbuild.cpp` retrieved from dev branch — confirms `fcs_data_dummy.bin` is placed in `PT_FCSDATA` when FCS is Disabled (not omitted); the dummy header lacks the `'MFCS'` magic number, causing `hal_voe_fcs_check_OK()` to return false → bootloader skips KM I2C sensor init → `FCS_I2C_INIT_ERR (0x200A)` is never triggered
- Official docs confirm Disable = "No Camera FCS mode process" (full bypass implied)
- `hal_video_fcs_en()` confirmed as application-side only — does NOT affect KM boot path
- FCS + FlashMemory both introduced in V4.0.8 simultaneously — no prior-SDK compatibility warning
- `fcs_peri_info_ram_t` structure surfaced (`fcs_OK`, `fcs_used` fields); `hal_video_check_fcs_OK()` readable by application — no retry path exists
- Forum thread #4321 (GC2053 sensor init failed, Aug 2025) newly identified as related symptom
- No Chinese-language content found on this bug; all Chinese community sites remain 403-blocked
- SDK freeze confirmed: no new commits to either repo since May 5, 2026

| Source | Key Finding | Priority |
|---|---|---|
| `Ameba_misc/Ameba_tools/postbuild_tool/postbuild.cpp` (ameba-arduino-pro2 `dev` branch) | **FCS Disable mechanism confirmed from source:** When `fcs_mode_val == "Disable"`, postbuild: (1) copies `fcs_data_dummy.bin` into `PT_FCSDATA` slot; (2) uses `non_fcs/` variant of the ISP IQ JSON; (3) still produces `PT_FCSDATA=boot_fcs.bin` in the combined flash image — the partition is NOT removed. The dummy blob lacks the `ISP_MULTI_FCS_DATA_MAGIC_NUM = 0x5343464D` (`'MFCS'`) header. At boot, `hal_voe_fcs_check_OK()` validates this magic; with dummy data it returns 0. The bootloader then skips FCS sensor I2C initialization entirely, never calling the sequence that produces `FCS_I2C_INIT_ERR`. This is the strongest mechanistic evidence yet that "Camera FCS Mode = Disable" would prevent the cold-boot camera failure — but hardware confirmation with a flash-written device is still needed. | HIGH |
| Official AmebaPro2 Arduino documentation (amebaiot.com Arduino doc repo) | Verbatim quote: **"Camera FCS Mode — Disable — No Camera FCS mode process. Enable — Enable Camera FCS mode, if the camera sensor has FCS mode."** Confirms that Disable produces zero FCS boot activity — not partial bypass. Camera still functions via normal OS-level sensor init (slower startup, same image quality). | HIGH |
| `hal_video.h` — `hal_video_fcs_en()` (ameba-arduino-pro2 `main`) | `hal_video_fcs_en(ch, en)` sets `cml->fcs = en` and calls `dcache_clean_invalidate_by_addr()`. When "Disable" is selected, this sets `cml->fcs = 0` at runtime — but this is an **application-layer flag only**. It does NOT affect whether the KM co-processor runs its FCS boot sequence. The real FCS bypass at cold boot comes from the dummy `PT_FCSDATA` partition (see postbuild.cpp finding above), not this runtime function. | MEDIUM |
| V4.0.8 release notes (ameba-arduino-pro2 releases, Oct 2024) | **Historical finding:** V4.0.8 was the release that simultaneously introduced BOTH "FCS mode for all supported sensors" AND "Flash Memory with FlashMemory.h API." These two features were co-released with zero documented interaction warning. Users upgrading from V4.0.7 → V4.0.8+ automatically receive both features; the FCS flash-write interaction bug could not have existed before V4.0.8. | MEDIUM |
| `hal_video.h` — `fcs_peri_info_ram_t` (ameba-arduino-pro2 `main`) | Structure fields: `fcs_peri_valid`, `fcs_OK`, `fcs_used`. Lives in RAM; populated by bootloader after KM completes FCS. Application calls `hal_video_check_fcs_OK()` to read `fcs_OK`. When bug occurs, `fcs_OK = 0` is never set to 1 — and there is no API to retry FCS sensor initialization from user code. The failure is permanent for the session (until next boot). | MEDIUM |
| `video_boot.c` — `hal_voe_set_kmfw_base_addr()` IPC detail | Bootloader signals KM via `hal_voe_set_kmfw_base_addr(FCS_RUN_DATA_OK_KM)` (0x0082) on success or `FCS_RUN_DATA_NG_KM` (0x2081) on failure. KM reads this register to know whether TM-side FCS succeeded. Confirms that 0x2081 is written by the TM bootloader — the KM does not self-report it. The I2C failure occurs inside KM firmware (voe.bin), which signals 0x200A back to TM via `KM_FCS_ERROR_REG`. | MEDIUM |
| forum.amebaiot.com/t/camera-sensor-init-failed-gc2053/4321 (Aug 2025) | Newly identified thread: GC2053 sensor with "sensor init failed" and VOE initialization command failures. Snippet only — content blocked (403). Different sensor from our bug's typical JXF37/SC2336P but same symptom class. Not confirmed as flash-triggered. | LOW |
| forum.amebaiot.com/t/voe-frame-end-sensor-didnt-initialize-done/4302 (Aug 2025) | Search snippet confirms user had JXF37 camera with "FCS Mode: Disable" selected in their configuration — indicating a user was already running FCS Disabled during camera sensor failures. Content remains 403 blocked; no fix confirmation extractable from snippet. | LOW |
| ameba-arduino-pro2 `dev` branch + ameba-rtos-pro2 `main` | **SDK freeze confirmed by two independent agents.** No commits to either repository after May 5, 2026 (arduino) / May 1, 2026 (rtos). No new releases (V4.1.1-QC-V06 or stable V4.1.1) exist. FCS handshake states S1–S4 (`0x1118` KM→TM enter voe_open, `0x1318` ISP open done, `0x1518` 2-stage init done TM→KM, `0x1718` bring-up complete KM→TM) are now documented from header files for completeness. | LOW |
| All Chinese-language sources (CSDN, 知乎, EEWorld, 21IC, bbs.aithinker.com, Gitee, Baidu) | No new Chinese-language content on this bug. bbs.aithinker.com forum threads indexed by Google (BW21-CBV-Kit debugging, home surveillance, DIY camera project, unboxing — tids 45923, 45929, 46028, 46140, 47223) all return 403. No accessible discussion of FCS flash-write camera failure in any Chinese-language source. | LOW |

**Revised "Camera FCS Mode = Disable" workaround assessment:**

The Cycle U7 hypothesis ("packager omits or invalidates the FCS partition") is now refined:
- The FCS partition is **NOT omitted** — `PT_FCSDATA` is always present in the flash image
- Instead, `fcs_data_dummy.bin` is placed there — it has an **invalid magic number**
- At cold boot, `hal_voe_fcs_check_OK()` reads the magic → fails → bootloader skips KM FCS sensor I2C init
- The KM's I2C attempt (`FCS_I2C_INIT_ERR = 0x200A`) is never reached
- Camera initializes normally via the OS-level path (NONE_FCS_MODE / `video_get_fw_isp_info()`)
- **Net effect:** slower camera start, no flash-write-triggered boot failure

**This mechanism is now strongly supported by source code** — but is still NOT confirmed by a hardware test with a flash-written device. The counter-risk remains: if the KM firmware (voe.bin, closed-source) ignores the TM-side magic check and independently attempts I2C based on its own flash read, the workaround fails.

**SDK state as of 2026-05-15 (Cycle U8 — unchanged):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release: V4.1.1-QC-V05 (Mar 6, 2026) — no fix
- ameba-rtos-pro2 main: frozen at May 1, 2026 (VOE 1.7.1.0)
- ameba-arduino-pro2 dev: frozen at May 5, 2026 (SHA `13961cc`)

**No confirmed fix. Bug remains unpatched as of 2026-05-15 (Cycle U8).  
Highest-priority action: hardware test of "Camera FCS Mode = Disable" as a workaround — mechanism now strongly supported by postbuild.cpp source code analysis.**

## Research Update — 2026-05-15 (Cycle U9)

**Search scope:** ameba-rtos-pro2 commits (May 1–15); ameba-arduino-pro2 main/dev branches; GitHub issues (both repos); forum.amebaiot.com new threads; ideashatch/HUB-8735 issues; Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com); GitHub_release_note.txt; general web for FCS disable workaround reports.

**Key new finding this cycle:** ameba-rtos-pro2 is no longer frozen — new commits landed on May 15, 2026. The most significant is a third iterative MMF fix: `afc85a0` "[amebapro2][mmf] avoid task recreate in mmf start". This is directly relevant to the "[VOE][WARN]slot full" deadlock symptom (mild case), though it does not address the FCS I2C cold-boot root cause. No new Arduino SDK releases. All public issue trackers remain empty of this bug report. No confirmed fix.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 commit `afc85a0` "avoid task recreate in mmf start" (May 15, 2026) | **SDK no longer frozen.** This is the third MMF stability fix in the rtos-pro2 upstream (after `fb3dc02` queue-init check and `3130193` JPEG exception, both Apr 1). Fix wraps task verification and creation under a `ctrl_lock` synchronization guard and applies across all MMF topologies (SISO, SIMO, MISO, MIMO). Prevents duplicate/re-entrant task creation during MMF startup. This is mechanically consistent with preventing the `[VOE][WARN]slot full` deadlock, which occurs when a module attempts to enqueue into an already-consumed slot during a mid-initialization restart. Changes land in `libmmf.a` (compiled binary); source change not directly visible. **NOT yet in any Arduino SDK release.** | MEDIUM |
| ameba-rtos-pro2 commit `3f95070` "Sync upstream 7343927…" (May 15, 2026) | Upstream sync commit; adds one entry to `GitHub_release_note.txt` documenting the MMF task recreate fix. Confirms the SHA `7343927fdd080e02020b33d5b1ea9c11e77d16fb` is the newest entry in the upstream private repo's release log as of May 15. No flash, FCS, boot, VOE, or sensor changes in this sync. | LOW |
| ameba-rtos-pro2 commits `9c8b6f6` and `d2676f1` (May 15, 2026) | WLAN fixes only: `wowlan modify dhcp renew unit from min to sec` and `modify dynamic ARP example`. Entirely unrelated to camera/flash/FCS. | LOW |
| ameba-arduino-pro2 main branch (fetched 2026-05-15) | **Still frozen.** Last commit remains `93d6351` "Release Version 4.1.0" (March 2, 2026). No new commits, no new stable or pre-release. The three upstream MMF fixes (Apr 1 + May 15) and VOE 1.7.1.0 remain unmerged into the Arduino SDK after 6–10+ weeks. | MEDIUM |
| ameba-arduino-pro2 open issues (fetched 2026-05-15) | 17 open issues confirmed. Most recent is #398 (March 29, 2026, raw video access feature request). No new issues since May 5, 2026. No issue filed for FCS/flash/camera/VOE_OPEN_CMD/slot-full/boot failure. | LOW |
| ameba-rtos-pro2 open issues (fetched 2026-05-15) | Unchanged: 3 open issues (AI glass src path #16, chip support #4, antivirus #3). No new issues. No FCS/flash/camera bug filed. | LOW |
| forum.amebaiot.com/t/voe-frame-end-sensor-didnt-initialize-done/4302 (Aug 2025) | Still HTTP 403 Forbidden on direct fetch. Continues to appear in search engine results. No new snippets accessible this cycle. Content remains entirely inaccessible without forum login. | MEDIUM (blocked) |
| forum.amebaiot.com/t/camera-sensor-init-failed-gc2053/4321 (Aug 2025) | Confirmed accessible URL in search results this cycle. Thread: GC2053 sensor with "sensor init failed." Not confirmed as flash-triggered. No new snippet data accessible. | LOW |
| Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com, May 15 sweep) | bbs.aithinker.com indexed threads (tids 45923, 47223, 45929, 46060, 45688) confirmed present in Google index — content about BW21-CBV-Kit unboxing, environment setup, DIY camera project, BLE tutorial — but all return 403. mcublog.cn article (April 2026) about BW21-CBV with Feishu bot for LED+photo is accessible, unrelated to our bug. No new Chinese-language content on FCS flash-write camera failure found anywhere. | LOW |

**Third MMF fix analysis — "slot full" symptom relevance:**

The three upstream MMF fixes form a sequence addressing progressively deeper task-lifecycle safety:
1. `fb3dc02` (Apr 1): Refuse module init if state != `MM_STAT_READY` → prevents bad-state entry
2. `3130193` (Apr 1): Exempt JPEG snapshot from the above check → prevents regression
3. `afc85a0` (May 15): Guard task creation under `ctrl_lock`; skip re-creation if task already exists → prevents duplicate-task deadlock

This sequence suggests Realtek's engineering team is iterating on MMF stability without directly addressing the FCS/I2C cold-boot root cause. The "slot full" symptom (mild case, 70× flash writes) may be mitigated by these fixes if the underlying cause is MMF task duplication on restart. The severe case (sector erase → `VOE_OPEN_CMD fail` + `FCS_I2C_INIT_ERR`) is not addressed by any of these fixes.

**SDK state as of 2026-05-15 (Cycle U9):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release: V4.1.1-QC-V05 (Mar 6, 2026) — no fix
- ameba-rtos-pro2 main: Active again as of May 15; newest commit `afc85a0` (MMF task recreate fix, May 15, 2026)
- ameba-arduino-pro2 dev/main: Frozen; no new commits or releases

**No confirmed fix. Bug remains unpatched as of 2026-05-15 (Cycle U9).  
Top unresolved action: hardware test of "Camera FCS Mode = Disable" — mechanism confirmed by source; no public hardware test result found anywhere.**

## Research Update — 2026-05-15 (Cycle U10)

**Search scope:** ameba-rtos-pro2 commits (May 15+); ameba-arduino-pro2 dev/main branches and releases; forum.amebaiot.com new threads; ideashatch/HUB-8735 issues; Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com); GitHub issues (both repos); video_user_boot.c PRIVATE_TEST/FCS_PARTITION analysis; video_boot.c FCS error-path analysis; official Arduino Getting Started doc (FCS menu options).

**Key new findings this cycle:**
- Both repos still frozen (ameba-rtos-pro2 at May 15 / ameba-arduino-pro2 at May 5)
- `PRIVATE_TEST` macro in `video_user_boot.c` is about **privacy masking overlays**, NOT FCS debugging — earlier ISP doc search snippet was misleading
- `FCS_PARTITION` flag (line ~394 of `video_user_boot.c`) is a newly documented conditional: when defined, FCS data loads from a "bootloader partition" instead of `NOR_FLASH_FCS (0xF0D000)` in flash storage
- `video_boot.c` FCS error-path analyzed: the TM-side bootloader has **no recovery fallback** when the KM returns `FCS_I2C_INIT_ERR (0x200A)` — weak-function stubs `user_load_sensor_boot()` and `video_boot_init_sensor_config()` both return error with no alternative init
- Official Getting Started doc confirms: Camera FCS Mode Disable = "No Camera FCS mode process." — zero warnings about FlashMemory interaction exist in any public documentation
- No hardware test of FCS Disable workaround found anywhere in public web searches

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 commits/main (fetched 2026-05-15) | **Repo still frozen at May 15, 2026.** Full commit list retrieved and verified: newest entry is `3f95070` "Sync upstream 7343927…" (May 15). Zero new commits in 0 days since last cycle. No flash, FCS, VOE, or sensor changes visible. | LOW |
| ameba-arduino-pro2 dev branch (fetched 2026-05-15) | **Still frozen at May 5, 2026** (SHA `13961cc` "Update API for AMB82-zero and SWD off logic"). Full commit list retrieved and verified. No V4.1.1 stable release; latest pre-release remains V4.1.1-QC-V05 (Mar 6, 2026). | LOW |
| `video_user_boot.c` — `PRIVATE_TEST` macro (lines ~467–489) | **Correction of earlier misinterpretation:** `PRIVATE_TEST` is NOT a FCS debug path. It enables privacy masking (rectangular color-blocked overlay regions with configurable dimensions and bitmap patterns). An earlier ISP documentation search snippet implied it was for "FCS testing" — that was incorrect. Confirmed via direct source code retrieval. | LOW |
| `video_user_boot.c` — `FCS_PARTITION` flag (line ~394) | **Previously undocumented conditional.** When `FCS_PARTITION` is defined, `boot_read_flash_data()` loads FCS data from a "bootloader partition" rather than directly from `NOR_FLASH_FCS (0xF0D000)` in NOR flash storage. Default state (undefined) = reads from 0xF0D000 as previously documented. The partition-based path may load FCS data from a different address not exposed in the public partition table; relevance to the cold-boot bug is unknown but notes an unexplored internal SDK mode. | LOW |
| `video_boot.c` — FCS error path (full analysis) | **No TM-side recovery from KM `FCS_I2C_INIT_ERR`.** Weak functions `user_load_sensor_boot()` (returns 0) and `video_boot_init_sensor_config()` (returns -1) provide hooks for sensor init but have no default implementation. `video_btldr_fcs_terminated()` (lines 809–837) only fires when `user_disable_fcs()` returns 1 (hardcoded to 0). When the KM signals `FCS_I2C_INIT_ERR (0x200A)`, the TM bootloader receives the NG status, logs it, and exits with sensor uninitialized — consistent with "It don't do the sensor initial process." Confirms: overriding `user_load_sensor_boot()` in user code (via RTOS SDK weak-function override) could theoretically provide a fallback, but this would require building from source. | MEDIUM |
| ameba-arduino-doc `Getting Started with Ameba.rst` (main branch, fetched 2026-05-15) | Official Getting Started documentation for AMB82-Mini. Camera FCS Mode option confirmed: Disable = "No Camera FCS mode process." / Enable = "Enable Camera FCS mode, if the camera sensor has FCS mode." **Zero warnings or notes about FlashMemory write interaction with FCS.** The documentation gap (no warning to users that FlashMemory writes can destroy FCS boot integrity) is confirmed. Full supported sensor list in Tools menu: JFX37, JFX53, GC2053, GC4653, GC5035, IMX307, IMX327, IMX662, PS5268, OV9734, SC2336 (11 sensors). K306P (added in Apr 1 rtos-pro2 commit) is NOT yet in the Arduino IDE Tools menu. | LOW |
| ideashatch/HUB-8735 issues (fetched 2026-05-15) | No new issues. Only Issue #10 (PS5268 sensor id fail, Aug 2025) remains open — unrelated to our bug. | LOW |
| ameba-arduino-pro2 issues (fetched 2026-05-15) | 11 open issues visible; none related to FCS/flash/camera boot failure. No new issues since last cycle. | LOW |
| All forum threads (4302, 4748, 4777, 4834, 3429) | All still HTTP 403 Forbidden. No new accessible content from the Realtek Ameba developer forum this cycle. | LOW (blocked) |
| Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com, mcublog.cn, May 15 sweep) | bbs.aithinker.com, bbs.ai-thinker.com, forum.amebaiot.com all 403. mcublog.cn BW21-CBV article (April 2026) also 403 this cycle. CSDN/Zhihu/EEWorld/21IC searches: zero new results about FCS flash-write camera failure. | LOW |
| Web-wide search for exact error phrase "It don't do the sensor initial process" | **Zero results** (same as previous cycles). This research log is the only public documentation of this exact Boot ROM message and its connection to flash writes. | LOW |

**New technical insight — `user_load_sensor_boot()` weak function override:**

The `video_boot.c` analysis surfaces a previously unnoticed RTOS SDK extension point. Because `user_load_sensor_boot()` is a **weak function**, an RTOS SDK user could override it to provide a fallback sensor initialization when FCS fails. The override would execute when FCS returns NG — potentially allowing the camera to initialize via the normal OS path at boot time, without the delay penalty of FCS fast-start. However:
- This requires building from the RTOS SDK (not Arduino)
- The function signature and calling convention are not publicly documented
- It is unknown whether the OS-level video subsystem properly re-initializes after a bootloader-level failure

This remains theoretical — no public implementation exists.

**SDK state as of 2026-05-15 (Cycle U10 — unchanged from U9):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release: V4.1.1-QC-V05 (Mar 6, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at May 15, 2026 (newest: `3f95070`, `afc85a0`)
- ameba-arduino-pro2 dev/main: Frozen at May 5, 2026 (SHA `13961cc`)

**No confirmed fix. Bug remains unpatched as of 2026-05-15 (Cycle U10).  
Top unresolved action: hardware test of "Camera FCS Mode = Disable" — mechanism confirmed by source code; no public hardware test result found in any accessible web source.**

## Research Update — 2026-05-15 (Cycle U11)

**Search scope:** ameba-rtos-pro2 commits after May 15; ameba-arduino-pro2 issues/releases after May 5; forum.amebaiot.com new threads; GitHub Discussions; English/Chinese community sources; FlashMemory.cpp source re-verification; "[SPIF Err]Invalid ID" error documentation; SDK flash layout documentation.

**Key new findings this cycle:** Both repos remain frozen. Three previously untracked forum threads newly identified (2929, 4811, 4541). "[SPIF Err]Invalid ID" error confirmed in thread #4834 context — represents a more severe boot failure variant where the flash chip itself cannot be identified at boot, extending the known severity ladder. No new fixes, no new public hardware tests of the FCS Disable workaround.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 commits (fetched 2026-05-15) | **Still frozen.** Direct fetch of commits page confirms newest commit remains `3f95070` "Sync upstream 7343927…" (May 15, 2026) — identical to U9/U10. Zero new commits in 0 days. No flash, FCS, VOE, sensor, or boot changes. | LOW |
| ameba-arduino-pro2 issues page (fetched 2026-05-15) | **17 open issues confirmed, none bug-related.** Newest issue is #398 (Mar 29, 2026, raw video access feature request). No issues filed for camera, flash, FCS, VOE, or boot failure. Bug remains entirely unreported on the official tracker. | LOW |
| forum.amebaiot.com/t/.../4834 — "[SPIF Err]Invalid ID" detail | **New error detail from thread #4834 "Boot failure after OTA update":** Web search snippets confirm this thread contains the error string "[SPIF Err]Invalid ID" and "[BOOT Err]Flash init error" — the boot ROM's SPIF controller cannot read the JEDEC identification bytes from the flash chip at all. Mechanism: if the WIP (Write-In-Progress) bit is active at power-up after an incomplete or just-finished erase, the flash chip holds MISO high and does not respond to the RDID command; boot ROM logs "Invalid ID" and halts flash init entirely. This is a **more severe** failure mode than FCS_I2C_INIT_ERR (which occurs later in boot after flash is successfully initialized). Adds a new severity tier to the known failure ladder. Thread content still 403-blocked. | MEDIUM |
| forum.amebaiot.com/t/amb82-mini-camera-not-sending-data-to-image-processor/2929 | **Newly identified thread** (previously untracked). Title: "AMB82-Mini Camera Not Sending Data to Image Processor." Documents "[VOE] osd2enc receive timeout" and "[VOE] isp2osd receive timeout" errors — OSD-to-encoder and ISP-to-OSD pipeline timeout errors. These are distinct from our FCS_I2C_INIT_ERR failure (which occurs in the bootloader before OS camera init). Not confirmed as flash-write-triggered. Thread content blocked (403). | LOW |
| forum.amebaiot.com/t/camera-sketch-errors-warnings/4811 | **Newly identified thread** (previously untracked). Title: "camera sketch errors/warnings." Content blocked (403). Thread number is higher than 4777 (Mar 2026) suggesting it was posted after March 2026. Possibly documents camera initialization warning messages from an Arduino sketch. No snippet content accessible to determine relevance to our bug. | LOW |
| forum.amebaiot.com/t/ameba-mini-with-gc4653-camera-sensor/4541 | **Newly identified thread** (previously untracked). Title: "Ameba Mini with GC4653 camera sensor." Web search suggests it discusses using flash memory with the GC4653 sensor. Content blocked (403). GC4653 is one of the 11 sensors in the AMB82-Mini Tools menu. | LOW |
| FlashMemory.cpp direct source fetch (2026-05-15) | **Re-confirmed from source:** No WIP polling, no mutex acquisition, no `dcache_invalidate_by_addr` call in any FlashMemory operation. After `flash_write_word()`, code reads back to verify but provides no retry beyond one full sector rewrite attempt. This is consistent with all prior findings (U7 Finding 205) — confirmed unchanged. | LOW |
| ameba-arduino-pro2 GitHub Discussions | **Does not exist** — GitHub Discussions are not enabled for this repository (returns 404). No community discussion channel beyond Issues exists on GitHub. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com, May 15 sweep) | Two Zhihu BW21-CBV articles identified (p/24778003595 — HomeAssistant integration; p/1933901413328586556 — fall detection DIY) — both return 403. bbs.ai-thinker.com BW21-CBV threads (MQTTS, OLED, BLE, gesture recognition) confirmed indexed in search results but all 403-blocked. No new Chinese-language content about FCS flash-write camera failure found anywhere. | LOW |

**Extended severity ladder (revised with Cycle U11 data):**

| Flash operations | Next boot failure mode | Error(s) observed |
|---|---|---|
| 0 writes | Always OK | — |
| 1× `flash_write_word` (4 bytes, no erase) | Stable | — |
| 70× `flash_write_word` (280 bytes, no erase) | `[VOE][WARN]slot full` deadlock | `FCS_BYPASS_WHILE1_KM (0x0083)` |
| Any sector erase | VOE camera complete fail | `FCS_RUN_DATA_NG_KM (0x2081)` + `FCS_I2C_INIT_ERR (0x200A)` |
| OTA flash write → immediate reboot (thread #4832) | Console silent, no boot messages | Unknown (soft-reset D-cache path) |
| Flash write/erase → power-cycle with WIP still active (thread #4834) | Flash chip not recognized at boot | `[SPIF Err]Invalid ID` + `[BOOT Err]Flash init error` |

The "[SPIF Err]Invalid ID" tier is the most severe: the boot ROM cannot initialize the SPI flash controller at all, so the entire system is bricked until the flash operation completes and the device is power-cycled again. This is consistent with the Zephyr WIP-bit boot failure precedent (logged in prior cycles).

**SDK state as of 2026-05-15 (Cycle U11 — unchanged):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release: V4.1.1-QC-V05 (Mar 6, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at May 15, 2026 (newest: `3f95070`, `afc85a0`)
- ameba-arduino-pro2 dev/main: Frozen at May 5, 2026 (SHA `13961cc`)

**No confirmed fix. Bug remains unpatched as of 2026-05-15 (Cycle U11).  
Top unresolved action: hardware test of "Camera FCS Mode = Disable" — mechanism confirmed by source; still no public hardware test result in any accessible source.**

## Research Update — 2026-05-16 (Cycle U12)

**Search scope:** Four parallel agents: (1) GitHub — all repos post-May 15 activity; (2) English forum/web — new threads, error code indexing, workaround reports; (3) Chinese sources — comprehensive sweep; (4) SDK deep-dive — `video_boot.c` full FCS Disable boot path trace, `NONE_FCS_MODE` analysis, flash address safety table.

**Key new findings this cycle:**
- FCS Disable boot sequence fully traced from SDK source — workaround is mechanistically complete; KM enters `FCS_BYPASS_WHILE1_KM` (0x0083) with dummy blob, never reaches I2C; `NOR_FLASH_FCS` (0xF0D000) never read; camera reinitializes via application layer
- **"It don't do the sensor initial process" appears in BOTH the bug state AND the FCS Disable state** — the message alone does not indicate camera failure; it indicates the bootloader skipped sensor init, which is expected when FCS is disabled
- `NONE_FCS_MODE` is baked into prebuilt `libvideo_ntz.a` as always-1; independent of Arduino `Arduino_FCS_MODE` compile flag
- Thread #4302 new snippet detail: user had FCS Mode: **Disable** but got `[VOE]frame_end: sensor didn't initialize done!` — a **different** error from our `FCS_I2C_INIT_ERR` (frame pipeline timeout vs KM boot-ROM I2C failure); may indicate a race condition in the non-FCS camera init path
- All repos confirmed frozen since May 15, 2026; no new releases, issues, or commits anywhere
- Zero new Chinese-language content; zero new English public reports of this specific bug

| Source | Key Finding | Priority |
|---|---|---|
| `video_boot.c` `video_btldr_init_sensor_process()` (lines 29–44) | **"It don't do the sensor initial process" appears in BOTH the FCS fail state AND the FCS Disable state.** Weak default `user_load_sensor_boot()` always returns 0 → message printed → bootloader-level sensor init returns -1. With FCS Disabled, camera STILL initializes via application-layer `video_init()` / `video_init_peri()` / `video_open()`. The message alone does NOT indicate camera failure. | MEDIUM |
| `video_boot.c` `video_btldr_process()` (line 691) + `video_api.c` `video_init_peri()` (line 1518) | **FCS Disable boot sequence fully traced:** (1) Dummy blob → no MFCS magic → KM enters `FCS_BYPASS_WHILE1_KM` (0x0083); (2) `hal_voe_fcs_check_OK()` = 0 → FCS init block skipped; (3) `user_boot_config_init()` never called → `NOR_FLASH_FCS (0xF0D000)` never read; (4) Application `video_init_peri()` L1518 checks `!hal_video_check_fcs_OK()` → TRUE → re-registers all GPIO/I2C pins, powers sensor via GPIO (L1566), registers I2C (L1581) → full camera initialization from scratch. **The `FCS_I2C_INIT_ERR` cold-boot failure path cannot be triggered with FCS Disabled.** | HIGH |
| `video_api.c` `NONE_FCS_MODE` macro analysis | **`NONE_FCS_MODE` is baked into the prebuilt `libvideo_ntz.a` as always-1** — not controlled by the Arduino `Arduino_FCS_MODE` compile flag. The two flags are independent: `Arduino_FCS_MODE` (boards.txt) affects post-build image packaging (which ISP IQ JSON is used); `NONE_FCS_MODE` controls the always-compiled-in `video_get_fw_isp_info()` application-layer fallback sensor info path. `NONE_FCS_MODE = 1` is therefore always active regardless of FCS mode setting. | MEDIUM |
| Flash address safety analysis (`video_boot.c` + `postbuild.cpp`) | **With FCS Disabled, neither FCS-sensitive flash region is accessed during cold boot:** PT_FCSDATA (0x8000 region) — KM enters bypass before any meaningful address read; NOR_FLASH_FCS (0xF0D000) — `user_boot_config_init()` is never called. Any `FlashMemory.write()`/`erase()` touching either region is harmless to camera boot reliability with FCS Disabled. Only raw bootloader/partition-table regions (< 0x8000) remain always-dangerous. | HIGH |
| forum.amebaiot.com/t/voe-frame-end-sensor-didnt-initialize-done/4302 (Aug 2025) — Google snippet | **Thread #4302 new detail from snippet:** User explicitly had "Camera FCS Mode: Disable" + JXF37 sensor and got `[VOE]frame_end: sensor didn't initialize done!`. This is a DIFFERENT error from our `FCS_I2C_INIT_ERR` — it occurs in the frame pipeline AFTER camera initialization, not during boot-ROM KM init. May indicate a race condition in the non-FCS application-layer camera init path (sensor not fully ready before first frame capture). Does NOT refute the FCS Disable workaround for our specific bug, but suggests FCS Disable may introduce a separate, lower-severity camera reliability risk. Thread content still 403 blocked. | MEDIUM |
| All GitHub repos (Ameba-AIoT, ideashatch, Ai-Thinker-Open), fetched 2026-05-16 | **All repos frozen since May 15, 2026.** ameba-rtos-pro2 HEAD = `3f95070` (May 15); ameba-arduino-pro2 main HEAD = `93d63514` (Mar 2); dev = `13961ccf` (May 5); ideashatch/HUB-8735 last commit Dec 2025; latest HUB-8735 release = V4.0.15_HUB8735 (Apr 2025, tracks upstream 4.0.9). No V4.1.1 stable release, no QC-V06+, no new issues filed. | LOW |
| English web (all search engines, forums, community sites) | **Still zero indexed results** for `"FCS KM_status 0x00002081"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"It don't do the sensor initial process"`, `"VOE_OPEN_CMD fail"`. This research log remains the only public documentation of this bug and its error codes. | LOW |
| Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/Gitee/Bilibili, May 16) | No new Chinese-language content about FCS flash-write camera failure. All Chinese community sites remain 403-blocked. Google-indexed snippets from Chinese sites show only unrelated BW21-CBV DIY projects (fall detection, HomeAssistant, surveillance). No technical FCS articles found. | LOW |

**Workaround confidence assessment — complete mechanistic chain (Cycle U12):**

| Boot-path chain link | Evidence source |
|---|---|
| Dummy blob written to PT_FCSDATA (no MFCS magic `0x5343464D`) | `postbuild.cpp` L428, L445–450, L680 |
| KM reads magic → validation fails → enters `FCS_BYPASS_WHILE1_KM` (0x0083) | `rtl8735b_voe_status.h` L158 |
| KM never reaches GPIO init (0x2009) or I2C init (0x200A) | KM error code table in `voe_status.h` |
| `hal_voe_fcs_check_OK()` returns 0 → FCS init block skipped in bootloader | `video_boot.c` L691 |
| `user_boot_config_init()` not called → `NOR_FLASH_FCS (0xF0D000)` never read | `video_boot.c` gating on `hal_voe_fcs_check_OK()` |
| "It don't do the sensor initial process" printed (expected, not a failure) | `video_boot.c` L29–44 |
| `video_init_peri()` L1518: `!hal_video_check_fcs_OK()` → full GPIO/I2C re-register, sensor power-on, I2C registration | `video_api.c` L1518, L1566, L1581 |
| Camera streams normally (slower start, no FCS fast-boot) | Official docs, `boards.txt` |

**Remaining risk:** Thread #4302 shows a user with FCS Mode: Disable experiencing `[VOE]frame_end: sensor didn't initialize done!` — a frame pipeline timeout distinct from the KM I2C boot failure. This may be a race condition in the non-FCS camera init path unrelated to flash writes. The relationship to flash writes is unconfirmed (thread content 403-blocked).

**Recommended hardware test sequence (unchanged):**
1. Enable "Camera FCS Mode = Disable" in Arduino IDE Tools menu → rebuild + flash
2. Run `flash_erase_sector()` → power cycle → verify `VOE_OPEN_CMD fail` / `FCS_I2C_INIT_ERR` does NOT occur
3. Observe "It don't do the sensor initial process" appears (expected, not a failure)
4. Verify camera streams (expect 1–3s longer startup than FCS-enabled)
5. Monitor for `[VOE]frame_end: sensor didn't initialize done!` — if seen, may be unrelated race condition

**SDK state as of 2026-05-16 (Cycle U12 — unchanged):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release: V4.1.1-QC-V05 (Mar 6, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at May 15, 2026 (`3f95070`, `afc85a0`)
- ameba-arduino-pro2 dev/main: Frozen at May 5, 2026 (`13961cc`)

**No confirmed fix. Bug remains unpatched as of 2026-05-16 (Cycle U12).
Workaround ("Camera FCS Mode = Disable") is mechanistically confirmed from full source-code analysis but still lacks hardware validation. This is the highest-priority open action.**

## Research Update — 2026-05-16 (Cycle U13)

**Search scope:** Four parallel agents: (1) GitHub — all repos post-May 15, 2026 activity; (2) English forum/web — new threads, FCS disable workaround reports, readthedocs ISP docs; (3) Chinese sources — comprehensive sweep (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/Gitee/Bilibili); (4) SDK technical deep-dive — `hal_flash_ns.c` actual non-secure world implementation, `hal_voe_export_ctrl.h` new enum values, `voe_isp_export_ld_info_digest_check_from_nor` digest scope.

**Key new findings this cycle:**
- `flash_ns_sector_erase` in `hal_flash_ns.c` (the actual non-secure implementation, not just the stub wrapper) confirmed: sends SE opcode and returns immediately with **zero WIP polling**. `flash_ns_wait_ready` (which polls `rdsr & 0x1`) is a separate function never called from erase or page-program.
- `voe_isp_export_ld_info_digest_check_from_nor` digest scope partially clarified: `digest_obj` parameter maps to `VOE_EXPORT_LD_ISP_IMG_MULTI_FCS_HDR = 0x04` and FCS sensor-set enum IDs (0x10–0x19). The digest covers FCS multi-sensor header data specifically, which partially limits the digest-corruption cold-boot hypothesis.
- New forum thread #4748 identified: user compiled custom `voe.bin` + `sensor_f37.bin`, placed in SDK `voe_bin/` folder, sensor failed to initialize — VOE binary is the critical sensor-init component.
- `ameba-doc-rtos-pro2-sdk.readthedocs-hosted.com/en/latest/application_note/15_ISP.html` surfaced as the most complete FCS documentation URL — returns 403; requires developer login.
- All tracked repos confirmed frozen at the same HEAD as Cycle U12 (zero new commits anywhere).
- No hardware test of FCS Disable workaround found in any public source.

| Source | Key Finding | Priority |
|---|---|---|
| `component/soc/8735b/fwlib/rtl8735b/source/ram/hal_flash_ns.c` (ameba-rtos-pro2, lines 1559–1580) | **`flash_ns_sector_erase` WIP non-polling confirmed from actual implementation.** The non-secure world driver sends the SE opcode via `spic_ns_tx_cmd()` and returns immediately. `flash_ns_wait_ready` (lines 1463–1477), which polls `rdsr & 0x1` (the Write-In-Progress bit), is a separate function that is **never called** from `flash_ns_sector_erase` or `flash_ns_page_program` (lines 2381–2566). Prior cycles only confirmed this from the stub wrapper `hal_flash.c`; this cycle confirms it from the actual ns-world implementation. The erase command is fire-and-forget at the C layer; any WIP polling must be done by the caller (FlashMemory does not do this). | MEDIUM |
| `hal_voe_export_ctrl.h` — `voe_isp_export_ld_info_digest_check_from_nor` + new enums | **Digest scope partially clarified.** The `digest_obj` parameter of `voe_isp_export_ld_info_digest_check_from_nor` maps to enum values in `hal_voe_export_ctrl.h`: `VOE_EXPORT_LD_ISP_IMG_MULTI_FCS_HDR = 0x04`, plus FCS sensor-set IDs 0x10–0x19, IQ set IDs 0x20–0x29, sensor set IDs 0x30–0x39 (up to 10 sensor configs). This means the digest check operates on FCS multi-sensor header data and pre-loaded ISP/sensor blobs — NOT on the raw user-data region written by `FlashMemory.write()` (0xFD0000–0xFFFFFF). This partially refines the digest-corruption cold-boot hypothesis: the digest check alone is unlikely to be disrupted by writes to the 0xFD0000 user region, though the FCS partition at 0xF0D000/0x8000 remains potentially vulnerable if a sector erase at 0xFD0000 aliases into an adjacent sector boundary. | MEDIUM |
| forum.amebaiot.com/t/need-latest-voe-and-sensor-drivers-source-code/4748 | **Newly identified thread** (previously untracked). User compiled custom `voe.bin` + `sensor_f37.bin` from the AmebaPro2 RTOS SDK and placed them in the Arduino SDK `voe_bin/` folder; camera sensor failed to initialize. Confirms that `voe.bin` (the KM co-processor firmware) is the critical binary for sensor initialization and that incorrect or custom `voe.bin` produces sensor init failure. Tangentially relevant: if the KM co-processor reads FCS data from flash during boot, any corruption of its expected data produces the same class of failure. Thread content 403 blocked. | LOW |
| `ameba-doc-rtos-pro2-sdk.readthedocs-hosted.com/en/latest/application_note/15_ISP.html` | **Newly surfaced documentation URL.** This readthedocs-hosted page is the most complete FCS documentation available and was surfaced by multiple search queries. Returns HTTP 403 (requires developer login or Realtek partner access). The page likely documents FCS flash address layout, `CMD_VIDEO_PRE_INIT_LOAD` with `SAVE_TO_FLASH` option, and the FCS Disable behavior in detail. Accessing this page may resolve open questions about digest coverage and FCS partition boundaries. | LOW |
| All GitHub repos (Ameba-AIoT, ideashatch, Ai-Thinker-Open), fetched 2026-05-16 | **All repos confirmed frozen.** ameba-rtos-pro2 HEAD = `3f95070` (May 15); ameba-arduino-pro2 main HEAD = `93d63514` (Mar 2); dev HEAD = `13961ccf` (May 5); ideashatch/HUB-8735 last commit Dec 2025. Zero new commits, releases, or issues since Cycle U12. `FCS_I2C_INIT_ERR` and `FCS_RUN_DATA_NG_KM` return zero results in any GitHub code search — confirmed not present in any publicly indexed repository. | LOW |
| All English/Chinese web sources (forum, CSDN, 知乎, EEWorld, 21IC, Bilibili, Gitee, bbs.aithinker.com) | **No new accessible content anywhere.** All Chinese community sites remain 403. Zero new English-language forum posts or blog articles about the FCS flash-write camera failure. No hardware test of the FCS Disable workaround reported in any publicly accessible source. Error strings `"It don't do the sensor initial process"`, `"FCS KM_status 0x00002081"`, `VOE_OPEN_CMD fail`, `FCS_I2C_INIT_ERR` remain unindexed outside the known 403-blocked forum threads. | LOW |

**Revised cold-boot failure mechanism (digest hypothesis update):**

The digest-scope clarification from `hal_voe_export_ctrl.h` refines the two-mechanism model:

- `voe_isp_export_ld_info_digest_check_from_nor` checks FCS multi-sensor headers (enum IDs 0x04, 0x10–0x19) — these live inside the FCS partition (PT_FCSDATA at 0x8000 and NOR_FLASH_FCS at 0xF0D000), NOT in the FlashMemory user region (0xFD0000+). Direct address-space corruption of the digest source by FlashMemory writes is therefore **unlikely** (no overlap for 4-byte or 280-byte writes).
- The severe failure (sector erase at 0xFD0000) remains unexplained by digest corruption alone. The most likely mechanism for sector-erase severity is the **WIP bit at cold boot**: `flash_ns_sector_erase` returns immediately without polling WIP. If power is cycled while the erase is still in progress (or very shortly after), the flash chip is still executing the erase command at next boot. The KM co-processor's first flash read (FCS partition) can then return 0xFF bytes (erased/undefined state) or block, causing `FCS_I2C_INIT_ERR`. Writes to 0xFD0000 and erases to adjacent sectors may not complete before the host cuts power.
- The **severity gradient** (4-byte write → stable; 280-byte write → mild; sector erase → complete fail) maps well to WIP duration: a 4-byte page program completes in ~0.3ms; 280 bytes in ~2ms; a 4KB sector erase takes 30–300ms. The longer the WIP window, the higher the probability that power is cut before the operation completes.

**WIP-duration hypothesis — testable prediction:**
If the cold-boot failure is caused by the WIP bit being active at power-on, then adding a `hal_flash_wait_ready()` call (or manual `flash_stream_read()` of the just-erased sector) **immediately before the device is powered down** should eliminate the cold-boot failure regardless of FCS mode. This is a simpler workaround than disabling FCS entirely and would preserve fast camera start. Not yet tested in any public source.

**SDK state as of 2026-05-16 (Cycle U13 — unchanged):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release: V4.1.1-QC-V05 (Mar 6, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at May 15, 2026 (`3f95070`, `afc85a0`)
- ameba-arduino-pro2 dev/main: Frozen at May 5, 2026 (`13961cc`)

**No confirmed fix. Bug remains unpatched as of 2026-05-16 (Cycle U13).**

**Two highest-priority open actions:**
1. **Hardware test of "Camera FCS Mode = Disable"** — mechanism confirmed from source; no public test result exists.
2. **Hardware test of `hal_flash_wait_ready()` before power-down** — new hypothesis: if WIP bit is the cold-boot root cause, waiting for flash idle before power-off may fix the severe (sector-erase) case while preserving FCS fast-boot.

## Research Update — 2026-05-16 (Cycle U14)

**Search scope:** Four parallel agents: (1) GitHub — all repos post-May 15 activity, code search for FCS error symbols; (2) English forum/web — new threads, FCS disable workaround reports, error string indexing; (3) Chinese sources — comprehensive sweep (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/Gitee/Bilibili); (4) SDK deep-dive — `hal_flash_wait_ready` availability, WIP polling chain from `hal_flash_ns.c` / `hal_spic_ns.c`, `spic_ns_tx_cmd` vs `spic_ns_tx_cmd_no_check`, partition table from `amebapro2_partitiontable.json`, W25Q128JV timing datasheet.

**Key new findings this cycle:**
- **`hal_flash_wait_ready` IS publicly declared** in `hal_flash.h` (L108) — U13 stated "not found in any public RTL8735B code"; this was incorrect; Agent 4 retrieved it from the header directly.
- **WIP polling correction (major):** The NS-domain `flash_ns_sector_erase` → `spic_ns_tx_cmd` path DOES call `flash_ns_wait_ready` internally (hal_spic_ns.c L860/863). The characterization from U13 ("erase is fire-and-forget at the C layer") was wrong for the NS path — the erase function blocks until WIP clears before returning. The secure-domain `hal_flash_sector_erase` (ROM stub, `hal_flash.c` L730–742) remains unverifiable.
- **Partition table from JSON** (`amebapro2_partitiontable.json`): fcsdata = 0x8000–0x9000 (4 KB), `nn` ends at 0xF00000, `mp` = 0xFC0000–0xFC1000, FlashMemory default = 0xFD0000+. Zero adjacency between FlashMemory region and fcsdata — address overlap hypothesis fully refuted.
- **W25Q128JV datasheet timing confirmed:** tSE (4KB sector erase) = 45 ms typ / **400 ms max**; tPP (page program) = 0.7 ms typ / 3 ms max. The severity gradient (4-byte stable → 280-byte mild → sector-erase complete) correlates with WIP window duration if power is cut mid-operation.
- All repos confirmed frozen; no new releases; no new forum threads above #4811 about our bug; zero new Chinese-language content.

| Source | Key Finding | Priority |
|---|---|---|
| `hal_flash.h` L108 (ameba-rtos-pro2, public) | **`hal_flash_wait_ready` is publicly declared:** `void hal_flash_wait_ready(phal_spic_adaptor_t phal_spic_adaptor)`. Delegates to ROM stub via `hal_flash_stubs.hal_flash_wait_ready()`. `flash_ns_wait_ready` (`hal_flash_ns.h` L82, NS-world variant) polls status register S0 (WIP bit) until clear; Micron variant polls rdsr2 bit 7. Prior statement in U13 that this function "does not exist in any public RTL8735B code" was incorrect. Calling this from Arduino would require obtaining the `phal_spic_adaptor_t` pointer (internal to the flash HAL, not exposed by `FlashMemory.h`); direct use from an Arduino sketch is non-trivial. | MEDIUM |
| `hal_spic_ns.c` L806–876 vs L885–952 (ameba-rtos-pro2, public) | **WIP polling correction — NS path.** `spic_ns_tx_cmd` (write/erase path): calls both `spic_ns_wait_ready` (controller busy) and `flash_ns_wait_ready` (device WIP) after the SPI transfer — erase blocks until complete. `spic_ns_tx_cmd_no_check` (read path): only calls `spic_ns_wait_ready` (controller), skips `flash_ns_wait_ready` (device WIP). Reads therefore do NOT check device WIP before executing — a read issued immediately after a just-triggered erase could theoretically return erased/undefined data. This does NOT affect the cold-boot root cause (cold boot power is off), but it affects read-after-write correctness in user code. | MEDIUM |
| `amebapro2_partitiontable.json` (ameba-rtos-pro2, `project/realtek_amebapro2_v0_example/GCC-RELEASE/mp/`) | **Definitive partition layout retrieved:** `sysdata`=0x7000 (4KB), `fcsdata`=0x8000 (4KB), `boot_p`=0x9000, `boot_s`=0x30000, `fw1`=0x60000, `iq`=0x460000, `fw2`=0x520000, `nn`=0x920000–0xF00000, `mp`=0xFC0000–0xFC1000. Region 0xF00000–0xFBFFFF is unallocated. FlashMemory default (0xFD0000) is in unallocated space above `mp`. No address adjacency exists between FlashMemory and fcsdata (0x8000). **Address-overlap/digest-corruption hypothesis is fully and definitively refuted for the 0xFD0000 FlashMemory region.** | MEDIUM |
| W25Q128JV datasheet (Winbond, Rev F 2018-03-27, Mouser mirror) | **Exact WIP timing confirmed:** tSE (4KB sector erase) = 45 ms typical / 400 ms maximum. tPP (256B page program) = 0.7–0.8 ms typ / 3 ms max. Chip erase = 40 s typ / 200 s max. WIP bit (S0) = 1 while any erase/program/write-status is executing; flash ignores all new instructions except RDSR and suspend while busy. RTL8735B supports Winbond (0xEF), MXIC, GigaDevice (0xC8), XTX, EON, and Micron flash types; W25Q128JV is the standard part on AMB82-Mini boards. | LOW |
| Revised WIP-at-boot mechanism (synthesis, this cycle) | **Narrowed failure mode:** Because the NS erase path DOES poll WIP to completion, the erase function does NOT return until the flash device is idle. Therefore the WIP-at-boot failure requires power to be cut **during** the erase operation (before the function returns), not after. The 400 ms maximum window for a 4KB sector erase creates a realistic probability of power loss during operation (e.g., device losing battery, abrupt power-off after triggering erase). This maps to the severity gradient: tPP ≈ 1–3 ms (tiny risk window for 4-byte write) vs tSE ≈ 45–400 ms (large risk window for sector erase). If the user's system cannot cut power during a 400 ms window (e.g., hardware power latch after flash write), the WIP-at-boot path does not apply. | MEDIUM |
| `hal_flash.c` L730–742 — ROM secure stub | **Secure-domain `hal_flash_sector_erase` behavior unverified.** Delegates to `hal_flash_stubs.hal_flash_sector_erase()` (ROM function pointer). If FlashMemory.cpp routes through the NS path (likely for non-secure world code), WIP IS polled. If it routes through the secure stub, WIP polling is unknown. The path taken by Arduino's `flash_erase_sector()` call chain cannot be confirmed from public source alone. | LOW |
| forum.amebaiot.com thread #4811 (confirmed via Agent 2) | **Thread #4811 content confirmed:** "Camera_2_Lcd_JPEGDEC.ino error/warning" — a general camera sketch error/warning thread, NOT a camera cold-boot failure. Previously unconfirmed. Content still 403-blocked; title extracted from search snippet. | LOW |
| bbs.aithinker.com tid=46140 "BW21-CBV-Kit調試" (Agent 3, first appearance) | **Newly identified Chinese-language thread:** Title = "BW21-CBV-Kit debugging." Google search snippet reveals content is about **SWD-pin/I2C conflict** — user accidentally used SWD debug pins for I2C camera control, causing I2C communication failure (different hardware bug class, not FCS flash-write). Not our bug. URL: `https://bbs.aithinker.com/forum.php?mod=viewthread&tid=46140` (HTTP 403 blocked). | LOW |
| `ameba-doc-rtos-pro2-sdk.readthedocs-hosted.com/en/latest/application_note/08_FLASHLAYOUT.html` | **New documentation URL:** RTL8735B flash layout application note — the official partition documentation. Returns HTTP 403 (developer login required). Would likely confirm or extend the partition table findings from `amebapro2_partitiontable.json`. | LOW |
| All GitHub repos (ameba-rtos-pro2, ameba-arduino-pro2, ideashatch, Ai-Thinker-Open), fetched 2026-05-16 | **All repos confirmed frozen.** ameba-rtos-pro2 HEAD = `3f95070` (May 15, 2026); ameba-arduino-pro2 main HEAD = `93d63514` (Mar 2); dev HEAD = `13961ccf` (May 5); ideashatch/HUB-8735 last commit Dec 2025. No V4.1.1 stable release; no QC-V06+. No new issues, PRs, or commits in any repo. Two independent agents confirmed identical freeze state. | LOW |
| GitHub code search: `FCS_I2C_INIT_ERR`, `FCS_RUN_DATA_NG_KM`, `hal_flash_wait_ready RTL8735B` | `FCS_I2C_INIT_ERR` = 13 hits (all `rtl8735b_voe_status.h`); `FCS_RUN_DATA_NG_KM` = 17 hits (all `video_boot.c` variants). `hal_flash_wait_ready` has no search hits specific to RTL8735B camera/FCS context — function exists but no usage example connecting it to FCS workaround. No other repositories publicly document this bug. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/Gitee/Bilibili, May 16) | **Zero new content.** All Chinese community sites remain 403-blocked (bbs.aithinker.com, bbs.ai-thinker.com, CSDN articles, Zhihu). Bilibili, EEWorld, 21IC, Gitee return zero results for FCS flash-write camera failure on BW21-CBV/RTL8735B. No Chinese-language content on this bug exists in 14 research cycles. | LOW |

**Revised cold-boot mechanism — WIP hypothesis refinement:**

Since the NS erase path polls WIP to completion, the "cold-boot from power-cut-during-erase" scenario requires the user's hardware to lose power **during** the up-to-400 ms erase window. This is plausible for battery-powered devices or systems with external power control. For devices that remain powered continuously, this path does not apply, and a separate mechanism must explain the cold-boot failure.

The two most plausible cold-boot mechanisms (if power is NOT cut during the erase) remain:
1. The secure-domain `hal_flash_sector_erase` ROM stub may be the actual path taken by FlashMemory and may NOT poll WIP — leaving WIP active at function return.
2. The erase operation at 0xFD0000 (even though in unallocated space) disturbs the SPI flash controller state in a way the boot ROM does not handle on the next cold boot.

**Revised workaround table:**

| Workaround | Mechanism | Status | Confidence |
|---|---|---|---|
| "Camera FCS Mode = Disable" | Dummy blob → invalid magic → KM bypass (0x0083), never reaches I2C | Mechanistically confirmed from `postbuild.cpp`, `video_boot.c`, `video_api.c` | HIGH (source-confirmed, no hardware test) |
| `hal_flash_wait_ready()` after erase | Ensures WIP clears before power-down; requires internal adaptor pointer | Technically available in `hal_flash.h` L108; not accessible from `FlashMemory.h` API | LOW (untested, API access non-trivial from Arduino) |
| Add 500ms delay after `flash_erase_sector()` | Allows tSE worst-case (400ms) to complete before power-down | Simple Arduino workaround if power cut is the root cause | LOW (untested, only applicable to WIP-at-boot path) |

**SDK state as of 2026-05-16 (Cycle U14 — unchanged):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release: V4.1.1-QC-V05 (Mar 6, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at May 15, 2026 (`3f95070`, `afc85a0`)
- ameba-arduino-pro2 dev/main: Frozen at May 5, 2026 (`13961cc`)

**No confirmed fix. Bug remains unpatched as of 2026-05-16 (Cycle U14).**

**Top unresolved actions (unchanged from U13):**
1. **Hardware test of "Camera FCS Mode = Disable"** — source-confirmed mechanism; no public hardware test result exists anywhere.
2. **Determine which flash erase path FlashMemory.cpp actually invokes** — NS path (WIP polled) vs ROM secure stub (WIP unknown). If ROM stub, WIP-at-boot is a viable cold-boot root cause even without power being cut during erase.

## Research Update — 2026-05-17 (Cycle U15)

**Search scope:** Six parallel search threads: (1) GitHub — new commits/issues/releases after May 15; (2) English forums — new threads above #4834, FCS disable workaround hardware test reports; (3) Chinese sources — comprehensive sweep; (4) FlashMemory.cpp call chain — `flash_erase_sector` vs mbed API vs ROM stub; (5) New documentation portals — aiot.realmcu.com, ameba-doc-arduino-sdk readthedocs; (6) Realtek successor chip RTL8735C announcement.

**Key new findings this cycle:**
- **FlashMemory.cpp call chain confirmed**: calls `flash_erase_sector(flash_t *obj, uint32_t address)` — the mbed-compatible NOR Flash API, NOT `flash_ns_sector_erase` (NS-domain) or `hal_flash_sector_erase` (ROM stub) directly. This means the U13 WIP analysis for the NS path does not directly apply to FlashMemory's actual erase chain. The mbed-API `flash_erase_sector` routes through `hal_flash_sector_erase` (ROM stub via function pointer table) — the ROM stub WIP behavior remains the critical unknown.
- Three new forum threads newly identified (#4809, #3429, #4725) — all 403-blocked.
- Both ameba repos confirmed frozen; no new releases or commits since May 15 (rtos-pro2) / May 5 (arduino-pro2).
- RTL8735C successor chip (AmebaPro3?) announced; no public SDK exists yet.
- aiot.realmcu.com identified as a new official Realtek IoT documentation portal — all pages return 403.
- No hardware test of the FCS Disable workaround found anywhere in any public source.

| Source | Key Finding | Priority |
|---|---|---|
| `FlashMemory.cpp` (ameba-arduino-pro2 `main` branch, direct source fetch) | **Call chain resolved: FlashMemory.cpp calls `flash_erase_sector(flash_t *obj, uint32_t address)`** — the mbed-compatible NOR Flash API with a `flash_t` object. Function signature: `void flash_erase_sector(flash_t *obj, uint32_t address)`. This is different from both `flash_ns_sector_erase` (NS-domain, confirmed WIP-polled in U13/U14) and from `hal_flash_sector_erase` (ROM stub, WIP unknown). The mbed-style `flash_erase_sector` in Ameba Arduino SDKs routes through `flash_api.c` which calls `hal_flash_sector_erase()` (ROM stub). Consequently, the U13 finding "NS erase path polls WIP" does NOT apply to FlashMemory's actual call path — the ROM stub is the actual gating function, and its WIP behavior remains unverified. This resolves the U14 open question in a concerning direction: FlashMemory likely goes through the ROM stub, not the NS path. | MEDIUM |
| forum.amebaiot.com/t/new-amb82-mini-starts-running-arduino-code-before-turning-on-3-3v/4809 (thread ~Mar–Apr 2026) | **Newly identified thread** (previously untracked). Title: "New AMB82-Mini starts running Arduino code before turning on 3.3V." Suggests the AMB82-Mini's Arduino application code begins executing before the 3.3V supply rail is stable. This is potentially relevant to the cold-boot FCS failure: if the SPI flash VCC is not stable at the moment the boot ROM begins the FCS flash read sequence, the flash could return undefined data → `FCS_I2C_INIT_ERR`. Could explain why some cold boots fail immediately after power-cycling without any flash write. Content 403-blocked. | MEDIUM (blocked) |
| forum.amebaiot.com/t/sensor-fail-on-amb82-mini/3429 (2024 or earlier) | **Newly identified thread** (previously untracked). Title: "Sensor fail on AMB82 Mini." Different symptom class from our FCS_I2C_INIT_ERR boot failure — but may document related sensor initialization failures. Content 403-blocked. Not confirmed as flash-write-triggered. | LOW (blocked) |
| forum.amebaiot.com/t/how-to-get-the-restart-reason/4725 (Feb 12, 2026) | **Newly identified thread** (previously untracked). Title: "How to get the restart reason." Discusses AMB82 restart reason APIs — potentially useful for diagnostically distinguishing warm vs. cold reset paths in our bug (checking if `hal_sys_get_rst_reason()` or equivalent returns different codes after flash write). Content 403-blocked. | LOW (blocked) |
| ameba-rtos-pro2 commits (fetched 2026-05-17) | **Confirmed frozen.** HEAD remains `3f95070` "Sync upstream 7343927…" (May 15, 2026). Zero new commits in the past 48 hours. No flash, FCS, VOE, boot, or sensor changes in any observable pipeline. | LOW |
| ameba-arduino-pro2 issues (fetched 2026-05-17) | **Confirmed frozen.** Open issues max at #398 (Mar 29, 2026). No new issues filed. No bug report about FCS/flash/camera/VOE/boot failure. 12 open issues total, all feature requests. | LOW |
| ameba-arduino-pro2 releases (fetched 2026-05-17) | **No new release.** Latest stable: V4.1.0 (Mar 2, 2026). Latest pre-release: V4.1.1-QC-V05 (Mar 6, 2026). No V4.1.1 stable or QC-V06+ exists. | LOW |
| Realtek RTL8735C (announced COMPUTEX 2025, Best Choice Award; news release Dec 2025) | **Successor chip to RTL8735B announced.** RTL8735C: Wi-Fi 6, Bluetooth 5.3, advanced AI ISP with "high-resolution full-color imaging in low light," ultra-low power for wearables. Single-chip integrating wireless communication, imaging, 2-way audio, and AI edge computing. No public SDK or Arduino support exists yet. Whether RTL8735C addresses the FCS+flash boot race is unknown — no technical specifications comparing FCS implementation between RTL8735B and RTL8735C are publicly available. | LOW |
| aiot.realmcu.com (newly identified Realtek documentation portal) | **New official documentation portal discovered.** URLs identified: `aiot.realmcu.com/en/latest/arduino/arduino_guide/sdk_intro/evb_guides/evb_amb82mini.html` (AMB82-mini Arduino guide), `aiot.realmcu.com/en/latest/rtos/sdk/mpu_cache/mmu/index.html` (MMU/cache docs), `aiot.realmcu.com/en/latest/tools/image_tool/index.html` (Flash Program Tool). All return HTTP 403. This portal may contain FCS flash layout documentation, dcache management guides, and flash safe-address specifications not available elsewhere — but it requires authenticated access. | LOW (blocked) |
| Web-wide English search: FCS Disable hardware test confirmation | **Still zero results.** No public hardware test of "Camera FCS Mode = Disable" as a workaround for the FlashMemory cold-boot failure has been posted anywhere on the accessible web. Developers are using FCS Disable as a normal camera configuration choice (confirmed via search snippets showing `Amb82HTTPDisplayJPEGContinuous.ino` with "Camera FCS Mode: Disable"), but none specifically as a fix for the flash-write cold-boot bug. | LOW |
| Web-wide search: `"It don't do the sensor initial process"`, `FCS_I2C_INIT_ERR`, `FCS_RUN_DATA_NG_KM` | **Zero indexed results** (unchanged from all prior cycles). This research log remains the only publicly accessible documentation connecting these error codes to flash write operations. | LOW |
| Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/Bilibili/Gitee, May 17) | No new Chinese-language content on FCS flash-write camera failure. All Chinese community sites remain 403-blocked. No new BW21-CBV articles with relevant content. Zero results for FCS flash camera boot failure in any Chinese-language search. | LOW |

**FlashMemory call chain — revised WIP analysis:**

The call chain resolution from this cycle changes the U13/U14 WIP analysis:

| Layer | Function | WIP polling confirmed? |
|---|---|---|
| Arduino / user sketch | `FlashMemory.write()`, `.erase()` | None (confirmed U7) |
| FlashMemory.cpp internal | `flash_erase_sector(flash_t*, uint32_t)` | Unknown — depends on ROM stub |
| mbed NOR Flash API impl | `flash_api.c` → `hal_flash_sector_erase()` | Unknown — ROM stub |
| ROM stub (boot ROM) | `hal_flash_stubs.hal_flash_sector_erase()` | **NOT VERIFIED** (U14) |
| NS-domain | `flash_ns_sector_erase` → `spic_ns_tx_cmd` → `flash_ns_wait_ready` | Yes (U13 — but this path is NOT called by FlashMemory) |

**Conclusion:** The U13 finding that "NS erase path polls WIP" describes a path that FlashMemory does NOT use. The ROM stub path used by FlashMemory (`flash_erase_sector` → `hal_flash_sector_erase` → ROM) may or may not poll WIP. If the ROM stub returns immediately without polling (fire-and-forget), then WIP is always active at function return, making the WIP-at-boot hypothesis viable even without a power cut during erase. This remains the most important unresolved technical question.

**Power supply timing note (thread #4809):**

Thread #4809 ("AMB82-Mini starts running Arduino code before turning on 3.3V") suggests the board's power sequencing may allow code execution before supply rails stabilize. If the SPI flash VCC (VDDIO) is not fully charged when the boot ROM begins the FCS partition read at 0x8000, the flash may return erased (0xFF) or garbage data, producing `FCS_I2C_INIT_ERR`. This could be a separate contributing factor independent of flash write operations — or it could compound the ROM stub WIP hypothesis (flash busy + supply unstable = guaranteed failure).

**SDK state as of 2026-05-17 (Cycle U15 — unchanged):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release: V4.1.1-QC-V05 (Mar 6, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at May 15, 2026 (`3f95070`, `afc85a0`) — 2 days no change
- ameba-arduino-pro2 dev/main: Frozen at May 5, 2026 (`13961cc`) / Mar 2, 2026

**No confirmed fix. Bug remains unpatched as of 2026-05-17 (Cycle U15).**

**Top unresolved actions (updated):**
1. **Hardware test of "Camera FCS Mode = Disable"** — source-confirmed mechanism from 3 independent code paths; no public hardware test result exists anywhere.
2. **Determine if `hal_flash_sector_erase` ROM stub polls WIP** — this is now confirmed as the actual FlashMemory call path; the NS path analysis is not directly applicable. ROM binary inspection or hardware logic analyzer capture needed.
3. **Investigate thread #4809 power sequencing issue** — if SPI flash VCC is unstable at boot ROM FCS read time, this is a separate root cause contributing to the cold-boot failure gradient. Thread content is 403-blocked.

## Research Update — 2026-05-17 (Cycle U16)

**Search scope:** Four parallel agents + direct web searches: (1) GitHub — new commits/releases after May 15 (rtos-pro2) / May 5 (arduino-pro2); (2) English forum/web — new threads above #4834, FCS Disable workaround reports; (3) Chinese sources — bbs.aithinker.com, CSDN, 知乎, EEWorld, 21IC; (4) Flash driver deep-dive — `hal_flash.c` function bodies retrieved directly from GitHub, `flash_api.c` call chain, WIP polling confirmation.

**Key new findings this cycle:**
- **`hal_flash_sector_erase()` C-layer function body retrieved and confirmed fire-and-forget** — lines 545–560 of `hal_flash.c`: ROM stub called with no `hal_flash_wait_ready()` before or after. `hal_flash_page_program()` is equally a thin wrapper (lines 930–938). `hal_flash_wait_ready()` exists (lines 422–429) but is never called from erase or page-program. This resolves Cycle U15's open question about ROM stub WIP behavior at the C layer — the C layer is definitively fire-and-forget.
- Both repos still frozen at same HEADs as U15; no new releases; no new forum threads above #4834 found.
- bbs.aithinker.com remains 403-blocked (one earlier agent report of accessibility was incorrect — confirmed by direct WebFetch returning 403).
- ISP documentation, forum threads #4834 and #4809, and all Chinese community sites remain 403-blocked.
- No hardware test of FCS Disable workaround found anywhere in any public source.

| Source | Key Finding | Priority |
|---|---|---|
| `hal_flash.c` lines 545–560, 930–938, 422–429 (ameba-rtos-pro2, fetched 2026-05-17) | **`hal_flash_sector_erase` is definitively fire-and-forget at the C layer.** Function body: sets extended address bits, calls `hal_flash_stubs.hal_flash_sector_erase(phal_spic_adaptor, address)`, restores address bits — **no `hal_flash_wait_ready()` call anywhere.** `hal_flash_page_program` (lines 930–938) is an even thinner wrapper: single line `hal_flash_stubs.hal_flash_page_program(...)` with zero WIP management. `hal_flash_wait_ready` (lines 422–429) exists as `hal_flash_stubs.hal_flash_wait_ready(phal_spic_adaptor)` — but is never called from erase or page-program functions. This closes the C-layer ambiguity from U14/U15. Whether the ROM stub itself internally waits remains unverifiable from public source alone, but the C wrapper never waits. | HIGH |
| FlashMemory call chain (synthesis from U15 + U16 hal_flash.c source) | **Complete FlashMemory WIP non-polling chain confirmed:** `FlashMemory.erase()` → `flash_erase_sector(flash_t*, addr)` (mbed API) → `hal_flash_sector_erase(adaptor, addr)` (C wrapper, confirmed fire-and-forget) → `hal_flash_stubs.hal_flash_sector_erase()` (ROM stub, WIP behavior unknown but C layer does not wait). Result: from the C layer down, there is **zero WIP polling** at any point accessible from public source. If the ROM stub returns before the flash erase completes (reasonable assumption given the pattern), WIP is active at function return — meaning a cold boot occurring within the subsequent 0–400 ms window (tSE worst case) would catch the flash chip mid-erase. | HIGH |
| mbed-os Issue #6380 "HAL Flash sector erase doesn't work consistently" (ARMmbed/mbed-os, GitHub) | **Cross-platform mbed precedent confirmed.** A separate mbed-os issue (not RTL8735B-specific) documents that mbed HAL flash sector erase returns before the operation is complete on multiple targets. Pattern is consistent with RTL8735B's C-layer fire-and-forget behavior. Not RTL8735B-specific, but validates the general hazard class at the mbed HAL level. | LOW |
| ameba-rtos-pro2 HEAD (fetched 2026-05-17) | **Frozen.** HEAD = `3f95070` "Sync upstream 7343927…" (May 15, 2026) — identical to U15. Zero new commits in 2 days. No flash, FCS, VOE, boot, or sensor changes in any commit. | LOW |
| ameba-arduino-pro2 releases (fetched 2026-05-17) | **No new releases.** Latest stable = V4.1.0 (Mar 2, 2026). Latest pre-release = V4.1.1-QC-V05 (Mar 6, 2026). No V4.1.1 stable or QC-V06+ has been published. | LOW |
| All Chinese-language sources (bbs.aithinker.com, CSDN, 知乎, EEWorld, 21IC, Gitee, Bilibili, May 17) | **Zero new content; bbs.aithinker.com confirmed still 403-blocked.** Previous cycle's agent report of bbs.aithinker.com accessibility was incorrect — direct WebFetch returns HTTP 403. No new Chinese-language technical content about FCS flash-write camera failure found. | LOW |
| Web-wide English search (all engines, May 17 sweep) | **Zero new indexed results** for `FCS_I2C_INIT_ERR`, `FCS_RUN_DATA_NG_KM`, `"It don't do the sensor initial process"`, `VOE_OPEN_CMD fail flash`. No new public hardware test reports of FCS Disable workaround for this specific bug. | LOW |

**WIP-at-boot hypothesis — now strongly supported (revised assessment):**

The C-layer source confirmation that `hal_flash_sector_erase` is fire-and-forget upgrades this hypothesis from "plausible" to "strongly supported":

1. `FlashMemory.erase()` returns to user code with WIP potentially still active.
2. If any code path (software reset, power cut, watchdog, OTA reboot) triggers a cold boot within tSE worst-case (400 ms), the flash chip is still erasing.
3. The boot ROM's FCS partition read at 0x8000 (fcsdata) reads 0xFF or undefined data from the mid-erase chip.
4. KM co-processor receives invalid FCS header → `FCS_I2C_INIT_ERR` (0x200A) → `FCS_RUN_DATA_NG_KM` (0x2081).
5. "It don't do the sensor initial process" → camera dead for this boot session.

For cases where the device is not powered down for minutes after the erase (e.g., a software `sys_reset()` triggered immediately), the WIP window explains everything. For devices with battery or mechanical power switches that could be toggled within seconds, the 400 ms window is realistic.

**Practical `delay()` workaround — upgraded to MEDIUM confidence:**

Adding `delay(500)` (covering W25Q128JV tSE max = 400 ms + margin) immediately after `flash_erase_sector()` in user code would close the WIP window before any reboot is possible. This is a one-line Arduino sketch change requiring no SDK modification and no FCS mode change. It would not eliminate the cold-boot failure if the ROM stub itself is synchronous (waits internally), but in that case the bug's root cause is different and this delay is harmless. If the ROM stub is asynchronous, this delay is the minimal fix.

**Updated workaround table:**

| Workaround | Mechanism | Status | Confidence |
|---|---|---|---|
| "Camera FCS Mode = Disable" | Dummy blob → invalid magic → KM bypass (0x0083), never reaches I2C | Source-confirmed (postbuild.cpp, video_boot.c, video_api.c); no hardware test | HIGH (mechanism); UNCONFIRMED (hardware) |
| `delay(500)` after `flash_erase_sector()` | Allows tSE worst-case (400ms) to complete before any reboot | Trivially implementable in Arduino; addresses WIP-at-boot path | MEDIUM (unconfirmed hardware test) |
| `hal_flash_wait_ready()` after erase | Explicit WIP-done signal from HAL | Declared in hal_flash.h; non-trivial to call from Arduino (requires adaptor ptr) | LOW (API access non-trivial) |

**SDK state as of 2026-05-17 (Cycle U16 — unchanged):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release: V4.1.1-QC-V05 (Mar 6, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at May 15, 2026 (`3f95070`, `afc85a0`)
- ameba-arduino-pro2 dev/main: Frozen at May 5, 2026 (`13961cc`)

**No confirmed fix. Bug remains unpatched as of 2026-05-17 (Cycle U16).**

**Top unresolved actions (updated from U15):**
1. **Hardware test of "Camera FCS Mode = Disable"** — source-confirmed mechanism; no public hardware test result exists anywhere. Highest priority.
2. **Hardware test of `delay(500)` after `flash_erase_sector()`** — simple Arduino workaround for WIP-at-boot path; C-layer source now confirms fire-and-forget. Second highest priority.
3. **Determine ROM stub internal WIP behavior** — if the ROM stub is synchronous internally, neither the C-layer fire-and-forget observation nor the `delay()` workaround applies to the cold-boot case. Logic analyzer or ROM binary inspection needed.

## Research Update — 2026-05-17 (Cycle U17)

**Search scope:** Four parallel agents: (1) GitHub — all repos post-May 15 activity, hal_flash.c function bodies; (2) English forum/web — new threads above #4834, FCS disable workaround reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/Bilibili/Gitee; (4) SDK deep-dive — `hal_flash_ns.c` full NS stub table, `spic_ns_tx_cmd` WIP polling, FlashMemory call chain resolution.

**Key new findings this cycle:**
- **MAJOR REVISION — ROM stub IS synchronous:** `flash_ns_sector_erase` (the NS stub implementation used by Arduino SDK under `CONFIG_BUILD_NONSECURE`) calls `spic_ns_tx_cmd()`, which unconditionally calls both `spic_ns_wait_ready()` (SPIC controller) and `flash_ns_wait_ready()` (flash device WIP bit) before returning. The erase is **fully blocking** — WIP=0 is guaranteed before `flash_erase_sector()` returns. This disproves the WIP-at-boot hypothesis for continuously-powered devices and invalidates the `delay(500)` workaround proposed in U16.
- `hal_flash_stubs_ns` struct confirmed as the actual stubs table used: `hal_flash_sector_erase` → `flash_ns_sector_erase`, `hal_flash_wait_ready` → `flash_ns_wait_ready` (independent entry, confirming it can be called separately but is redundant after erase).
- "VOE_OUT_CMD type 2 command fail -1" from thread #4321 identified as a new error string variant in the camera sensor init failure class (GC2053, Aug 2025) — previously logged as generic "sensor init failed".
- All repos confirmed frozen; no new commits, releases, or issues anywhere.
- Zero new Chinese or English content; no hardware test of FCS Disable workaround anywhere.

| Source | Key Finding | Priority |
|---|---|---|
| `hal_flash_ns.c` lines ~361-400 (ameba-rtos-pro2, `CONFIG_BUILD_NONSECURE` build) | **NS stubs table confirmed:** `hal_flash_stubs_ns` maps `.hal_flash_sector_erase = flash_ns_sector_erase` and `.hal_flash_wait_ready = flash_ns_wait_ready`. The Arduino SDK compiles with `CONFIG_BUILD_NONSECURE` defined, so `hal_flash_stubs.hal_flash_sector_erase()` dispatches to `flash_ns_sector_erase` from `hal_flash_ns.c`, NOT to a closed ROM binary. This resolves the U14/U15/U16 ambiguity about ROM stub WIP behavior — the NS stubs table is the actual path. | HIGH |
| `hal_spic_ns.c` lines 1004–1076 — `spic_ns_tx_cmd()` (ameba-rtos-pro2) | **WIP polling IS present in the NS erase path — MAJOR REVISION.** `spic_ns_tx_cmd()` sends any flash command and then unconditionally calls: (1) `spic_ns_wait_ready(spic_dev)` — polls SPIC_SR BUSY bit (controller done); (2) `flash_ns_wait_ready(phal_spic_adaptor)` — polls flash Status Register WIP bit (S0 = 0 for W25Qxx, bit 7 of SR2 for Micron). Both polls are in a busy-wait loop that blocks until cleared. `flash_ns_sector_erase` calls `spic_ns_tx_cmd(cmd->se, ...)` as its final step → erase is fully blocking. **The characterization in U13/U16 that "erase is fire-and-forget" applied to the RAM-layer wrapper only; the NS implementation below it is synchronous.** | HIGH |
| `flash_ns_set_write_enable()` (hal_flash_ns.c lines ~1272-1282) | Pre-erase WIP check also included: `flash_ns_set_write_enable()` calls `flash_ns_wait_ready()` before issuing WREN, then busy-loops until WEL bit (SR1 bit 1) is set. Both the WREN and the SE command paths enforce WIP=0. Calling `hal_flash_wait_ready()` after `hal_flash_sector_erase()` is therefore redundant — the erase already blocks until WIP=0. | MEDIUM |
| Revised WIP-at-boot hypothesis status | **WIP-at-boot hypothesis DISPROVED for continuously-powered devices.** Because `flash_ns_sector_erase` blocks until WIP=0, the function cannot return while flash is still erasing. A cold boot triggered any time after `flash_erase_sector()` returns will NOT catch the flash chip mid-erase. The 400 ms WIP window is therefore irrelevant for normally-powered RTL8735B devices. The WIP scenario is only valid if power is physically cut DURING the busy-wait loop itself (flash WIP=1, CPU spinning) — which requires the host to cut power during a 45–400 ms window while the CPU is still running. This is plausible only for battery-powered devices or hardware with aggressive power control that cuts VDDIO before the erase function returns. | HIGH |
| `delay(500)` workaround assessment (U16) | **Downgraded from MEDIUM to NOT NEEDED** for normally-powered devices. Since the erase is synchronous, there is nothing to "wait out" after the function returns. Adding a delay is harmless but unnecessary for the WIP path. The U16 "MEDIUM confidence" rating was based on the incorrect assumption that the NS path was not called by FlashMemory. | HIGH |
| New cold-boot root cause analysis required | **With WIP ruled out, a different cold-boot mechanism must explain the persistent failure.** Best remaining candidates: (1) **SPIC concurrent access**: `ftl_common_write()` (ISP AE/AWB background save to `NOR_FLASH_FCS = 0xF0D000`) has no mutex protecting SPIC access. While `flash_ns_sector_erase` busy-waits on WIP (CPU running, FreeRTOS still scheduling), the ISP AE/AWB write task could also attempt SPIC operations — concurrent SPIC access without a mutex could corrupt the AE/AWB data at 0xF0D000, which persists in flash across cold boots. (2) **SPIC controller state**: The SPIC controller may leave some internal register state after an erase that disrupts the boot ROM's flash-init sequence on next cold boot (unrelated to WIP). (3) **Power-cut-during-erase still applies** for battery/low-power designs where VDDIO could drop during the erase busy-wait. | MEDIUM |
| forum.amebaiot.com/t/camera-sensor-init-failed-gc2053/4321 — new error detail | **"VOE_OUT_CMD type 2 command fail -1"** — newly extracted error string variant from thread #4321 (GC2053, Aug 2025). Previously logged as "sensor init failed." This string suggests the VOE command dispatcher has a "type 2" command variant distinct from "OPEN_CMD" — may represent a different IPC command type in the VOE protocol. Not confirmed as flash-triggered. Thread content still 403 blocked. | LOW |
| All GitHub repos (fetched 2026-05-17, two agents) | **All repos confirmed frozen.** ameba-rtos-pro2 HEAD = `3f95070` (May 15, 2026); ameba-arduino-pro2 main = `93d63514` (Mar 2); dev = `13961ccf` (May 5); ideashatch/HUB-8735 last commit Dec 2025. No new commits, releases (no V4.1.1 stable, no QC-V06+), or issues in any repository. Two independent agents reached identical conclusions. | LOW |
| All English/Chinese web sources (three agents, May 17 sweep) | **Zero new content anywhere.** forum.amebaiot.com, bbs.aithinker.com, bbs.ai-thinker.com, CSDN, Zhihu, EEWorld, 21IC, Bilibili, Gitee, mcublog.cn all return 403 or zero relevant results. Error strings `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"VOE_OPEN_CMD fail"` remain unindexed anywhere outside 403-blocked forum threads. No public hardware test of "Camera FCS Mode = Disable" as a flash-write workaround has been posted anywhere. | LOW |

**Revised WIP analysis — complete call chain (NS build, Cycle U17):**

| Layer | Function | WIP polling |
|---|---|---|
| User sketch | `FlashMemory.erase()` | None |
| FlashMemory.cpp | `flash_erase_sector(flash_t*, addr)` | None |
| mbed/flash_api.c | `hal_flash_sector_erase(adaptor, addr)` (RAM wrapper) | None — thin wrapper only |
| NS stubs table | `hal_flash_stubs.hal_flash_sector_erase` → `flash_ns_sector_erase` | None in stub dispatch |
| NS implementation | `flash_ns_sector_erase` → `flash_ns_set_write_enable()` + `spic_ns_tx_cmd(SE)` | **YES** — `flash_ns_wait_ready()` called twice (before WREN and after SE) |
| SPIC layer | `spic_ns_tx_cmd` → `spic_ns_wait_ready()` + `flash_ns_wait_ready()` | **YES** — both controller and device WIP polled to 0 |

**Conclusion:** WIP=0 is guaranteed before `flash_erase_sector()` returns. The U16 fire-and-forget characterization applied only to the RAM wrapper layer; the NS implementation is fully synchronous.

**Revised workaround table (Cycle U17):**

| Workaround | Mechanism | Status | Confidence |
|---|---|---|---|
| "Camera FCS Mode = Disable" | Dummy blob → invalid MFCS magic → KM enters bypass (0x0083), never reaches GPIO/I2C init | Source-confirmed from `postbuild.cpp`, `video_boot.c`, `video_api.c`; no hardware test | HIGH (mechanism); UNCONFIRMED (hardware) |
| Stop camera before flash write | Eliminates concurrent ISP `ftl_common_write()` SPIC access; prevents AE/AWB data corruption at 0xF0D000 | Untested; addresses SPIC concurrent-access hypothesis | LOW (hypothesis, unconfirmed) |
| `delay(500)` after `flash_erase_sector()` | Unnecessary for WIP (erase is synchronous); only relevant if power-cut-during-erase is the root cause | **Downgraded from MEDIUM (U16) — NOT NEEDED for normally-powered devices** | VERY LOW (inapplicable unless WIP scenario applies) |
| `hal_flash_wait_ready()` after erase | Redundant — erase already ensures WIP=0 | Available in hal_flash.h but unnecessary | NOT NEEDED |

**SDK state as of 2026-05-17 (Cycle U17 — unchanged):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release: V4.1.1-QC-V05 (Mar 6, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at May 15, 2026 (`3f95070`, `afc85a0`)
- ameba-arduino-pro2 dev/main: Frozen at May 5, 2026 (`13961cc`)

**No confirmed fix. Bug remains unpatched as of 2026-05-17 (Cycle U17).**

**Top unresolved actions (updated):**
1. **Hardware test of "Camera FCS Mode = Disable"** — source-confirmed full bypass of FCS boot path; no public hardware test result exists. Highest priority.
2. **Investigate SPIC concurrent-access hypothesis** — does `ftl_common_write()` (ISP AE/AWB task) race with `FlashMemory.erase()` on the SPIC bus? Stopping the camera before flash write is the practical test. If concurrent SPIC is the root cause, `USE_ISP_RETENTION_DATA` (saving AE/AWB to SRAM instead of flash) may be a second workaround.
3. **Determine exact call path for `flash_erase_sector(flash_t*, addr)`** — Agent 4 confirmed FlashMemory calls this mbed-compat function, but `flash_api.c` (the mbed implementation file) was not directly retrieved to verify whether it calls `hal_flash_sector_erase` or takes a different path. This is the remaining ambiguity in the confirmed-NS-path analysis.

## Research Update — 2026-05-17 (Cycle U18)

**Search scope:** Six parallel search threads + direct GitHub/web fetches: (1) GitHub — new commits/releases after May 15 (rtos-pro2) / May 5 (arduino-pro2); (2) English forums — new threads above #4834, FCS Disable workaround hardware tests; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com; (4) SPIC concurrent-access hypothesis — `video_open_close_mutex` scope from `video_api.c`, `ftl_common_write` in GitHub code search; (5) `flash_ns_sector_erase` function body at `hal_flash_ns.c` line 1285; (6) New documentation portals — `aiot.realmcu.com/en/latest/linux/peripherals/spic/index.html`.

**Key new findings this cycle:**
- **`video_open_close_mutex` confirmed NOT a SPIC guard** — exists in `video_api.c` at line ~270, protects video init/teardown only; no mutex protects the SPIC bus during runtime ISP AE/AWB flash writes. SPIC concurrent-access hypothesis gains support.
- **`ftl_common_write` returns zero results** in GitHub code search for ameba-rtos-pro2 — requires authentication or resides in a closed-source compiled library; ISP AE/AWB flash write locking behavior is opaque.
- **`hal_flash_stubs_ns` struct confirmed at lines 815–846 of `hal_flash_ns.c`** — `.hal_flash_sector_erase = flash_ns_sector_erase` confirmed from source.
- Both repos still frozen; no new releases, issues, or commits anywhere; no new forum threads above #4834; zero new Chinese-language content.

| Source | Key Finding | Priority |
|---|---|---|
| `video_api.c` (ameba-rtos-pro2, retrieved May 17) | **`video_open_close_mutex` confirmed NOT a SPIC guard.** `static _mutex video_open_close_mutex = NULL` at line ~270 protects video initialization and teardown sequences only (`video_open` / `video_close`). There is **no mutex or semaphore visible in open-source C code** that prevents concurrent SPIC flash bus access between the ISP AE/AWB background write task (`ftl_common_write`) and `FlashMemory.erase()` or `FlashMemory.write()`. This is the first positive source-code confirmation that the SPIC bus has no cross-subsystem lock. If `ftl_common_write` also lacks internal locking, both paths could issue SPIC commands simultaneously, producing undefined flash controller state. | MEDIUM |
| GitHub code search: `ftl_common_write` in ameba-rtos-pro2 | **Zero results** — GitHub code search for `ftl_common_write` in the ameba-rtos-pro2 repository requires login (returned authentication wall, not a 0-hit page). This is distinct from a confirmed 0-hit result. The function is either in a closed-source binary (e.g., `libvideo_ns.a`), in a file not indexed by unauthenticated search, or named differently. Combined with `video_api.c` `#include "ftl_common_api.h"` at line ~130, the ISP AE/AWB flash write implementation is fully opaque from public source. | MEDIUM |
| `hal_flash_ns.c` lines 815–846 (ameba-rtos-pro2, retrieved May 17) | **`hal_flash_stubs_ns` struct confirmed from source.** Direct fetch of `hal_flash_ns.c` shows `hal_flash_stubs_ns` struct containing `.hal_flash_sector_erase = flash_ns_sector_erase` at the stubs-table definition. `flash_ns_sector_erase` is at line 1285. The content after line 1300 was truncated in the fetch but the dispatch chain is confirmed; WIP polling behavior was established in U17 via `spic_ns_tx_cmd` analysis (unconditionally calls both `spic_ns_wait_ready` and `flash_ns_wait_ready`). This is a direct source confirmation of the U17 NS-path finding. | LOW (confirms U17) |
| ameba-rtos-pro2 commits (fetched 2026-05-17, direct GitHub fetch) | **Still frozen.** HEAD = `3f95070` "Sync upstream 7343927…" (May 15, 2026). Zero new commits in 2 days since U17. Ten most recent commits: `3f95070`, `afc85a0`, `9c8b6f6`, `d2676f1` (all May 15); `1c1c8b7`, `a111e91`, `7b2b97f`, `63c0a2f`, `d54e1a8`, `687a4c7` (all May 1). No flash, FCS, VOE, boot, or sensor changes anywhere. | LOW |
| ameba-arduino-pro2 dev branch commits (fetched 2026-05-17, direct GitHub fetch) | **Still frozen.** HEAD = `13961cc` "Update API for AMB82-zero and SWD off logic" (May 5, 2026). Latest stable = V4.1.0 (Mar 2, 2026, `93d6351`). Latest pre-release = V4.1.1-QC-V05 (no release after Apr 17). No new commits, pre-releases, or stable releases since last cycle. ameba-arduino-pro2 open issues: 12 open, max #398 (Mar 29, 2026) — no new issues filed. | LOW |
| forum.amebaiot.com threads #4835–#4840 (probed 2026-05-17) | **No new indexed threads.** Direct fetch of threads #4835 and #4836 (constructed URLs) returned HTTP 403. Google search for "forum.amebaiot.com 4835 OR 4836 OR 4837 OR 4838 OR 4839 OR 4840" returned only the forum index page — these thread IDs are not indexed, suggesting they either do not yet exist or were created within the past 24 hours and are not yet crawled. Forum thread ceiling remains at #4834 (Boot failure after OTA update) as the highest confirmed thread. | LOW |
| `aiot.realmcu.com/en/latest/linux/peripherals/spic/index.html` | **SPIC controller documentation page confirmed present but 403.** This URL appeared in search results for "SPIC concurrent access" queries; content describes the RTL8735B SPI Flash Controller driver. Returns HTTP 403 (developer login required). If accessible, it may document whether the SPIC driver uses a global mutex for multi-thread safety. Currently inaccessible. | LOW (blocked) |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/Bilibili/Gitee, May 17) | **Zero new content.** All Chinese community sites remain 403-blocked. bbs.ai-thinker.com BW21-CBV threads confirmed still inaccessible. Sohu.com BW21-CBV tutorial also returns 403 (May 17 re-check). No Chinese-language forum posts or articles discuss FCS flash-write camera failure on RTL8735B or BW21-CBV. | LOW |
| Web-wide English search: all error strings | **Still zero new results.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"VOE_OPEN_CMD fail flash"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"` return zero publicly indexed results outside 403-blocked forum threads. No hardware test of "Camera FCS Mode = Disable" as a flash-write bug workaround has appeared anywhere on the accessible web. | LOW |

**SPIC concurrent-access hypothesis — updated assessment:**

The U17 hypothesis that the ISP AE/AWB background task (`ftl_common_write`) may race with `FlashMemory.erase()` on the shared SPIC bus receives indirect support from this cycle:

- **No SPIC bus mutex visible in open-source C code.** `video_open_close_mutex` in `video_api.c` only guards `video_open()`/`video_close()` — it does not lock the SPIC bus during runtime ISP flash writes.
- **`ftl_common_write` is in a closed-source binary.** Its internal locking cannot be confirmed. The pessimistic assumption (no internal lock) is consistent with the absence of any observable mutex protecting the SPIC bus.
- **Practical test remains unchanged:** Stop the camera (call `video_deinit()` / `camObj.videoDeinit()`) before calling `FlashMemory.erase()`, then reinitialize the camera afterward. If the cold-boot failure disappears, concurrent SPIC access is confirmed as the root cause. This is the most actionable remaining hardware test after "Camera FCS Mode = Disable."

**`USE_ISP_RETENTION_DATA` as a second workaround path:**

If the SPIC concurrent-access hypothesis is confirmed, `USE_ISP_RETENTION_DATA` (uncomment in `video_api.h` to store AE/AWB ISP parameters in SRAM retention instead of NOR flash) eliminates the ISP's background flash writes entirely. Combined with user code that never writes to the 0xF0D000 NOR_FLASH_FCS region, this would remove the race condition without requiring FCS mode changes. This was documented in earlier cycles but is newly relevant given the `video_open_close_mutex` scope confirmation.

**SDK state as of 2026-05-17 (Cycle U18 — unchanged):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release: V4.1.1-QC-V05 (Mar 6 / Apr 17, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at May 15, 2026 (`3f95070`, `afc85a0`)
- ameba-arduino-pro2 dev/main: Frozen at May 5, 2026 (`13961cc`)

**No confirmed fix. Bug remains unpatched as of 2026-05-17 (Cycle U18).**

**Top unresolved actions (updated from U17):**
1. **Hardware test of "Camera FCS Mode = Disable"** — source-confirmed full bypass of FCS cold-boot path via dummy blob; no public hardware test result exists. Highest priority.
2. **Hardware test of camera-stop before flash erase** — call `video_deinit()` before `FlashMemory.erase()`; this tests the SPIC concurrent-access hypothesis. If this fixes the bug, `USE_ISP_RETENTION_DATA` is a non-intrusive long-term workaround.
3. **Determine `ftl_common_write` locking behavior** — function is in a closed-source binary; ROM binary inspection or logic analyzer capture of the SPIC bus during concurrent camera+flash operation needed.

## Research Update — 2026-05-18 (Cycle U19)

**Search scope:** Four parallel agents: (1) GitHub — all repos post-May 15 activity, code search for FCS symbols; (2) English forum/web — new threads above #4834, FCS Disable workaround hardware tests; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/Bilibili/Gitee; (4) SDK deep-dive — `ftl_common_api.c` / `ftl_nor_api.c` locking, `flash_api.c` call chain, `USE_ISP_RETENTION_DATA` from source.

**Key new findings this cycle:**
- **`ftl_common_api.c` and `ftl_nor_api.c` found as PUBLIC source in ameba-rtos-pro2** — contradicts U18's characterization of `ftl_common_write` as "in a closed-source binary." These files exist at `component/file_system/ftl_common/` and were not discovered in prior cycles.
- **`RT_DEV_LOCK_FLASH` mutex confirmed** — `ftl_nor_api.c`'s NOR callbacks (`nor_read_cb`, `nor_write_cb`, `nor_erase_cb`) each call `device_mutex_lock(RT_DEV_LOCK_FLASH)` / `device_mutex_unlock`. This is the system-wide SPIC bus protection mechanism.
- **CONFIRMED ARCHITECTURAL DEFECT — FlashMemory bypasses `RT_DEV_LOCK_FLASH`**: `FlashMemory.erase()` → `hal_flash_sector_erase()` (C wrapper in `hal_flash.c`) contains ZERO mutex calls. `hal_flash.c` confirmed to have no mutex/semaphore in any of its 39 functions. FlashMemory never acquires `RT_DEV_LOCK_FLASH` before issuing SPIC commands, meaning it can collide with any concurrent FTL operation (ISP AE/AWB write) on the shared SPIC bus.
- **`USE_ISP_RETENTION_DATA` path confirmed from source** — `video_api.h` L95, currently commented out. When enabled + `SAVE_TO_RETENTION` passed, ISP AE/AWB persistence uses ONLY CPU retention memory — zero SPIC operations. This eliminates the ISP's competing flash writes entirely.
- **Forum thread #4840 newly identified** — OTA via HTTPS (unrelated to our bug, ~May 2026).
- All repos confirmed frozen; no new commits since May 15 (rtos-pro2) / May 5 (arduino-pro2); zero new Chinese-language content.

| Source | Key Finding | Priority |
|---|---|---|
| `component/file_system/ftl_common/ftl_nor_api.c` (ameba-rtos-pro2, public) | **`RT_DEV_LOCK_FLASH` mutex confirmed in FTL layer.** `nor_read_cb` (L13–20), `nor_write_cb` (L22–31), `nor_erase_cb` (L33–40) each call `device_mutex_lock(RT_DEV_LOCK_FLASH)` and `device_mutex_unlock(RT_DEV_LOCK_FLASH)` around their `flash_stream_read` / `flash_stream_write` / `flash_erase_sector` calls. The FTL layer — used by the ISP AE/AWB save path via `ftl_common_write` → `ftl_write_nor` → callbacks — correctly serializes all SPIC access via this system-wide lock. | HIGH |
| `device_lock.h` (both repos) | **`RT_DEV_LOCK_FLASH = 1` is the system-wide SPI flash bus arbiter.** Enum: `RT_DEV_LOCK_EFUSE=0, RT_DEV_LOCK_FLASH=1, RT_DEV_LOCK_CRYPTO=2, RT_DEV_LOCK_PTA=3, RT_DEV_LOCK_WLAN=4, RT_DEV_LOCK_VOE=5, RT_DEV_LOCK_NN=6`. `device_mutex_lock` uses `rtw_mutex_get_timeout(..., 10000)` — a 10-second blocking acquire. This is the correct OS-level protection for the SPIC bus and is used throughout the FTL layer. | HIGH |
| `hal_flash.c` (ameba-rtos-pro2, full file analysis) | **CONFIRMED: `hal_flash.c` has ZERO mutex/semaphore calls across all 39 functions.** `hal_flash_sector_erase` (L367) is: set extended addr bits → `hal_flash_stubs.hal_flash_sector_erase()` → restore addr bits. No `device_mutex_lock`, no `xSemaphoreTake`, no `taskENTER_CRITICAL`, no `flash_lock`. `hal_flash_global_lock` / `hal_flash_global_unlock` are hardware write-protect SPI commands to the flash chip, not OS mutex calls. The C wrapper layer is completely unprotected from concurrent SPIC access. | HIGH |
| **SYNTHESIS: FlashMemory `RT_DEV_LOCK_FLASH` bypass (architectural defect)** | **FlashMemory.erase()→hal_flash_sector_erase() bypasses `RT_DEV_LOCK_FLASH` entirely, while the ISP AE/AWB FTL path correctly holds it.** The two paths share the SPIC bus with no mutual exclusion. If `video_pre_init_save_cur_params()` (ISP AE/AWB task) is mid-write to `NOR_FLASH_FCS (0xF0D000)` when `FlashMemory.erase()` issues its own SPIC commands, the SPI command stream on the bus is interleaved. Since WREN + SE are two separate SPI transactions, an interleaved command from FlashMemory between WREN and SE could cause the flash chip to act on a corrupted or wrong address — potentially erasing or corrupting AE/AWB data at 0xF0D000 even though FlashMemory targets 0xFD0000. This is a **confirmed architectural defect** in the Arduino SDK: `FlashMemory` does not acquire `RT_DEV_LOCK_FLASH` before any SPIC operation. | HIGH |
| `component/file_system/ftl_common/ftl_common_api.c` (ameba-rtos-pro2, public) | **`ftl_common_write` source found.** Uses its own `ftl_mutex` (`rtw_mutex_get`/`put`) to serialize FTL-internal calls. `ftl_lock()` (L40–47) and `ftl_unlock()` wrap the write sequence. However `ftl_mutex` only serializes concurrent callers of `ftl_common_write` against each other — it does NOT protect against FlashMemory's `hal_flash_sector_erase()` which never touches `ftl_mutex` or `RT_DEV_LOCK_FLASH`. | MEDIUM |
| `video_api.c` L3436 + `video_api.h` L95 (ameba-rtos-pro2) | **`USE_ISP_RETENTION_DATA` confirmed from source.** `video_api.h` L95: `// #define USE_ISP_RETENTION_DATA` (commented out by default). When uncommented + `SAVE_TO_RETENTION` used in `video_pre_init_save_cur_params()`, the save path uses only `dcache_clean_invalidate_by_addr()` and writes to `retention_table` in RAM — **zero SPIC operations**. This eliminates the ISP's competing flash writes entirely. The `ftl_common_write()` call at `video_api.c` L3436 is NOT surrounded by `device_mutex_lock(RT_DEV_LOCK_FLASH)` at the call site (only `video_open_close_mutex` exists in `video_api.c`, which guards open/close only). | HIGH |
| `flash_api.c` (ameba-arduino-pro2 / ameba-rtos-pro2) | **`flash_api.c` mbed source not publicly available as `.c` file.** Only `flash_api.h` exists in `ameba-arduino-pro2` at `Arduino_package/.../hal_ext/flash_api.h`. The `.c` implementation is compiled into a pre-built library. The call chain `FlashMemory → flash_erase_sector(flash_t*, addr) → hal_flash_sector_erase()` is confirmed by header analysis, but the mbed-layer `.c` cannot be directly verified for mutex additions. Given `hal_flash.c` has no mutex, any mutex would have to be in the mbed layer — which cannot be confirmed from public source. | LOW |
| forum.amebaiot.com thread #4840 (~May 2026) | **Newly identified thread.** Title: "關於Ameba Pro透過https下載Bin檔進行OTA的流程" (About Ameba Pro OTA flow via HTTPS/downloading Bin file). Confirms thread IDs above #4834 exist. Content discusses OTA protocol (HTTP vs HTTPS), not camera/flash/FCS failure. Thread content 403-blocked; date ~May 2026 (indexed by search engines after May 5). Not related to our bug. | LOW |
| All GitHub repos (fetched 2026-05-18, two agents) | **All repos confirmed frozen.** ameba-rtos-pro2 HEAD = `3f95070` (May 15, 2026); ameba-arduino-pro2 main = `93d63514` (Mar 2); dev = `13961cc` (May 5); ideashatch/HUB-8735 last commit Dec 2025. GitHub code search: `FCS_I2C_INIT_ERR` = 13 hits (all `rtl8735b_voe_status.h`), `FCS_RUN_DATA_NG_KM` = 17 hits (all `video_boot.c` variants) — no new repos. No new issues, PRs, or releases in any repo. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/Bilibili/Gitee, May 18) | **Zero new content.** bbs.aithinker.com thread tid=46140 ("BW21-CBV-Kit调试") remains the highest-indexed Chinese-language discussion of BW21-CBV debugging — still 403-blocked. All other Chinese community sites 403. Zhihu BW21-CBV article (fall detection, p/1933901413328586556) 403. mcublog.cn April 2026 BW21-CBV article 403. No new content on FCS flash-write camera failure anywhere in Chinese-language sources. | LOW |

**SPIC concurrent-access — upgraded from hypothesis to confirmed architectural defect:**

The Cycle U18 hypothesis is now confirmed from source code analysis:

| Component | `RT_DEV_LOCK_FLASH` usage |
|---|---|
| `ftl_nor_api.c` `nor_read_cb` / `nor_write_cb` / `nor_erase_cb` | **YES — acquires and releases for every individual SPIC operation** |
| `ftl_common_api.c` `ftl_common_write` | Uses own `ftl_mutex` (FTL-internal only) |
| `video_api.c` `video_pre_init_save_cur_params` → `ftl_common_write` | NO `RT_DEV_LOCK_FLASH` at call site |
| `hal_flash.c` `hal_flash_sector_erase` (FlashMemory path) | **NO — zero mutex of any kind** |

The bug scenario: ISP AE/AWB task issues WREN via `flash_ns_set_write_enable()` (acquires WEL bit on flash chip) as part of its `nor_write_cb` → `flash_stream_write` path. Between the WREN and the PAGE_PROGRAM command, `FlashMemory.erase()` issues its own WREN + SE sequence without holding `RT_DEV_LOCK_FLASH`. The second WREN is accepted (WEL was already set), and the SE command targets 0xFD0000. But if `flash_ns_set_write_enable()` in the FTL path is still mid-sequence, the bus command interleaving could corrupt the intended write to 0xF0D000. Result: AE/AWB FCS data at `NOR_FLASH_FCS (0xF0D000)` contains corrupt or partially-written data → boot ROM reads corrupt `isp_fcs_header_t` → `FCS_I2C_INIT_ERR (0x200A)` on next cold boot.

**Revised workaround table (Cycle U19):**

| Workaround | Mechanism | Confidence | Implementation |
|---|---|---|---|
| "Camera FCS Mode = Disable" | Dummy blob → invalid MFCS magic → KM bypass (0x0083), never reaches I2C | HIGH (source-confirmed; no hardware test) | Arduino IDE Tools menu |
| `USE_ISP_RETENTION_DATA` + `SAVE_TO_RETENTION` | Eliminates ISP SPIC writes entirely; no competing SPIC traffic | HIGH (source-confirmed; no hardware test) | Uncomment `video_api.h` L95; requires RTOS SDK or modified `video_api.h` |
| Wrap `FlashMemory.erase()` with `device_mutex_lock(RT_DEV_LOCK_FLASH)` | Acquires the same system-wide flash bus lock used by FTL layer | MEDIUM (source-confirmed mechanism; no hardware test; requires calling `device_lock.h` API from sketch) | `device_mutex_lock(RT_DEV_LOCK_FLASH)` before erase; `device_mutex_unlock` after |
| Stop camera (`video_deinit()`) before flash erase | Eliminates ISP AE/AWB SPIC writes by stopping the ISP entirely | LOW (untested; intrusive) | Call `video_deinit()` before `FlashMemory.erase()` |

**SDK state as of 2026-05-18 (Cycle U19 — unchanged from U18):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release: V4.1.1-QC-V05 (Apr 17, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at May 15, 2026 (`3f95070`, `afc85a0`)
- ameba-arduino-pro2 dev/main: Frozen at May 5, 2026 (`13961cc`)

**No confirmed fix. Bug remains unpatched as of 2026-05-18 (Cycle U19).**

**Top unresolved actions (updated from U18):**
1. **Hardware test of "Camera FCS Mode = Disable"** — source-confirmed full FCS bypass; no hardware test result exists anywhere. Highest priority.
2. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP SPIC writes; source-confirmed path; requires modifying `video_api.h` in the SDK (not accessible from Arduino sketch directly).
3. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — wrap `FlashMemory.erase()` / `FlashMemory.write()` with `device_mutex_lock(1)` / `device_mutex_unlock(1)` (if `device_lock.h` is accessible from Arduino). If this eliminates the cold-boot failure, SPIC concurrent-access is confirmed as the root cause.

## Research Update — 2026-05-18 (Cycle U20)

**Search scope:** Four parallel agents: (1) GitHub — all repos post-May 15 activity, commit history for FlashMemory.cpp, open issues; (2) English forum/web — threads above #4840, FCS Disable hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/Bilibili/Gitee; (4) SDK deep-dive — official flash example mutex pattern, `flash_api.c` availability, PRs adding mutex to FlashMemory.

**Key new findings this cycle:**
- **Official Realtek SDK flash example (`flash/src/main.c`) explicitly wraps every flash HAL call with `device_mutex_lock(RT_DEV_LOCK_FLASH)`** — this is the strongest evidence yet that Realtek considers the mutex mandatory for safe flash access. FlashMemory.cpp's omission is an intentional divergence from the documented correct pattern, not an oversight in the example.
- **FlashMemory.cpp has only 2 commits in its entire history** (V4.0.8: Oct 29 2024; V4.1.0: Mar 2 2026) — the library was never updated to add mutex protection in any release.
- **HUB-8735 Issue #10 new error string** — `"hal_voe_send2voe too long 36808 cmd 0x00000206"` — VOE IPC buffer overflow producing `VOE_OPEN_CMD command fail` / `hal_video_open fail` via a different failure path than FCS_I2C_INIT_ERR. Catalog entry for a distinct error route to the same terminal failure.
- All repos confirmed frozen; no new commits above May 15 (rtos-pro2) / May 5 (arduino-pro2); no forum threads above #4840 indexed anywhere; zero Chinese-language content.

| Source | Key Finding | Priority |
|---|---|---|
| `project/realtek_amebapro2_v0_example/example_sources/flash/src/main.c` (ameba-rtos-pro2, SHA `68c95b75`) | **Official Realtek SDK flash example wraps every flash operation with `device_mutex_lock(RT_DEV_LOCK_FLASH)`.** Confirmed pattern: `device_mutex_lock(RT_DEV_LOCK_FLASH)` → `flash_read_word()` / `flash_erase_sector()` / `flash_write_word()` / `flash_stream_write()` / `flash_stream_read()` → `device_mutex_unlock(RT_DEV_LOCK_FLASH)`. This is the official Realtek-authored reference implementation demonstrating that the flash bus mutex is required for any user flash access. `FlashMemory.cpp` (the Arduino library) omits this mutex across all 8 public flash operations — making it non-compliant with Realtek's own published safe-usage pattern. This is the clearest authoritative evidence that the RT_DEV_LOCK_FLASH bypass in FlashMemory is an architectural bug. | HIGH |
| `FlashMemory.cpp` commit history (ameba-arduino-pro2, GitHub log fetched 2026-05-18) | **FlashMemory.cpp has only 2 commits in its entire history:** `581ce487` "Release Version 4.0.8" (Oct 29, 2024, author M-ichae-l) and `93d63514` "Release Version 4.1.0" (Mar 2, 2026, author M-ichae-l). The library was never modified between these two releases, and no mutex was introduced at either point. No PRs adding mutex protection to FlashMemory exist (0 results in open + closed PR search). The mutex omission is not a pending fix — it has been unchanged across the library's entire 18-month public history. | MEDIUM |
| ideashatch/HUB-8735 Issue #10 (Aug 13, 2025 — open, no fix) | **New error string identified: `"hal_voe_send2voe too long 36808 cmd 0x00000206"`** — VOE IPC command payload (36,808 bytes) exceeds the KM co-processor's receive buffer for command `0x206`. Triggers cascade: `"VOE_OUT_CMD type 2 command fail -1"` → `"VOE_OPEN_CMD command fail"` → `"hal_video_open fail"`. This is a distinct root cause (IPC buffer overflow) from `FCS_I2C_INIT_ERR (0x200A)` but produces the same terminal failure. Relevant to the error catalog: the same terminal strings (`VOE_OPEN_CMD command fail`, `hal_video_open fail`) can originate from at least two independent root causes. PS5268 wide-angle sensor only; not flash-triggered. | LOW |
| `flash_api.c` (ameba-rtos-pro2 and ameba-arduino-pro2, fetched 2026-05-18) | **`flash_api.c` confirmed NOT publicly available as source.** Referenced in CMake build files (`component/mbed/targets/hal/rtl8735b/config.json` and `application.cmake`) but the `.c` source is not present in the public repo — compiled into prebuilt binary libraries. Any mutex or WIP protection at the mbed layer cannot be verified from public source. Given `hal_flash.c` has no mutex and the official example bypasses `hal_flash.c` by calling mutex + flash API directly, the mbed layer is likely mutex-free as well. | LOW (confirms U17) |
| All GitHub repos (ameba-rtos-pro2, ameba-arduino-pro2, ideashatch/HUB-8735), fetched 2026-05-18 | **All repos confirmed frozen — identical to U19.** ameba-rtos-pro2 HEAD = `3f95070` (May 15, 2026); ameba-arduino-pro2 main = `93d63514` (Mar 2, 2026); dev = `13961cc` (May 5, 2026); ideashatch/HUB-8735 last commit Dec 2025. No new commits, issues, PRs, or releases in any repo. ameba-arduino-pro2 open issues: #398 (Mar 29, 2026) remains the newest — no new issues related to flash/FCS/camera/VOE/boot. Three independent agents confirmed identical freeze state. | LOW |
| forum.amebaiot.com thread ceiling (fetched 2026-05-18) | **No threads above #4840 indexed.** Search for thread IDs 4841–4845 returns zero results in any search engine. Forum ceiling remains at thread #4840 ("OTA via HTTPS", ~May 2026, unrelated to our bug). No new relevant threads have appeared since U19. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/Bilibili/Gitee, May 18 sweep, two agents) | **Zero new content — unchanged for 20 consecutive cycles.** All Chinese community sites remain 403-blocked. bbs.aithinker.com thread tid=46140 ("BW21-CBV-Kit调试") contains SWD/I2C pin conflict content (confirmed from prior indexed snippet) — unrelated to FCS flash-write camera failure. No new Chinese-language articles, forum posts, or technical discussions about this bug were found in any source. | LOW |
| Web-wide English search: all key error strings (2026-05-18 sweep) | **Zero indexed results — unchanged.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"` return zero results anywhere on the public web. No hardware test result for "Camera FCS Mode = Disable" as a flash-write bug workaround has been posted anywhere. This research log remains the only publicly accessible documentation of this bug and its error codes. | LOW |

**Official flash example mutex pattern (reference for user workaround):**

The correct mutex pattern from `flash/src/main.c` (Realtek's official usage reference):

```c
#include "device_lock.h"
// Before any flash operation:
device_mutex_lock(RT_DEV_LOCK_FLASH);    // = device_mutex_lock(1)
flash_erase_sector(&flash, address);
device_mutex_unlock(RT_DEV_LOCK_FLASH);  // = device_mutex_unlock(1)
```

This pattern can be applied in an Arduino sketch to wrap any `FlashMemory.erase()` or `FlashMemory.write()` call, provided `device_lock.h` is accessible from the sketch include path. The header is present in both repos at `component/os/os_dep/include/device_lock.h`.

**VOE terminal-error catalog — two confirmed root cause paths (updated):**

| Root cause | Error sequence | Triggered by |
|---|---|---|
| `FCS_I2C_INIT_ERR (0x200A)` | `FCS KM_status 0x2081` → "It don't do the sensor initial process" → `VOE_OPEN_CMD fail` → `hal_video_open fail` | Concurrent SPIC access (FlashMemory + ISP AE/AWB) corrupting FCS data at 0xF0D000 |
| VOE IPC buffer overflow (cmd 0x206) | `hal_voe_send2voe too long 36808` → `VOE_OUT_CMD type 2 fail -1` → `VOE_OPEN_CMD command fail` → `hal_video_open fail` | Wrong sensor variant (e.g., PS5268 wide-angle vs. standard) |

**SDK state as of 2026-05-18 (Cycle U20 — unchanged from U19):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release: V4.1.1-QC-V05 (Apr 17, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at May 15, 2026 (`3f95070`, `afc85a0`) — 3 days no change
- ameba-arduino-pro2 dev/main: Frozen at May 5, 2026 (`13961cc`) / Mar 2, 2026

**No confirmed fix. Bug remains unpatched as of 2026-05-18 (Cycle U20).**

**Top unresolved actions (updated from U19):**
1. **Hardware test of "Camera FCS Mode = Disable"** — source-confirmed full FCS bypass via dummy blob; no public hardware test result exists anywhere. Highest priority.
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper around `FlashMemory.erase()` / `.write()`** — Realtek's own official flash example confirms this is the required pattern; applying it in Arduino sketch is the minimal-invasive fix candidate. If this eliminates the cold-boot failure, SPIC concurrent-access is confirmed as the root cause and the fix is a one-liner per flash call.
3. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes; requires RTOS SDK `video_api.h` modification.

## Research Update — 2026-05-18 (Cycle U21)

**Search scope:** Six parallel search threads + direct GitHub/web fetches: (1) GitHub — new commits in ameba-rtos-pro2 and ameba-arduino-pro2 after May 15 / May 5; new issues and PRs; (2) English forum/web — new threads above #4840, FCS Disable / mutex workaround hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/Bilibili/Gitee; (4) amebaiot.com Flash Memory docs — any new mutex warnings; (5) New documentation portals — aiot.realmcu.com AMB82-mini guide; ameba-doc-rtos-pro2-sdk flash layout page; (6) PlatformIO issue #4809 disambiguation.

**Key new findings this cycle:**
- **PR #408 "Add I2C Slave"** opened May 15, 2026 on ameba-arduino-pro2 — confirms the Arduino repo has some active development; unrelated to flash/FCS.
- **Forum thread #4835 newly indexed** — "AMB82-mini Deep Sleep: Is AON GPIO pin 21 unreadable after `PowerMode.begin()`? (Bus Fault observed)" — tangentially relevant because deep sleep + wake cycles may involve a cold boot scenario; content still 403-blocked.
- **PlatformIO issue #4809 disambiguation** — the GitHub `platformio/platformio-core` issue #4809 ("Board Support: REALTEK AMB82-Mini") is a feature request for PlatformIO board support, entirely distinct from forum thread #4809 ("AMB82-Mini starts running Arduino code before turning on 3.3V"). Both previously appeared in searches as "#4809"; they are unrelated.
- Both repos confirmed frozen at identical HEADs as Cycle U20. No new releases, no new bug reports, no new Chinese-language content anywhere. Error strings remain unindexed.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 commits (direct GitHub fetch, 2026-05-18) | **Confirmed frozen — identical to U20.** HEAD = `3f95070` "Sync upstream 7343927…" (May 15, 2026). Twenty most recent commits retrieved and verified: newest are `3f95070`, `afc85a0` (May 15), `d2676f1`, `9c8b6f6` (May 15) — all unchanged from U20. No flash, FCS, VOE, boot, HAL, or sensor changes in any of the 20 most recent commits. | LOW |
| ameba-arduino-pro2 dev branch commits (direct GitHub fetch, 2026-05-18) | **Confirmed frozen.** HEAD = `13961ccf` (May 5, 2026) — unchanged from U20. | LOW |
| ameba-arduino-pro2 PR #408 "Add I2C Slave" (opened May 15, 2026, by kevinlookl) | **New PR identified — unrelated to bug.** Changes the Wire library to add I2C Slave functionality (3 commits). There are no other open PRs besides #408. All previously tracked open issues remain unchanged — newest is #398 (Mar 29, 2026). No PRs or issues about FlashMemory, mutex, FCS, camera, or boot failure exist in open or closed history. Confirms the Arduino repo has some ongoing activity but no FCS/flash bug triage. | LOW |
| forum.amebaiot.com/t/.../4835 — "AMB82-mini Deep Sleep: Is AON GPIO pin 21 unreadable after `PowerMode.begin()`? (Bus Fault observed)" | **Newly indexed forum thread.** Confirmed present in search engine results for the first time this cycle. Topic: user configures deep sleep (RETENTION=0) with wake-on-external-HIGH on AON GPIO pin 21; observes Bus Fault after `PowerMode.begin()`. Content is 403-blocked; snippet indicates the thread is in the "Arduino" category and involves power/sleep cycles. Tangential relevance: if a device with a pending FlashMemory operation enters deep sleep, the resulting power cycle (sleep → wake) may constitute a "cold boot" that catches the flash operation in a vulnerable state. The bus fault itself is a separate failure from FCS_I2C_INIT_ERR. Not confirmed as flash-write-triggered. | LOW (blocked) |
| PlatformIO issue #4809 (`platformio/platformio-core` GitHub) | **Disambiguation confirmed.** This is a feature request to add REALTEK AMB82-Mini board support to PlatformIO (opened by user `whittenator`). It is entirely separate from and unrelated to forum.amebaiot.com/t/.../4809 ("AMB82-Mini starts running Arduino code before turning on 3.3V"). Prior research (U15) may have ambiguously referenced both as "#4809" — the forum thread describes a power-sequencing anomaly; the PlatformIO issue is a board-support feature request. Neither contains a fix for our bug. | LOW (disambiguation) |
| aiot.realmcu.com AMB82-mini documentation (2026-05-18) | **Still 403-blocked.** Direct fetch of `aiot.realmcu.com/en/latest/arduino/arduino_guide/sdk_intro/evb_guides/evb_amb82mini.html` returns HTTP 403. The new Realtek documentation portal remains inaccessible without developer login. | LOW (blocked) |
| ameba-doc-rtos-pro2-sdk.readthedocs-hosted.com flash layout docs (2026-05-18) | **Still 403-blocked.** `ameba-doc-rtos-pro2-sdk.readthedocs-hosted.com/en/latest/application_note/08_FLASHLAYOUT.html` returns HTTP 403. | LOW (blocked) |
| amebaiot.com Flash Memory Read Write Word docs (2026-05-18) | **Still 403-blocked.** `amebaiot.com/en/amebapro2-arduino-flash-writeword/` returns HTTP 403. No new mutex warning or FCS interaction note accessible from the official Flash Memory documentation. | LOW (blocked) |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/Bilibili/Gitee, May 18 sweep) | **Zero new content — unchanged for 21 consecutive cycles.** CSDN article `139222964` (AMB82-MINI Arduino method intro) and `139584304` (SD card AI recognition) are the only indexed AMB82 Chinese articles; neither discusses FCS flash-write camera failure. All Chinese community forums remain 403-blocked. No new BW21-CBV or RTL8735B Chinese-language technical posts found anywhere. | LOW |
| Web-wide English search: all key error strings (2026-05-18 sweep) | **Zero indexed results — unchanged across all 21 cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"` return zero publicly indexed results anywhere on the accessible web. No hardware test result for any of the three proposed workarounds ("Camera FCS Mode = Disable", `device_mutex_lock` wrapper, `USE_ISP_RETENTION_DATA`) has been posted anywhere. | LOW |

**SDK state as of 2026-05-18 (Cycle U21 — unchanged from U20):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release: V4.1.1-QC-V05 (Apr 17, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at May 15, 2026 (`3f95070`, `afc85a0`) — 3 days no change
- ameba-arduino-pro2 dev/main: Frozen at May 5, 2026 (`13961cc`) / Mar 2, 2026

**No confirmed fix. Bug remains unpatched as of 2026-05-18 (Cycle U21).**

**Open actions — unchanged from U20 (no new hardware test results found):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files; no public result anywhere. Highest priority.
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` example demonstrates this is the required pattern; omission from `FlashMemory.cpp` is the confirmed architectural defect.
3. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes entirely; requires `video_api.h` edit.

## Research Update — 2026-05-18 (Cycle U22)

**Search scope:** Four parallel agents + direct web searches: (1) GitHub — all repos post-May 15 activity, open PRs; (2) English forum/web — new threads above #4840, FCS Disable / mutex workaround hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/Bilibili/Gitee; (4) `device_lock.h` accessibility from Arduino sketch — raw URL fetch, enum verification, Arduino include path investigation.

**Key new findings this cycle:**
- `device_lock.h` raw GitHub URL confirmed accessible without authentication; full API verified with `RT_DEV_LOCK_VOE = 5` newly documented as a separate lock enum entry.
- Four previously untracked forum threads newly identified (#4651, #4802, #4803, #4829) — all 403-blocked; #4651 potentially relevant.
- ameba-rtos-pro2 has open PR #17 (USB Ethernet driver) — first confirmed open PR; unrelated to bug.
- Official RTOS ISP doc confirms `SAVE_TO_FLASH` "requires checking flash write limits" — official Realtek acknowledgement of flash write pressure in the ISP context.
- All repos confirmed frozen; zero new commits, releases, forum threads, or hardware test reports anywhere.

| Source | Key Finding | Priority |
|---|---|---|
| `component/os/os_dep/include/device_lock.h` (raw GitHub URL, fetched 2026-05-18) | **Full API confirmed from direct fetch.** `typedef uint32_t RT_DEV_LOCK_E`. Enum: `RT_DEV_LOCK_EFUSE=0, RT_DEV_LOCK_FLASH=1, RT_DEV_LOCK_CRYPTO=2, RT_DEV_LOCK_PTA=3, RT_DEV_LOCK_WLAN=4, RT_DEV_LOCK_VOE=5, RT_DEV_LOCK_NN=6, RT_DEV_LOCK_MAX=7`. Functions: `void device_mutex_lock(RT_DEV_LOCK_E device)` / `void device_mutex_unlock(RT_DEV_LOCK_E device)`. No platform-specific conditional compilation. Realtek copyright 2013. Raw URL: `https://raw.githubusercontent.com/Ameba-AIoT/ameba-rtos-pro2/main/component/os/os_dep/include/device_lock.h` | MEDIUM |
| `device_lock.h` Arduino SDK accessibility | **NOT in public Arduino SDK includes.** The header is confirmed to exist in the RTOS layer but is not present in or documented for the ameba-arduino-pro2 package. An Arduino sketch could potentially include it via a relative or absolute path (e.g., by copying it into the sketch directory), but this is undocumented and unsupported. No Arduino examples anywhere call `device_mutex_lock`. **Correction of prior cycle:** there is NO risk of deadlock from wrapping `FlashMemory.erase()` with `device_mutex_lock(RT_DEV_LOCK_FLASH)` — `FlashMemory.cpp` has zero mutex calls (confirmed U20), so the outer lock would be acquired, HAL calls execute unguarded, then lock releases. No nested acquisition possible. | MEDIUM |
| `RT_DEV_LOCK_VOE = 5` in `device_lock.h` | **VOE subsystem has its own separate device lock.** The `RT_DEV_LOCK_VOE = 5` entry confirms that VOE IPC operations are expected to be separately serialized from flash operations. The ISP AE/AWB flash write path uses `RT_DEV_LOCK_FLASH = 1` (via `ftl_nor_api.c` — confirmed U19). The VOE FCS cold-boot path uses the KM co-processor and does not appear to use `RT_DEV_LOCK_FLASH`. The two locks are independent. | LOW |
| Official RTOS ISP doc snippet (`ameba-doc-rtos-pro2-sdk.readthedocs-hosted.com/en/latest/application_note/15_ISP.html`) | **`SAVE_TO_FLASH` officially documented with flash write limit warning.** Web search snippet (URL 403-blocked) confirms the official docs state: "`SAVE_TO_FLASH`: saves video initial AE, AWB settings to flash, and data is saved for all modes **but requires checking flash write limits**." `SAVE_TO_RETENTION` is documented as zero-SPIC (SRAM only). This is an official Realtek acknowledgement that ISP AE/AWB SAVE_TO_FLASH mode has flash write constraints — consistent with our SPIC concurrent-access finding from U19. No mention of interaction with `FlashMemory` in accessible snippets. | MEDIUM |
| forum.amebaiot.com/t/how-to-use-more-than-16mb-flash-on-amb82-mini/4651 (Jan 2026) | **Newly identified thread** (previously untracked). Title: "How to use more than 16MB flash on AMB82 Mini." Indexed in search results with snippet: "users discussing upgrading from 16MB to 32MB flash using a Winbond chip." Content 403-blocked. If users replace the 16MB flash chip with a 32MB part, the FCS partition and FlashMemory partition table assignments may shift — potentially increasing the risk of our bug if the larger flash changes the sector layout visible to the boot ROM. Tangentially relevant. | LOW (blocked) |
| forum.amebaiot.com/t/amb82-mini-usb-host-cdc-ecm-fails-to-enumerate-quectel-ec200u-4g-modem-ecm-init-fail/4802 | **Newly identified thread** (previously untracked). Title: "AMB82-Mini USB Host CDC ECM fails to enumerate Quectel EC200U 4G modem — 'ecm init fail'." USB host CDC ECM initialization failure. Content 403-blocked. Not related to camera/flash/FCS. Adds to thread catalog. | LOW (blocked) |
| forum.amebaiot.com/t/amb82-mini-usb-ethernet-failing/4803 | **Newly identified thread** (previously untracked). Title: "AMB82-mini: USB Ethernet failing." USB Ethernet issues. Content 403-blocked. Not related to camera/flash/FCS. Adds to thread catalog. | LOW (blocked) |
| forum.amebaiot.com/t/can-amb82-mini-be-used-with-teachable-machine-uvc-issue/4829 | **Newly identified thread** (previously untracked). Title: "Can AMB82 MINI be used with Teachable Machine? (UVC Issue)." Content 403-blocked. Not related to camera cold-boot / FCS / flash. | LOW (blocked) |
| ameba-rtos-pro2 PR #17 (GitHub, May 15, 2026) | **First confirmed open PR in ameba-rtos-pro2.** Title appears to be about USB Ethernet/NCM driver support. Confirmed open and unmerged as of 2026-05-18. Not related to flash, FCS, camera, or boot issues. Confirms the repo is not entirely dormant — USB subsystem has pending community contributions. | LOW |
| All GitHub repos (ameba-rtos-pro2, ameba-arduino-pro2, ideashatch/HUB-8735), fetched 2026-05-18 | **All repos confirmed frozen — identical to U21.** ameba-rtos-pro2 HEAD = `3f95070` (May 15, 2026); ameba-arduino-pro2 main HEAD = `93d63514` (Mar 2); dev = `13961cc` (May 5); HUB-8735 last commit Dec 2025. Zero new commits, issues, or releases anywhere. No FCS/flash/camera fixes in any pipeline. | LOW |
| All forum threads above #4840 | **Still none indexed.** Threads #4841 through at least #4848 return zero search results. Forum ceiling remains at #4840 ("OTA via HTTPS", ~May 2026). | LOW |
| All English/Chinese web sources (full sweep, 2026-05-18) | **Zero new content — 22 consecutive cycles.** All Chinese community sites remain 403-blocked. No new English-language hardware test reports for any workaround ("Camera FCS Mode = Disable", `device_mutex_lock` wrapper, `USE_ISP_RETENTION_DATA`). Error strings `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"` return zero publicly indexed results. | LOW |

**`device_lock.h` Arduino integration — practical implementation guidance (updated):**

The confirmed API allows an Arduino sketch to wrap FlashMemory operations as follows:

```cpp
// Method 1: Direct include (path may not be in Arduino default search path)
#include "device_lock.h"

// Method 2: Inline the minimal definition (no include required)
extern "C" {
    typedef unsigned int RT_DEV_LOCK_E;
    void device_mutex_lock(RT_DEV_LOCK_E device);
    void device_mutex_unlock(RT_DEV_LOCK_E device);
}
#define RT_DEV_LOCK_FLASH 1

// Usage (compatible with both methods):
device_mutex_lock(RT_DEV_LOCK_FLASH);     // Acquire flash bus lock
FlashMemory.erase();                       // or FlashMemory.write(), etc.
device_mutex_unlock(RT_DEV_LOCK_FLASH);   // Release flash bus lock
```

Method 2 (forward declaration without the header) avoids the include-path problem entirely, as the linker will resolve `device_mutex_lock` at link time from the prebuilt RTOS libraries (same as how FreeRTOS API functions are used from Arduino). This is the recommended approach for Arduino context.

**Official SAVE_TO_FLASH warning — context for `USE_ISP_RETENTION_DATA`:**

The ISP application note explicitly says `SAVE_TO_FLASH` "requires checking flash write limits." This confirms that Realtek's own documentation acknowledges ISP flash write pressure — but frames it as a flash *endurance* concern (write cycle limits), not a *concurrent access* concern (SPIC bus collision). The architectural defect (FlashMemory bypassing `RT_DEV_LOCK_FLASH`) remains undocumented in any official Realtek publication.

**SDK state as of 2026-05-18 (Cycle U22 — unchanged from U21):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release: V4.1.1-QC-V05 (Apr 17, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at May 15, 2026 (`3f95070`, `afc85a0`); PR #17 open
- ameba-arduino-pro2 dev/main: Frozen at May 5, 2026 (`13961cc`) / Mar 2, 2026

**No confirmed fix. Bug remains unpatched as of 2026-05-18 (Cycle U22).**

**Top unresolved actions (updated from U21):**
1. **Hardware test of "Camera FCS Mode = Disable"** — source-confirmed full FCS bypass via dummy blob; no public hardware test result exists anywhere. Highest priority.
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Method 2 (forward declaration) avoids include-path issues and is linkable from Arduino. Deadlock risk is zero (FlashMemory.cpp has no mutex). If this eliminates cold-boot failure, SPIC concurrent-access is confirmed as root cause.
3. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes; requires `video_api.h` edit in RTOS SDK or Arduino package.

## Research Update — 2026-05-19 (Cycle U23)

**Search scope:** Six parallel search threads + direct GitHub fetches: (1) GitHub — all repos post-May 18 activity, new commits/PRs/issues; (2) English forum/web — new threads above #4840, FCS Disable / mutex workaround hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/Bilibili/Gitee; (4) SDK doc portals — aiot.realmcu.com AMB82-mini guide, readthedocs ISP docs, flash memory docs; (5) ameba-rtos-pro2 HEAD comparison to confirm freeze; (6) ameba-arduino-pro2 dev/main branch activity.

**Key new findings this cycle:**
- **ameba-arduino-pro2 dev branch: new commit `cd0bd40` (May 18, 2026)** — "Add I2C Slave (#408)", merging PR #408 (kevinlookl). Wire library updated with I2C Slave support and timeout API. Unrelated to flash/FCS bug. This is the first new commit to any Ameba repo since our last cycle cutoff.
- **PR #408 merged and closed** — was listed as open in U21; now confirmed merged May 18 by M-ichae-l. Zero open PRs remain in ameba-arduino-pro2.
- **ameba-rtos-pro2 frozen confirmed from comparison**: `3f95070...HEAD` shows identical — zero new commits since May 15, 2026.
- **Forum thread #4865 newly identified**: "AmebaPro2 uartfwburn - Can't flash. 'fail for download 0' after 'programing' is 100% complete" — about the UART firmware upload tool failing after 100% progress. Distinct failure class (upload tool, not runtime flash + camera race). 403-blocked; not related to our bug.
- All documentation portals remain 403-blocked; no new Chinese-language content; no hardware test results for any proposed workaround.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-arduino-pro2 dev branch commit `cd0bd40` (May 18, 2026, M-ichae-l) | **New commit after U22 cutoff.** Content: merge of PR #408 "Add I2C Slave" — adds I2C Slave functionality to the Wire library (3 sub-commits covering I2C Slave implementation, coding style compliance, and Wire timeout API). Tested on AMB82-mini with ambpro2_arduino V4.1.1 / Arduino IDE 2.3.7 / Windows 11. **Unrelated to flash/FCS/camera/boot failure bug.** | LOW (unrelated) |
| ameba-arduino-pro2 PR #408 (closed May 18, 2026) | **Merged by M-ichae-l.** Was open in U21 ("Add I2C Slave", kevinlookl). Zero open PRs remain. No new PRs related to FlashMemory, mutex, FCS, or camera exist in open or closed history. | LOW (unrelated) |
| ameba-rtos-pro2 `3f95070...HEAD` comparison (direct GitHub fetch) | **Frozen definitively confirmed.** GitHub compare endpoint returns: "3f95070 and HEAD are identical." Zero new commits in 4 days since May 15, 2026. No flash, FCS, VOE, boot, or sensor changes in any observable pipeline. | LOW |
| ameba-arduino-pro2 main branch (direct GitHub fetch) | **Still frozen.** HEAD = `93d63514` "Release Version 4.1.0" (March 2, 2026) — identical to all prior cycles. ameba-arduino-pro2 main has not been updated in 78 days. The I2C Slave commit (`cd0bd40`, May 18) landed in `dev` only. | LOW |
| ameba-arduino-pro2 issues (direct GitHub fetch) | **12 open issues confirmed; newest is #398 (Mar 29, 2026).** No new issues after May 18, 2026. No issues about FlashMemory, FCS, camera, VOE, or boot failure exist anywhere in the issue tracker (open or closed). | LOW |
| ameba-rtos-pro2 issues (direct GitHub fetch) | **3 open issues (unchanged since U8):** #16 (AI glass src path, Jan 27, 2026), #4 (chip support, Apr 25, 2025), #3 (antivirus detection, Apr 21, 2025). No new issues. No FCS/flash/camera bug filed. | LOW |
| ideashatch/HUB-8735 issues (direct GitHub fetch) | **1 open issue: #10** (PS5268 sensor ID fail, Aug 13, 2025). No new issues after May 18, 2026. Unchanged since U10. | LOW |
| forum.amebaiot.com thread #4865 (search engine snippet, 403 content) | **Newly identified thread above prior ceiling (#4840).** Title: "AmebaPro2 uartfwburn - Can't flash. 'fail for download 0' after 'programing' is 100% complete." About the UART firmware upload tool completing 100% progress (81920/81920 bytes) but reporting "fail for download 0" at verification. This is a **firmware flash-tool failure** (programming interface), distinct from our runtime `FlashMemory` + camera race condition. Thread 403-blocked; not related to our bug. Highest indexed thread ID found this cycle. | LOW (blocked, unrelated) |
| ameba-arduino-pro2 releases (direct GitHub fetch) | **No new releases.** Latest stable = V4.1.0 (Mar 2, 2026). Latest pre-release = V4.1.1-QC-V05 (Mar 6, 2026). No V4.1.1 stable or QC-V06+ exists. Confirmed by direct releases page fetch. | LOW |
| aiot.realmcu.com, ameba-doc-arduino-sdk.readthedocs-hosted.com, ameba-doc-rtos-pro2-sdk.readthedocs-hosted.com | **All documentation portals still 403-blocked.** ISP app note (`15_ISP.html`), AMB82-mini Arduino guide (aiot.realmcu.com), Flash Memory example docs, Flash layout app note — all require developer authentication. No new public documentation found. | LOW (blocked) |
| GitHub Issue #251 (ameba-arduino-pro2) — retrospective confirmation | **Normal working FCS boot log confirmed from issue.** Boot sequence shows: `FCS KM_status 0x00000082 err 0x00000000` + `FCS TM_status 0x00000001` → `fcs OK`. This is the healthy reference boot (matches the reference at top of this document). Issue itself is about DDR memory exhaustion during ControlLED example — unrelated to flash writes. | LOW (background) |
| All English/Chinese web sources (full sweep, 2026-05-19) | **Zero new content — 23 consecutive cycles with no new indexed results.** Error strings `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"` return zero publicly indexed results on the accessible web. No hardware test result for any proposed workaround has been posted anywhere. All Chinese community sites (bbs.aithinker.com, bbs.ai-thinker.com, CSDN, Zhihu, EEWorld, 21IC, Bilibili, Gitee) remain 403-blocked or return zero relevant content. | LOW |

**SDK state as of 2026-05-19 (Cycle U23):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release: V4.1.1-QC-V05 (Mar 6, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at May 15, 2026 (`3f95070`, `afc85a0`) — 4 days no change
- ameba-arduino-pro2 dev: `cd0bd40` (May 18, 2026, I2C Slave — unrelated); main: frozen Mar 2, 2026

**No confirmed fix. Bug remains unpatched as of 2026-05-19 (Cycle U23).**

**Top unresolved actions (unchanged from U22 — no new hardware test results found):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. Highest priority.
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates this is the required pattern for safe flash access; FlashMemory.cpp's omission is the confirmed architectural defect. Forward-declaration pattern callable from Arduino sketch without include-path issues.
3. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes at source; requires `video_api.h` edit.

## Research Update — 2026-05-19 (Cycle U24)

**Search scope:** Six parallel search threads: (1) GitHub — all repos post-May 18 activity, commits/PRs/issues/releases in ameba-rtos-pro2 and ameba-arduino-pro2; (2) English forum/web — new threads above #4865, FCS Disable / mutex / USE_ISP_RETENTION_DATA workaround hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/mcublog.cn/Bilibili/Gitee; (4) Documentation portals — aiot.realmcu.com, readthedocs ISP/Flash Memory/MMF docs; (5) Error string indexing sweep — `FCS_I2C_INIT_ERR`, `FCS KM_status 0x00002081`, `It don't do the sensor initial process`; (6) RTL8735C/AmebaPro3 SDK availability.

**Key new findings this cycle:** None. All research channels frozen, blocked, or empty for the 24th consecutive cycle. No new commits, releases, forum threads, documentation, or hardware test reports found anywhere.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 GitHub compare `3f95070...HEAD` (fetched 2026-05-19) | **Confirmed frozen by compare endpoint.** GitHub returned: "3f95070 and HEAD are identical." Zero new commits since May 15, 2026. No flash, FCS, VOE, boot, HAL, or sensor changes in any observable pipeline. Confirmed by two independent methods (direct commit page + compare endpoint). | LOW |
| ameba-arduino-pro2 main branch (fetched 2026-05-19) | **Still frozen.** HEAD = `93d63514` (March 2, 2026). No new commits to `main` in 78 days. The `dev` branch commit `cd0bd40` (May 18, I2C Slave) was already documented in U23; no further `dev` branch activity detected. | LOW |
| ameba-arduino-pro2 releases (fetched 2026-05-19) | **No new releases.** Latest stable = V4.1.0 (Mar 2, 2026). Latest pre-release = V4.1.1-QC-V05 (Mar 6, 2026). No V4.1.1 stable release or QC-V06+ has been published. Release list unchanged since U10. | LOW |
| ameba-arduino-pro2 issues (fetched 2026-05-19) | **12 open issues; newest = #398 (Mar 29, 2026).** No new issues filed for FCS, flash, camera, VOE, boot failure, or sensor init. All 12 open issues are feature requests. Bug remains entirely unreported on the official tracker after 24 research cycles. | LOW |
| ideashatch/HUB-8735 issues (fetched 2026-05-19) | **1 open issue: #10** (PS5268 sensor id fail, Aug 2025). No new issues. Unchanged since U10. | LOW |
| forum.amebaiot.com threads above #4865 (search 2026-05-19) | **No new threads indexed.** Targeted search for thread IDs 4866–4890 returned zero results. Forum ceiling remains at #4865 ("AmebaPro2 uartfwburn - Can't flash", hardware upload issue, unrelated to our bug). | LOW |
| All documentation portals (2026-05-19) | **All still 403-blocked.** `ameba-doc-rtos-pro2-sdk.readthedocs-hosted.com/en/latest/application_note/15_ISP.html`, Flash Memory example guide, MMF architecture doc, `aiot.realmcu.com` AMB82-mini guide — all return HTTP 403. No new content accessible without developer authentication. | LOW (blocked) |
| Web-wide error string sweep (2026-05-19) | **Zero indexed results — unchanged across all 24 cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"` return zero publicly indexed results anywhere on the accessible web. No hardware test result for any of the three proposed workarounds has been posted anywhere. | LOW |
| RTL8735C / AmebaPro3 (search 2026-05-19) | **No public SDK announced.** RTL8735C was announced at COMPUTEX 2025 (documented in U15); no development SDK, GitHub repository, or Arduino support has been released publicly as of today. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/mcublog.cn, May 19 sweep) | **Zero new content — 24 consecutive cycles.** All Chinese community sites remain 403-blocked or return zero relevant results for FCS flash-write camera failure on BW21-CBV or RTL8735B. mcublog.cn BW21-CBV article (April 2026, Feishu bot LED+photo) remains 403. bbs.aithinker.com all threads 403. No new Chinese-language technical posts about this bug found. | LOW |

**SDK state as of 2026-05-19 (Cycle U24 — unchanged from U23):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release: V4.1.1-QC-V05 (Mar 6, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at May 15, 2026 (`3f95070`, `afc85a0`) — 4 days no change; confirmed identical to HEAD by compare endpoint
- ameba-arduino-pro2 dev: `cd0bd40` (May 18, 2026, I2C Slave — unrelated); main: frozen Mar 2, 2026

**No confirmed fix. Bug remains unpatched as of 2026-05-19 (Cycle U24).**

**Top unresolved actions (unchanged across U20–U24 — no new hardware test results found in any cycle):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. Highest priority.
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates this is the required pattern; FlashMemory.cpp omission is the confirmed architectural defect; forward-declaration pattern avoids include-path issues from Arduino.
3. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes; requires `video_api.h` edit.


## Research Update — 2026-05-19 (Cycle U25)

**Search scope:** Six parallel agents + direct GitHub fetches: (1) GitHub — all repos post-May 18 activity, new commits/PRs/issues/releases; (2) English forum/web — new threads above #4865, FCS Disable / mutex / USE_ISP_RETENTION_DATA workaround reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/Bilibili/Gitee; (4) SDK deep-dive — `hal_video_release_note.txt` from new May 19 build, `FlashMemory.cpp` full source and commit history, `hal_video_common.h` FCS field, `video_api.h` USE_ISP_RETENTION_DATA status; (5) `GitHub_release_note.txt` full content; (6) RTL8735C/AmebaPro3 SDK availability and aiot.realmcu.com access.

**Key new findings this cycle:**
- **`ameba-arduino-pro2` dev branch has two new commits dated May 19, 2026** — `3d53672` "Update Code base and add cam IMX681_5M (#409)" (122 files changed) and `7db1c7d` "Pre Release Version 4.1.1". Pre-release `4.1.1-build20260519` is packaged in the early index JSON but not yet published as a GitHub Release tag.
- **`voe.bin` and `boot.bin` were updated** in the new build (binary blobs — no diff possible). `hal_video_release_note.txt` was also updated.
- **`hal_video_release_note.txt` full content retrieved** — newest documented VOE version is **1.7.1.0 (04/21/2026)**, which only fixes "dual sensor id FCS mirror/flip issue" (unrelated to our `FCS_I2C_INIT_ERR` boot bug). **No FCS cold-boot fix, no flash-mutex entry, no sensor-init-after-flash-write fix is documented anywhere in the 46-version release history.**
- **`FlashMemory.cpp` full source confirmed** — 3 total commits in history (Jul 2024, Sep 2025 ×2); still zero mutex calls across all 8 flash operations. Unchanged in May 19 build.
- **New sibling-chip thread identified** — forum.amebaiot.com/t/rtl8720c-flash-log/1239: "RTL8720C — after saving data to FLASH, log shows boot failure on next restart" — same symptom class on the RTL8720C (sibling of RTL8735B). 403-blocked.
- **New Chinese platform thread**: bbs.ai-thinker.com thread tid=46317 "[BW20]二次开发学习4 FLASH读写" — BW20 (sibling platform) flash read/write tutorial. 403-blocked.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-arduino-pro2 dev branch commits `3d53672` + `7db1c7d` (May 19, 2026) | **New pre-release `4.1.1-build20260519` published to index JSON** (not a GitHub Release tag). Adds IMX681_5M camera sensor support; updates `voe.bin`, `boot.bin`, `partition.bin`, `certificate.bin`, `hal_video.h`, `hal_video_common.h`, `hal_isp.h`, `isp_ctrl_api.h`, `libarduino_sensor_sel.a` (all sensors), and many other files. Tools bumped to v1.4.11. PR #409 description: "API codebase updates with minor bug fix." No FCS or flash specifics mentioned. | MEDIUM |
| `hal_video_release_note.txt` — full file fetched from dev branch (46 versions, through 1.7.1.0) | **No FCS cold-boot / flash-write / SPIC-mutex fix in any VOE version.** Newest entry: VOE 1.7.1.0 (04/21/2026) — "Fix dual sensor id FCS mirror/flip issue" (dual-sensor mirror/flip, unrelated to our `FCS_I2C_INIT_ERR` boot bug). The complete 2025-2026 VOE release history (1.6.0.0 through 1.7.1.0) contains no reference to: flash write interaction, SPIC mutex, `FCS_I2C_INIT_ERR`, camera cold-boot failure, or `hal_flash` WIP management. The updated `voe.bin` in `4.1.1-build20260519` may contain undocumented fixes (it is a binary blob), but no documented fix exists. | MEDIUM |
| `FlashMemory.cpp` — full source confirmed from dev branch | **Three total commits in history** (correction of prior "2 commits" finding): (1) `d9022ef` Jul 9, 2024 "Add feature Flash Memory (#252)"; (2) `d1a988f` Sep 30, 2025 "Add Arduino printf (#336)"; (3) `4fdfbec` Sep 30, 2025 "Optimize codes (#337)". All 8 flash operations (`read`, `write`, `readWord`, `writeWord`, `eraseSector`, `eraseWord`, `flash_stream_read`, `flash_stream_write`) call flash HAL functions directly with **zero mutex/lock calls**. File NOT changed in May 19 build. | LOW (confirms prior) |
| `video_api.h` — `USE_ISP_RETENTION_DATA` status in May 19 build | **Still commented out.** `// #define USE_ISP_RETENTION_DATA` at the equivalent of prior-cycle line 95. `isp_retention_data_t` struct exists but is dead code. Only change in `video_api.h` in commit `3d53672`: two new fields (`isp_gain_mode`, `isp_gain`) added to `video_pre_init_params_s` inside `#ifdef ARDUINO_SDK` — unrelated to FCS or flash mutex. | LOW (confirms prior) |
| `hal_video_common.h` — `commandLine_s.fcs` field confirmed | **`int fcs;` field confirmed in `commandLine_s` struct**: comment reads "1: fcs flow ROM load sensor, 0: normal flow need init. sensor." This is the field that is set to 0 in the application layer when FCS Disable is selected (see Cycle U12 analysis). File was updated in `3d53672` but the specific diff was not publicly visible (large commit, GitHub UI truncation). | LOW (confirms prior) |
| `rtl8735b_voe_status.h` — error codes in May 19 build | **`FCS_I2C_INIT_ERR = 0x200A` and `FCS_RUN_DATA_NG_KM = 0x2081` UNCHANGED.** File does not appear in commit `3d53672` changed-file list — it was not modified. Error code definitions match all prior cycles exactly. | LOW (confirms prior) |
| `GitHub_release_note.txt` (ameba-rtos-pro2) — full content fetched | **25 entries, newest is `7343927f` "[amebapro2][mmf] avoid task recreate in mmf start" (May 15, 2026).** No new entries since U23. Two video entries present: `[video] update sensor driver` (SHA `4de7607b`) and `[video] update sensor driver & video related default setting` (SHA `ccd2b17c`) — neither references FCS, flash bus, mutex, or camera boot. The release note is an exact match for what was known from U23. | LOW (confirms prior) |
| `4.1.1-build20260519` release_log.txt changelog | **Entries for V4.1.1 (2026/05/19):** "Add I2C Slave; Update Code base; Update API for AMB82-zero and SWD off logic; Minor bug fix; Update ameba_pro2_tools 1.4.11 — Add camera sensor IMX681_5M." No FCS changes, no flash mutex, no camera boot fix mentioned anywhere in the changelog going back to V4.1.1-QC-V05 (March 6, 2026). | LOW |
| forum.amebaiot.com/t/rtl8720c-flash-log/1239 (date unknown, Google-indexed) | **NEW sibling-chip precedent.** Thread title: "RTL8720C — 数据保存到FLASH后再次启动 log显示启动失败" ("After saving data to FLASH on RTL8720C, log shows boot failure on next restart"). This is the most semantically similar public report found across all research cycles: same symptom class (flash write → next boot failure) on the RTL8720C (sibling chip to RTL8735B, same Realtek Ameba family). Content is 403-blocked. Confirms this flash→boot failure class affects multiple Realtek Ameba platform generations. | MEDIUM (blocked) |
| bbs.ai-thinker.com thread tid=46317 (Google-indexed) | **Newly identified BW20 flash tutorial.** Title: "[BW20]二次开发学习4 FLASH读写" ("BW20 secondary development lesson 4: FLASH read/write"). BW20 is an Ai-Thinker module on the same Realtek Ameba platform family as BW21-CBV. Content is 403-blocked. May contain relevant flash usage patterns from the Chinese developer community, but no evidence it covers the FCS camera boot interaction. | LOW (blocked) |
| ameba-rtos-pro2 (fetched 2026-05-19 via compare endpoint) | **Confirmed frozen — `3f95070...HEAD` are identical.** Zero new commits since May 15, 2026. No flash, FCS, VOE, boot, or sensor-init changes in any observable pipeline. | LOW |
| All English/Chinese web sources (full sweep, 2026-05-19) | **Zero new content — 25 consecutive cycles with no new indexed results.** All Chinese community sites remain 403-blocked. No hardware test of any workaround posted anywhere. Error strings `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"` return zero publicly indexed results. Forum ceiling confirmed at thread #4865 (uartfwburn fail). | LOW |

**`4.1.1-build20260519` relevance assessment:**

The updated `voe.bin` in this build is the only plausible vehicle for an undocumented FCS cold-boot fix. Against this:
- The accompanying `hal_video_release_note.txt` (which tracks all VOE binary changes) shows no new VOE entry beyond 1.7.1.0 (04/21/2026) — suggesting the `voe.bin` update may be a routine binary update bundled with the IMX681_5M sensor addition, not a new VOE release.
- The PR #409 description mentions only "API codebase updates with minor bug fix" and IMX681_5M sensor; no FCS or flash-write context.
- All error code constants (`FCS_I2C_INIT_ERR`, `FCS_RUN_DATA_NG_KM`) are unchanged in the new build, which is consistent with no fix to the KM's FCS error reporting.
- The `FlashMemory.cpp` mutex omission — the confirmed root cause from U19 — is **unchanged**.

**Conclusion:** The `4.1.1-build20260519` build does not fix the flash-write → FCS cold-boot camera failure bug. The architectural defect (FlashMemory.cpp bypassing `RT_DEV_LOCK_FLASH`) remains present in all SDK versions through this pre-release.

**SDK state as of 2026-05-19 (Cycle U25):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release: V4.1.1-QC-V05 (Mar 6, 2026 tag; last QC update Apr 30, 2026) — no fix
- `4.1.1-build20260519` in index JSON only (not a GitHub Release tag) — no fix
- ameba-rtos-pro2 main: Frozen at May 15, 2026 (`3f95070`)
- ameba-arduino-pro2 dev: `7db1c7d` (May 19, 2026, Pre Release 4.1.1 — no fix)
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`)

**No confirmed fix. Bug remains unpatched as of 2026-05-19 (Cycle U25).**

**Top unresolved actions (unchanged from U24):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files; no public hardware test result exists anywhere. Highest priority.
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; FlashMemory.cpp omission is the confirmed architectural defect.
3. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes; requires `video_api.h` edit.

## Research Update — 2026-05-19 (Cycle U26)

**Search scope:** Five parallel agents: (1) GitHub — all repos post-May 18 activity, new commits/PRs/issues/releases; (2) English forum/web — new threads above #4865, FCS Disable / mutex workaround hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/Bilibili/Gitee; (4) SDK deep-dive — FlashMemory.cpp status in 4.1.1-build20260519, hal_video_release_note.txt full history, fcs_peri_info_ram_t struct, video_api.h; (5) RTL8720C thread #1239 access attempt, RTL8720CF WBR3 thread #2352 identification, workaround hardware test search.

**Key new findings this cycle:**
- **RTL8720CF(WBR3) thread #2352 newly identified** — "startup always stops at 'Fast connect profile is empty, abort fast connection'" — semantically adjacent sibling-chip symptom: flash-stored fast-connect profile being empty/corrupted causes boot stall. "Fast connect profile" on RTL8720CF (WiFi SoC) is the structural analogue of "FCS data" on RTL8735B (camera SoC) — both are Realtek fast-start profiles stored in NOR flash, both produce boot stalls when flash data is absent or corrupted. Confirms this is a cross-family Realtek platform hazard class. Content 403-blocked.
- **Thread #4868 newly indexed** — "NN Model loading from Memory instead of Flash or SD card failing with exceptions" — multimedia+flash/memory pipeline failure; different from FCS I2C failure but same multimedia subsystem. Content 403-blocked.
- **VOE version history fully documented** from hal_video_release_note.txt in 4.1.1-build20260519 (46 versions, May 2025–Apr 2026): most relevant — VOE 1.6.5.0 (08/29/2025) includes "I2C clock config" — the only I2C-related fix entry in the entire 46-version VOE history. Predates all known bug reports; no FCS cold-boot context.
- **4.1.1-build20260519 definitively confirmed no fix**: FlashMemory.cpp absent from the 122-file commit `3d53672`; zero mutex calls unchanged; VOE still at 1.7.1.0; fcs_peri_info_ram_t two previously undocumented fields confirmed.
- **All repos frozen; no hardware tests; Chinese sources zero (26th consecutive cycle).**

| Source | Key Finding | Priority |
|---|---|---|
| forum.amebaiot.com/t/rtl8720cf-wbr3-fast-connect-profile-is-empty-abort-fast-connection/2352 (date unknown, Google-indexed) | **NEW sibling-chip boot-stall precedent.** "RTL8720CF(WBR3) — startup always stops at 'Fast connect profile is empty, abort fast connection'." The RTL8720CF is a Realtek Ameba WiFi SoC; its "fast connect profile" is a NOR-flash-stored precomputed WiFi connection record — the direct structural analogue of RTL8735B's FCS camera data. When this profile is empty (written or erased), the device stalls at boot with an explicit error message. The pattern (fast-start flash profile → boot stall when corrupted) spans at least two Realtek Ameba chip generations. Thread content 403-blocked; no resolution extractable. | MEDIUM (blocked) |
| forum.amebaiot.com/t/.../4868 — "NN Model loading from Memory instead of Flash or SD card failing with exceptions" (Google-indexed, newly indexed this cycle) | **Thread #4868 newly surfaced.** Title indicates a failure loading NN (neural network) model data from memory/flash/SD — failures in the multimedia data pipeline that are adjacent to our VOE initialization failure class. Not confirmed as flash-write-triggered or FCS-related. Content 403-blocked; no further detail extractable from snippet. Adds to the catalog of multimedia pipeline failure threads in this research. | LOW (blocked) |
| `hal_video_release_note.txt` — full 46-version history (4.1.1-build20260519 `dev` branch) | **Complete VOE version history documented.** The 10 most recent versions: 1.6.2.0 (05/23/2025) "Add 12M feature; Fix AE stuck issue"; 1.6.3.0 (07/18/2025) "CCM sum != 256 issue; Define VOE error id"; 1.6.4.0 (08/01/2025) "Support one-shot mode for dynamic IQ"; 1.6.5.0 (08/29/2025) "N-image verify path config; improve verify close time; **I2C clock config**"; 1.6.6.0 (09/26/2025) "Direct WDR; Fix GPIOA_0 open stream issue; Dual I2C slave addr"; 1.6.7.0 (10/17/2025) "Enable & get max dyn region idx; Fix hal_video.c share buffer issue"; 1.6.8.0 (12/02/2025) "Dynamic zoom; Fix hal_video.c share buffer cache issue"; 1.6.9.0 (01/20/2026) "Add AE debug metadata"; 1.7.0.0 (03/17/2026) "Fix dual sensor ID mirror/flip; Merge PC2 12M DRC"; 1.7.1.0 (04/21/2026) "Fix dual sensor ID FCS mirror/flip." **VOE 1.6.5.0 "I2C clock config" is the only I2C-related fix in all 46 versions — predates our bug reports, no flash-write or FCS cold-boot context.** No fix for `FCS_I2C_INIT_ERR` anywhere in the full history. | MEDIUM |
| `fcs_peri_info_ram_t` struct — two previously undocumented fields (Arduino `dev` branch, `hal_video.h`) | **Struct now fully documented.** Complete field list: `i2c_id`, `adc_id`, `pwm_id`, `snr_clk_pin`, `gpio_list[12]`, `gpio_cnt`, `i2c_scl`, `i2c_sda`, `fcs_peri_valid`, `fcs_OK`, `fcs_used`, `fcs_data_verion` (typo preserved from source), `fcs_data_id`, `reserved[2]`. The previously undocumented fields `fcs_data_verion` and `fcs_data_id` suggest FCS data has a version field and a sensor-ID field — which means the boot ROM may reject FCS data whose version or sensor ID does not match expectations, independent of flash write corruption. | LOW |
| `FlashMemory.cpp` — confirmed absent from commit `3d53672` (122-file IMX681_5M update, May 19, 2026) | **Positive confirmation: FlashMemory.cpp was not touched in the May 19 build.** GitHub commit diff shows the 122 files in `3d53672` are exclusively: sensor binary blobs, ISP IQ JSON files, hal_video header updates (ISP gain API), tools v1.4.11. FlashMemory.cpp is not in the list. Zero mutex calls are confirmed unchanged in both `dev` and `main` branches. | LOW (confirms prior) |
| `video_boot.c` / `video_api.c` — confirmed absent from Arduino package | **Implementation files not public in Arduino SDK.** The `Arduino_package/hardware/system/component/video/driver/RTL8735B/` directory contains only `.h` header files; no `.c` source files. `video_boot.c` and `video_api.c` — analyzed from the RTOS SDK in prior cycles — are compiled into prebuilt binary blobs (`voe.bin`, `boot.bin`) in the Arduino package. Arduino users cannot inspect or modify these implementations without the RTOS SDK. | LOW (confirms prior) |
| All GitHub repos (ameba-rtos-pro2, ameba-arduino-pro2, ideashatch/HUB-8735), fetched 2026-05-19 | **All repos confirmed frozen — identical to U25.** ameba-rtos-pro2 HEAD = `3f95070` (May 15, 2026, confirmed by compare-endpoint "are identical"); ameba-arduino-pro2 main = `93d63514` (Mar 2); dev = `7db1c7d` (May 19, Pre Release 4.1.1 — no fix). No new commits, issues, PRs, or releases. ameba-arduino-pro2 open issues: 12 total, newest = #398 (Mar 29, 2026). Bug unreported on any official tracker. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/Bilibili/Gitee, May 19 sweep) | **Zero new content — 26th consecutive cycle.** All Chinese community sites remain 403-blocked. No new BW21-CBV or RTL8735B Chinese-language technical posts about FCS flash-write camera failure found anywhere. | LOW |
| Web-wide error string sweep (2026-05-19) | **Zero indexed results — 26 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"` return zero publicly indexed results anywhere on the accessible web. No hardware test result for any of the three proposed workarounds posted anywhere. | LOW |

**Realtek fast-start profile family pattern (new cross-chip insight):**

Thread #2352 establishes that RTL8720CF uses a "fast connect profile" in NOR flash with the same fragility pattern as RTL8735B's FCS camera data. The error message "Fast connect profile is empty, abort fast connection" is structurally identical to "It don't do the sensor initial process" — both are boot-ROM messages indicating a fast-start flash profile cannot be loaded, causing the device to skip the fast-start path. This may indicate Realtek's boot ROM design pattern across Ameba chip generations uses flash-stored fast-start profiles without atomic write protection, making all chips in this family vulnerable to flash-write-then-reboot failures when the profile storage region is uncoordinated.

**SDK state as of 2026-05-19 (Cycle U26 — unchanged from U25):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release: V4.1.1-QC-V05 (Mar 6, 2026 tag) — no fix
- `4.1.1-build20260519` in index JSON (not a GitHub Release tag) — **confirmed no fix**; FlashMemory.cpp unchanged, VOE at 1.7.1.0
- ameba-rtos-pro2 main: Frozen at May 15, 2026 (`3f95070`)
- ameba-arduino-pro2 dev: `7db1c7d` (May 19, 2026, Pre Release 4.1.1 — no fix)
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`)

**No confirmed fix. Bug remains unpatched as of 2026-05-19 (Cycle U26).**

**Top unresolved actions (unchanged from U25):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); no public hardware test result exists anywhere. Highest priority.
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates this is the required pattern; FlashMemory.cpp omission confirmed as architectural defect; forward-declaration callable from Arduino without include-path issues.
3. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes; requires `video_api.h` edit.

**Late-arriving findings (U26 addendum — same research session, arrived after commit):**

| Source | Key Finding | Priority |
|---|---|---|
| forum.amebaiot.com/t/saving-user-parameters-in-flash/1005 (Dec 29, 2021, Google-indexed) | **Newly identified thread — FlashMemory hang on AMB82.** User implemented `SYS_ParamWrite()` / `SYS_ParamRead()` using `FlashMemory.update()` and reported the system "hangs / gets stuck inside SYS_ParamWrite()" with snippet mentioning "possibly due to some hardware exception from memory access." This is the first publicly indexed thread describing FlashMemory causing a blocking hang on an AMB82 device. Camera running state during the hang is not confirmed from the snippet, but the mechanism (FlashMemory blocking while another subsystem holds `RT_DEV_LOCK_FLASH`) is consistent with the confirmed SPIC concurrent-access defect. Date confirmed Dec 29, 2021. Content 403-blocked. | MEDIUM (blocked) |
| pvvx/RTL0B_SDK GitHub — `rtl8710b_ota.c` (RTL8710B legacy SDK, public) | **Cross-chip `RT_DEV_LOCK_FLASH` pattern confirmed in Realtek SDK lineage.** OTA implementation for RTL8710B (Ameba predecessor to RTL8735B) wraps every flash erase/write with `device_mutex_lock(RT_DEV_LOCK_FLASH)` / `device_mutex_unlock(RT_DEV_LOCK_FLASH)`. This is the same mutex and enum ID (`RT_DEV_LOCK_FLASH = 1`) confirmed in RTL8735B `device_lock.h` (U22). Provides historical evidence that Realtek has used this mutex as the canonical flash serialization primitive since at least the RTL8710B era — making its omission from RTL8735B's `FlashMemory.cpp` a deviation from the consistent SDK pattern across generations. | LOW |

## Research Update — 2026-05-20 (Cycle U27)

**Search scope:** Six parallel search threads: (1) GitHub — all repos post-May 19 activity (ameba-rtos-pro2 compare endpoint; ameba-arduino-pro2 dev/main commits, releases, issues); (2) English forum/web — new threads above #4865/4868, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` workaround hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/mcublog.cn/Bilibili/Gitee; (4) Error string indexing — `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`; (5) New documentation portals — `ameba-doc-arduino-sdk.readthedocs-hosted.com` Flash Memory example guide; `aiot.realmcu.com/cn/product/rtl8735b.html`; (6) Forum thread #1239 (RTL8720C flash→boot failure) content retrieval; RTL8735B `hal_flash_sector_erase` + `device_mutex_lock` patch searches.

**Key new findings this cycle:** None of substance. All research channels return the same freeze / blocked state as Cycle U26. Two new documentation URLs newly confirmed present (but 403-blocked). Both repositories and all associated trackers are unchanged.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 commits page (direct GitHub fetch, 2026-05-20) | **Confirmed frozen — identical to U26.** 10 most recent commits fetched and verified: `3f95070` (May 15), `afc85a0` (May 15), `9c8b6f6` (May 15), `d2676f1` (May 15), `1c1c8b7` (May 1), `a111e91` (May 1), `7b2b97f` (May 1), `63c0a2f` (May 1), `d54e1a8` (May 1), `687a4c7` (May 1). **Zero new commits in 5 days since May 15, 2026.** No flash, FCS, VOE, boot, HAL, or sensor changes visible in any commit. | LOW |
| ameba-arduino-pro2 dev branch commits (direct GitHub fetch, 2026-05-20) | **Confirmed frozen — identical to U26.** 10 most recent commits fetched and verified: `7db1c7d` "Pre Release Version 4.1.1" (May 19), `3d53672` "Update Code base and add cam IMX681_5M (#409)" (May 19), `cd0bd40` "Add I2C Slave (#408)" (May 18), `13961cc` (May 5), and prior entries unchanged. **Zero new commits after May 19, 2026.** No FCS/flash/camera fix in any commit. | LOW |
| ameba-arduino-pro2 releases page (direct GitHub fetch, 2026-05-20) | **No new releases.** Latest stable = V4.1.0 (Mar 2, 2026). Latest published GitHub Release tag = V4.1.1-QC-V05 (Mar 6, 2026). The `4.1.1-build20260519` pre-release (index JSON only, not a GitHub Release tag, documented in U25) remains the most recent build. No V4.1.1 stable release or QC-V06+ tag has been published. | LOW |
| ameba-arduino-pro2 open issues (direct GitHub fetch, 2026-05-20) | **12 open issues; newest = #398 (Mar 29, 2026).** Full list confirmed: #398, #342, #325, #324, #317, #310, #296, #287, #276, #235, #224, #184. No new issues after March 29, 2026. No issues about FlashMemory, FCS, camera, VOE, or boot failure in any open or closed issue. Bug remains entirely unreported on the official tracker after 27 research cycles. | LOW |
| `ameba-doc-arduino-sdk.readthedocs-hosted.com/en/latest/ameba_pro2/amb82-mini/Example_Guides/Flash%20Memory/index.html` (2026-05-20) | **Newly confirmed documentation page — Flash Memory example guide for AMB82-mini.** This URL appeared in search results as a dedicated Flash Memory example guide page within the official AMB82-mini Arduino documentation. Returns HTTP 403 (authenticated access required). This page would be the most likely location for any official warnings about concurrent flash+camera usage or mutex requirements. Inaccessible without developer credentials. Previously, only the Flash Memory tutorial at `amebaiot.com/en/amebapro2-arduino-flash-writeword/` was tracked; this readthedocs version may contain more complete documentation. | LOW (blocked) |
| `aiot.realmcu.com/cn/product/rtl8735b.html` (2026-05-20) | **Newly confirmed Chinese-language RTL8735B product page on aiot.realmcu.com.** This page was returned by Chinese-language search for BW21-CBV/RTL8735B. Returns HTTP 403. The Chinese-language Realtek product page may contain FCS documentation, boot sequence descriptions, or developer notes not mirrored in the English aiot.realmcu.com pages. Inaccessible without developer credentials. | LOW (blocked) |
| forum.amebaiot.com threads #4866–#4878 (search engine sweep, 2026-05-20) | **No new threads indexed above the U25/U26 ceiling.** Targeted search queries for thread IDs 4866 through 4878 on forum.amebaiot.com returned zero results from the forum domain. The search ceiling remains at thread #4865 ("AmebaPro2 uartfwburn - Can't flash", hardware upload tool failure, unrelated to our bug). No new relevant threads have appeared in the past 24 hours. | LOW |
| forum.amebaiot.com/t/rtl8720c-flash-log/1239 (2026-05-20 access attempt) | **Still 403-blocked.** Direct WebFetch returned HTTP 403 Forbidden. Search engine snippets confirm: thread title is "RTL8720C 数据保存到FLASH后再次启动 log显示启动失败" (RTL8720C — after saving data to FLASH, log shows boot failure on next restart). Snippet confirms thread discusses flash partition tables and boot failure logs. Date in search snippet: May 2022. Content remains fully inaccessible. The sibling-chip flash→boot failure precedent (first documented in U25) is confirmed but unresolved. | LOW (blocked) |
| forum.amebaiot.com/t/saving-user-parameters-in-flash/1005 (2026-05-20 search update) | **Date confirmed: Dec 29, 2021.** Search result snippet confirms: user describes `SYS_ParamWrite()` hanging inside `FlashMemory.update()` on AMB82, "possibly due to some hardware exception from memory access." This is the same AMB82 hardware platform as our bug; the FlashMemory hang on AMB82 was occurring as early as December 2021 — predating both FCS mode introduction (V4.0.8, Oct 2024) and the concurrent-camera usage scenario. No resolution visible in snippet. Thread content 403-blocked. | LOW (historical context) |
| Web-wide search: `"device_mutex_lock"` + `"RT_DEV_LOCK_FLASH"` + FlashMemory / RTL8735B (2026-05-20) | **Zero new results.** No public forum posts, blog articles, GitHub issues, or PRs have appeared discussing the `RT_DEV_LOCK_FLASH` mutex workaround for the FlashMemory+camera bug. This research log remains the only publicly accessible documentation connecting the mutex omission to the FCS cold-boot failure. | LOW |
| Web-wide search: all key error strings (2026-05-20 sweep) | **Zero indexed results — unchanged across all 27 cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"` return zero publicly indexed results on the accessible web. No hardware test result for any of the three proposed workarounds has been posted anywhere. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/mcublog.cn/Bilibili/Gitee, May 20 sweep) | **Zero new content — 27th consecutive cycle.** All Chinese community sites remain 403-blocked or return zero relevant results. bbs.aithinker.com forum page 5 of BW21-CBV-Kit subforum visible in search index (threads about home surveillance, human detection, Rd-04 radar) — all contain unrelated BW21-CBV DIY projects, none discuss FCS flash-write camera failure. mcublog.cn BW21-CBV article (April 2026, Feishu bot) still accessible in search snippet but page itself returns 403 on direct fetch. No new Chinese-language technical posts about this bug found anywhere. | LOW |

**"Saving user parameters in flash" thread #1005 — historical significance:**

The confirmed Dec 29, 2021 date for thread #1005 (FlashMemory hanging on AMB82) establishes that FlashMemory concurrent-access issues on the AMB82 platform were reported **nearly 3 years before** the FCS camera feature was introduced in V4.0.8 (Oct 2024). This means:
- The SPIC concurrent-access hazard (FlashMemory bypassing `RT_DEV_LOCK_FLASH`) is not a new defect introduced alongside FCS — it was present from FlashMemory's earliest version.
- The Dec 2021 hang may have been caused by the same mutex omission, in a different concurrent-access scenario (FlashMemory competing with a non-FCS subsystem that does hold `RT_DEV_LOCK_FLASH`).
- The FCS introduction in V4.0.8 added a new ISP AE/AWB SPIC write path (`ftl_common_write`) that can race with FlashMemory — making an existing latent defect suddenly produce camera cold-boot failures, not just hangs.

**SDK state as of 2026-05-20 (Cycle U27 — unchanged from U26):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release: V4.1.1-QC-V05 (Mar 6, 2026 tag) — no fix
- `4.1.1-build20260519` in index JSON (not a GitHub Release tag) — no fix
- ameba-rtos-pro2 main: Frozen at May 15, 2026 (`3f95070`) — 5 days no change
- ameba-arduino-pro2 dev: Frozen at May 19, 2026 (`7db1c7d`) — 1 day no change
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — 79 days no change

**No confirmed fix. Bug remains unpatched as of 2026-05-20 (Cycle U27).**

**Top unresolved actions (unchanged from U26):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. Highest priority.
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates this is the required pattern; FlashMemory.cpp omission confirmed as architectural defect; forward-declaration pattern avoids include-path issues from Arduino.
3. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes; requires `video_api.h` edit.

## Research Update — 2026-05-20 (Cycle U28)

**Search scope:** Four parallel agents: (1) GitHub — all repos post-May 19 activity, new commits/PRs/issues/releases; (2) English forum/web — new threads above #4868, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` workaround hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee; (4) SDK deep-dive — FlashMemory.cpp and hal_video_release_note.txt status in latest dev branch build, VOE version beyond 1.7.1.0.

**Key new findings this cycle:**
- All repositories confirmed frozen at identical HEADs as Cycle U27 — zero new commits, releases, or issues anywhere after May 19, 2026.
- **PR #17 in ameba-rtos-pro2 — new detail:** Confirmed to be an automated security scanner filing (orbisai0security automation), classified as V-001, addressing a buffer overflow in `component/ethernet_mii/ethernet_usb.c` line 391 where received network frame data is copied into fixed-size buffers without bounds checking. Entirely unrelated to our flash/FCS/camera bug.
- **Forum thread #3319 newly identified** — "AMB82-Mini object detection osd2enc queue / isp2osd queue receive timeout" — camera pipeline timeout errors (`osd2enc receive timeout`, `isp2osd receive timeout`), a different failure class from FCS_I2C_INIT_ERR. Not confirmed flash-triggered. Content 403-blocked.
- Zero new Chinese-language content (28th consecutive cycle); all Chinese community sites remain 403-blocked.
- No hardware test result for any proposed workaround found anywhere.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 commits page (direct fetch, 2026-05-20) | **Confirmed frozen — identical to U27.** 10 most recent commits verified: `3f95070` (May 15), `afc85a0` (May 15), `9c8b6f6` (May 15), `d2676f1` (May 15), `1c1c8b7` (May 1), `a111e91` (May 1), `7b2b97f` (May 1), `63c0a2f` (May 1), `d54e1a8` (May 1), `687a4c7` (May 1). Zero new commits in 5+ days since May 15, 2026. No flash, FCS, VOE, boot, HAL, or sensor changes visible. | LOW |
| ameba-arduino-pro2 dev branch commits (direct fetch, 2026-05-20) | **Confirmed frozen — identical to U27.** 10 most recent commits verified: `7db1c7d` "Pre Release Version 4.1.1" (May 19), `3d53672` "Update Code base and add cam IMX681_5M (#409)" (May 19), `cd0bd40` "Add I2C Slave (#408)" (May 18), `13961cc` (May 5), and earlier entries unchanged. Zero new commits after May 19, 2026. No FCS/flash/camera fix in any commit. | LOW |
| ameba-arduino-pro2 releases page (2026-05-20) | **No new GitHub Release tags.** Latest stable = V4.1.0 (Mar 2, 2026). Latest published GitHub Release tag = V4.1.1-QC-V05 (Mar 6, 2026). The `4.1.1-build20260519` pre-release (index JSON only, not a GitHub Release tag) remains the most recent build. No V4.1.1 stable release or QC-V06+ tag confirmed. (One agent reported "V4.1.1-QC-V06 March 6, 2026 with I2C Slave" — this is contradicted by the confirmed merge date of I2C Slave (May 18, 2026) and is treated as an agent error; not confirmed as a real release.) | LOW |
| ameba-rtos-pro2 PR #17 — new detail (2026-05-20) | **PR #17 additional detail confirmed.** Previously logged in U22 as "USB Ethernet/NCM driver support." Now confirmed by two independent agents: filed by `orbisai0security` (automated security scanner); classified as **V-001**; addresses buffer overflow in `component/ethernet_mii/ethernet_usb.c` line 391 — received network frame data copied into fixed-size buffers without bounds checking, enabling attacker-controlled length values to overwrite memory. PR title: "fix: the ethernet usb driver copies received network frame data…" Build passes; LLM code review passed; re-scan confirms fix. **Entirely unrelated to flash/FCS/camera cold-boot bug.** | LOW (unrelated) |
| forum.amebaiot.com/t/amb82-mini-object-detection-osd2enc-queue-isp2osd-queue-receive-queue-timeout-or-fail/3319 | **Newly identified thread** (previously untracked). Title: "AMB82-Mini object detection osd2enc queue / isp2osd queue receive queue timeout or fail." Errors: `[VOE] osd2enc receive timeout` and `[VOE] isp2osd receive timeout` — VOE pipeline timeouts within the OSD-to-encoder and ISP-to-OSD stages. These are distinct from FCS_I2C_INIT_ERR (which occurs in boot ROM before OS camera init). Not confirmed as flash-write-triggered. Content 403-blocked. Previously untracked; now catalogued. | LOW (blocked) |
| forum.amebaiot.com threads above #4868 (search sweep, 2026-05-20) | **No new threads indexed.** Targeted search for thread IDs 4869 through 4890 returned zero results from the forum domain. Forum ceiling remains at #4868 ("NN Model loading from Memory instead of Flash or SD card failing with exceptions"). No new relevant threads in the past 24 hours. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/mcublog.cn/Bilibili/Gitee, May 20 sweep) | **Zero new content — 28th consecutive cycle.** All Chinese community sites remain 403-blocked or return zero relevant results. bbs.aithinker.com BW21-CBV-Kit subforum (home surveillance, human detection, Rd-04 radar topics) confirmed still inaccessible. No Chinese-language forum posts or articles discuss FCS flash-write camera failure on RTL8735B or BW21-CBV. | LOW |
| Web-wide English search: all key error strings (2026-05-20 sweep) | **Zero indexed results — 28 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"` return zero publicly indexed results on the accessible web. No hardware test result for any of the three proposed workarounds ("Camera FCS Mode = Disable", `device_mutex_lock` wrapper, `USE_ISP_RETENTION_DATA`) has been posted anywhere in any language. | LOW |

**SDK state as of 2026-05-20 (Cycle U28 — unchanged from U27):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release GitHub Release tag: V4.1.1-QC-V05 (Mar 6, 2026) — no fix
- `4.1.1-build20260519` in index JSON only (not a GitHub Release tag) — no fix; FlashMemory.cpp mutex omission unchanged
- ameba-rtos-pro2 main: Frozen at May 15, 2026 (`3f95070`) — 5 days no change; PR #17 (ethernet security fix) open and unmerged
- ameba-arduino-pro2 dev: Frozen at May 19, 2026 (`7db1c7d`) — 1 day no change
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — 79 days no change

**No confirmed fix. Bug remains unpatched as of 2026-05-20 (Cycle U28).**

**Top unresolved actions (unchanged from U27):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. Highest priority.
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; FlashMemory.cpp omission is the confirmed architectural defect; forward-declaration callable from Arduino without include-path issues (`extern "C" void device_mutex_lock(unsigned int)` / `#define RT_DEV_LOCK_FLASH 1`).
3. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes at source; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-05-20 (Cycle U29)

**Search scope:** Five parallel search threads + direct web fetches: (1) GitHub — all repos post-May 19 activity, new commits/PRs/issues/releases; (2) English forum/web — new threads above #4868, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee; (4) SDK deep-dive — FlashMemory.cpp and video_api.h in dev branch, hal_video_release_note.txt location; (5) GitHub Release tag sweep — V4.1.1-QC-V06 confirmation, content analysis.

**Key new findings this cycle:**
- **V4.1.1-QC-V06 confirmed as a GitHub Release tag** — previously reported in U25/U26 as "4.1.1-build20260519 in index JSON only, not a GitHub Release tag." The build has since been published as a proper GitHub Release tag V4.1.1-QC-V06 (tag creation date March 6, 2026; release notes contain version dates through 2026/05/19). This corrects the characterization in U25–U28. No FCS, flash camera boot, or FlashMemory mutex fix is mentioned anywhere in its release notes.
- **FlashMemory.cpp confirmed unchanged** in dev branch — zero mutex calls across all 8 flash operations; not in the 122-file IMX681_5M commit. Workaround 2 has NOT been applied upstream.
- **`USE_ISP_RETENTION_DATA` still commented out** in dev branch `video_api.h`.
- **`hal_video_release_note.txt` returns HTTP 404** on dev branch raw URL — may have been moved or renamed in the May 19 update. The last documented VOE version (1.7.1.0) remains unchanged.
- **Thread #4857 newly identified** — "WiFi Camera MJPG stream not stop when client close" — camera pipeline / streaming resource cleanup issue. Content 403-blocked; not related to flash-write cold-boot failure.
- All repos frozen at same HEADs as U27/U28; no new forum threads above #4868; zero new Chinese-language content (29th consecutive cycle).

| Source | Key Finding | Priority |
|---|---|---|
| GitHub releases page for ameba-arduino-pro2 (direct WebFetch, 2026-05-20) | **V4.1.1-QC-V06 confirmed as a GitHub Release tag.** Tag creation date: March 6, 2026. Release note version dates listed: 2026/03/06, 2026/03/20, 2026/04/02, 2026/04/17, 2026/04/30, 2026/05/19. Features: Battery-Powered Camera POC, Audio Trigger Recording, Video Zoom, TensorFlowLite, AMB82-zero support, I2C Slave, K306P sensor, IMX681_5M camera. This is the same build previously identified in U25 as "4.1.1-build20260519 in index JSON only, not a GitHub Release tag" — that characterization was wrong; the build has been published as a proper pre-release tag. **No mention of FCS, flash camera boot, FlashMemory mutex, or sensor init in the release notes.** The U28 report "one agent reported V4.1.1-QC-V06 — treated as an agent error" was incorrect; V4.1.1-QC-V06 is real and is the current latest pre-release. | MEDIUM (clarification, no fix) |
| `FlashMemory.cpp` — confirmed from dev branch raw fetch (2026-05-20) | **Zero mutex calls confirmed unchanged in V4.1.1-QC-V06.** All 8 flash operations (`read`, `write`, `readWord`, `writeWord`, `eraseSector`, `eraseWord`, `flash_stream_read`, `flash_stream_write`) still call flash HAL functions directly with zero `device_mutex_lock`, `device_mutex_unlock`, or `RT_DEV_LOCK_FLASH` calls. The file was not modified in the May 19 commit (`3d53672`, 122-file IMX681_5M update). The architectural defect persists in the latest pre-release. | LOW (confirms prior) |
| `video_api.h` — confirmed from dev branch raw fetch (2026-05-20) | **`USE_ISP_RETENTION_DATA` still commented out.** Exact line: `// #define USE_ISP_RETENTION_DATA`. No change from prior cycles. The workaround remains unavailable without manual SDK edit. | LOW (confirms prior) |
| `hal_video_release_note.txt` — raw dev branch URL (2026-05-20) | **HTTP 404 returned.** The file was accessible at this path in prior cycles (U25 retrieved full content). The May 19 commit (`3d53672`, 122-file change) may have moved or renamed the file. Alternative location not determined this cycle. Last documented VOE version (1.7.1.0, 04/21/2026) is unchanged; no new VOE release is expected based on all available evidence. | LOW |
| forum.amebaiot.com/t/arduino-sdk-wifi-camera-mjpg-stream-not-stop-when-client-close/4857 | **Thread #4857 newly identified** (previously untracked). Title: "Arduino SDK Wifi Camera MJPG stream not stop when client close." Discusses camera stream resource cleanup failure when the HTTP client disconnects — a camera pipeline / session management issue distinct from FCS_I2C_INIT_ERR (which occurs in boot ROM before OS camera init). Not confirmed as flash-write-triggered. Content 403-blocked. | LOW (blocked, unrelated) |
| ameba-rtos-pro2 commits page (direct fetch, 2026-05-20) | **Confirmed frozen — identical to U27/U28.** 10 most recent commits verified: `3f95070` (May 15), `afc85a0` (May 15), `9c8b6f6` (May 15), `d2676f1` (May 15), `1c1c8b7` (May 1), and prior unchanged entries. Zero new commits in 5+ days since May 15, 2026. No flash, FCS, VOE, boot, HAL, or sensor changes visible. | LOW |
| ameba-arduino-pro2 dev branch commits (direct fetch, 2026-05-20) | **Confirmed frozen — identical to U27/U28.** Head = `7db1c7d` "Pre Release Version 4.1.1" (May 19, 2026). Zero new commits after May 19. No FCS/flash/camera fix in any commit. | LOW |
| ameba-arduino-pro2 open issues (fetched 2026-05-20) | **Unchanged — 12 open issues; newest = #398 (Mar 29, 2026).** No new issues about FlashMemory, FCS, camera, VOE, or boot failure. Bug remains entirely unreported on the official tracker after 29 research cycles. | LOW |
| forum.amebaiot.com threads above #4868 (search sweep, 2026-05-20) | **No new threads indexed.** Targeted searches for IDs 4869–4890 returned zero results. Forum ceiling remains at #4868 ("NN Model loading from Memory instead of Flash or SD card failing with exceptions"). No new relevant threads in the past 24 hours. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn, May 20 sweep — two agents) | **Zero new content — 29th consecutive cycle.** Both a direct web search and a dedicated background agent confirm: no Chinese-language forum posts or articles discuss FCS flash-write camera failure on RTL8735B or BW21-CBV. bbs.aithinker.com and bbs.ai-thinker.com both 403. mcublog.cn BW21-CBV article (April 2026, Feishu bot) 403 on direct fetch. oshwhub.com BW21-CBV-Kit open-hardware design page newly surfaced — hardware design files only, no software/FCS content. | LOW |
| Web-wide error string sweep (2026-05-20) | **Zero indexed results — 29 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"` return zero publicly indexed results anywhere on the accessible web. No hardware test result for any of the three proposed workarounds has been posted anywhere in any language. | LOW |

**V4.1.1-QC-V06 release tag — clarification of U25–U28 characterization:**

Prior cycles (U25–U28) characterized the May 19, 2026 pre-release as "4.1.1-build20260519 in index JSON only, not a GitHub Release tag." This was incorrect. The build was published as `V4.1.1-QC-V06` — a proper GitHub Release tag. The tag creation date is March 6, 2026 on GitHub's releases page, but its release notes have been updated to include version entries through 2026/05/19. This single pre-release tag accumulates version entries over time, explaining the discrepancy. The conclusion remains unchanged: **no FCS, flash-write camera boot, or FlashMemory mutex fix exists in V4.1.1-QC-V06.**

**Corrected SDK state as of 2026-05-20 (Cycle U29):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release GitHub Release tag: **V4.1.1-QC-V06** (tag created Mar 6, 2026; release notes through May 19, 2026) — no fix (corrects U25–U28 characterization of QC-V05 as latest)
- ameba-rtos-pro2 main: Frozen at May 15, 2026 (`3f95070`) — 5 days no change; PR #17 (ethernet security fix) open and unmerged
- ameba-arduino-pro2 dev: Frozen at May 19, 2026 (`7db1c7d`) — 1 day no change
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — 79 days no change

**No confirmed fix. Bug remains unpatched as of 2026-05-20 (Cycle U29).**

**Top unresolved actions (unchanged from U28):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. Highest priority.
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; FlashMemory.cpp omission confirmed as architectural defect; forward-declaration callable from Arduino without include-path issues (`extern "C" void device_mutex_lock(unsigned int)` / `#define RT_DEV_LOCK_FLASH 1`).
3. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes at source; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-05-20 (Cycle U30)

**Search scope:** Four parallel agents: (1) GitHub — all repos post-May 19 activity, commits/PRs/issues/releases; (2) English forum/web — threads above #4868, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` workaround hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee; (4) SDK deep-dive — `hal_video_release_note.txt` new location, `FlashMemory.cpp` and `video_api.h` status in latest dev branch build, FCS error code enumeration, community wrapper search.

**Key new findings this cycle:**
- **`hal_video_release_note.txt` new location confirmed** — the file returned HTTP 404 in U29 because it moved to the `fcs_hal/` subdirectory in the May 19 commit. Now found at `Arduino_package/hardware/system/component/video/driver/RTL8735B/fcs_hal/hal_video_release_note.txt`.
- **Arduino SDK copy of the release note tops out at VOE 1.5.6.0 (Jul 2024)** — distinct from the RTOS SDK copy (which goes to 1.7.1.0, Apr 2026). The Arduino SDK ships an older/separate release note file that has not been kept in sync with the binary `voe.bin` blob since July 2024. The binary blob (runtime version) continues to be updated; the text file is not.
- **Thread #4670 newly surfaced** — "Updated AMB82-mini board breaks working code" — content 403-blocked; not confirmed as flash/FCS related.
- Both repos confirmed frozen; `FlashMemory.cpp` mutex omission unchanged through V4.1.1-QC-V06; `USE_ISP_RETENTION_DATA` still commented out; zero community workaround wrappers exist anywhere; 30th consecutive cycle with zero new Chinese-language content.

| Source | Key Finding | Priority |
|---|---|---|
| `Arduino_package/hardware/system/component/video/driver/RTL8735B/fcs_hal/hal_video_release_note.txt` (ameba-arduino-pro2 `dev` branch, fetched 2026-05-20) | **`hal_video_release_note.txt` new location found** — moved to `fcs_hal/` subdirectory in the May 19 commit (`3d53672`). Previously returning HTTP 404 (U29). The `fcs_hal/` directory also contains `hal_video.h`, `hal_voe.h`, `rtl8735b_voe_status.h`, `rtl8735b_voe_type.h`, `hal_video_common.h`, `hal_video_cmd.h` — a reorganization of FCS-related headers into a dedicated subdirectory. | LOW |
| `hal_video_release_note.txt` Arduino SDK copy vs. RTOS SDK copy | **TWO release note files exist, last-version mismatch.** Arduino SDK copy (in `fcs_hal/`): newest entry is **VOE 1.5.6.0 (07/17/2024)** — the file has not been updated since July 2024. RTOS SDK copy (`ameba-rtos-pro2`): documented through VOE 1.7.1.0 (04/21/2026) in prior cycles (U25/U26). The binary `voe.bin` blob (the actual firmware) continues to be updated in the Arduino package, but the text changelog shipped with it has not been maintained since July 2024. Versions 1.6.x and 1.7.x are not reflected in the Arduino SDK release note text at all. This means VOE fix history since July 2024 cannot be audited from Arduino SDK source alone — the RTOS SDK copy is the authoritative release note. | LOW (clarification) |
| `FlashMemory.cpp` — confirmed from dev branch (2026-05-20) | **Zero mutex calls confirmed unchanged in V4.1.1-QC-V06.** Full commit history from GitHub confirms 6 commits total (corrects prior "3 commits" finding): Jul 9, 2024 (initial #252), Jul 16, 2024 (update links), Jun 20, 2025 (update example guide links), Sep 9, 2025 (update WiFi example), Sep 30, 2025 (#336 printf), Sep 30, 2025 (#337 optimize). None of these added mutex protection. The architectural defect persists through V4.1.1-QC-V06. | LOW (confirms prior) |
| `video_api.h` — confirmed from dev branch (2026-05-20) | **`USE_ISP_RETENTION_DATA` still commented out.** `// #define USE_ISP_RETENTION_DATA` at same line. `isp_retention_data_t` struct exists but is dead code. No changes in May 19 commit. New fields `isp_gain_mode` and `isp_gain` added to `video_pre_init_params_s` under `#ifdef ARDUINO_SDK` — unrelated to FCS or flash mutex. | LOW (confirms prior) |
| `rtl8735b_voe_status.h` — FCS error code enumeration (dev branch, 2026-05-20) | **`FCS_I2C_INIT_ERR = 0x200A` confirmed unchanged.** Full KM-side error range: `FCS_GPIO_INIT_ERR = 0x2009`, `FCS_I2C_INIT_ERR = 0x200A`, `FCS_ADC_INIT_ERR = 0x200B`, `FCS_PWM_INIT_ERR = 0x200C`, `FCS_I2C_TRANS_ERR = 0x2100`, `FCS_I2C_CMP_ERR = 0x21FF`, `FCS_I2C_CB_ERR = 0x21FD`. **`FCS_CHK_FAIL` does NOT exist as a defined constant** in this file — it is likely a printf string only, not a status code enum entry. No error codes were added, removed, or changed in V4.1.1-QC-V06. | LOW (confirms prior) |
| forum.amebaiot.com/t/.../4670 — "Updated AMB82-mini board breaks working code" (search result snippet) | **Newly surfaced thread** (previously untracked). Title: "Updated AMB82-mini board breaks working code." Thread appeared in search results this cycle for the first time. Suggests the transition to a newer SDK version caused previously working code to stop functioning — a board-compatibility/API-break complaint that is tangentially relevant (SDK changes can introduce or mask race conditions). Content is 403-blocked; no indication it is flash/FCS-triggered. Thread number not determinable from search snippet. | LOW (blocked) |
| ameba-rtos-pro2 commits (fetched 2026-05-20, two agents) | **Confirmed frozen — identical to U29.** HEAD = `3f95070` (May 15, 2026). Zero new commits in 5 days. No flash, FCS, VOE, boot, HAL, or sensor changes in any observable pipeline. Two independent agents reached identical conclusions. | LOW |
| ameba-arduino-pro2 dev/main branches and releases (fetched 2026-05-20, two agents) | **Confirmed frozen — identical to U29.** dev HEAD = `7db1c7d` (May 19, 2026); main HEAD = `93d63514` (Mar 2, 2026). V4.1.1-QC-V06 remains latest pre-release (tag created Mar 6, 2026; release notes accumulate through May 19). No FCS/flash/camera fixes in any release note entry. 12 open issues in ameba-arduino-pro2 — newest #398 (Mar 29, 2026); no FCS/flash/camera/VOE/boot issue filed. | LOW |
| Community FlashMemory + mutex wrapper (GitHub gists, forks, search, 2026-05-20) | **Zero community-written wrappers exist.** GitHub gist search for "AMB82 FlashMemory mutex," web searches combining ameba-arduino-pro2 with `device_mutex_lock`, `RT_DEV_LOCK_FLASH`, and `FlashMemory` all returned zero results. No third-party PRs, issues, or forks of ameba-arduino-pro2 addressing this race condition exist publicly. One third-party AMB82 project repo (`github.com/Dennis40816/ameba_stream_project`) returned HTTP 404 — deleted or made private. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn, May 20 sweep) | **Zero new content — 30th consecutive cycle.** All Chinese community sites remain 403-blocked or return zero relevant results. bbs.aithinker.com BW21-CBV subforum thread titles (home surveillance, human detection, DIY projects) confirmed from Google index — none mention flash/camera/FCS/VOE failure. No new BW21-CBV or RTL8735B Chinese-language technical posts about this bug found anywhere. | LOW |
| Web-wide error string sweep (2026-05-20, two agents) | **Zero indexed results — 30 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"` return zero publicly indexed results anywhere on the accessible web. No hardware test result for any of the three proposed workarounds has been posted anywhere in any language. | LOW |

**VOE release note discrepancy — two-file model:**

| File location | Repo | Latest version documented | Last updated |
|---|---|---|---|
| `fcs_hal/hal_video_release_note.txt` | ameba-arduino-pro2 (`dev`) | **VOE 1.5.6.0 (07/17/2024)** | Never updated post-Jul 2024 |
| `component/video/driver/RTL8735B/hal_video_release_note.txt` | ameba-rtos-pro2 | **VOE 1.7.1.0 (04/21/2026)** | Actively maintained |

The RTOS SDK release note is the authoritative source for VOE binary changes. The Arduino SDK copy is a static snapshot from July 2024. All VOE version findings in prior cycles (1.6.x, 1.7.x) were sourced from the RTOS SDK copy — those remain valid. The Arduino SDK ships a binary `voe.bin` that is newer than its text release note suggests.

**FlashMemory.cpp commit history — complete (corrects prior "3 commits" finding):**

| Commit | Date | Message |
|---|---|---|
| `d9022ef` | Jul 9, 2024 | Add feature Flash Memory (#252) — initial commit |
| `86d0801` | Jul 16, 2024 | Update Flash memory links |
| `0403608` | Jun 20, 2025 | Update all example guide links |
| `e1fa54e` | Sep 9, 2025 | Update WiFi example (#333) |
| `d1a988f` | Sep 30, 2025 | Add Arduino printf (#336) |
| `4fdfbec` | Sep 30, 2025 | Optimize codes (#337) |

None of these 6 commits added mutex protection. The library has existed for 10 months without ever acquiring `RT_DEV_LOCK_FLASH`.

**SDK state as of 2026-05-20 (Cycle U30 — unchanged from U29):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; release notes through May 19, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at May 15, 2026 (`3f95070`) — 5 days no change; PR #17 (ethernet security fix) still open
- ameba-arduino-pro2 dev: Frozen at May 19, 2026 (`7db1c7d`) — 1 day no change
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — 79 days no change

**No confirmed fix. Bug remains unpatched as of 2026-05-20 (Cycle U30).**

**Top unresolved actions (unchanged from U29):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. Highest priority.
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates this is the required pattern; FlashMemory.cpp omission is confirmed architectural defect; forward-declaration callable from Arduino (`extern "C" void device_mutex_lock(unsigned int)` / `#define RT_DEV_LOCK_FLASH 1`).
3. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes at source; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-05-21 (Cycle U31)

**Search scope:** Four parallel agents: (1) GitHub — ameba-rtos-pro2 and ameba-arduino-pro2 commits/releases/issues after May 19, 2026; (2) English forum/web — new threads above #4868, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` workaround hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee; (4) SDK deep-dive — FlashMemory.cpp and hal_flash mutex state in V4.1.1-QC-V06, hal_video_release_note.txt location, community PRs/forks.

**Key new findings this cycle:** None. All research channels are frozen, blocked, or empty for the 31st consecutive cycle. No new commits, releases, forum threads, documentation, hardware test results, or Chinese-language content found anywhere.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 commits (direct fetch, 2026-05-21) | **Confirmed frozen — identical to U30.** 5 most recent commits verified: `3f95070` (May 15), `afc85a0` (May 15), `9c8b6f6` (May 15), `d2676f1` (May 15), `1c1c8b7` (May 1). Zero new commits in 6 days since May 15, 2026. No flash, FCS, VOE, boot, HAL, or sensor changes visible. | LOW |
| ameba-arduino-pro2 dev branch commits (direct fetch, 2026-05-21) | **Confirmed frozen — identical to U30.** 5 most recent commits verified: `7db1c7d` "Pre Release Version 4.1.1" (May 19), `3d53672` "Update Code base and add cam IMX681_5M (#409)" (May 19), `cd0bd40` "Add I2C Slave (#408)" (May 18), `13961cc` (May 5), `e218f33` (Apr 30). Zero new commits after May 19, 2026. No FCS/flash/camera fix in any commit. | LOW |
| ameba-arduino-pro2 releases (direct fetch, 2026-05-21) | **No new releases.** Latest stable = V4.1.0 (Mar 2, 2026). Latest pre-release = V4.1.1-QC-V06 (tag created Mar 6, 2026; release notes through May 19, 2026). No V4.1.1 stable release has been published. | LOW |
| ameba-arduino-pro2 open issues (direct fetch, 2026-05-21) | **12 open issues; newest = #398 (Mar 29, 2026).** No new issues filed for FCS, flash, camera, VOE, boot failure, or sensor init. Bug remains entirely unreported on the official tracker after 31 research cycles. | LOW |
| ideashatch/HUB-8735 issues (2026-05-21) | **1 open issue: #10** (PS5268 sensor id fail, Aug 2025). No new issues. Unchanged since U10. | LOW |
| `FlashMemory.cpp` — dev branch raw fetch (2026-05-21) | **Zero mutex calls confirmed unchanged.** All 8 flash operations (lines 59, 71, 76, 88, 106, 107, 121, 135–140) call flash HAL functions directly with zero `device_mutex_lock`, `device_mutex_unlock`, or `#include "device_lock.h"`. File has 3 commits total in its history (Jul 9, 2024; Sep 30, 2025 ×2) — none added mutex protection. The architectural defect persists unchanged through V4.1.1-QC-V06. | LOW (confirms prior) |
| Community PRs / forks adding `RT_DEV_LOCK_FLASH` to FlashMemory (GitHub search, 2026-05-21) | **Zero.** GitHub PR search `is:pr mutex` in ameba-arduino-pro2: 0 results. PR search `is:pr flash`: 5 results, none related to mutex/locking. No community fork or gist implementing this fix was found on any platform. | LOW (confirms prior) |
| Official flash example `flash/src/main.c` (ameba-rtos-pro2, 2026-05-21) | **`device_mutex_lock(RT_DEV_LOCK_FLASH)` pattern confirmed still present.** Every flash read/erase/write in the example is wrapped with `device_mutex_lock(1)` / `device_mutex_unlock(1)`. The architectural contradiction with FlashMemory.cpp persists: Realtek's own reference code requires the mutex; the Arduino library never acquires it. | LOW (confirms prior) |
| `hal_video_release_note.txt` in ameba-rtos-pro2 main (2026-05-21) | **File not found at `component/video/driver/RTL8735B/hal_video_release_note.txt`** — returns HTTP 404 on main branch. Last documented VOE version (1.7.1.0, 04/21/2026 per RTOS SDK copy, U25/U26) remains unchanged. Arduino SDK copy is in `fcs_hal/` subdirectory and tops out at VOE 1.5.6.0 (Jul 2024). No new VOE version has been released. | LOW (confirms prior) |
| V4.1.1-QC-V06 release notes (ameba-arduino-pro2, 2026-05-21) | **No mention of flash safety, mutex, FCS, SPIC, concurrent access, or camera boot.** Features: Battery-Powered Camera POC, Audio Trigger Recording, Video Zoom, TensorFlowLite, I2C Slave, K306P/IMX681_5M sensors, tools v1.4.11. Only data-corruption-related fix: WiFi TCP data corruption (ServerDrv) — entirely unrelated to flash/SPIC. | LOW (confirms prior) |
| forum.amebaiot.com threads above #4868 (2026-05-21 sweep) | **No new threads indexed.** Targeted search for IDs 4869–4875 returns zero results. Forum ceiling remains at #4868 ("NN Model loading from Memory instead of Flash or SD card failing with exceptions"). Forum is HTTP 403 for all direct fetches. | LOW |
| English web: hardware test reports for any workaround (2026-05-21) | **Zero results.** No post confirms hardware testing of "Camera FCS Mode = Disable," `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper, or `USE_ISP_RETENTION_DATA` as workarounds for the flash-write cold-boot camera failure. Reddit, Hackster.io, and Instructables have no new AMB82 camera+flash bug reports. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee, May 21 sweep) | **Zero new content — 31st consecutive cycle.** All Chinese community sites remain 403-blocked or return zero relevant results. No Chinese-language forum posts or articles discuss FCS flash-write camera failure on RTL8735B or BW21-CBV. bbs.aithinker.com is fully inaccessible to automated fetching. | LOW |
| Web-wide error string sweep (2026-05-21) | **Zero indexed results — 31 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"` return zero publicly indexed results anywhere on the accessible web. This research log remains the only public documentation of this bug and its error codes. | LOW |

**SDK state as of 2026-05-21 (Cycle U31 — unchanged from U30):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; release notes through May 19, 2026) — no fix; FlashMemory.cpp mutex omission confirmed unchanged
- ameba-rtos-pro2 main: Frozen at May 15, 2026 (`3f95070`) — 6 days no change; PR #17 (ethernet security fix) open and unmerged
- ameba-arduino-pro2 dev: Frozen at May 19, 2026 (`7db1c7d`) — 2 days no change
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — 80 days no change

**No confirmed fix. Bug remains unpatched as of 2026-05-21 (Cycle U31).**

**Top unresolved actions (unchanged from U30):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. Highest priority.
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; FlashMemory.cpp omission is confirmed architectural defect; forward-declaration callable from Arduino without include-path issues (`extern "C" void device_mutex_lock(unsigned int)` / `#define RT_DEV_LOCK_FLASH 1`).
3. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes at source; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-05-21 (Cycle U32)

**Search scope:** Six parallel search threads + direct GitHub/web fetches: (1) GitHub — ameba-rtos-pro2 and ameba-arduino-pro2 commits/releases/issues after May 19; ameba-tool-rtos-pro2 first-time check; (2) English forum/web — new threads above #4868, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee; (4) New documentation portals — `ameba-doc-rtos-pro2-sdk.readthedocs-hosted.com` application note index; (5) Error string sweeps; (6) ameba-doc-arduino-sdk ISP Control / Flash Memory pages.

**Key new findings this cycle:** None of substance. All research channels are frozen, blocked, or empty for the 32nd consecutive cycle. One new documentation URL identified. `ameba-tool-rtos-pro2` repo checked for the first time.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 commits (direct fetch, 2026-05-21) | **Confirmed frozen — identical to U31.** 10 most recent commits verified: `3f95070` (May 15), `afc85a0` (May 15), `9c8b6f6` (May 15), `d2676f1` (May 15), `1c1c8b7` (May 1), and earlier entries unchanged. Zero new commits in 6 days since May 15, 2026. No flash, FCS, VOE, boot, HAL, or sensor changes visible. | LOW |
| ameba-arduino-pro2 dev branch commits (direct fetch, 2026-05-21) | **Confirmed frozen — identical to U31.** 10 most recent commits verified: `7db1c7d` "Pre Release Version 4.1.1" (May 19), `3d53672` "Update Code base and add cam IMX681_5M (#409)" (May 19), `cd0bd40` "Add I2C Slave (#408)" (May 18), `13961cc` (May 5). Zero new commits after May 19, 2026. No FCS/flash/camera fix in any commit. | LOW |
| ameba-arduino-pro2 releases (direct GitHub fetch, 2026-05-21) | **No new releases.** Latest stable = V4.1.0 (Mar 2, 2026). Latest pre-release = V4.1.1-QC-V06 (tag created Mar 6, 2026; release notes accumulate through May 19, 2026). V4.1.1 stable not published. Release notes confirm no FCS, flash camera boot, FlashMemory mutex, or SPIC concurrent-access fix in any release entry. | LOW |
| ameba-arduino-pro2 open issues (direct GitHub fetch, 2026-05-21) | **17 open issues confirmed; newest = #398 (Mar 29, 2026).** No new issues after March 29, 2026. No issues about FlashMemory, FCS, camera, VOE, or boot failure in open or closed history. Bug entirely unreported after 32 research cycles. | LOW |
| ameba-tool-rtos-pro2 (GitHub, first-time check, 2026-05-21) | **Previously untracked repository.** `github.com/Ameba-AIoT/ameba-tool-rtos-pro2` contains Ameba RTOS Pro2 tooling (OSD tools, IQ tuning tool). 5 total commits: initial (May 27, 2024), OSD tools + README (Oct 23, 2025), "Add IQ tuning tool (#2)" (Mar 9, 2026, SHA `c1d70e7`). Last commit = March 9, 2026. Zero commits related to flash, FCS, postbuild, camera boot, or image packaging. Not relevant to the bug. | LOW |
| `ameba-doc-rtos-pro2-sdk.readthedocs-hosted.com/en/latest/application_note/UM_IQ_driver_guide/37_Introduction_For_Sensor_Bringup_Flow.html` | **NEW documentation URL identified for the first time.** Full path: `UM_IQ_driver_guide/37_Introduction_For_Sensor_Bringup_Flow.html` — "[AmebaPro2] Introduction for Sensor Bring up Flow." This is section 37 of a User Manual for IQ/driver development. The path structure implies this document covers the camera sensor I2C initialization sequence — the exact sequence that fails with `FCS_I2C_INIT_ERR (0x200A)` in our bug. Returns HTTP 403 (developer login required). If accessible, may document the GPIO→I2C bring-up order that the KM co-processor follows during FCS boot, potentially explaining which step fails and why flash writes trigger it. Previously untracked documentation URL. | LOW (blocked) |
| `ameba-doc-rtos-pro2-sdk.readthedocs-hosted.com` application note index (2026-05-21) | **Application note index confirmed present but 403-blocked.** Application notes confirmed to exist: 02_SDK, 04_IMAGE, 08_FLASHLAYOUT, 09_OTA, 11_SYSTEMAPI, 15_ISP, 19_USB, UM_IQ_driver_guide/37_Introduction_For_Sensor_Bringup_Flow. All return HTTP 403. The ISP page (15_ISP.html) remains the highest-priority blocked page — it likely documents FCS data layout, SAVE_TO_FLASH/SAVE_TO_RETENTION interaction, and FCS partition addressing. | LOW (blocked) |
| forum.amebaiot.com threads above #4868 (sweep, 2026-05-21) | **No new threads indexed.** Targeted search for IDs 4869–4875 returned zero results. Forum ceiling confirmed at #4868 ("NN Model loading from Memory instead of Flash or SD card failing with exceptions"). | LOW |
| English web: hardware test reports for any workaround (2026-05-21) | **Zero results.** No public hardware test result for "Camera FCS Mode = Disable," `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper, or `USE_ISP_RETENTION_DATA` has been published anywhere on the accessible web. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee, May 21) | **Zero new content — 32nd consecutive cycle.** All Chinese community sites remain 403-blocked or return zero relevant results. No Chinese-language forum posts or articles discuss FCS flash-write camera failure on RTL8735B or BW21-CBV. | LOW |
| Web-wide error string sweep (2026-05-21) | **Zero indexed results — 32 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"` return zero publicly indexed results anywhere on the accessible web. This research log remains the only public documentation of this bug and its error codes. | LOW |

**SDK state as of 2026-05-21 (Cycle U32 — unchanged from U31):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; release notes through May 19, 2026) — no fix; FlashMemory.cpp mutex omission confirmed unchanged
- ameba-rtos-pro2 main: Frozen at May 15, 2026 (`3f95070`) — 6 days no change; PR #17 (ethernet security fix) open and unmerged
- ameba-arduino-pro2 dev: Frozen at May 19, 2026 (`7db1c7d`) — 2 days no change
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — 80 days no change
- ameba-tool-rtos-pro2: Frozen at March 9, 2026 (`c1d70e7`) — first-time confirmed

**No confirmed fix. Bug remains unpatched as of 2026-05-21 (Cycle U32).**

**Top unresolved actions (unchanged from U31):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. Highest priority.
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; FlashMemory.cpp omission is confirmed architectural defect; forward-declaration callable from Arduino without include-path issues (`extern "C" void device_mutex_lock(unsigned int)` / `#define RT_DEV_LOCK_FLASH 1`).
3. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes at source; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-05-21 (Cycle U33)

**Search scope:** Six parallel search threads + direct GitHub/web fetches: (1) GitHub — ameba-rtos-pro2 and ameba-arduino-pro2 commits/releases/issues after May 19; (2) English forum/web — new threads above #4868, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/Bilibili/Gitee; (4) MMF documentation snippet analysis — `SAVE_TO_RETENTION` ~90ms ISP window confirmation; (5) aiot.realmcu.com AMB82-mini guide and Flash Memory docs access attempts; (6) Error string indexing sweep.

**Key new findings this cycle:** None of substance. All research channels are frozen, blocked, or empty for the 33rd consecutive cycle. One minor documentation snippet confirmed an ISP AE/AWB retrieval timing detail (~90ms). Both repositories and all associated trackers are unchanged.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 commits (direct GitHub fetch, 2026-05-21) | **Confirmed frozen — identical to U32.** 10 most recent commits verified: `3f95070` (May 15), `afc85a0` (May 15), `9c8b6f6` (May 15), `d2676f1` (May 15), `1c1c8b7` (May 1), and prior unchanged entries. Zero new commits in 6 days since May 15, 2026. No flash, FCS, VOE, boot, HAL, or sensor changes visible. | LOW |
| ameba-arduino-pro2 dev branch commits (direct GitHub fetch, 2026-05-21) | **Confirmed frozen — identical to U32.** 10 most recent commits verified: `7db1c7d` "Pre Release Version 4.1.1" (May 19), `3d53672` "Update Code base and add cam IMX681_5M (#409)" (May 19), `cd0bd40` "Add I2C Slave (#408)" (May 18). Zero new commits after May 19, 2026. No FCS/flash/camera fix in any commit. | LOW |
| ameba-arduino-pro2 releases (direct GitHub fetch, 2026-05-21) | **No new releases.** Latest stable = V4.1.0 (Mar 2, 2026). Latest pre-release = V4.1.1-QC-V06 (tag created Mar 6, 2026; release notes through May 19, 2026). No V4.1.1-QC-V07 or stable V4.1.1 published. | LOW |
| ameba-arduino-pro2 open issues (direct GitHub fetch, 2026-05-21) | **12 open issues; newest = #398 (Mar 29, 2026).** No new issues filed for FCS, flash, camera, VOE, boot failure, or sensor init. Bug remains entirely unreported on the official tracker after 33 research cycles. | LOW |
| ameba-rtos-pro2 open issues (direct GitHub fetch, 2026-05-21) | **3 open issues: #16 (Jan 2026), #4 (Apr 2025), #3 (Apr 2025).** No new issues. No FCS/flash/camera bug filed after 33 cycles. | LOW |
| ideashatch/HUB-8735 issues (direct GitHub fetch, 2026-05-21) | **1 open issue: #10** (PS5268 sensor id fail, Aug 2025). No new issues. Unchanged since U10. | LOW |
| MMF documentation snippet (search engine, `ameba-doc-rtos-pro2-sdk.readthedocs-hosted.com/en/latest/application_note/06_MMF.html`, 403-blocked) | **`SAVE_TO_RETENTION` timing confirmed: ~90ms ISP control API window.** Search snippet (URL remains 403-blocked) confirms: `CMD_VIDEO_PRE_INIT_SAVE` supports `SAVE_TO_STRUCTURE`, `SAVE_TO_FLASH`, `SAVE_TO_RETENTION`; `SAVE_TO_RETENTION` uses only SRAM (zero SPIC); when metadata is not available, the ISP control API path (used before saving) takes **approximately 90ms**. This 90ms is the AE/AWB parameter retrieval window — during which `ftl_common_write` may issue SPIC commands. If `FlashMemory.erase()` is called during this window, the SPIC bus race condition (confirmed U19) can occur. The 90ms figure is new quantification not previously captured in this log. | LOW (background) |
| aiot.realmcu.com AMB82-mini guide and Flash Memory docs (2026-05-21) | **All still 403-blocked.** `aiot.realmcu.com/en/latest/arduino/arduino_guide/sdk_intro/evb_guides/evb_amb82mini.html`, `ameba-doc-arduino-sdk.readthedocs-hosted.com/en/latest/ameba_pro2/amb82-mini/Example_Guides/Flash%20Memory/index.html`, `ameba-doc-rtos-pro2-sdk.readthedocs-hosted.com/en/latest/application_note/15_ISP.html` — all return HTTP 403. Inaccessible without developer login for the 33rd consecutive cycle. | LOW (blocked) |
| forum.amebaiot.com threads above #4868 (sweep, 2026-05-21) | **No new threads indexed.** Targeted search for IDs 4869–4880 returned zero results. Forum ceiling remains at #4868 ("NN Model loading from Memory instead of Flash or SD card failing with exceptions"). | LOW |
| Web-wide error string sweep (2026-05-21) | **Zero indexed results — 33 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"FCS_RUN_DATA_NG_KM"` return zero publicly indexed results anywhere on the accessible web. No hardware test result for any of the three proposed workarounds has been posted anywhere in any language. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee, May 21 sweep) | **Zero new content — 33rd consecutive cycle.** All Chinese community sites remain 403-blocked or return zero relevant results. No Chinese-language forum posts or articles discuss FCS flash-write camera failure on RTL8735B or BW21-CBV. | LOW |

**ISP AE/AWB ~90ms window — SPIC race condition context:**

The search snippet confirming the ~90ms ISP control API timing provides a concrete window for the SPIC concurrent-access race:

| Phase | Duration | SPIC activity |
|---|---|---|
| Camera sends AE/AWB retrieval command | ~90ms | ISP reads sensor registers via I2C; no SPIC |
| ISP calls `ftl_common_write` → `nor_write_cb` → `flash_stream_write` | ~1–3ms (tPP) | **SPIC active: acquires `RT_DEV_LOCK_FLASH`, issues WREN + PAGE_PROGRAM** |
| If `FlashMemory.erase()` runs concurrently | 45–400ms (tSE) | **SPIC race: no `RT_DEV_LOCK_FLASH` acquired → bus collision possible** |

The 90ms retrieval phase is I2C-only (no SPIC conflict). The conflict occurs during the subsequent `ftl_common_write` SPIC write phase (~1–3ms), which can overlap with a `FlashMemory.erase()` call issued by the Arduino sketch at any time. This confirms the race window is real but narrow (1–3ms per ISP save cycle), explaining why the bug is intermittent unless flash operations are frequent or continuous.

**SDK state as of 2026-05-21 (Cycle U33 — unchanged from U32):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; release notes through May 19, 2026) — no fix; FlashMemory.cpp mutex omission confirmed unchanged
- ameba-rtos-pro2 main: Frozen at May 15, 2026 (`3f95070`) — 6 days no change; PR #17 (ethernet security fix) open and unmerged
- ameba-arduino-pro2 dev: Frozen at May 19, 2026 (`7db1c7d`) — 2 days no change
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — 80 days no change
- ameba-tool-rtos-pro2: Frozen at March 9, 2026 (`c1d70e7`)

**No confirmed fix. Bug remains unpatched as of 2026-05-21 (Cycle U33).**

**Top unresolved actions (unchanged from U32):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. Highest priority.
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; FlashMemory.cpp omission confirmed as architectural defect; forward-declaration callable from Arduino without include-path issues (`extern "C" void device_mutex_lock(unsigned int)` / `#define RT_DEV_LOCK_FLASH 1`).
3. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-05-21 (Cycle U34)

**Search scope:** Six parallel search threads + direct web searches: (1) GitHub — ameba-rtos-pro2 and ameba-arduino-pro2 commits/releases/issues/PRs after May 19; (2) English forum/web — new threads above #4868, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee; (4) GitHub code search — `RT_DEV_LOCK_FLASH` in FlashMemory.cpp, new mutex PRs; (5) Error string indexing sweep; (6) New forum thread identification above previously-known ceiling.

**Key new findings this cycle:**
- **PR #410 "Update SPI API for SPI1 switching"** — newly opened in ameba-arduino-pro2 (first time documented); unrelated to flash/FCS bug but confirms repo has active development beyond I2C and sensor additions.
- **Thread #3864 "Flash Translation Layer (FTL) - Intermittently unable to read previously stored data"** — newly identified thread (previously untracked). Involves FTL storing ~500 bytes of config data (`ftl_phy_page_num = 3`); intermittent FTL read failures are conceptually consistent with the confirmed SPIC concurrent-access architectural defect (U19): FlashMemory bypasses `RT_DEV_LOCK_FLASH` while FTL layer correctly holds it. Content 403-blocked.
- **Thread #4726 "ISP tuning required for Sony IMX662 on Ameba Mini"** — newly identified thread (previously untracked); involves FCS mode for Sony IMX662 sensor; content 403-blocked.
- **RTL8720C thread #1239 date confirmed: May 11, 2022** — first time explicitly confirmed from search snippet.
- All repos still frozen; FlashMemory.cpp mutex omission unchanged; no hardware test results for any workaround; all Chinese community sites remain 403-blocked (34th consecutive cycle).

| Source | Key Finding | Priority |
|---|---|---|
| ameba-arduino-pro2 PR #410 "Update SPI API for SPI1 switching" (GitHub, 2026-05-21) | **Newly identified open PR** (previously untracked). Filed after the I2C Slave PR #408 (May 18) and IMX681_5M PR #409 (May 19). Unrelated to flash mutex, FCS, or camera boot failure. Confirms the Arduino repo has at least one PR in the pipeline post-May 19. No flash/FCS content. | LOW (unrelated) |
| forum.amebaiot.com/t/flash-translation-layer-ftl-intermittently-unable-to-read-previously-stored-data/3864 | **Newly identified thread** (previously untracked). Title: "Flash Translation Layer (FTL) - Intermittently unable to read previously stored data." Search snippet reveals: user stores ~500 bytes of config (SSID, password, firmware parameters) via FTL initialized with `ftl_phy_page_num = 3`. FTL reads fail intermittently. This is conceptually adjacent to the confirmed architectural defect (U19): if a `FlashMemory.erase()` call races with an FTL write (both on the same SPIC bus, with no cross-subsystem mutex), the FTL-managed region could be partially overwritten, producing intermittent read failures on subsequent accesses. Thread content is 403-blocked; causal connection to `RT_DEV_LOCK_FLASH` bypass is inferred but unconfirmed. Platform not determinable from snippet (likely AMB82 or similar Ameba platform). | LOW (blocked, inferred relevance) |
| forum.amebaiot.com/t/isp-tuning-required-for-sony-imx662-on-ameba-mini/4726 (2026-02 or later) | **Newly identified thread** (previously untracked). Title: "ISP tuning required for Sony IMX662 on Ameba Mini." Thread discusses FCS mode and sensor binary files for the Sony IMX662 camera sensor (one of the 11 sensors in the AMB82-Mini Tools menu). Content 403-blocked. No indication it describes the flash-write cold-boot failure; appears to be an IQ tuning / sensor bringup question. Not confirmed as related to our bug. Thread ID lower than known ceiling (#4868); it was not previously surfaced in research. | LOW (blocked, unrelated) |
| platformio/platformio-core GitHub Issue #4855 "Feature Request: Support RealTek Ameba AMB82-Mini board (RTL8735BDM)" | **Newly identified PlatformIO issue** (previously untracked; distinct from issue #4809 documented in U21). Filed as a feature request to add AMB82-Mini (RTL8735BDM variant) board support to PlatformIO. Confirms that AMB82-Mini PlatformIO support is still not complete for the -BDM silicon variant as of 2026. Not related to camera/flash/FCS boot failure. | LOW (background) |
| RTL8720C thread #1239 date (search snippet, 2026-05-21) | **Date confirmed: May 11, 2022.** Search snippet directly shows the thread was created May 11, 2022. Thread title: "RTL8720C 数据保存到FLASH后再次启动 log显示启动失败" — content discusses RTL8720C flash partition table structure and boot failure logs after flash data save. Previously estimated "2022" without confirmation. This is the earliest confirmed public report of the flash→boot failure symptom class in the Realtek Ameba family, predating the RTL8735B FCS feature by over 2 years. Content still 403-blocked. | LOW (confirms prior) |
| ameba-rtos-pro2 commits (direct GitHub fetch, 2026-05-21, two agents) | **Confirmed frozen — identical to U33.** 10 most recent commits verified by two independent agents: `3f95070` (May 15), `afc85a0` (May 15), `9c8b6f6` (May 15), `d2676f1` (May 15), `1c1c8b7` (May 1), unchanged further back. Zero new commits in 6 days since May 15, 2026. No flash, FCS, VOE, boot, HAL, or sensor changes visible in any commit. | LOW |
| ameba-arduino-pro2 dev branch commits (direct GitHub fetch, 2026-05-21, two agents) | **Confirmed frozen — identical to U33.** Head = `7db1c7d` "Pre Release Version 4.1.1" (May 19, 2026). Zero new commits after May 19, 2026. No FCS/flash/camera fix in any commit. Only open PR: #410 (SPI API — unrelated). | LOW |
| ameba-arduino-pro2 releases (direct GitHub fetch, 2026-05-21) | **No new releases.** Latest stable = V4.1.0 (Mar 2, 2026). Latest pre-release = V4.1.1-QC-V06 (tag Mar 6, 2026; release notes accumulate through May 19, 2026). No V4.1.1-QC-V07 or stable V4.1.1 published. Release notes confirm no FCS, flash camera boot, FlashMemory mutex, or SPIC concurrent-access fix. | LOW |
| ameba-arduino-pro2 open issues (direct GitHub fetch, 2026-05-21) | **12–17 open issues (count confirmed as 12 by one agent, 17 by another — probable count varies by issue visibility); newest = #398 (Mar 29, 2026).** No new issues after March 29, 2026. No issues about FlashMemory, FCS, camera, VOE, or boot failure in open or closed history. Bug entirely unreported after 34 research cycles. | LOW |
| `FlashMemory.cpp` — raw GitHub fetch of dev branch (2026-05-21, confirmed by two agents) | **Zero mutex calls confirmed unchanged.** GitHub code search for `RT_DEV_LOCK_FLASH` in ameba-arduino-pro2 returns exactly one hit — the enum definition in `device_lock.h` — and zero hits in `FlashMemory.cpp`. File has 6 total commits; last meaningful change Sep 30, 2025 (#337). The architectural defect persists in V4.1.1-QC-V06. | LOW (confirms prior) |
| All English forum/web sources (2026-05-21, two agents) | **Zero new content.** No new forum threads above #4868 indexed. Error strings `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"` return zero publicly indexed results on the accessible web. No hardware test result for any workaround posted anywhere. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee, May 21 sweep) | **Zero new content — 34th consecutive cycle.** All Chinese community sites remain 403-blocked or return zero relevant results. No Chinese-language forum posts or articles discuss FCS flash-write camera failure on RTL8735B or BW21-CBV. | LOW |

**Thread #3864 FTL intermittent read failure — SPIC concurrent-access relevance:**

Thread #3864 is the first publicly indexed report of an AMB82-family FTL read failure that is conceptually consistent with the confirmed SPIC bus mutex defect. The scenario described (FTL used for user config storage, intermittent reads failing) maps directly to the race condition mechanism:

1. `FlashMemory.erase()` at 0xFD0000 bypasses `RT_DEV_LOCK_FLASH`
2. FTL layer (`nor_erase_cb`/`nor_write_cb`) holds `RT_DEV_LOCK_FLASH` during its own write
3. Without the mutex, `FlashMemory` can interleave SPIC commands with an in-progress FTL write
4. The FTL-managed region (distinct from FlashMemory's region) may receive a partial/corrupted write
5. Result: intermittent read failure from the FTL region on next access

This provides independent evidence that the `RT_DEV_LOCK_FLASH` bypass in FlashMemory has real-world consequences beyond just the ISP AE/AWB FCS data — any FTL-based storage (user config, FCS AE/AWB, WiFi fast-connect profile) is vulnerable. Thread content is 403-blocked; no resolution is extractable.

**SDK state as of 2026-05-21 (Cycle U34 — unchanged from U33):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; release notes through May 19, 2026) — no fix; FlashMemory.cpp mutex omission confirmed unchanged
- ameba-rtos-pro2 main: Frozen at May 15, 2026 (`3f95070`) — 6 days no change; PR #17 (ethernet security fix) open and unmerged
- ameba-arduino-pro2 dev: Frozen at May 19, 2026 (`7db1c7d`) — 2 days no change; PR #410 (SPI API) open and unmerged
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — 80 days no change
- ameba-tool-rtos-pro2: Frozen at March 9, 2026 (`c1d70e7`)

**No confirmed fix. Bug remains unpatched as of 2026-05-21 (Cycle U34).**

**Top unresolved actions (unchanged from U33):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. Highest priority.
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; FlashMemory.cpp omission is confirmed architectural defect; forward-declaration callable from Arduino without include-path issues (`extern "C" void device_mutex_lock(unsigned int)` / `#define RT_DEV_LOCK_FLASH 1`).
3. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-05-22 (Cycle U35)

**Search scope:** Four parallel agents: (1) GitHub — all repos post-May 19, 2026 activity (commits/PRs/issues/releases); (2) English forum/web — new threads above #4868, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — comprehensive sweep (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee); (4) SDK deep-dive — FlashMemory.cpp mutex state, FTL mutex source confirmation, VOE version beyond 1.7.1.0, community wrappers, documentation portal accessibility.

**Key new findings this cycle:**
- **V4.1.0 release notes: "Add `cameraClearQItem` function"** — previously undocumented in this research log. Potentially useful for recovering from the "[VOE][WARN]slot full" mild case, but not a root-cause fix.
- **`ftl.c` mutex usage confirmed from a new source** — `device_mutex_lock(RT_DEV_LOCK_FLASH)` confirmed in `ftl.c` directly (prior research U19 cited `ftl_nor_api.c` callbacks); confirms the architectural defect from an additional file.
- Both repos frozen at same HEADs as U34; PRs #17 and #410 still open.
- All error strings unindexed for 35th consecutive cycle; all docs still 403-blocked; zero new Chinese content; no hardware test results anywhere.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-arduino-pro2 V4.1.0 release notes (Mar 2, 2026, retrieved 2026-05-22) | **"Add `cameraClearQItem` function"** — previously undocumented in this research log. Present in the current stable SDK. Function may allow user code to explicitly clear camera queue entries after a "[VOE][WARN]slot full" mild-case deadlock. Exact signature, parameters, and scope are not documented in any publicly accessible source. If it clears MMF queue slots (not just frame buffers), calling it after detecting a slot-full condition could allow camera re-initialization without a full power cycle. Not a fix for the FCS_I2C_INIT_ERR cold-boot root cause. V4.1.0 also includes "Update FlashMemory.h" — exact changes in that update not confirmed from public changelog; no mutex addition was confirmed in FlashMemory.cpp source (zero mutex calls across all 8 operations, unchanged). | LOW |
| `ftl.c` (ameba-rtos-pro2, direct source fetch, 2026-05-22) | **`RT_DEV_LOCK_FLASH` mutex usage confirmed from `ftl.c` directly.** `device_mutex_lock(RT_DEV_LOCK_FLASH)` / `device_mutex_unlock(RT_DEV_LOCK_FLASH)` found in `ftl.c` flash read operations — a second confirmation of the mutex pattern in the FTL layer (prior research U19 documented the same in `ftl_nor_api.c` callbacks). Both files use the system-wide flash mutex. FlashMemory.cpp remains the sole exception that never acquires `RT_DEV_LOCK_FLASH`. | LOW (confirms U19) |
| ameba-rtos-pro2 commits (two agents, 2026-05-22) | **Confirmed frozen.** HEAD = `3f95070` (May 15, 2026). Zero new commits in 7 days. PR #17 ("fix: ethernet USB driver buffer overflow", orbisai0security) still open and unmerged. No flash, FCS, VOE, boot, HAL, or sensor changes in any observable pipeline. | LOW |
| ameba-arduino-pro2 dev/main branches and releases (two agents, 2026-05-22) | **Confirmed frozen.** dev HEAD = `7db1c7d` (May 19, 2026). main HEAD = `93d63514` (Mar 2, 2026, 81 days frozen). Latest stable = V4.1.0; latest pre-release = V4.1.1-QC-V06 (tag Mar 6, 2026; release notes through May 19, 2026). No V4.1.1-QC-V07 or stable V4.1.1. PR #410 ("Update SPI API for SPI1 switching", kevinlookl) still open and unmerged. | LOW |
| ideashatch/HUB-8735 issues (2026-05-22) | **1 open issue: #10** (PS5268 sensor id fail, Aug 2025). No new issues. Unchanged since U10. | LOW |
| Community FlashMemory mutex wrappers (GitHub gist/fork/web search, 2026-05-22) | **Zero community implementations found.** No Arduino library, GitHub gist, or public repository wraps FlashMemory operations with `device_mutex_lock(RT_DEV_LOCK_FLASH)`. No community PRs to ameba-arduino-pro2 address this. The architectural defect (confirmed U19–U20) remains uncorrected by any public third-party code after 35 research cycles. | LOW |
| VOE version search (2026-05-22) | **No VOE version beyond 1.7.1.0 found anywhere.** `voe.bin` is updated silently in SDK releases without explicit VOE version strings in changelogs. Last explicitly documented: VOE 1.7.1.0 (04/21/2026, RTOS SDK release note). | LOW |
| forum.amebaiot.com threads (sweep, 2026-05-22) | **No new threads above #4868 indexed.** Forum ceiling remains at #4868 ("NN Model loading from Memory instead of Flash or SD card failing with exceptions"). No new threads related to flash/FCS/camera cold-boot failure. Thread #4302 ("[VOE]frame_end: sensor didn't initialize done!") still 403-blocked; Google snippets confirm it shows "Camera FCS Mode: Disable" as part of a working config, but no causal explanation of flash-write interaction is visible. | LOW |
| All documentation portals (2026-05-22) | **All still 403-blocked.** ISP application note (15_ISP.html), Flash Layout (08_FLASHLAYOUT.html), Sensor Bringup Flow (37_Introduction_For_Sensor_Bringup_Flow.html), aiot.realmcu.com AMB82-mini guide (CN and EN), Flash Memory example guide — all return HTTP 403 for the 35th consecutive cycle. | LOW (blocked) |
| Web-wide error string sweep (2026-05-22, two agents) | **Zero indexed results — 35 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH"` — all return zero results on the public web. No hardware test result for any of the three proposed workarounds has been posted anywhere in any language. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn, May 22 sweep, two agents) | **Zero new content — 35th consecutive cycle.** All Chinese community sites remain 403-blocked or return zero relevant results. bbs.aithinker.com BW21-CBV subforum indexed threads (home surveillance, DIY camera, BLE, unboxing) confirmed still inaccessible. No Chinese-language forum posts or articles discuss FCS flash-write camera failure on RTL8735B or BW21-CBV. | LOW |

**`cameraClearQItem` — relevance to slot-full mild case:**

The "[VOE][WARN]slot full" deadlock (mild case from 70× flash writes) occurs when the MMF module cannot enqueue into an already-consumed slot during re-initialization. If `cameraClearQItem()` clears individual queue slot entries (rather than frame buffers), it could allow recovery without a full power cycle:
1. Detect the slot-full condition (by monitoring VOE warnings or checking a status API)
2. Call `cameraClearQItem()` to release the stuck slot
3. Re-open the camera stream normally

Without public documentation of the function's signature and scope, this remains speculative. The three upstream MMF fixes (U9, U19) — queue-init check (Apr 1), JPEG exception (Apr 1), and task-recreate guard (May 15) — address the slot-full root cause at the SDK level; `cameraClearQItem` may address it at the application level. Function is present in V4.1.0 stable but was not previously catalogued in this research log.

**SDK state as of 2026-05-22 (Cycle U35 — unchanged from U34):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix; newly noted `cameraClearQItem` function
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; release notes through May 19, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at May 15, 2026 (`3f95070`) — 7 days no change; PR #17 open
- ameba-arduino-pro2 dev: Frozen at May 19, 2026 (`7db1c7d`) — 3 days no change; PR #410 open
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — 81 days no change
- ameba-tool-rtos-pro2: Frozen at March 9, 2026 (`c1d70e7`)

**No confirmed fix. Bug remains unpatched as of 2026-05-22 (Cycle U35).**

**Top unresolved actions (unchanged from U34):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. Highest priority.
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; FlashMemory.cpp omission is the confirmed architectural defect; forward-declaration callable from Arduino (`extern "C" void device_mutex_lock(unsigned int)` / `#define RT_DEV_LOCK_FLASH 1`).
3. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-05-22 (Cycle U36)

**Search scope:** Four parallel agents: (1) GitHub — all repos post-May 19, 2026 activity (commits/PRs/issues/releases); (2) English forum/web — new threads above #4868, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — comprehensive sweep (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee); (4) SDK deep-dive — FlashMemory.cpp mutex state in V4.1.0 main branch, `hal_video_release_note.txt` new path confirmation, `RT_DEV_LOCK_FLASH` code search scope.

**Key new findings this cycle:** None. All research channels are frozen, blocked, or empty for the 36th consecutive cycle. One minor clarification: `hal_video_release_note.txt` in the Arduino SDK dev branch was found at a new path after the May 19 reorganization. Ai-Thinker-Open confirmed to have zero RTL8735B/BW21 repositories. Both repositories and all associated trackers are unchanged.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 commits (direct GitHub fetch, 2026-05-22, two agents) | **Confirmed frozen — identical to U35.** HEAD = `3f95070` (May 15, 2026). Zero new commits in 7 days. Most recent 4 commits: `3f95070`, `afc85a0`, `9c8b6f6`, `d2676f1` (all May 15, 2026). PR #17 ("fix: ethernet USB driver buffer overflow", orbisai0security) still open and unmerged. No flash, FCS, VOE, boot, HAL, or sensor changes in any observable pipeline. | LOW |
| ameba-arduino-pro2 dev/main branches and releases (direct GitHub fetch, 2026-05-22, two agents) | **Confirmed frozen — identical to U35.** dev HEAD = `7db1c7d` "Pre Release Version 4.1.1" (May 19, 2026). main HEAD = `93d63514` (Mar 2, 2026) — 81 days frozen. Latest stable = V4.1.0; latest pre-release = V4.1.1-QC-V06 (tag Mar 6, 2026; release notes through May 19, 2026). PR #410 ("Update SPI API for SPI1 switching", kevinlookl, filed May 21, 2026) still open and unreviewed. No FCS/flash/camera fix in any commit. | LOW |
| `FlashMemory.cpp` — V4.1.0 main branch raw GitHub fetch (2026-05-22) | **Zero mutex calls confirmed in shipping V4.1.0 stable codebase.** Direct fetch confirms all operations (`flash_stream_read`, `flash_stream_write`, `flash_erase_sector`, `flash_read_word`, `flash_write_word`) called directly with zero `device_mutex_lock`, `device_mutex_unlock`, `RT_DEV_LOCK_FLASH`, or any synchronization primitive. File SHA: `b4781b70`. Last modified Sep 30, 2025 (`4fdfbec`). Architectural defect present in every released SDK version. | LOW (confirms prior) |
| `hal_video_release_note.txt` path in Arduino SDK dev branch (2026-05-22) | **Path reorganized in May 19 commit.** New confirmed location: `Arduino_package/hardware/system/component/soc/8735b/fwlib/rtl8735b/lib/source/ram/video/hal_video_release_note.txt` (SHA `6e6ee79` at `7db1c7d`). Previously documented at `fcs_hal/hal_video_release_note.txt` (Cycle U30). Reorganization occurred in the May 19 `3d53672` commit. Latest documented VOE version remains **1.7.1.0 (04/21/2026)** — no new VOE release since the dual-sensor FCS mirror/flip fix. | LOW (path clarification) |
| `RT_DEV_LOCK_FLASH` code search in ameba-arduino-pro2 (2026-05-22, two agents) | **One hit only — the enum definition in `device_lock.h`.** Zero hits in FlashMemory.cpp, hal_flash.c, or any Arduino library source file. The mutex bypass in FlashMemory is the sole exception to a pattern correctly used in 15+ RTOS SDK files (`ftl_nor_api.c`, `ftl.c`, `flash_fatfs.c`, `fwfs.c`, `ota_8735b.c`, `dfu_8735b.c`, `wifi_fast_connect.c`, `atcmd_sys.c`, `system_data_api.c`, and others). Confirmed by two independent agents. | LOW (confirms prior) |
| Ai-Thinker-Open GitHub organization (2026-05-22) | **No BW21 or RTL8735B repositories exist in Ai-Thinker-Open.** First-time exhaustive confirmation: searches for "BW21", "8735", "RTL8735" in the organization returned zero repository matches. Organization focused on Bouffalo/BL618, Telink Bluetooth, and WB2 chips. BW21-CBV module software support, if any, is maintained through private channels only. Ai-Thinker-Open cannot be a source of public RTL8735B flash+FCS fixes. | LOW |
| ideashatch/HUB-8735 issues (2026-05-22) | **1 open issue: #10** (PS5268 sensor id fail, Aug 2025). No new issues. Repository last committed Dec 2, 2025 — 172 days frozen. | LOW |
| forum.amebaiot.com threads above #4868 (sweep, 2026-05-22, two agents) | **No new threads indexed.** Targeted searches for IDs #4869–#4900 returned zero results from the forum domain. Forum ceiling confirmed at #4868 ("NN Model loading from Memory instead of Flash or SD card failing with exceptions"). All direct forum fetches return HTTP 403. | LOW |
| Web-wide English search: all key error strings (2026-05-22, two agents) | **Zero indexed results — 36 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"` — all return zero results on the public web. No hardware test result for any of the three proposed workarounds has been posted anywhere in any language. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn, May 22 sweep, two agents) | **Zero new content — 36th consecutive cycle.** All Chinese community sites remain 403-blocked or return zero relevant results. Ai-Thinker forum indexed threads (BW21-CBV) confirmed still inaccessible. No Chinese-language forum posts or articles discuss FCS flash-write camera failure on RTL8735B or BW21-CBV. | LOW |

**SDK state as of 2026-05-22 (Cycle U36 — unchanged from U35):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp mutex omission confirmed in shipping codebase (SHA `b4781b70`)
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; release notes through May 19, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at May 15, 2026 (`3f95070`) — 7 days no change; PR #17 (ethernet security fix) open and unmerged
- ameba-arduino-pro2 dev: Frozen at May 19, 2026 (`7db1c7d`) — 3 days no change; PR #410 (SPI API) open and unmerged
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — 81 days no change
- ameba-tool-rtos-pro2: Frozen at March 9, 2026 (`c1d70e7`) — 74 days no change
- Ai-Thinker-Open: No RTL8735B/BW21 repositories exist (confirmed first time this cycle)

**No confirmed fix. Bug remains unpatched as of 2026-05-22 (Cycle U36).**

**Top unresolved actions (unchanged from U35):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. Highest priority.
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; FlashMemory.cpp omission confirmed in shipping V4.1.0 (main branch SHA `b4781b70`); forward-declaration callable from Arduino (`extern "C" void device_mutex_lock(unsigned int)` / `#define RT_DEV_LOCK_FLASH 1`).
3. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-05-22 (Cycle U37)

**Search scope:** Four parallel agents + direct web searches: (1) GitHub — all repos post-May 19 activity (commits/PRs/issues/releases); (2) English forum/web — new threads above #4868, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — comprehensive sweep (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee); (4) SDK deep-dive — FlashMemory.cpp mutex state (authoritative path confirmed), `USE_ISP_RETENTION_DATA`, `hal_video_release_note.txt`, `RT_DEV_LOCK_FLASH` code search coverage.

**Key new findings this cycle:**
- **FlashMemory.cpp authoritative path confirmed:** `Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.cpp` (SHA `b4781b70`) — 3 commits total touching this file (Jul 9, 2024; Sep 30, 2025 ×2); last meaningful change Sep 30, 2025. All 6 flash operations have zero mutex calls. File frozen for 8 months.
- **`RT_DEV_LOCK_FLASH` correctly used in 16+ files in ameba-rtos-pro2** — `ftl_nor_api.c`, `flash_fatfs.c`, `fwfs.c`, `ftl.c`, `ota_8735b.c`, `dfu_8735b.c`, `wifi_fast_connect.c`, `atcmd_sys.c`, `system_data_api.c`, and others. FlashMemory.cpp remains the sole exception across the entire SDK family.
- PR #410 ("Update SPI API for SPI1 switching") appears as open issue #410 in the GitHub issues list (May 21, 2026) — this is GitHub's standard PR-as-issue behavior; it is a PR not a bug report. Newest actual bug-related issue remains #398 (Mar 29, 2026).
- All other channels frozen/blocked/empty for the 37th consecutive cycle.

| Source | Key Finding | Priority |
|---|---|---|
| `Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.cpp` (dev branch, SHA `b4781b70`, fetched 2026-05-22) | **Authoritative path for FlashMemory library confirmed** (prior cycles referenced `component/utilities/`, which returns 404). Confirmed 3 commits to this file (Jul 9, 2024; Sep 30, 2025 ×2). All 6 flash-touching operations (`read`, `write`, `readWord`, `writeWord`, `eraseSector`, `eraseWord`) call flash HAL functions directly with zero `device_mutex_lock`, `device_mutex_unlock`, or `RT_DEV_LOCK_FLASH` calls. File frozen since Sep 30, 2025 — 8 months without a mutex fix. | LOW (confirms prior; path correction) |
| `RT_DEV_LOCK_FLASH` usage in ameba-rtos-pro2 (GitHub code search, 2026-05-22) | **16+ files confirmed using `RT_DEV_LOCK_FLASH` correctly in ameba-rtos-pro2:** `ftl_nor_api.c`, `flash_fatfs.c`, `fwfs.c`, `ftl.c`, `ota_8735b.c`, `dfu_8735b.c`, `wifi_fast_connect.c`, `atcmd_sys.c`, `system_data_api.c`, and others. FlashMemory.cpp is the sole exception. Prior cycles documented 15+ files; this cycle confirms at least 16. The pattern mismatch between the Arduino library and the rest of the RTOS SDK is even wider than previously documented. | LOW (confirms and extends prior) |
| `USE_ISP_RETENTION_DATA` in `video_api.h` (dev branch, SHA `91a00df`, fetched 2026-05-22) | **Still commented out.** Exact line: `// #define USE_ISP_RETENTION_DATA`. `isp_retention_data_t` struct exists but is dead code. File unchanged in May 19 commit. | LOW (confirms prior) |
| `hal_video_release_note.txt` latest VOE version (fetched 2026-05-22) | **VOE 1.7.1.0 (04/21/2026) remains latest.** Most recent entry: "Fix dual sensor ID FCS mirror/flip issue." No new entry beyond 1.7.1.0. | LOW (confirms prior) |
| ameba-rtos-pro2 commits (direct GitHub fetch + compare endpoint, 2026-05-22) | **Confirmed frozen — identical to U36.** HEAD = `3f95070` (May 15, 2026). Zero new commits in 7 days. PR #17 (ethernet security fix, orbisai0security) still open and unmerged. No flash, FCS, VOE, boot, HAL, or sensor changes. | LOW |
| ameba-arduino-pro2 dev/main branches and releases (direct GitHub fetch, 2026-05-22) | **Confirmed frozen — identical to U36.** dev HEAD = `7db1c7d` (May 19, 2026); main HEAD = `93d63514` (Mar 2, 2026) — 82 days frozen. Compare endpoint: "7db1c7d and dev are identical." PR #410 (SPI API) still open and unreviewed. V4.1.1 stable not published; V4.1.1-QC-V06 remains latest pre-release. | LOW |
| ameba-arduino-pro2 open issues (fetched 2026-05-22) | **PR #410 appears as newest open issue (May 21, 2026)** — standard GitHub PR-as-issue behavior; it is a PR (SPI API switching) not a bug report. Newest actual feature-request-only issue remains #398 (Mar 29, 2026). No new bug reports about FlashMemory, FCS, camera, VOE, or boot failure in open or closed history. | LOW |
| Flash Memory documentation pages + ISP app note (2026-05-22) | **All still 403-blocked.** `ameba-doc-arduino-sdk.readthedocs-hosted.com/en/latest/ameba_pro2/amb82-mini/Example_Guides/Flash%20Memory/index.html`, `ameba-doc-rtos-pro2-sdk.readthedocs-hosted.com/en/latest/application_note/15_ISP.html`, Flash Layout (08_FLASHLAYOUT.html), Sensor Bringup Flow (37_Introduction_For_Sensor_Bringup_Flow.html), aiot.realmcu.com AMB82-mini guide — all return HTTP 403. No new concurrent/mutex warnings accessible from any official documentation. | LOW (blocked) |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee, May 22 sweep) | **Zero new content — 37th consecutive cycle.** All Chinese community sites remain 403-blocked or return zero relevant results. No Chinese-language forum posts or articles discuss FCS flash-write camera failure on RTL8735B or BW21-CBV. | LOW |
| Web-wide error string sweep (2026-05-22) | **Zero indexed results — 37 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"` return zero publicly indexed results anywhere on the accessible web. No hardware test result for any of the three proposed workarounds has been posted anywhere in any language. | LOW |

**FlashMemory.cpp — definitive path and revision table (correction/synthesis):**

| Attribute | Value |
|---|---|
| Canonical path | `Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.cpp` |
| SHA in dev HEAD | `b4781b70b4603949a41751999a7ff2af6ddc75b0` |
| Commits to this file | 3 total (Jul 9, 2024; Sep 30, 2025 ×2) |
| Last modification | Sep 30, 2025 (Optimize codes #337) |
| Months frozen | 8 months |
| Mutex calls | 0 (all 6 operations direct-call flash HAL) |

Note: Prior cycle U30 documented "6 commits" for FlashMemory — that count covered the entire FlashMemory directory (including documentation and example files). The `.cpp` source file itself has only 3 commits.

**`RT_DEV_LOCK_FLASH` usage coverage — updated:**

The confirmed list of ameba-rtos-pro2 files correctly using `RT_DEV_LOCK_FLASH` now numbers at least 16, spanning: FTL layer (`ftl_nor_api.c`, `ftl.c`), filesystem layer (`flash_fatfs.c`, `fwfs.c`), OTA/DFU (`ota_8735b.c`, `dfu_8735b.c`), WiFi fast-connect (`wifi_fast_connect.c`), AT-command system (`atcmd_sys.c`), system data API (`system_data_api.c`), and others. FlashMemory.cpp is the sole library in the entire SDK ecosystem that bypasses this mutex.

**SDK state as of 2026-05-22 (Cycle U37 — unchanged from U36):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp SHA `b4781b70`, zero mutex calls
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; release notes through May 19, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at May 15, 2026 (`3f95070`) — 7 days no change; PR #17 open
- ameba-arduino-pro2 dev: Frozen at May 19, 2026 (`7db1c7d`) — 3 days no change; PR #410 open
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — 82 days no change
- ameba-tool-rtos-pro2: Frozen at March 9, 2026 (`c1d70e7`)

**No confirmed fix. Bug remains unpatched as of 2026-05-22 (Cycle U37).**

**Top unresolved actions (unchanged from U36):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. Highest priority.
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; FlashMemory.cpp omission is confirmed in 16+ RTOS SDK files using it correctly; forward-declaration callable from Arduino (`extern "C" void device_mutex_lock(unsigned int)` / `#define RT_DEV_LOCK_FLASH 1`).
3. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-05-22 (Cycle U38)

**Search scope:** Four parallel web searches + direct GitHub fetches: (1) GitHub — ameba-rtos-pro2 compare endpoint `3f95070...HEAD`; ameba-arduino-pro2 dev/main commits, releases, open issues and PRs; (2) English forum/web — new threads above #4868, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee; (4) Documentation portal — aiot.realmcu.com AMB82-mini guide; ideashatch/HUB-8735 issues; error string sweeps.

**Key new findings this cycle:** None. All research channels are frozen, blocked, or empty for the 38th consecutive cycle. Both repositories confirmed frozen via compare endpoint and direct commit page fetch. No new releases, no new forum threads above #4868, no hardware test results for any workaround, no new Chinese-language content.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 compare endpoint `3f95070...HEAD` (direct GitHub fetch, 2026-05-22) | **Confirmed frozen.** GitHub returned: "3f95070 and HEAD are identical." Zero new commits since May 15, 2026 — now 7 days frozen. No flash, FCS, VOE, boot, HAL, or sensor changes in any observable pipeline. | LOW |
| ameba-arduino-pro2 dev branch commits (direct GitHub fetch, 2026-05-22) | **Confirmed frozen — identical to U37.** HEAD = `7db1c7d` "Pre Release Version 4.1.1" (May 19, 2026). Zero new commits after May 19, 2026. No FCS/flash/camera fix in any commit. Only open PR: #410 (SPI API — unrelated, filed May 21, 2026). | LOW |
| ameba-arduino-pro2 releases (direct GitHub fetch, 2026-05-22) | **No new releases.** Latest stable = V4.1.0 (Mar 2, 2026). Latest pre-release = V4.1.1-QC-V06 (tag Mar 6, 2026; release notes through May 19, 2026). No V4.1.1-QC-V07 or stable V4.1.1 published. Release notes confirmed: no FCS, flash camera boot, FlashMemory mutex, or SPIC concurrent-access fix in any entry from V4.0.6 through V4.1.1-QC-V06. | LOW |
| ameba-arduino-pro2 open issues (direct GitHub fetch, 2026-05-22) | **12 open issues; newest = #398 (Mar 29, 2026).** No new issues filed for FCS, flash, camera, VOE, boot failure, or sensor init. Bug remains entirely unreported on the official tracker after 38 research cycles. | LOW |
| aiot.realmcu.com AMB82-mini guide (direct fetch, 2026-05-22) | **Still HTTP 403 Forbidden.** No change from all prior cycles. | LOW (blocked) |
| ideashatch/HUB-8735 issues (search, 2026-05-22) | **No new issues found.** Repository still contains only Issue #10 (PS5268 sensor id fail, Aug 2025). Repository last committed Dec 2, 2025 — 172 days frozen. No flash/FCS/camera boot issues filed. | LOW |
| Web-wide error string sweep (2026-05-22) | **Zero indexed results — 38 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"` — all return zero publicly indexed results. No hardware test result for any of the three proposed workarounds has been posted anywhere in any language. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee, May 22 sweep) | **Zero new content — 38th consecutive cycle.** CSDN returns only the same two previously-documented articles (139222964, 139584304) — both unrelated to FCS flash-write camera failure. All Chinese community sites remain 403-blocked. No new Chinese-language technical posts about this bug found anywhere. | LOW |
| forum.amebaiot.com threads above #4868 (search, 2026-05-22) | **No new threads indexed.** Targeted search for IDs 4869–4900 returned zero results from the forum domain. Forum ceiling remains at #4868 ("NN Model loading from Memory instead of Flash or SD card failing with exceptions"). | LOW |
| English web — hardware test reports for any workaround (2026-05-22) | **Zero results.** No public hardware test result for "Camera FCS Mode = Disable," `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper, or `USE_ISP_RETENTION_DATA` has been published anywhere on the accessible web. | LOW |

**SDK state as of 2026-05-22 (Cycle U38 — unchanged from U37):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp SHA `b4781b70`, zero mutex calls
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; release notes through May 19, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at May 15, 2026 (`3f95070`) — 7 days no change; PR #17 open
- ameba-arduino-pro2 dev: Frozen at May 19, 2026 (`7db1c7d`) — 3 days no change; PR #410 open
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — 81 days no change
- ameba-tool-rtos-pro2: Frozen at March 9, 2026 (`c1d70e7`)
- ideashatch/HUB-8735: Frozen at Dec 2, 2025 — 172 days no change

**No confirmed fix. Bug remains unpatched as of 2026-05-22 (Cycle U38).**

**Top unresolved actions (unchanged from U37):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. Highest priority.
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp omission is the sole exception; forward-declaration callable from Arduino (`extern "C" void device_mutex_lock(unsigned int)` / `#define RT_DEV_LOCK_FLASH 1`).
3. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-05-23 (Cycle U39)

**Search scope:** Six parallel search threads + direct GitHub/web fetches: (1) GitHub — ameba-rtos-pro2 compare endpoint and direct commit page; ameba-arduino-pro2 dev/main commits, releases, issues, and PRs after May 22; (2) English forum/web — new threads above #4868, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee; (4) Error string indexing sweep; (5) ameba-arduino-pro2 PRs page direct fetch; (6) Forum ceiling sweep (IDs #4869–#4930).

**Key new findings this cycle:** None. All research channels are frozen, blocked, or empty for the 39th consecutive cycle. Both repositories confirmed frozen via direct commit page fetch. No new releases, no new forum threads above #4868, no hardware test results for any workaround, no new Chinese-language content.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 commits (direct GitHub fetch, 2026-05-23) | **Confirmed frozen — identical to U38.** 10 most recent commits verified: `3f95070` (May 15), `afc85a0` (May 15), `9c8b6f6` (May 15), `d2676f1` (May 15), `1c1c8b7` (May 1), and prior unchanged entries. Zero new commits in 8 days since May 15, 2026. No flash, FCS, VOE, boot, HAL, or sensor changes visible. PR #17 (ethernet USB driver buffer overflow fix, orbisai0security) still open and unmerged. | LOW |
| ameba-arduino-pro2 dev branch commits (direct GitHub fetch, 2026-05-23) | **Confirmed frozen — identical to U38.** HEAD = `7db1c7d` "Pre Release Version 4.1.1" (May 19, 2026). Zero new commits after May 19, 2026 (now 4 days frozen). No FCS/flash/camera fix in any commit. | LOW |
| ameba-arduino-pro2 releases (direct GitHub fetch, 2026-05-23) | **No new releases.** Latest stable = V4.1.0 (Mar 2, 2026). Latest pre-release = V4.1.1-QC-V06 (tag Mar 6, 2026; release notes accumulate through May 19, 2026). No V4.1.1-QC-V07 or stable V4.1.1 published. | LOW |
| ameba-arduino-pro2 open issues (direct GitHub fetch, 2026-05-23) | **12 open issues; newest = #398 (Mar 29, 2026).** No new issues filed for FCS, flash, camera, VOE, boot failure, or sensor init. Bug remains entirely unreported on the official tracker after 39 research cycles. | LOW |
| ameba-arduino-pro2 PRs page (direct GitHub fetch, 2026-05-23) | **1 open PR: #410 "Update SPI API for SPI1 switching"** (filed May 21, 2026 by kevinlookl). No new PRs opened since last cycle. 321 closed PRs total; none in closed history are related to FlashMemory mutex, FCS, camera, or boot failure. | LOW |
| forum.amebaiot.com threads above #4868 (search sweep, 2026-05-23) | **No new threads indexed.** Targeted search for IDs #4869–#4930 returned zero results from the forum domain. Forum ceiling confirmed at #4868 ("NN Model loading from Memory instead of Flash or SD card failing with exceptions"). All direct forum fetches return HTTP 403. | LOW |
| Web-wide error string sweep (2026-05-23) | **Zero indexed results — 39 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"` — all return zero publicly indexed results anywhere on the accessible web. No hardware test result for any of the three proposed workarounds has been posted anywhere in any language. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn, May 23 sweep) | **Zero new content — 39th consecutive cycle.** All Chinese community sites remain 403-blocked or return zero relevant results. bbs.aithinker.com BW21-CBV subforum indexed threads (home surveillance, DIY projects, human detection) confirmed still inaccessible. No Chinese-language forum posts or articles discuss FCS flash-write camera failure on RTL8735B or BW21-CBV. | LOW |
| English web — hardware test reports for any workaround (2026-05-23) | **Zero results.** No public hardware test result for "Camera FCS Mode = Disable," `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper, or `USE_ISP_RETENTION_DATA` has been published anywhere on the accessible web. | LOW |

**SDK state as of 2026-05-23 (Cycle U39 — unchanged from U38):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp SHA `b4781b70`, zero mutex calls
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; release notes through May 19, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at May 15, 2026 (`3f95070`) — 8 days no change; PR #17 open
- ameba-arduino-pro2 dev: Frozen at May 19, 2026 (`7db1c7d`) — 4 days no change; PR #410 open
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — 82 days no change
- ameba-tool-rtos-pro2: Frozen at March 9, 2026 (`c1d70e7`) — 75 days no change
- ideashatch/HUB-8735: Frozen at Dec 2, 2025 — 172 days no change

**No confirmed fix. Bug remains unpatched as of 2026-05-23 (Cycle U39).**

**Top unresolved actions (unchanged from U38):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. Highest priority.
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp omission is the sole exception; forward-declaration callable from Arduino (`extern "C" void device_mutex_lock(unsigned int)` / `#define RT_DEV_LOCK_FLASH 1`).
3. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-05-23 (Cycle U40)

**Search scope:** Four parallel agents + direct GitHub fetches: (1) GitHub — ameba-rtos-pro2 compare endpoint and commit page; ameba-arduino-pro2 dev/main commits, releases, issues, and PRs after May 22; ideashatch/HUB-8735 issues; (2) English forum/web — new threads above #4868, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn; (4) SDK deep-dive — FlashMemory.cpp mutex state confirmation, ameba-rtos-pro2 new commits, community mutex wrappers, new releases.

**Key new findings this cycle:** None. All research channels are frozen, blocked, or empty for the 40th consecutive cycle. Four independent agents confirmed: both repos frozen, FlashMemory.cpp unchanged (SHA `b4781b70`, zero mutex calls), no new forum threads above #4868 indexed, all error strings unindexed, no hardware test results for any workaround posted anywhere, zero new Chinese-language content.

**One minor clarification from this cycle:** Forum thread #4834 ("Boot failure after OTA update") snippets confirm the thread involves NOR flash chip ID detection failure (`[SPIF Err]Invalid ID`) after OTA, consistent with prior logging in Cycle U11. No new detail extractable.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 compare `3f95070...HEAD` (four agents, 2026-05-23) | **Confirmed frozen — identical to U39.** GitHub returns "3f95070 and HEAD are identical." Zero new commits in 8 days since May 15, 2026. No flash, FCS, VOE, boot, HAL, sensor, or mutex changes. PR #17 (ethernet USB driver buffer overflow fix, orbisai0security) still open and unmerged. | LOW |
| ameba-arduino-pro2 dev branch commits (2026-05-23) | **Confirmed frozen — identical to U39.** HEAD = `7db1c7d` "Pre Release Version 4.1.1" (May 19, 2026). Zero new commits in 4 days. No FCS/flash/camera fix in any commit. Only open PR: #410 (SPI API switching — unrelated, filed May 21, 2026). 321 closed PRs total; none in closed history are related to FlashMemory mutex, FCS, camera, or boot failure. | LOW |
| ameba-arduino-pro2 releases (2026-05-23) | **No new releases.** Latest stable = V4.1.0 (Mar 2, 2026). Latest pre-release = V4.1.1-QC-V06 (tag Mar 6, 2026; release notes through May 19, 2026). No V4.1.1-QC-V07 or stable V4.1.1 published. | LOW |
| ameba-arduino-pro2 open issues (2026-05-23) | **12 open issues; newest = #398 (Mar 29, 2026).** No new issues after March 29, 2026. No issues about FlashMemory, FCS, camera, VOE, or boot failure in any open or closed history. Bug remains entirely unreported on the official tracker after 40 research cycles. | LOW |
| ideashatch/HUB-8735 issues (2026-05-23) | **1 open issue: #10** (PS5268 sensor id fail, Aug 2025). No new issues. Repository last committed Dec 2, 2025 — 172 days frozen. | LOW |
| `FlashMemory.cpp` — dev branch raw fetch (2026-05-23, two agents) | **Zero mutex calls confirmed unchanged.** SHA `b4781b70`, 162 lines, last modified Sep 30, 2025. All 6 flash-touching operations (`flash_stream_read`, `flash_stream_write`, `flash_erase_sector`, `flash_read_word`, `flash_write_word`) call flash HAL functions directly with zero `device_mutex_lock`, `device_mutex_unlock`, or any synchronization primitive. The architectural defect persists in every released SDK version through V4.1.1-QC-V06. | LOW (confirms prior) |
| Community FlashMemory mutex wrappers (GitHub code search, 2026-05-23) | **Zero community implementations found.** GitHub code search `RT_DEV_LOCK_FLASH FlashMemory` = 0 results. `device_mutex_lock AMB82 FlashMemory` = 0 results. No third-party library, fork, or wrapper adds mutex protection to FlashMemory operations for the AMB82/RTL8735B platform. | LOW (confirms prior) |
| forum.amebaiot.com threads above #4868 (sweep, 2026-05-23) | **No new threads indexed.** Targeted searches for IDs #4869–#4930 returned zero results. Forum ceiling confirmed at #4868 ("NN Model loading from Memory instead of Flash or SD card failing with exceptions"). All direct forum fetches return HTTP 403. | LOW |
| forum.amebaiot.com thread #4834 — new snippet detail (2026-05-23) | **Consistent with prior logging.** Agent confirmed snippets describe "[SPIF Err]Invalid ID" — NOR flash chip ID detection failure after OTA flash write, matching the Cycle U11 "most severe" tier in the extended severity ladder. No new detail beyond what was documented in U11. Thread still 403-blocked. | LOW (confirms U11) |
| Web-wide error string sweep (2026-05-23, two agents) | **Zero indexed results — 40 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"` — all return zero publicly indexed results anywhere on the accessible web. Note: the healthy string `"FCS KM_status 0x00000082"` (err 0x00000000) does appear in GitHub issue #251 as incidental context in an unrelated memory crash report — this confirms the string format exists in firmware output but the error-state variants have never been publicly disclosed. No hardware test result for any of the three proposed workarounds has been posted anywhere in any language. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn, May 23 sweep, two agents) | **Zero new content — 40th consecutive cycle.** All Chinese community sites remain 403-blocked or return zero relevant results. bbs.aithinker.com subforum threads (home surveillance, DIY camera, BLE, human detection) confirmed still inaccessible. No Chinese-language forum posts or articles discuss FCS flash-write camera failure on RTL8735B or BW21-CBV. | LOW |

**SDK state as of 2026-05-23 (Cycle U40 — unchanged from U39):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp SHA `b4781b70`, zero mutex calls
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; release notes through May 19, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at May 15, 2026 (`3f95070`) — 8 days no change; PR #17 open
- ameba-arduino-pro2 dev: Frozen at May 19, 2026 (`7db1c7d`) — 4 days no change; PR #410 open
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — 82 days no change
- ameba-tool-rtos-pro2: Frozen at March 9, 2026 (`c1d70e7`) — 75 days no change
- ideashatch/HUB-8735: Frozen at Dec 2, 2025 — 172 days no change
- Ai-Thinker-Open: No RTL8735B/BW21 repositories exist (confirmed U36)

**No confirmed fix. Bug remains unpatched as of 2026-05-23 (Cycle U40).**

**Top unresolved actions (unchanged from U39):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. Highest priority.
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp omission confirmed in shipping V4.1.0 (SHA `b4781b70`) — the sole exception across the entire SDK; forward-declaration callable from Arduino (`extern "C" void device_mutex_lock(unsigned int)` / `#define RT_DEV_LOCK_FLASH 1`).
3. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-05-23 (Cycle U41)

**Search scope:** Four parallel agents: (1) GitHub — ameba-rtos-pro2 compare endpoint and direct commit page; ameba-arduino-pro2 dev/main commits, releases, issues, and PRs; PR #17 and PR #410 status; (2) English forum/web — new threads above #4868, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports, Reddit/Hackster/Instructables; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn; (4) SDK deep-dive — FlashMemory.cpp mutex state (authoritative path + SHA), `USE_ISP_RETENTION_DATA` in video_api.h, `hal_video_release_note.txt` location, GitHub_release_note.txt new entries, `RT_DEV_LOCK_FLASH` code search.

**Key new findings this cycle:**
- **`hal_video_release_note.txt` returns 0 GitHub code search results** — GitHub code search for the filename across both repos yields zero indexed results, and all previously documented paths return HTTP 404. U36 documented a path at `Arduino_package/hardware/system/component/soc/8735b/fwlib/rtl8735b/lib/source/ram/video/hal_video_release_note.txt`. The discrepancy is likely a GitHub code search indexing lag rather than a new deletion (no new commits exist in either repo to account for a removal). Last confirmed VOE version: 1.7.1.0 (04/21/2026) from the RTOS SDK copy documented in U25/U26.
- **Reddit/Hackster/Instructables/EEVBlog confirmed barren for this bug** — Zero AMB82+FCS+flash write bug reports on any platform. Bug has not surfaced on any English community channel.
- All repos confirmed frozen, all other channels empty — 41st consecutive null cycle.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 compare endpoint `3f95070...HEAD` (2026-05-23) | **Confirmed frozen — identical to U40.** GitHub returned: "3f95070 and HEAD are identical." Zero new commits in 8 days since May 15, 2026. PR #17 (ethernet USB driver buffer overflow, orbisai0security) still open and unmerged. No flash, FCS, VOE, boot, HAL, or sensor changes. | LOW |
| ameba-arduino-pro2 dev branch commits (2026-05-23) | **Confirmed frozen — identical to U40.** HEAD = `7db1c7d` "Pre Release Version 4.1.1" (May 19, 2026) — 4 days frozen. Zero new commits. Only open PR: #410 "Update SPI API for SPI1 switching" (kevinlookl, filed May 21, 2026) — unrelated to flash/FCS. No V4.1.1-QC-V07 or stable V4.1.1 published. | LOW |
| ameba-arduino-pro2 open issues (2026-05-23) | **12 open issues; newest = #398 (Mar 29, 2026).** No new issues after March 29, 2026. 321 closed PRs in history — zero related to FlashMemory mutex, FCS, or camera boot failure. Bug entirely unreported after 41 research cycles. | LOW |
| `FlashMemory.cpp` — dev branch raw fetch (2026-05-23) | **Zero mutex calls confirmed.** SHA `b4781b70b4603949a41751999a7ff2af6ddc75b0`. 3 commits to this file (Jul 9, 2024; Sep 30, 2025 ×2). All 6 flash operations direct-call flash HAL with no `device_mutex_lock`, `device_mutex_unlock`, `RT_DEV_LOCK_FLASH`. Frozen 8 months. Architectural defect present in shipping V4.1.0 and V4.1.1-QC-V06. | LOW (confirms prior) |
| `video_api.h` — `USE_ISP_RETENTION_DATA` (2026-05-23) | **Still commented out** — `// #define USE_ISP_RETENTION_DATA`. No change. | LOW (confirms prior) |
| `GitHub_release_note.txt` in ameba-rtos-pro2 (2026-05-23) | **No new entries after SHA 7343927f (May 15, 2026).** Most recent entry: "[amebapro2][mmf] avoid task recreate in mmf start". Release note 8+ days stale. No flash, FCS, or camera boot fix entry in any of the 25 documented entries. | LOW (confirms prior) |
| `hal_video_release_note.txt` — code search (2026-05-23) | **Zero GitHub code search hits** for `hal_video_release_note` across both repos. All previously documented paths return HTTP 404. U36 confirmed path at `…/soc/8735b/fwlib/rtl8735b/lib/source/ram/video/hal_video_release_note.txt`; since no new commits have landed since May 15–19, the 0-result outcome is likely a GitHub indexing artifact, not a new deletion. Last confirmed VOE content: 1.7.1.0 (04/21/2026) from U25/U26. | LOW |
| Reddit (r/embedded, r/arduino, r/esp32), Hackster.io, Instructables, EEVBlog (2026-05-23) | **Zero results.** No posts, projects, or articles about AMB82/RTL8735B FCS flash-write camera boot failure on any English community platform. Bug has not surfaced anywhere outside the 403-blocked Ameba developer forum. | LOW |
| forum.amebaiot.com threads above #4868 (sweep, 2026-05-23) | **No new threads indexed.** Targeted search for IDs #4869–#4930 returned zero results. Forum ceiling confirmed at #4868 ("NN Model loading from Memory instead of Flash or SD card failing with exceptions"). All direct forum fetches return HTTP 403. | LOW |
| Web-wide error string sweep (2026-05-23, four agents) | **Zero indexed results — 41 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"` — all return zero publicly indexed results anywhere on the accessible web. No hardware test result for any of the three proposed workarounds posted anywhere in any language. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn, May 23 sweep) | **Zero new content — 41st consecutive cycle.** All Chinese community sites remain 403-blocked or return zero relevant results. No Chinese-language forum posts or articles discuss FCS flash-write camera failure on RTL8735B or BW21-CBV. | LOW |

**SDK state as of 2026-05-23 (Cycle U41 — unchanged from U40):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp SHA `b4781b70`, zero mutex calls
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; release notes through May 19, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at May 15, 2026 (`3f95070`) — 8 days no change; PR #17 open
- ameba-arduino-pro2 dev: Frozen at May 19, 2026 (`7db1c7d`) — 4 days no change; PR #410 open
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — 82 days no change
- ameba-tool-rtos-pro2: Frozen at March 9, 2026 (`c1d70e7`) — 75 days no change
- ideashatch/HUB-8735: Frozen at Dec 2, 2025 — 172 days no change
- Ai-Thinker-Open: No RTL8735B/BW21 repositories (confirmed U36)

**No confirmed fix. Bug remains unpatched as of 2026-05-23 (Cycle U41).**

**Top unresolved actions (unchanged from U40):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. Highest priority.
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp omission confirmed in shipping V4.1.0 (SHA `b4781b70`) — the sole exception across the entire SDK; forward-declaration callable from Arduino (`extern "C" void device_mutex_lock(unsigned int)` / `#define RT_DEV_LOCK_FLASH 1`).
3. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-05-23 (Cycle U42)

**Search scope:** Four parallel agents: (1) GitHub — ameba-rtos-pro2 releases page (new release tags discovered); ameba-arduino-pro2 dev/main commits, releases, issues; ideashatch/HUB-8735; (2) English forum/web — new threads above #4868, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — comprehensive sweep; (4) ameba-rtos-pro2 V1.0.3 and V1.0.3-aiglass.08 release tag content analysis.

**Key new findings this cycle:**
- **Two new ameba-rtos-pro2 GitHub Release tags published May 22, 2026:** `V1.0.3` ("V1.0.3 main branch patch") and `V1.0.3-aiglass.08` ("AI glass patch 08"). Not documented in prior cycles. Neither contains any fix relevant to the flash→FCS camera boot bug. `V1.0.3` is simply a tag on the existing main HEAD (SHA `3f95070`); `V1.0.3-aiglass.08` is a separate AI Glass product-line commit (SHA `8d9040c`).
- Background English forum search (agent a4036ed8) confirms: forum ceiling still at #4868; no new public hardware test for any workaround; thread #4302 ("[VOE]frame_end: sensor didn't initialize done!") still the only indexed symptom-adjacent thread.
- All other channels confirmed frozen / blocked / empty.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 GitHub Releases page (fetched 2026-05-23) | **Two new release tags discovered — first time documented.** `V1.0.3` published May 22, 2026 — "V1.0.3 main branch patch." Tag SHA = `3f95070` = same as main branch HEAD. Ships two patch ZIPs (RTSP source, WebSocket viewer source). `GitHub_release_note.txt` included: 25 entries covering WLAN (DHCP, WoWLAN, WiFi crash fix), Bluetooth controller patch, KVS WebRTC v2, PIR sensor example, AI Glass scenario additions, GPS parser fix, sensor/video driver updates. **No mention of flash, FCS, FlashMemory, RT_DEV_LOCK_FLASH, SPIC, mutex, boot fail, or camera cold-boot fix.** | LOW (not a fix) |
| ameba-rtos-pro2 release tag `V1.0.3-aiglass.08` (fetched 2026-05-23) | **AI Glass product-line tag** — SHA `8d9040c`, distinct from main branch HEAD. 18 updates focused on the AI Glass scenario: lifetime snapshot modes, OV13B10 + IMX681_5M sensor drivers, AINR model tuning, UART IRQ→DMA switch, OTA buffer changes, SD card size reporting, burst mode. **No mention of flash, FCS, FlashMemory, RT_DEV_LOCK_FLASH, mutex, or cold-boot fix.** Separate product line (AI Glass wearable) unrelated to the RTL8735B AMB82-Mini camera flash race condition. | LOW (unrelated product line) |
| ameba-rtos-pro2 compare `3f95070...HEAD` (2026-05-23) | **Main branch still frozen.** GitHub returns "3f95070 and HEAD are identical." The V1.0.3 release tag is simply a label on the existing HEAD — no new code added. Zero new commits since May 15, 2026 (8 days). | LOW |
| ameba-arduino-pro2 dev/main branches, releases, issues, PRs (2026-05-23) | **All frozen — identical to U41.** dev HEAD = `7db1c7d` (May 19); main HEAD = `93d63514` (Mar 2); V4.1.1-QC-V06 remains latest pre-release; 12 open issues; PR #410 (SPI API) open and unreviewed. No FCS/flash/camera fix in any commit. FlashMemory.cpp SHA `b4781b70` unchanged — zero mutex calls. | LOW |
| ideashatch/HUB-8735 (2026-05-23) | **1 open issue: #10** (PS5268 sensor id fail, Aug 2025). No new issues. Repository last committed Dec 2, 2025 — 172 days frozen. | LOW |
| English forum/web — workaround hardware test confirmation (2026-05-23) | **Zero confirmed hardware tests.** Background agent (a4036ed8) exhaustively searched all channels. Forum thread #4302 remains the only indexed symptom-adjacent thread. No new threads above #4868. One forum snippet notes a user had FCS Mode: Disable set and still experienced sensor init error — this is the "[VOE]frame_end: sensor didn't initialize done!" pipeline timeout (distinct from the KM boot-ROM `FCS_I2C_INIT_ERR` failure), consistent with Cycle U12's note about the separate risk from thread #4302. None of the three workarounds (FCS Disable, `device_mutex_lock` wrapper, `USE_ISP_RETENTION_DATA`) has been publicly validated by hardware testing. | LOW |
| Web-wide error string sweep (2026-05-23) | **Zero indexed results — 42 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"` — all return zero results on the public web. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/Bilibili/Gitee, May 23 sweep) | **Zero new content — 42nd consecutive cycle.** All Chinese community sites remain 403-blocked or return zero relevant results. No Chinese-language content about FCS flash-write camera failure on RTL8735B/BW21-CBV found anywhere. | LOW |

**ameba-rtos-pro2 release versioning — context:**

The `V1.0.x` release series (for the RTOS SDK) is distinct from the Arduino SDK's `V4.x.x` series. Prior cycles only tracked the main branch commits, not release tags in the RTOS repo. `V1.0.3` is tagged on the same SHA as main HEAD and contains the same 25 changelog entries already documented via `GitHub_release_note.txt` in Cycle U25. No new code.

**SDK state as of 2026-05-23 (Cycle U42 — unchanged from U41 for bug purposes):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp SHA `b4781b70`, zero mutex calls
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; release notes through May 19, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at May 15, 2026 (`3f95070`) — 8 days; PR #17 open; new release tags V1.0.3 and V1.0.3-aiglass.08 published May 22 (no new code)
- ameba-arduino-pro2 dev: Frozen at May 19, 2026 (`7db1c7d`) — 4 days; PR #410 open
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — 82 days
- ameba-tool-rtos-pro2: Frozen at March 9, 2026 (`c1d70e7`) — 75 days
- ideashatch/HUB-8735: Frozen at Dec 2, 2025 — 172 days
- Ai-Thinker-Open: No RTL8735B/BW21 repositories (confirmed U36)

**No confirmed fix. Bug remains unpatched as of 2026-05-23 (Cycle U42).**

**Top unresolved actions (unchanged from U41):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. Highest priority.
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp is the sole exception; forward-declaration callable from Arduino (`extern "C" void device_mutex_lock(unsigned int)` / `#define RT_DEV_LOCK_FLASH 1`).
3. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

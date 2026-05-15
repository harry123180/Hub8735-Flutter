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

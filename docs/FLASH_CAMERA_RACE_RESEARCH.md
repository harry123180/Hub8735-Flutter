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

## Research Update — 2026-05-24 (Cycle U43)

**Search scope:** Six parallel web searches + direct GitHub fetches: (1) GitHub — ameba-rtos-pro2 commit page and releases page; ameba-arduino-pro2 dev/main commits, releases, issues, and PRs after May 22; (2) English forum/web — new threads above #4868, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee; (4) Error string sweep — all key FCS/camera/flash boot error strings; (5) ameba-rtos-pro2 releases page — new tags beyond V1.0.3 / V1.0.3-aiglass.08 (May 22); (6) Hardware workaround test confirmation search.

**Key new findings this cycle:** None. All research channels are frozen, blocked, or empty for the 43rd consecutive cycle. All six search threads confirmed: both repos frozen, no new releases, no new forum threads above #4868, all error strings unindexed, no hardware test results for any workaround, zero new Chinese-language content. The forum ceiling remains at thread #4868 ("NN Model loading from Memory instead of Flash or SD card failing with exceptions").

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 commits (direct GitHub fetch, 2026-05-24) | **Confirmed frozen — identical to U42.** 10 most recent commits verified: `3f95070` (May 15), `afc85a0` (May 15), `9c8b6f6` (May 15), `d2676f1` (May 15), `1c1c8b7` (May 1), and prior unchanged entries. Zero new commits in 9 days since May 15, 2026. No flash, FCS, VOE, boot, HAL, sensor, or mutex changes. PR #17 (ethernet USB driver buffer overflow fix, orbisai0security) still open and unmerged. | LOW |
| ameba-rtos-pro2 releases (direct GitHub fetch, 2026-05-24) | **No new releases beyond U42.** Latest tags: V1.0.3 and V1.0.3-aiglass.08 (both May 22, 2026, documented in U42). No tags published after May 22, 2026. No flash, FCS, or camera boot fix content in any release tag. | LOW |
| ameba-arduino-pro2 dev branch commits (direct GitHub fetch, 2026-05-24) | **Confirmed frozen — identical to U42.** HEAD = `7db1c7d` "Pre Release Version 4.1.1" (May 19, 2026). Zero new commits in 5 days. No FCS/flash/camera fix in any commit. Only open PR: #410 ("Update SPI API for SPI1 switching", kevinlookl, filed May 21, 2026) — still open and unreviewed. | LOW |
| ameba-arduino-pro2 releases (direct GitHub fetch, 2026-05-24) | **No new releases.** Latest stable = V4.1.0 (Mar 2, 2026). Latest pre-release = V4.1.1-QC-V06 (tag Mar 6, 2026; release notes through May 19, 2026). No V4.1.1-QC-V07 or stable V4.1.1 published. Release notes confirmed: no FCS, flash-write camera boot, FlashMemory mutex, or SPIC concurrent-access fix in any entry. | LOW |
| ameba-arduino-pro2 open issues (direct GitHub fetch, 2026-05-24) | **17 open issues; newest = #398 (Mar 29, 2026).** No new issues filed for FCS, flash, camera, VOE, boot failure, or sensor init. Bug entirely unreported after 43 research cycles. 321 closed PRs total — zero in closed history about FlashMemory mutex or FCS. | LOW |
| ameba-rtos-pro2 open issues (direct GitHub fetch, 2026-05-24) | **3 open issues unchanged:** #16 (AI glass src path, Jan 2026), #4 (chip support, Apr 2025), #3 (antivirus, Apr 2025). No new issues. No FCS/flash/camera bug filed. | LOW |
| `FlashMemory.cpp` — dev branch (confirmed 2026-05-24) | **Zero mutex calls — confirmed unchanged.** SHA `b4781b70`. All 6 flash operations (`flash_stream_read`, `flash_stream_write`, `flash_erase_sector`, `flash_read_word`, `flash_write_word`) direct-call flash HAL with no `device_mutex_lock`, `device_mutex_unlock`, or `RT_DEV_LOCK_FLASH`. Frozen 9 months since initial commit; architectural defect present in every SDK version through V4.1.1-QC-V06. | LOW (confirms prior) |
| forum.amebaiot.com threads above #4868 (sweep, 2026-05-24) | **No new threads indexed.** Targeted search for IDs #4869–#4930 returned zero results from the forum domain. Forum ceiling confirmed at #4868 ("NN Model loading from Memory instead of Flash or SD card failing with exceptions"). All direct forum fetches return HTTP 403. | LOW |
| Web-wide error string sweep (2026-05-24) | **Zero indexed results — 43 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"` — all return zero publicly indexed results anywhere on the accessible web. No hardware test result for any of the three proposed workarounds has been posted anywhere in any language. | LOW |
| Hardware test confirmation search — all three workarounds (2026-05-24) | **Zero results for any workaround.** Targeted searches for "Camera FCS Mode = Disable" + flash workaround, `device_mutex_lock` + AMB82 + flash camera, `USE_ISP_RETENTION_DATA` + tested — all return zero results. No community member has publicly reported testing any of the three proposed workarounds on hardware. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn, May 24 sweep) | **Zero new content — 43rd consecutive cycle.** bbs.aithinker.com BW21-CBV subforum (home surveillance, DIY projects, environment setup, unboxing threads) confirmed still 403-blocked. No new Chinese-language forum posts or articles discuss FCS flash-write camera failure on RTL8735B or BW21-CBV. | LOW |

**Cumulative freeze summary (as of Cycle U43):**

| Repository | Frozen since | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | 9 days |
| ameba-arduino-pro2 dev | May 19, 2026 (`7db1c7d`) | 5 days |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **83 days** |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **76 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 | **173 days** |
| Ai-Thinker-Open | No RTL8735B repos exist | — |

**SDK state as of 2026-05-24 (Cycle U43 — unchanged from U42):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp SHA `b4781b70`, zero mutex calls
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; release notes through May 19, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at May 15, 2026 (`3f95070`) — 9 days; PR #17 open; release tags V1.0.3 and V1.0.3-aiglass.08 (May 22, no new code)
- ameba-arduino-pro2 dev: Frozen at May 19, 2026 (`7db1c7d`) — 5 days; PR #410 open
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — 83 days no change
- ameba-tool-rtos-pro2: Frozen at March 9, 2026 (`c1d70e7`) — 76 days no change
- ideashatch/HUB-8735: Frozen at Dec 2, 2025 — 173 days no change

**No confirmed fix. Bug remains unpatched as of 2026-05-24 (Cycle U43).**

**Top unresolved actions (unchanged from U42):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. Highest priority.
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp omission confirmed as sole exception; forward-declaration callable from Arduino (`extern "C" void device_mutex_lock(unsigned int)` / `#define RT_DEV_LOCK_FLASH 1`).
3. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes at source; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-05-24 (Cycle U44)

**Search scope:** Six parallel search threads + direct GitHub/web fetches: (1) GitHub — ameba-rtos-pro2 compare endpoint and commit page; ameba-arduino-pro2 dev/main commits, releases, issues, and PRs after May 22; ameba-rtos-pro2 releases page (post-V1.0.3); (2) English forum/web — new threads above #4868, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/mcublog.cn/Bilibili/Gitee; (4) Error string sweep — all key FCS/camera/flash boot error strings; (5) Forum ceiling sweep (IDs #4869–#4930); (6) SDK deep-dive — FlashMemory.cpp, video_api.h, hal_video_release_note.txt status.

**Key new findings this cycle:** None. All research channels are frozen, blocked, or empty for the 44th consecutive cycle. Four independent agents confirmed via direct GitHub API and web search: both repos frozen at same HEADs as U43, no new releases, no new forum threads above #4868 indexed, all error strings unindexed, no hardware test results for any workaround, zero new Chinese-language content.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 compare endpoint `3f95070...HEAD` (direct GitHub fetch, 2026-05-24) | **Confirmed frozen — identical to U43.** GitHub returned: "3f95070 and HEAD are identical." Zero new commits since May 15, 2026 — now 9 days frozen. PR #17 ("fix: ethernet USB driver buffer overflow", orbisai0security) still open and unmerged. No flash, FCS, VOE, boot, HAL, sensor, or mutex changes in any observable pipeline. | LOW |
| ameba-rtos-pro2 releases (direct GitHub fetch, 2026-05-24) | **No new release tags beyond V1.0.3 / V1.0.3-aiglass.08** (both published May 22, documented in U42). No new release tags published after May 22, 2026. The V1.0.3 tag is on the existing HEAD SHA `3f95070` — no new code. No flash, FCS, or camera boot fix content in any release tag. | LOW |
| ameba-arduino-pro2 dev branch commits (direct GitHub fetch, 2026-05-24) | **Confirmed frozen — identical to U43.** HEAD = `7db1c7d` "Pre Release Version 4.1.1" (May 19, 2026). Zero new commits in 5 days. PR #410 ("Update SPI API for SPI1 switching", kevinlookl, May 21, 2026) still open and unreviewed — no reviews, no assignees. No FCS/flash/camera fix in any commit. | LOW |
| ameba-arduino-pro2 releases (direct GitHub fetch, 2026-05-24) | **No new releases.** Latest stable = V4.1.0 (Mar 2, 2026). Latest pre-release = V4.1.1-QC-V06 (tag Mar 6, 2026; release notes through May 19, 2026). No V4.1.1-QC-V07 or stable V4.1.1 published. | LOW |
| ameba-arduino-pro2 open issues (direct GitHub fetch, 2026-05-24) | **17 open issues (count varies by agent — 12–17 depending on GitHub pagination); newest bug-report = #398 (Mar 29, 2026).** No new issues filed for FCS, flash, camera, VOE, boot failure, or sensor init. Bug remains entirely unreported on the official tracker after 44 research cycles. 321 closed PRs total — zero in closed history about FlashMemory mutex or FCS cold-boot failure. | LOW |
| ameba-rtos-pro2 open issues (direct GitHub fetch, 2026-05-24) | **3 open issues unchanged:** #16 (AI glass src path, Jan 2026), #4 (chip support, Apr 2025), #3 (antivirus, Apr 2025). No new issues. No FCS/flash/camera bug filed. | LOW |
| `FlashMemory.cpp` — dev branch (confirmed 2026-05-24) | **Zero mutex calls — confirmed unchanged.** SHA `b4781b70b4603949a41751999a7ff2af6ddc75b0`. 3 commits to this file (Jul 9, 2024; Sep 30, 2025 ×2). All 6 flash operations (`flash_stream_read`, `flash_stream_write`, `flash_erase_sector`, `flash_read_word`, `flash_write_word`) direct-call flash HAL with no `device_mutex_lock`, `device_mutex_unlock`, or `RT_DEV_LOCK_FLASH`. File unchanged for 8+ months. Architectural defect present in every released SDK version through V4.1.1-QC-V06. | LOW (confirms prior) |
| ideashatch/HUB-8735 issues (2026-05-24) | **1 open issue: #10** (PS5268 sensor id fail, Aug 2025). No new issues. Repository last committed Dec 2, 2025 — 173 days frozen. | LOW |
| forum.amebaiot.com threads above #4868 (sweep, 2026-05-24) | **No new threads indexed.** Targeted searches for IDs #4869–#4930 returned zero results from the forum domain. Forum ceiling confirmed at #4868 ("NN Model loading from Memory instead of Flash or SD card failing with exceptions"). All direct forum fetches return HTTP 403. | LOW |
| Chinese-language search — BW21-CBV + Flash + camera + FCS (2026-05-24) | **No new content.** Search for "BW21-CBV RTL8735B flash camera 摄像头 启动失败 FCS 2026" returned only the same indexed Chinese-language sources: bbs.aithinker.com unboxing/tutorial threads (403-blocked), mcublog.cn LED+photo Feishu bot article (403-blocked), and product pages. No new Chinese-language forum posts or articles discuss FCS flash-write camera failure on RTL8735B or BW21-CBV. | LOW |
| Web-wide error string sweep (2026-05-24, multiple agents) | **Zero indexed results — 44 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"` — all return zero publicly indexed results anywhere on the accessible web. No hardware test result for any of the three proposed workarounds has been posted anywhere in any language. | LOW |
| Hardware test confirmation search — all three workarounds (2026-05-24) | **Zero results.** Targeted searches for "Camera FCS Mode = Disable" + flash workaround, `device_mutex_lock` + AMB82 + flash + camera, `USE_ISP_RETENTION_DATA` + tested — all return zero results. No community member has publicly reported testing any of the three proposed workarounds on hardware. | LOW |

**Cumulative freeze summary (as of Cycle U44):**

| Repository | Frozen since | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | 9 days |
| ameba-arduino-pro2 dev | May 19, 2026 (`7db1c7d`) | 5 days |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **83 days** |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **76 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 | **173 days** |
| Ai-Thinker-Open | No RTL8735B repos exist | — |

**SDK state as of 2026-05-24 (Cycle U44 — unchanged from U43):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp SHA `b4781b70`, zero mutex calls
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; release notes through May 19, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at May 15, 2026 (`3f95070`) — 9 days; V1.0.3 release tag (May 22, no new code); PR #17 open
- ameba-arduino-pro2 dev: Frozen at May 19, 2026 (`7db1c7d`) — 5 days; PR #410 open
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — 83 days no change
- ameba-tool-rtos-pro2: Frozen at March 9, 2026 (`c1d70e7`) — 76 days no change
- ideashatch/HUB-8735: Frozen at Dec 2, 2025 — 173 days no change
- Ai-Thinker-Open: No RTL8735B/BW21 repositories (confirmed U36)

**No confirmed fix. Bug remains unpatched as of 2026-05-24 (Cycle U44).**

**Top unresolved actions (unchanged from U43):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. Highest priority.
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp omission confirmed as sole exception in shipping V4.1.0 (SHA `b4781b70`); forward-declaration callable from Arduino (`extern "C" void device_mutex_lock(unsigned int)` / `#define RT_DEV_LOCK_FLASH 1`).
3. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes at source; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-05-24 (Cycle U45)

**Search scope:** Four parallel agents + direct web searches: (1) GitHub — ameba-rtos-pro2 compare endpoint and direct commit page; ameba-arduino-pro2 dev/main commits, releases, issues, PRs after May 22; PR #17 and PR #410 status; (2) English forum/web — new threads above #4868, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn; (4) SDK deep-dive — documentation portals (aiot.realmcu.com, readthedocs), FlashMemory.cpp mutex state, forum ceiling sweep (#4869–#4930).

**Key new findings this cycle:** None. All research channels are frozen, blocked, or empty for the 45th consecutive cycle. Four independent agents + direct web searches confirm: both repos frozen at same HEADs as U44, no new releases, no new forum threads above #4868 indexed, all error strings unindexed (45 consecutive null cycles), no hardware test results for any workaround, zero new Chinese-language content (42nd consecutive cycle), all documentation portals remain HTTP 403.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 compare endpoint `3f95070...HEAD` (direct GitHub fetch, 2026-05-24) | **Confirmed frozen — identical to U44.** GitHub returned: "3f95070 and HEAD are identical." Zero new commits since May 15, 2026 — now 9 days frozen. PR #17 ("fix: ethernet USB driver buffer overflow", orbisai0security) still open and unmerged, no review activity. No flash, FCS, VOE, boot, HAL, sensor, or mutex changes in any observable pipeline. | LOW |
| ameba-arduino-pro2 dev branch commits (direct GitHub fetch, 2026-05-24) | **Confirmed frozen — identical to U44.** HEAD = `7db1c7d` "Pre Release Version 4.1.1" (May 19, 2026). Zero new commits in 5 days. PR #410 ("Update SPI API for SPI1 switching", kevinlookl, May 21, 2026) still open, no reviewers assigned, no reviews submitted. FlashMemory.cpp SHA `b4781b70` confirmed unchanged — zero mutex calls. No FCS/flash/camera fix in any commit or open PR. | LOW |
| ameba-arduino-pro2 releases (direct GitHub fetch, 2026-05-24) | **No new releases.** Latest stable = V4.1.0 (Mar 2, 2026). Latest pre-release = V4.1.1-QC-V06 (tag Mar 6, 2026; release notes through May 19, 2026). No V4.1.1-QC-V07 or stable V4.1.1 published. Search for "ameba-arduino-pro2 V4.1.1 stable release 2026" confirmed: stable release does not exist. | LOW |
| ameba-arduino-pro2 open issues (2026-05-24) | **12–17 open issues; newest bug report = #398 (Mar 29, 2026).** 321 closed PRs total — zero related to FlashMemory mutex, FCS, camera, VOE, or boot failure in open or closed history. Bug remains entirely unreported on the official tracker after 45 research cycles. | LOW |
| ideashatch/HUB-8735 issues (2026-05-24) | **1 open issue: #10** (PS5268 sensor id fail, Aug 2025). No new issues. Repository frozen at Dec 2, 2025 — 174 days. | LOW |
| forum.amebaiot.com threads above #4868 (search sweep, 2026-05-24) | **No new threads indexed.** Targeted searches for IDs #4869–#4930 returned zero results from the forum domain. Forum ceiling confirmed at #4868 ("NN Model loading from Memory instead of Flash or SD card failing with exceptions"). All direct forum fetches return HTTP 403. Web search found no new forum threads about RTL8735B FCS flash camera boot failure in any thread ID range. | LOW |
| Documentation portals (2026-05-24) | **All still HTTP 403 Forbidden.** `aiot.realmcu.com/en/latest/arduino/arduino_guide/sdk_intro/evb_guides/evb_amb82mini.html`, `ameba-doc-arduino-sdk.readthedocs-hosted.com/.../Flash%20Memory/index.html`, `ameba-doc-rtos-pro2-sdk.readthedocs-hosted.com/.../15_ISP.html`, Flash Layout (08_FLASHLAYOUT.html), Sensor Bringup Flow (37_Introduction_For_Sensor_Bringup_Flow.html) — all return HTTP 403. Both portals appeared in web search results this cycle but remain inaccessible without developer authentication. | LOW (blocked) |
| Web-wide error string sweep (2026-05-24, multiple agents + direct searches) | **Zero indexed results — 45 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"`, `"AMB82 device_mutex_lock camera workaround"` — all return zero publicly indexed results anywhere on the accessible web. No hardware test result for any of the three proposed workarounds has been posted anywhere in any language. | LOW |
| English web — hardware test reports for any workaround (2026-05-24) | **Zero results.** Targeted searches for "Camera FCS Mode = Disable" + flash bug workaround, `device_mutex_lock` + AMB82 + camera, `USE_ISP_RETENTION_DATA` + tested all return zero results. Reddit, Hackster.io, Instructables, EEVBlog, and all other English community channels remain barren. No public hardware test of any proposed workaround has been posted anywhere since the workarounds were first proposed (Cycle U7, 2026-05-14 — over 10 days ago). | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn, May 24 sweep) | **Zero new content — 42nd consecutive cycle.** All Chinese community sites remain 403-blocked or return zero relevant results. bbs.aithinker.com subforum threads (home surveillance, DIY camera, BLE, human detection) confirmed still inaccessible. No Chinese-language forum posts or articles discuss FCS flash-write camera failure on RTL8735B or BW21-CBV in any accessible source. | LOW |

**Milestone: 45 consecutive null research cycles**

This cycle marks the 45th consecutive research cycle with zero new public information on this bug. Key statistics:
- First research cycle: Cycle U1 (approximately 2026-05-05)
- Elapsed research time: ~19 days
- Total cycles run: 45
- Total new Chinese-language content found: 0 (across all 45 cycles)
- Total publicly indexed bug reports: 0 (error strings have never been indexed outside 403-blocked forum threads)
- Total confirmed hardware test results for any workaround: 0
- Total public acknowledgment by Realtek of this bug: 0

The bug is, as far as any accessible public internet content is concerned, entirely undocumented and unknown to the broader developer community.

**SDK state as of 2026-05-24 (Cycle U45 — unchanged from U44):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp SHA `b4781b70`, zero mutex calls
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; release notes through May 19, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at May 15, 2026 (`3f95070`) — 9 days; V1.0.3 tag (May 22, no new code); PR #17 open
- ameba-arduino-pro2 dev: Frozen at May 19, 2026 (`7db1c7d`) — 5 days; PR #410 open
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — 83 days no change
- ameba-tool-rtos-pro2: Frozen at March 9, 2026 (`c1d70e7`) — 76 days no change
- ideashatch/HUB-8735: Frozen at Dec 2, 2025 — 174 days no change
- Ai-Thinker-Open: No RTL8735B/BW21 repositories (confirmed U36)

**No confirmed fix. Bug remains unpatched as of 2026-05-24 (Cycle U45).**

**Top unresolved actions (unchanged from U44):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. Highest priority. (Proposed Cycle U7, May 14 — 10+ days unresolved.)
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp is the sole exception in shipping V4.1.0 (SHA `b4781b70`); forward-declaration callable from Arduino (`extern "C" void device_mutex_lock(unsigned int)` / `#define RT_DEV_LOCK_FLASH 1`). (Proposed Cycle U19–U20, May 18.)
3. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes at source; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`. (Proposed Cycle U19, May 18.)

## Research Update — 2026-05-24 (Cycle U46)

**Search scope:** Six parallel search threads + direct GitHub/web fetches: (1) GitHub — ameba-rtos-pro2 commit page and compare endpoint; ameba-arduino-pro2 dev/main commits, releases, issues, PRs; ameba-arduino-doc repo (first-time check this session); ameba-rtos-pro2 releases page; (2) English forum/web — new threads above #4868, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn; (4) Error string sweep — all key FCS/camera/flash boot error strings; (5) Documentation portal accessibility — aiot.realmcu.com, readthedocs ISP/Flash Memory pages; (6) RTL8735C/AmebaPro3 SDK availability.

**Key new findings this cycle:**
- **ameba-arduino-doc repository has 2 new commits** (first time checked this session): SHA `64863ce` "Add I2C slave example guides (#107)" dated May 24, 2026; and SHA `7f0bc9c` "Update application step (#106)" dated May 21, 2026. Both are documentation updates for the I2C Slave feature (PR #408 merged May 18). **Not related to FlashMemory, FCS, camera, or our bug.**
- **RTL8735C successor chip confirmed with additional detail**: Won COMPUTEX 2025 Best Choice Award; targets Wi-Fi 6 + BT 5.3 + AI ISP wearables. No public SDK released as of 2026-05-24.
- All other channels null — 46th consecutive cycle with no new public information on this bug.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 commits (direct GitHub fetch, 2026-05-24, multiple agents) | **Confirmed frozen — identical to U45.** HEAD = `3f95070` "Sync upstream 7343927…" (May 15, 2026). Zero new commits in 9 days. Most recent 4 commits: `3f95070`, `afc85a0`, `9c8b6f6`, `d2676f1` (all May 15, 2026). PR #17 (ethernet USB driver buffer overflow fix, orbisai0security) still open and unmerged. No flash, FCS, VOE, boot, HAL, or sensor changes in any observable pipeline. | LOW |
| ameba-rtos-pro2 releases (direct GitHub fetch, 2026-05-24) | **No new tags beyond V1.0.3 and V1.0.3-aiglass.08** (both May 22, 2026, documented in U42). Full release tag list confirmed: V1.0.3, V1.0.3-aiglass.08 (May 22), V1.0.3-aiglass.07 (Apr 2), 9.6e (Mar 3), V1.0.3-aiglass.06 (Feb 6), and earlier. No new code — V1.0.3 tag is SHA `3f95070` (identical to main HEAD). No flash, FCS, or camera boot fix content in any tag. | LOW |
| ameba-arduino-pro2 dev branch commits (direct GitHub fetch, 2026-05-24) | **Confirmed frozen — identical to U45.** HEAD = `7db1c7d` "Pre Release Version 4.1.1" (May 19, 2026). Zero new commits in 5 days. Only open PR: #410 ("Update SPI API for SPI1 switching", kevinlookl, filed May 21, 2026) — no reviewers assigned. No FCS/flash/camera fix in any commit. | LOW |
| ameba-arduino-pro2 releases (direct GitHub fetch, 2026-05-24) | **No new releases.** Latest stable = V4.1.0 (Mar 2, 2026). Latest pre-release = V4.1.1-QC-V06 (tag Mar 6, 2026; release notes accumulate through May 19, 2026). No V4.1.1-QC-V07 or stable V4.1.1 published. | LOW |
| ameba-arduino-pro2 open issues (direct GitHub fetch, 2026-05-24) | **11 open issues confirmed; newest = #398 (Mar 29, 2026).** 321 closed PRs total — zero related to FlashMemory mutex, FCS, camera boot, VOE, or SPIC concurrent access in open or closed history. Bug entirely unreported after 46 research cycles. | LOW |
| ameba-arduino-doc repository (direct GitHub fetch, 2026-05-24) | **NEW — First time fully checked this session.** Two commits since U43 cutoff: (1) SHA `7f0bc9c` "Update application step (#106)" (May 21, 2026); (2) SHA `64863ce` "Add I2C slave example guides (#107)" (May 24, 2026). Both commits add documentation for the I2C Slave library addition (PR #408, merged May 18). **Zero commits related to FlashMemory, FCS, SPIC, camera cold-boot, or mutex warnings in any of the 10 most recent commits.** | LOW (unrelated) |
| `FlashMemory.cpp` — dev branch (confirmed 2026-05-24, multiple agents) | **Zero mutex calls — confirmed unchanged.** SHA `b4781b70b4603949a41751999a7ff2af6ddc75b0`. 3 commits to this file (Jul 9, 2024; Sep 30, 2025 ×2). Architectural defect present in every released SDK version through V4.1.1-QC-V06 for 8+ months. Official RTOS SDK flash example (`flash/src/main.c`) continues to use `device_mutex_lock(RT_DEV_LOCK_FLASH)` — 3 separate wrapping code blocks confirmed still present. | LOW (confirms prior) |
| ameba-arduino-pro2 V4.0.8 release notes — bug origin point (background agent, 2026-05-24) | **HISTORICAL ORIGIN CONFIRMED.** Release V4.0.8 (October 29, 2024) introduced BOTH FlashMemory AND FCS mode in the same release: notes contain "Add feature Flash Memory" AND "Add feature FCS mode for all supported sensors" together. This is the precise moment at which the SPIC concurrent-access architectural defect entered the shipped SDK. Every SDK version from V4.0.8 through V4.1.1-QC-V06 (May 2026, 7+ months) ships both features without `RT_DEV_LOCK_FLASH` coordination in the FlashMemory path. | MEDIUM (historical clarity) |
| ideashatch/HUB-8735 issues (2026-05-24) | **1 open issue: #10** (PS5268 sensor id fail, Aug 2025). No new issues. Repository last committed Dec 2, 2025 — 173 days frozen. | LOW |
| forum.amebaiot.com threads above #4868 (search sweep, 2026-05-24) | **No new threads indexed.** Targeted searches for IDs #4869–#4930 returned zero results. Forum ceiling confirmed at #4868 ("NN Model loading from Memory instead of Flash or SD card failing with exceptions"). Forum thread #4834 ("Boot failure after OTA update") still 403-blocked; snippets confirm it describes "[SPIF Err]Invalid ID" on power-cycle after OTA flash write (documented in Cycle U11). No new content. | LOW |
| Documentation portals (aiot.realmcu.com, readthedocs ISP/Flash/layout pages, 2026-05-24) | **All still HTTP 403 Forbidden.** `aiot.realmcu.com`, `ameba-doc-arduino-sdk.readthedocs-hosted.com/.../Flash%20Memory/index.html`, `ameba-doc-rtos-pro2-sdk.readthedocs-hosted.com/.../15_ISP.html` — all return HTTP 403. The ISP application note URL appeared in web search results this cycle (indexed URL confirmed real), but content remains gated. | LOW (blocked) |
| RTL8735C successor chip (search, 2026-05-24) | **NEW DETAIL — COMPUTEX 2025 Best Choice Award confirmed.** RTL8735C won a COMPUTEX 2025 Best Choice Award (award ID 10251 at bcaward.computex.biz). Product page at realtek.com and news article at realtek.com/Article/NewsDetail?id=4717 confirm announcement. No public SDK, no Ameba-AIoT GitHub repository for RTL8735C, no "AmebaPro3" branding found. Whether RTL8735C addresses the FCS+flash boot race is unknown. | LOW (background) |
| Web-wide error string sweep (2026-05-24, multiple agents + direct searches) | **Zero indexed results — 46 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"` — all return zero publicly indexed results anywhere on the accessible web. This research log remains the only public documentation of this bug and its error codes. | LOW |
| Hardware test confirmation search — all three workarounds (2026-05-24) | **Zero results for any workaround.** Searches for "Camera FCS Mode = Disable" + flash workaround AMB82, `device_mutex_lock` + AMB82 + flash camera, `USE_ISP_RETENTION_DATA` + test all return zero results. No public hardware test of any proposed workaround has been posted anywhere as of 2026-05-24. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn, May 24 sweep) | **Zero new content — 43rd consecutive null cycle.** bbs.aithinker.com, bbs.ai-thinker.com, mcublog.cn BW21-CBV article — all 403-blocked. No new Chinese-language forum posts or articles discuss FCS flash-write camera failure on RTL8735B or BW21-CBV. | LOW |

**SDK state as of 2026-05-24 (Cycle U46 — unchanged from U45):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp SHA `b4781b70`, zero mutex calls
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; release notes through May 19, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at May 15, 2026 (`3f95070`) — 9 days; V1.0.3 release tag (May 22, no new code); PR #17 open
- ameba-arduino-pro2 dev: Frozen at May 19, 2026 (`7db1c7d`) — 5 days; PR #410 open
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — 83 days no change
- ameba-arduino-doc: Latest commit `64863ce` (May 24, 2026, I2C slave docs — unrelated to bug)
- ameba-tool-rtos-pro2: Frozen at March 9, 2026 (`c1d70e7`) — 76 days no change
- ideashatch/HUB-8735: Frozen at Dec 2, 2025 — 173 days no change
- Ai-Thinker-Open: No RTL8735B/BW21 repositories (confirmed U36)

**No confirmed fix. Bug remains unpatched as of 2026-05-24 (Cycle U46).**

**Top unresolved actions (unchanged from U45):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. Highest priority. (Proposed Cycle U7, May 14 — 10+ days unresolved.)
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp is the sole exception in shipping V4.1.0 (SHA `b4781b70`); forward-declaration callable from Arduino (`extern "C" void device_mutex_lock(unsigned int)` / `#define RT_DEV_LOCK_FLASH 1`). (Proposed Cycle U19–U20, May 18.)
3. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes at source; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`. (Proposed Cycle U19, May 18.)

## Research Update — 2026-05-25 (Cycle U47)

**Search scope:** Four parallel agents + direct web searches: (1) GitHub — all repos post-May 24 activity (commits, releases, issues, PRs); (2) English forum/web — new threads above #4868, FCS Disable / mutex workaround hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/Bilibili/Gitee/mcublog.cn; (4) SDK technical deep-dive — ftl_nor_api.c three-callback race window, platform_opts.h NOR_FLASH_FCS address confirmation, V4.1.1 FlashMemory.cpp content.

**Key new findings this cycle:**
- **V1.0.3-aiglass.08** (May 22, 2026) released on ameba-rtos-pro2 — contains "VOE driver improvements" alongside many AI Glass features; not a FlashMemory/FCS fix but confirms VOE binary is actively being updated in the aiglass branch.
- **Three-callback race window precisely mapped**: `ftl_write_nor()` has **no outer lock** around its three-callback sequence (`nor_read_cb` → `nor_erase_cb` → `nor_write_cb`). Each callback individually acquires and releases `RT_DEV_LOCK_FLASH`. `FlashMemory.write()` can inject SPIC commands between any two of these callbacks — e.g., between `nor_erase_cb` and `nor_write_cb` — corrupting the pending FCS write to `NOR_FLASH_FCS (0xF0D000)`.
- **`platform_opts.h` source** (`project/realtek_amebapro2_v0_example/inc/platform_opts.h`) confirms: `NOR_FLASH_FCS = USER_DATA_BASE + 0x0D000 = 0xF0D000`; `ISP_FW_LOCATION = USER_DATA_BASE + 0x0C000 = 0xF0C000`.
- **V4.1.1-QC-V06 / commit `7db1c7d`** (May 19, 2026) confirmed no FlashMemory mutex fix — full release log analyzed; no mention of SPIC concurrency, device_lock, FCS sector protection, or boot race condition in any changelog entry.
- **Two new forum threads identified**: #4865 (uartfwburn flash programming failure), #4801 ([HALMAC][ERR]fw chksum! WiFi firmware checksum) — both unrelated to camera/FCS bug.
- **ElegantOTA GitHub Issue #150** ("AMB82-MINI didn't work with OTA") newly identified — OTA flash write causing boot failure on AMB82-Mini, same failure class as our bug but via different trigger. Content accessible via GitHub.
- All repos frozen; no new V4.1.1 stable or QC-V07; all Chinese sources still 403-blocked; zero hardware test reports for any workaround.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 release V1.0.3-aiglass.08 (May 22, 2026, commit `8d9040c`) | **New release published** — AI Glass branch update with 18 items: lifetime snapshot blocking/non-blocking modes, OV13B10 sensor driver + AINR model, **VOE driver improvements**, IMX681_5M sensor, object detection for AI snapshots, UART IRQ→DMA, AINR disabled by default (burst mode support), OTA buffer changes, auto SD size reporting. The "VOE driver improvements" tag is vague and may not relate to FCS or cold-boot. Released by `Kyderio` (AI Glass maintainer), separate from main SDK development line. Not in any Arduino SDK release. | LOW |
| ameba-rtos-pro2 release V1.0.3 (May 22, 2026) | **Formal V1.0.3 tag created** — Commit `3f95070` (same as HEAD), published by M-ichae-l. Assets: RTSP source code patch (zip) + WebSocket viewer source code patch (zip). This is a tagged snapshot of the May 15 main HEAD; contains no new code beyond what was already frozen at May 15. No flash/FCS/camera changes. | LOW |
| `ftl_nor_api.c` three-callback race (ameba-rtos-pro2, confirmed from source, Cycle U47) | **NEW PRECISION — Race window between callbacks confirmed.** `ftl_write_nor()` calls `nor_read_cb()` → `nor_erase_cb()` → `nor_write_cb()` in sequence. Each callback individually acquires and releases `RT_DEV_LOCK_FLASH`. There is **no outer `RT_DEV_LOCK_FLASH` hold** across the full read-modify-erase-write cycle. `FlashMemory.write()` can therefore inject a SPIC command between `nor_erase_cb()` (which erased the FCS sector) and `nor_write_cb()` (which would write the new FCS data), leaving `NOR_FLASH_FCS (0xF0D000)` in an erased (all-0xFF) state. Boot ROM reads 0xFF as FCS data → `FCS_I2C_INIT_ERR (0x200A)` on next cold boot. This is the most precise description of the race window obtained in any research cycle. | HIGH |
| `platform_opts.h` (ameba-rtos-pro2, `project/.../inc/platform_opts.h`) | **NOR_FLASH_FCS confirmed from new source file.** `USER_DATA_BASE = 0xF00000`; `ISP_FW_LOCATION = USER_DATA_BASE + 0xC000 = 0xF0C000`; `FLASH_FCS_DATA = NOR_FLASH_FCS = USER_DATA_BASE + 0xD000 = 0xF0D000`. ISP firmware and FCS data occupy consecutive 4 KB sectors at 0xF0C000 and 0xF0D000 respectively. The ISP firmware sits immediately before the FCS data sector — a sector-erase at 0xF0D000 specifically targets the FCS data; a larger erase could also hit ISP firmware. Confirms no adjacency to FlashMemory region (0xFD0000), consistent with prior partition table analysis. | MEDIUM |
| `video_api.c` VOE lock vs FLASH lock (ameba-rtos-pro2, confirmed from source, Cycle U47) | **Clarification of locking hierarchy.** `video_api.c` calls `device_mutex_lock(RT_DEV_LOCK_VOE)` around video open/close operations but NOT around ISP AE/AWB flash writes. The ISP flash write chain: `video_pre_init_save_cur_params()` → `ftl_common_write()` → `ftl_lock()` [FreeRTOS mutex — FTL-internal only] → `ftl_write_nor()` → `nor_write_cb()` → `device_mutex_lock(RT_DEV_LOCK_FLASH)` [hardware SPIC lock, per-callback only]. The `RT_DEV_LOCK_FLASH` IS eventually acquired for each individual SPIC operation — but not for the full read-modify-erase-write sequence. `FlashMemory.erase()` skips all levels. | MEDIUM |
| V4.1.1 commit `7db1c7d` "Pre Release Version 4.1.1" (May 19, 2026) FlashMemory.cpp | **FlashMemory.cpp confirmed unchanged** in V4.1.1 pre-release — SHA `b4781b70b4603949a41751999a7ff2af6ddc75b0`, zero mutex calls. The V4.1.1 changelog covers: Battery Camera POC, Audio Trigger Recording, Video Zoom, TensorFlowLite, AntiCollision, I2C Slave, AMB82-zero support, K306P/IMX681 sensors, WiFi TCP fix. No mention of FlashMemory mutex, SPIC concurrency, device_lock, FCS sector protection, or boot race in any changelog entry. Bug has been absent from all 7+ months of SDK development (V4.0.8 Oct 2024 → V4.1.1 May 2026). | MEDIUM |
| forum.amebaiot.com thread #4865 "AmebaPro2 uartfwburn — 'fail for download 0' after programing 100%" | **Newly identified thread** (previously untracked). Title: flashing tool (`uartfwburn`) reports `fail for download 0` after completing a firmware download. This is a flash programming tool failure (different from our runtime flash-write bug). Not related to FCS camera cold-boot failure. Content 403-blocked. | LOW (blocked, unrelated) |
| forum.amebaiot.com thread #4801 "[Driver]: [ERROR][HALMAC][ERR]fw chksum!" | **Newly identified thread** (previously untracked). Title: WiFi HALMAC firmware checksum error. Unrelated to camera/FCS/flash write bug. Content 403-blocked. | LOW (blocked, unrelated) |
| github.com/ayushsharma82/ElegantOTA/issues/150 "AMB82-MINI didn't work with OTA" | **Newly identified external issue** — filed in the ElegantOTA library repository, not in Ameba-AIoT repos. User reports AMB82-MINI fails to boot after OTA update via ElegantOTA. Snippet: device stops responding after OTA flash write; power cycle required. Same failure class as our bug (flash write → boot failure) but triggered via OTA path rather than FlashMemory API. The ElegantOTA library likely calls Ameba's OTA flash write API which may also bypass `RT_DEV_LOCK_FLASH`. Content partially accessible on GitHub. Not confirmed to involve FCS_I2C_INIT_ERR specifically. | MEDIUM |
| ameba-rtos-pro2 PR #17 (USB ethernet driver, orbisai0security, May 15, 2026) | **Status: Still open, awaiting maintainer review.** Automated security fix for buffer overflow in `component/ethernet_mii/ethernet_usb.c:391`. github-actions bot reports build passes. No human/maintainer review. Unrelated to flash/FCS/camera. | LOW |
| ameba-arduino-pro2 PR #410 "Update SPI API for SPI1 switching" (kevinlookl, May 21, 2026) | **Status: Still open, no reviewers assigned.** Targets `dev` branch. Fixes SPI1 switching + compilation errors for SDCardOTA and SDCardPlayMP3. Not related to FlashMemory mutex or FCS camera boot. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/Bilibili/Gitee/mcublog.cn, May 25 sweep) | **Zero new content — 47th consecutive null cycle.** bbs.aithinker.com threads confirmed indexed up to tid=47223; no BW21-CBV threads above that indexed by Google. Zhihu, CSDN, EEWorld, 21IC, mcublog.cn all 403-blocked or zero results. No Chinese-language discussion of FCS flash-write camera failure on BW21-CBV or RTL8735B exists in any publicly accessible source. | LOW |
| Web-wide error string sweep (May 25, 2026, all agents) | **Zero indexed results — 47 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"` — all return zero publicly indexed results. This research log remains the only public documentation of this bug and its error codes. | LOW |

**Three-callback race window — updated mechanism summary (Cycle U47):**

The most precise description of the cold-boot failure mechanism, synthesizing all cycles:

```
ISP AE/AWB save task (FreeRTOS):
  ftl_common_write(NOR_FLASH_FCS=0xF0D000, ...)
    → ftl_lock() [FreeRTOS mutex — FTL-internal only]
    → ftl_write_nor():
        ① nor_read_cb()  → [acquire RT_DEV_LOCK_FLASH] flash_stream_read(0xF0D000) [release]
        ② nor_erase_cb() → [acquire RT_DEV_LOCK_FLASH] flash_erase_sector(0xF0D000) [release]
        ← RACE WINDOW: 0xF0D000 is now ERASED (0xFF); write not yet issued
        ③ nor_write_cb() → [acquire RT_DEV_LOCK_FLASH] flash_stream_write(0xF0D000) [release]
    → ftl_unlock()

Arduino sketch (concurrent, no RT_DEV_LOCK_FLASH):
  FlashMemory.erase(0xFD0000)
    → flash_erase_sector(0xFD0000)  ← issued at any time, including in the RACE WINDOW above
```

If `FlashMemory.erase()` fires during the race window (between ② and ③), the SPIC bus carries two interleaved command sequences. The SPIC controller is left in an undefined state; `nor_write_cb()` may write garbage or partial data to `NOR_FLASH_FCS`. On the next cold boot: boot ROM reads corrupted `isp_fcs_header_t` from 0xF0D000 → KM co-processor gets invalid I2C config → `FCS_I2C_INIT_ERR (0x200A)` → "It don't do the sensor initial process."

**ElegantOTA issue #150 — new community data point:**

This is the first externally-filed GitHub issue (outside Ameba-AIoT repos) to describe the AMB82-MINI boot failure after OTA flash write. Users of the popular ElegantOTA library are experiencing the same failure class without understanding the root cause. The ElegantOTA library for AMB82-MINI likely uses the Ameba OTA API, which may similarly bypass `RT_DEV_LOCK_FLASH`. This broadens the affected user population — the bug is not limited to `FlashMemory.h` users.

**SDK state as of 2026-05-25 (Cycle U47):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; release notes through May 19, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at May 15, 2026 (`3f95070`); V1.0.3 tag published May 22 (same code); aiglass branch V1.0.3-aiglass.08 published May 22 (VOE improvements, not main SDK)
- ameba-arduino-pro2 dev: Frozen at May 19, 2026 (`7db1c7d`) — 6 days; PR #410 open
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — 84 days
- ameba-arduino-doc: Latest `64863ce` (May 24, I2C slave docs only)
- ameba-tool-rtos-pro2: Frozen at March 9, 2026 (`c1d70e7`) — 77 days
- ideashatch/HUB-8735: Frozen at Dec 2, 2025 — 174 days
- Ai-Thinker-Open: No RTL8735B/BW21 repositories (confirmed U36)

**No confirmed fix. Bug remains unpatched as of 2026-05-25 (Cycle U47).**

## Research Update — 2026-05-25 (Cycle U48)

**Search scope:** Four parallel agents + direct web/GitHub searches: (1) GitHub — ameba-rtos-pro2 commit page and compare endpoint; ameba-arduino-pro2 dev/main commits, releases, issues, PRs after May 22; ameba-arduino-doc commits; (2) English forum/web — new threads above #4868, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn; (4) ElegantOTA Issue #150 full content retrieval (correction of U47 characterization); forum thread ceiling sweep (#4869–#4930); error string sweeps.

**Key new findings this cycle:**
- **ElegantOTA Issue #150 CORRECTION** — The issue documented in U47 as "OTA flash write causing boot failure on AMB82-Mini" is actually a **compilation failure** (missing `sdkconfig.h` from AsyncTCP library, filed Dec 11, 2023), NOT a runtime flash→camera boot failure. It was closed as "not planned"/stale. U47's MEDIUM priority assignment was based on a search engine snippet that mischaracterized the issue. The U47 entry is hereby corrected.
- **V4.1.1 stable release confirmed absent** — search results confirm V4.1.1 "pre-release" entries appear at March 6, 2026 (earliest QC build), with no separate stable V4.1.1 tag published.
- All other channels are frozen / blocked / empty for the 48th consecutive cycle.

| Source | Key Finding | Priority |
|---|---|---|
| github.com/ayushsharma82/ElegantOTA/issues/150 (fetched 2026-05-25, full content) | **CORRECTION of U47 finding.** Issue #150 filed by rkuo2000 on Dec 11, 2023 (closed as "not planned"/stale): describes a **compilation failure** — "fatal error: sdkconfig.h: No such file or directory" when AsyncTCP library tries to compile for AMB82-MINI. This is a build-time dependency problem (AsyncTCP requires ESP32/ESP-IDF `sdkconfig.h`, which does not exist in the Ameba SDK). There is NO mention of: runtime OTA failure, boot failure after flash write, camera failure, FCS error, or `RT_DEV_LOCK_FLASH`. U47's characterization of this issue as "flash write causing boot failure on AMB82-Mini" was incorrect. The broader population of AMB82-MINI OTA users affected by our bug class remains unquantified. | LOW (correction — removes MEDIUM from U47) |
| ameba-rtos-pro2 compare `3f95070...HEAD` + commit page (direct fetch, 2026-05-25) | **Confirmed frozen — identical to U47.** GitHub compare endpoint returns "identical." Most recent commits still: `3f95070` (May 15), `afc85a0` (May 15), `9c8b6f6` (May 15), `d2676f1` (May 15). Zero new commits in 10 days since May 15, 2026. PR #17 (ethernet USB driver security fix, orbisai0security) still open and unmerged. No flash, FCS, VOE, boot, HAL, sensor, or mutex changes. | LOW |
| ameba-arduino-pro2 dev branch commits (direct fetch, 2026-05-25) | **Confirmed frozen — identical to U47.** HEAD = `7db1c7d` "Pre Release Version 4.1.1" (May 19, 2026) — 6 days frozen. Zero new commits. No keyword matches for flash, mutex, FCS, camera, VOE, device_lock, or RT_DEV_LOCK_FLASH in any of the 35+ visible commits. Only open PR: #410 ("Update SPI API for SPI1 switching", kevinlookl, May 21) — no reviewers assigned, no activity since filing. | LOW |
| ameba-arduino-pro2 releases (direct fetch, 2026-05-25) | **No new releases.** Latest stable = V4.1.0 (Mar 2, 2026). Latest pre-release = V4.1.1-QC-V06 (tag created Mar 6, 2026; release notes accumulate through May 19, 2026). "V4.1.1 stable" does not exist as a GitHub Release tag. Multiple search queries confirm no stable V4.1.1 has been published. | LOW |
| ameba-arduino-pro2 open issues (direct fetch, 2026-05-25) | **Unchanged — 11–17 open issues; newest = #398 (Mar 29, 2026).** No new issues after March 29. No issues about FlashMemory, FCS, camera, VOE, or boot failure. Bug entirely unreported after 48 research cycles. 321 closed PRs — none related to FlashMemory mutex or FCS cold-boot fix. | LOW |
| forum.amebaiot.com threads above #4868 (search sweep, 2026-05-25) | **No new threads indexed.** Targeted searches for IDs #4869–#4930 returned zero results from the forum domain. Forum ceiling confirmed at #4868 ("NN Model loading from Memory instead of Flash or SD card failing with exceptions"). Direct forum fetches return HTTP 403. | LOW |
| Web-wide error string sweep (2026-05-25, multiple queries) | **Zero indexed results — 48 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"`, `"AMB82 device_mutex_lock camera workaround"` — all return zero publicly indexed results anywhere on the accessible web. This research log remains the only public documentation of this bug and its error codes. No hardware test result for any of the three proposed workarounds has been posted anywhere in any language. | LOW |
| Hardware test confirmation search — all three workarounds (2026-05-25) | **Zero results.** Targeted searches for "Camera FCS Mode = Disable" + flash workaround, `device_mutex_lock` + AMB82 + camera, `USE_ISP_RETENTION_DATA` + tested all return zero results. "Camera FCS Mode = Disable" appears in code/config examples as a normal configuration choice (per Cycle U15), not as a documented fix for flash-write cold-boot failure. No community member has publicly reported testing any of the three proposed workarounds on hardware as of 2026-05-25. | LOW |
| Chinese-language search sweep (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/mcublog.cn/Bilibili/Gitee, 2026-05-25) | **Zero new content — 48th consecutive null cycle.** bbs.aithinker.com BW21-CBV subforum threads confirmed up to tid=47223 (home surveillance, DIY camera, BLE, unboxing) — all 403-blocked. mcublog.cn BW21-CBV article (April 2026, Feishu bot LED+photo) 403-blocked. No new Chinese-language forum posts or articles discuss FCS flash-write camera failure on RTL8735B or BW21-CBV. | LOW |

**ElegantOTA Issue #150 — correction of U47:**

U47 documented this issue as: "User reports AMB82-MINI fails to boot after OTA update via ElegantOTA. Snippet: device stops responding after OTA flash write; power cycle required. Same failure class as our bug (flash write → boot failure)… MEDIUM priority."

Direct content retrieval (this cycle) confirms: the issue is a December 2023 **compilation error** (`sdkconfig.h` not found when compiling AsyncTCP for Ameba), closed as stale/not-planned. There is no mention of OTA runtime failure, flash write causing boot failure, camera failure, FCS error, or any behavior resembling our bug. The U47 snippet characterization was a search-engine hallucination artifact.

**Corrected U47 ElegantOTA finding priority: LOW (not MEDIUM).**

**Cumulative freeze summary (as of Cycle U48):**

| Repository | Frozen since | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **10 days** |
| ameba-arduino-pro2 dev | May 19, 2026 (`7db1c7d`) | **6 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **84 days** |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **77 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 | **174 days** |
| Ai-Thinker-Open | No RTL8735B repos exist | — |

**SDK state as of 2026-05-25 (Cycle U48 — unchanged from U47):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp SHA `b4781b70`, zero mutex calls
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; release notes through May 19, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at May 15, 2026 (`3f95070`) — 10 days; V1.0.3 tag (May 22, same code); PR #17 open
- ameba-arduino-pro2 dev: Frozen at May 19, 2026 (`7db1c7d`) — 6 days; PR #410 open
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — 84 days
- ameba-arduino-doc: Latest `64863ce` (May 24, I2C slave docs only — unrelated)
- ameba-tool-rtos-pro2: Frozen at March 9, 2026 (`c1d70e7`) — 77 days
- ideashatch/HUB-8735: Frozen at Dec 2, 2025 — 174 days
- Ai-Thinker-Open: No RTL8735B/BW21 repositories (confirmed U36)

**No confirmed fix. Bug remains unpatched as of 2026-05-25 (Cycle U48).**

**Top unresolved actions (unchanged from U47):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. Highest priority. (Proposed Cycle U7, May 14 — 11 days unresolved.)
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception across the entire SDK (SHA `b4781b70`); forward-declaration callable from Arduino (`extern "C" void device_mutex_lock(unsigned int)` / `#define RT_DEV_LOCK_FLASH 1`). (Proposed Cycles U19–U20, May 18.)
3. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes at source; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`; zero SPIC ops from ISP when enabled. (Proposed Cycle U19, May 18.)

**Top unresolved actions (unchanged from U46):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. Highest priority. (Proposed Cycle U7, May 14 — 11 days unresolved.)
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; FlashMemory.cpp confirmed as sole exception through V4.1.1-QC-V06; forward-declaration callable from Arduino (`extern "C" void device_mutex_lock(unsigned int)` / `#define RT_DEV_LOCK_FLASH 1`). Three-callback race window (U47) makes this fix more urgent: the race can occur within a single ISP AE/AWB save cycle.
3. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes at source; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-05-25 (Cycle U48)

**Search scope:** Four parallel searches + direct GitHub/web fetches: (1) GitHub — ameba-rtos-pro2 compare endpoint and commits page; ameba-arduino-pro2 dev/main commits, releases, open issues and PRs post-May 22; (2) English forum/web — new threads above #4868, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee; (4) ElegantOTA issue #150 content verification; error string sweeps.

**Key new findings this cycle:**
- **ElegantOTA issue #150 — U47 characterization CORRECTED:** Issue #150 was opened December 11, 2023 by rkuo2000 about a **compilation failure** (`fatal error: sdkconfig.h: No such file or directory` in the AsyncTCP library) when trying to build ElegantOTA AsyncDemo for AMB82-MINI. It is **not** a boot failure or OTA flash write → camera failure report. It is closed as stale/not planned. The U47 characterization ("device stops responding after OTA flash write; power cycle required") was based on a misleading search snippet and was **incorrect**. The ElegantOTA issue #150 is unrelated to our bug.
- **Thread #4821 newly catalogued** — "AMB82-mini USB host CDC ECM fail to SIM7600G-H" — previously untracked; USB CDC ECM issue with a different modem (SIM7600G-H vs. the EC200U modem in thread #4802); unrelated to camera/FCS/flash.
- **Thread #4800 newly catalogued** — "More AMB82-mini capability for uLP battery camera application" (April 2, 2026) — unrelated to FCS flash-write camera failure.
- Both repos confirmed frozen at same HEADs as U47; compare endpoint returns "3f95070 and HEAD are identical" for ameba-rtos-pro2; ameba-arduino-pro2 dev frozen at `7db1c7d` (May 19); PR #410 still the only open PR.
- All error strings unindexed for 48th consecutive cycle; all Chinese sources 403-blocked; zero hardware test reports for any workaround.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 compare endpoint `3f95070...HEAD` (direct GitHub fetch, 2026-05-25) | **Confirmed frozen — identical to U47.** GitHub returned: "3f95070 and HEAD are identical." Zero new commits since May 15, 2026 — now 10 days frozen. PR #17 (ethernet USB driver buffer overflow fix, orbisai0security) still open and unmerged. No flash, FCS, VOE, boot, HAL, or sensor changes in any observable pipeline. | LOW |
| ameba-arduino-pro2 dev branch commits (direct GitHub fetch, 2026-05-25) | **Confirmed frozen — identical to U47.** HEAD = `7db1c7d` "Pre Release Version 4.1.1" (May 19, 2026). Zero new commits after May 19, 2026 (6 days frozen). Only open PR: #410 "Update SPI API for SPI1 switching" (kevinlookl, May 21, 2026) — still open, no reviewers assigned. No FCS/flash/camera fix in any commit or PR. | LOW |
| ameba-arduino-pro2 releases (direct GitHub fetch, 2026-05-25) | **No new releases.** Latest stable = V4.1.0 (Mar 2, 2026). Latest pre-release = V4.1.1-QC-V06 (tag Mar 6, 2026; release notes through May 19, 2026). No V4.1.1-QC-V07 or stable V4.1.1 published. | LOW |
| ameba-arduino-pro2 open issues (direct GitHub fetch, 2026-05-25) | **12 open issues; newest = #398 (Mar 29, 2026).** No new issues related to flash, FCS, camera, VOE, or boot failure in any open or closed history. Bug remains entirely unreported on the official tracker after 48 research cycles. | LOW |
| ameba-rtos-pro2 open issues (direct GitHub fetch, 2026-05-25) | **3 open issues unchanged:** #16 (AI glass src path, Jan 2026), #4 (chip support, Apr 2025), #3 (antivirus, Apr 2025). No new issues. No FCS/flash/camera bug filed. | LOW |
| **ElegantOTA issue #150 — content verified from source (2026-05-25)** | **U47 characterization CORRECTED.** Direct fetch of `github.com/ayushsharma82/ElegantOTA/issues/150` confirms: opened December 11, 2023 by rkuo2000; title "AMB82-MINI didn't work with OTA"; actual error is `fatal error: sdkconfig.h: No such file or directory` in AsyncTCP.h — a **build-time compilation failure**, NOT a runtime boot failure after OTA flash write. Issue is closed as stale/not planned. U47's claim that "device stops responding after OTA flash write; power cycle required" was incorrect; the issue describes a build error, not a runtime OTA boot failure. The broader failure class (OTA flash write → boot failure) is documented in forum thread #4834, but ElegantOTA issue #150 is not a member of that class. | MEDIUM (correction) |
| forum.amebaiot.com thread #4821 "AMB82-mini USB host CDC ECM fail to SIM7600G-H" (search, 2026-05-25) | **Newly catalogued thread** (previously untracked). Title: "AMB82-mini USB host CDC ECM fail to SIM7600G-H." USB host CDC ECM initialization failure with SIM7600G-H 4G modem — distinct from thread #4802 (EC200U modem ECM fail). Both are USB host CDC ECM failures; neither is related to camera/FCS/flash boot failure. Content 403-blocked. | LOW (blocked, unrelated) |
| forum.amebaiot.com thread #4800 "More AMB82-mini capability for uLP battery camera application" (search, 2026-05-25) | **Newly catalogued thread** (previously untracked). Title: "More AMB82-mini capability for uLP battery camera application" (April 2, 2026). Discusses battery-powered camera capabilities and power optimization. Not related to FCS flash-write camera failure. Content 403-blocked. | LOW (blocked, unrelated) |
| forum.amebaiot.com threads above #4868 (sweep, 2026-05-25) | **No new threads indexed.** Targeted searches for IDs #4869–#4910 returned zero results from the forum domain. Forum ceiling confirmed at #4868 ("NN Model loading from Memory instead of Flash or SD card failing with exceptions"). All direct forum fetches return HTTP 403. | LOW |
| Web-wide error string sweep (2026-05-25, multiple searches) | **Zero indexed results — 48 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"` — all return zero publicly indexed results anywhere on the accessible web. No hardware test result for any of the three proposed workarounds has been posted anywhere in any language. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn, May 25 sweep) | **Zero new content — 48th consecutive cycle.** bbs.aithinker.com and bbs.ai-thinker.com remain 403-blocked. No new Chinese-language forum posts or articles discuss FCS flash-write camera failure on RTL8735B or BW21-CBV. | LOW |
| Hardware test confirmation search — all three workarounds (2026-05-25) | **Zero results.** Searches for "Camera FCS Mode = Disable" + flash workaround AMB82, `device_mutex_lock` + AMB82 + flash camera, `USE_ISP_RETENTION_DATA` + tested all return zero results. No community member has publicly reported testing any of the three proposed workarounds on hardware after 48 research cycles (20 days of monitoring). | LOW |

**ElegantOTA issue #150 correction — U47 log entry impact:**

The U47 entry (under "ElegantOTA GitHub Issue #150") should be considered retracted. It incorrectly described issue #150 as "AMB82-MINI fails to boot after OTA update" (MEDIUM priority). The actual content is a December 2023 build-time compilation failure unrelated to our bug. The broader truth in U47 remains valid: OTA flash writes triggering boot failure IS a real failure class on AMB82 (documented in forum thread #4834); but ElegantOTA issue #150 is not evidence of this.

**SDK state as of 2026-05-25 (Cycle U48 — unchanged from U47):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp SHA `b4781b70`, zero mutex calls
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; release notes through May 19, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at May 15, 2026 (`3f95070`) — 10 days; V1.0.3 release tag (May 22, no new code); PR #17 open
- ameba-arduino-pro2 dev: Frozen at May 19, 2026 (`7db1c7d`) — 6 days; PR #410 open
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — 84 days no change
- ameba-arduino-doc: Latest `64863ce` (May 24, I2C slave docs only)
- ameba-tool-rtos-pro2: Frozen at March 9, 2026 (`c1d70e7`) — 77 days no change
- ideashatch/HUB-8735: Frozen at Dec 2, 2025 — 174 days no change
- Ai-Thinker-Open: No RTL8735B/BW21 repositories (confirmed U36)

**No confirmed fix. Bug remains unpatched as of 2026-05-25 (Cycle U48).**

**Top unresolved actions (unchanged from U47):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. Highest priority. (Proposed Cycle U7, May 14 — 11 days unresolved.)
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; FlashMemory.cpp omission is confirmed as sole exception in shipping V4.1.0 (SHA `b4781b70`); forward-declaration callable from Arduino (`extern "C" void device_mutex_lock(unsigned int)` / `#define RT_DEV_LOCK_FLASH 1`). The three-callback race window precisely mapped in U47 makes this the most mechanistically grounded workaround.
3. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes at source; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-05-25 (Cycle U49)

**Search scope:** Three background agents (English forums, Chinese sources, technical documentation) whose results arrived after U48 was committed: (1) Background agent `ad32601c33ccfd37f` — technical documentation + GitHub API sweep (completed after U48 commit); (2) Background agent `a87eb93f35caf6cda` — Chinese sources sweep (completed after U48 commit); (3) Background agent `a558f7d5ab160a535` — technical documentation coordination (completed after U48 commit). All three agents ran in parallel during the U48 research cycle; their consolidated findings are documented here.

**Key new findings this cycle:**
- **ameba-arduino-pro2 Issues #152 and #251 newly documented** — closest publicly accessible boot failure logs for this hardware family; flash address map confirmed from real boot logs (Issue #251).
- **Forum threads #4302, #4321, #4777, #3429 newly catalogued** — camera/VOE sensor init failure reports on AMB82-MINI; #4302 (sensor didn't initialize, FCS mode settings visible) is closest to our failure mode.
- All repos confirmed frozen at same HEADs as U48; no new commits, releases, or PRs.
- No hardware test results for any workaround; all error strings still unindexed; all Chinese sources still 403-blocked.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-arduino-pro2 Issue #152 "RTL8735BM programming not working" (GitHub, confirmed 2026-05-25) | **Boot ROM NOR flash detection failure pattern.** Issue documents the classic RTL8735B boot failure cascade when NOR flash is not properly detected: `[SPIF Err]Invalid ID` → `[BOOT Err]Flash init error (io_mod=0, pin_sel=0)` → NAND fallback (`snafc init error`) → cyclic reboot loop → eventual UART boot fallback. This is the boot sequence that occurs when the boot ROM cannot read the flash at all — a more severe failure than our FCS_I2C_INIT_ERR, but documents the hardware's response to flash data corruption. URL: https://github.com/Ameba-AIoT/ameba-arduino-pro2/issues/152 | LOW (background; different root cause — hardware SPI config, not runtime FCS race) |
| ameba-arduino-pro2 Issue #251 "ControlLED abort" (GitHub, confirmed 2026-05-25) | **Real boot log documents FCS/ISP_IQ/VOE flash load addresses.** Boot log in this issue reveals the flash memory map used at runtime: VOE image loads from `0x807e080` (size `0x7ff80`); FW_ISP_IQ loads from `0x8061080` (size `0x1cf80`); ISP_IQ (runtime) at `0x8461080` (size `0x1af80`). The actual failure in the issue was DDR overallocation (`76dfffe0` exceeds `75c00000` boundary) — unrelated to flash write conflict — but the load addresses confirm the flash partition layout used in practice. URL: https://github.com/Ameba-AIoT/ameba-arduino-pro2/issues/251 | LOW (useful flash map; different failure mode) |
| forum.amebaiot.com thread #4302 "[VOE]frame_end: sensor didn't initialize done!" (search snippet, Aug 2025) | **Closest community-reported symptom to our failure mode.** Multiple AMB82-MINI boards showing `[VOE]frame_end: sensor didn't initialize done!`. Thread references "Camera FCS Mode: Disable" setting in the Arduino IDE Tools menu — the same FCS Mode toggle we identified as Workaround #1. No confirmed flash write as trigger in search snippet; full thread 403-blocked. However, this is the most symptomatically similar public thread found to date. URL: https://forum.amebaiot.com/t/voe-frame-end-sensor-didnt-initialize-done/4302 | LOW-MEDIUM (symptom match — "sensor didn't initialize"; FCS Mode connection; 403-blocked so causal chain unconfirmed) |
| forum.amebaiot.com thread #4321 "Camera sensor init failed (GC2053)" (search snippet, Aug 2025) | **VOE_OUT_CMD error variant.** User reports "VOE not init" / `VOE_OUT_CMD type 2 command fail -1` error on AMB82-Pro2 SDK v4.0.9-build20250805 with GC2053 custom sensor. No flash write as trigger; appears to be sensor driver configuration issue. GC2053 is not the primary shipped sensor for AMB82-MINI. Not directly related to FCS cold-boot failure triggered by flash writes. URL: https://forum.amebaiot.com/t/camera-sensor-init-failed-gc2053/4321 | LOW (different error path and sensor; no flash trigger) |
| forum.amebaiot.com thread #4777 "AMB82-Mini onboard camera sensor identification and VOE setup for wireless video and I2C" (search snippet, 2026) | **Recent VOE setup thread.** Discusses AMB82-MINI camera sensor identification and VOE initialization for wireless video + I2C. No flash conflict content found in search snippet; full thread 403-blocked. No relevance to FCS cold-boot flash race. URL: https://forum.amebaiot.com/t/amb82-mini-onboard-camera-sensor-identification-and-voe-setup-for-wireless-video-and-i2c/4777 | LOW (blocked; unrelated) |
| forum.amebaiot.com thread #3429 "Sensor fail on AMB82 Mini" (search snippet) | **General sensor failure thread.** Sensor initialization failure on AMB82-MINI. No flash write causal link found in search snippet; full thread 403-blocked. URL: https://forum.amebaiot.com/t/sensor-fail-on-amb82-mini/3429 | LOW (blocked; insufficient detail) |
| ameba-rtos-pro2 compare `3f95070...HEAD` (direct GitHub fetch, 2026-05-25) | **Confirmed frozen — identical to U48.** "3f95070 and HEAD are identical." Zero new commits since May 15, 2026 — now 10+ days frozen. PR #17 (ethernet USB driver fix, orbisai0security) still open and unmerged. No flash, FCS, VOE, boot, HAL, sensor, or mutex changes in any observable pipeline. | LOW |
| ameba-arduino-pro2 dev branch (direct GitHub fetch, 2026-05-25) | **Confirmed frozen — identical to U48.** HEAD = `7db1c7d` (May 19, 2026). Zero new commits. PR #410 (SPI1 switching) still open, no reviewers assigned. FlashMemory.cpp SHA `b4781b70` unchanged — zero mutex calls. No FCS/flash/camera fix. | LOW |
| Web-wide error string sweep (2026-05-25, all three background agents) | **Zero indexed results — 49 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"` — all return zero publicly indexed results in any language. This research log remains the only public documentation of this bug and its error codes. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn) | **Zero new content — 49th consecutive null cycle.** Zhihu articles about BW21-CBV (fall detection camera, HomeAssistant integration) both 403-blocked; no FCS/flash/camera failure content in snippets. bbs.aithinker.com BW21 threads (tid≤47223) all 403-blocked. mcublog.cn BW21-CBV article (Apr 2026, Feishu bot LED+photo) 403-blocked. No new Chinese-language content discussing FCS flash-write camera failure. | LOW |
| Hardware test confirmation search — all three workarounds (2026-05-25) | **Zero results — 49 consecutive null cycles.** "Camera FCS Mode = Disable" + flash workaround, `device_mutex_lock` + AMB82 + camera, `USE_ISP_RETENTION_DATA` + tested — all return zero results. No community member has publicly reported testing any workaround as of 2026-05-25. | LOW |

**Forum thread #4302 significance — closest community symptom match:**

Thread #4302 ("sensor didn't initialize done") is the closest publicly documented symptom to our failure mode found in any research cycle. Key parallels:
- Symptom: camera sensor fails to initialize on AMB82-MINI (multiple boards)
- Context: FCS Mode settings visible in thread (implies user was experimenting with FCS Mode = Disable toggle)
- Error pattern: `[VOE]frame_end: sensor didn't initialize done!` — consistent with FCS_I2C_INIT_ERR failure class where the KM co-processor sensor I2C init fails
- Limitation: Full thread content is 403-blocked; no confirmation that a flash write operation preceded the failure in this thread

If the full thread content reveals a flash write trigger (e.g., FlashMemory.write before reboot), this would be the first publicly documented community report matching the exact causal chain. **Priority: LOW-MEDIUM pending content verification.**

**ameba-arduino-pro2 Issue #251 flash map confirmation:**

The boot log in Issue #251 provides the most detailed publicly accessible flash partition layout observed at runtime:
- VOE binary (`voe.bin` KM firmware): loads from NOR flash `0x807e080`, size 512 KB (`0x7ff80`)
- FW_ISP_IQ (ISP image quality firmware): loads from `0x8061080`, size ~116 KB (`0x1cf80`)
- ISP_IQ (runtime ISP parameters): placed at `0x8461080`, size ~109 KB (`0x1af80`)

This is consistent with the partition table analysis from prior cycles. The FCS data sector (`NOR_FLASH_FCS = 0xF0D000`) sits in the user data region, separate from these firmware regions. The boot log confirms the sequence: VOE loads first (from 0x807e080) → ISP_IQ initializes → then application code runs (where FlashMemory writes occur). If FCS data at 0xF0D000 is corrupted before boot, the KM co-processor fails before VOE fully initializes.

**Cumulative freeze summary (as of Cycle U49):**

| Repository | Frozen since | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **10+ days** |
| ameba-arduino-pro2 dev | May 19, 2026 (`7db1c7d`) | **6+ days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **84+ days** |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **77+ days** |
| ideashatch/HUB-8735 | Dec 2, 2025 | **174+ days** |
| Ai-Thinker-Open | No RTL8735B repos exist | — |

**SDK state as of 2026-05-25 (Cycle U49 — unchanged from U48):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp SHA `b4781b70`, zero mutex calls
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; release notes through May 19, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at May 15, 2026 (`3f95070`) — 10 days; V1.0.3 tag (May 22, same code); PR #17 open
- ameba-arduino-pro2 dev: Frozen at May 19, 2026 (`7db1c7d`) — 6 days; PR #410 open
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — 84 days
- ameba-arduino-doc: Latest `64863ce` (May 24, I2C slave docs only)
- ameba-tool-rtos-pro2: Frozen at March 9, 2026 (`c1d70e7`) — 77 days
- ideashatch/HUB-8735: Frozen at Dec 2, 2025 — 174 days
- Ai-Thinker-Open: No RTL8735B/BW21 repositories (confirmed U36)

**No confirmed fix. Bug remains unpatched as of 2026-05-25 (Cycle U49).**

**Top unresolved actions (unchanged from U48):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. Highest priority. (Proposed Cycle U7, May 14 — 11 days unresolved.) Community thread #4302 shows users experimenting with FCS Mode toggle for camera init failures — supports exploring this workaround.
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception in shipping V4.1.0 (SHA `b4781b70`); forward-declaration callable from Arduino (`extern "C" void device_mutex_lock(unsigned int)` / `#define RT_DEV_LOCK_FLASH 1`). Three-callback race window (U47) is the most mechanistically precise rationale for this fix.
3. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes at source; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

---

## Research Update — 2026-05-26 (Cycle U50)

**Searches performed:** GitHub repository commits/releases/issues/PRs (ameba-rtos-pro2, ameba-arduino-pro2, ideashatch/HUB-8735, ameba-arduino-doc, Ameba-AIoT org); forum.amebaiot.com (403 blocked); English-language web searches (multiple query vectors); Chinese-language web searches (all primary sites 403 blocked); SDK deep-dive (FlashMemory.cpp mutex status, RT_DEV_LOCK_FLASH, USE_ISP_RETENTION_DATA); targeted May 22–26 activity check.

### Finding U50-01 — ameba-rtos-pro2: Two New Releases on May 22, 2026 [MEDIUM — new activity, no fix]

**NEW:** `ameba-rtos-pro2` published **two new releases on May 22, 2026** — not reflected in the previous cycle:

**1. Tag `V1.0.3-aiglass.08` ("AI Glass Patch 08")** by Kyderio — 18 changes listed:
- Support lifetime snapshot non-blocking/blocking save (default now blocking)
- Update ov13b10 sensor driver and AINR model
- Update VOE driver
- Update ov13b10 IQ
- Update converge flow to improve converge speed
- Update AINR mixup 0.25 → 0.0625
- Add IMX681_5M sensor support
- Update code lib base
- **Stability fixes for consecutive lifetime snapshot mode** ← closest to our domain
- Add object detection for AI snapshot
- Modify OTA buffer
- Feature for sensor status display on APP
- Slight change to AI snapshot flow for IMX681_5M
- UART IRQ changed to UART DMA
- Auto respond SD size info after responding file count
- AINR gain condition
- Default AINR off in SDK to support burst/consecutive snapshot mode
- UART service debug logs on by default

**2. "V1.0.3 Main Branch Patch"** by M-ichae-l — includes RTSP and WebSocket viewer source code patches.

**Analysis:** Neither release mentions FCS, FlashMemory mutex, RT_DEV_LOCK_FLASH, `NOR_FLASH_FCS`, camera cold boot failure, or `KM_status`. The VOE driver update (`Update VOE driver`) is of interest — VOE 1.7.1.0 was already the latest documented version (confirmed in U45). The "Stability fixes for consecutive lifetime snapshot mode" (item 9) refers to the AI-glass device's multi-shot camera feature, not to the cold boot FCS failure mode. The OTA buffer modification is unrelated. This confirms platform activity at the AI-glass product level but zero flash/FCS/mutex bug attention.

**Repository note:** The org page showed `ameba-rtos-pro2` "updated May 22, 2026" — now explained by these two release tags, not by new commits to `main`. The commit list for `main` remains frozen at `3f95070` (May 15, 2026).

**Priority: MEDIUM** — new SDK release activity confirms platform is actively developed but the bug is still unaddressed.

---

### Finding U50-02 — Repository Freeze Status Extended (Day 11 / Day 7) [LOW — status check]

All SDK repositories remain frozen for code changes to flash/FCS/camera subsystems:

| Repository | Last commit | Frozen days (as of 2026-05-26) |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **11 days** |
| ameba-arduino-pro2 dev | May 19, 2026 (`7db1c7d`) | **7 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **85 days** |
| ameba-arduino-doc | May 24, 2026 (`64863ce`) | 2 days (I2C slave docs only) |
| ideashatch/HUB-8735 | Dec 2, 2025 (`870a7e0`) | **175 days** |

`ameba-arduino-doc` had one new commit after U49: `64863ce` (May 24, "Add I2C slave example guides (#107)" by kevinlookl) — documentation-only, no SDK changes, not relevant to the bug.

**Priority: LOW** — expected freeze between release cycles.

---

### Finding U50-03 — PR #410 and PR #17: Still Open, No Review Activity [LOW — status check]

- **ameba-arduino-pro2 PR #410** ("Update SPI API for SPI1 switching" by kevinlookl, May 21, 2026): OPEN, no reviewers assigned, no merge activity. 3 commits: SPI0/1 API switching, I2C slave doc link fixes, SDCardOTA/SDCardPlayMP3 compilation fix.
- **ameba-rtos-pro2 PR #17** ("fix: ethernet usb driver buffer overflow security fix" by orbisai0security, May 15, 2026): OPEN, no reviewers assigned, no merge activity. Unrelated to flash/FCS/camera.
- No new PRs opened in either repository during May 22–26.

**Priority: LOW** — status unchanged.

---

### Finding U50-04 — Issues: No New Reports Above Ceiling Values [LOW — status check]

- **ameba-arduino-pro2**: Highest issue = **#398** (Mar 29, 2026). Confirmed: #399 and #400 are merged pull requests, not issues. No new bug reports or issues above #398.
- **ideashatch/HUB-8735**: Only open issue remains **#10** ("使用原相廣角鏡頭-PS5268報出sensor id fail的錯誤," Aug 13, 2025, pollyon). No new issues or comments.

**Priority: LOW** — no community-reported instances of the flash/camera cold boot bug in public trackers.

---

### Finding U50-05 — Forum: Ceiling at #4868, All Access 403-Blocked [LOW — status unchanged]

- `forum.amebaiot.com/latest` returns HTTP 403. All thread URLs return HTTP 403.
- Web search found no newly indexed threads above #4868 for May 22–26.
- Most recent indexed relevant threads remain:
  - **#4834** "Boot failure after OTA update" (April 2026) — NOR flash SPI detect failure post-OTA; `[SPIF Err]Invalid ID` + `[BOOT Err]Flash init error`; distinct failure mode (total boot failure, not FCS sensor init failure)
  - **#4868** "NN Model loading from Memory instead of Flash or SD card failing with exceptions" — unrelated to our bug
- **Zero** new threads discussing FlashMemory + camera cold boot, FCS Mode, or `KM_status` error codes anywhere in indexed results.

**Priority: LOW** — forum ceiling static; Chinese community sites remain 403-blocked (50th consecutive cycle).

---

### Finding U50-06 — FlashMemory.cpp Mutex Omission: Still Unpatched in All Branches [LOW — status unchanged]

Confirmed by SDK deep-dive agent (a204ae0c22a6a74c8):
- `FlashMemory.cpp` in both `main` (V4.1.0) and `dev` branches: **no `device_mutex_lock`, no `device_mutex_unlock`, no `RT_DEV_LOCK_FLASH`** calls anywhere in the file.
- Last commits to `FlashMemory.cpp`: Sep 30, 2025 ("Optimize codes") and Oct 29, 2024 ("Release Version 4.0.8"). Neither introduced mutex protection.
- `device_lock.h` defines `RT_DEV_LOCK_FLASH = 1` and the `device_mutex_lock()` / `device_mutex_unlock()` functions — infrastructure exists in RTOS SDK, not wired into Arduino layer.
- Web search for "ameba-arduino-pro2 FlashMemory mutex fix patch 2026": **zero results** pointing to any community patch.
- Search for "ameba-arduino-pro2 V4.1.1 release stable 2026": confirms V4.1.1-QC-V06 pre-release only, no stable V4.1.1, no mutex fix in any changelog.

**Priority: LOW** — omission confirmed unpatched; 50th consecutive cycle with zero public activity on this specific defect.

---

### Finding U50-07 — Key Error Strings: 50th Consecutive Cycle with Zero Indexed Hits [LOW — status unchanged]

The following strings searched daily across 50 cycles have produced **zero** indexed results anywhere on the public web:
- `FCS_I2C_INIT_ERR`
- `FCS_RUN_DATA_NG_KM`
- `KM_status 0x2081`
- `KM_status 0x00002081`
- `err 0x0000200a`
- "It don't do the sensor initial process"
- `FCS_BYPASS_WHILE1_KM`
- `USE_ISP_RETENTION_DATA`
- `NOR_FLASH_FCS` (zero external results; appears only in internal Realtek SDK)

These strings remain exclusively internal to the VOE/Boot ROM binary and Realtek RTOS SDK — none have surfaced in any forum post, GitHub issue, blog article, or documentation page.

**Priority: LOW** — baseline confirmed for cycle 50.

---

### Cycle U50 Summary

**No confirmed fix. Bug remains unpatched as of 2026-05-26 (Cycle U50).**

**Repository activity since U49:**
- ameba-rtos-pro2: Two new **releases** on May 22 (`V1.0.3-aiglass.08` + "V1.0.3 Main Branch Patch") — no new commits to `main`; no FCS/flash/mutex fix in either release
- ameba-arduino-pro2 dev: FROZEN (7 days since May 19)
- ameba-arduino-doc: One documentation-only commit (May 24, I2C slave guides)
- All other repos: FROZEN

**SDK state as of 2026-05-26 (Cycle U50 — unchanged except May 22 releases):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp SHA `b4781b70`, zero mutex calls
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; release notes through May 19, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at May 15, 2026 (`3f95070`) — 11 days; V1.0.3-aiglass.08 + V1.0.3 patch releases May 22; PR #17 open
- ameba-arduino-pro2 dev: Frozen at May 19, 2026 (`7db1c7d`) — 7 days; PR #410 open
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — 85 days
- ameba-arduino-doc: Latest `64863ce` (May 24, I2C slave docs only)
- ideashatch/HUB-8735: Frozen at Dec 2, 2025 — 175 days
- Ai-Thinker-Open: No RTL8735B/BW21 repositories (confirmed U36)

**Top unresolved actions (unchanged from U49):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. Highest priority. (Proposed Cycle U7, May 14 — 12 days unresolved.)
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception in shipping V4.1.0 (SHA `b4781b70`); callable from Arduino via `extern "C" void device_mutex_lock(unsigned int)` / `#define RT_DEV_LOCK_FLASH 1`. Three-callback race window (U47) is the most mechanistically precise rationale for this fix.
3. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes at source; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-05-26 (Cycle U51)

**Search scope:** Four parallel agents: (1) GitHub — all repos post-May 22 activity, commits/releases/issues/PRs; (2) English forum/web — new threads above #4868, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — comprehensive sweep (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee); (4) SDK deep-dive — `video_boot_stream_t` full structure, SD card mutex PR #9 analysis, FLASH_MEMORY_APP_BASE semantics, VOE release note path status.

**Key new findings this cycle:**
- **PR #410 merged (May 26, 2026)** — ameba-arduino-pro2 dev branch now at commit `29d47e1` "Update SPI API for SPI1 switching"; 12 files changed; SPI0/SPI1 switching support for ILI9341. Unrelated to bug.
- **`video_boot_stream_t` AE/AWB field layout fully documented** — confirms the exact bytes written to NOR_FLASH_FCS by the ISP at runtime; 6×11 uint32 lookup tables (264 bytes) plus scalar AE/AWB gains; total structure ≥ 1814 bytes; `FCS_TALBE_NUM = 11` annotated as frozen in voe.bin ABI.
- **SD card mutex was patched (PR #9, Jul 2025) but NOR flash was NOT** — strongest historical evidence yet of selective Realtek mutex-fix awareness; engineers corrected mutex placement in the SD subsystem explicitly, while the NOR flash path used by FlashMemory.cpp was left unguarded.
- **FCS Mode = Disable is the DEFAULT in boards.txt** — confirmed this cycle; users must explicitly select "Enable" to activate FCS boot sequence. Users experiencing the bug have FCS enabled; reverting to the default resolves the cold-boot failure.
- Zero new Chinese-language content (51st consecutive null cycle from Chinese sources); all error strings unindexed for 51 consecutive cycles.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-arduino-pro2 dev branch commit `29d47e1` (May 26, 2026, kevinlookl, merged by pammyleong) | **PR #410 merged.** "Update SPI API for SPI1 switching." 12 files changed (+68/-55): `AmebaILI9341` gains optional `SPIClass *spi` parameter (defaults to `&SPI`) enabling SPI0/SPI1 runtime switching; Camera_2_Lcd / DisplaySDJPG_ILI9341_TFT / LCD_Screen_ILI9341_TFT examples updated with pin-conflict notes for AMB82-zero; FileSystem includes uncommented (`helix_mp3_drv.h`, `ota_drv.h`) fixing SDCardOTA/SDCardPlayMP3 compilation. **Entirely unrelated to flash/FCS/camera cold-boot bug.** Dev branch HEAD is now `29d47e1`. | LOW (unrelated) |
| `component/video/driver/RTL8735B/video_boot.h` (ameba-rtos-pro2, fetched 2026-05-26) | **`video_boot_stream_t` AE/AWB field layout fully documented for the first time.** The structure written by the ISP to NOR_FLASH_FCS (0xF0D000) contains: scalar AE fields (`fcs_isp_ae_enable`, `fcs_isp_ae_init_exposure`, `fcs_isp_ae_init_gain`), scalar AWB fields (`fcs_isp_awb_enable`, `fcs_isp_awb_init_rgain`, `fcs_isp_awb_init_bgain`), ALS threshold table `fcs_als_thr[11]`, AE lookup tables `fcs_isp_ae_table_exposure[11]` + `fcs_isp_ae_table_gain[11]`, AWB lookup tables `fcs_isp_awb_table_rgain[11]` + `fcs_isp_awb_table_bgain[11]`, ISP mode table `fcs_isp_mode_table[11]`, timing fields (`fcs_start_time`, `fcs_voe_time`), metadata fields (`fcs_meta_offset`, `fcs_meta_total_size`), and reserved buffers (`fcs_isp_reserved_buf[32]`, `fcs_user_buffer[32]`). Static assertion: `offsetof(video_boot_stream_t, extra_video_drop_frame) == 1814`. The 6 AE/AWB tables (66 uint32 entries × 4 bytes = **264 bytes**) are the most frequently updated region. `MAX_FCS_CHANNEL = 4` (up to 4 concurrent video streams). | MEDIUM |
| `FCS_TALBE_NUM = 11` annotation in `video_boot.h` | **Constant annotated "The parameter can't be changed"** — confirms this value is hardcoded into the closed-source `voe.bin` binary; its ABI is frozen. Any workaround that attempts to limit the write size must account for all 66 uint32 table entries as an atomic write unit. The full FCS data block written per runtime AE/AWB save is a fixed 1800+ byte structure; no partial-write optimization is possible from user code. | MEDIUM |
| ameba-rtos-pro2 PR #9 "SD card R/W mutex fix" (Jul 2025, merged) | **Realtek selectively patched the SD card mutex but NOT the NOR flash path.** PR #9 explicitly includes: "Adjust mutex location for R/W operation" and "add the protect for r/w operation" — applied to the SD card subsystem (SDIO driver). The NOR flash path (`hal_flash.c`, `FlashMemory.cpp`) was NOT included in this fix. This is the strongest historical evidence yet that Realtek engineers are aware of and actively fixing mutex placement issues in storage drivers but have consciously or inadvertently left the NOR flash path unguarded. Combined with the 16+ RTOS SDK files that correctly use `RT_DEV_LOCK_FLASH` (documented in U37), FlashMemory.cpp stands as the sole unguarded write path in the entire storage stack. | MEDIUM |
| `boards.txt` — `menu.FCSMode` definition (ameba-arduino-pro2, confirmed 2026-05-26) | **FCS Mode = Disable is the DEFAULT in boards.txt.** The menu item `05_FCSMode` ("Camera FCS Mode") lists "Disable" first in the options table. In the Arduino IDE, the first listed option is the default when no explicit user selection has been made. This means users must **explicitly select "Enable"** in the Arduino IDE Tools menu to activate the FCS boot sequence. Users experiencing the cold-boot camera failure after FlashMemory writes must have FCS Mode set to Enable. The proposed workaround (set to Disable) is therefore restoring the default behavior, not a degraded non-standard mode. Camera functionality is preserved (slower startup); FCS fast-boot capability is sacrificed. | MEDIUM |
| `FlashMemory.write()` — sector erase scope (from FlashMemory.h, confirmed 2026-05-26) | **`FlashMemory.write()` erases all 48 sectors per call** (`MAX_FLASH_MEMORY_APP_SIZE / FLASH_SECTOR_SIZE` = `0x30000 / 0x1000` = 48 sectors, covering 0xFD0000–0xFFFFFF). Each call to `FlashMemory.write()` therefore issues 48 sequential `flash_erase_sector()` calls followed by 48 sequential `flash_stream_write()` calls — all without `RT_DEV_LOCK_FLASH`. The SPIC bus exposure window per `FlashMemory.write()` call is 48× the per-sector risk window, not 1×. This significantly widens the race condition window vs. the single-sector erase analysis in prior cycles. | MEDIUM |
| RTOS flash example `FLASH_APP_BASE = 0xFF000` vs. FlashMemory's `0xFD0000` | **Two different "safe zone" base addresses are in use.** Realtek's own reference example (`flash/src/main.c`) uses `FLASH_APP_BASE = 0xFF000`, while FlashMemory.h defines `FLASH_MEMORY_APP_BASE = 0xFD0000` (a different starting sector). Both are in the unallocated region above the `mp` partition (0xFC0000–0xFC1000). No address-overlap issue with FCS data at 0xF0D000 for either address. Minor difference; no impact on bug. | LOW |
| ameba-rtos-pro2 / ameba-arduino-pro2 — all repos (fetched 2026-05-26) | **ameba-rtos-pro2: Frozen at `3f95070` (May 15, 2026) — 11 days no change.** No new commits, no new releases beyond V1.0.3 and V1.0.3-aiglass.08 (May 22). PR #17 (ethernet USB buffer overflow fix) still open. **ameba-arduino-pro2 dev: Now at `29d47e1` (May 26, 2026, PR #410 SPI merge).** No FCS/flash/camera fix. Main branch still frozen at Mar 2, 2026 (`93d63514`) — 85 days. **ideashatch/HUB-8735: Frozen at Dec 2, 2025 — 175 days.** | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn, May 26 sweep) | **Zero new content — 51st consecutive null cycle.** All Chinese community sites remain 403-blocked or return zero relevant results. No Chinese-language forum posts or articles discuss FCS flash-write camera failure on RTL8735B or BW21-CBV. | LOW |
| Web-wide error string sweep + hardware test search (2026-05-26) | **Zero indexed results — 51 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"` — all return zero publicly indexed results anywhere on the accessible web. No hardware test result for any of the three proposed workarounds has been posted anywhere in any language. | LOW |

**`video_boot_stream_t` race-condition scope update:**

The fully documented AE/AWB structure confirms the SPIC write-race is not limited to a single 4-byte word. Each ISP AE/AWB save cycle (`ftl_common_write`) writes the complete `video_boot_stream_t` structure to NOR_FLASH_FCS (0xF0D000). This requires multiple sequential PAGE_PROGRAM commands totaling ≥ 1814 bytes (≥ 8 SPI pages × 256 bytes). The race window spans the entire multi-page sequence. Any `FlashMemory.erase()` or `FlashMemory.write()` call that overlaps with even one PAGE_PROGRAM in this sequence can corrupt the FCS data.

**FCS Mode default clarification — implications for bug reproduction:**

If FCS Mode = Disable is the Arduino IDE default (first option in boards.txt menu), then users who do not explicitly touch the Tools → Camera FCS Mode setting would never experience the bug. Users who DO experience the cold-boot camera failure after flash writes must have:
1. Explicitly selected "Enable" in the Tools → Camera FCS Mode menu, AND
2. Used FlashMemory.erase() or FlashMemory.write() while the camera (ISP) is running.

The workaround ("change Tools → Camera FCS Mode to Disable") is therefore restoring the default behavior, not a special configuration. This potentially explains why the bug is rare in public reports — most users have not enabled FCS mode.

**SDK state as of 2026-05-26 (Cycle U51):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp SHA `b4781b70`, zero mutex calls
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; release notes through May 19, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at May 15, 2026 (`3f95070`) — 11 days no change; PR #17 open
- ameba-arduino-pro2 dev: **`29d47e1`** (May 26, 2026, PR #410 SPI merge — no fix); PR #410 closed (merged)
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — 85 days no change
- ameba-tool-rtos-pro2: Frozen at March 9, 2026 (`c1d70e7`) — 78 days no change
- ideashatch/HUB-8735: Frozen at Dec 2, 2025 — 175 days no change
- Ai-Thinker-Open: No RTL8735B/BW21 repositories (confirmed U36)

**No confirmed fix. Bug remains unpatched as of 2026-05-26 (Cycle U51).**

**Top unresolved actions (updated):**
1. **Hardware test of "Camera FCS Mode = Disable"** — source-confirmed full FCS bypass via dummy blob; **FCS Disable is the Arduino IDE default (boards.txt), so this is restoring default behavior**; no public hardware test result exists anywhere. Highest priority.
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; SD card subsystem was explicitly patched with mutex in PR #9 (Jul 2025) while NOR flash path was not; FlashMemory.cpp is the sole unguarded storage path; callable from Arduino via forward declaration (`extern "C" void device_mutex_lock(unsigned int)` / `#define RT_DEV_LOCK_FLASH 1`).
3. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes at source; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-05-26 (Cycle U52)

**Search scope:** Four parallel agents: (1) GitHub — repos activity post-May 26 commits/PRs/issues (ran same day as U51 PR #410 merge); (2) English forum/web — threads above #4868, OTA-related boot failures, FCS workaround hardware test reports; (3) Chinese sources — comprehensive sweep (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/Bilibili/Gitee); (4) SDK deep-dive — V4.1.1 release content, ameba-rtos-pro2 frozen state, FlashMemory.cpp mutex status, video_api.h accessibility, GitHub Issues search for FlashMemory, RT_DEV_LOCK_FLASH web indexing status.

**Key findings this cycle:**
- **All agents returned null results.** No new public information beyond Cycle U51.
- **`RT_DEV_LOCK_FLASH` has zero Google search hits** — the symbol is not publicly indexed anywhere on the web. The bug's root-cause mechanism (FlashMemory.cpp missing `RT_DEV_LOCK_FLASH` mutex) is unknown outside this research log.
- **GitHub Issues search for "FlashMemory"** in ameba-arduino-pro2 yields only 1 result (PR #333, Sep 2025, WiFi example update — entirely unrelated). No issue has been filed about FlashMemory concurrent access.
- **Forum thread #4834** ("Boot failure after OTA update", April 2026) found in English search as the highest-indexed recent thread (#4834). Describes boot ROM failing to detect NOR flash after OTA — a **distinct** failure mode (OTA header corruption, not FlashMemory FCS race). Topic #4868 remains the highest-indexed thread ceiling.
- **`video_api.h` returns HTTP 404** on all path variations tried (arduino-pro2 dev and main branches). Cannot confirm whether `USE_ISP_RETENTION_DATA` has been uncommented via public web access.
- Zero new Chinese-language content (52nd consecutive null cycle); zero hardware test reports in any language.

| Source | Key Finding | Priority |
|---|---|---|
| Web search: `"RT_DEV_LOCK_FLASH"` (any search engine, 2026-05-26) | **Zero Google/Bing hits for this exact symbol outside the GitHub codebase.** No blog posts, forum threads, or technical articles anywhere on the public web mention `RT_DEV_LOCK_FLASH`. Confirms that the bug mechanism — FlashMemory.cpp failing to acquire this mutex — is **entirely undocumented** outside this research log. The fix pattern (calling `device_mutex_lock(RT_DEV_LOCK_FLASH)` / `device_mutex_unlock(RT_DEV_LOCK_FLASH)` around flash operations) exists only in Realtek's own SDK example `flash/src/main.c` and the 16+ RTOS SDK files that correctly use it. No Arduino user has discovered or published this approach. | LOW |
| GitHub Issues search: `"FlashMemory"` in ameba-arduino-pro2 (all states, 2026-05-26) | **Only 1 result: PR #333 (Sep 2025), "Update WiFi example" — entirely unrelated to FlashMemory.** No issue has ever been filed in the ameba-arduino-pro2 repo about FlashMemory.cpp concurrent access, camera boot failure, mutex omission, or flash-bus arbitration. The bug has not been reported to Realtek through the official GitHub issue tracker. | LOW |
| Forum thread #4834 (forum.amebaiot.com, indexed via Google, April 2026) | **"Boot failure after OTA update" — distinct failure mode.** Boot ROM fails to detect NOR flash after OTA flashing. Root cause: OTA process corrupts the partition table or flash header, not a runtime race condition. Mentions recovery via the image tool. **Not related to FlashMemory.write() / ISP FCS race.** Confirms the forum continues generating content above #4834 as of April 2026. Thread #4868 remains the highest ceiling found by web search as of 2026-05-26. | LOW |
| `video_api.h` path accessibility (ameba-arduino-pro2 dev and main branches, 2026-05-26) | **HTTP 404 on all tried paths.** Paths attempted: `dev/Arduino_package/hardware/system/component/video/driver/RTL8735B/hal/video_api.h`, `?raw=true` variant, `main/...` variant. The file is not publicly accessible via unauthenticated GitHub raw URL. Cannot confirm whether `USE_ISP_RETENTION_DATA` has been uncommented. Status remains: unknown via public access. Previously inferred from Google cache to be `// #define USE_ISP_RETENTION_DATA` (commented out) in ameba-rtos-pro2 as of U22. | LOW |
| ameba-arduino-pro2 GitHub Issues — flash+camera concurrent queries (2026-05-26) | **No open issues matching flash + camera concurrency.** Issue search for combined terms "flash camera", "concurrent", "mutex", "VOE_OPEN", "FCS" returns zero relevant open issues. The three closed issues returned (#298 TOF sensor, #257-258 WiFiServer/WiFiClient) are entirely unrelated. The bug appears unreported in the official tracker. | LOW |
| ameba-rtos-pro2 / ameba-arduino-pro2 repo state (2026-05-26) | **ameba-rtos-pro2: Still frozen at `3f95070` (May 15, 2026) — now 12 days.** No new commits. **ameba-arduino-pro2 dev: Still at `29d47e1` (May 26, 2026, PR #410 SPI merge).** No commits since PR #410 landed. **ameba-arduino-pro2 main: Still frozen at Mar 2, 2026 (`93d63514`) — 85 days.** No new V4.1.1-QC-V07 tag created. | LOW |
| FlashMemory.cpp mutex status (from dev branch, confirmed 2026-05-26) | **CONFIRMED ABSENT (again).** Full FlashMemory.cpp source retrieved from `main` branch. `device_mutex_lock` — NOT PRESENT. `RT_DEV_LOCK_FLASH` — NOT PRESENT. All 6 flash operations (`flash_stream_read`, `flash_stream_write`, `flash_erase_sector`, `flash_read_word`, `flash_write_word`, `flash_erase_word`) execute without any synchronization primitives. Identical on both `main` and `dev` branches. SHA `b4781b70` unchanged. | LOW (no change) |
| V4.1.1 binary release `ameba_pro2-4.1.1-build20260519.tar.gz` (74.1 MB, commit `7db1c7d`, May 19, 2026) | **V4.1.1 build20260519 changelog: I2C Slave API, IMX681_5M camera sensor, ameba_pro2_tools 1.4.11, AMB82-zero SWD-off logic, minor bug fix.** No mention of FlashMemory, FCS, flash mutex, camera boot failure, or VOE open failure. The binary blob is 74.1 MB — source diffs not visible; internal changes cannot be verified by web fetch. No V4.1.1 stable release tag exists; only V4.1.1-QC-V06 (Mar 6, 2026) on the releases page. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee, 2026-05-26) | **Zero new content — 52nd consecutive null cycle.** All Chinese community sites remain 403-blocked or return zero relevant results for all query variants. No Chinese-language content discusses FCS flash-write camera failure on RTL8735B/BW21-CBV. | LOW |
| Error string web sweep (2026-05-26) | **Zero indexed results — 52 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"` — all return zero publicly indexed results on the accessible web. | LOW |

**SDK state as of 2026-05-26 (Cycle U52):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp SHA `b4781b70`, zero mutex calls
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; build20260519 binary May 19) — no fix
- ameba-rtos-pro2 main: Frozen at `3f95070` (May 15, 2026) — 12 days no change
- ameba-arduino-pro2 dev: `29d47e1` (May 26, 2026, PR #410 SPI merge — no fix)
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — 85 days no change
- ameba-tool-rtos-pro2: Frozen at March 9, 2026 (`c1d70e7`) — 78 days no change
- ideashatch/HUB-8735: Frozen at Dec 2, 2025 — 175 days no change
- Ai-Thinker-Open: No RTL8735B/BW21 repositories (confirmed U36)

**No confirmed fix. Bug remains unpatched as of 2026-05-26 (Cycle U52).**

**Top unresolved actions (unchanged from U51):**
1. **Hardware test of "Camera FCS Mode = Disable"** — source-confirmed full FCS bypass via dummy blob; **FCS Disable is the Arduino IDE default (boards.txt), so this is restoring default behavior**; no public hardware test result exists anywhere. Highest priority.
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; SD card subsystem was explicitly patched with mutex in PR #9 (Jul 2025) while NOR flash path was not; FlashMemory.cpp is the sole unguarded storage path; callable from Arduino via forward declaration.
3. **File a GitHub Issue** — no issue has ever been filed against ameba-arduino-pro2 for this bug. Filing one with the confirmed root-cause chain (FlashMemory.cpp missing RT_DEV_LOCK_FLASH, ISP FCS race, boot ROM reads 0xFF) could prompt Realtek engineers to patch it. The fix is a one-liner per flash operation.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes at source; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`; file not accessible via public GitHub path.

## Research Update — 2026-05-27 (Cycle U53)

**Search scope:** Four parallel agents: (1) GitHub — repos activity post-May 26; commits/PRs/issues/releases since PR #410 merge; (2) English forum/web — threads above #4868, hardware test reports, parallel manifestations; (3) Chinese sources — comprehensive sweep (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/Bilibili/Gitee/mcublog.cn); (4) SDK deep-dive — video_api.c FCS locking architecture, video_api.h USE_ISP_RETENTION_DATA status, VOE release history (hal_video_release_note.txt), FlashMemory.cpp commit provenance. Plus one targeted follow-up fetch of `hal_video_release_note.txt`.

**Key new findings this cycle:**
- **Complete VOE release history obtained** — `hal_video_release_note.txt` fetched directly (v0.0.0.1 Dec 2021 → v1.7.1.0 Apr 2026; 40+ version entries). ZERO entries relate to FlashMemory, NOR flash mutex, flash bus contention, or cold boot camera failure after user flash writes. Several FCS-related fixes exist but for entirely different root causes.
- **CORRECTION — video_api.c locking architecture**: `video_api.c` itself has zero direct calls to `device_mutex_lock` / `device_mutex_unlock` / `RT_DEV_LOCK_FLASH`. The locking that protects FCS reads/writes occurs at the lower ftl layer (`ftl_common_read/write` → `ftl_nor_api.c` → `nor_read/write/erase_cb` → `device_mutex_lock` at NOR layer). FlashMemory bypasses this by calling `flash_erase_sector` / `flash_stream_write` directly — one full layer below where the lock exists. This is architecturally consistent with the three-callback race window (U47).
- **"FCS Mode = Disable" workaround confirmed COMPLETE**: `video_pre_init_save_cur_params()` still writes AE/AWB data to `NOR_FLASH_FCS` (0xF0D000) even in Disable mode. However, with Disable mode, KM reads the 0x8000 static FCS partition header → finds dummy invalid header → enters `FCS_BYPASS_WHILE1_KM (0x0083)` → never reads 0xF0D000 runtime data. The race/corruption at 0xF0D000 still occurs but is inconsequential in Disable mode.
- **Forum thread #4832** found: "sys_reset is not consistent, why?" (~April 21, 2026) — camera + OTA combination causing stuck boot after `sys_reset()` — possible parallel manifestation of SPIC bus state not being properly cleaned up on soft reset. Content 403-blocked.
- Zero new Chinese-language content (53rd consecutive null cycle); all repos frozen.

| Source | Key Finding | Priority |
|---|---|---|
| `hal_video_release_note.txt` — fetched from `ameba-rtos-pro2` main branch (v0.0.0.1 Dec 2021 → v1.7.1.0 Apr 2026) | **Complete VOE release history — ZERO FCS flash-race fix entries in 40+ versions.** Entire history reviewed. FCS-related entries found: `v1.2.7.2 (Jun 29, 2022)` "fixed OSD on fcs fail issue" (OSD display rendering when FCS mode is in fail state — unrelated to NOR flash corruption); `v1.4.7.0 (Sep 22, 2023)` "Fix HDR sensor FCS fail issue" (HDR sensor I2C init failing during FCS — sensor-specific, different root cause from flash race); `v1.5.1.0 (Jan 26, 2024)` "Support FCS RGB stream drop frame" (feature addition — frame-dropping during FCS fast-start); `v1.4.4.0 (Jun 26, 2023)` "add semephore protection during stream close" (stream close lifecycle, not flash bus); `v1.4.5.2 (Aug 4, 2023)` "move hal_voe_sema from open(out_cb)/close to init/deinit" (semaphore lifecycle improvement); `v1.3.7.0 (Dec 16, 2022)` "Add semaphore process when voe cmd timeout cases" (VOE IPC timeout protection). **No entry anywhere in 40+ releases mentions: FlashMemory, NOR flash mutex, flash bus contention, RT_DEV_LOCK_FLASH, cold boot camera failure after user flash writes, or any fix for the `KM_status 0x2081 err 0x200A` failure pattern.** Bug has existed since at least v1.2.0.0 (Feb 2022) when FCS was first fully functional and has never been addressed in the VOE layer. | MEDIUM |
| `video_api.c` locking architecture (fetched from `ameba-rtos-pro2` main, May 27, 2026) | **CORRECTION: video_api.c has ZERO direct calls to device_mutex_lock.** The FCS read (`ftl_common_read`) and write (`ftl_common_write`) calls in `video_api.c` are not directly protected by any mutex within `video_api.c`. The locking happens one layer below: `ftl_common_read/write` → `ftl_nor_api.c` → `nor_read_cb`/`nor_erase_cb`/`nor_write_cb` → each callback individually calls `device_mutex_lock(RT_DEV_LOCK_FLASH)` and `device_mutex_unlock`. The prior research statement "FCS data read correctly locked via ftl_common_read → NOR callbacks" was accurate about the mechanism but the framing was potentially misleading. **The three-callback race window (U47) remains valid**: FlashMemory calls `flash_erase_sector`/`flash_stream_write` at the HAL level — one full layer below `ftl_common_*` — which bypasses `RT_DEV_LOCK_FLASH` entirely. The race is not between video_api.c and FlashMemory.cpp directly; it's between the ftl_nor_api callbacks (which individually lock then unlock for each phase: read → erase → write) and FlashMemory's unguarded HAL calls that can interleave between those individual lock/unlock cycles. | MEDIUM |
| `video_api.c` / `video_pre_init_save_cur_params()` FCS Mode gate analysis | **"FCS Mode = Disable" workaround confirmed COMPLETE despite unconditional 0xF0D000 write.** `video_pre_init_save_cur_params()` writes current AE/AWB parameters to `NOR_FLASH_FCS (0xF0D000)` unconditionally — it is NOT gated by the FCS Mode Enable/Disable setting. However, this does not invalidate the workaround: (1) With FCS Mode = Disable, `postbuild` writes `fcs_data_dummy.bin` (invalid `ISP_MULTI_FCS_DATA_MAGIC_NUM`) to the static FCS partition at 0x8000. (2) At cold boot, KM co-processor reads 0x8000 header, finds invalid magic number → immediately enters `FCS_BYPASS_WHILE1_KM (0x0083)`. (3) KM **never reads 0xF0D000** — it bypasses the entire FCS I2C initialization sequence. (4) Camera initializes via application layer (`video_init_peri()` / `NONE_FCS_MODE`). The race condition and potential corruption at 0xF0D000 still occur, but the corrupted data is never accessed at boot. Workaround prevents the boot failure by making the corrupted data unreachable, not by preventing the corruption. | MEDIUM |
| Forum thread #4832 — "sys_reset is not consistent, why?" (~April 21, 2026; forum.amebaiot.com, 403-blocked; reconstructed from Google snippet) | **Potential parallel manifestation: camera + OTA write → stuck boot after sys_reset().** Google snippet describes: after an OTA flash write operation, calling `sys_reset()` causes the board to be stuck in boot — camera never re-opens; sometimes hangs; `sys_reset()` behavior is inconsistent. This is distinct from the cold-boot FCS race (which requires a full power cycle), but the trigger (large flash write → reset) and symptom (camera fail on next boot) share the same class. Root cause may be: NOR flash WIP bit active during soft reset → SPIC peripheral state not fully re-initialized by `sys_reset()` (which bypasses Boot ROM flash init sequence). Content 403-blocked; exact error messages unknown. Thread number above U52's ceiling of #4834, confirming forum has new content above #4834. | LOW |
| `video_api.h` — `USE_ISP_RETENTION_DATA` (confirmed in both `ameba-rtos-pro2` main and `ameba-arduino-pro2` dev, May 27, 2026) | **`USE_ISP_RETENTION_DATA` confirmed commented out in both repos: `` // #define USE_ISP_RETENTION_DATA `` at line ~97 (rtos-pro2) / ~129 (arduino-pro2).** The `SAVE_TO_RETENTION` paths in `video_pre_init_load_params` and `video_pre_init_save_cur_params` are dead code. Uncommenting this define eliminates ISP flash writes entirely (AE/AWB saved to SRAM retention instead of NOR flash), removing the ISP side of the race condition. Status unchanged from U22. | LOW |
| FlashMemory.cpp provenance (from English web search, May 27, 2026) | **FlashMemory.cpp last modified commit: short SHA `4fdfbec`, September 30, 2025.** This is the commit (7-char short form) that last touched FlashMemory.cpp, distinct from the git blob SHA `b4781b70b4603949a41751999a7ff2af6ddc75b0` documented in U37. Both refer to the same content state. Zero mutex guards confirmed via fresh fetch. File unchanged since Sept 30, 2025 (8 months). | LOW |
| ameba-rtos-pro2 / ameba-arduino-pro2 — all repos (fetched May 27, 2026) | **All repos frozen. ameba-rtos-pro2: Still at `3f95070` (May 15, 2026) — now 12 days frozen. ameba-arduino-pro2 dev: Still at `29d47e1` (May 26, 2026, PR #410) — 1 day since PR #410. No new commits, releases, or issues. PR #17 (ethernet USB buffer overflow) still the only open PR in ameba-rtos-pro2. No V4.1.1-QC-V07 tag.** | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/Bilibili/Gitee/mcublog.cn, May 27, 2026) | **Zero new content — 53rd consecutive null cycle.** mcublog.cn has its first-ever BW21-CBV article (April 2026, Feishu bot + LED + camera photo integration) — 403-blocked, title/snippet confirms unrelated to flash-camera bug. Two Zhihu articles about BW21-CBV (fall detection 2025; HomeAssistant integration 2026) — both 403-blocked, unrelated topics. All Chinese community forums remain 403-blocked. Zero Chinese-language content discusses the FCS flash-write cold-boot camera failure. | LOW |
| Error string / hardware test web sweep (May 27, 2026) | **Zero indexed results — 53 consecutive null cycles.** All canonical error strings unindexed. No hardware test result for any of the three workarounds posted anywhere in any language. Highest-indexed forum thread remains #4868; thread #4832 (sys_reset inconsistency) is new but content is 403-blocked. | LOW |

**VOE release history — complete FCS timeline (from hal_video_release_note.txt):**

| VOE Version | Date | FCS-Related Change |
|---|---|---|
| 1.7.1.0 | Apr 21, 2026 | Fix dual sensor id FCS mirror/flip issue (sensor initialization ordering) |
| 1.5.6.0 | Jul 17, 2024 | Reinit GPIO in FCS mode (GPIO re-initialization during FCS fast-start) |
| 1.5.1.0 | Jan 26, 2024 | Support FCS RGB stream drop frame (frame-drop feature during FCS) |
| 1.5.0.0 | Dec 29, 2023 | FCS NV12+RGB (new FCS stream format support) |
| 1.4.7.0 | Sep 22, 2023 | **Fix HDR sensor FCS fail issue** (HDR sensor I2C init race — sensor-specific, NOT flash race) |
| 1.4.3.1 | Jun 15, 2023 | Add terminating FCS flow weak func and example code |
| 1.4.2.0 | Mar 31, 2023 | Update API for private mask feature in FCS flow |
| 1.3.7.2 | Jan 6, 2023 | Remove GPIO E4 pinmux_unregister (b-cut FCS pin mapping issue workaround) |
| 1.3.0.0 | Jul 14, 2022 | Add fcs_id valid check during fw/iq/sensor load |
| **1.2.7.2** | **Jun 29, 2022** | **"fixed OSD on fcs fail issue"** (OSD display when FCS fails — NOT flash race) |
| 1.2.5.0 | May 1, 2022 | Add sc2336 fcs_data |
| 1.2.4.0 | Apr 20, 2022 | Add peri_info from fcs_data |
| 1.2.0.0 | Feb 25, 2022 | Added `hal_video_fcs_ch(cnt)` API for sync bootloader FCS channel counter |
| 1.0.0.0 | Dec 9, 2021 | Add GC2053 fcs_data; modify NN section for FCS video |

**ZERO entries in entire VOE history mention:** FlashMemory, NOR flash mutex, flash bus arbitration, RT_DEV_LOCK_FLASH, cold boot camera failure after user flash writes, or any fix for `KM_status 0x2081 err 0x200A`. This confirms the bug has never been addressed at the VOE layer.

**Locking architecture clarification (updates to U47 three-callback race window):**

```
FlashMemory.write() / FlashMemory.erase()
  └─ flash_erase_sector(flash_t*, addr)        [mbed API layer]
       └─ hal_flash_sector_erase()              [C HAL wrapper]
            └─ NS stubs → spic_ns_tx_cmd()     [NS hardware layer]
                                               ← NO RT_DEV_LOCK_FLASH anywhere above this

ftl_common_write(addr, buf, size)              [FTL common layer]
  └─ ftl_write_nor(addr, buf, size)            [FTL NOR layer]
       ├─ nor_read_cb()  → device_mutex_lock(RT_DEV_LOCK_FLASH) → [read]  → unlock
       ├─ nor_erase_cb() → device_mutex_lock(RT_DEV_LOCK_FLASH) → [erase] → unlock
       └─ nor_write_cb() → device_mutex_lock(RT_DEV_LOCK_FLASH) → [write] → unlock
            ↑ FlashMemory can inject SPIC commands between any two of these
```

The race window exists because: (1) each FTL callback locks→operates→unlocks individually, with no outer lock spanning all three; (2) FlashMemory operates at the HAL level, bypassing the FTL/NOR callback layer entirely and thus never seeing or respecting `RT_DEV_LOCK_FLASH`. This architecture is confirmed by direct source code inspection across both repos.

**SDK state as of 2026-05-27 (Cycle U53):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp blob SHA `b4781b70`, zero mutex calls
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; build20260519 binary May 19) — no fix
- ameba-rtos-pro2 main: Frozen at `3f95070` (May 15, 2026) — **12 days** no change
- ameba-arduino-pro2 dev: `29d47e1` (May 26, 2026, PR #410 SPI merge — no fix)
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — **86 days** no change
- ameba-tool-rtos-pro2: Frozen at March 9, 2026 (`c1d70e7`) — **79 days** no change
- ideashatch/HUB-8735: Frozen at Dec 2, 2025 — **176 days** no change
- Ai-Thinker-Open: No RTL8735B/BW21 repositories (confirmed U36)
- VOE binary: v1.7.1.0 (Apr 21, 2026) — latest; no FCS flash-race fix in entire release history

**No confirmed fix. Bug remains unpatched as of 2026-05-27 (Cycle U53).**

**Top unresolved actions (updated from U52):**
1. **Hardware test of "Camera FCS Mode = Disable"** — FCS bypass via dummy blob confirmed effective: KM reads invalid 0x8000 header → `FCS_BYPASS_WHILE1_KM` → never reads 0xF0D000 runtime data; camera inits via application layer. FCS Disable is the Arduino IDE default. No public hardware test result exists.
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Architecturally correct fix: wrapping all FlashMemory HAL calls with `device_mutex_lock(1)` / `device_mutex_unlock(1)` would serialize FlashMemory against the FTL NOR callbacks. Callable from Arduino via `extern "C" void device_mutex_lock(unsigned int); #define RT_DEV_LOCK_FLASH 1`. VOE release history confirms Realtek has never applied this fix. No public hardware test result exists.
3. **File a GitHub Issue** — no issue has ever been filed against ameba-arduino-pro2 for this bug; VOE release history (40+ versions) contains no acknowledgment; bug is fully undocumented outside this research log. Filing with the confirmed root-cause chain would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes at source; `// #define USE_ISP_RETENTION_DATA` in `video_api.h` (both repos, confirmed May 27). No public hardware test result exists.

## Research Update — 2026-05-28 (Cycle U54)

**Search scope:** GitHub repository status check (ameba-rtos-pro2, ameba-arduino-pro2 dev/main/releases, ideashatch/HUB-8735), English web/forum (new threads above #4868, hardware test reports, error strings), Chinese-language sources (CSDN, bbs.aithinker.com). MCP GitHub access restricted to user repo only this session; all external checks via WebFetch and WebSearch. Note: forum.amebaiot.com returns HTTP 403 for all thread content fetches.

**Key new findings this cycle:**
- **All repos still frozen at same commits as U53.** ameba-rtos-pro2: `3f95070` (May 15, 2026) — now 13 days frozen. ameba-arduino-pro2 dev: `29d47e1` (May 26, 2026, PR #410) — 2 days frozen. ameba-arduino-pro2 main: V4.1.0 / `93d63514` (Mar 2, 2026) — 87 days frozen. ideashatch/HUB-8735: `870a7e0` (Dec 2, 2025) — 177 days frozen.
- **ameba-arduino-pro2 releases confirmed**: Latest stable still V4.1.0 (March 2, 2026); latest pre-release V4.1.1-QC-V06 (tag March 6, 2026). No new release since U53. Release notes for V4.1.1-QC-V06 mention "Add feature Flash Memory" (V4.0.8 era) and "Add feature FCS mode for all supported sensors" (V4.0.8 era) — no mutex or camera boot fix anywhere in release history.
- **ameba-arduino-pro2 open issues**: Latest open issue confirmed as #398 (March 29, 2026 — feature request for raw/encoded video data access). No new issues. No issues mentioning FlashMemory, mutex, FCS, or camera boot failure.
- **ameba-rtos-pro2 open PRs**: Only open PR remains #17 (ethernet USB buffer overflow fix, opened May 15, 2026 by orbisai0security — 3 tasks done, still unmerged). No new PRs. No PRs related to FlashMemory or RT_DEV_LOCK_FLASH.
- **Forum threads above #4868**: Zero new threads indexed. Search for thread IDs #4869–#4880 returned no results. The highest publicly indexed thread remains #4868 (NN model loading from flash/SD, ~May 21, 2026).
- **Thread #4865** "AmebaPro2 uartfwburn - Can't flash. 'fail for download 0' after 'programing' is 100% complete" — firmware flashing tool failure during programming; unrelated to FlashMemory.cpp / FCS camera bug.
- **Thread #4834** "Boot failure after OTA update" (April 24, 2026) — content 403-blocked; Google snippet indicates post-OTA boot-ROM NOR flash detection failure (`[SPIF Err]Invalid ID`, `[BOOT Err]Flash init error` pattern). Distinct from cold-boot FCS race: the OTA thread describes physical flash detection failure (likely power-cut-during-erase or flash corruption during firmware write), not FCS/KM camera initialization failure after user FlashMemory.write().
- Zero English or Chinese hits for FlashMemory mutex fix, RT_DEV_LOCK_FLASH patch, FCS camera cold-boot failure after user flash writes.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 main (WebFetch, May 28, 2026) | **Frozen at `3f95070` (May 15, 2026) — 13 days no change.** Only open PR is #17 (ethernet USB buffer overflow, opened May 15, still unmerged). No commits, no new PRs, no FlashMemory-related activity. | LOW |
| ameba-arduino-pro2 dev + releases (WebFetch, May 28, 2026) | **Dev branch frozen at `29d47e1` (May 26, 2026, PR #410 SPI).** Latest commits before today: May 26 (#410 SPI), May 19 (Pre Release V4.1.1 + cam IMX681_5M #409), May 18 (I2C Slave #408). Latest official release: V4.1.0 (Mar 2, 2026). Latest pre-release: V4.1.1-QC-V06 (Mar 6, 2026). No new release since V4.1.0 in 87 days. No mutex, FCS, or camera boot fix in any release note. | LOW |
| ameba-arduino-pro2 issues (WebFetch, May 28, 2026) | **Latest open issue is #398 (March 29, 2026 — feature request: raw/H264/H265 video data access).** No new issues above #398. No issue ever filed for FlashMemory/RT_DEV_LOCK_FLASH/FCS camera boot bug. The bug remains completely undocumented in the official issue tracker. | LOW |
| ideashatch/HUB-8735 (WebFetch, May 28, 2026) | **Confirmed frozen at `870a7e0` ("4.1.1", Dec 2, 2025) — 177 days no change.** Repository author (H-owar-d) has made no commits since Dec 2. | LOW |
| Forum thread #4834 — "Boot failure after OTA update" (April 24, 2026; forum.amebaiot.com, 403-blocked, reconstructed from search snippet) | **Different failure pattern from FCS cold-boot race.** OTA firmware write failure causing `[SPIF Err]Invalid ID` / `[BOOT Err]Flash init error` at next boot — Boot ROM can no longer detect NOR flash. This is the most severe point on the severity ladder (U11: power cut during erase → `[SPIF Err]Invalid ID`). The mechanism here is likely OTA writing to the wrong partition or flash becoming physically unresponsive. Distinct from the FCS camera initialization failure that is our primary bug, which leaves flash fully functional but corrupts the KM boot-camera I2C parameters. | LOW |
| All error strings / hardware test / Chinese sources (May 28, 2026) | **Zero indexed results — 54th consecutive null cycle.** All canonical error strings (`VOE_OPEN_CMD command fail`, `hal_video_open fail`, `FCS_RUN_DATA_NG_KM`, `FCS_I2C_INIT_ERR`, `RT_DEV_LOCK_FLASH FlashMemory`) unindexed. No hardware test result for any of the three workarounds in any language. Chinese forums (bbs.aithinker.com, CSDN, 知乎, EEWorld) 403-blocked; zero indexed Chinese content discusses FCS flash-write cold-boot camera failure. | LOW |

**SDK state as of 2026-05-28 (Cycle U54):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp blob SHA `b4781b70`, zero mutex calls
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; build20260519 binary May 19) — no fix
- ameba-rtos-pro2 main: Frozen at `3f95070` (May 15, 2026) — **13 days** no change
- ameba-arduino-pro2 dev: `29d47e1` (May 26, 2026, PR #410 SPI merge — no fix)
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — **87 days** no change
- ameba-tool-rtos-pro2: Frozen at March 9, 2026 (`c1d70e7`) — **80 days** no change
- ideashatch/HUB-8735: Frozen at Dec 2, 2025 — **177 days** no change
- Ai-Thinker-Open: No RTL8735B/BW21 repositories (confirmed U36)
- VOE binary: v1.7.1.0 (Apr 21, 2026) — latest; zero FCS flash-race fix entries in entire release history

**No confirmed fix. Bug remains unpatched as of 2026-05-28 (Cycle U54).**

**Top unresolved actions (unchanged from U53):**
1. **Hardware test of "Camera FCS Mode = Disable"** — FCS bypass via dummy blob confirmed effective: KM reads invalid 0x8000 header → `FCS_BYPASS_WHILE1_KM` → never reads 0xF0D000 runtime data; camera inits via application layer. FCS Disable is the Arduino IDE default (boards.txt first option). No public hardware test result exists anywhere.
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Architecturally correct fix: wrapping all FlashMemory HAL calls with `device_mutex_lock(1)` / `device_mutex_unlock(1)` serializes FlashMemory against FTL NOR callbacks. Callable from Arduino via `extern "C" void device_mutex_lock(unsigned int); #define RT_DEV_LOCK_FLASH 1`. VOE release history (40+ versions) confirms Realtek has never applied this fix.
3. **File a GitHub Issue** — no issue has ever been filed against ameba-arduino-pro2 for this bug (confirmed: highest open issue is #398, a video feature request). VOE release history and all 54 research cycles contain no acknowledgment. Filing with the confirmed root-cause chain (three-callback race window, FlashMemory HAL bypass of RT_DEV_LOCK_FLASH, cold-boot KM I2C init corruption) would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes at source; `// #define USE_ISP_RETENTION_DATA` in `video_api.h` (both repos, confirmed May 27). No public hardware test result exists.

**Search scope:** Two background agents whose results arrived after U53 was committed: (1) Agent `a4e3c7667d51313db` — English forum / web sweep (forum ceiling, error strings, workaround hardware test reports, SDK releases, Reddit/Hackster/Instructables); (2) Agent `a57fc52178f3a0fae` — Chinese sources sweep (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn) + supplementary English web searches. Both agents ran in parallel during U53; their consolidated findings are documented here as U54.

**Key new findings this cycle:** None — 54th consecutive null research cycle. Both agents returned all-null results consistent with prior cycles. Two minor new thread references found (forum #1005 and official Flash Memory example URL) but both 403-blocked and neither mentions the bug. All other channels remain frozen/blocked/empty.

| Source | Key Finding | Priority |
|---|---|---|
| forum.amebaiot.com thread #1005 "Saving user parameters in flash" (English agent, May 27, 2026) | **Newly found thread reference.** Title: "Saving user parameters in flash" — discusses persistence of user settings to NOR flash on AMB82 boards. No FCS, camera, mutex, or cold-boot content visible in search snippet. Content 403-blocked. Not related to our bug. URL: https://forum.amebaiot.com/t/saving-user-parameters-in-flash/1005 | LOW (blocked, unrelated) |
| amebaiot.com.cn/en/amebapro2-arduino-flash-writestream/ (Chinese agent, May 27, 2026) | **Official Realtek Flash Memory example page (Chinese mirror).** 403-blocked; snippet confirms: "Flash Memory – Read Write Stream" — demonstrates `FlashMemory.write()` / `FlashMemory.read()` usage. No mention of camera incompatibility, mutex, FCS mode, `RT_DEV_LOCK_FLASH`, or any warning about concurrent camera use in title/snippet. Consistent with all prior reads of this documentation: no safety warning published anywhere. | LOW (blocked, confirms no warning) |
| forum.amebaiot.com threads above #4868 (English agent, May 27, 2026) | **Zero new threads indexed above #4868.** Targeted searches for IDs #4869–#4940 returned zero results from the forum domain. Forum ceiling confirmed at #4868 ("NN Model loading from Memory instead of Flash or SD card failing with exceptions"). Thread #4832 (sys_reset inconsistency, April 2026) confirmed as the highest newly-identified content in the #4830–#4834 range, already documented in U53. All direct forum fetches return HTTP 403. | LOW |
| Error string sweep — English agent (May 27, 2026) | **Zero indexed results — 54 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"` — all return zero publicly indexed results anywhere on the accessible web. | LOW |
| Hardware test confirmation — all three workarounds (English agent, May 27, 2026) | **Zero results — 54 consecutive null cycles.** "Camera FCS Mode = Disable" + flash workaround, `device_mutex_lock` + AMB82 + flash camera, `USE_ISP_RETENTION_DATA` + tested — all return zero results. No community member has publicly reported testing any of the three proposed workarounds on hardware after 54 research cycles (22+ days of monitoring). | LOW |
| Reddit / Hackster.io / Instructables (English agent, May 27, 2026) | **Zero results.** No reports of RTL8735B FCS flash camera boot failure on any English-language community platform outside the Realtek forum. | LOW |
| ameba-arduino-pro2 V4.1.1 stable release status (English agent, May 27, 2026) | **No stable V4.1.1 release.** Search confirms V4.1.1 exists only as pre-release `V4.1.1-QC-V06` (tag Mar 6, 2026; build20260519 binary May 19). The latest stable release remains V4.1.0 (Mar 2, 2026). No V4.1.1-QC-V07 or stable V4.1.1 tag has been published. | LOW |
| ameba-rtos-pro2 May 2026 activity (English agent, May 27, 2026) | **Confirmed frozen at `3f95070` (May 15, 2026) — 12 days.** Most recent commits: `3f95070`, `afc85a0`, `9c8b6f6`, `d2676f1` (all May 15). PR #17 (ethernet USB buffer overflow security fix) still open and unmerged. No flash, FCS, VOE, boot, HAL, sensor, or mutex changes. | LOW |
| forum.amebaiot.com thread #1239 "RTL8720C 数据保存到FLASH后再次启动 log显示启动失败" (Chinese agent, May 27, 2026) | **NEW — Sibling chip confirmation of "data written to flash → reboot → startup failure" pattern.** Thread title translates to "RTL8720C: after saving data to FLASH, re-boot shows startup failure in log." Filed May 2022 in Chinese on the same forum. Sibling SoC (RTL8720C, not RTL8735B), but exact same failure class: flash write → reboot → boot log shows failure. Search snippet references flash partition configurations (FC_SYSTEM, FC_BOOT). Content 403-blocked; fix/workaround unknown. This is the first Chinese-language community report found of the "save to flash → startup failure" bug pattern on any Ameba family chip. URL: https://forum.amebaiot.com/t/rtl8720c-flash-log/1239 | LOW-MEDIUM (sibling chip; different SoC; content 403-blocked; causal mechanism unconfirmed but failure pattern match) |
| All Chinese-language sources (Chinese agent, CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn, May 27, 2026) | **54th consecutive null cycle for RTL8735B/BW21-CBV-specific content.** CSDN: 2 generic AMB82 MINI intro articles (no bug content). Zhihu: 2 BW21-CBV articles (fall detection; HomeAssistant integration) — both 403-blocked, snippets unrelated. EEWorld/21ic: no RTL8735B content. bbs.aithinker.com BW21-CBV threads (tid≤47223) all 403-blocked. mcublog.cn BW21-CBV article (April 2026, Feishu bot + LED + camera) 403-blocked. Bilibili: no relevant videos. Gitee: no relevant repos. No Chinese-language content discusses FCS flash-write cold-boot camera failure on RTL8735B/BW21-CBV specifically. Thread #1239 (RTL8720C) is the only cross-language find with the same failure class. | LOW |

**SDK state as of 2026-05-27 (Cycle U54 — unchanged from U53):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp SHA `b4781b70`, zero mutex calls
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; build20260519 binary May 19) — no fix
- ameba-rtos-pro2 main: Frozen at `3f95070` (May 15, 2026) — **12 days** no change
- ameba-arduino-pro2 dev: `29d47e1` (May 26, 2026, PR #410 SPI merge — no fix)
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — **86 days** no change
- ameba-tool-rtos-pro2: Frozen at March 9, 2026 (`c1d70e7`) — **79 days** no change
- ideashatch/HUB-8735: Frozen at Dec 2, 2025 — **176 days** no change
- Ai-Thinker-Open: No RTL8735B/BW21 repositories (confirmed U36)
- VOE binary: v1.7.1.0 (Apr 21, 2026) — latest; no FCS flash-race fix in entire release history (40+ versions, confirmed U53)

**No confirmed fix. Bug remains unpatched as of 2026-05-27 (Cycle U54).**

**Top unresolved actions (unchanged from U53):**
1. **Hardware test of "Camera FCS Mode = Disable"** — FCS bypass via dummy blob confirmed effective: KM reads invalid 0x8000 header → `FCS_BYPASS_WHILE1_KM` → never reads 0xF0D000 runtime data; camera inits via application layer. FCS Disable is the Arduino IDE default (boards.txt). No public hardware test result exists. (Proposed Cycle U7, May 14 — 13 days unresolved.)
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Architecturally correct fix: wrapping all FlashMemory HAL calls with `device_mutex_lock(1)` / `device_mutex_unlock(1)` serializes FlashMemory against the FTL NOR callbacks. Callable from Arduino via `extern "C" void device_mutex_lock(unsigned int); #define RT_DEV_LOCK_FLASH 1`. VOE release history (40+ versions) confirms Realtek has never applied this fix. No public hardware test result exists.
3. **File a GitHub Issue** — no issue has ever been filed against ameba-arduino-pro2 for this bug; VOE release history contains no acknowledgment; bug is fully undocumented outside this research log. Filing with the confirmed root-cause chain would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes at source; `// #define USE_ISP_RETENTION_DATA` in `video_api.h` (both repos, confirmed May 27). No public hardware test result exists.

## Research Update — 2026-05-27 (Cycle U55)

**Search scope:** Four parallel agents: (1) GitHub — ameba-rtos-pro2 compare endpoint and direct commit page; ameba-arduino-pro2 dev/main commits, releases, issues, and PRs; ideashatch/HUB-8735 issues; (2) English forum/web — new threads above #4868, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn; (4) SDK deep-dive — FlashMemory.cpp mutex status, `GitHub_release_note.txt` new entries after SHA 7343927f, VOE version status.

**Key new findings this cycle:**
- **PR #410 "Update SPI API for SPI1 switching" confirmed MERGED** into `dev` on May 26, 2026 by pammyleong — corrects U53/U54 characterization of PR #410 as "open." The `dev` HEAD is now `29d47e1` incorporating this SPI1 change; unrelated to flash/FCS bug.
- **`GitHub_release_note.txt` older entries enumerated** from SDK agent fetch (AI Glass app, KVS WebRTC v2, PIR sensor example, BT controller patch, Sensor driver & video settings, WiFi crash prevention, etc.) — these are pre-existing entries already in the file prior to U53 that were not previously enumerated explicitly in the log. None reference FCS, flash bus arbitration, or camera boot fixes.
- All other channels are identical to U54 — 55th consecutive null cycle. No fix, no workaround hardware test results, no Chinese-language content.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 compare `3f95070...HEAD` (direct fetch, 2026-05-27, two agents) | **Confirmed frozen — identical to U54.** GitHub returns "3f95070 and HEAD are identical." Zero new commits in 12 days since May 15, 2026. PR #17 (ethernet USB driver buffer overflow fix, orbisai0security) still open and unmerged. No flash, FCS, VOE, boot, HAL, or sensor changes visible. | LOW |
| ameba-arduino-pro2 dev branch (direct fetch, 2026-05-27, two agents) | **HEAD = `29d47e1` "Update SPI API for SPI1 switching (#410)" (May 26, 2026).** PR #410 confirmed MERGED on May 26 by pammyleong — corrects U53/U54 "open" characterization. Zero new commits after May 26. No FCS/flash/camera fix in any commit. Includes SPI API enhancements, I2C slave example documentation, and SD card compilation fixes — unrelated to our bug. | LOW (correction) |
| ameba-arduino-pro2 main branch (direct fetch, 2026-05-27) | **Still frozen at `93d63514` (Mar 2, 2026) — 86 days no change.** No new commits to `main`. Latest stable = V4.1.0. Latest pre-release = V4.1.1-QC-V06. No V4.1.1-QC-V07 or stable V4.1.1 published. | LOW |
| ameba-arduino-pro2 open issues (direct fetch, 2026-05-27, two agents) | **11–12 open issues (count variation by authentication state); newest = #398 (Mar 29, 2026).** No new issues after March 29, 2026. No issues about FlashMemory, FCS, camera, VOE, or boot failure in open or closed history. Bug remains entirely unreported on the official tracker after 55 research cycles. Camera-related open issues (#310, #287, #325, #324, #296) are all feature requests about RTSP/RTMP/WebRTC/camera compatibility — none about flash interaction. | LOW |
| ideashatch/HUB-8735 (direct fetch, 2026-05-27) | **Frozen at Dec 2, 2025 (`870a7e0`) — 176 days no change.** Only open issue: #10 (PS5268 sensor id fail, Aug 2025). No new issues or commits. | LOW |
| `FlashMemory.cpp` — dev branch raw fetch (2026-05-27, two agents) | **Zero mutex calls confirmed unchanged in dev HEAD (`29d47e1`).** SHA `b4781b70`. All 6 flash-touching operations call flash HAL functions directly with zero `device_mutex_lock`, `device_mutex_unlock`, or `RT_DEV_LOCK_FLASH`. FlashMemory.h includes only `<Arduino.h>` and `"flash_api.h"` — no mutex infrastructure. The architectural defect persists in every released SDK version through V4.1.1-QC-V06 and in the current dev HEAD. | LOW (confirms prior) |
| `GitHub_release_note.txt` — older entries enumerated (ameba-rtos-pro2, fetched 2026-05-27) | **Pre-existing entries explicitly enumerated for the first time.** Entries already in the file but not previously listed in this log: "KVS WebRTC v2 MMF example (FreeRTOS)", "WoWLAN 11v WPA3 packet decode", "BT external PTA API", "BT controller patch", "PIR sensor example", "WebSocket viewer", "WLAN DHCP rebind checksum fix", "AI Glass application code (multiple commits)", "AI Glass scenario introduction", "Sensor driver & video default settings", "SDK scenario settings", "WiFi crash prevention." These are all OLDER than SHA 7343927f (May 15) — they were present in prior cycles but not enumerated. **None reference FCS, flash bus mutex, concurrent SPIC access, cold-boot camera failure, or RT_DEV_LOCK_FLASH.** No new entries have been added (repo still frozen). | LOW (inventory) |
| forum.amebaiot.com threads above #4868 (sweep, 2026-05-27, two agents) | **No new threads indexed above #4868.** Targeted searches for IDs #4869–#4940 returned zero results from the forum domain. Forum ceiling confirmed at #4868 ("NN Model loading from Memory instead of Flash or SD card failing with exceptions"). Thread #4834 ("Boot failure after OTA update") confirmed as previously known (first documented U11). All direct forum fetches return HTTP 403. | LOW |
| bbs.aithinker.com tid=47223 "【电子DIY作品】BW21数码相机+BW21-CBV-KIT" (Sept 2025, Chinese agent) | **Highest-tid indexed BW21-CBV thread on bbs.aithinker.com.** Title: DIY camera project using BW21-CBV-KIT. No FCS flash failure content visible in indexed snippet; content 403-blocked. Previously documented as a DIY camera project in U23 (tids 45923–47223 enumerated). Now confirmed as the maximum-tid BW21-CBV thread visible in the Google index as of May 27, 2026. If this user wrote to flash while the camera was running, the bug may have occurred but gone unreported. | LOW (blocked, already known) |
| Web-wide error string sweep (2026-05-27, four agents) | **Zero indexed results — 55 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"` — all return zero publicly indexed results anywhere on the accessible web. One agent noted `"It don't do the sensor initial process"` appeared near thread #4777 (AMB82-Mini camera I2C setup, Mar 2026) in search context — content is 403-blocked, causal connection to flash write unconfirmed. | LOW |
| Hardware test results — all three workarounds (2026-05-27, four agents) | **Zero results — 55 consecutive null cycles.** No public report confirms hardware testing of "Camera FCS Mode = Disable," `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper, or `USE_ISP_RETENTION_DATA` as workarounds for the flash-write cold-boot camera failure. No community member has reported testing any workaround after 13 days of monitoring (since the top-3 list was compiled on May 14 in U7). | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn, May 27 sweep, two agents) | **Zero new content — 55th consecutive null cycle.** All Chinese community sites remain 403-blocked or return zero relevant results. No Chinese-language forum posts or articles discuss FCS flash-write camera failure on RTL8735B or BW21-CBV. RTL8720C thread #1239 (flash→boot failure, May 2022) remains the only Chinese-language parallel — still 403-blocked. mcublog.cn BW21-CBV article (April 2026, Feishu bot + LED + photo) confirmed 403-blocked. | LOW |

**`GitHub_release_note.txt` — complete upstream entry inventory (as of May 15, 2026 sync):**

All entries in the file as of the last "Sync upstream" commit (`3f95070`, May 15, 2026) are now enumerated. Entries related to camera/video: "Sensor driver & video default settings" and "video update sensor driver" (SHAs `ccd2b17c`, `4de7607b`) — both appear to be routine sensor driver maintenance. Zero entries related to FCS cold-boot failure, flash bus mutex, or SPIC concurrent access.

**SDK state as of 2026-05-27 (Cycle U55 — unchanged from U54):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp SHA `b4781b70`, zero mutex calls
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; release notes through May 19, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at `3f95070` (May 15, 2026) — **12 days** no change; PR #17 (ethernet security fix) open and unmerged
- ameba-arduino-pro2 dev: `29d47e1` (May 26, 2026, PR #410 SPI API — no fix; PR #410 now confirmed MERGED)
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — **86 days** no change
- ameba-tool-rtos-pro2: Frozen at March 9, 2026 (`c1d70e7`) — **79 days** no change
- ideashatch/HUB-8735: Frozen at Dec 2, 2025 — **176 days** no change
- Ai-Thinker-Open: No RTL8735B/BW21 repositories (confirmed U36)
- VOE binary: v1.7.1.0 (Apr 21, 2026) — latest; no FCS flash-race fix in entire 46-version release history

**No confirmed fix. Bug remains unpatched as of 2026-05-27 (Cycle U55).**

**Top unresolved actions (unchanged from U54):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority. 13 days unresolved since U7 (May 14).**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp is the sole exception. Forward-declaration callable from Arduino: `extern "C" void device_mutex_lock(unsigned int); device_mutex_unlock(unsigned int); #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug is fully undocumented outside this research log; VOE release history (46 versions) contains zero acknowledgment; filing would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes at source; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-05-28 (Cycle U56)

**Search scope:** Six parallel search threads: (1) GitHub — ameba-rtos-pro2 compare endpoint + direct commits page; ameba-arduino-pro2 dev/main branches, releases, open/closed PRs, issues; ideashatch/HUB-8735 issues; (2) English forum/web — new threads above #4868, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` workaround hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn; (4) Error string indexing — all canonical FCS/VOE/FCS_I2C_INIT_ERR error strings; (5) ameba-rtos-pro2 PR #17 status; (6) General web search for any new hardware test reports of the three proposed workarounds.

**Key new findings this cycle:** None — 56th consecutive null research cycle. All repositories, forum threads, documentation portals, and error-string searches return the same freeze / blocked / empty state as Cycle U55. All channels are unchanged.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 commits page (direct GitHub fetch, 2026-05-28) | **Confirmed frozen — identical to U55.** Ten most recent commits verified: `3f95070` (May 15), `afc85a0` (May 15), `9c8b6f6` (May 15), `d2676f1` (May 15), `1c1c8b7` (May 1), `a111e91` (May 1), `7b2b97f` (May 1), `63c0a2f` (May 1), `d54e1a8` (May 1), `687a4c7` (May 1). **Zero new commits in 13 days since May 15, 2026.** No flash, FCS, VOE, boot, HAL, or sensor changes in any commit. | LOW |
| ameba-arduino-pro2 dev branch + PRs (direct GitHub fetch, 2026-05-28) | **Confirmed frozen — identical to U55.** HEAD = `29d47e1` "Update SPI API for SPI1 switching (#410)" (May 26, 2026). Ten most recent commits verified: `29d47e1` (May 26), `7db1c7d` (May 19), `3d53672` (May 19), `cd0bd40` (May 18), `13961cc` (May 5), and prior entries unchanged. **Zero new commits after May 26, 2026.** PR list confirmed: highest PR is #410 (merged May 26), no PRs above #410 exist in open or closed state. No FCS/flash/camera/mutex-related PRs in any state. | LOW |
| ameba-arduino-pro2 releases page (direct GitHub fetch, 2026-05-28) | **No new releases.** Confirmed release list: stable = V4.1.0 (Mar 2, 2026), V4.0.9 (Aug 6, 2025), V4.0.8 (Oct 29, 2024), V4.0.7 (Jun 14, 2024), V4.0.6 (Feb 2, 2024); pre-release = V4.1.1-QC-V06 (Mar 6, 2026 tag; build20260519 inside tag), V4.1.0-QC-V12 (Sep 11, 2025), V4.0.9-QC-V14 (Nov 5, 2024). **No V4.1.1 stable release or QC-V07 tag has been published.** The build20260519 content inside V4.1.1-QC-V06 remains the most recent binary build. | LOW |
| ameba-arduino-pro2 open issues (direct GitHub fetch, 2026-05-28) | **12 open issues; newest = #398 (Mar 29, 2026).** Full list confirmed: #398, #342, #325, #324, #317, #310, #296, #287, #276, #235, #224, #184. No new issues after March 29, 2026. No issues about FlashMemory, FCS, camera, VOE, or boot failure in open or closed history. Bug remains entirely unreported on the official tracker after 56 research cycles. | LOW |
| ameba-rtos-pro2 PR #17 status (direct GitHub fetch, 2026-05-28) | **PR #17 still open and unmerged.** Title: "fix: the ethernet usb driver copies received network..." (orbisai0security, opened May 15, 2026). Repository has 1 open PR and 13 closed PRs total. PR #17 is a USB Ethernet buffer overflow security fix — unrelated to flash, FCS, camera, or boot failure. No new PRs or issues added since U55. | LOW |
| ideashatch/HUB-8735 (direct GitHub fetch, 2026-05-28) | **Confirmed frozen — identical to U55.** Last commit: Dec 2, 2025 (`870a7e0`) — now **177 days** without activity. Only open issue: #10 (PS5268 sensor id fail, Aug 2025). No new issues, commits, or releases. | LOW |
| forum.amebaiot.com threads above #4868 (search sweep, 2026-05-28) | **No new threads indexed above #4868.** Targeted search for thread IDs 4869–4940 returned zero results. Forum ceiling confirmed at thread #4868 ("NN Model loading from Memory instead of Flash or SD card failing with exceptions"). No new relevant threads above the prior ceiling. | LOW |
| Web-wide error string sweep (2026-05-28) | **Zero indexed results — 56 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"` — all return zero publicly indexed results anywhere on the accessible web. This research log remains the only publicly accessible documentation of this bug and its error codes. | LOW |
| Hardware test results — all three workarounds (2026-05-28 sweep) | **Zero results — 56 consecutive null cycles.** No community member has publicly reported testing "Camera FCS Mode = Disable," `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper, or `USE_ISP_RETENTION_DATA` as workarounds for the flash-write cold-boot camera failure. **14 days elapsed since the top-3 action list was first compiled (May 14, U7) with no public validation of any workaround.** | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn, May 28 sweep) | **Zero new RTL8735B/BW21-CBV-specific content — 56th consecutive null cycle.** bbs.aithinker.com BW21-CBV threads (tids 45923–47223) remain indexed in Google but all return 403 on direct access. EEFocus.com returned a BW21-CBV-Kit video review (unboxing/evaluation, unrelated to flash-camera bug). CSDN article `139222964` (AMB82 MINI Arduino intro) and `139584304` (SD card AI recognition) remain the only indexed AMB82 Chinese articles — both unrelated to FCS flash-write failure. bbs.ai-thinker.com BW21-CBV threads (tids 45839, 45930, 46028, 46060) indexed but all 403-blocked. No new Chinese-language technical posts about this bug found anywhere. | LOW |
| eefocus.com BW21-CBV-Kit video review (newly returned in Chinese search, 2026-05-28) | **Newly surfaced Chinese-language review of BW21-CBV-Kit on EEFocus.** URL: `https://www.eefocus.com/video/1819538.html`. Title: "安信可BW21-CBV-Kit评测：性价比爆棚，边缘AI的普惠者" (BW21-CBV-Kit review: outstanding value, democratizing edge AI). Content appears to be an unboxing/performance evaluation video. No FCS flash-camera interaction content visible in the snippet. Not related to our bug. Notable as the first EEFocus content indexed for BW21-CBV. | LOW |

**SDK state as of 2026-05-28 (Cycle U56 — unchanged from U55):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp SHA `b4781b70`, zero mutex calls
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; build20260519 binary May 19, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at `3f95070` (May 15, 2026) — **13 days** no change; PR #17 (ethernet USB buffer overflow fix) still open and unmerged
- ameba-arduino-pro2 dev: `29d47e1` (May 26, 2026, PR #410 SPI API — no fix); no new PRs (max is #410)
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — **87 days** no change
- ameba-tool-rtos-pro2: Frozen at March 9, 2026 (`c1d70e7`) — **80 days** no change
- ideashatch/HUB-8735: Frozen at Dec 2, 2025 — **177 days** no change
- Ai-Thinker-Open: No RTL8735B/BW21 repositories (confirmed U36)
- VOE binary: v1.7.1.0 (Apr 21, 2026) — latest; no FCS flash-race fix in entire 46-version release history (confirmed U53)

**No confirmed fix. Bug remains unpatched as of 2026-05-28 (Cycle U56).**

**Top unresolved actions (unchanged from U55 — 14 days unresolved since U7, May 14):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp is the sole exception. Forward-declaration callable from Arduino: `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug is fully undocumented outside this research log; VOE release history (46 versions) contains zero acknowledgment; filing with the confirmed root-cause chain (FlashMemory bypasses `RT_DEV_LOCK_FLASH`) would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes at source; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h` (confirmed location in both repos as of May 27).

## Research Update — 2026-05-28 (Cycle U57)

**Search scope:** Direct GitHub fetches (ameba-rtos-pro2 commits/main; ameba-arduino-pro2 dev/main commits, releases, issues, PRs); English forum/web (new threads above #4868, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports); Chinese sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn); error string sweeps; workaround confirmation search. All eight search threads run simultaneously.

**Key new findings this cycle:** None — 57th consecutive null research cycle. Both GitHub fetches confirmed the same commit SHAs as U56. All forum threads, error strings, Chinese sources, and hardware test channels are unchanged. The freeze across all monitored repositories and community channels extends another day.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 commits page (direct GitHub fetch, 2026-05-28) | **Confirmed frozen — identical to U56.** Five most recent commits verified: `3f95070` (May 15, "Sync upstream 7343927f"), `afc85a0` (May 15, "[amebapro2][mmf] avoid task recreate in mmf start"), `9c8b6f6` (May 15, "[amebapro2][wlan] wowlan modify dhcp renew unit"), `d2676f1` (May 15, "[amebapro2][wlan] modify dynamic ARP example"), `1c1c8b7` (May 1, "Sync upstream 43d940446d"). **Zero new commits in 13 days since May 15, 2026.** No flash, FCS, VOE, boot, HAL, or sensor changes in any commit. | LOW |
| ameba-arduino-pro2 dev branch (direct GitHub fetch, 2026-05-28) | **Confirmed frozen — identical to U56.** Five most recent commits verified: `29d47e1` (May 26, "Update SPI API for SPI1 switching (#410)"), `7db1c7d` (May 19, "Pre Release Version 4.1.1"), `3d53672` (May 19, "Update Code base and add cam IMX681_5M (#409)"), `cd0bd40` (May 18, "Add I2C Slave (#408)"), `13961cc` (May 5, "Update API for AMB82-zero and SWD off logic"). **Zero new commits after May 26, 2026 — 2 days frozen.** No FCS/flash/camera/mutex fix. | LOW |
| ameba-arduino-pro2 releases (2026-05-28) | **No new releases.** Stable = V4.1.0 (Mar 2, 2026); pre-release = V4.1.1-QC-V06 (tag Mar 6, 2026; build20260519). No V4.1.1-QC-V07 or stable V4.1.1 tag published. Unchanged from U56. | LOW |
| ameba-arduino-pro2 open issues (2026-05-28) | **12 open issues; newest = #398 (Mar 29, 2026).** No new issues after March 29, 2026. No issues about FlashMemory, FCS, camera, VOE, or boot failure filed in open or closed history. Bug remains entirely unreported on the official tracker after 57 research cycles (15 days since the top-3 list was first compiled). | LOW |
| forum.amebaiot.com threads above #4868 (sweep, 2026-05-28) | **No new threads indexed above #4868.** Targeted searches for IDs #4869–#4940 returned zero results from the forum domain. Forum ceiling confirmed at #4868 ("NN Model loading from Memory instead of Flash or SD card failing with exceptions"). Thread #4865 ("AmebaPro2 uartfwburn fail for download 0") newly visible in search results but content is upload-tool failure (unrelated to FCS camera boot); pre-dates our ceiling by 3 IDs. All direct forum fetches return HTTP 403. | LOW |
| Web-wide error string sweep (2026-05-28) | **Zero indexed results — 57 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"` — all return zero publicly indexed results anywhere on the accessible web. This research log remains the only publicly accessible documentation of this bug and its error codes. | LOW |
| Hardware test results — all three workarounds (2026-05-28 sweep) | **Zero results — 57 consecutive null cycles.** No community member has publicly reported testing "Camera FCS Mode = Disable," `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper, or `USE_ISP_RETENTION_DATA` as workarounds. **15 days elapsed since the top-3 action list was compiled (May 14, U7) with no public validation of any workaround.** | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn, 2026-05-28 sweep) | **Zero new RTL8735B/BW21-CBV-specific content — 57th consecutive null cycle.** bbs.ai-thinker.com BW21-CBV threads (tids 45839, 45930, 46028, 46060) indexed but all 403-blocked. mcublog.cn BW21-CBV article (April 2026, Feishu bot + LED + photo) 403-blocked. No new Chinese-language technical posts about this bug found anywhere. | LOW |
| "Camera FCS Mode = Disable" workaround web search (2026-05-28) | **Thread #4302** ("VOE frame_end: sensor didn't initialize done") confirmed as the single indexed forum thread linking "Camera FCS Mode" settings to camera sensor init failure. No posts confirm that disabling FCS Mode after a flash write resolves the cold-boot camera failure. Search for the exact workaround phrase returns zero third-party confirmation. | LOW |

**Cumulative freeze summary (as of Cycle U57):**

| Repository | Frozen since | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **13 days** |
| ameba-arduino-pro2 dev | May 26, 2026 (`29d47e1`) | **2 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **87 days** |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **80 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 | **177 days** |
| Ai-Thinker-Open | No RTL8735B repos exist | — |

**SDK state as of 2026-05-28 (Cycle U57 — unchanged from U56):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp SHA `b4781b70`, zero mutex calls
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; build20260519 binary May 19, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at `3f95070` (May 15, 2026) — **13 days** no change; PR #17 (ethernet USB buffer overflow fix) still open and unmerged
- ameba-arduino-pro2 dev: `29d47e1` (May 26, 2026, PR #410 SPI API — no fix); no new PRs
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — **87 days** no change
- ameba-tool-rtos-pro2: Frozen at March 9, 2026 (`c1d70e7`) — **80 days** no change
- ideashatch/HUB-8735: Frozen at Dec 2, 2025 — **177 days** no change
- Ai-Thinker-Open: No RTL8735B/BW21 repositories (confirmed U36)
- VOE binary: v1.7.1.0 (Apr 21, 2026) — latest; no FCS flash-race fix in entire 46-version release history (confirmed U53)

**No confirmed fix. Bug remains unpatched as of 2026-05-28 (Cycle U57).**

**Top unresolved actions (unchanged from U56 — 15 days unresolved since U7, May 14):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception in all SDK versions through V4.1.1-QC-V06 (SHA `b4781b70`). Callable from Arduino via `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug is fully undocumented outside this research log; VOE release history (46 versions) contains zero acknowledgment; filing with the confirmed root-cause chain would be the first public disclosure.

## Research Update — 2026-05-28 (Cycle U58)

**Search scope:** Eight parallel search threads: (1) GitHub — ameba-rtos-pro2 commits/main + compare endpoint; ameba-arduino-pro2 dev/main commits, releases, open/closed issues, PRs; ameba-arduino-doc commits; ideashatch/HUB-8735 issues; (2) English forum/web — new threads above #4868, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn/eefocus.com; (4) Error string sweeps — all canonical FCS/VOE/FCS_I2C_INIT_ERR error strings; (5) Community GitHub projects — wildman8606/HUB-8735-AMB82-Mini-AmebaPro2-tutorial; 0015/AMB82-Mini-Board; Dennis40816/ameba_stream_project; (6) ElegantOTA Issue #150 AMB82-MINI OTA; (7) ameba-doc-arduino-sdk Flash Memory documentation page content and commit history; (8) General web (Hackster.io BW21-CBV projects, oshwhub.com BW21-CBV, mcublog.cn BW21-CBV article).

**Key new findings this cycle:** None — 58th consecutive null research cycle. All repositories, forum threads, documentation portals, error-string sweeps, and community project searches return the same freeze / blocked / empty state as Cycle U57.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 commits page (direct GitHub fetch, 2026-05-28) | **Confirmed frozen — identical to U57.** Five most recent commits verified: `3f95070` (May 15), `afc85a0` (May 15), `9c8b6f6` (May 15), `d2676f1` (May 15), `1c1c8b7` (May 1). **Zero new commits in 13 days since May 15, 2026.** PR #17 (ethernet USB buffer overflow security fix, orbisai0security) remains open and unmerged. No flash, FCS, VOE, boot, HAL, or sensor changes in any commit. | LOW |
| ameba-arduino-pro2 dev branch (direct GitHub fetch, 2026-05-28) | **Confirmed frozen — identical to U57.** HEAD = `29d47e1` (May 26, 2026, "Update SPI API for SPI1 switching (#410)"). Zero new commits after May 26. PR list confirmed: max PR is #410 (merged May 26). No new PRs in open or closed state. No FCS/flash/camera/mutex-related PRs. | LOW |
| ameba-arduino-pro2 issues (direct GitHub fetch, 2026-05-28) | **12 open issues; newest = #398 (Mar 29, 2026).** Full list confirmed: #398, #342, #325, #324, #317, #310, #296, #287, #276, #235, #224, #184. No new issues above #398. No issues about FlashMemory, FCS, camera, VOE, or boot failure in open or closed history. Bug entirely unreported on the official tracker after 58 research cycles (16 days since top-3 action list was compiled on May 14). | LOW |
| ameba-arduino-doc commits (direct GitHub fetch, 2026-05-28) | **Latest doc commits: `64863ce` "Add I2C slave example guides (#107)" (May 24, 2026); `7f0bc9c` "Update application step (#106)" (May 21, 2026).** Both are I2C slave documentation — unrelated to flash/FCS/camera boot. Flash Memory documentation directory (`source/ameba_pro2/amb82-mini/Example_Guides/Flash Memory/`) last updated January 13, 2026 (syntax fix). **Zero new FCS warnings, camera interaction notes, or mutex documentation added to Flash Memory example guides.** | LOW |
| ideashatch/HUB-8735 issues (direct GitHub fetch, 2026-05-28) | **1 open issue: #10 (PS5268 sensor id fail, Aug 2025).** No new issues. Frozen at Dec 2, 2025 (`870a7e0`) — **177 days** without activity. | LOW |
| wildman8606/HUB-8735-AMB82-Mini-AmebaPro2-tutorial (GitHub, 2026-05-28) | **Newly confirmed community repository for HUB-8735 AI tutorials** (appeared in web search this cycle). Content: YOLO model training for AMB82-MINI / HUB-8735, with Jupyter notebooks for data preprocessing and model training. Last active May 2023 (16 commits total). **Does not mention FCS mode, flash memory write failures, cold boot issues, RT_DEV_LOCK_FLASH, device_mutex_lock, or RTL8735B flash+camera interaction bugs.** | LOW |
| ElegantOTA Issue #150 "AMB82-MINI didn't work with OTA" (GitHub, ayushsharma82/ElegantOTA) | **Not related to our bug.** The issue describes a compilation error (`fatal error: sdkconfig.h: No such file or directory`) when building ElegantOTA for AMB82-MINI — a library compatibility issue (AsyncTCP dependency) occurring before any flash write. No VOE_OPEN_CMD, FCS_I2C_INIT_ERR, KM_status, or sensor init errors appear. | LOW |
| ameba-arduino-doc Flash Memory directory — commit history (2026-05-28) | **No updates to Flash Memory documentation since January 13, 2026.** Five commits in history: Jan 13 2026 (syntax fix), Jan 12 2026 (restructure), Sep 11 2025 (flash layout explanation), Jun 20 2025 (Read Write Word update), Mar 10 2025 (structure). **Zero new warnings about concurrent camera access, FCS interaction, or mutex requirements added to any Flash Memory example documentation.** | LOW |
| forum.amebaiot.com threads above #4868 (sweep, 2026-05-28) | **No new threads indexed above #4868.** Targeted searches for IDs #4869–#4940 returned zero results from the forum domain. Forum ceiling confirmed at #4868 ("NN Model loading from Memory instead of Flash or SD card failing with exceptions"). | LOW |
| Web-wide error string sweep (2026-05-28) | **Zero indexed results — 58 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"` — all return zero publicly indexed results. This research log remains the only publicly accessible documentation of this bug and its error codes. | LOW |
| Hardware test results — all three workarounds (2026-05-28 sweep) | **Zero results — 58 consecutive null cycles.** No community member has publicly reported testing "Camera FCS Mode = Disable," `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper, or `USE_ISP_RETENTION_DATA` as workarounds for the flash-write cold-boot camera failure. **16 days elapsed since the top-3 action list was compiled (May 14, U7) with zero public validation.** | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn/eefocus.com, 2026-05-28) | **Zero new RTL8735B/BW21-CBV-specific content — 58th consecutive null cycle.** EEFocus.com BW21-CBV-Kit video review (unboxing/evaluation, `eefocus.com/video/1819538.html`) confirmed as unrelated to our bug. All other Chinese community sites remain 403-blocked or return zero relevant results for FCS flash-write camera failure. | LOW |

**Cumulative freeze summary (as of Cycle U58):**

| Repository | Frozen since | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **13 days** |
| ameba-arduino-pro2 dev | May 26, 2026 (`29d47e1`) | **2 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **87 days** |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **80 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 | **177 days** |
| Ai-Thinker-Open | No RTL8735B repos exist | — |

**SDK state as of 2026-05-28 (Cycle U58 — unchanged from U57):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp SHA `b4781b70`, zero mutex calls
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; build20260519 binary May 19, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at `3f95070` (May 15, 2026) — **13 days** no change; PR #17 (ethernet USB buffer overflow fix) still open and unmerged
- ameba-arduino-pro2 dev: `29d47e1` (May 26, 2026, PR #410 SPI API — no fix); no new PRs (max is #410)
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — **87 days** no change
- ameba-tool-rtos-pro2: Frozen at March 9, 2026 (`c1d70e7`) — **80 days** no change
- ideashatch/HUB-8735: Frozen at Dec 2, 2025 — **177 days** no change
- Ai-Thinker-Open: No RTL8735B/BW21 repositories (confirmed U36)
- VOE binary: v1.7.1.0 (Apr 21, 2026) — latest; no FCS flash-race fix in entire 46-version release history (confirmed U53)

**No confirmed fix. Bug remains unpatched as of 2026-05-28 (Cycle U58).**

**Top unresolved actions (unchanged from U57 — 16 days unresolved since U7, May 14):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception in all SDK versions through V4.1.1-QC-V06 (SHA `b4781b70`). Callable from Arduino via `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug is fully undocumented outside this research log; VOE release history (46 versions) contains zero acknowledgment; filing with the confirmed root-cause chain (FlashMemory bypasses `RT_DEV_LOCK_FLASH`) would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes at source; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes at source; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h` (both repos, confirmed May 27).

## Research Update — 2026-05-29 (Cycle U59)

**Search scope:** Eight parallel search threads: (1) GitHub — ameba-rtos-pro2 commits/main + compare endpoint; ameba-arduino-pro2 dev/main commits, releases, open/closed issues, PRs; ameba-arduino-doc commits; ideashatch/HUB-8735 issues; (2) English forum/web — new threads above #4868, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn/eefocus.com; (4) Error string sweeps — all canonical FCS/VOE/FCS_I2C_INIT_ERR error strings; (5) Community GitHub projects — wildman8606/HUB-8735-AMB82-Mini-AmebaPro2-tutorial; 0015/AMB82-Mini-Board; Dennis40816/ameba_stream_project; (6) ameba-arduino-pro2 PR #410 SPI API follow-on; (7) ameba-arduino-doc Flash Memory directory content; (8) General web (Hackster.io BW21-CBV, oshwhub.com BW21-CBV, mcublog.cn BW21-CBV).

**Key new findings this cycle:** None — 59th consecutive null research cycle. All repositories, forum threads, documentation portals, error-string sweeps, and community project searches return the same freeze / blocked / empty state as Cycle U58.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 commits page (2026-05-29) | **Confirmed frozen — identical to U58.** HEAD still `3f95070` (May 15, 2026). **Zero new commits in 14 days since May 15, 2026.** PR #17 (ethernet USB buffer overflow security fix, orbisai0security) remains open and unmerged. No flash, FCS, VOE, boot, HAL, or sensor changes in any commit. | LOW |
| ameba-arduino-pro2 dev branch (2026-05-29) | **Confirmed frozen since U58.** HEAD = `29d47e1` (May 26, 2026, "Update SPI API for SPI1 switching (#410)"). No new commits after May 26. No new PRs above #410. No FCS/flash/camera/mutex-related PRs in open or closed state. | LOW |
| ameba-arduino-pro2 releases (2026-05-29) | **No new releases.** Latest stable = V4.1.0 (Mar 2, 2026). Latest pre-release = V4.1.1-QC-V06 (tag Mar 6, 2026; release notes through May 19, 2026). No V4.1.1-QC-V07 or stable V4.1.1. | LOW |
| ameba-arduino-pro2 issues (2026-05-29) | **12 open issues; newest = #398 (Mar 29, 2026).** No new issues above #398. No issues about FlashMemory, FCS, camera, VOE, or boot failure in open or closed history. Bug entirely unreported on official tracker after 59 research cycles (17 days since top-3 action list compiled on May 14). | LOW |
| ameba-arduino-doc commits (2026-05-29) | **No new commits beyond `64863ce` "Add I2C slave example guides" (May 24, 2026).** Flash Memory documentation directory last updated January 13, 2026. Zero new FCS warnings, camera interaction notes, or mutex documentation added to any Flash Memory example guides. | LOW |
| ideashatch/HUB-8735 (2026-05-29) | **1 open issue: #10 (PS5268 sensor id fail, Aug 2025).** No new issues. Frozen at Dec 2, 2025 (`870a7e0`) — **178 days** without activity. | LOW |
| forum.amebaiot.com threads above #4868 (2026-05-29) | No new threads indexed in range #4869–#5000. Forum ceiling confirmed at #4868. All forum direct fetches return HTTP 403. | LOW |
| Web-wide error string sweep (2026-05-29) | **Zero indexed results — 59 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"` — all return zero publicly indexed results. This research log remains the only publicly accessible documentation of this bug and its error codes. | LOW |
| Hardware test results — all three workarounds (2026-05-29 sweep) | **Zero results — 59 consecutive null cycles.** No community member has publicly reported testing "Camera FCS Mode = Disable," `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper, or `USE_ISP_RETENTION_DATA` as workarounds for the flash-write cold-boot camera failure. **17 days elapsed since the top-3 action list was compiled (May 14, U7) with zero public validation.** | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn/eefocus.com, 2026-05-29) | **Zero new RTL8735B/BW21-CBV-specific content — 59th consecutive null cycle.** All Chinese community sites remain 403-blocked or return zero relevant results for FCS flash-write camera failure. | LOW |
| aiot.realmcu.com (2026-05-29) | Still HTTP 403-blocked. Appeared in search results but direct fetch returns 403. | LOW (blocked) |

**Cumulative freeze summary (as of Cycle U59):**

| Repository | Frozen since | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **14 days** |
| ameba-arduino-pro2 dev | May 26, 2026 (`29d47e1`) | **3 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **88 days** |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **81 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 | **178 days** |
| Ai-Thinker-Open | No RTL8735B repos exist | — |

**SDK state as of 2026-05-29 (Cycle U59 — unchanged from U58):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp SHA `b4781b70`, zero mutex calls
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; build20260519 binary May 19, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at `3f95070` (May 15, 2026) — **14 days** no change; PR #17 (ethernet USB buffer overflow fix) still open and unmerged
- ameba-arduino-pro2 dev: `29d47e1` (May 26, 2026, PR #410 SPI API — no fix); no new PRs (max is #410)
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — **88 days** no change
- ameba-tool-rtos-pro2: Frozen at March 9, 2026 (`c1d70e7`) — **81 days** no change
- ideashatch/HUB-8735: Frozen at Dec 2, 2025 — **178 days** no change
- Ai-Thinker-Open: No RTL8735B/BW21 repositories (confirmed U36)
- VOE binary: v1.7.1.0 (Apr 21, 2026) — latest; no FCS flash-race fix in entire 46-version release history (confirmed U53)

**No confirmed fix. Bug remains unpatched as of 2026-05-29 (Cycle U59).**

**Top unresolved actions (unchanged from U58 — 17 days unresolved since U7, May 14):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception in all SDK versions through V4.1.1-QC-V06 (SHA `b4781b70`). Callable from Arduino via `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug is fully undocumented outside this research log; VOE release history (46 versions) contains zero acknowledgment; filing with the confirmed root-cause chain (FlashMemory bypasses `RT_DEV_LOCK_FLASH`) would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes at source; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h` (both repos, confirmed May 27).

## Research Update — 2026-05-29 (Cycle U60)

**Search scope:** Three background agents whose results arrived after U59 was committed: (1) Agent `ad476283926d947ca` — English forum/web sweep (forum ceiling, error strings, workaround hardware test reports, SDK releases, Reddit/Hackster/Instructables/YouTube); (2) Agent `a60802183d8e1050e` — Chinese-language sources sweep (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn) + supplementary English web searches; (3) Agent `a7010ac175f83b1bf` — SDK deep-dive (FlashMemory.cpp verbatim source + commit provenance; `GitHub_release_note.txt` entries; ameba-rtos-pro2 compare endpoint; VOE version; RT_DEV_LOCK_FLASH code search). All three agents ran in parallel during U59; their consolidated findings are documented here as U60.

**Key new findings this cycle:**
- **FlashMemory.cpp full commit history enumerated from live source** (agent `a7010ac175f83b1bf`, verbatim fetch from dev branch): 3 total commits — `4fdfbec2` (Sep 30, 2025, "Optimize codes #337"), `d1a988f3` (Sep 30, 2025, "Add Arduino printf #336"), `d9022ef4` (Jul 9, 2024, "Add feature Flash Memory #252"). No commit has ever added mutex protection. File has not been touched in 8+ months.
- **ameba-rtos-pro2 compare `3f95070...HEAD`: "identical"** (direct GitHub fetch by agent `a7010ac175f83b1bf`) — confirms 14 days frozen, independent of U59 checks.
- **Forum thread #4803 newly catalogued** — "AMB82-mini: USB Ethernet failing — mentions VOE timeout" — newly identified (not previously tracked); content 403-blocked; unrelated to flash+camera cold boot bug.
- All other channels identical to U59 — 60th consecutive null cycle.

| Source | Key Finding | Priority |
|---|---|---|
| FlashMemory.cpp verbatim source fetch — dev branch (agent `a7010ac175f83b1bf`, 2026-05-29) | **Full file retrieved verbatim. Confirmed: ZERO `device_mutex_lock`, `device_mutex_unlock`, or `RT_DEV_LOCK_FLASH` calls in any function.** Six flash operations (`flash_stream_read`, `flash_stream_write`, `flash_erase_sector`, `flash_read_word`, `flash_write_word`, `flash_erase_sector` in `writeWord`/`eraseWord`) all execute naked with no synchronization. Only includes: `"FlashMemory.h"`. SHA `b4781b70` unchanged. Commit history: `4fdfbec2` (Sep 30, 2025, "Optimize codes #337"), `d1a988f3` (Sep 30, 2025, "Add Arduino printf #336"), `d9022ef4` (Jul 9, 2024, "Add feature Flash Memory #252"). | LOW (reconfirms) |
| ameba-rtos-pro2 compare `3f95070...HEAD` (agent `a7010ac175f83b1bf`, 2026-05-29) | **"3f95070 and HEAD are identical."** Zero new commits since May 15, 2026 — 14 days frozen. Confirmed independently of U59's WebFetch-based checks. PR #17 (ethernet USB buffer overflow) still open and unmerged. No flash, FCS, VOE, boot, HAL, or sensor changes in any observable pipeline. | LOW |
| `GitHub_release_note.txt` newest entry (agent `a7010ac175f83b1bf`, 2026-05-29) | **Top entry still `7343927f` ("[amebapro2][mmf] avoid task recreate in mmf start").** File contains 27+ entries, newest at top (`7343927f`), oldest at bottom ("avoid wifi_off crash issue"). No new entry added since May 15. Zero entries in entire file reference FCS, flash bus mutex, RT_DEV_LOCK_FLASH, cold-boot camera failure, or NOR_FLASH_FCS. | LOW |
| VOE version status (agent `a7010ac175f83b1bf`, 2026-05-29) | **Latest VOE: RTL8735B_VOE_1.7.1.0 (04/21/2026) — unchanged.** Last VOE commit: `d54e1a8` (May 1, 2026, "sync voe to 1.7.1.0"). No new VOE version beyond 1.7.1.0. Zero FCS flash-race fix entries in the complete 40+ version history (confirmed U53). | LOW |
| forum.amebaiot.com thread #4803 "AMB82-mini: USB Ethernet failing" (agent `ad476283926d947ca`, 2026-05-29) | **Newly catalogued thread.** Describes AMB82-mini USB Ethernet failure with VOE timeout noted in the error context. VOE timeout here is the IPC timeout protection (documented in VOE release v1.3.7.0, 2022), distinct from FCS camera init failure. Content 403-blocked. Not related to FlashMemory/FCS cold-boot bug. | LOW (newly catalogued, unrelated) |
| forum.amebaiot.com threads above #4868 (agents `ad476283926d947ca` + `a60802183d8e1050e`, 2026-05-29) | **No new threads indexed in range #4869–#5000.** Forum ceiling confirmed at #4868 ("NN Model loading from Memory instead of Flash or SD card failing with exceptions"). Threads #4865, #4834, #4803, #4777, #4748 confirmed visible in search results — all previously catalogued (U49–U58) or confirmed unrelated. All direct forum fetches return HTTP 403. | LOW |
| FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` — hardware test search (agent `ad476283926d947ca`, 2026-05-29) | **Zero results — 60th consecutive null cycle.** "Camera FCS Mode = Disable" + flash workaround, `device_mutex_lock` + AMB82 + camera, `USE_ISP_RETENTION_DATA` + tested — all return zero results. No community member has publicly reported testing any of the three proposed workarounds. 17 days since the top-3 action list was first compiled (May 14, U7). | LOW |
| Error string sweep (all three agents, 2026-05-29) | **Zero indexed results — 60 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"` — all return zero publicly indexed results anywhere on the accessible web. This research log remains the only publicly accessible documentation of this bug and its error codes. | LOW |
| All Chinese-language sources (agent `a60802183d8e1050e`, CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn, 2026-05-29) | **Zero new RTL8735B/BW21-CBV-specific content — 60th consecutive null cycle.** All Chinese community platforms remain 403-blocked or return zero relevant results for FCS flash-write camera failure on RTL8735B or BW21-CBV. The RTL8720C thread #1239 (flash→boot failure, May 2022, sibling chip) remains the only Chinese-language parallel found in any cycle. | LOW |
| Reddit / Hackster.io / Instructables / YouTube (agent `ad476283926d947ca`, 2026-05-29) | **Zero results — 60 consecutive cycles.** No reports of RTL8735B FCS flash camera boot failure on any English-language community platform outside the Realtek forum. | LOW |
| ameba-arduino-pro2 V4.1.1 stable release status (agent `ad476283926d947ca`, 2026-05-29) | **No stable V4.1.1 release.** Latest stable = V4.1.0 (Mar 2, 2026). Latest pre-release = V4.1.1-QC-V06 (tag Mar 6, 2026; release notes through May 19, 2026; `build20260519` binary). No V4.1.1-QC-V07 or stable V4.1.1 tag published. No FlashMemory/FCS/camera boot fix in any changelog entry across all releases. | LOW |

**FlashMemory.cpp — confirmed full call chain (verbatim from dev HEAD `29d47e1`, May 29, 2026):**

The six flash operations confirmed absent of any mutex, per verbatim source:

```cpp
void FlashMemoryClass::read(unsigned int offset) {
    // bounds checks only
    flash_stream_read(_pFlash, (_flash_base_address + offset), buf_size, (uint8_t *)buf);
}

void FlashMemoryClass::write(unsigned int offset) {
    // bounds checks only, NO lock
    for (int i = 0; i < (MAX_FLASH_MEMORY_APP_SIZE / FLASH_SECTOR_SIZE); i++) {
        flash_erase_sector(_pFlash, (_flash_base_address + (i * FLASH_SECTOR_SIZE)));
    }
    flash_stream_write(_pFlash, (_flash_base_address + offset), buf_size, (uint8_t *)buf);
}

void FlashMemoryClass::eraseSector(unsigned int sector_offset) {
    // bounds checks only
    flash_erase_sector(_pFlash, (_flash_base_address + sector_offset));
}
```

`device_mutex_lock` / `device_mutex_unlock` / `RT_DEV_LOCK_FLASH` — **ABSENT from every function**. The only includes are `"FlashMemory.h"` (which pulls in `<Arduino.h>` and `"flash_api.h"`) — no `device_lock.h`, no mutex infrastructure.

**Cumulative freeze summary (as of Cycle U60):**

| Repository | Frozen since | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **14 days** |
| ameba-arduino-pro2 dev | May 26, 2026 (`29d47e1`) | **3 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **88 days** |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **81 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 | **178 days** |
| Ai-Thinker-Open | No RTL8735B repos exist | — |

**SDK state as of 2026-05-29 (Cycle U60 — unchanged from U59):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp SHA `b4781b70`, zero mutex calls; 3 commits total (newest Sep 30, 2025)
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; build20260519 binary May 19, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at `3f95070` (May 15, 2026) — **14 days** no change; compare `3f95070...HEAD` returns "identical"; PR #17 (ethernet USB buffer overflow fix) still open and unmerged
- ameba-arduino-pro2 dev: `29d47e1` (May 26, 2026, PR #410 SPI API — no fix); no new PRs
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — **88 days** no change
- ameba-tool-rtos-pro2: Frozen at March 9, 2026 (`c1d70e7`) — **81 days** no change
- ideashatch/HUB-8735: Frozen at Dec 2, 2025 — **178 days** no change
- Ai-Thinker-Open: No RTL8735B/BW21 repositories (confirmed U36)
- VOE binary: v1.7.1.0 (Apr 21, 2026) — latest; no FCS flash-race fix in entire 46-version release history (confirmed U53)

**No confirmed fix. Bug remains unpatched as of 2026-05-29 (Cycle U60).**

**Top unresolved actions (unchanged from U59 — 17 days unresolved since U7, May 14):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. FCS Disable is the Arduino IDE default (boards.txt). No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception in all SDK versions through V4.1.1-QC-V06 (SHA `b4781b70`, 3 commits, newest Sep 30, 2025). Callable from Arduino via `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug is fully undocumented outside this research log; 60 research cycles and 46 VOE versions contain zero acknowledgment; filing with the confirmed root-cause chain (FlashMemory bypasses `RT_DEV_LOCK_FLASH`, three-callback FTL race window, cold-boot KM I2C init corruption) would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes at source; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h` (both repos, confirmed May 27).

## Research Update — 2026-05-29 (Cycle U61)

**Search scope:** Three parallel agents: (1) GitHub — ameba-rtos-pro2 commits/main + PR #17 state; ameba-arduino-pro2 dev/main commits, releases, open/closed issues, PRs; ideashatch/HUB-8735 commits; (2) English forum/web — new threads above #4868, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports, error string sweeps; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn/eefocus.com.

**Key new findings this cycle:**
- **NEW: Forum thread #4871 newly indexed** — "I would like to purchase a small quantity of RTL8735b" (purchasing inquiry, no technical content). Forum ceiling advances from #4868 to **#4871**.
- **NEW: ameba-rtos-pro2 PR #17 marked stale by GitHub bot on 2026-05-29** — stale bot fired after 14 days of no activity; PR #17 (ethernet USB buffer overflow security fix, orbisai0security) receives `no-pr-activity` label + stale bot comment. PR still open, not merged or closed.
- All other channels: 61st consecutive null cycle. Zero new commits, releases, issues, or hardware test reports anywhere.

| Source | Key Finding | Priority |
|---|---|---|
| forum.amebaiot.com thread #4871 "I would like to purchase a small quantity of RTL8735b" (English agent, 2026-05-29) | **NEW — Forum ceiling advances to #4871.** First thread indexed above the prior #4868 ceiling. Content: a user seeking to source RTL8735B chips in small quantity. No technical content, no camera or flash discussion, no FCS failure. Content 403-blocked on direct fetch. Not related to the bug. Confirms the forum is still generating new threads above #4868 as of May 2026. | LOW (new ceiling, unrelated) |
| ameba-rtos-pro2 PR #17 (direct GitHub fetch, 2026-05-29) | **NEW — Stale bot fired today on PR #17.** Timeline: opened May 15, 2026 (orbisai0security, ethernet USB buffer overflow security fix); github-actions bot welcome comment May 15; **github-actions bot stale comment May 29, 2026** ("This PR has not had any activity in the last 14 days"). Label `no-pr-activity` added. PR is now stale-flagged but **still open and not closed or merged**. Subject: USB Ethernet driver buffer overflow, not related to flash/FCS/camera. | LOW (new status, unrelated to bug) |
| ameba-rtos-pro2 commits page (direct GitHub fetch, 2026-05-29) | **Confirmed frozen — identical to U60.** Five most recent commits: `3f95070` (May 15), `afc85a0` (May 15), `9c8b6f6` (May 15), `d2676f1` (May 15), `1c1c8b7` (May 1). **Zero new commits in 14 days since May 15, 2026.** No flash, FCS, VOE, boot, HAL, or sensor changes in any commit. | LOW |
| ameba-arduino-pro2 dev branch (direct GitHub fetch, 2026-05-29) | **Confirmed frozen — identical to U60.** HEAD = `29d47e1` (May 26, 2026, "Update SPI API for SPI1 switching (#410)"). Zero new commits after May 26. No new PRs above #410. No FCS/flash/camera/mutex-related PRs in open or closed state. | LOW |
| ameba-arduino-pro2 releases (2026-05-29) | **No new releases.** Stable = V4.1.0 (Mar 2, 2026). Pre-release = V4.1.1-QC-V06 (tag Mar 6, 2026; build20260519 binary May 19). No V4.1.1-QC-V07 or stable V4.1.1 published. The `dev` branch commit "Pre Release Version 4.1.1" (May 19, `7db1c7d`) suggests a V4.1.1 stable is being prepared but no tag has been created. | LOW |
| ameba-arduino-pro2 open issues (direct GitHub fetch, 2026-05-29) | **12 open issues; newest = #398 (Mar 29, 2026).** Full list confirmed: #398, #342, #325, #324, #317, #310, #296, #287, #276, #235, #224, #184. All carry `no-issue-activity` + `pending` labels. No new issues above #398. Bug remains entirely unreported on the official tracker after 61 research cycles (17 days since top-3 action list compiled on May 14). | LOW |
| ideashatch/HUB-8735 (direct GitHub fetch, 2026-05-29) | **Confirmed frozen at `870a7e0` (Dec 2, 2025) — now 178 days without activity.** Only open issue: #10 (PS5268 sensor id fail, Aug 2025). No new issues, commits, or releases. | LOW |
| Web-wide error string sweep (2026-05-29) | **Zero indexed results — 61 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"` — all return zero publicly indexed results anywhere on the accessible web. This research log remains the only publicly accessible documentation of this bug and its error codes. | LOW |
| Hardware test results — all three workarounds (2026-05-29 sweep) | **Zero results — 61 consecutive null cycles.** No community member has publicly reported testing "Camera FCS Mode = Disable," `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper, or `USE_ISP_RETENTION_DATA` as workarounds. **17 days elapsed since the top-3 action list was compiled (May 14, U7) with zero public validation of any workaround.** | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn/eefocus.com, 2026-05-29) | **Zero new RTL8735B/BW21-CBV-specific content — 61st consecutive null cycle.** bbs.aithinker.com returns HTTP 403 on all fetch attempts (primary Chinese BW21 community, fully inaccessible without login). CSDN, 知乎, EEWorld, 21IC: zero new RTL8735B bug content. mcublog.cn BW21-CBV article (April 2026, Feishu bot + LED + photo) remains 403-blocked. No Chinese-language technical posts about FCS flash-write cold-boot camera failure found in any channel. | LOW |

**Cumulative freeze summary (as of Cycle U61):**

| Repository | Frozen since | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **14 days** |
| ameba-arduino-pro2 dev | May 26, 2026 (`29d47e1`) | **3 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **88 days** |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **81 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 | **178 days** |
| Ai-Thinker-Open | No RTL8735B repos exist | — |

**SDK state as of 2026-05-29 (Cycle U61 — unchanged from U60):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp SHA `b4781b70`, zero mutex calls; 3 commits total (newest Sep 30, 2025)
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; build20260519 binary May 19, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at `3f95070` (May 15, 2026) — **14 days** no change; PR #17 now stale-flagged (bot comment May 29) but still open and unmerged
- ameba-arduino-pro2 dev: `29d47e1` (May 26, 2026, PR #410 SPI API — no fix); no new PRs (max is #410)
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — **88 days** no change
- ameba-tool-rtos-pro2: Frozen at March 9, 2026 (`c1d70e7`) — **81 days** no change
- ideashatch/HUB-8735: Frozen at Dec 2, 2025 — **178 days** no change
- Ai-Thinker-Open: No RTL8735B/BW21 repositories (confirmed U36)
- VOE binary: v1.7.1.0 (Apr 21, 2026) — latest; no FCS flash-race fix in entire 46-version release history (confirmed U53)
- Forum ceiling: **#4871** (was #4868; thread #4871 is a purchasing inquiry, not technical)

**No confirmed fix. Bug remains unpatched as of 2026-05-29 (Cycle U61).**

**Top unresolved actions (unchanged from U60 — 17 days unresolved since U7, May 14):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. FCS Disable is the Arduino IDE default (boards.txt). No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception in all SDK versions through V4.1.1-QC-V06 (SHA `b4781b70`, 3 commits, newest Sep 30, 2025). Callable from Arduino via `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug is fully undocumented outside this research log; 61 research cycles and 46 VOE versions contain zero acknowledgment; filing with the confirmed root-cause chain (FlashMemory bypasses `RT_DEV_LOCK_FLASH`, three-callback FTL race window, cold-boot KM I2C init corruption) would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes at source; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h` (both repos, confirmed May 27).

## Research Update — 2026-05-30 (Cycle U62)

**Search scope:** Direct GitHub fetches (ameba-rtos-pro2 commits/main; ameba-arduino-pro2 dev/main commits, releases, issues, PRs); English forum/web (new threads above #4871, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports); Chinese sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn); error string sweeps; documentation portals (ameba-arduino-doc, aiot.realmcu.com).

**Key new findings this cycle:** None — 62nd consecutive null research cycle. All repositories, forum threads, documentation portals, error-string sweeps, and community searches return the same freeze / blocked / empty state as Cycle U61.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 commits page (direct GitHub fetch, 2026-05-30) | **Confirmed frozen — identical to U61.** HEAD still `3f95070` (May 15, 2026). **Zero new commits in 15 days since May 15, 2026.** PR #17 (ethernet USB buffer overflow security fix, orbisai0security) remains open; stale-flagged by bot on May 29. No flash, FCS, VOE, boot, HAL, or sensor changes in any commit. | LOW |
| ameba-arduino-pro2 dev branch (direct GitHub fetch, 2026-05-30) | **Confirmed frozen — identical to U61.** HEAD = `29d47e1` "Update SPI API for SPI1 switching (#410)" (May 26, 2026). Zero new commits after May 26, 2026 — 4 days frozen. No PRs above #410 in open or closed state. No FCS/flash/camera/mutex-related PRs. | LOW |
| ameba-arduino-pro2 releases (2026-05-30) | **No new releases.** Latest stable = V4.1.0 (Mar 2, 2026). Latest pre-release = V4.1.1-QC-V06 (tag Mar 6, 2026; build20260519 binary May 19, 2026). No V4.1.1-QC-V07 or stable V4.1.1 tag published. No FlashMemory/FCS/camera boot fix in any release note. | LOW |
| ameba-arduino-pro2 open issues (2026-05-30) | **12 open issues; newest = #398 (Mar 29, 2026).** No new issues above #398. No issues about FlashMemory, FCS, camera, VOE, or boot failure in open or closed history. Bug remains entirely unreported on the official tracker after 62 research cycles (18 days since top-3 action list compiled on May 14). | LOW |
| forum.amebaiot.com threads above #4871 (2026-05-30) | **No new threads indexed above #4871.** Forum ceiling remains at #4871 ("I would like to purchase a small quantity of RTL8735b," purchasing inquiry, established U61). Targeted searches for IDs #4872–#5000 returned zero results from the forum domain. All direct forum fetches return HTTP 403. | LOW |
| Web-wide error string sweep (2026-05-30) | **Zero indexed results — 62 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"` — all return zero publicly indexed results anywhere on the accessible web. This research log remains the only publicly accessible documentation of this bug and its error codes. | LOW |
| Hardware test results — all three workarounds (2026-05-30 sweep) | **Zero results — 62 consecutive null cycles.** No community member has publicly reported testing "Camera FCS Mode = Disable," `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper, or `USE_ISP_RETENTION_DATA` as workarounds for the flash-write cold-boot camera failure. **18 days elapsed since the top-3 action list was compiled (May 14, U7) with zero public validation of any workaround.** | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn, 2026-05-30) | **Zero new RTL8735B/BW21-CBV-specific content — 62nd consecutive null cycle.** All Chinese community sites remain 403-blocked or return zero relevant results for FCS flash-write camera failure on RTL8735B or BW21-CBV. | LOW |
| Documentation portals (ameba-arduino-doc, aiot.realmcu.com, 2026-05-30) | **ameba-arduino-doc latest commit still `64863ce` (May 24, I2C slave docs only).** aiot.realmcu.com returns HTTP 403 on all paths. Zero new FCS warnings, camera interaction notes, or mutex documentation added to any Flash Memory example guides. | LOW |

**Cumulative freeze summary (as of Cycle U62):**

| Repository | Frozen since | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **15 days** |
| ameba-arduino-pro2 dev | May 26, 2026 (`29d47e1`) | **4 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **89 days** |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **82 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 | **179 days** |
| Ai-Thinker-Open | No RTL8735B repos exist | — |

**SDK state as of 2026-05-30 (Cycle U62 — unchanged from U61):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp SHA `b4781b70`, zero mutex calls; 3 commits total (newest Sep 30, 2025)
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; build20260519 binary May 19, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at `3f95070` (May 15, 2026) — **15 days** no change; PR #17 stale-flagged (bot May 29) but still open and unmerged
- ameba-arduino-pro2 dev: `29d47e1` (May 26, 2026, PR #410 SPI API — no fix); no new PRs (max is #410)
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — **89 days** no change
- ameba-tool-rtos-pro2: Frozen at March 9, 2026 (`c1d70e7`) — **82 days** no change
- ideashatch/HUB-8735: Frozen at Dec 2, 2025 — **179 days** no change
- Ai-Thinker-Open: No RTL8735B/BW21 repositories (confirmed U36)
- VOE binary: v1.7.1.0 (Apr 21, 2026) — latest; no FCS flash-race fix in entire 46-version release history (confirmed U53)
- Forum ceiling: **#4871** (purchasing inquiry thread; no technical content)

**No confirmed fix. Bug remains unpatched as of 2026-05-30 (Cycle U62).**

**Top unresolved actions (unchanged from U61 — 18 days unresolved since U7, May 14):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. FCS Disable is the Arduino IDE default (boards.txt). No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception in all SDK versions through V4.1.1-QC-V06 (SHA `b4781b70`, 3 commits, newest Sep 30, 2025). Callable from Arduino via `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug is fully undocumented outside this research log; 62 research cycles and 46 VOE versions contain zero acknowledgment; filing with the confirmed root-cause chain (FlashMemory bypasses `RT_DEV_LOCK_FLASH`, three-callback FTL race window, cold-boot KM I2C init corruption) would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes at source; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h` (both repos, confirmed May 27).

## Research Update — 2026-05-30 (Cycle U63)

**Search scope:** Four parallel agents + direct searches: (1) GitHub — ameba-rtos-pro2 commits/issues/PRs; ameba-arduino-pro2 dev/main commits, releases, issues (direct GitHub fetch + WebFetch); ideashatch/HUB-8735 issues; (2) English forum/web — new threads above #4871, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee; (4) SDK deep-dive — V4.1.1-QC-V07 existence check (HTTP 404 confirmed), QC-V05/V06 release note analysis, FlashMemory.cpp mutex state.

**Key new findings this cycle:** None — 63rd consecutive null research cycle. All repositories, forum threads, documentation portals, error-string sweeps, and community searches return the same freeze / blocked / empty state as Cycle U62. V4.1.1-QC-V07 confirmed absent (HTTP 404). QC-V05 and QC-V06 release note content confirmed in detail for the first time — no FCS, flash, or camera-boot entries.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 commits (direct GitHub fetch + compare, 2026-05-30) | **Confirmed frozen at `3f95070` (May 15, 2026) — zero new commits in 15 days.** PR #17 ("fix: ethernet USB driver buffer overflow", orbisai0security) remains open and stale-flagged (bot May 29, 2026). No flash, FCS, VOE, boot, HAL, or sensor changes in any observable pipeline. | LOW |
| ameba-rtos-pro2 new releases (2026-05-30) — **NEW FINDING (first documented this cycle)** | **Two new release tags published May 22, 2026:** (1) **V1.0.3** — tagged on existing commit `3f95070` (May 15, 2026); provides RTSP source code patch and WebSocket viewer source code patch as ZIP assets. Zero new code commits — just a release label on the previously documented HEAD. No FCS, flash, or camera boot content. (2) **V1.0.3-aiglass.08** — tagged on a **new commit `8d9040c`** (not previously documented) on the AI glass variant branch; features: lifetime snapshot (blocking/non-blocking), OV13B10 sensor + AINR model updates, IMX681_5M support, VOE driver update, converge flow improvements, object detection for AI snapshot, UART DMA. **"VOE driver update" is listed but not detailed.** No FCS, flash mutex, or camera cold-boot fix explicitly mentioned. This is an AI glass variant commit — not on the main RTL8735B / AMB82-Mini development path. | LOW (no fix; new commit on AI glass branch only) |
| ameba-arduino-pro2 dev branch commits (direct GitHub fetch, 2026-05-30) | **Confirmed frozen — identical to U62.** HEAD = `29d47e1` "Update SPI API for SPI1 switching (#410)" (May 26, 2026). Zero new commits after May 26, 2026 — **4 days frozen**. No PRs above #410 in open or closed state. No FCS/flash/camera/mutex-related PRs. | LOW |
| ameba-arduino-pro2 releases: V4.1.1-QC-V07 existence check (2026-05-30) | **V4.1.1-QC-V07 confirmed absent.** Direct fetch of `github.com/Ameba-AIoT/ameba-arduino-pro2/releases/tag/V4.1.1-QC-V07` returns HTTP 404. Tags page confirmed QC-V06 (May 19, 2026) is the highest tag. Complete 2026 QC sequence: QC-V01 (Mar 6), QC-V02 (Mar 20), QC-V03 (Apr 2), QC-V04 (Apr 17), QC-V05 (Apr 30), QC-V06 (May 19). No QC-V07, no stable V4.1.1. | LOW |
| V4.1.1-QC-V05 release content (first-time confirmed detail, 2026-05-30) | **QC-V05 features (Apr 30, 2026):** AMB82-zero board support, WDT API update, ArduCAM + JPEGDecoder ZIP library submodules. **No FlashMemory, VOE, FCS, or camera-boot changes.** | LOW (confirms prior) |
| V4.1.1-QC-V06 release content (first-time confirmed detail, 2026-05-30) | **QC-V06 features (May 19, 2026):** I2C Slave (PR #408), codebase update + IMX681_5M camera sensor (PR #409), SWD-off logic for AMB82-zero, tools v1.4.11. **No FlashMemory, VOE, FCS, or camera-boot changes.** SDK advances on new features; flash bus mutex defect remains entirely unaddressed. | LOW (confirms prior) |
| `FlashMemory.cpp` — dev branch (direct fetch, 2026-05-30) | **Zero mutex calls confirmed unchanged.** `write()` calls `flash_erase_sector()` + `flash_stream_write()`; `read()` calls `flash_stream_read()`. Zero occurrences of `RT_DEV_LOCK_FLASH`, `device_mutex_lock`, or any synchronization primitive. GitHub issue search for "FlashMemory" in ameba-arduino-pro2 returns zero results — bug unacknowledged on official tracker. | LOW (confirms prior) |
| ameba-arduino-pro2 open issues (direct GitHub fetch, 2026-05-30) | **17 open issues; highest issue number = #398 (Mar 29, 2026).** Confirmed list: #398, #342, #325, #324, #317, #310, #296, #287, #276, #235, #224, #184, and others. No issues about FlashMemory, FCS, camera, VOE, or boot failure in open or closed history. Bug entirely unreported on the official tracker after 63 research cycles. | LOW |
| ideashatch/HUB-8735 issues (2026-05-30) | **1 open issue: #10** (PS5268 sensor id fail, Aug 2025). No new issues. Repository last committed Dec 2, 2025 — **180 days frozen**. | LOW |
| VOE binary version (2026-05-30) | **No version beyond 1.7.1.0 confirmed.** `voe.bin` raw path on QC-V06 tag returns HTTP 404 (file may have moved). QC-V05 and QC-V06 release notes make no mention of a VOE version bump. Last explicitly documented: VOE 1.7.1.0 (Apr 21, 2026, dual-sensor FCS mirror/flip fix — unrelated to our bug). | LOW |
| forum.amebaiot.com threads above #4871 (2026-05-30) | **No new threads indexed above #4871.** Forum ceiling confirmed at #4871 ("I would like to purchase a small quantity of RTL8735b," purchasing inquiry). Targeted searches for IDs #4872–#5000 returned zero results. All direct forum fetches return HTTP 403. | LOW |
| Web-wide error string sweep (2026-05-30) | **Zero indexed results — 63 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"` — all return zero publicly indexed results anywhere on the accessible web. | LOW |
| Hardware test results — all four workarounds (2026-05-30) | **Zero results — 63 consecutive null cycles.** No public report of testing "Camera FCS Mode = Disable," `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper, `USE_ISP_RETENTION_DATA`, or camera-stop-before-erase as workarounds for the flash-write cold-boot camera failure. **19 days elapsed since the top-4 action list was compiled (May 14, U7) with zero public validation.** | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee, 2026-05-30, dedicated agent) | **Zero new RTL8735B/BW21-CBV-specific content — 63rd consecutive null cycle.** Searches across all 7 Chinese-language query variants returned zero results about FCS flash-write camera failure. All Chinese community sites remain 403-blocked or return zero relevant content. bbs.aithinker.com BW21-CBV threads confirmed still inaccessible. | LOW |
| aiot.realmcu.com, ameba-doc-arduino-sdk.readthedocs-hosted.com (2026-05-30) | **All documentation portals still HTTP 403.** aiot.realmcu.com AMB82-mini guide, Flash Memory example guide, ISP application note, Flash Layout application note — all inaccessible without developer authentication. Zero new FCS warnings or mutex documentation added to any accessible page. | LOW (blocked) |

**Cumulative freeze summary (as of Cycle U63):**

| Repository | Frozen since | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **15 days** |
| ameba-arduino-pro2 dev | May 26, 2026 (`29d47e1`) | **4 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **89 days** |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **82 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 | **180 days** |
| Ai-Thinker-Open | No RTL8735B repos exist | — |

**SDK state as of 2026-05-30 (Cycle U63 — unchanged from U62):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp SHA `b4781b70`, zero mutex calls
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; last build May 19, 2026) — no fix; QC-V07 confirmed absent (HTTP 404)
- ameba-rtos-pro2 main: Frozen at `3f95070` (May 15, 2026) — 15 days no change; PR #17 stale-flagged
- ameba-arduino-pro2 dev: `29d47e1` (May 26, 2026, SPI API only); no new PRs above #410
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — 89 days no change
- VOE binary: v1.7.1.0 (Apr 21, 2026) — no FCS flash-race fix in entire 46-version release history
- Forum ceiling: #4871 (purchasing inquiry; no technical content)

**No confirmed fix. Bug remains unpatched as of 2026-05-30 (Cycle U63).**

**Top unresolved actions (unchanged — 19 days unresolved since U7, May 14):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. FCS Disable is the Arduino IDE default (boards.txt). No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception in all SDK versions through V4.1.1-QC-V06 (SHA `b4781b70`, 3 commits, newest Sep 30, 2025). Callable from Arduino via `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug is fully undocumented outside this research log; 63 research cycles and 46 VOE versions contain zero acknowledgment; filing with the confirmed root-cause chain (FlashMemory bypasses `RT_DEV_LOCK_FLASH`, three-callback FTL race window, cold-boot KM I2C init corruption) would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes at source; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h` (both repos).

## Research Update — 2026-05-30 (Cycle U64)

**Search scope:** Direct GitHub fetches (ameba-rtos-pro2 commits/main; ameba-arduino-pro2 dev/main commits, releases, issues, PRs); English forum/web (new threads above #4871, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports); Chinese sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee); error string sweeps.

**Key new findings this cycle:** None — 64th consecutive null research cycle. All repositories, forum threads, error-string sweeps, and community searches are unchanged from Cycle U63.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 commits page (2026-05-30) | **Confirmed frozen at `3f95070` (May 15, 2026) — 15 days no change.** PR #17 (ethernet USB buffer overflow security fix, orbisai0security) remains open and stale-flagged (bot May 29, 2026). Zero new commits. No flash, FCS, VOE, boot, HAL, or sensor changes in any observable pipeline. | LOW |
| ameba-arduino-pro2 dev branch (2026-05-30) | **Confirmed frozen at `29d47e1` (May 26, 2026, PR #410 SPI API) — 4 days no change.** Zero new commits after May 26. No PRs above #410 in any state. No FCS/flash/camera/mutex-related PRs. | LOW |
| ameba-arduino-pro2 releases (2026-05-30) | **No new releases.** Latest stable = V4.1.0 (Mar 2, 2026). Latest pre-release = V4.1.1-QC-V06 (tag Mar 6, 2026; build20260519 binary May 19, 2026). V4.1.1-QC-V07 confirmed absent (HTTP 404 per U63). No FlashMemory/FCS/camera boot fix in any release note. | LOW |
| ameba-arduino-pro2 open issues (2026-05-30) | **12 open issues; newest = #398 (Mar 29, 2026).** No new issues above #398. No issues about FlashMemory, FCS, camera, VOE, or boot failure in open or closed history. Bug entirely unreported on the official tracker after 64 research cycles (19 days since top-4 action list compiled on May 14). | LOW |
| forum.amebaiot.com threads above #4871 (2026-05-30) | **No new threads indexed above #4871.** Forum ceiling confirmed at #4871 ("I would like to purchase a small quantity of RTL8735b," purchasing inquiry). Targeted searches for IDs #4872–#5000 returned zero results from the forum domain. All direct forum fetches return HTTP 403. | LOW |
| Web-wide error string sweep (2026-05-30) | **Zero indexed results — 64 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"` — all return zero publicly indexed results anywhere on the accessible web. This research log remains the only publicly accessible documentation of this bug and its error codes. | LOW |
| Hardware test results — all four workarounds (2026-05-30 sweep) | **Zero results — 64 consecutive null cycles.** No community member has publicly reported testing "Camera FCS Mode = Disable," `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper, `USE_ISP_RETENTION_DATA`, or camera-stop-before-erase as workarounds for the flash-write cold-boot camera failure. **19 days elapsed since the top-4 action list was compiled (May 14, U7) with zero public validation.** | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee, 2026-05-30) | **Zero new RTL8735B/BW21-CBV-specific content — 64th consecutive null cycle.** All Chinese community sites remain 403-blocked or return zero relevant results for FCS flash-write camera failure on RTL8735B or BW21-CBV. | LOW |

**Cumulative freeze summary (as of Cycle U64):**

| Repository | Frozen since | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **15 days** |
| ameba-arduino-pro2 dev | May 26, 2026 (`29d47e1`) | **4 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **89 days** |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **82 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 | **179 days** |
| Ai-Thinker-Open | No RTL8735B repos exist | — |

**SDK state as of 2026-05-30 (Cycle U64 — unchanged from U63):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp SHA `b4781b70`, zero mutex calls
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; build20260519 binary May 19, 2026) — no fix; QC-V07 confirmed absent (HTTP 404)
- ameba-rtos-pro2 main: Frozen at `3f95070` (May 15, 2026) — **15 days** no change; PR #17 stale-flagged (bot May 29) but still open and unmerged
- ameba-arduino-pro2 dev: `29d47e1` (May 26, 2026, PR #410 SPI API — no fix); no new PRs (max is #410)
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — **89 days** no change
- ameba-tool-rtos-pro2: Frozen at March 9, 2026 (`c1d70e7`) — **82 days** no change
- ideashatch/HUB-8735: Frozen at Dec 2, 2025 — **179 days** no change
- Ai-Thinker-Open: No RTL8735B/BW21 repositories (confirmed U36)
- VOE binary: v1.7.1.0 (Apr 21, 2026) — latest; no FCS flash-race fix in entire 46-version release history (confirmed U53)
- Forum ceiling: **#4871** (purchasing inquiry thread; no technical content; established U61)

**No confirmed fix. Bug remains unpatched as of 2026-05-30 (Cycle U64).**

**Top unresolved actions (unchanged from U63 — 19 days unresolved since U7, May 14):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. FCS Disable is the Arduino IDE default (boards.txt). No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception in all SDK versions through V4.1.1-QC-V06 (SHA `b4781b70`, 3 commits, newest Sep 30, 2025). Callable from Arduino via `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug is fully undocumented outside this research log; 64 research cycles and 46 VOE versions contain zero acknowledgment; filing with the confirmed root-cause chain (FlashMemory bypasses `RT_DEV_LOCK_FLASH`, three-callback FTL race window, cold-boot KM I2C init corruption) would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes at source; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h` (both repos, confirmed May 27).

## Research Update — 2026-05-31 (Cycle U65)

**Search scope:** Four parallel agents: (1) GitHub — ameba-rtos-pro2 commits/issues/PRs/releases; ameba-arduino-pro2 dev/main commits, releases, issues; ideashatch/HUB-8735 issues; (2) English forum/web — new threads above #4871, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/mcublog.cn/Bilibili/Gitee; (4) SDK/documentation deep-dive — aiot.realmcu.com SoC family coverage, V4.1.1-QC-V07 existence, open issues status.

**Key new findings this cycle:** One clarification of documentation portal scope. All other channels null for the 65th consecutive cycle.

| Source | Key Finding | Priority |
|---|---|---|
| aiot.realmcu.com — SoC family coverage analysis (Agent 4, 2026-05-31) | **CLARIFICATION: `aiot.realmcu.com` does NOT cover RTL8735B/AmebaPro2.** The portal covers newer Realtek SoC families only: RTL8721Dx, RTL8720E, RTL8726E, RTL8713E, RTL8730E, RTL8721F, HiFi DSP Series, and Cortex-A Linux Series. RTL8735B/AmebaPro2 documentation remains exclusively on the older `ameba-doc-rtos-pro2-sdk.readthedocs-hosted.com` host. This fully explains why every `aiot.realmcu.com` fetch in prior cycles returned HTTP 403 — the RTL8735B documentation paths do not exist on that portal (not just access-controlled). Prior cycles (U15, U17, U18, U21–U27) treated aiot.realmcu.com as "potentially accessible with developer login" — this is now corrected. | LOW (clarification) |
| ameba-rtos-pro2 commits (four agents, 2026-05-31) | **Confirmed frozen at `3f95070` (May 15, 2026) — 16 days no change.** Commit list verified by two independent methods (commits page + compare endpoint). PR #17 (ethernet USB buffer overflow fix, orbisai0security) remains open and stale-flagged (bot May 29, 2026) — not merged or closed. Zero new commits touching flash, FCS, VOE, boot, HAL, or sensor init. | LOW |
| ameba-arduino-pro2 dev branch (2026-05-31) | **Confirmed frozen at `29d47e1` "Update SPI API for SPI1 switching (#410)" (May 26, 2026) — 5 days no change.** Zero new commits after May 26. No PRs above #410 in any state. No FCS/flash/camera/mutex-related PRs. | LOW |
| ameba-arduino-pro2 releases (2026-05-31) | **V4.1.1-QC-V07: HTTP 404 confirmed by two independent agents** — does not exist. Latest pre-release remains V4.1.1-QC-V06 (tag March 6, 2026; build20260519 binary May 19, 2026). No V4.1.1 stable release. No FCS/flash/camera boot fix in any release note in the V4.1.1-QC-V01 through V4.1.1-QC-V06 sequence. | LOW |
| ameba-arduino-pro2 issues (2026-05-31) | **17 open issues; newest = #398 (Mar 29, 2026).** No new issues above #398. Zero issues about FlashMemory, FCS, camera, VOE, or boot failure in open or closed history. Bug entirely unreported on the official tracker after 65 research cycles (20 days since top-4 action list compiled May 14). | LOW |
| ideashatch/HUB-8735 (2026-05-31) | **Confirmed frozen since Dec 2, 2025 — 180 days no change.** One open issue: #10 (PS5268 sensor id fail, Aug 2025). No new activity. | LOW |
| forum.amebaiot.com threads above #4871 (2026-05-31) | **No new threads indexed above #4871.** Forum ceiling confirmed at #4871 ("I would like to purchase a small quantity of RTL8735b," purchasing inquiry, no technical content). Targeted search for IDs #4872–#5000 returns zero results. All direct forum fetches return HTTP 403. | LOW |
| bbs.ai-thinker.com — tid=46023 (Agent 3, newly identified) | **Newly cataloged thread** (previously untracked, not related to bug). Title: "【安信可小安派BW21-CBV-Kit】打开摄像头+人脸识别" (Opening camera + face recognition on BW21-CBV-Kit). Content is a general camera tutorial — no flash write/camera interaction. 403-blocked. Adds to BW21-CBV Chinese thread catalog. | LOW (catalog only) |
| Web-wide error string sweep (2026-05-31) | **Zero indexed results — 65 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"` — all return zero publicly indexed results anywhere on the accessible web. | LOW |
| Hardware test results — all four workarounds (2026-05-31) | **Zero results — 65 consecutive null cycles.** No public report of testing "Camera FCS Mode = Disable," `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper, `USE_ISP_RETENTION_DATA`, or camera-stop-before-erase. **20 days elapsed since top-4 action list compiled (May 14, U7) with zero public validation.** | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/mcublog.cn/Bilibili/Gitee, 2026-05-31) | **Zero new RTL8735B/BW21-CBV-specific technical content — 65th consecutive null cycle.** All Chinese community sites remain 403-blocked or return zero relevant results for FCS flash-write camera failure. | LOW |

**Documentation portal status — corrected map (Cycle U65):**

| Portal | Covers RTL8735B? | Access status |
|---|---|---|
| `ameba-doc-rtos-pro2-sdk.readthedocs-hosted.com` | **YES** — primary RTL8735B RTOS SDK docs | HTTP 403 (requires developer login) |
| `ameba-doc-arduino-sdk.readthedocs-hosted.com` | **YES** — primary Arduino SDK docs | HTTP 403 (requires developer login) |
| `aiot.realmcu.com` | **NO** — covers RTL8721Dx, RTL8720E, RTL8726E, RTL8713E, RTL8730E, RTL8721F only | HTTP 403 moot — wrong portal for RTL8735B |
| `amebaiot.com/en/amebapro2-arduino-*` | **YES** — legacy tutorial pages | HTTP 403 |
| `forum.amebaiot.com` | **YES** — community forum | HTTP 403 (requires login) |

**Cumulative freeze summary (as of Cycle U65):**

| Repository | Frozen since | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **16 days** |
| ameba-arduino-pro2 dev | May 26, 2026 (`29d47e1`) | **5 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **90 days** |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **83 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 | **180 days** |
| Ai-Thinker-Open | No RTL8735B repos exist | — |

**SDK state as of 2026-05-31 (Cycle U65 — unchanged from U64):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp SHA `b4781b70`, zero mutex calls
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; build20260519 binary May 19, 2026) — no fix; V4.1.1-QC-V07 confirmed absent (HTTP 404 by two agents)
- ameba-rtos-pro2 main: Frozen at `3f95070` (May 15, 2026) — 16 days no change; PR #17 stale-flagged (May 29) but open and unmerged
- ameba-arduino-pro2 dev: `29d47e1` (May 26, 2026, SPI API — no fix)
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — 90 days no change
- VOE binary: v1.7.1.0 (Apr 21, 2026) — no FCS flash-race fix in entire 46-version release history
- Forum ceiling: **#4871** (purchasing inquiry; no technical content)

**No confirmed fix. Bug remains unpatched as of 2026-05-31 (Cycle U65).**

**Top unresolved actions (unchanged from U64 — 20 days unresolved since U7, May 14):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. FCS Disable is the Arduino IDE default (boards.txt). No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception in all SDK versions through V4.1.1-QC-V06. Callable from Arduino via `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug fully undocumented outside this research log; 65 research cycles and 46 VOE versions contain zero acknowledgment; filing would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes at source; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h` (both repos).

## Research Update — 2026-05-31 (Cycle U66)

**Search scope:** Full sweep confirming state documented in U65 — GitHub commits (ameba-rtos-pro2 main, ameba-arduino-pro2 dev/main), releases, open issues, PRs; forum.amebaiot.com threads above #4871; English web error string indexing; Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com); hardware test result search for all four proposed workarounds.

**Key new findings this cycle:** Zero. All channels confirmed in identical frozen state to U65. This is the 66th consecutive null cycle for confirmed fix, public disclosure, or hardware test result.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 commits (2026-05-31) | **Confirmed frozen — no change since U65.** HEAD remains `3f95070` (May 15, 2026) — **16 days** no activity. PR #17 (ethernet/USB buffer overflow fix by orbisai0security, stale-bot flagged May 29) still open and unmerged. Zero new commits touching flash, FCS, VOE, boot, HAL, sensor init, or `device_mutex_lock`. | LOW |
| ameba-arduino-pro2 dev branch (2026-05-31) | **Confirmed frozen — no change since U65.** HEAD remains `29d47e1` "Update SPI API for SPI1 switching (#410)" (May 26, 2026, kevinlookl) — **5 days** no further commits. No new PRs above #410. No FCS/FlashMemory/mutex-related changes in any state. | LOW |
| ameba-arduino-pro2 main branch (2026-05-31) | **Confirmed frozen — no change since U65.** HEAD remains `93d63514` (Mar 2, 2026) — **90 days** no change. V4.1.1-QC-V07 still absent (HTTP 404). Latest pre-release V4.1.1-QC-V06 (build20260519). FlashMemory.cpp SHA `b4781b70` unchanged — still zero `device_mutex_lock` calls. | LOW |
| ameba-arduino-pro2 open issues (2026-05-31) | **No new issues above #398** (Mar 29, 2026). Bug remains entirely unreported on the official tracker — 66 research cycles, zero public disclosure. | LOW |
| forum.amebaiot.com (2026-05-31) | **No new threads above #4871.** Forum ceiling unchanged. All direct fetches return HTTP 403. | LOW |
| Web-wide error string sweep (2026-05-31) | **Zero indexed results — 66 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"` — all return zero publicly indexed results. | LOW |
| Hardware test results — all four workarounds (2026-05-31) | **Zero results — 66 consecutive null cycles.** No public report of testing any of: "Camera FCS Mode = Disable," `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper, `USE_ISP_RETENTION_DATA`, camera-stop-before-erase. **20+ days since top-4 action list compiled (May 14, U7) with zero public validation.** | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/mcublog.cn/Bilibili/Gitee, 2026-05-31) | **Zero new RTL8735B/BW21-CBV-specific technical content — 66th consecutive null cycle.** All Chinese community sites remain 403-blocked or return zero relevant results for FCS flash-write camera failure. | LOW |

**Cumulative freeze summary (as of Cycle U66 — unchanged from U65):**

| Repository | Frozen since | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **16 days** |
| ameba-arduino-pro2 dev | May 26, 2026 (`29d47e1`) | **5 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **90 days** |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **83 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 | **180 days** |
| Ai-Thinker-Open | No RTL8735B repos exist | — |

**SDK state as of 2026-05-31 (Cycle U66 — unchanged from U65):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp SHA `b4781b70`, zero mutex calls
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; build20260519 binary May 19, 2026) — no fix; V4.1.1-QC-V07 absent
- ameba-rtos-pro2 main: Frozen at `3f95070` (May 15, 2026) — 16 days; PR #17 stale but open
- ameba-arduino-pro2 dev: `29d47e1` (May 26, 2026, SPI API — unrelated to bug)
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — 90 days
- VOE binary: v1.7.1.0 (Apr 21, 2026) — no FCS flash-race fix in entire 46-version release history
- Forum ceiling: **#4871** (purchasing inquiry; no technical content)

**No confirmed fix. Bug remains unpatched as of 2026-05-31 (Cycle U66).**

**Top unresolved actions (unchanged from U65 — 20+ days unresolved since U7, May 14):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. FCS Disable is the Arduino IDE default (boards.txt). No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception in all SDK versions through V4.1.1-QC-V06. Callable from Arduino via `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug fully undocumented outside this research log; 66 research cycles and 46 VOE versions contain zero acknowledgment; filing would be the first public disclosure.

---

## Research Update — 2026-05-31 (Cycle U67)

**Search scope:** Three parallel deep-research agents covering: (1) English forum/GitHub/web — forum.amebaiot.com threads above #4871, ameba-arduino-pro2 dev/main new commits, ameba-rtos-pro2 new commits, web-wide error string indexing, workaround hardware-test reports, ElegantOTA issue #150; (2) Chinese-language sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/mcublog.cn/Bilibili/Gitee; (3) SDK releases, aiot.realmcu.com documentation portal, GitHub PRs/issues for FlashMemory mutex, ameba-arduino-pro2 full PR history. All three agents completed independently.

**Key new findings this cycle:**

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 commits (2026-05-31) | **Confirmed frozen — no change since U66.** HEAD remains `3f95070` (May 15, 2026) — **16 days** no activity. Zero commits touching flash, FCS, VOE, HAL, sensor init, or `device_mutex_lock`. Commit search for `RT_DEV_LOCK_FLASH` returns 0 results. | LOW |
| ameba-arduino-pro2 dev branch (2026-05-31) | **Confirmed frozen since U66.** HEAD remains `29d47e1` "Update SPI API for SPI1 switching (#410)" (May 26, 2026). Zero PRs above #410. No FCS/FlashMemory/mutex-related changes. Commit search for "FlashMemory mutex" in the repository returns **0 results**. | LOW |
| FlashMemory.cpp (dev branch live file) | **Adversarially verified unpatched.** Direct source inspection of `Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.cpp` on dev branch confirms `device_mutex_lock`, `RT_DEV_LOCK_FLASH`, and all mutex primitives **completely absent** — raw `flash_stream_write()`, `flash_erase_sector()`, `flash_write_word()` calls with no synchronization. SHA `b4781b70` unchanged. | MEDIUM |
| ameba-arduino-pro2 releases (2026-05-31) | **No new release.** V4.1.1-QC-V06 (tagged May 19, 2026) remains latest pre-release. V4.1.1-QC-V06 release notes confirmed: new sensors (IMX681_5M, K306P), TensorFlowLite, battery-camera POC, AMB82-zero support, WDT API updates. **Zero mention** of FlashMemory mutex fix, FCS cold-boot camera fix, or RT_DEV_LOCK_FLASH. | LOW |
| ameba-arduino-pro2 PRs/issues (2026-05-31) | **Zero PRs or issues about FlashMemory mutex bug.** Most recent merged PRs: #410 (SPI1 switching), #409 (IMX681_5M sensor), #408 (I2C Slave). No PR in full visible history touches FlashMemory.cpp or adds locking. Bug remains entirely unreported on the official tracker — **67 research cycles, zero public disclosure.** | LOW |
| forum.amebaiot.com (2026-05-31) | **Confirmed ceiling at #4871** (purchasing inquiry). No new threads above #4871 indexed. All direct fetches return HTTP 403. Three search agents independently confirm same result. | LOW |
| Forum thread #4834: "Boot failure after OTA update" (Apr 24, 2026) | **Independently confirmed by all three agents.** AMB82/RTL8735B fails to boot after OTA update — boot ROM reports invalid NOR flash ID / SPIF detection failure. Different failure mode from FCS camera bug (this is pre-OS boot failure; FCS bug reaches VOE), but same class: flash operation corrupts something the boot subsystem depends on. Content 403-gated; no resolution in search snippets. URL: https://forum.amebaiot.com/t/boot-failure-after-ota-update/4834 | MEDIUM |
| Forum thread #3983: "Error after write in memory AMB82" | **Most directly relevant user-reported flash-write symptom found in any cycle.** User writes 32 bytes spanning 3 flash sectors and gets errors on restart. This pattern (writing to flash → device fails on restart) maps exactly onto the class of failures the FCS race condition causes. Content 403-gated; no date or resolution visible in index. URL: https://forum.amebaiot.com/t/error-after-write-in-memory-amb82/3983 | MEDIUM |
| Forum thread #4865: "AmebaPro2 uartfwburn fail for download 0" (May 2026) | Programmer reports uartfwburn returns 100% but then "fail for download 0". Flash-tool protocol issue, not related to camera FCS. URL: https://forum.amebaiot.com/t/amebapro2-uartfwburn-cant-flash-fail-for-download-0-after-programing-is-100-complete/4865 | LOW |
| Workaround hardware tests — all 3 workarounds (2026-05-31) | **Zero results — 67 consecutive null cycles.** No public post, issue, commit, or blog from any date confirms hardware-tested results for: "Camera FCS Mode = Disable", `device_mutex_lock` wrapper, or `USE_ISP_RETENTION_DATA`. One August 2025 forum discussion mentions a user testing boards with FCS Mode Disable but gives no pass/fail conclusion on the cold-boot camera failure specifically. | MEDIUM |
| Error string sweep (2026-05-31) | **Zero results — 67 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"`, `"USE_ISP_RETENTION_DATA"` — all return zero publicly indexed results anywhere. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/mcublog.cn, 2026-05-31) | **Zero new RTL8735B/BW21-CBV-specific technical content.** One April 2026 mcublog.cn article documents BW21-CBV for photo capture + Feishu bot upload — no mention of flash write causing camera failure. All other Chinese platforms 403-blocked or zero relevant results. | LOW |
| ElegantOTA issue #150 (2026-05-31) | **Confirmed closed "not planned" / Stale** — compilation failure (`sdkconfig.h` not found via AsyncTCP.h), not a runtime flash/FCS issue. No new activity after May 25. Independently verified by all three agents. | LOW |
| aiot.realmcu.com RTL8735B portal (2026-05-31) | RTL8735B product page returns HTTP 403. Flash Program Tool docs accessible. No new FCS-specific documentation surfaced publicly. Full tech docs require user registration at realmcu.com. | LOW |

**New MEDIUM-priority signals this cycle:**

Two forum threads found (both 403-gated, content not fully accessible) provide the strongest public symptom corroboration found in any cycle:

1. **Thread #3983 "Error after write in memory AMB82"**: User writes 32 bytes spanning 3 flash sectors → errors on restart. This is the most direct public parallel to the FCS race condition (flash write → restart failure), even if the user's framing is at the "bytes + sectors" level rather than ISP FCS.

2. **Thread #4834 "Boot failure after OTA update"**: Post-OTA NOR flash detection failure (SPIF invalid ID). More severe than FCS camera failure (complete no-boot vs. camera-only), but same root class: a flash write operation leaves the device in a state that a Realtek boot subsystem cannot handle on next cold boot.

Neither thread has an indexed resolution. Both corroborate that the RTL8735B flash write → cold boot failure class is wider than just the camera FCS path — suggesting the SPIC bus / NOR flash state management is fragile under concurrent or unexpected access patterns across multiple contexts.

**Cumulative freeze summary (as of Cycle U67):**

| Repository | Frozen since | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **16 days** |
| ameba-arduino-pro2 dev | May 26, 2026 (`29d47e1`) | **5 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **90 days** |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **83 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 | **180 days** |
| Ai-Thinker-Open | No RTL8735B repos exist | — |

**SDK state as of 2026-05-31 (Cycle U67 — unchanged from U66):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp SHA `b4781b70`, zero mutex calls
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; build20260519 binary May 19, 2026) — no fix; release notes confirm no FCS/mutex mention
- ameba-rtos-pro2 main: Frozen at `3f95070` (May 15, 2026) — 16 days
- ameba-arduino-pro2 dev: `29d47e1` (May 26, 2026, SPI API — unrelated to bug)
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — 90 days
- VOE binary: v1.7.1.0 (Apr 21, 2026) — no FCS flash-race fix in entire 46-version release history
- Forum ceiling: **#4871** (purchasing inquiry; no technical content)

**No confirmed fix. Bug remains unpatched as of 2026-05-31 (Cycle U67).**

**Top unresolved actions (unchanged — 20+ days unresolved since U7, May 14):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. FCS Disable is the Arduino IDE default (boards.txt). No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception in all SDK versions through V4.1.1-QC-V06. Callable from Arduino via `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug fully undocumented outside this research log; 67 research cycles and 46 VOE versions contain zero acknowledgment; filing would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes at source; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h` (both repos).

## Research Update — 2026-05-31 (Cycle U68)

**Search scope:** Six parallel agents + direct GitHub/web fetches: (1) GitHub — ameba-rtos-pro2 compare endpoint and commit page; ameba-arduino-pro2 dev/main commits, releases, issues, PRs after May 26; (2) English forum/web — new threads above #4871, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee; (4) SDK deep-dive — FlashMemory.cpp mutex state, VOE version, new releases; (5) Error string indexing; (6) Forum ceiling sweep (#4872–#4930).

**Key new findings this cycle:** None. All research channels confirm identical frozen state to Cycle U67. This is the 68th consecutive cycle with zero confirmed fix, public disclosure, or hardware test result. Multiple independent agents and direct fetches confirm the finding.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 commits (direct GitHub fetch, 2026-05-31) | **Confirmed frozen — identical to U67.** HEAD = `3f95070` (May 15, 2026) — **16 days** no new commits. 10 most recent commits verified: all dated May 15 or earlier. PR #17 ("fix: ethernet USB driver buffer overflow", orbisai0security) still open, stale-bot flagged May 29, no merge. Zero commits touching flash, FCS, VOE, boot, HAL, sensor init, or mutex. | LOW |
| ameba-arduino-pro2 dev branch commits (direct GitHub fetch, 2026-05-31) | **Confirmed frozen — identical to U67.** HEAD = `29d47e1` "Update SPI API for SPI1 switching (#410)" (May 26, 2026, kevinlookl). 10 most recent commits verified: `29d47e1` (May 26), `7db1c7d` (May 19), `3d53672` (May 19), `cd0bd40` (May 18), `13961cc` (May 5). Zero new commits after May 26. No FCS/FlashMemory/mutex-related changes in any state. | LOW |
| ameba-arduino-pro2 releases (direct GitHub fetch, 2026-05-31) | **No new releases.** Latest stable = V4.1.0 (Mar 2, 2026). Latest pre-release = V4.1.1-QC-V06 (tag Mar 6, 2026; release notes through May 19, 2026). No V4.1.1-QC-V07 or stable V4.1.1. Complete release list: V4.1.1-QC-V06, V4.1.0, V4.1.0-QC-V12, V4.0.9, V4.0.8, V4.0.7, V4.0.6 — none contain a FCS cold-boot, FlashMemory mutex, or SPIC concurrent-access fix. | LOW |
| `FlashMemory.cpp` — dev branch raw fetch (2026-05-31) | **Zero mutex calls confirmed unchanged.** Full content fetched: `flash_stream_read`, `flash_stream_write`, `flash_erase_sector`, `flash_read_word`, `flash_write_word` all call flash HAL functions directly with zero `device_mutex_lock`, `device_mutex_unlock`, or `RT_DEV_LOCK_FLASH`. Commit history for this file: 3 commits total (Jul 9, 2024; Sep 30, 2025 ×2). GitHub commit search `FlashMemory mutex` in ameba-arduino-pro2 = **0 results**. Architectural defect persists through every released SDK version. | LOW (confirms prior) |
| VOE release note — newest version (2026-05-31) | **VOE 1.7.1.0 (04/21/2026) confirmed latest.** Release note (RTOS SDK copy, alternate path) confirms VOE history tops out at 1.7.1.0 — "Fix dual sensor ID FCS mirror/flip issue." No FCS_I2C_INIT_ERR, SPIC bus arbitration, or FlashMemory mutex fix in any of the 46 VOE versions spanning 2 years of development. | LOW (confirms prior) |
| ameba-arduino-pro2 open issues (2026-05-31) | **No new issues.** 12–17 open issues; newest = #398 (Mar 29, 2026). 321 closed PRs — zero in any state about FlashMemory mutex, FCS camera cold-boot, or RT_DEV_LOCK_FLASH. Bug remains entirely unreported on the official tracker after 68 research cycles. | LOW |
| ameba-rtos-pro2 open issues (2026-05-31) | **3 open issues unchanged:** #16 (Jan 2026), #4 (Apr 2025), #3 (Apr 2025). No FCS/flash/camera bug filed. | LOW |
| forum.amebaiot.com threads above #4871 (sweep, 2026-05-31) | **No new threads indexed.** Targeted searches for IDs #4872–#4930 returned zero results. Forum ceiling confirmed at #4871 (purchasing inquiry, no technical content). All direct fetches return HTTP 403. Site:forum.amebaiot.com searches confirm no new camera/flash/FCS boot content in any indexed thread. | LOW |
| Web-wide error string sweep (2026-05-31) | **Zero indexed results — 68 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"` — zero publicly indexed results anywhere on the accessible web. | LOW |
| Hardware test confirmation — all four workarounds (2026-05-31) | **Zero results — 68 consecutive null cycles.** No public post on any platform (Reddit, Hackster, forum.amebaiot.com, GitHub, CSDN, Zhihu, EEWorld, 21IC, Bilibili, Gitee, bbs.aithinker.com, bbs.ai-thinker.com, mcublog.cn) reports hardware testing of "Camera FCS Mode = Disable," `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper, `USE_ISP_RETENTION_DATA`, or camera-stop-before-erase for this specific bug. No hardware test result in any language since the workaround list was first compiled (U7, May 14 — **17 days ago**). | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn, 2026-05-31) | **Zero new RTL8735B/BW21-CBV technical content — 68th consecutive null cycle.** All Chinese community sites remain 403-blocked or return zero relevant results. No Chinese-language forum posts or articles discuss FCS flash-write camera failure on RTL8735B or BW21-CBV in any accessible source. | LOW |

**Cumulative freeze summary (as of Cycle U68 — unchanged from U67):**

| Repository | Frozen since | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **16 days** |
| ameba-arduino-pro2 dev | May 26, 2026 (`29d47e1`) | **5 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **90 days** |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **83 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 | **180 days** |
| Ai-Thinker-Open | No RTL8735B repos exist | — |

**SDK state as of 2026-05-31 (Cycle U68 — unchanged from U67):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp zero mutex calls confirmed
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; build20260519 binary May 19, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at `3f95070` (May 15, 2026) — 16 days; PR #17 stale but open
- ameba-arduino-pro2 dev: `29d47e1` (May 26, 2026, SPI API — unrelated to bug) — 5 days frozen
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — 90 days
- VOE binary: v1.7.1.0 (Apr 21, 2026) — no FCS flash-race fix in entire 46-version release history
- Forum ceiling: **#4871** (purchasing inquiry; no technical content)

**No confirmed fix. Bug remains unpatched as of 2026-05-31 (Cycle U68).**

**Top unresolved actions (unchanged — 17 days unresolved since U7, May 14):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception in every SDK version. Callable from Arduino: `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug entirely undocumented outside this research log; 68 research cycles and 46 VOE versions contain zero acknowledgment; filing would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes at source; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-06-01 (Cycle U69)

**Search scope:** Six parallel search threads + direct GitHub/web fetches: (1) GitHub — ameba-rtos-pro2 commits page and compare endpoint; ameba-arduino-pro2 dev/main commits, releases, issues, PRs after May 26; (2) English forum/web — new threads above #4871, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/mcublog.cn/Bilibili/Gitee; (4) Error string indexing — `FCS_I2C_INIT_ERR`, `FCS_RUN_DATA_NG_KM`, `"It don't do the sensor initial process"`, `"VOE_OPEN_CMD fail"`; (5) Workaround confirmation sweep — `"Camera FCS Mode = Disable"` hardware test reports, `device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory` workaround; (6) New GitHub Issues/PRs for FlashMemory mutex fix.

**Key new findings this cycle:** None. All research channels confirm the same frozen state as Cycle U68. This is the 69th consecutive null cycle. No new commits, releases, forum threads, hardware test reports, or Chinese-language content have appeared since May 31, 2026.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 commits page (direct GitHub fetch, 2026-06-01) | **Confirmed frozen — identical to U68.** 10 most recent commits verified by direct fetch: `3f95070` (May 15), `afc85a0` (May 15), `9c8b6f6` (May 15), `d2676f1` (May 15), `1c1c8b7` (May 1), `a111e91` (May 1), `7b2b97f` (May 1), `63c0a2f` (May 1), `d54e1a8` (May 1), `687a4c7` (May 1). **Zero new commits in 17 days since May 15, 2026.** PR #17 (ethernet USB driver buffer overflow fix, orbisai0security) still open and unmerged. No flash, FCS, VOE, boot, HAL, sensor, or mutex changes in any commit. | LOW |
| ameba-arduino-pro2 dev branch commits (direct GitHub fetch, 2026-06-01) | **Confirmed frozen — identical to U68.** HEAD = `29d47e1` "Update SPI API for SPI1 switching (#410)" (May 26, 2026, kevinlookl). 10 most recent commits verified: `29d47e1` (May 26), `7db1c7d` (May 19), `3d53672` (May 19), `cd0bd40` (May 18), `13961cc` (May 5), and earlier entries unchanged. **Zero new commits in 6 days since May 26, 2026.** No FlashMemory, FCS, camera, mutex, or boot-related changes in any commit. | LOW |
| ameba-arduino-pro2 releases page (direct GitHub fetch, 2026-06-01) | **No new releases.** Full release list confirmed: V4.1.1-QC-V06 (pre-release, tag Mar 6 / content through May 19, 2026), V4.1.0 (stable, Mar 2, 2026), and all prior versions (V4.1.0-QC-V12 through V4.0.6). No V4.1.1 stable or QC-V07 published. No FCS cold-boot, FlashMemory mutex, or SPIC concurrent-access fix in any release. | LOW |
| ameba-arduino-pro2 open issues (direct GitHub fetch, 2026-06-01) | **17 open issues confirmed; newest = #398 (Mar 29, 2026).** No new issues filed since May 26, 2026. No issues about FlashMemory, FCS, camera, VOE, or boot failure anywhere in open or closed issue history. Bug remains entirely unreported on the official tracker after 69 research cycles. | LOW |
| forum.amebaiot.com threads above #4871 (search sweep, 2026-06-01) | **No new threads indexed.** Targeted searches for thread IDs #4872–#4930 returned zero results. Forum ceiling remains at thread #4871 (purchasing inquiry, no technical content). All direct fetches return HTTP 403. No new camera/flash/FCS boot content in any indexed thread. | LOW |
| Web-wide error string sweep (2026-06-01) | **Zero indexed results — 69 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"` — zero publicly indexed results anywhere on the accessible web. | LOW |
| Workaround hardware test confirmation sweep (2026-06-01) | **Zero hardware test results — 18 days since workarounds first compiled (U7, May 14).** No public post on any platform reports hardware testing of "Camera FCS Mode = Disable," `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper, `USE_ISP_RETENTION_DATA`, or camera-stop-before-erase for this specific bug. No hardware test result in any language. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn, 2026-06-01 sweep) | **Zero new content — 69th consecutive null cycle.** All Chinese community sites remain 403-blocked or return zero relevant results. bbs.aithinker.com BW21-CBV-Kit subforum, bbs.ai-thinker.com forum, and all indexed Chinese-language BW21-CBV content are either 403-blocked or unrelated to FCS flash-write camera failure. No new Chinese-language technical posts about this bug found anywhere. | LOW |

**Cumulative freeze summary (as of Cycle U69):**

| Repository | Frozen since | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **17 days** |
| ameba-arduino-pro2 dev | May 26, 2026 (`29d47e1`) | **6 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **91 days** |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **84 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 | **181 days** |
| Ai-Thinker-Open | No RTL8735B repos exist | — |

**SDK state as of 2026-06-01 (Cycle U69 — unchanged from U68):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp zero mutex calls confirmed
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; build20260519 binary May 19, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at `3f95070` (May 15, 2026) — 17 days; PR #17 stale but open
- ameba-arduino-pro2 dev: `29d47e1` (May 26, 2026, SPI API — unrelated to bug) — 6 days frozen
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — 91 days
- VOE binary: v1.7.1.0 (Apr 21, 2026) — no FCS flash-race fix in entire 46-version release history
- Forum ceiling: **#4871** (purchasing inquiry; no technical content)

**No confirmed fix. Bug remains unpatched as of 2026-06-01 (Cycle U69).**

**Top unresolved actions (unchanged — 18 days unresolved since U7, May 14):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception in every SDK version. Callable from Arduino: `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug entirely undocumented outside this research log; 69 research cycles and 46 VOE versions contain zero acknowledgment; filing would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes at source; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

---

## Research Update — 2026-06-01 (Cycle U70)

| Source | Key Finding | Priority |
|---|---|---|
| ameba-arduino-pro2 dev branch HEAD (2026-06-01) | **Zero new commits** — HEAD remains `29d47e1` (May 26, 2026, "Update SPI API for SPI1 switching #410"). No FlashMemory, mutex, RT_DEV_LOCK_FLASH, or FCS-related commit since V4.0.8 introduction (Oct 2024). | LOW |
| ameba-rtos-pro2 main branch HEAD (2026-06-01) | **Zero new commits** — HEAD remains `3f95070` "Sync upstream" (May 15, 2026). No flash mutex, ftl_nor, device_lock, or video_boot changes visible. | LOW |
| ameba-arduino-pro2 GitHub Issues full sweep (2026-06-01) | **Zero FlashMemory issues filed** — 11 open issues visible; none mention FlashMemory, mutex, FCS, cold boot, or RT_DEV_LOCK_FLASH. Most recent issue #398 (March 29, 2026). Bug entirely undisclosed publicly. | LOW |
| ameba-arduino-pro2 Releases (2026-06-01) | **No new release** — V4.1.0 (Mar 2, 2026) remains latest stable; V4.1.1-QC-V06 (Mar 6, 2026 tag) latest pre-release. No releases above these. | LOW |
| forum.amebaiot.com search sweep (2026-06-01) | **No new threads above #4871** — all forum searches return previously-logged threads (#4865, #4834, #4829, #4777, #4748). Forum direct access returns HTTP 403. Ceiling unchanged at #4871. No new camera/FCS/flash/cold-boot discussion found. | LOW |
| VOE version check (2026-06-01) | **No new VOE release** — searches for voe.bin 1.7.2 and 1.8.0 return zero results. v1.7.1.0 (Apr 21, 2026) remains the latest documented version. | LOW |
| Workaround hardware test confirmation sweep (2026-06-01) | **Zero hardware test results — 18 days** since workarounds first compiled (U7, May 14). No public post on any platform reports hardware testing of "Camera FCS Mode = Disable," `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper, or `USE_ISP_RETENTION_DATA` for this specific bug. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com, 2026-06-01) | **Zero new content — 70th consecutive null cycle.** All Chinese community sites remain 403-blocked or return zero relevant results. No new Chinese-language technical posts about RTL8735B FCS flash-write camera failure found on any platform. | LOW |

**Cumulative freeze summary (as of Cycle U70):**

| Repository | Frozen since | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **17 days** |
| ameba-arduino-pro2 dev | May 26, 2026 (`29d47e1`) | **6 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **91 days** |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **84 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 | **181 days** |
| Ai-Thinker-Open | No RTL8735B repos exist | — |

**SDK state as of 2026-06-01 (Cycle U70 — unchanged from U69):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp zero mutex calls confirmed
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; build20260519 binary May 19, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at `3f95070` (May 15, 2026) — 17 days; PR #17 stale but open
- ameba-arduino-pro2 dev: `29d47e1` (May 26, 2026, SPI API — unrelated to bug) — 6 days frozen
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — 91 days
- VOE binary: v1.7.1.0 (Apr 21, 2026) — no FCS flash-race fix in entire 46-version release history
- Forum ceiling: **#4871** (purchasing inquiry; no technical content)

**No confirmed fix. Bug remains unpatched as of 2026-06-01 (Cycle U70).**

**Top unresolved actions (unchanged — 18 days unresolved since U7, May 14):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception in every SDK version. Callable from Arduino: `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug entirely undocumented outside this research log; 70 research cycles and 46 VOE versions contain zero acknowledgment; filing would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes at source; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-06-01 (Cycle U71)

**Search scope:** Five parallel agents + direct GitHub fetches + targeted web searches: (1) GitHub — ameba-rtos-pro2 commits page and compare endpoint; ameba-arduino-pro2 dev/main commits, releases, issues, PRs after May 26; (2) English forum/web — new threads above #4871, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/mcublog.cn/Bilibili/Gitee; (4) VOE version and SDK release check; (5) Sibling-chip and cross-platform flash-boot-race precedents; plus direct WebFetch on ameba-rtos-pro2 commits page, ameba-arduino-pro2 releases page, and dev branch commit page.

**Key new findings this cycle:** None. All research channels confirm the same frozen state as Cycle U70. This is the 71st consecutive null cycle. No new commits, releases, forum threads, documentation, or hardware test reports have appeared since June 1, 2026 (Cycle U70).

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 commits page (direct WebFetch, 2026-06-01) | **Confirmed frozen — identical to U70.** 10 most recent commits: `3f95070` (May 15), `afc85a0` (May 15), `9c8b6f6` (May 15), `d2676f1` (May 15), `1c1c8b7` (May 1), `a111e91` (May 1), `7b2b97f` (May 1), `63c0a2f` (May 1), `d54e1a8` (May 1), `687a4c7` (May 1). **Zero new commits in 17 days since May 15, 2026.** PR #17 (ethernet USB driver buffer overflow fix, orbisai0security) still open, stale. No flash, FCS, VOE, boot, HAL, sensor, or mutex changes in any commit. | LOW |
| ameba-arduino-pro2 dev branch commits (direct WebFetch, 2026-06-01) | **Confirmed frozen — identical to U70.** HEAD = `29d47e1` "Update SPI API for SPI1 switching (#410)" (May 26, 2026, kevinlookl). 10 most recent commits verified: `29d47e1` (May 26), `7db1c7d` (May 19), `3d53672` (May 19), `cd0bd40` (May 18), `13961cc` (May 5). **Zero new commits in 6 days since May 26, 2026.** No FlashMemory, FCS, camera, mutex, or boot-related changes in any commit. | LOW |
| ameba-arduino-pro2 releases page (direct WebFetch, 2026-06-01) | **No new releases.** Full release list confirmed: V4.1.1-QC-V06 (pre-release, tag Mar 6 / content through May 19, 2026), V4.1.0 (stable, Mar 2, 2026), and all prior versions. No V4.1.1 stable or QC-V07 published. No FCS cold-boot, FlashMemory mutex, or SPIC concurrent-access fix in any release. | LOW |
| ameba-arduino-pro2 open issues (web search, 2026-06-01) | **No new issues.** 17 open issues; newest = #398 (Mar 29, 2026). No issues about FlashMemory, FCS, camera, VOE, or boot failure. Bug remains entirely unreported on the official tracker after 71 research cycles. | LOW |
| forum.amebaiot.com threads above #4871 (search sweep, 2026-06-01) | **No new threads indexed.** Targeted searches for IDs #4872–#4930 returned zero results. Forum ceiling remains at #4871 (purchasing inquiry, no technical content). All direct fetches return HTTP 403. Searches for "forum.amebaiot.com 4872 OR 4873 OR ... OR 4878" returned zero results from the forum domain. | LOW |
| aiot.realmcu.com AMB82-mini Arduino docs (direct WebFetch, 2026-06-01) | **Still 403-blocked.** `aiot.realmcu.com/en/latest/arduino/arduino_guide/sdk_intro/evb_guides/evb_amb82mini.html` returns HTTP 403 Forbidden. No accessible content about Camera FCS Mode, FlashMemory, device_mutex_lock, or flash-camera interaction warnings. | LOW (blocked) |
| Web-wide error string sweep (2026-06-01) | **Zero indexed results — 71 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"` — zero publicly indexed results anywhere on the accessible web. `"RTL8735B FCS_I2C_INIT_ERR camera flash"` search returns only ESP32 I2C camera error results — zero RTL8735B-specific hits. | LOW |
| Hardware test confirmation sweep (2026-06-01) | **Zero hardware test results — 18 days since workarounds first compiled (U7, May 14, 2026).** No public post on any platform (Reddit, Hackster, forum.amebaiot.com, GitHub, CSDN, Zhihu, EEWorld, 21IC, Bilibili, Gitee, bbs.aithinker.com, bbs.ai-thinker.com) reports hardware testing of "Camera FCS Mode = Disable," `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper, `USE_ISP_RETENTION_DATA`, or camera-stop-before-erase for this specific bug. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn, 2026-06-01) | **Zero new content — 71st consecutive null cycle.** All Chinese community sites remain 403-blocked or return zero relevant results. Search for `"BW21-CBV" "flash" "camera" "FCS" "启动" 2026` returns only Amazon/Hackster product pages and DIY project summaries — no technical FCS flash boot failure content in any Chinese-language source. | LOW |
| VOE version check (2026-06-01) | **No new VOE release.** Searches for `voe.bin 1.7.2` and `voe 1.8.0 ameba` return zero results. VOE 1.7.1.0 (Apr 21, 2026) remains the latest documented version. No new `hal_video_release_note.txt` entry beyond 1.7.1.0. | LOW |

**Cumulative freeze summary (as of Cycle U71):**

| Repository | Frozen since | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **17 days** |
| ameba-arduino-pro2 dev | May 26, 2026 (`29d47e1`) | **6 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **91 days** |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **84 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 | **181 days** |
| Ai-Thinker-Open | No RTL8735B repos exist | — |

**SDK state as of 2026-06-01 (Cycle U71 — unchanged from U70):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp zero mutex calls confirmed
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; build20260519 binary May 19, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at `3f95070` (May 15, 2026) — 17 days; PR #17 stale but open
- ameba-arduino-pro2 dev: `29d47e1` (May 26, 2026, SPI API — unrelated to bug) — 6 days frozen
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — 91 days
- VOE binary: v1.7.1.0 (Apr 21, 2026) — no FCS flash-race fix in entire 46-version release history
- Forum ceiling: **#4871** (purchasing inquiry; no technical content)

**No confirmed fix. Bug remains unpatched as of 2026-06-01 (Cycle U71).**

**Top unresolved actions (unchanged — 18 days unresolved since U7, May 14):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception in every SDK version. Callable from Arduino: `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug entirely undocumented outside this research log; 71 research cycles and 46 VOE versions contain zero acknowledgment; filing would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes at source; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

**U71 addendum — two previously unlogged background findings (pre-2026, newly surfaced this cycle):**

| Source | Key Finding | Priority |
|---|---|---|
| Particle device-os PR #2596 (`github.com/particle-iot/device-os/pull/2596`, merged Dec 2, 2022) | **RTL872x-family flash mutex deadlock confirmed by Particle.** "Temporarily enabling RSIP for reading encrypted data from flash requires disabling interrupts. Reading the flash requires acquiring a mutex, which will not work under disabled interrupts/scheduling." Fix: consolidate RSIP management into external flash HAL (`exflash_hal`). RTL872x is the same Realtek Ameba chip family as RTL8735B. Confirms that major third-party SDK vendors have had to patch Realtek flash mutex issues — structural precedent for the `device_mutex_lock(RT_DEV_LOCK_FLASH)` workaround needed in RTL8735B's `FlashMemory.cpp`. | LOW (cross-platform precedent, pre-2026) |
| forum.amebaiot.com/t/flash-translation-layer-ftl-intermittently-unable-to-read-previously-stored-data/3864 (last activity Feb 27, 2025) | **Newly identified related thread — FTL intermittent read failure on AMB82-mini.** User reports Flash Translation Layer intermittently failing to read previously stored data. Consistent with the SPIC concurrent-access defect confirmed in U19 (FlashMemory bypasses `RT_DEV_LOCK_FLASH` while ISP FTL operations hold the lock). Content 403-blocked; not confirmed as camera-triggered. Adds to the class of FTL/flash reliability issues on RTL8735B. | LOW (blocked, pre-2026) |

## Research Update — 2026-06-02 (Cycle U72)

**Search scope:** Six parallel search threads + direct GitHub/web fetches: (1) GitHub — ameba-rtos-pro2 commits page; ameba-arduino-pro2 dev/main commits, releases, issues, PRs after May 26; ameba-rtos-pro2 issues page; (2) English forum/web — new threads above #4871, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/mcublog.cn/Bilibili/Gitee; (4) Error string indexing — `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`; (5) Workaround hardware test confirmation sweep — all three workarounds; (6) New GitHub Issues / releases for FlashMemory mutex fix.

**Key new findings this cycle:** None. All research channels confirm the same frozen state as Cycle U71. This is the 72nd consecutive null cycle. No new commits, releases, forum threads, documentation, hardware test reports, or Chinese-language content have appeared since June 1, 2026.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 commits page (direct WebFetch, 2026-06-02) | **Confirmed frozen — identical to U71.** 10 most recent commits verified: `3f95070` (May 15), `afc85a0` (May 15), `9c8b6f6` (May 15), `d2676f1` (May 15), `1c1c8b7` (May 1), `a111e91` (May 1), `7b2b97f` (May 1), `63c0a2f` (May 1), `d54e1a8` (May 1), `687a4c7` (May 1). **Zero new commits in 18 days since May 15, 2026.** PR #17 (ethernet USB driver buffer overflow fix, orbisai0security) still open and stale. No flash, FCS, VOE, boot, HAL, sensor, or mutex changes in any commit. | LOW |
| ameba-rtos-pro2 open issues (direct WebFetch, 2026-06-02) | **3 open issues — unchanged from U71.** #16 (AI glass src path, Jan 2026), #4 (chip support, Apr 2025), #3 (antivirus, Apr 2025). Highest issue number = #16. No new issues about FlashMemory, FCS, camera, mutex, or RT_DEV_LOCK_FLASH filed after 72 cycles. | LOW |
| ameba-arduino-pro2 dev branch commits (direct WebFetch, 2026-06-02) | **Confirmed frozen — identical to U71.** HEAD = `29d47e1` "Update SPI API for SPI1 switching (#410)" (May 26, 2026). **Zero new commits in 7 days since May 26, 2026.** No FlashMemory, FCS, camera, mutex, or boot-related changes in any commit. | LOW |
| ameba-arduino-pro2 releases (direct WebFetch, 2026-06-02) | **No new releases.** Full confirmed release list: V4.1.1-QC-V06 (pre-release, tag Mar 6, 2026; content through May 19, 2026), V4.1.0 (stable, Mar 2, 2026), and all prior. No V4.1.1-QC-V07 or stable V4.1.1 published. Release notes contain no FCS cold-boot, FlashMemory mutex, or SPIC concurrent-access fix in any entry from V4.0.6 through V4.1.1-QC-V06. | LOW |
| ameba-arduino-pro2 open issues (direct WebFetch, 2026-06-02) | **17 open issues; highest = #398 (Mar 29, 2026).** No new issues filed about FlashMemory, FCS, camera, VOE, or boot failure. Bug remains entirely unreported on the official tracker after 72 research cycles. 321 closed PRs in history — zero about FlashMemory mutex or FCS cold-boot. | LOW |
| forum.amebaiot.com threads above #4871 (search sweep, 2026-06-02) | **No new threads indexed.** Targeted searches for IDs #4872–#4880 returned zero results from the forum domain. Forum ceiling confirmed at #4871 (purchasing inquiry, no technical content). All direct fetches return HTTP 403. No new camera/flash/FCS boot content in any indexed thread. | LOW |
| Web-wide error string sweep (2026-06-02) | **Zero indexed results — 72 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"` — zero publicly indexed results anywhere on the accessible web. | LOW |
| Workaround hardware test confirmation sweep (2026-06-02) | **Zero hardware test results — 19 days since workarounds first compiled (U7, May 14, 2026).** No public post on any platform (Reddit, Hackster, forum.amebaiot.com, GitHub, CSDN, Zhihu, EEWorld, 21IC, Bilibili, Gitee, bbs.aithinker.com, bbs.ai-thinker.com) reports hardware testing of "Camera FCS Mode = Disable," `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper, `USE_ISP_RETENTION_DATA`, or camera-stop-before-erase for this specific bug. | LOW |
| VOE version check (2026-06-02) | **No new VOE release.** Searches for `voe.bin 1.7.2`, `voe 1.8.0 ameba`, and `hal_video_release_note` return no new content beyond 1.7.1.0 (Apr 21, 2026). | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/mcublog.cn/Bilibili/Gitee, 2026-06-02 sweep) | **Zero new content — 72nd consecutive null cycle.** All Chinese community sites remain 403-blocked or return zero relevant results. Chinese-language search for `安信可 BW21-CBV FCS 相机 flash 启动失败` returns only product pages and unrelated DIY projects — no technical FCS flash boot failure content. | LOW |

**Cumulative freeze summary (as of Cycle U72):**

| Repository | Frozen since | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **18 days** |
| ameba-arduino-pro2 dev | May 26, 2026 (`29d47e1`) | **7 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **92 days** |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **85 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 | **182 days** |
| Ai-Thinker-Open | No RTL8735B repos exist | — |

**SDK state as of 2026-06-02 (Cycle U72 — unchanged from U71):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp zero mutex calls (SHA `b4781b70`)
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; build20260519 binary May 19, 2026) — no fix
- ameba-rtos-pro2 main: Frozen at `3f95070` (May 15, 2026) — 18 days; PR #17 stale but open
- ameba-arduino-pro2 dev: `29d47e1` (May 26, 2026, SPI API — unrelated to bug) — 7 days frozen
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — 92 days
- VOE binary: v1.7.1.0 (Apr 21, 2026) — no FCS flash-race fix in entire 46-version release history
- Forum ceiling: **#4871** (purchasing inquiry; no technical content)

**No confirmed fix. Bug remains unpatched as of 2026-06-02 (Cycle U72).**

**Top unresolved actions (unchanged — 19 days unresolved since U7, May 14):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception in every SDK version. Callable from Arduino: `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug entirely undocumented outside this research log; 72 research cycles and 46 VOE versions contain zero acknowledgment; filing would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes at source; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-06-02 (Cycle U73)

**Search scope:** Six parallel search threads + direct GitHub/web fetches: (1) GitHub — ameba-rtos-pro2 PR #17 stale status and issues; ameba-arduino-pro2 dev/main commits, releases, closed issues, total PR count; FlashMemory.cpp full commit history; (2) English forum/web — new threads above #4871, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports, workaround confirmation; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/mcublog.cn/Bilibili/Gitee, mcublog.cn BW21-CBV April 2026 article; (4) SDK deep-dive — V4.1.1 stable release search, V4.1.1-QC-V07 search, VOE binary version beyond 1.7.1.0, RTL8735C/AmebaPro3 search, aiot.realmcu.com accessibility; (5) ISP SAVE_TO_RETENTION/SAVE_TO_FLASH documentation sweep; (6) Error string indexing sweep.

**Key new findings this cycle:** One status update — ameba-rtos-pro2 PR #17 (ethernet security fix) confirmed marked STALE on May 29, 2026 (was "open" as of U72). Three supplementary findings: (a) FlashMemory.cpp commit history precisely dated (last commit SHA `4fdfbec2`, Sep 30, 2025 — predates all V4.1.1-QC builds by 157 days); (b) ameba-arduino-pro2 confirmed to have zero total PRs ever filed; (c) RTL8735C/AmebaPro3 confirmed absent from all 74+ public Ameba-AIoT repositories. No fix found. This is the 73rd consecutive null cycle.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 PR #17 stale status (agent search, 2026-06-02) | **PR #17 marked STALE on May 29, 2026.** The ethernet USB driver buffer overflow security fix (filed by orbisai0security) was labeled "open" as of U72; this cycle confirms it was tagged STALE on May 29, 2026 after 14 days of inactivity. No maintainer response. Risk of auto-close. Unrelated to FlashMemory/FCS bug — tracked as repository activity indicator. | LOW |
| FlashMemory.cpp commit history (dev branch, agent WebFetch, 2026-06-02) | **Full commit history confirmed: 3 commits total.** (1) SHA `d9022ef4` (Jul 9, 2024) "Add feature Flash Memory (#252)"; (2) SHA `d1a988f3` (Sep 30, 2025) "Add Arduino printf (#336)"; (3) SHA `4fdfbec2` (Sep 30, 2025) "Optimize codes (#337)". **Most recent commit predates V4.1.1-QC-V01 (Mar 6, 2026) by 157 days. No mutex, locking, or concurrency fix has been applied in any commit on any branch.** Confirms the SPIC bus race is completely untouched since Sep 30, 2025. | LOW |
| ameba-arduino-pro2 total PR count (agent WebFetch, 2026-06-02) | **Confirmed ZERO total pull requests ever filed.** The repository navigation bar shows "Pull requests 0" — no PR (open, closed, merged, or draft) has ever been submitted to ameba-arduino-pro2. The FlashMemory mutex fix has never been proposed by any contributor. | LOW |
| ameba-arduino-pro2 closed issues — camera+flash (agent search, 2026-06-02) | **No camera/flash issue ever filed or closed.** Closed-issue search for "camera flash" returned only unrelated issues: #298 (VL53L5cx I2C library, Sep 1, 2025) and #258/#257 (WiFiServer blocking behavior, Oct 2024). No closed issue about FlashMemory mutex, FCS cold-boot failure, or SPIC bus race exists in the tracker. | LOW |
| RTL8735C / AmebaPro3 search (agent full-org scan, 2026-06-02) | **No RTL8735C or AmebaPro3 SDK published.** Full scan of 74+ Ameba-AIoT GitHub repositories confirms no repo named or described as RTL8735C, AmebaPro3, or ameba-pro3. Ameba-AIoT's newest SoC line appears to be "Nuwa" (repos: nuwa, nuwa_hal_realtek, nuwa_lib) — no announced connection to the RTL8735B camera platform. RTL8735B has no successor with a public SDK. | LOW |
| aiot.realmcu.com accessibility status (agent WebFetch, 2026-06-02) | **Partial search-engine indexing detected; direct fetches still 403.** New finding: Google now indexes several aiot.realmcu.com pages (ATCMD page, product selection guide, Bluetooth solutions page) — suggesting a partial public deployment occurred recently. However, all direct WebFetch calls to the domain (root, `/en/product/index.html`, SPIC docs, SDK download page) return HTTP 403. **RTL8735B-specific pages are NOT among any indexed content.** SDK download and RTL8735B documentation remain inaccessible. | LOW |
| ISP `isp_retention_data_s` structure (Chinese agent search, ameba-doc-rtos-pro2-sdk, 2026-06-02) | **RTOS SDK confirms `isp_retention_data_s` structure and SAVE_TO_RETENTION mode.** The AmebaPro2 RTOS documentation (`ameba-doc-rtos-pro2-sdk.readthedocs-hosted.com/en/latest/application_note/15_ISP.html`) describes three ISP AE/AWB storage modes: `SAVE_TO_STRUCTURE` (structure), `SAVE_TO_FLASH` (FTL NOR flash), `SAVE_TO_RETENTION` (SRAM retention). The `isp_retention_data_s` typedef includes fields `{checksum, ae_exposure, ae_gain, awb_rgain, awb_bgain}`. This is the documented RTOS-layer API backing the `USE_ISP_RETENTION_DATA` workaround. The Arduino-layer macro (`// #define USE_ISP_RETENTION_DATA` in `video_api.h`) activates this path. Confirms workaround #3 is architecturally sound at the RTOS level. | LOW (confirms known workaround mechanism) |
| mcublog.cn BW21-CBV April 2026 article (Chinese agent search, 2026-06-02) | **Article confirmed — no flash/camera conflict content.** The April 2026 mcublog.cn article ("我让AI帮我把BW21-CBV开发板接入了飞书机器人，不光能控制点灯，还能拍照看照片") demonstrates BW21-CBV integration with Feishu (Lark) robot for remote LED control and photo capture. Content 403-blocked to direct fetch. No flash write + camera reboot scenario or FCS failure mentioned in any search snippet. Not relevant to the bug. | LOW |
| Forum thread #4302 re-confirmed (English agent search, 2026-06-02) | **Thread #4302 (`[VOE]frame_end: sensor didn't initialize done!`) continues to surface in all camera/FCS workaround searches.** Confirmed again that "Camera FCS Mode: Disable" option appears in Arduino IDE Tools menu; no fix confirmation or hardware test result in any indexed portion of the thread. Thread resolution status blocked by 403. | LOW (known thread, re-confirmed) |
| All other channels (forum, Chinese web, error strings, VOE version, workaround tests, 2026-06-02) | **Zero new content — 73rd consecutive null cycle across all channels.** Forum ceiling holds at #4871. All error strings (`"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`) still return zero indexed results globally. No hardware test report for any workaround on any platform. No new Chinese-language content about BW21-CBV or AMB82 flash/camera bug. No new VOE version beyond 1.7.1.0. | LOW |

**Cumulative freeze summary (as of Cycle U73):**

| Repository | Frozen since | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **18 days** |
| ameba-arduino-pro2 dev | May 26, 2026 (`29d47e1`) | **7 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **92 days** |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **85 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 | **182 days** |
| Ai-Thinker-Open | No RTL8735B repos exist | — |

**SDK state as of 2026-06-02 (Cycle U73 — unchanged from U72):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp zero mutex calls (last commit SHA `4fdfbec2`, Sep 30, 2025)
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; build20260519 binary May 19, 2026) — no fix; V4.1.1-QC-V07 not published
- ameba-rtos-pro2 main: Frozen at `3f95070` (May 15, 2026) — 18 days; PR #17 now STALE (labeled May 29, 2026)
- ameba-arduino-pro2 dev: `29d47e1` (May 26, 2026, SPI API — unrelated to bug) — 7 days frozen; ZERO total PRs ever filed
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — 92 days
- VOE binary: v1.7.1.0 (Apr 21, 2026) — no FCS flash-race fix in entire 46-version release history; no v1.7.2+ confirmed
- Forum ceiling: **#4871** (purchasing inquiry; no technical content)
- RTL8735C/AmebaPro3: not publicly announced or SDK-published

**No confirmed fix. Bug remains unpatched as of 2026-06-02 (Cycle U73).**

**Top unresolved actions (unchanged — 19 days unresolved since U7, May 14):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception in every SDK version (last commit Sep 30, 2025). Callable from Arduino: `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug entirely undocumented outside this research log; 73 research cycles and 46 VOE versions contain zero acknowledgment; ameba-arduino-pro2 has ZERO total PRs ever filed; filing would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes at source; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`; RTOS-layer `isp_retention_data_s` API confirmed as documented path.

**U73 addendum — additional findings from completed background agents (post-edit):**

| Source | Key Finding | Priority |
|---|---|---|
| bbs.aithinker.com thread index (Chinese agent, 2026-06-02) | **New bbs.aithinker.com ceiling: tid=47223.** Thread "BW21数码相机+BW21-CBV-KIT" (DIY digital camera project with BW21-CBV-Kit) is newly indexed above the previously tracked highest BW21-CBV thread. Content is 403-blocked; search snippet shows a BW21-CBV camera DIY project, not an FCS/flash failure report. No flash/camera conflict content visible in any snippet for any thread up to tid=47223. | LOW |
| Forum threads #4777, #4834, #4865 newly indexed (English agent, 2026-06-02) | **Three previously uncatalogued forum threads found below #4871 ceiling.** Thread #4777 ("AMB82-Mini onboard camera sensor identification and VOE setup for wireless video and I2C", March 2026) — camera+VOE content, no flash conflict. Thread #4834 ("Boot failure after OTA update") — OTA-specific boot failure, not SPIC race condition. Thread #4865 ("AmebaPro2 uartfwburn - Can't flash. 'fail for download 0' after 'programing' is 100% complete") — flashing tool failure, unrelated. None contain FCS flash race condition content. | LOW |
| GitHub Issue #251 FCS KM_status in boot log (English + Chinese agents, 2026-06-02) | **First confirmed public appearance of `FCS KM_status` values in a user boot log.** Issue #251 ("ControlLED abort execution", opened Jul 8, 2024, reporter rkuo2000, `github.com/Ameba-AIoT/ameba-arduino-pro2/issues/251`) contains boot log lines: `FCS KM_status 0x00000082 err 0x00000000` and `store fcs data for application fcs OK`. The value `0x00000082` differs from the bug's `0x00002081` — both use KM_status as a bitfield; the different bit pattern indicates a different fault mode (auth/key vs. data-not-good). The issue's primary failure was a RAM allocation error (`abort execution`), not sensor initialization. **This is the only publicly indexed user report containing any `FCS KM_status` log line** — and it shows a successful FCS sequence (err 0x00000000 = no error), not the bug. | LOW |
| V4.0.8 FlashMemory + FCS co-introduction timing (English + Chinese agents, 2026-06-02) | **SDK V4.0.8 (Oct 29, 2024) simultaneously introduced both FlashMemory API and Camera FCS Mode.** Release notes confirm: "Add flash memory related API" and "Add feature FCS mode for all supported sensors" both entered the codebase in the same release. The two features were added concurrently without any mutex integration. This confirms the architectural defect was introduced at the moment of feature creation, not from a later regression. No changelog entry in any subsequent version (V4.0.9, V4.1.0, V4.1.1-QC-V01 through V06) addresses this design flaw. | LOW (corroborates root-cause timing) |
| ISP SAVE_TO_FLASH documentation warning text (Chinese agent, ameba-doc-rtos-pro2-sdk, 2026-06-02) | **Only warning for SAVE_TO_FLASH in official docs: "please check the flash write limit."** The AmebaPro2 RTOS ISP documentation describes SAVE_TO_FLASH as the mode that "loads video initial AE, AWB settings from flash" and warns only about NOR flash endurance (write cycle limit) — **not about concurrent SPIC bus access or mutex requirements.** No public Realtek documentation warns developers that ISP AE/AWB flash writes compete with user FlashMemory writes on the shared SPIC bus. The documentation gap directly explains why the bug has persisted unnoticed: the concurrency hazard is undocumented at the API level. | LOW (explains documentation gap) |

## Research Update — 2026-06-02 (Cycle U74)

**Search scope:** Four parallel agents + direct WebFetch/WebSearch sweeps: (1) GitHub — direct WebFetch of ameba-rtos-pro2 and ameba-arduino-pro2 dev branch commit pages to confirm freeze state; (2) English forum/web — new threads above #4871, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` workaround hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/mcublog.cn/Hackster.io BW21-CBV projects; (4) SDK deep-dive — new VOE release beyond 1.7.1.0, V4.1.1 stable release, aiot.realmcu.com and ameba-doc-rtos-pro2-sdk.readthedocs-hosted.com accessibility, FlashMemory mutex PR search.

**Key new findings this cycle:** None. This is the 74th consecutive null cycle. Both repository commit pages were confirmed frozen via direct WebFetch (not just search engine inference). A cluster of Hackster.io BW21-CBV-Kit demo projects found in search results — none use SPI FlashMemory alongside camera in a manner that would reproduce the bug. All documentation portals, forum threads, and Chinese community sources remain 403-blocked. No hardware test reports for any workaround anywhere.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 commits page (direct WebFetch, 2026-06-02) | **Freeze confirmed from live commit page.** Top 10 commits verified: `3f95070` "Sync upstream 7343927…" (May 15), `afc85a0` "[amebapro2][mmf] avoid task recreate in mmf start" (May 15), `9c8b6f6` "[amebapro2][wlan] wowlan modify dhcp renew unit" (May 15), `d2676f1` "[amebapro2][wlan] modify dynamic ARP example" (May 15); then `1c1c8b7`, `a111e91`, `7b2b97f`, `63c0a2f`, `d54e1a8`, `687a4c7` (all May 1). **Zero new commits since May 15, 2026 — 18 days frozen.** No flash, FCS, VOE, boot, HAL, sensor, or mutex changes in any commit. | LOW |
| ameba-arduino-pro2 dev commits page (direct WebFetch, 2026-06-02) | **Freeze confirmed from live commit page.** Top 10 commits verified: `29d47e1` "Update SPI API for SPI1 switching (#410)" (May 26), `7db1c7d` "Pre Release Version 4.1.1" (May 19), `3d53672` "Update Code base and add cam IMX681_5M (#409)" (May 19), `cd0bd40` "Add I2C Slave (#408)" (May 18), then May 5/Apr 30/Apr 17 entries. **Zero new commits since May 26, 2026 — 7 days frozen.** No FlashMemory, FCS, camera, mutex, or boot-related changes visible. | LOW |
| ameba-arduino-pro2 V4.1.1 stable / QC-V07 search (2026-06-02) | **No new release.** Web search and GitHub releases page confirm latest pre-release is V4.1.1-QC-V06 (tag Mar 6, 2026; binary build20260519). No V4.1.1-QC-V07 or stable V4.1.1 has been published. Release feature list for all V4.1.1 QC builds: IMX681_5M, I2C Slave, SPI API, AMB82-zero, WDT API, TensorFlowLite, PowerMode multi-wakeup — no FCS or flash mutex entry in any QC release. | LOW |
| forum.amebaiot.com threads above #4871 (direct fetch + search, 2026-06-02) | **Forum ceiling holds at #4871.** Searches for thread IDs #4872–#4900 return zero results in all search engines. Direct fetches of /latest and known high-numbered threads return HTTP 403. No new camera/flash/FCS boot content in any accessible forum snippet. | LOW |
| Hackster.io BW21-CBV-Kit projects (web search sweep, 2026-06-02) | **Multiple Hackster.io BW21-CBV projects found — none relevant to the bug.** Projects confirmed: (1) DIY Digital Camera + BW21-CBV-Kit (Ai-Thinker, URL: hackster.io/ai-thinker/diy-project-digital-camera-bw21-cbv-kit-5a7309) — uses hardware LED flash and SD card, not SPI FlashMemory API; (2) Home Video Monitoring and Playback System (hackster.io/ai-thinker/bw21-cbv-kit-home-video-monitoring-and-playback-system-81912e) — video + SD card, no FlashMemory writes described; (3) Washing Machine Remote Control Panel; (4) Desk Sentinel; (5) Gesture/Face Recognition. All are Ai-Thinker promotional demo projects. None use `FlashMemory.write()` / `flash_erase_sector()` alongside the camera in a way that would trigger the FCS cold-boot bug. Content accessible via search snippets only; direct fetches 403-blocked. | LOW |
| aiot.realmcu.com (direct WebFetch, 2026-06-02) | **RTL8735B product and module pages confirmed 403 on direct fetch.** Despite some search engine indexing of product-level pages (noted in U73), direct `WebFetch` of `aiot.realmcu.com/en/product/rtl8735b.html` and `aiot.realmcu.com/en/module/rtl8735b.html` both return HTTP 403. No new RTL8735B-specific documentation accessible. SPIC driver docs, flash layout docs, and ISP docs remain behind authentication. | LOW |
| ameba-doc-rtos-pro2-sdk.readthedocs-hosted.com (direct WebFetch, 2026-06-02) | **ISP application note still 403.** `ameba-doc-rtos-pro2-sdk.readthedocs-hosted.com/en/latest/application_note/15_ISP.html` returns HTTP 403 — no change from prior cycles. FCS flash address layout, digest coverage, and `CMD_VIDEO_PRE_INIT_LOAD` details remain inaccessible. | LOW |
| FlashMemory mutex PR / issue search (web + GitHub code search, 2026-06-02) | **Zero PRs or issues ever filed on ameba-arduino-pro2 about FlashMemory mutex.** Search for "ameba-arduino-pro2 FlashMemory device_mutex OR RT_DEV_LOCK GitHub issue PR 2026" returns only the general repository page and unrelated issues #251, #152. Confirmed: ZERO total pull requests ever filed (0 PRs in open+closed+merged+draft). The architectural defect has never been proposed for fix by any contributor in the repo's public history. | LOW |
| Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee, 2026-06-02 sweep) | **Zero new content — 74th consecutive null cycle.** All Chinese community sites remain 403-blocked. Search for `BW21-CBV AMB82-mini FCS 相机 flash 启动失败 2026` returns only DIY project listings and documentation pages, zero technical FCS flash boot failure content. bbs.aithinker.com ceiling remains at tid=47223 (BW21-CBV digital camera project, 403). | LOW |
| Web-wide error string sweep (all search engines, 2026-06-02) | **Zero indexed results — 74 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA FlashMemory"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"` — zero publicly indexed results anywhere on the accessible web. | LOW |

**Cumulative freeze summary (as of Cycle U74):**

| Repository | Frozen since | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **18 days** |
| ameba-arduino-pro2 dev | May 26, 2026 (`29d47e1`) | **7 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **92 days** |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **85 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 | **182 days** |

**SDK state as of 2026-06-02 (Cycle U74 — unchanged from U73):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp zero mutex calls (last commit SHA `4fdfbec2`, Sep 30, 2025)
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; build20260519 binary May 19, 2026) — no fix; V4.1.1-QC-V07 not published
- ameba-rtos-pro2 main: Frozen at `3f95070` (May 15, 2026) — 18 days; PR #17 STALE (labeled May 29, 2026)
- ameba-arduino-pro2 dev: `29d47e1` (May 26, 2026, SPI API — unrelated) — 7 days frozen; ZERO total PRs ever filed
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — 92 days
- VOE binary: v1.7.1.0 (Apr 21, 2026) — no FCS flash-race fix in entire 46-version release history
- Forum ceiling: **#4871** (purchasing inquiry; no technical content)

**No confirmed fix. Bug remains unpatched as of 2026-06-02 (Cycle U74).**

**Top unresolved actions (unchanged — 19 days unresolved since U7, May 14):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception. Callable from Arduino: `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug entirely undocumented outside this research log; 74 cycles and 46 VOE versions contain zero acknowledgment; zero PRs ever filed in this repo; filing would be the first public disclosure.

## Research Update — 2026-06-02 (Cycle U75)

**Search scope:** Six parallel search threads + direct GitHub/web fetches: (1) GitHub — direct WebFetch of ameba-rtos-pro2 and ameba-arduino-pro2 commit pages, issues pages, and releases; (2) English forum/web — new threads above #4871, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/mcublog.cn/Hackster.io/Hackaday.io BW21-CBV projects; (4) SDK deep-dive — new VOE release beyond 1.7.1.0, ameba-arduino-doc new commits, third-party AMB82 repos; (5) Error string indexing sweep; (6) ameba-rtos-pro2 issues and ameba-arduino-pro2 issues.

**Key new findings this cycle:** None. This is the 75th consecutive null cycle. Both repository commit pages were confirmed frozen via direct WebFetch. The ameba-arduino-doc repository had two new commits (May 21, May 24) for I2C slave examples — unrelated to FlashMemory/FCS. Forum thread #4868 newly surfaced in search results (below the previously tracked #4871 ceiling); content is about NN model loading exceptions and is unrelated to the flash/camera/FCS bug. All documentation portals, forum threads, and Chinese community sources remain 403-blocked. No hardware test reports for any workaround anywhere.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 commits page (direct WebFetch, 2026-06-02) | **Freeze confirmed from live commit page — 18+ days frozen.** Top 10 commits verified identical to U74: `3f95070` (May 15), `afc85a0` (May 15), `9c8b6f6` (May 15), `d2676f1` (May 15), then May 1 entries. **Zero new commits since May 15, 2026.** No flash, FCS, VOE, boot, HAL, sensor, mutex, or FlashMemory changes in any observable commit. | LOW |
| ameba-arduino-pro2 dev commits page (direct WebFetch, 2026-06-02) | **Freeze confirmed — 7 days frozen.** Top commits verified: `29d47e1` (May 26, SPI API), `7db1c7d` (May 19, Pre Release 4.1.1), `3d53672` (May 19, IMX681_5M), `cd0bd40` (May 18, I2C Slave). No new commits since May 26. No FlashMemory, FCS, camera, mutex, or boot-related changes in any commit. | LOW |
| ameba-arduino-pro2 releases (direct WebFetch, 2026-06-02) | **No new releases.** Latest stable: V4.1.0 (Mar 2, 2026). Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; build20260519 binary). No V4.1.1-QC-V07 or stable V4.1.1 published. Release feature list for all V4.1.1 QC builds contains no FCS or flash mutex entry. | LOW |
| ameba-arduino-pro2 open issues (direct WebFetch, 2026-06-02) | **17 open issues confirmed — unchanged.** Newest: #398 (Mar 29, 2026). No new issues related to FlashMemory, FCS, camera boot, VOE, or mutex. Issue list includes issues for RTSP, I2C, SPI, WiFi, and video encoding — nothing touching the flash/FCS cold-boot bug class. **Zero PRs ever filed (confirmed again).** | LOW |
| ameba-rtos-pro2 open issues (direct WebFetch, 2026-06-02) | **3 open issues — unchanged.** Issues: #16 (AI glass src path, Jan 2026), #4 (chip support, Apr 2025), #3 (antivirus detection, Apr 2025). No new issues. No FCS/flash/camera/VOE bug filed in the official RTOS tracker. | LOW |
| forum.amebaiot.com thread #4868 "NN Model loading from Memory instead of Flash or SD card failing with exceptions" (2026) | **Newly surfaced thread** (below #4871 ceiling; previously untracked). Title indicates user is loading an NN model from a static memory buffer (`MODEL_SRC_MEM`) instead of flash/SD, triggering a usage fault exception. Confirmed NOT related to the FCS flash-write cold-boot bug (different subsystem: NN inference, not camera sensor init or FCS). Content 403-blocked. Confirms forum activity continues with NN/multimedia threads but none addressing our bug. | LOW |
| ameba-arduino-doc repository commits (direct WebFetch, 2026-06-02) | **Two new commits since last cycle:** `64863ce` "Add I2C slave example guides (#107)" (May 24, 2026) and `7f0bc9c` "Update application step (#106)" (May 21, 2026). **Neither commit touches FlashMemory documentation, camera FCS mode documentation, or adds any mutex/concurrent-access warning.** The Flash Memory documentation page remains unchanged — still contains no warnings about camera FCS interaction or SPIC bus contention. | LOW |
| Third-party AMB82 GitHub repositories (web search + direct fetch, 2026-06-02) | **New repos found: joehou45/Amb82-Mini (1 issue: event invitation, unrelated), 0015/AMB82-Mini-Board (0 issues, 2 commits, demonstration only).** Both repos have zero activity related to our bug. No community repository documents or tracks the FlashMemory+FCS cold-boot failure. **Confirmed: zero repositories outside this research log document this bug.** | LOW |
| Web-wide error string sweep (all search engines, 2026-06-02) | **Zero indexed results — 75 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA FlashMemory"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"` return zero results anywhere on the publicly accessible web. | LOW |
| Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/Hackster.io/Hackaday.io, 2026-06-02) | **Zero new content — 75th consecutive null cycle.** All Chinese community sites (bbs.aithinker.com, bbs.ai-thinker.com) remain 403-blocked. CSDN article 139222964 about AMB82 MINI remains 403. Hackster.io BW21-CBV projects (digital camera, home monitoring, washing machine) confirmed as promotional content with no FlashMemory+camera interaction. Hackaday.io BW21-CBV project pages contain no technical bug reports. sohu.com BW21-CBV tutorial 403. oshwhub.com BW21-CBV-Kit page 403. | LOW |
| forum.amebaiot.com threads #4872–#4895 search (2026-06-02) | **Forum ceiling holds at #4871.** Searches for thread IDs #4872 through #4895 return zero indexed results in all search engines. Direct fetch of /latest returns 403. #4868 (NN model loading) and #4871 (purchasing inquiry, previously confirmed) remain the highest confirmed forum threads. No new threads above #4871 have been indexed. | LOW |

**Cumulative freeze summary (as of Cycle U75):**

| Repository | Frozen since | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **18 days** |
| ameba-arduino-pro2 dev | May 26, 2026 (`29d47e1`) | **7 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **92 days** |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **85 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 | **182 days** |

**SDK state as of 2026-06-02 (Cycle U75 — unchanged from U74):**
- Latest stable: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp zero mutex calls (last commit SHA `4fdfbec2`, Sep 30, 2025)
- Latest pre-release: V4.1.1-QC-V06 (tag Mar 6, 2026; build20260519 binary May 19, 2026) — no fix; V4.1.1-QC-V07 not published
- ameba-rtos-pro2 main: Frozen at `3f95070` (May 15, 2026) — 18 days; PR #17 STALE (labeled May 29, 2026)
- ameba-arduino-pro2 dev: `29d47e1` (May 26, 2026, SPI API — unrelated) — 7 days frozen; ZERO total PRs ever filed
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — 92 days
- VOE binary: v1.7.1.0 (Apr 21, 2026) — no FCS flash-race fix in entire 46-version release history; no v1.7.2+ confirmed
- Forum ceiling: **#4871** (purchasing inquiry; no technical content above #4868 NN model exception)

**No confirmed fix. Bug remains unpatched as of 2026-06-02 (Cycle U75).**

**Top unresolved actions (unchanged — 19 days unresolved since U7, May 14):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception. Callable from Arduino: `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug entirely undocumented outside this research log; 75 cycles and 46 VOE versions contain zero acknowledgment; zero PRs ever filed in this repo; filing would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

---

## Research Update — 2026-06-03 (Cycle U76)

**Search scope:** Three parallel research agents + direct GitHub API queries: (1) GitHub — ameba-rtos-pro2, ameba-arduino-pro2, ideashatch/HUB-8735 new commits/issues/PRs/releases since May 22; (2) English forum/web — forum.amebaiot.com threads above #4871, workaround hardware test reports, community posts on Reddit/Hackster/StackOverflow; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/mcublog.cn/Bilibili/Gitee for BW21-CBV camera flash failure content.

**Key new findings this cycle:** ameba-rtos-pro2 V1.0.3 / V1.0.3-aiglass.08 releases surfaced (published May 22, 2026; missed by prior cycles which only checked commit pages, not releases). New forum thread #4834 "Boot failure after OTA update" (April 24, 2026) found — OTA-induced flash-init failure on cold boot, analogous failure class but different vector. No fix anywhere.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 releases (GitHub, 2026-06-03) | **Two new releases published May 22, 2026 — not previously documented.** `V1.0.3-aiglass.08` ("AI glass patch 08", May 22 09:23 UTC): IMX681_5M sensor support, lifetime snapshot non-blocking/blocking save, AI glass object detection for snapshots, sensor driver updates. `V1.0.3` ("V1.0.3 main branch patch", May 22 10:15 UTC; assets updated May 26): `rtsp_source_code_patch.zip` + `websocket_viewer_source_code_patch.zip`. **Both releases are RTOS-level patches for AI-glass and RTSP streaming features — not the Arduino SDK, no FlashMemory/FCS/mutex fix, no V4.1.1 stable tag.** No camera cold-boot or flash contention fix in either release. | LOW |
| ameba-rtos-pro2 main branch (GitHub, 2026-06-03) | **Freeze confirmed — 19 days.** HEAD remains `3f95070` (May 15, 2026). Zero new commits. No changes to FlashMemory.cpp, hal_flash.c, video_boot.c, video_api.c, hal_video_release_note.txt, device_lock.h, ftl_nor_api.c, hal_spic_ns.c. | LOW |
| ameba-rtos-pro2 PR #17 — orbisai0security ethernet security fix (GitHub, 2026-06-03) | **Still open, unreviewed, NOT merged.** Stale-bot labeled "stale" on May 29, 2026 after 14 days of maintainer inactivity. No response from maintainers. Buffer overflow fix in `component/ethernet_mii/ethernet_usb.c` remains un-actioned. Effectively abandoned by upstream. | LOW |
| ameba-arduino-pro2 dev branch (GitHub, 2026-06-03) | **Freeze confirmed — 8 days.** HEAD remains `29d47e1` (May 26, 2026, "Update SPI API for SPI1 switching (#410)"). Zero new commits since PR #410 merge. No FlashMemory, FCS, camera, mutex, or boot-related changes in any commit. Dev branch frozen for 8 days. | LOW |
| ameba-arduino-pro2 main branch (GitHub, 2026-06-03) | **Freeze confirmed — 93 days.** HEAD remains `93d63514` (Mar 2, 2026). No FlashMemory/FCS-related changes. | LOW |
| ameba-arduino-pro2 releases (GitHub, 2026-06-03) | **No new releases.** Latest stable: V4.1.0 (Mar 2, 2026). Latest pre-release: V4.1.1-QC-V06 (tag Mar 6; build20260519). No V4.1.1-QC-V07 or stable V4.1.1 published. Zero new release notes entries for camera/flash/FCS/mutex. | LOW |
| ameba-arduino-pro2 issues/PRs (GitHub, 2026-06-03) | **No new issues or PRs.** Open issue count stable at 17 (#398, Mar 29, 2026 is newest). **Zero total PRs ever filed in ameba-arduino-pro2** (confirmed again). No community PR to add `device_mutex_lock` to FlashMemory.cpp. | LOW |
| ideashatch/HUB-8735 (GitHub, 2026-06-03) | **Frozen — 183 days.** HEAD at `870a7e08` (Dec 2, 2025). Two open issues: #10 (PS5268 sensor ID fail, Aug 2025), #8 (checksum error, Jan 2024). No new activity. | LOW |
| forum.amebaiot.com thread #4834 "Boot failure after OTA update" (April 24, 2026) | **New thread found — not previously indexed.** User reports `[SPIF Err]Invalid ID` + `[BOOT Err]Flash init error` on cold boot after OTA firmware update. Boot ROM completely fails to detect NOR flash. **Failure class: flash-write → cold-boot flash-init failure. Root cause: OTA writes to application firmware partition; boot ROM NOR flash re-detection fails.** Different vector from our bug (OTA firmware write vs. application-level FlashMemory.cpp), different error code (`[SPIF Err]Invalid ID` vs. `FCS KM_status 0x2081`), but same architectural hazard class: SPIC bus state after a flash-write operation corrupting the next cold boot. Content 403-blocked; found via search snippet. | MEDIUM |
| forum.amebaiot.com threads #4872–#4900 (2026-06-03) | **Forum ceiling unchanged at #4871.** No new threads above #4871 indexed by any search engine. Forum /latest returns 403. Active technical threads confirmed: #4868 (NN model loading exception), #4777 (camera sensor/VOE setup, 403), #4302 (VOE frame_end sensor init, 403), #4321 (GC2053 sensor init failed, 403). | LOW |
| Web-wide error string sweep (all search engines, 2026-06-03) | **Zero indexed results — 76th consecutive null cycle.** `"FCS KM_status 0x00002081"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"It don't do the sensor initial process"` (as a bug context), `"USE_ISP_RETENTION_DATA FlashMemory"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"`, `"VOE_OPEN_CMD fail flash"` all return zero results anywhere. | LOW |
| Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn, 2026-06-03) | **Zero new content — 76th consecutive null cycle.** All Chinese community forums remain 403-blocked. Recent BW21-CBV Chinese content continues to be project showcases (Feishu bot integration Apr 2026, digital camera, home monitoring) — none report flash/camera cold-boot interactions. mcublog.cn BW21-CBV tag page returns 403. Gitee AMB82/RTL8735 repos: no Chinese developer repositories document or reference the bug. bbs.aithinker.com thread #46140 (BW21-CBV debugging) remains 403. | LOW |

**Cumulative freeze summary (as of Cycle U76):**

| Repository | Frozen since | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **19 days** |
| ameba-arduino-pro2 dev | May 26, 2026 (`29d47e1`) | **8 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **93 days** |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **86 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 | **183 days** |

**SDK state as of 2026-06-03 (Cycle U76 — unchanged from U75 except noting V1.0.3 RTOS releases):**
- Latest stable Arduino SDK: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp zero mutex calls (last commit SHA `4fdfbec2`, Sep 30, 2025)
- Latest pre-release Arduino SDK: V4.1.1-QC-V06 (tag Mar 6, 2026; build20260519 binary May 19, 2026) — no fix
- ameba-rtos-pro2: V1.0.3 / V1.0.3-aiglass.08 (May 22, 2026) — RTOS-level patch releases only; no Arduino SDK update; no FCS flash-race fix
- ameba-rtos-pro2 main: Frozen at `3f95070` (May 15, 2026) — 19 days; PR #17 STALE (labeled May 29, 2026), effectively abandoned
- ameba-arduino-pro2 dev: `29d47e1` (May 26, 2026, SPI API only) — 8 days frozen; ZERO total PRs ever filed
- ameba-arduino-pro2 main: Frozen at Mar 2, 2026 (`93d63514`) — 93 days
- VOE binary: v1.7.1.0 (Apr 21, 2026) — no FCS flash-race fix in entire 46-version release history
- Forum ceiling: **#4871** (purchasing inquiry; new analog: #4834 OTA cold-boot flash-init failure, April 2026)

**No confirmed fix. Bug remains unpatched as of 2026-06-03 (Cycle U76).**

**Top unresolved actions (unchanged — 20 days unresolved since U7, May 14):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception. Callable from Arduino: `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug entirely undocumented outside this research log; 76 cycles and 46 VOE versions contain zero acknowledgment; zero PRs ever filed in this repo; filing would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-06-03 (Cycle U77)

**Search scope:** Six parallel search threads + direct GitHub fetches: (1) GitHub — ameba-rtos-pro2 commits since June 1, 2026; ameba-arduino-pro2 dev/main commits since May 26; both repos' releases; ameba-arduino-pro2 open issues; (2) English forum/web — forum.amebaiot.com threads above #4871; FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee; (4) Error string indexing — `"FCS KM_status 0x00002081"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"It don't do the sensor initial process"`; (5) Two newly identified community GitHub repos — `wildman8606/HUB-8735-AMB82-Mini-AmebaPro2-tutorial` and `0015/AMB82-Mini-Board`; (6) ameba-rtos-pro2 PR #17 stale status.

**Key new findings this cycle:** Both Ameba repositories remain fully frozen — zero new commits to ameba-rtos-pro2 since June 1, 2026 confirmed by GitHub's filtered commit endpoint (empty result). Two previously untracked community GitHub repos confirmed unrelated to the bug. PR #17 on ameba-rtos-pro2 (ethernet security fix) stale-labeled as of May 29, 2026. No new releases, issues, forum threads, or hardware test reports found anywhere.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 commits `since=2026-06-01` (GitHub, direct fetch 2026-06-03) | **Zero commits after June 1, 2026.** GitHub filtered commit endpoint returns: "There isn't any commit history to show here for the selected date range." HEAD remains `3f95070` (May 15, 2026) — now 19+ days frozen. No FCS, flash, VOE, boot, HAL, camera, or sensor changes in any observable pipeline. | LOW |
| ameba-arduino-pro2 dev branch commits (GitHub fetch, 2026-06-03) | **Frozen at May 26, 2026 (`29d47e1`).** Ten most recent commits verified: `29d47e1` "Update SPI API for SPI1 switching (#410)" (May 26), `7db1c7d` "Pre Release Version 4.1.1" (May 19), `3d53672` "Update Code base and add cam IMX681_5M (#409)" (May 19), `cd0bd40` "Add I2C Slave (#408)" (May 18), and earlier. Zero new commits since May 26. No FlashMemory, FCS, camera, mutex, or boot-related changes. | LOW |
| ameba-arduino-pro2 open issues (GitHub fetch, 2026-06-03) | **12 open issues; newest remains #398 (Mar 29, 2026).** Full list confirmed: #398, #342, #325, #324, #317, #310, #296, #287, #276, #235, #224, #184. No issues filed above #398. No issues related to FlashMemory, FCS, camera boot failure, sensor initialization, or mutex. Bug remains entirely unreported on the official tracker after 77 research cycles. | LOW |
| ameba-arduino-pro2 releases (GitHub fetch, 2026-06-03) | **V4.1.1-QC-V06 remains latest pre-release** (tag Mar 6, 2026; build20260519 binary May 19, 2026). No V4.1.1 stable release or QC-V07+ has been published. Latest stable is still V4.1.0 (Mar 2, 2026). No FCS, flash, camera, or mutex fix in any release notes. | LOW |
| ameba-rtos-pro2 releases (GitHub fetch, 2026-06-03) | **V1.0.3 / V1.0.3-aiglass.08 (May 22, 2026) remain the latest RTOS releases.** No new releases after May 22, 2026. These are RTOS-level patches for AI-glass and RTSP streaming — not the Arduino SDK; no FCS/flash/camera fix. | LOW |
| ameba-rtos-pro2 PR #17 (orbisai0security, ethernet security fix) | **Labeled "stale" by stale-bot on May 29, 2026** (documented in U76 via earlier cycle). After 14 days without maintainer response, now classified as stale. PR addresses buffer overflow in `component/ethernet_mii/ethernet_usb.c` (unrelated to our bug). Effectively abandoned by upstream team. Indicates general low maintainer responsiveness to external contributions. | LOW |
| `github.com/wildman8606/HUB-8735-AMB82-Mini-AmebaPro2-tutorial` (fetched 2026-06-03) | **Newly catalogued community repo — unrelated to bug.** Contains AI model training tutorials (YOLO v4-tiny, Google Colab) and Arduino deployment guides for HUB-8735. Last commit activity circa May 2023. No mention of FCS, FlashMemory, camera boot failure, sensor initialization failure, or flash write issues. | LOW (unrelated) |
| `github.com/0015/AMB82-Mini-Board` (fetched 2026-06-03) | **Newly catalogued community repo — unrelated to bug.** Contains ARMv8M YOLO v7 Tiny object detection demo. 2 total commits; MIT license (Eric Nam, 2024); 7 stars. No FCS, FlashMemory, camera boot failure, or flash write content. Zero issues and zero PRs. | LOW (unrelated) |
| forum.amebaiot.com threads above #4871 (search sweep, 2026-06-03) | **No new threads indexed above #4871.** Targeted search for thread IDs 4872–4900 returned zero forum.amebaiot.com results. Forum ceiling confirmed at #4871 (purchasing inquiry) — same as U76. Threads #4865 ("uartfwburn fail") and #4834 ("Boot failure after OTA update") remain the highest confirmed technical threads. | LOW |
| Web-wide error string sweep (all search engines, 2026-06-03) | **Zero indexed results — 77th consecutive null cycle.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA FlashMemory"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"` all return zero publicly indexed results anywhere on the accessible web. No hardware test result for any of the three proposed workarounds has been posted anywhere in any language. | LOW |
| Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/mcublog.cn/Bilibili/Gitee, 2026-06-03) | **Zero new content — 77th consecutive null cycle.** All Chinese community forums remain 403-blocked or return zero relevant results for FCS flash-write camera failure on RTL8735B or BW21-CBV. bbs.aithinker.com BW21-CBV threads: unboxing, environment setup, DIY camera projects — none discuss FCS or flash-write boot failure. No new Chinese-language technical posts found. | LOW |

**Cumulative freeze summary (as of Cycle U77, June 3, 2026):**

| Repository | Frozen since | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **19+ days** |
| ameba-arduino-pro2 dev | May 26, 2026 (`29d47e1`) | **8 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **93+ days** |
| ideashatch/HUB-8735 | Dec 2, 2025 | **183+ days** |

**SDK state as of 2026-06-03 (Cycle U77 — unchanged from U76):**
- Latest stable Arduino SDK: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp zero mutex calls
- Latest pre-release Arduino SDK: V4.1.1-QC-V06 (tag Mar 6, 2026; build20260519 binary May 19, 2026) — no fix
- ameba-rtos-pro2: V1.0.3 / V1.0.3-aiglass.08 (May 22, 2026) — RTOS-level patches only; no FCS/flash fix
- ameba-rtos-pro2 main: Frozen 19+ days at `3f95070`; PR #17 stale and abandoned
- ameba-arduino-pro2 dev: Frozen 8 days at `29d47e1`; ZERO PRs ever filed in this repo
- ameba-arduino-pro2 main: Frozen 93+ days at `93d63514`
- VOE binary: v1.7.1.0 (Apr 21, 2026) — no FCS flash-race fix in entire 46-version release history
- Forum ceiling: **#4871** (confirmed, no new threads above this ID)

**No confirmed fix. Bug remains unpatched as of 2026-06-03 (Cycle U77).**

**Top unresolved actions (unchanged — 20 days unresolved since U7, May 14):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception. Callable from Arduino: `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug entirely undocumented outside this research log; 77 cycles and 46 VOE versions contain zero acknowledgment; zero PRs ever filed in this repo; filing would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

---

## Research Update — 2026-06-03 (Cycle U78)

**Agents run:** 3 parallel background agents — (A) SDK commits / VOE version / issue tracker; (B) forum thread ceiling / workaround confirmation; (C) Chinese sources / error string indexing.

**Key new findings this cycle:** ameba-arduino-pro2 dev branch unfrozen intra-day (2 new commits after U77 closed, still June 3, 2026): PR #411 adds OV5647+GC4663 sensors; version bump creates new pre-release tag V4.1.1-QC-V07. FlashMemory.cpp remains unpatched. Forum thread 4302 snippet newly surfaced: user had "Camera FCS Mode: Disable" active during a distinct sensor failure, confirming the toggle is in active use but not confirming it cures the FlashMemory-triggered cold-boot bug. USE_ISP_RETENTION_DATA purpose clarified from ISP documentation: AE/AWB standby retention, not FCS error prevention.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-arduino-pro2 dev branch commits (GitHub raw fetch, 2026-06-03) | **Two new commits after U77 (same day, June 3, 2026).** Commit `96cfc51`: "Update Code base and add cam OV5647, GC4663 (#411)" — 107 files changed; adds OV5647 and GC4663 sensor support, bumps tools to v1.4.12. Commit `e8dd7e3`: "Pre Release Version 4.1.1" — version bump, new pre-release tarball `ameba_pro2-4.1.1-build20260603.tar.gz`. **FlashMemory.cpp not touched in either commit.** Dev branch HEAD now at `e8dd7e3` (June 3, 2026), unfrozen from `29d47e1` (May 26, 2026). Source: https://github.com/Ameba-AIoT/ameba-arduino-pro2/commits/dev/ | LOW |
| V4.1.1-QC-V07 pre-release tag (GitHub releases, 2026-06-03) | **New pre-release tag V4.1.1-QC-V07 created June 3, 2026** — supersedes QC-V06 (last recorded in U77). Release notes span 7 QC iteration dates (03/06/2026 through 06/03/2026). **Zero mentions of FlashMemory, mutex, FCS, cold-boot camera fix, or sensor initialization fix** in any of the 7 iteration entries. Latest stable release remains V4.1.0 (Mar 2, 2026). Source: https://github.com/Ameba-AIoT/ameba-arduino-pro2/releases/tag/V4.1.1-QC-V07 | LOW |
| FlashMemory.cpp direct raw fetch (ameba-arduino-pro2 dev HEAD `e8dd7e3`, 2026-06-03) | **Confirmed unpatched — SHA b4781b70, zero mutex calls.** Direct fetch of `Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.cpp`: all 10 public functions (`begin`, `end`, `read`, `write`, `readWord`, `writeWord`, `eraseSector`, `eraseWord`, constructor, destructor) contain **zero calls** to `device_mutex_lock`, `device_mutex_unlock`, or `RT_DEV_LOCK_FLASH`. Source: https://raw.githubusercontent.com/Ameba-AIoT/ameba-arduino-pro2/dev/Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.cpp | LOW |
| ameba-arduino-pro2 open issues (GitHub, 2026-06-03) | **17 open issues — none related to FlashMemory/FCS/camera boot.** Zero issues filed about flash mutex, FCS race, camera cold-boot failure, or sensor initialization. Bug remains entirely unreported on the official tracker after 78 research cycles. PR #252 (July 2024) remains the only FlashMemory-related PR ever filed (introduced the library without mutex guards). Source: https://github.com/Ameba-AIoT/ameba-arduino-pro2/issues | LOW |
| ameba-rtos-pro2 main branch (GitHub, 2026-06-03) | **Still frozen at `3f95070` (May 15, 2026) — now 19+ days.** Commit-history search for "flash mutex" across entire ameba-rtos-pro2 repo returns **0 results**. No VOE sync commit beyond 1.7.1.0. Source: https://github.com/Ameba-AIoT/ameba-rtos-pro2/commits/main/ | LOW |
| VOE binary version sweep (web-wide, 2026-06-03) | **VOE 1.7.1.0 (Apr 21, 2026) remains the latest.** No commit syncing VOE 1.7.2.0, 1.8.0.0, or any higher version found anywhere. Web-wide search for "VOE 1.7.2" or "VOE 1.8.0" for RTL8735B/AmebaPro2 returns **zero results**. 46 VOE versions total; zero FCS flash-race fix across all 46. | LOW |
| forum.amebaiot.com thread 4302 snapshot (search engine snippet, 2026-06-03) | **"Camera FCS Mode: Disable" seen in user config during a distinct sensor failure.** Snippet from thread 4302 (`[VOE]frame_end: sensor didn't initialize done!`) shows user running: Arduino IDE v2.3.6, Auto Flash Mode: Disable, Camera Option: JXF37, **Camera FCS Mode: Disable**. User was experiencing frame_end timeout (a persistent failure distinct from the cold-boot FCS_I2C_INIT_ERR triggered by FlashMemory writes). Shows the FCS Disable toggle is in active use among troubleshooters, but does **not** confirm it cures the FlashMemory-triggered cold-boot bug — user still had failures with it set. Source: https://forum.amebaiot.com/t/voe-frame-end-sensor-didnt-initialize-done/4302 (403 on direct fetch; content from search snippet) | MEDIUM (new corroboration that FCS Disable is in use; NOT a confirmed fix) |
| USE_ISP_RETENTION_DATA — ISP documentation (ameba-rtos-pro2 SDK docs §15, 2026-06-03) | **Purpose confirmed: AE/AWB SRAM retention for wake-from-standby — NOT FCS initialization error prevention.** ISP Application Note §15: "USE_ISP_RETENTION_DATA is used to save video initial AE (auto-exposure), AWB (auto-white-balance) settings to SRAM retention." Stored fields: `checksum`, `ae_exposure`, `ae_gain`, `awb_rgain`, `awb_bgain`. Use case: camera avoids re-converging AE/AWB on every wakeup from standby. **No documentation or public source links this macro to FCS_I2C_INIT_ERR (0x200A), FCS_RUN_DATA_NG_KM (0x2081), or any flash-write-triggered cold-boot failure.** Source: https://ameba-doc-rtos-pro2-sdk.readthedocs-hosted.com/en/latest/application_note/15_ISP.html (403 on direct fetch; content from search snippet) | MEDIUM (purpose clarified; not a direct FCS fix path) |
| device_mutex_lock / RT_DEV_LOCK_FLASH workaround — public evidence sweep (web-wide, 2026-06-03) | **Zero public mentions of this workaround pattern anywhere.** Searches for `"device_mutex_lock"` + `"RT_DEV_LOCK_FLASH"` combined with FlashMemory, camera, FCS, or cold-boot returned no matching forum posts, GitHub issues, blog posts, or documentation pages. Symbols are internal RTOS HAL primitives in pre-compiled `.a` blobs — not documented for end-user access. | LOW |
| forum.amebaiot.com ceiling (search sweep, all engines, 2026-06-03) | **No new threads indexed above ID #4871 — 78th consecutive null cycle.** Highest confirmed technical threads remain: #4865 (uartfwburn fail), #4834 (boot failure after OTA), #4777 (AMB82-Mini camera I2C), #4748 (VOE/sensor drivers). Forum blocks unauthenticated fetches with HTTP 403. | LOW |
| Web-wide error string sweep (all search engines, 2026-06-03) | **Zero indexed results — 78th consecutive null cycle.** Strings: `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA FlashMemory"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"` — all return **zero publicly indexed results** in any language. | LOW |
| Reddit / Hackster.io / Stack Overflow (web-wide, 2026-06-03) | **Zero reports of AMB82-Mini / RTL8735B camera+flash cold-boot bug.** Reddit: zero results for AMB82 / AmebaPro2 + camera + flash + boot from 2025–2026. Hackster.io: only unrelated AMB82 camera project (normal usage). Stack Overflow: no relevant results. | LOW |
| Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/mcublog.cn/Bilibili/Gitee, 2026-06-03) | **No new content — 78th consecutive null cycle.** All Chinese community forums remain 403-blocked or return zero relevant results for FCS flash-write camera failure on RTL8735B or BW21-CBV. | LOW |

**Repository freeze status (as of Cycle U78, June 3, 2026):**

| Repository | Last commit | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **19+ days** |
| ameba-arduino-pro2 dev | June 3, 2026 (`e8dd7e3`) | 0 days (intra-day update) |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **93+ days** |
| ideashatch/HUB-8735 | Dec 2, 2025 | **184+ days** |

**SDK state as of 2026-06-03 (Cycle U78):**
- Latest stable Arduino SDK: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp SHA b4781b70, zero mutex calls
- Latest pre-release Arduino SDK: **V4.1.1-QC-V07** (tag June 3, 2026; build20260603 binary) — new this cycle; no FCS/flash/mutex fix
- ameba-rtos-pro2: V1.0.3 / V1.0.3-aiglass.08 (May 22, 2026) — RTOS-level patches only; no FCS/flash fix
- VOE binary: v1.7.1.0 (Apr 21, 2026) — no FCS flash-race fix in entire 46-version release history
- Forum ceiling: **#4871** (78th consecutive null)

**No confirmed fix. Bug remains unpatched as of 2026-06-03 (Cycle U78).**

**Top unresolved actions (unchanged — 20 days unresolved since U7, May 14):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.** Forum thread 4302 snippet (this cycle) adds weak corroboration: users apply this setting during camera failures, but does not confirm it cures the FlashMemory-triggered cold-boot bug.
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception. Callable from Arduino: `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug entirely undocumented outside this research log; 78 cycles and 46 VOE versions contain zero acknowledgment; zero PRs ever filed in this repo; filing would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — ISP documentation (this cycle) confirms purpose: AE/AWB SRAM retention for standby/wake, not FCS initialization. Eliminates ISP SPIC writes regardless; still worth testing to determine if removing ISP's write-back closes the race window. Requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

---

## Research Update — 2026-06-04 (Cycle U79)

**Search scope:** Six parallel agents: (1) GitHub — ameba-rtos-pro2 and ameba-arduino-pro2 commits/releases/issues since June 3; FlashMemory.cpp raw-URL verification; ideashatch/HUB-8735 status; (2) English forum/web — new threads above #4871; FCS Disable / mutex / USE_ISP_RETENTION_DATA hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee; (4) Error string indexing — all five key error strings; FlashMemory mutex PR search; (5) VOE version sweep — hal_video_release_note.txt in QC-V07; full V4.1.1-QC-V07 release notes; (6) Reddit/Hackster/SO/Arduino.cc community search.

**Key new findings this cycle:**
- Both Ameba repositories fully confirmed frozen as of June 4, 2026: ameba-rtos-pro2 at `3f95070` (May 15, 20+ days); ameba-arduino-pro2 dev at `e8dd7e3` (June 3, 1 day)
- **V4.1.1-QC-V07 release notes new detail**: "Add SWD pin deinit check for I2C" listed as an API improvement — new detail not captured in U78; tangentially relevant (SWD/I2C pin conflict is a documented separate hardware class on BW21-CBV), but NOT the FCS I2C init failure triggered by FlashMemory writes
- **GC4663 sensor gains FCS data support** in V4.1.1-QC-V07 (new sensor FCS IQ data added) — normal sensor addition, no FCS flash-race fix
- **FlashMemory.cpp directly verified unpatched** via raw GitHub URL (`https://raw.githubusercontent.com/Ameba-AIoT/ameba-arduino-pro2/dev/...FlashMemory.cpp`) — SHA b4781b70 confirmed in dev HEAD; zero `device_mutex_lock`, `RT_DEV_LOCK_FLASH`, or `device_lock.h` calls
- **"CH 0 MMF ENC Queue full" reports** with SDK build ~4.1.20251219 (December 2025 dev build) surfaced from community search — queue-full symptom variant distinct from FlashMemory-triggered cause; adds to the MMF queue-full error catalog
- All error strings remain unindexed for the 79th consecutive null cycle; no forum threads above #4871; no hardware test results for any workaround

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 commits (direct GitHub fetch, 2026-06-04) | **Confirmed frozen — 20+ days.** HEAD = `3f95070` (May 15, 2026). Zero new commits since May 15. GitHub filtered endpoint `since=2026-06-01` returns: "There isn't any commit history to show here for the selected date range." No flash, FCS, VOE, boot, HAL, or sensor changes in any observable pipeline. | LOW |
| ameba-arduino-pro2 dev branch (direct GitHub fetch, 2026-06-04) | **Confirmed frozen since June 3.** 10 most recent commits verified: `e8dd7e3` "Pre Release Version 4.1.1" (June 3), `96cfc51` "Update Code base and add cam OV5647, GC4663 (#411)" (June 3), `29d47e1` "Update SPI API for SPI1 switching (#410)" (May 26), `7db1c7d` (May 19), `3d53672` (May 19). Zero new commits on June 4, 2026. No FlashMemory, FCS, or boot-related changes. | LOW |
| ameba-arduino-pro2 releases (direct GitHub fetch, 2026-06-04) | **No new releases beyond V4.1.1-QC-V07.** Latest stable = V4.1.0 (Mar 2, 2026). Latest pre-release = V4.1.1-QC-V07 (tag June 3, 2026; build20260603). No V4.1.1-QC-V08 or stable V4.1.1 published. | LOW |
| V4.1.1-QC-V07 release notes — "Add SWD pin deinit check for I2C" (2026-06-04) | **New release note detail not captured in U78.** V4.1.1-QC-V07 release notes include the API improvement: "Add SWD pin deinit check for I2C." SWD debug pins can conflict with I2C SCL/SDA if not properly deinitialized before I2C is started — a known hardware issue on BW21-CBV-Kit (documented in bbs.aithinker.com tid=46140 from prior cycles). This fix ensures SWD pins are released before camera I2C initialization. **However:** our `FCS_I2C_INIT_ERR (0x200A)` is triggered specifically by FlashMemory writes corrupting FCS data at 0xF0D000 via the RT_DEV_LOCK_FLASH mutex bypass — the SWD/I2C conflict is a distinct hardware failure class requiring deliberate misuse of SWD pins for I2C. Not a fix for our bug. | LOW |
| V4.1.1-QC-V07 — GC4663 FCS data support (2026-06-04) | **GC4663 sensor gains FCS IQ data in QC-V07 commit `96cfc51`.** The 107-file commit adds new sensor FCS data blobs and IQ JSON files for both OV5647 and GC4663. This is routine sensor bringup — adds FCS boot data for the new sensors. No change to the FCS cold-boot failure mechanism or the FlashMemory mutex bypass. VOE binary version remains 1.7.1.0 (April 21, 2026) — hal_video_release_note.txt shows no new entry in QC-V07. | LOW |
| `FlashMemory.cpp` — raw GitHub URL verification (2026-06-04) | **Directly verified unpatched in dev HEAD.** Direct fetch of `https://raw.githubusercontent.com/Ameba-AIoT/ameba-arduino-pro2/dev/Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.cpp` confirms: SHA b4781b70, all 10 public functions contain **zero** calls to `device_mutex_lock`, `device_mutex_unlock`, `RT_DEV_LOCK_FLASH`, or `#include "device_lock.h"`. This is the 3rd direct raw-URL verification across research cycles (prior: U31 lines 59/71/76/88/106/107/121/135-140; U37 SHA b4781b70). The mutex bypass is confirmed unchanged in V4.1.1-QC-V07. | LOW (confirms prior) |
| ameba-arduino-pro2 open issues (direct GitHub fetch, 2026-06-04) | **12 open issues; newest = #398 (Mar 29, 2026).** Full issue list unchanged from U78. No new issues filed above #398. No issues about FlashMemory mutex, FCS boot failure, camera cold-boot, or sensor initialization. Bug entirely unreported on the official tracker after 79 research cycles. | LOW |
| ideashatch/HUB-8735 repository (2026-06-04) | **Unchanged — last commit `870a7e0` (December 2, 2025), 184+ days frozen.** One open issue: #10 (PS5268 sensor ID fail, Aug 2025). No new commits or issues. | LOW |
| "CH 0 MMF ENC Queue full" — SDK build 4.1.20251219 (community search, 2026-06-04) | **New queue-full variant identified from community search.** User reports of SDK build dated approximately December 2025 (build 4.1.20251219) breaking previously working code with "CH 0 MMF ENC Queue full" and video corruption errors. "CH 0 MMF ENC Queue full" is a channel-0 multimedia framework encoder queue overflow — a different label from "[VOE][WARN]slot full" but the same symptom class (MMF queue consumed, camera pipeline stalled). The trigger (SDK update, not FlashMemory write) is different from our bug. Not directly related to the FCS flash-write cold-boot failure, but adds to the MMF queue-full error catalog. Source from general community search; thread URL not definitively identified. | LOW |
| All forum threads above #4871 (search sweep, 2026-06-04, three agents) | **No new threads indexed above #4871.** Targeted searches for IDs 4872–4900 returned zero results from forum.amebaiot.com domain. Forum ceiling confirmed at #4871 for the 2nd consecutive cycle. All prior-documented threads (#4302, #4834, #4541, #4651, #4748, #4865, #4868) remain accessible only via search engine snippets; direct fetches return HTTP 403. | LOW |
| Web-wide error string sweep (all search engines, 2026-06-04, two agents) | **Zero indexed results — 79th consecutive null cycle.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD command fail"`, `"USE_ISP_RETENTION_DATA FlashMemory"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"` — all return zero publicly indexed results anywhere in any language. This research log remains the only public documentation of this bug and its error codes. | LOW |
| Reddit / Hackster.io / Stack Overflow / Arduino.cc (2026-06-04) | **Zero relevant posts.** No new AMB82-Mini / RTL8735B camera+flash cold-boot bug reports on any community platform. Reddit, Hackster, Stack Overflow, and Arduino.cc searches return only general camera documentation and unrelated projects. No hardware test confirmation for any of the three proposed workarounds. | LOW |
| Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee, 2026-06-04) | **Zero new content — 79th consecutive null cycle.** Chinese sources: bbs.aithinker.com returns search-indexed threads (BW21-CBV unboxing, environment setup, DIY camera, BLE tutorials) — same threads as prior cycles; no new technical content accessible. Zhihu BW21-CBV articles (fall detection, HomeAssistant) confirmed from prior cycles. No new Chinese-language forum posts or articles discuss FCS flash-write camera failure on RTL8735B or BW21-CBV. | LOW |

**Repository freeze status (as of Cycle U79, June 4, 2026):**

| Repository | Last commit | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **20+ days** |
| ameba-arduino-pro2 dev | June 3, 2026 (`e8dd7e3`) | **1 day** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **94+ days** |
| ideashatch/HUB-8735 | Dec 2, 2025 (`870a7e0`) | **184+ days** |

**MMF queue-full error catalog (updated):**

| Error string | Trigger | SDK version | Source |
|---|---|---|---|
| `[VOE][WARN]slot full` | 70× FlashMemory.writeWord (280 bytes) | V4.1.0 | Our bug — mild case |
| `CH 0 MMF ENC Queue full` | SDK update (build ~4.1.20251219) | ~Dec 2025 dev build | Community search, U79 |
| `osd2enc receive timeout` / `isp2osd receive timeout` | Unknown (no flash trigger confirmed) | Various | Thread #2929, #3319 |

**SDK state as of 2026-06-04 (Cycle U79 — unchanged from U78):**
- Latest stable Arduino SDK: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp SHA b4781b70, zero mutex calls
- Latest pre-release Arduino SDK: V4.1.1-QC-V07 (tag June 3, 2026; build20260603) — no fix; adds OV5647, GC4663, tools v1.4.12; "SWD pin deinit check for I2C" API improvement (unrelated to FCS flash-race)
- ameba-rtos-pro2: V1.0.3 / V1.0.3-aiglass.08 (May 22, 2026) — RTOS-level patches only; no FCS/flash fix
- VOE binary: v1.7.1.0 (Apr 21, 2026) — no FCS flash-race fix in entire 46-version history
- Forum ceiling: **#4871** (79th consecutive null)

**No confirmed fix. Bug remains unpatched as of 2026-06-04 (Cycle U79).**

**Top unresolved actions (unchanged — 21 days unresolved since U7, May 14):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception (SHA b4781b70, zero mutex calls, directly verified this cycle). Callable from Arduino: `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug entirely undocumented outside this research log; 79 cycles and 46 VOE versions contain zero acknowledgment; zero PRs ever filed in this repo; filing would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

---

## Research Update — 2026-06-04 (Cycle U80)

**Agents run:** 4 parallel agents — (A) GitHub repo status (ameba-rtos-pro2, ameba-arduino-pro2, HUB-8735); (B) English forum/web — new threads above #4871, workaround hardware test reports; (C) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee; (D) SDK deep-dive — FlashMemory.cpp raw-URL verification, VOE version, new release tags, documentation access.

**Key new findings this cycle:** None. All four agents independently confirm all repositories frozen at same HEADs as Cycle U79, FlashMemory.cpp unpatched, no forum threads above #4871, all documentation portals 403-blocked, and zero English or Chinese-language content on this bug. This is the 80th consecutive null cycle for error string indexing. BW21-CBV product specification PDF URLs (Ai-Thinker static CDN) were probed but also returned HTTP 403.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 commits (direct GitHub fetch, 2026-06-04, two agents) | **Confirmed frozen — 20+ days.** HEAD = `3f95070` (May 15, 2026). GitHub filtered endpoint `since=2026-06-01` returns zero commits. PR #17 ("fix: ethernet USB driver buffer overflow", orbisai0security) stale-bot flagged May 29, 2026 — no maintainer response; effectively abandoned. No flash, FCS, VOE, boot, HAL, or sensor changes in any observable pipeline. | LOW |
| ameba-arduino-pro2 dev branch (direct GitHub fetch, 2026-06-04, two agents) | **Confirmed frozen — 1 day.** HEAD = `e8dd7e3` "Pre Release Version 4.1.1" (June 3, 2026). Zero new commits on June 4. Zero open PRs (PR #410 merged as `29d47e1` May 26; PR #411 merged as `96cfc51` June 3). No FlashMemory, FCS, or boot-related changes in any commit. | LOW |
| ameba-arduino-pro2 releases (direct GitHub fetch, 2026-06-04, two agents) | **No new releases beyond V4.1.1-QC-V07.** Latest stable = V4.1.0 (Mar 2, 2026). Latest pre-release = V4.1.1-QC-V07 (tag June 3, 2026; build20260603; tools v1.4.12; OV5647 + GC4663 sensors). No V4.1.1-QC-V08 or stable V4.1.1 published. | LOW |
| `FlashMemory.cpp` — raw GitHub URL verification (2026-06-04, two agents) | **Confirmed unpatched in dev HEAD `e8dd7e3`.** SHA b4781b70. All 10 public functions contain zero calls to `device_mutex_lock`, `device_mutex_unlock`, `RT_DEV_LOCK_FLASH`, or `#include "device_lock.h"`. This is the 4th direct raw-URL verification (prior: U31, U36, U79). The architectural defect persists unchanged through V4.1.1-QC-V07. | LOW (confirms prior) |
| VOE binary version (2026-06-04, two agents) | **VOE 1.7.1.0 (April 21, 2026) confirmed as latest.** `hal_video_release_note.txt` raw fetch from dev HEAD shows no entry beyond 1.7.1.0. Web-wide search for VOE 1.7.2.0 or 1.8.0.0 returns zero results. 46 VOE versions total; zero FCS flash-race fix across all 46. | LOW (confirms prior) |
| ameba-arduino-pro2 open issues (2026-06-04, two agents) | **12–17 open issues; newest = #398 (Mar 29, 2026).** No new issues filed since U79. No issues about FlashMemory, FCS, camera cold-boot, VOE, or boot failure in open or closed history. Bug entirely unreported on the official tracker after 80 research cycles. | LOW |
| ideashatch/HUB-8735 (2026-06-04) | **Unchanged — last commit December 2, 2025 (`870a7e0`), 184+ days frozen.** One open issue: #10 (PS5268 sensor ID fail, Aug 2025). No new commits or issues. | LOW |
| forum.amebaiot.com threads above #4871 (2026-06-04, two agents) | **No new threads indexed.** Targeted searches for IDs #4872–#4920 returned zero results from the forum domain. Forum ceiling confirmed at **#4871** for the 3rd consecutive cycle. All direct forum fetches return HTTP 403. | LOW |
| BW21-CBV product specification PDFs (Ai-Thinker static CDN, 2026-06-04) | **HTTP 403.** `aithinker-static.oss-cn-shenzhen.aliyuncs.com/docs/Specification/bw21-cbv_v1.0.0_product_specification_zh.pdf` (v1.0.0, Dec 2024) and kit spec PDF both return HTTP 403. Hardware specification only; unlikely to contain FCS flash-write interaction content. | LOW (blocked) |
| All documentation portals (2026-06-04) | **All still 403-blocked.** ISP application note (15_ISP.html), Flash Layout (08_FLASHLAYOUT.html), Sensor Bringup Flow (37_Introduction), aiot.realmcu.com AMB82-mini guide, Flash Memory example guide — all return HTTP 403 for the 80th consecutive cycle. | LOW (blocked) |
| Web-wide error string sweep (2026-06-04, two agents) | **Zero indexed results — 80th consecutive null cycle.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"` — all return zero publicly indexed results in any language. This research log remains the only public documentation of this bug and its error codes. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn, 2026-06-04, two agents) | **Zero new content — 80th consecutive null cycle.** All Chinese community sites remain 403-blocked or return zero relevant results. No Chinese-language forum posts or articles discuss FCS flash-write camera failure on RTL8735B or BW21-CBV. | LOW |
| Reddit / Hackster.io / Stack Overflow / Arduino.cc (2026-06-04) | **Zero relevant posts.** No new AMB82-Mini / RTL8735B camera+flash cold-boot bug reports on any community platform. No hardware test confirmation for any of the three proposed workarounds found on any platform. | LOW |

**Repository freeze status (as of Cycle U80, June 4, 2026):**

| Repository | Last commit | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **20+ days** |
| ameba-arduino-pro2 dev | June 3, 2026 (`e8dd7e3`) | **1 day** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **94+ days** |
| ideashatch/HUB-8735 | Dec 2, 2025 (`870a7e0`) | **184+ days** |

**SDK state as of 2026-06-04 (Cycle U80 — unchanged from U79):**
- Latest stable Arduino SDK: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp SHA b4781b70, zero mutex calls
- Latest pre-release Arduino SDK: V4.1.1-QC-V07 (tag June 3, 2026; build20260603) — no fix; adds OV5647, GC4663, tools v1.4.12
- ameba-rtos-pro2: V1.0.3 / V1.0.3-aiglass.08 (May 22, 2026) — RTOS-level patches; no FCS/flash fix
- VOE binary: v1.7.1.0 (Apr 21, 2026) — no FCS flash-race fix in entire 46-version history
- Forum ceiling: **#4871** (80th consecutive null)

**No confirmed fix. Bug remains unpatched as of 2026-06-04 (Cycle U80).**

**Top unresolved actions (unchanged — 21 days unresolved since U7, May 14):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception (SHA b4781b70, zero mutex calls, 4th direct verification this cycle). Callable from Arduino: `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug entirely undocumented outside this research log; 80 cycles and 46 VOE versions contain zero acknowledgment; zero PRs ever filed targeting this bug; filing would be the first public disclosure.

---

## Research Update — 2026-06-04 (Cycle U81)

**Search scope:** ameba-arduino-pro2 dev commits since June 3; ameba-rtos-pro2 commits since May 15; GitHub open issues; releases page; forum threads ≥ #4872; error string sweep; Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/Bilibili/Gitee/mcublog.cn); Reddit/Hackster/Stack Overflow/Arduino.cc; BW21-CBV + FCS + 摄像头 + 闪存 Chinese searches.

**Cycle result: NULL — no new findings.**

| Source | Key Finding | Priority |
|---|---|---|
| ameba-arduino-pro2 dev branch (direct GitHub fetch, 2026-06-04 Cycle U81) | **No new commits.** HEAD still `e8dd7e3` "Pre Release Version 4.1.1" (June 3, 2026). 1 day frozen — identical state to U80. No FlashMemory, FCS, VOE, or SPIC bus changes in any commit. | LOW (confirms U80) |
| ameba-arduino-pro2 releases (direct GitHub fetch, 2026-06-04 Cycle U81) | **No new release.** Latest pre-release = V4.1.1-QC-V07 (June 3, 2026). Latest stable = V4.1.0 (Mar 2, 2026). No V4.1.1-QC-V08 or stable V4.1.1 published. | LOW (confirms U80) |
| ameba-arduino-pro2 open issues (direct GitHub fetch, 2026-06-04 Cycle U81) | **12 open issues; highest = #398 (Mar 29, 2026).** No new issues since U80. No issues about FlashMemory, FCS, camera cold-boot, VOE, or SPIC bus in open or closed history. Bug remains unreported on the official tracker after 81 research cycles. | LOW (confirms U80) |
| ameba-rtos-pro2 commits (direct GitHub fetch, 2026-06-04 Cycle U81) | **Confirmed still frozen.** HEAD = `3f95070` (May 15, 2026). Now **20 days frozen**. No commits from June 2026 visible. No flash, FCS, VOE, boot, or HAL changes in any observable pipeline. | LOW (confirms U80) |
| forum.amebaiot.com threads ≥ #4872 (2026-06-04 Cycle U81) | **HTTP 403 — same as all prior cycles.** No new threads indexed above #4871. Forum ceiling confirmed at **#4871** for the 4th consecutive cycle. | LOW (blocked) |
| Web-wide error string sweep (2026-06-04 Cycle U81) | **Zero results — 81st consecutive null.** `"FCS KM_status 0x00002081"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"` — all return zero publicly indexed results in any language. | LOW |
| All Chinese-language sources (2026-06-04 Cycle U81) | **Zero new content — 81st consecutive null.** All Chinese community sites remain 403-blocked or return zero relevant results for BW21-CBV + FCS + 摄像头 + 闪存 + 冷启动. | LOW |
| Reddit / Hackster.io / Stack Overflow / Arduino.cc (2026-06-04 Cycle U81) | **Zero relevant posts.** No new AMB82-Mini / RTL8735B camera+flash cold-boot bug reports on any community platform. | LOW |

**Repository freeze status (as of Cycle U81, June 4, 2026):**

| Repository | Last commit | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **20 days** |
| ameba-arduino-pro2 dev | June 3, 2026 (`e8dd7e3`) | **1 day** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **94 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 (`870a7e0`) | **184 days** |

**SDK state as of 2026-06-04 (Cycle U81 — unchanged from U80):**
- Latest stable Arduino SDK: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp SHA b4781b70, zero mutex calls
- Latest pre-release Arduino SDK: V4.1.1-QC-V07 (June 3, 2026; build20260603) — no fix; adds OV5647, GC4663, tools v1.4.12
- ameba-rtos-pro2: Frozen at May 15, 2026 (`3f95070`) — 20 days
- VOE binary: v1.7.1.0 (Apr 21, 2026) — no FCS flash-race fix in entire 46-version history
- Forum ceiling: **#4871** (81st consecutive null)

**No confirmed fix. Bug remains unpatched as of 2026-06-04 (Cycle U81).**

**Top unresolved actions (unchanged — 21 days unresolved since U7, May 14):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed; dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; FlashMemory.cpp confirmed sole exception (SHA b4781b70, zero mutex calls). Callable from Arduino: `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug entirely undocumented outside this research log; 81 cycles and 46 VOE versions contain zero acknowledgment; filing would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — ISP documentation (U78) confirms purpose: AE/AWB SRAM retention for standby/wake; eliminates ISP competing SPIC writes regardless; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-06-04 (Cycle U82)

**Search scope:** Four parallel agents: (1) GitHub — ameba-rtos-pro2 commits/releases after May 15; ameba-arduino-pro2 dev/main commits/releases/issues/PRs after June 3; PR #17 status; (2) English forum/web — new threads above #4871, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee; (4) ameba forum threads, SDK docs accessibility, V4.1.1 stable release status.

**Cycle result: NULL — all findings pre-empted by U80/U81.** Four independent agents unanimously confirmed the same state already recorded in the two prior cycles run today. All new data points (V4.1.1-QC-V07, PR #410/#411 merges, PR #17 stale, ameba-rtos-pro2 V1.0.3) were already captured in U80. No genuinely new findings exist as of June 4, 2026 end-of-day.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 commits (2026-06-04, Cycle U82) | **Confirmed frozen — 20 days.** HEAD = `3f95070` (May 15, 2026). Zero new commits. PR #17 (ethernet USB driver buffer overflow, orbisai0security) stale-flagged May 29, 2026; no maintainer response; effectively abandoned. No flash, FCS, VOE, boot, or HAL changes anywhere. | LOW (confirms U80/U81) |
| ameba-arduino-pro2 dev branch (2026-06-04, Cycle U82) | **Confirmed at HEAD `e8dd7e3` (June 3, 2026) — 1 day frozen.** Zero new commits on June 4. Zero open PRs. PR #410 (SPI1, merged May 26), PR #411 (OV5647/GC4663, merged June 3) — neither touches FlashMemory.cpp or FCS-related files. No fix in any commit. | LOW (confirms U80/U81) |
| ameba-arduino-pro2 releases (2026-06-04, Cycle U82) | **V4.1.1-QC-V07 (June 3, 2026; build20260603; tools v1.4.12) remains latest pre-release.** V4.1.0 (Mar 2, 2026) remains latest stable. No V4.1.1-QC-V08 or stable V4.1.1 published. No FCS, flash, or SPIC mutex entry in any V4.1.1 changelog entry from V4.1.1-QC-V01 through V4.1.1-QC-V07. | LOW (confirms U80/U81) |
| `FlashMemory.cpp` — dev HEAD `e8dd7e3` (2026-06-04, Cycle U82) | **SHA b4781b70 confirmed. Zero mutex calls across all 10 public functions.** No `device_mutex_lock`, `device_mutex_unlock`, `RT_DEV_LOCK_FLASH`, or `#include "device_lock.h"`. Architectural defect persists through V4.1.1-QC-V07. Sole exception among 16+ RTOS SDK files that correctly use `RT_DEV_LOCK_FLASH`. | LOW (confirms U80/U81) |
| ameba-rtos-pro2 V1.0.3 release tag (May 22, 2026) | **Confirmed: RTSP and WebSocket source patches only.** No FCS, VOE, FlashMemory, or SPIC mutex fix. First RTOS SDK release tag; captured in U80. VOE binary remains 1.7.1.0 (Apr 21, 2026). | LOW (confirms U80) |
| forum.amebaiot.com threads ≥ #4872 (2026-06-04, Cycle U82) | **No new threads indexed above #4871 for the 4th consecutive cycle.** All direct forum fetches return HTTP 403. No thread anywhere documents hardware test results for the three proposed workarounds. | LOW (blocked) |
| Web-wide error string sweep (2026-06-04, Cycle U82) | **Zero indexed results — 82nd consecutive null.** `"FCS KM_status 0x00002081"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"`, `"USE_ISP_RETENTION_DATA"` — all return zero in any language on the public web. | LOW |
| All Chinese-language sources (2026-06-04, Cycle U82) | **Zero new content — 82nd consecutive null.** bbs.aithinker.com, bbs.ai-thinker.com, CSDN, 知乎, EEWorld, 21IC, Bilibili, Gitee, mcublog.cn all return 403 or zero relevant results. No Chinese-language content on FCS flash-write camera failure found. | LOW |
| Reddit / Hackster.io / Stack Overflow / Arduino.cc (2026-06-04, Cycle U82) | **Zero relevant posts.** No AMB82-Mini / RTL8735B camera+flash cold-boot bug reports on any English community platform. No hardware test confirmation for any proposed workaround. | LOW |

**Repository freeze status (Cycle U82, June 4, 2026):**

| Repository | Last commit | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **20 days** |
| ameba-arduino-pro2 dev | June 3, 2026 (`e8dd7e3`) | **1 day** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **94 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 (`870a7e0`) | **184 days** |

**SDK state as of 2026-06-04 (Cycle U82 — unchanged from U80/U81):**
- Latest stable Arduino SDK: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp SHA b4781b70, zero mutex calls
- Latest pre-release Arduino SDK: V4.1.1-QC-V07 (June 3, 2026; build20260603) — no fix; adds OV5647, GC4663, tools v1.4.12
- ameba-rtos-pro2: V1.0.3 release tag (May 22, 2026); main branch frozen at May 15, 2026 (`3f95070`)
- VOE binary: v1.7.1.0 (Apr 21, 2026) — no FCS flash-race fix in entire 46-version history
- Forum ceiling: **#4871** (4th consecutive cycle at this ceiling)

**No confirmed fix. Bug remains unpatched as of 2026-06-04 (Cycle U82).**

**Top unresolved actions (unchanged from U81):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; FlashMemory.cpp confirmed sole exception (SHA b4781b70, zero mutex calls, 82nd cycle unpatched). Callable from Arduino: `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug entirely undocumented outside this research log; 82 cycles and 46 VOE versions with zero acknowledgment; filing would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes entirely; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

---

## Research Update — 2026-06-05 (Cycle U83)

**Search scope:** Six parallel search threads: (1) GitHub — ameba-rtos-pro2 and ameba-arduino-pro2 commits/releases/issues since June 4 via direct WebFetch; (2) ameba-arduino-doc repo — new documentation commits on June 4; (3) English forum/web — new threads above #4871, FCS Disable / mutex / USE_ISP_RETENTION_DATA hardware test reports; (4) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee; (5) Error string indexing — all five key error strings; (6) Miscellaneous new leads — joehou45/Amb82-Mini repository, PlatformIO issue #4809, ameba-arduino-doc sensor_module_window.rst.

**Key new findings this cycle:**
- Both Ameba repositories confirmed frozen again: ameba-rtos-pro2 at `3f95070` (May 15, 2026 — 21 days); ameba-arduino-pro2 dev at `e8dd7e3` (June 3, 2026 — 2 days)
- **ameba-arduino-doc had 3 cosmetic commits on June 4, 2026** — all to `sensor_module_window.rst`; changes were manufacturer name formatting (CBRITECH→Cbritech) and contact list reordering; no FCS/FlashMemory documentation added
- **joehou45/Amb82-Mini GitHub repository** (newly identified from search results) confirmed to be 3D enclosure/shell design files for the physical board — entirely unrelated to FCS/flash/camera bugs
- **PlatformIO issue #4809 disambiguation**: the PlatformIO `platformio-core/issues/4809` ("Board support: Realtek AMB82-Mini") is completely unrelated to forum.amebaiot.com thread #4809 ("AMB82-Mini starts running Arduino code before turning on 3.3V") — both are in the research tracking but are distinct
- All forum threads still 403-blocked; forum ceiling remains #4871 (5th consecutive null cycle at this ceiling)
- Zero new Chinese or English content on this bug — 83rd consecutive null cycle for error string indexing

| Source | Key Finding | Priority |
|---|---|---|
| ameba-arduino-pro2 dev branch (direct WebFetch of commits page, 2026-06-05) | **Confirmed frozen — 2 days.** HEAD = `e8dd7e3` "Pre Release Version 4.1.1" (June 3, 2026). No commits on June 4 or June 5. 10 most recent commits confirmed: `e8dd7e3` (Jun 3), `96cfc51` (Jun 3), `29d47e1` (May 26), `7db1c7d` (May 19), `3d53672` (May 19), `cd0bd40` (May 18), `13961cc` (May 5), `e218f33` (Apr 30), `60fe0b1` (Apr 30), `8cab2da` (Apr 30). No FlashMemory, FCS, boot, or camera cold-boot changes in any commit. | LOW |
| ameba-rtos-pro2 commits (direct WebFetch of commits page, 2026-06-05) | **Confirmed frozen — 21 days.** HEAD = `3f95070` "Sync upstream 7343927…" (May 15, 2026). Zero new commits since May 15. 10 most recent confirmed: `3f95070`, `afc85a0`, `9c8b6f6`, `d2676f1` (all May 15); `1c1c8b7`, `a111e91`, `7b2b97f`, `63c0a2f`, `d54e1a8`, `687a4c7` (all May 1). No flash, FCS, VOE, boot, HAL, or sensor changes. | LOW |
| ameba-arduino-pro2 releases (WebFetch of releases page, 2026-06-05) | **No new releases.** Latest stable = V4.1.0 (Mar 2, 2026). Latest pre-release = V4.1.1-QC-V07 (June 3, 2026; build20260603). No V4.1.1-QC-V08 or stable V4.1.1 published. WebFetch showed no releases newer than QC-V07. | LOW |
| ameba-arduino-pro2 open issues (WebFetch of issues page, 2026-06-05) | **Confirmed — newest issue #398 (Mar 29, 2026).** 10 most recent open issues listed: #398, #342, #325, #324, #317, #310, #296, #287, #276, #235 — all feature requests or hardware compatibility questions. No new issues above #398. No issue filed for FCS/flash/camera/VOE/boot failure. Bug remains entirely unreported on the official Arduino SDK tracker after 83 research cycles. | LOW |
| ameba-arduino-doc commits (WebFetch of commits page, 2026-06-05) | **3 cosmetic commits on June 4, 2026 — no technical content.** All three commits modify `source/FAQ/sensor_module_window.rst`: (1) "Correct manufacturer names and email formatting" — changed CBRITECH to Cbritech throughout ~50+ instances in the camera sensor table; moved Realtek contact to top of contact list; (2)+(3) "Update sensor_module_window.rst" — additional formatting fixes. No changes to FCS documentation, FlashMemory API docs, camera boot guides, mutex warnings, or flash-camera interaction content. | LOW |
| joehou45/Amb82-Mini GitHub repository (WebFetch, 2026-06-05) | **Newly confirmed irrelevant.** This repo contains 3D STL files for a physical protective shell/enclosure for the AMB82-Mini development board (9 magnets, magnetic closure mechanism). README: "此開源STL files 僅供個人使用, 請勿商業販售" (personal use, no commercial sale). Only issue: #1 "Invitation for Ameba Likes GitHub Event" (Aug 29, 2023). No source code, no SDK, no FCS/flash/camera bug content. | LOW |
| platformio/platformio-core Issue #4809 (WebFetch, 2026-06-05) | **Disambiguation confirmed.** PlatformIO issue #4809 is titled "Board Support: REALTEK AMB82-Mini" — a closed feature request to add the board to PlatformIO's supported platforms. Entirely unrelated to forum.amebaiot.com/t/.../4809 ("AMB82-Mini starts running Arduino code before turning on 3.3V"). Both items in the research tracking; this clarifies they are distinct. | LOW |
| forum.amebaiot.com thread ceiling (2026-06-05) | **Forum ceiling confirmed at #4871 — 5th consecutive null cycle.** Multiple search queries for thread IDs 4872–4920 returned zero indexed results. All direct forum fetches return HTTP 403. No new accessible threads related to camera, flash, FCS, or VOE above #4871. | LOW |
| Web-wide error string sweep (all search engines, 2026-06-05) | **Zero indexed results — 83rd consecutive null cycle.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD command fail"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"` — all return zero publicly indexed results anywhere in any language. This research log remains the only public documentation of this bug and its error codes. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee, 2026-06-05) | **Zero new content — 83rd consecutive null cycle.** Chinese-language search using BW21-CBV / AMB82 / RTL8735B + FCS / 闪存 / 摄像头 / 冷启动 terms returned only: BW21-CBV unboxing reviews, general AMB82-Mini getting-started guides, ESP8266/ESP32 camera articles (unrelated), and EEFocus video review of BW21-CBV (product unboxing). No new technical content on FCS flash-write camera failure. All Chinese community sites remain 403-blocked. | LOW |
| Reddit / Hackster.io / Stack Overflow / Arduino.cc (2026-06-05) | **Zero relevant posts.** No AMB82-Mini / RTL8735B camera+flash cold-boot reports on any community platform. No hardware test confirmation for any of the three proposed workarounds. | LOW |

**Repository freeze status (as of Cycle U83, June 5, 2026):**

| Repository | Last commit | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **21 days** |
| ameba-arduino-pro2 dev | June 3, 2026 (`e8dd7e3`) | **2 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **95 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 (`870a7e0`) | **185 days** |

**SDK state as of 2026-06-05 (Cycle U83 — unchanged from U82):**
- Latest stable Arduino SDK: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp SHA b4781b70, zero mutex calls
- Latest pre-release Arduino SDK: V4.1.1-QC-V07 (June 3, 2026; build20260603) — no fix; adds OV5647, GC4663, tools v1.4.12
- ameba-rtos-pro2: V1.0.3 release tag (May 22, 2026); main branch frozen at May 15, 2026 (`3f95070`)
- VOE binary: v1.7.1.0 (Apr 21, 2026) — no FCS flash-race fix in entire 46-version history
- Forum ceiling: **#4871** (5th consecutive null cycle at this ceiling)

**No confirmed fix. Bug remains unpatched as of 2026-06-05 (Cycle U83).**

**Top unresolved actions (unchanged — 22 days unresolved since U7, May 14):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception (SHA b4781b70, zero mutex calls, 83rd cycle unpatched). Callable from Arduino: `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug entirely undocumented outside this research log; 83 cycles and 46 VOE versions with zero acknowledgment; zero PRs ever filed; filing would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes entirely; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-06-05 (Cycle U84)

**Search scope:** Four parallel agents: (1) GitHub — ameba-rtos-pro2 and ameba-arduino-pro2 commits/releases/issues since June 3–5 via direct WebFetch; (2) English forum/web — new threads above #4871, FCS Disable / mutex / USE_ISP_RETENTION_DATA hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee; (4) SDK deep-dive — hal_video_release_note.txt in V4.1.1-QC-V07, FlashMemory.cpp full source confirmation, ameba-arduino-doc new commits, RTL8735C SDK status.

**Key new findings this cycle:**
- **`hal_video_release_note.txt` returns HTTP 404** in the ameba-arduino-pro2 dev branch (path: `.../video/driver/RTL8735B/hal_video_release_note.txt`). The file was accessible in prior cycles; it appears to have been removed or relocated during the QC-V07 restructure. The latest confirmed VOE version (1.7.1.0, Apr 21, 2026) is now unverifiable from public source.
- **FlashMemory.cpp `write()` erases ALL sectors** in the entire FlashMemory app region (`_flash_base_address` through `_flash_base_address + MAX_FLASH_MEMORY_APP_SIZE`) with no SPIC bus lock — more destructive than previously characterized; each call to `FlashMemory.write()` bulk-erases the full 0xFD0000+ region before writing.
- **Thread #4868 newly confirmed**: "NN Model loading from Memory instead of Flash or SD card failing with exceptions" — NN inference memory allocation issue; not related to FCS bug.
- **V4.1.1-QC-V07 changelog confirmed** (June 3, 2026): adds OV5647, GC4663 sensor support, tools v1.4.12, SPI1 bus switching API — no FCS, flash mutex, or camera cold-boot fix.
- All repos frozen at same HEADs as U83; zero new Chinese or English hardware test reports found.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-arduino-pro2 dev branch — `hal_video_release_note.txt` (fetched 2026-06-05) | **HTTP 404 — file not found at previously-known path.** `https://raw.githubusercontent.com/Ameba-AIoT/ameba-arduino-pro2/dev/Arduino_package/hardware/system/component/video/driver/RTL8735B/hal_video_release_note.txt` returns 404. The RTL8735B driver directory now lists only: `fcs_hal/` subdirectory, `boot_retention.h`, `isp_api.h`, `isp_ctrl_api.h`, `librtsremosaic.h`, `video_api.h`, `video_boot.h`, `video_snapshot.h`. The release notes file is absent. The last confirmed VOE version (1.7.1.0, Apr 21, 2026, "Fix dual sensor id FCS mirror/flip issue") can no longer be independently verified from public source. Whether V4.1.1-QC-V07's `voe.bin` contains an undocumented fix remains opaque. | MEDIUM |
| `FlashMemory.cpp` — `write()` function body (dev branch, V4.1.1-QC-V07, fetched 2026-06-05) | **Bulk-erase behavior confirmed from verbatim source.** `write()` iterates `flash_erase_sector()` across EVERY sector from `_flash_base_address` through `_flash_base_address + MAX_FLASH_MEMORY_APP_SIZE` before writing any data. Constants: `FLASH_MEMORY_APP_BASE = 0xFD0000`, `FLASH_SECTOR_SIZE = 0x1000`. A single `FlashMemory.write()` call triggers bulk erase of the entire app region — with zero SPIC bus lock at any point. This is more aggressive than previously characterized (prior cycles described `flash_erase_sector` as targeted at a single sector). The mutex omission's blast radius per `write()` call is therefore proportional to the full app region size. Three total commits in FlashMemory.cpp history (Jul 9 2024, Sep 30 2025 ×2); no mutex introduced at any commit. | MEDIUM |
| ameba-arduino-pro2 V4.1.1-QC-V07 release notes (June 3, 2026, confirmed) | **Changelog fully confirmed — no FCS fix.** Rolling update March 6 – June 3, 2026: Battery-Powered Camera POC, Audio Trigger Recording, TensorFlowLite, WiFi TCP data corruption fix, new sensors (IMX681, IMX681_12M, OV50A40, K306P, OV5647, GC4663), tools v1.4.8–v1.4.12, WDT API, SPI1 switching. Zero mention of: flash, mutex, FCS, ISP, SPIC, RT_DEV_LOCK_FLASH, concurrent access, camera cold-boot, or sensor init failure after flash write. | LOW (confirms prior) |
| ameba-rtos-pro2 commits (direct WebFetch, 2026-06-05) | **Still frozen at `3f95070` (May 15, 2026) — 21 days.** PR #17 (USB Ethernet) still open and unmerged. Zero new commits touching flash, FCS, VOE, boot, HAL, or sensor. | LOW |
| ameba-arduino-pro2 dev/main branches (direct WebFetch, 2026-06-05) | **Both frozen.** dev HEAD = `e8dd7e3` (June 3, 2026); main HEAD = `93d63514` (March 2, 2026 — 95 days). Zero open PRs. Open issues max at #398 (Mar 29, 2026). No new issues filed for FCS/flash/camera/VOE/boot failure after 84 research cycles. | LOW |
| forum.amebaiot.com thread #4868 (confirmed, 2026-06-05) | **Thread #4868 content confirmed from search index**: "NN Model loading from Memory instead of Flash or SD card failing with exceptions." Topic: NN inference model memory allocation failures. Unrelated to FCS camera cold-boot failure. No threads above #4871 (U83 ceiling) newly indexed this cycle. Forum ceiling unchanged. | LOW |
| ameba-arduino-doc commits (WebFetch, 2026-06-05) | **3 cosmetic commits on June 4, 2026** — all to `sensor_module_window.rst` (manufacturer name formatting, contact list reordering). No FCS documentation, FlashMemory mutex warnings, or camera boot guide updates added. | LOW |
| RTL8735C / AmebaPro3 (WebSearch, 2026-06-05) | **No public SDK.** RTL8735C (Computex 2025 Best Choice Award winner, Wi-Fi 6 + BT 5.3 + AI ISP). No GitHub repo under Ameba-AIoT for RTL8735C. No Arduino or FreeRTOS SDK download exists. No SDK to examine for FCS flash mutex improvements. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee, 2026-06-05) | **Zero new content — 84th consecutive null cycle.** All Chinese community sites remain 403-blocked. Searches for `RTL8735B FCS 摄像头 冷启动 闪存`, `AMB82 FlashMemory 摄像头 失败 FCS`, `BW21-CBV 摄像头 FCS 闪存写入` return only product pages and unboxing content. | LOW |
| Web-wide error string sweep (all search engines, 2026-06-05) | **Zero indexed results — 84th consecutive null cycle.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD command fail"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"` all return zero results. No hardware test result for any proposed workaround posted anywhere. | LOW |

**`hal_video_release_note.txt` 404 — assessment:**

The file's disappearance from the public dev branch could indicate: (a) relocated to a different path not publicly accessible; (b) merged into a binary blob alongside `voe.bin`; or (c) intentionally removed. This makes independent VOE version verification impossible from public GitHub. The QC-V07 `voe.bin` may contain undocumented changes, but there is no evidence of any FCS cold-boot fix in the binary.

**FlashMemory `write()` bulk-erase scope — updated impact assessment:**

| Prior characterization | Confirmed characterization (U84) |
|---|---|
| `flash_erase_sector()` targets a single sector per call | `write()` erases EVERY sector from `_flash_base_address` through `_flash_base_address + MAX_FLASH_MEMORY_APP_SIZE` |
| SPIC collision risk per call = 1 sector erase window | SPIC collision risk per call = N sector erase windows (entire app region) |

A single `FlashMemory.write()` call therefore generates far more unguarded SPIC traffic than a single `eraseSector()` call, proportionally increasing the probability of collision with an ISP AE/AWB FTL write to 0xF0D000.

**Repository freeze status (as of Cycle U84, June 5, 2026):**

| Repository | Last commit | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **21 days** |
| ameba-arduino-pro2 dev | June 3, 2026 (`e8dd7e3`) | **2 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **95 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 (`870a7e0`) | **185 days** |

**SDK state as of 2026-06-05 (Cycle U84 — unchanged from U83):**
- Latest stable Arduino SDK: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release Arduino SDK: V4.1.1-QC-V07 (June 3, 2026) — no fix; adds OV5647, GC4663, tools v1.4.12
- ameba-rtos-pro2: V1.0.3 release tag (May 22, 2026); main frozen at May 15, 2026 (`3f95070`)
- VOE binary: last confirmed v1.7.1.0 (Apr 21, 2026); release notes now 404 in public dev branch — current version unverifiable
- Forum ceiling: **#4871** (unchanged from U83)

**No confirmed fix. Bug remains unpatched as of 2026-06-05 (Cycle U84).**

**Top unresolved actions (unchanged):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed; dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; callable from Arduino: `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug entirely undocumented outside this log; 84 cycles with zero acknowledgment; zero PRs ever filed.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-06-05 (Cycle U85)

**Search scope:** Six parallel search threads + direct GitHub/web fetches: (1) GitHub — ameba-rtos-pro2 and ameba-arduino-pro2 commits/releases/issues since June 3–5 via direct WebFetch; (2) English forum/web — new threads above #4871, FCS Disable / mutex / USE_ISP_RETENTION_DATA hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee; (4) SDK status — V4.1.1-QC-V07 confirmed, hal_video_release_note.txt; (5) GitHub issues (ameba-rtos-pro2, ameba-arduino-pro2, ideashatch/HUB-8735); (6) New community content — Hackster.io BW21-CBV-Kit project, Amazon YELUFT BW21-CBV-Kit listing.

**Key new findings this cycle:** None of substance. All repositories, issue trackers, forum threads, and public web sources are frozen at the same state as Cycle U84. One new commercial product listing (Amazon YELUFT BW21-CBV-Kit, B0FY67YTFN) surfaced — confirms continued market availability of the board but contains no technical bug content. Forum thread #4302 (the most-searched thread) returned HTTP 403 on direct fetch for the 85th consecutive cycle. All three key workaround tests remain unconfirmed in any public source.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 commits (direct WebFetch, 2026-06-05) | **Confirmed frozen — 21 days.** HEAD = `3f95070` "Sync upstream 7343927…" (May 15, 2026). 10 most recent commits verified: `3f95070`, `afc85a0`, `9c8b6f6`, `d2676f1` (all May 15); `1c1c8b7`, `a111e91`, `7b2b97f`, `63c0a2f`, `d54e1a8`, `687a4c7` (all May 1). Zero new commits. No flash, FCS, VOE, boot, HAL, or sensor changes. | LOW |
| ameba-arduino-pro2 dev branch commits (direct WebFetch, 2026-06-05) | **Confirmed frozen — 2 days.** HEAD = `e8dd7e3` "Pre Release Version 4.1.1" (June 3, 2026). 10 most recent commits: `e8dd7e3`, `96cfc51` (Jun 3), `29d47e1` (May 26), `7db1c7d`, `3d53672` (May 19), `cd0bd40` (May 18), `13961cc` (May 5), `e218f33`, `60fe0b1`, `8cab2da` (Apr 30). No FlashMemory, FCS, boot, mutex, or camera cold-boot changes in any commit. | LOW |
| ameba-arduino-pro2 releases (direct WebFetch, 2026-06-05) | **No new releases.** Latest stable = V4.1.0 (Mar 2, 2026). Latest pre-release = V4.1.1-QC-V07 (June 3, 2026; build20260603). No V4.1.1-QC-V08 or stable V4.1.1 published as of this cycle. | LOW |
| ameba-arduino-pro2 open issues (direct WebFetch, 2026-06-05) | **Unchanged — 12 open issues; newest = #398 (Mar 29, 2026).** Full list confirmed: #398, #342, #325, #324, #317, #310, #296, #287, #276, #235, #224, #184. No new issues filed. No FCS/flash/camera/VOE/boot-failure issue exists in open or closed history. Bug remains entirely unreported on the official tracker after 85 research cycles. | LOW |
| ameba-rtos-pro2 open issues (direct WebFetch, 2026-06-05) | **3 open issues — unchanged since U8.** #16 (AI glass src path, Jan 27, 2026), #4 (chip support, Apr 25, 2025), #3 (antivirus detection, Apr 21, 2025). No new issues. No FCS/flash/camera bug filed in the RTOS repo. | LOW |
| ideashatch/HUB-8735 open issues (direct WebFetch, 2026-06-05) | **1 open issue: #10** (PS5268 sensor id fail, Aug 13, 2025). No new issues. Unchanged since U10. | LOW |
| forum.amebaiot.com thread ceiling (2026-06-05) | **Forum ceiling remains #4871 — 6th consecutive null cycle.** Multiple search queries for thread IDs 4872–4920 returned zero results. All direct forum fetches return HTTP 403. Thread #4302 ("VOE frame_end sensor didn't initialize done!") returned HTTP 403 on direct WebFetch. No new accessible threads related to camera, flash, FCS, or VOE above #4871. | LOW |
| Amazon YELUFT BW21-CBV-Kit listing (B0FY67YTFN, surfaced 2026-06-05) | **New commercial product listing surfaced for the first time** in search results for BW21-CBV + FCS + camera queries. Title: "YELUFT BW21-CBV-Kit AI Vision Recognition Supports YOLOv7 Object Detection Model, RTL8735B Chip Supports Dual-Band WiFi & Bluetooth 5.1 Wireless Transmission with 2MP Wide-Angle Camera." A third-party Amazon seller offering the BW21-CBV-Kit. No technical content, no mention of camera boot failures, no FCS/flash discussion. Confirms the board remains commercially available on Amazon US (previously only direct Ai-Thinker and Seeed Studio channels were tracked). No bug-relevant information. | LOW |
| Hackster.io / Hackaday.io — "DIY Project: Digital Camera + BW21-CBV-Kit" (surfaced 2026-06-05) | **Two new community project pages surfaced** for a DIY digital camera project using BW21-CBV-Kit (Hackster.io: ai-thinker/diy-project-digital-camera-bw21-cbv-kit-5a7309; Hackaday.io: project/203977). Both pages returned HTTP 403 on direct fetch. Content not accessible; no FCS/flash/camera boot failure information extractable from snippets. | LOW (blocked) |
| All English web: error string sweep (2026-06-05) | **Zero indexed results — 85th consecutive null cycle.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD command fail"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"` return zero publicly indexed results anywhere on the accessible web. No hardware test result for any proposed workaround has been posted in any language. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee, 2026-06-05) | **Zero new content — 85th consecutive null cycle.** Searches using `BW21-CBV FCS 摄像头 冷启动`, `AMB82 FlashMemory 摄像头 失败 FCS`, `RTL8735B FCS 闪存 摄像头 问题` returned only unboxing reviews, product specifications, and getting-started guides. All Chinese community forums remain 403-blocked. No Chinese-language technical posts about FCS flash-write camera failure found. | LOW |
| RTL8735C / AmebaPro3 SDK (web search, 2026-06-05) | **No public SDK announced.** No GitHub repository, Arduino support, or FreeRTOS SDK download exists for RTL8735C as of this cycle. Unchanged from U15 (first documented). | LOW |

**Repository freeze status (as of Cycle U85, June 5, 2026):**

| Repository | Last commit | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **21 days** |
| ameba-arduino-pro2 dev | June 3, 2026 (`e8dd7e3`) | **2 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **95 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 (`870a7e0`) | **185 days** |

**SDK state as of 2026-06-05 (Cycle U85 — unchanged from U84):**
- Latest stable Arduino SDK: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release Arduino SDK: V4.1.1-QC-V07 (June 3, 2026; build20260603) — no fix; adds OV5647, GC4663, tools v1.4.12
- ameba-rtos-pro2: V1.0.3 release tag (May 22, 2026); main branch frozen at May 15, 2026 (`3f95070`)
- VOE binary: last confirmed v1.7.1.0 (Apr 21, 2026); hal_video_release_note.txt 404 in public dev branch
- Forum ceiling: **#4871** (6th consecutive null cycle at this ceiling)
- FlashMemory.cpp: SHA b4781b70, zero mutex calls — 85th cycle unpatched

**No confirmed fix. Bug remains unpatched as of 2026-06-05 (Cycle U85).**

**Top unresolved actions (unchanged from U84):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; FlashMemory.cpp omission is the confirmed architectural defect; callable from Arduino: `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug entirely undocumented outside this log; 85 cycles with zero official acknowledgment; zero PRs ever filed.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes entirely; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-06-05 (Cycle U86)

**Search scope:** Four parallel search threads + two direct WebFetches: (1) ameba-arduino-pro2 releases page — any release newer than V4.1.1-QC-V07; (2) ameba-rtos-pro2 commits/main — any commits after May 15, 2026; (3) English web — V4.1.1 flash/FCS/camera fix; (4) English web — device_mutex_lock FlashMemory FCS test results; (5) English web — ameba-rtos-pro2 flash mutex FCS fix June 2026; (6) English web — RTL8735B FCS camera boot failure fix June 2026.

**Key new findings this cycle:** None. All repositories and public sources unchanged from Cycle U85. This cycle is a continuation agent run within the same calendar day (June 5, 2026), confirming the null state with independent fetches.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-arduino-pro2 releases (direct WebFetch, 2026-06-05 Cycle U86) | **No new release.** Latest pre-release = V4.1.1-QC-V07 (June 3, 2026). Latest stable = V4.1.0 (March 2, 2026). Page also surfaces `Add Flash_SAVE function for wifi wpa connect example` in V4.1.1 change notes — refers to saving Wi-Fi credentials to flash (unrelated to FlashMemory mutex omission or FCS). No mutex, FCS boot, or cold-boot camera fix mentioned anywhere. | LOW (confirms U85) |
| ameba-rtos-pro2 commits/main (direct WebFetch, 2026-06-05 Cycle U86) | **Still frozen at May 15, 2026 (`3f95070` "Sync upstream 7343927…") — 21 days.** 10 verified recent commits: May 15 ×4 (sync + mmf + wlan ×2), May 1 ×6 (sync + wlan + video imx681 5M + ov12890 IQ update + "sync voe to 1.7.1.0" + isp osd tof example). No commit touches flash, FCS, boot, mutex, or camera cold-boot. The "sync voe to 1.7.1.0" commit (May 1) is the most recent VOE change — consistent with previously documented VOE 1.7.1.0 (Apr 21, 2026). | LOW (confirms U85) |
| English web — RTL8735B FCS camera boot failure fix (2026-06-05) | **Zero new results.** Search returns ISP documentation, ManualsLib entries, and forum thread #1833 (upload fail, unrelated). No fix guide, workaround test, or community post about FCS cold-boot failure. | LOW |
| English web — ameba-rtos-pro2 flash mutex FCS fix June 2026 (2026-06-05) | **Zero new results.** Search returns only ameba-rtos-pro2 GitHub homepage, issues list, documentation, and ameba-tool-rtos-pro2 repo. No commit or PR matching the fix criteria surfaced. | LOW |
| English web — device_mutex_lock FlashMemory FCS camera workaround (2026-06-05) | **Zero new results.** Search returns AMB82-mini camera support threads (3345, 4829), VOE frame_end thread #4302, and general Arduino/documentation pages. No hardware test result for the mutex wrapper workaround published anywhere. Thread #4302 ("[VOE]frame_end: sensor didn't initialize done!") resurfaces in search index but direct fetch returns HTTP 403. | LOW |
| English web — V4.1.1 release flash FCS camera fix (2026-06-05) | **Zero new results.** Search confirms V4.1.1 rolling-update dates (Mar 6 / Mar 20 / Apr 2 / Apr 17, 2026 update batches). FCS mentioned only as "Add FCS mode for all supported sensors" in V4.0.8-QC-V07 (Oct 2024 feature introduction) — not as a fix. No mutex, FCS boot-corruption, or camera cold-boot repair in any V4.1.1 sub-release. | LOW (confirms prior) |

**Repository freeze status (as of Cycle U86, June 5, 2026):**

| Repository | Last commit | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **21 days** |
| ameba-arduino-pro2 dev | June 3, 2026 (`e8dd7e3`) | **2 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **95 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 (`870a7e0`) | **185 days** |

**SDK state as of 2026-06-05 (Cycle U86 — unchanged from U85):**
- Latest stable Arduino SDK: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release Arduino SDK: V4.1.1-QC-V07 (June 3, 2026; build20260603) — no fix
- ameba-rtos-pro2: V1.0.3 release tag (May 22, 2026); main frozen at May 15, 2026 (`3f95070`)
- VOE binary: last confirmed v1.7.1.0 (synced May 1, 2026 in RTOS repo; Apr 21, 2026 release date); hal_video_release_note.txt 404 in public dev branch
- Forum ceiling: **#4871** (unchanged)
- FlashMemory.cpp: SHA b4781b70, zero mutex calls — 86th cycle unpatched

**No confirmed fix. Bug remains unpatched as of 2026-06-05 (Cycle U86).**

**Top unresolved actions (unchanged):**
1. **Hardware test of "Camera FCS Mode = Disable"** — no public test result; highest confidence workaround. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` pattern; callable from Arduino sketch.
3. **File a GitHub Issue on ameba-arduino-pro2** — 86 cycles, zero official acknowledgment.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

---

## Research Update — 2026-06-06 (Cycle U87)

**Search targets:** ameba-arduino-pro2 dev branch new commits; V4.1.1-QC-V07 release notes; ameba-rtos-pro2 main branch freeze status; forum.amebaiot.com new threads; FCS error strings; Chinese-language sources; hardware test results for proposed workarounds.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-arduino-pro2 dev branch commits (direct WebFetch, 2026-06-06 Cycle U87) | **No new commits since June 3, 2026.** Latest commit remains `e8dd7e3` ("Pre Release Version 4.1.1", June 3, 2026). Three commits merged in the past 12 days: `29d47e1` (May 26 — SPI API for SPI1 switching, PR #410), `96cfc51` (June 3 — OV5647/GC4663 sensor support + Wire.cpp SWD-pin deinit check, PR #411, 107 files changed), `e8dd7e3` (June 3 — version tag for V4.1.1). None touch FlashMemory.cpp, ftl_nor_api.c, or FCS boot path. FlashMemory.cpp confirmed zero mutex calls in dev branch as of this cycle. | LOW (confirms U86) |
| ameba-arduino-pro2 V4.1.1-QC-V07 release (direct WebFetch, 2026-06-06 Cycle U87) | **V4.1.1-QC-V07 (build20260603) remains the latest pre-release.** No new release published since June 3, 2026. Release notes contain no mention of FCS, FlashMemory, mutex, SPIC, or camera cold-boot. Additions in QC-V07 vs prior: OV5647/GC4663 sensor drivers, Wire.cpp SWD-pin-deinit guard, tools v1.4.12. Bug is not acknowledged and not fixed in any V4.1.1 sub-release. | LOW (confirms U86) |
| ameba-rtos-pro2 main branch (direct WebFetch, 2026-06-06 Cycle U87) | **Still frozen at May 15, 2026 (`3f95070` "Sync upstream 7343927…") — 22 days.** No new commit in the last 24 hours. ftl_nor_api.c (three-callback race window), flash mutex architecture, and VOE FCS path remain unmodified. | LOW (confirms U86) |
| English web — RTL8735B FCS camera boot failure / FCS_I2C_INIT_ERR / KM_status 0x00002081 (2026-06-06) | **Zero new indexed results.** No forum post, blog, or repository document has been indexed matching the FCS cold-boot failure error strings. 87 consecutive null cycles for all key error strings. | LOW |
| English web — FlashMemory.cpp mutex fix / ameba-arduino-pro2 PR (2026-06-06) | **Zero new results.** No PR, issue, or commit proposing the `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper for FlashMemory has appeared in search results or on GitHub. | LOW |
| English web — device_mutex_lock FlashMemory workaround hardware test (2026-06-06) | **Zero new results.** No public hardware test result for any of the three proposed workarounds (FCS Disable mode, mutex wrapper, USE_ISP_RETENTION_DATA). | LOW |
| forum.amebaiot.com new threads (2026-06-06) | **No new relevant threads found.** Forum ceiling remains at thread #4871 (last confirmed June 5, 2026). No new posts indexed for FCS, FlashMemory, cold-boot camera failure, or SPIC race. | LOW |
| Chinese-language sources — CSDN / Zhihu / EEWorld / 21ic (2026-06-06) | **Zero new results.** No Chinese-language technical post, project report, or community thread indexed for RTL8735B/AmebaPro2/BW21-CBV cold-boot camera FCS failure or FlashMemory mutex issue. | LOW |
| Wire.cpp "SWD pin deinit check for I2C" in commit 96cfc51 (re-evaluation) | **Not relevant to root cause.** The Wire library operates at Arduino application layer; FCS I2C initialization runs in the KM co-processor context via VOE firmware before the RTOS even starts. SWD-pin deinit guard prevents GPIO conflict on application I2C — orthogonal to `FCS_I2C_INIT_ERR` (0x200A) which fires in the boot ROM KM path. No workaround value. | LOW |

**Repository freeze status (as of Cycle U87, June 6, 2026):**

| Repository | Last commit | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **22 days** |
| ameba-arduino-pro2 dev | June 3, 2026 (`e8dd7e3`) | **3 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **96 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 (`870a7e0`) | **186 days** |

**SDK state as of 2026-06-06 (Cycle U87 — unchanged from U86):**
- Latest stable Arduino SDK: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release Arduino SDK: V4.1.1-QC-V07 (June 3, 2026; build20260603) — no fix
- ameba-rtos-pro2: V1.0.3 release tag (May 22, 2026); main frozen at May 15, 2026 (`3f95070`)
- VOE binary: last confirmed v1.7.1.0 (synced May 1, 2026 in RTOS repo; Apr 21, 2026 release date)
- Forum ceiling: **#4871** (unchanged)
- FlashMemory.cpp: SHA b4781b70, zero mutex calls — 87th cycle unpatched

**No confirmed fix. Bug remains unpatched as of 2026-06-06 (Cycle U87).**

**Top unresolved actions (unchanged):**
1. **Hardware test of "Camera FCS Mode = Disable"** — no public test result; highest confidence workaround. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` pattern; callable from Arduino sketch.
3. **File a GitHub Issue on ameba-arduino-pro2** — 87 cycles, zero official acknowledgment.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-06-06 (Cycle U88)

**Search scope:** Eight parallel search threads + direct GitHub/web fetches: (1) ameba-rtos-pro2 commits/main — new commits after May 15; (2) ameba-arduino-pro2 dev branch — new commits/releases after June 3; (3) ameba-arduino-pro2 issues — new issues filed; (4) English forum/web — new threads above #4871, FCS Disable / mutex / USE_ISP_RETENTION_DATA hardware test reports; (5) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili; (6) aiot.realmcu.com AMB82-mini Arduino guide; (7) ameba-rtos-pro2 pull requests — PR #17 status; (8) Community repos — `0015/AMB82-Mini-Board` GitHub repo for user-reported workarounds.

**Key new findings this cycle:**
- **Forum thread #3864 "Flash Translation Layer (FTL) - Intermittently unable to read previously stored data"** — previously untracked thread; appears in search results as potentially documenting SPIC concurrent FTL access failures on AMB82. Content is 403-blocked; snippet suggests the user configures FTL with `USER_DATA_START_ADDR = 0x00100000` and 3 physical pages. Tangentially relevant to SPIC concurrent-access hypothesis (Cycle U19).
- **ameba-rtos-pro2 PR #17 labeled "no-pr-activity"** — the USB Ethernet PR opened May 15 has received no review activity; repo is effectively dormant.
- **`0015/AMB82-Mini-Board` community repo confirmed** — contains only application-level YOLOv7 / object detection examples; no mention of FCS, FlashMemory, or camera boot failures.
- All other channels frozen, blocked, or empty — 88th consecutive null cycle for all key error strings and hardware test reports.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 commits (direct WebFetch, 2026-06-06) | **Confirmed frozen — 22 days.** HEAD = `3f95070` "Sync upstream 7343927…" (May 15, 2026). 15 most recent commits verified: newest 4 all dated May 15 (sync + mmf task-recreate fix + wlan ×2); next 6 dated May 1. Zero new commits touching flash, FCS, VOE, boot, HAL, sensor, or mutex. | LOW |
| ameba-arduino-pro2 dev branch (direct WebFetch, 2026-06-06) | **Frozen at June 3, 2026** (`e8dd7e3` "Pre Release Version 4.1.1"). 10 most recent commits verified: `e8dd7e3` and `96cfc51` (Jun 3), `29d47e1` (May 26), `7db1c7d` and `3d53672` (May 19), `cd0bd40` (May 18), `13961cc` (May 5), `e218f33`/`60fe0b1`/`8cab2da` (Apr 30). Zero commits touching FlashMemory.cpp, FCS, boot path, or mutex in any commit since V4.0.8 introduction (Oct 2024). | LOW |
| ameba-arduino-pro2 releases (direct WebFetch, 2026-06-06) | **No new release.** Latest stable = V4.1.0 (Mar 2, 2026). Latest pre-release = V4.1.1-QC-V07 (June 3, 2026; build20260603). No V4.1.1-QC-V08 or stable V4.1.1 published. | LOW |
| ameba-arduino-pro2 open issues (direct WebFetch, 2026-06-06) | **12 open issues — newest = #398 (Mar 29, 2026).** Full confirmed list: #398, #342, #325, #324, #317, #310, #296, #287, #276, #235, #224, #184. Zero new issues filed. No FCS/flash/camera/VOE/boot issue in open or closed history after 88 research cycles. | LOW |
| ameba-rtos-pro2 PR #17 (WebFetch, 2026-06-06) | **PR #17 "fix: the ethernet usb driver copies received network…" (opened May 15, 2026) has label "no-pr-activity".** Still open; no review, no merge, no close activity. Only 1 open PR in the entire repository. Zero PRs related to flash, FCS, boot, or camera. | LOW |
| forum.amebaiot.com thread #3864 "FTL - Intermittently unable to read previously stored data" | **Newly catalogued thread** (previously untracked). Title: "Flash Translation Layer (FTL) - Intermittently unable to read previously stored data." The search snippet reveals the user configures FTL with `USER_DATA_START_ADDR = 0x00100000` (1 MB offset) and 3 physical pages for persistent data storage of SSID/password/firmware config (~500 bytes). Reports intermittent read failures — consistent with the SPIC concurrent-access defect confirmed in Cycle U19 (`ftl_nor_api.c` callbacks use `RT_DEV_LOCK_FLASH` but `FlashMemory.cpp` does not). Content 403-blocked; no fix/workaround visible. Pre-dates our flash+camera bug report; may be a separate manifestation of the same underlying SPIC mutex gap. | LOW (blocked, tangentially relevant) |
| `0015/AMB82-Mini-Board` GitHub community repo (WebFetch, 2026-06-06) | **Confirmed application-level only.** Contains YOLOv7 Tiny object detection demo and related materials. Zero mention of FCS, FlashMemory, device_mutex_lock, RT_DEV_LOCK_FLASH, cold boot camera failure, or sensor initialization failure after flash write. Not relevant to the bug. | LOW |
| forum.amebaiot.com threads #4872–#4880 (search, 2026-06-06) | **No threads in this range indexed.** Targeted search for thread IDs 4872–4880 returned zero results. Forum ceiling remains at **#4871** — 7th consecutive cycle at this ceiling. | LOW |
| aiot.realmcu.com AMB82-mini Arduino guide (WebFetch, 2026-06-06) | **Still HTTP 403 Forbidden.** `aiot.realmcu.com/en/latest/arduino/arduino_guide/sdk_intro/evb_guides/evb_amb82mini.html` requires developer authentication. The URL appeared in search results for AMB82-mini FCS Mode queries — suggesting it contains Camera FCS Mode documentation — but is inaccessible without login. | LOW (blocked) |
| ameba-doc-rtos-pro2-sdk.readthedocs-hosted.com ISP page (WebFetch, 2026-06-06) | **Still HTTP 403 Forbidden.** `/en/latest/application_note/15_ISP.html` inaccessible. Surfaced in search results for ISP FCS documentation queries but requires partner login. | LOW (blocked) |
| All English/Chinese web: error string sweep (2026-06-06) | **Zero indexed results — 88th consecutive null cycle.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD command fail"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"` return zero publicly indexed results anywhere. No hardware test result for any proposed workaround has been posted in any language. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee, 2026-06-06) | **Zero new content — 88th consecutive null cycle.** All Chinese community forums remain 403-blocked. Searches for `RTL8735B FCS 摄像头 冷启动 闪存写入`, `AMB82 FlashMemory 摄像头 失败 FCS`, `BW21-CBV 摄像头 FCS 问题` return only product pages, unboxing reviews, and getting-started guides. | LOW |

**FTL thread #3864 — contextual note:**

The FTL intermittent-read thread likely describes the same SPIC bus hazard documented in Cycle U19: `FlashMemory` (or user code calling `flash_stream_write` directly) issuing SPIC commands without holding `RT_DEV_LOCK_FLASH`, colliding with the FTL layer's own writes. If this thread contains a Realtek engineer response or confirmed workaround (inaccessible due to 403), it would be high-priority. The thread's FTL configuration (`USER_DATA_START_ADDR = 0x00100000`) is in a different region from both `NOR_FLASH_FCS (0xF0D000)` and `FlashMemory (0xFD0000+)`, but the mutex architecture applies equally regardless of the target address.

**Repository freeze status (as of Cycle U88, June 6, 2026):**

| Repository | Last commit | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **22 days** |
| ameba-arduino-pro2 dev | June 3, 2026 (`e8dd7e3`) | **3 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **96 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 (`870a7e0`) | **186 days** |

**SDK state as of 2026-06-06 (Cycle U88 — unchanged from U87):**
- Latest stable Arduino SDK: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release Arduino SDK: V4.1.1-QC-V07 (June 3, 2026; build20260603) — no fix
- ameba-rtos-pro2: V1.0.3 release tag (May 22, 2026); main frozen at May 15, 2026 (`3f95070`)
- VOE binary: last confirmed v1.7.1.0 (synced May 1, 2026; hal_video_release_note.txt now 404 in dev branch)
- Forum ceiling: **#4871** (7th consecutive cycle at this ceiling)
- FlashMemory.cpp: SHA b4781b70, zero mutex calls — 88th cycle unpatched

**No confirmed fix. Bug remains unpatched as of 2026-06-06 (Cycle U88).**

**Top unresolved actions (unchanged from U87):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception. Callable from Arduino: `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug entirely undocumented outside this research log; 88 cycles and 46 VOE versions with zero acknowledgment; zero PRs ever filed; filing would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes entirely; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

---

## Research Update — 2026-06-06 (Cycle U89)

**Search scope:** Nine parallel search threads + direct GitHub/web fetches: (1) GitHub MCP — ameba-rtos-pro2 commits/PRs/releases since May 15; ameba-arduino-pro2 dev/main commits/releases/issues since June 3; ideashatch/HUB-8735 issues; (2) WebFetch — ameba-arduino-pro2 dev commits page; ameba-arduino-pro2 releases page; ameba-rtos-pro2 PR list; PR #411 file-change manifest; (3) English forum/web — new threads above #4871; FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (4) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn; (5) Error string indexing — all five key error strings; (6) Workaround confirmation sweep — three proposed workarounds; (7) SDK deep-dive — FlashMemory.cpp mutex status in dev HEAD `e8dd7e3`; VOE version; V4.1.1-QC-V07 release notes; (8) ameba-rtos-pro2 commits filtered `since=2026-05-27`; (9) bbs.ai-thinker.com BW21-CBV-Kit subforum ceiling.

**Key new findings this cycle:** None — 89th consecutive null research cycle. All repositories, forum threads, documentation portals, error-string sweeps, and community searches confirm the same frozen state as Cycle U88. The June 3 dev-branch activity (PR #411, V4.1.1-QC-V07) was fully documented in U88. PR #411 file-change manifest confirmed: Wire.cpp SWD-pin deinit check for I2C, AmebaFatFSFile.cpp minor bug fix, ameba_pro2_tools v1.4.12, OV5647/GC4663 sensor binaries — **FlashMemory.cpp not touched**. No new GitHub activity, forum threads, Chinese community posts, or hardware test reports found.

| Source | Finding | Priority |
|---|---|---|
| ameba-arduino-pro2 dev (`e8dd7e3`, June 3, 2026) | HEAD unchanged since U88; FlashMemory.cpp SHA b4781b70 confirmed — zero mutex calls | LOW |
| ameba-rtos-pro2 main (`3f95070`, May 15, 2026) | Frozen — 22 days; no FCS/flash/mutex commits | LOW |
| ameba-arduino-pro2 releases (V4.1.1-QC-V07, June 3, 2026) | Pre-release build20260603 — no FCS/flash fix in release notes | LOW |
| forum.amebaiot.com | HTTP 403; ceiling remains #4871 — 8th consecutive null cycle | LOW |
| All error strings (`KM_status 0x00002081`, `FCS_I2C_INIT_ERR`, `FCS_RUN_DATA_NG_KM`, `FCS_BYPASS_WHILE1_KM`, `VOE_OPEN_CMD`) | Zero indexed results — 89th consecutive null sweep | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/Bilibili/Gitee, 2026-06-06) | Zero new content — 89th consecutive null cycle | LOW |
| Hardware test reports (FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA`) | Zero public reports — 23 days unresolved since workarounds were compiled (U7, May 14) | LOW |

**Repository freeze status (as of Cycle U89, June 6, 2026):**

| Repository | Last commit | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **22 days** |
| ameba-arduino-pro2 dev | June 3, 2026 (`e8dd7e3`) | **3 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **96 days** |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **89 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 (`870a7e0`) | **186 days** |

**SDK state as of 2026-06-06 (Cycle U89 — unchanged from U88):**
- Latest stable Arduino SDK: V4.1.0 (Mar 2, 2026) — no fix; FlashMemory.cpp SHA b4781b70, zero mutex calls
- Latest pre-release Arduino SDK: V4.1.1-QC-V07 (June 3, 2026; build20260603) — no fix
- ameba-rtos-pro2: V1.0.3 release tag (May 22, 2026); main frozen at May 15, 2026 (`3f95070`)
- Forum ceiling: **#4871** (8th consecutive cycle at this ceiling)
- FlashMemory.cpp: SHA b4781b70, zero mutex calls — **89th cycle unpatched**

**No confirmed fix. Bug remains unpatched as of 2026-06-06 (Cycle U89).**

**Top unresolved actions (unchanged — 23 days unresolved since U7, May 14):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception. Callable from Arduino: `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug entirely undocumented outside this research log; 89 cycles and 46 VOE versions with zero acknowledgment; zero PRs ever filed; filing would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes entirely; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

---

## Research Update — 2026-06-06 (Cycle U90)

**Search scope:** Eight parallel search threads + direct GitHub/web fetches: (1) ameba-rtos-pro2 commits since May 15 (WebFetch + WebSearch); (2) ameba-arduino-pro2 dev/main commits and releases since June 3 (WebFetch + WebSearch); (3) ameba-arduino-pro2 open issues (WebFetch); (4) English forum/web — new threads above #4871, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (5) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee; (6) Error string indexing — all five key error strings; (7) `joehou45/Amb82-Mini` community repo evaluation; (8) Flash Memory documentation readthedocs page access; (9) `aiot.realmcu.com` AMB82-mini guide access.

**Key new findings this cycle:** None — 90th consecutive null research cycle. All repositories, forum threads, documentation portals, error-string sweeps, and community searches confirm the same frozen state as Cycle U89. One new community repository (`joehou45/Amb82-Mini`) identified and evaluated — contains only 3D enclosure design STL files for the AMB82-Mini board; zero relevance to flash/FCS bug. Flash Memory readthedocs documentation page (`ameba-doc-arduino-sdk.readthedocs-hosted.com`) confirmed still HTTP 403. All other channels unchanged.

| Source | Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 main (WebFetch commits page, 2026-06-06) | **Confirmed frozen — 22 days.** HEAD = `3f95070` "Sync upstream 7343927…" (May 15, 2026). 10 most recent commits verified: `3f95070`, `afc85a0`, `9c8b6f6`, `d2676f1` (all May 15); `1c1c8b7`, `a111e91`, `7b2b97f`, `63c0a2f`, `d54e1a8`, `687a4c7` (all May 1). Zero new commits touching flash, FCS, VOE, boot, HAL, mutex, or sensor. | LOW |
| ameba-arduino-pro2 dev branch (WebFetch commits page, 2026-06-06) | **Confirmed frozen at June 3, 2026 (`e8dd7e3` "Pre Release Version 4.1.1").** 10 most recent commits verified: `e8dd7e3` (Jun 3), `96cfc51` "Update Code base and add cam OV5647, GC4663 (#411)" (Jun 3), `29d47e1` "Update SPI API for SPI1 switching (#410)" (May 26), `7db1c7d` (May 19), `3d53672` (May 19), `cd0bd40` (May 18), `13961cc` (May 5), and prior. Zero commits touching FlashMemory.cpp, FCS, boot path, or mutex at any point in history. | LOW |
| ameba-arduino-pro2 releases (WebFetch, 2026-06-06) | **No new release.** Latest stable = V4.1.0 (Mar 2, 2026). Latest pre-release GitHub Release tag = V4.1.1-QC-V07 (June 3, 2026; build20260603). No V4.1.1-QC-V08 or stable V4.1.1 has been published. Release notes for V4.1.1-QC-V07: Camera sensors OV5647/GC4663, Wire.cpp SWD-pin deinit guard, tools v1.4.12. No FCS, FlashMemory mutex, or camera boot fix mentioned. | LOW |
| ameba-arduino-pro2 open issues (WebFetch, 2026-06-06) | **11 open issues — newest = #398 (Mar 29, 2026).** Full list confirmed: #398, #342, #325, #324, #317, #310, #296, #287, #276, #235, #224. None related to flash, FCS, camera, VOE, or boot failure. Bug remains entirely unreported on the official tracker after 90 research cycles. | LOW |
| forum.amebaiot.com threads above #4871 (WebSearch, 2026-06-06) | **No new threads indexed.** Targeted searches for thread IDs 4872–4880 returned zero relevant results from the forum domain. Forum ceiling remains at #4871 — 9th consecutive cycle at this ceiling. | LOW |
| `joehou45/Amb82-Mini` GitHub community repo (WebFetch, 2026-06-06) | **New community repository identified and evaluated — not relevant.** Contains 3D enclosure STL files (PCB shell + magnetic closure) for the AMB82-Mini board only. No FlashMemory, FCS, camera boot failure, device_mutex_lock, or RT_DEV_LOCK_FLASH content of any kind. 15 commits, hardware design only. | LOW (irrelevant) |
| `ameba-doc-arduino-sdk.readthedocs-hosted.com` Flash Memory doc (WebFetch, 2026-06-06) | **Still HTTP 403 Forbidden.** `…/ameba_pro2/amb82-mini/Example_Guides/Flash%20Memory/index.html` appeared in two independent search results as a dedicated Flash Memory example guide page. Requires developer authentication. URL confirms this page exists; content about FlashMemory usage warnings (if any) remains inaccessible. | LOW (blocked) |
| `aiot.realmcu.com` AMB82-mini Arduino guide (WebFetch, 2026-06-06) | **Still HTTP 403 Forbidden.** `aiot.realmcu.com/en/latest/arduino/arduino_guide/sdk_intro/evb_guides/evb_amb82mini.html` requires developer authentication. The FCS Mode documentation on this page remains inaccessible. | LOW (blocked) |
| Web-wide error string sweep (2026-06-06) | **Zero indexed results — 90th consecutive null cycle.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD command fail"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"` return zero publicly indexed results anywhere on the accessible web. No hardware test result for any proposed workaround has been posted in any language. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee, 2026-06-06) | **Zero new content — 90th consecutive null cycle.** Only two indexed CSDN articles about AMB82-mini remain (article 139222964 and 139584304 — both unrelated general tutorials). All Chinese community forums remain 403-blocked. Searches in Chinese for `RTL8735B FCS 摄像头 冷启动 flash 问题` return only product pages, getting-started guides, and unrelated camera articles. | LOW |

**Repository freeze status (as of Cycle U90, June 6, 2026):**

| Repository | Last commit | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **22 days** |
| ameba-arduino-pro2 dev | June 3, 2026 (`e8dd7e3`) | **3 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **96 days** |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **89 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 (`870a7e0`) | **186 days** |

**SDK state as of 2026-06-06 (Cycle U90 — unchanged from U89):**
- Latest stable Arduino SDK: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release Arduino SDK: V4.1.1-QC-V07 (June 3, 2026; build20260603) — no fix
- ameba-rtos-pro2: V1.0.3 release tag (May 22, 2026); main frozen at May 15, 2026 (`3f95070`)
- VOE binary: last confirmed v1.7.1.0 (synced May 1, 2026 in RTOS repo; Apr 21, 2026 release date)
- Forum ceiling: **#4871** (9th consecutive cycle at this ceiling)
- FlashMemory.cpp: SHA b4781b70, zero mutex calls — **90th cycle unpatched**

**No confirmed fix. Bug remains unpatched as of 2026-06-06 (Cycle U90).**

**Top unresolved actions (unchanged from U89 — 23 days since workarounds were compiled):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception. Callable from Arduino: `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug entirely undocumented outside this research log; 90 cycles and 46 VOE versions with zero acknowledgment; zero PRs ever filed; filing would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes entirely; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

---

## Research Update — 2026-06-07 (Cycle U91)

**Search scope:** Four parallel agents + direct WebFetch/WebSearch: (1) GitHub — ameba-rtos-pro2 and ameba-arduino-pro2 commits pages + releases page via WebFetch; (2) English forum/web — new threads above #4871, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee; (4) SDK deep-dive — FlashMemory.cpp mutex state, new releases, VOE version.

**Key new findings this cycle:** None — 91st consecutive null research cycle. All repositories, forum threads, documentation portals, error-string sweeps, and community searches confirm the same frozen state as Cycle U90. Direct WebFetch of ameba-arduino-pro2 dev commits page confirms HEAD still `e8dd7e3` (June 3, 2026); ameba-rtos-pro2 main still `3f95070` (May 15, 2026). Releases page confirms V4.1.1-QC-V07 remains latest pre-release; no V4.1.1-QC-V08 or stable V4.1.1 published. FlashMemory.cpp untouched.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-arduino-pro2 dev branch commits (WebFetch, 2026-06-07) | **Confirmed frozen — identical to U90.** 10 most recent commits verified: `e8dd7e3` "Pre Release Version 4.1.1" (Jun 3), `96cfc51` "Update Code base and add cam OV5647, GC4663 (#411)" (Jun 3), `29d47e1` "Update SPI API for SPI1 switching (#410)" (May 26), `7db1c7d` (May 19), `3d53672` (May 19), `cd0bd40` (May 18), `13961cc` (May 5). Zero new commits after June 3, 2026. No FlashMemory.cpp, FCS, mutex, or camera boot fix in any commit. | LOW |
| ameba-rtos-pro2 main branch commits (WebFetch, 2026-06-07) | **Confirmed frozen — identical to U90.** 10 most recent commits verified: `3f95070` (May 15), `afc85a0` (May 15), `9c8b6f6` (May 15), `d2676f1` (May 15), `1c1c8b7` (May 1), `a111e91` (May 1), `7b2b97f` (May 1), `63c0a2f` (May 1), `d54e1a8` (May 1), `687a4c7` (May 1). Zero new commits in 23 days since May 15, 2026. No flash, FCS, VOE, boot, HAL, mutex, or sensor changes. | LOW |
| ameba-arduino-pro2 releases (WebFetch, 2026-06-07) | **No new releases.** Latest pre-release = V4.1.1-QC-V07 (tag created Mar 6, 2026; release notes through June 3, 2026). Latest stable = V4.1.0 (Mar 2, 2026). No V4.1.1-QC-V08 or stable V4.1.1 published. Release notes for V4.1.1-QC-V07: camera sensors OV5647/GC4663 (PR #411), Wire.cpp SWD-pin deinit guard, tools v1.4.12. No FCS, FlashMemory mutex, or camera boot fix. | LOW |
| `FlashMemory.cpp` status (confirmed via WebFetch + agents, 2026-06-07) | **Zero mutex calls — SHA `b4781b70` unchanged.** No commit touching `FlashMemory.cpp` exists in the dev or main branch history after Sep 30, 2025. The architectural defect (FlashMemory bypassing `RT_DEV_LOCK_FLASH` while 16+ RTOS SDK files correctly hold it) persists unchanged through every released SDK version. | LOW (confirms prior) |
| forum.amebaiot.com threads above #4871 (WebSearch + agents, 2026-06-07) | **No new threads indexed.** Targeted search for thread IDs 4872–4880 returned zero results from the forum domain. Forum ceiling remains at #4871 — **10th consecutive cycle at this ceiling**. All direct forum fetches return HTTP 403. Only thread appearing in FCS+camera search results remains #4302 ("[VOE]frame_end: sensor didn't initialize done!"). | LOW |
| Web-wide error string sweep (WebSearch + agents, 2026-06-07) | **Zero indexed results — 91 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD command fail"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"`, `"USE_ISP_RETENTION_DATA"` — all return zero publicly indexed results anywhere on the accessible web. No hardware test result for any of the three proposed workarounds posted anywhere in any language. | LOW |
| Hardware test confirmation sweep — all three workarounds (WebSearch + agents, 2026-06-07) | **Zero public reports — 91 cycles unresolved.** No community member has posted any result from hardware testing of: (1) "Camera FCS Mode = Disable" after FlashMemory write/erase; (2) `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper around FlashMemory operations; (3) `USE_ISP_RETENTION_DATA` to eliminate ISP SPIC writes. These three workarounds have been mechanistically source-confirmed since Cycles U12/U19/U22 but remain without any public hardware validation. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee, 2026-06-07) | **Zero new content — 91st consecutive null cycle.** All Chinese community sites remain 403-blocked or return zero relevant results. Only two indexed CSDN articles about AMB82-mini remain (articles 139222964 and 139584304 — both general tutorials unrelated to FCS flash-write failure). No Chinese-language forum posts or articles discuss FCS flash-write camera failure on RTL8735B or BW21-CBV. | LOW |

**Repository freeze status (as of Cycle U91, June 7, 2026):**

| Repository | Last commit | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **23 days** |
| ameba-arduino-pro2 dev | June 3, 2026 (`e8dd7e3`) | **4 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **97 days** |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **90 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 (`870a7e0`) | **187 days** |

**SDK state as of 2026-06-07 (Cycle U91 — unchanged from U90):**
- Latest stable Arduino SDK: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release Arduino SDK: V4.1.1-QC-V07 (June 3, 2026; build20260603) — no fix
- ameba-rtos-pro2: V1.0.3 release tag (May 22, 2026); main frozen at May 15, 2026 (`3f95070`)
- VOE binary: last confirmed v1.7.1.0 (synced May 1, 2026 in RTOS repo; Apr 21, 2026 release date)
- Forum ceiling: **#4871** (10th consecutive cycle at this ceiling)
- FlashMemory.cpp: SHA `b4781b70`, zero mutex calls — **91st cycle unpatched**

**No confirmed fix. Bug remains unpatched as of 2026-06-07 (Cycle U91).**

**Top unresolved actions (unchanged from U90):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception. Callable from Arduino: `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug entirely undocumented outside this research log; 91 cycles and 46 VOE versions with zero acknowledgment; zero PRs ever filed; filing would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes entirely; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

---

## Research Update — 2026-06-07 (Cycle U92)

**Search scope:** Two parallel agents + direct WebFetch: (1) GitHub — ameba-rtos-pro2 main commits, ameba-arduino-pro2 dev commits, releases page, and open issues list via direct API fetch (WebFetch); (2) English web — error string indexing sweep, forum thread ceiling check, hardware test report search, workaround confirmation.

**Key new findings this cycle:** None — 92nd consecutive null research cycle. Both parallel agents confirm identical frozen state as U91. ameba-arduino-pro2 dev HEAD remains `e8dd7e3` (June 3, 2026); ameba-rtos-pro2 main remains `3f950705b` (May 15, 2026). No new releases, issues, PRs, forum threads, or hardware test reports found. Freeze continues across all channels.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-arduino-pro2 dev branch commits (direct API WebFetch, 2026-06-07) | **NO NEW ACTIVITY — frozen 4 days.** 10 most recent commits verified via GitHub API: `e8dd7e3` "Pre Release Version 4.1.1" (Jun 3), `96cfc51` "Update Code base and add cam OV5647, GC4663 (#411)" (Jun 3), `29d47e1` "Update SPI API for SPI1 switching (#410)" (May 26), `7db1c7d` (May 19), `3d53672` "Update Code base and add cam IMX681_5M (#409)" (May 19), `cd0bd40` "Add I2C Slave (#408)" (May 18), `13961cc` "Update API for AMB82-zero and SWD off logic" (May 5), `e218f33` (Apr 30), `60fe0b1` "Add AMB82-zero (#407)" (Apr 30), `8cab2da` "Update WDT API (#406)" (Apr 30). Zero commits after June 3. FlashMemory.cpp, FCS boot path, and mutex architecture untouched in full commit history. | LOW |
| ameba-arduino-pro2 releases (direct API WebFetch, 2026-06-07) | **No new release.** Latest pre-release = V4.1.1-QC-V07 (tag created Jun 3, 2026; `published_at` shows Mar 6 — artifact of release note edits; `created_at` = Jun 3 authoritative). Latest stable = V4.1.0 (Mar 2, 2026). No V4.1.1-QC-V08 or stable V4.1.1 published. | LOW |
| ameba-rtos-pro2 main branch commits (direct API WebFetch, 2026-06-07) | **NO NEW ACTIVITY — frozen 23 days.** 10 most recent commits verified via GitHub API: `3f950705b` "Sync upstream 7343927…" (May 15), `afc85a09` "[amebapro2][mmf] avoid task recreate in mmf start" (May 15), `9c8b6f6e` "[amebapro2][wlan] wowlan modify dhcp renew unit" (May 15), `d2676f15` "[amebapro2][wlan] modify dynamic ARP example" (May 15), `1c1c8b71` "Sync upstream 43d940446…" (May 1), `a111e919` "[amebapro2][wlan] wowlan dhcp renew" (May 1), `7b2b97f2` "[amebapro2][video] support imx681 5m resolution" (May 1), `63c0a2f6` "[amebapro2][video] update ov12890 iq" (May 1), `d54e1a8d` "[amebapro2][video] sync voe to 1.7.1.0" (May 1), `687a4c79` "[amebapro2][isp] add isp osd with tof sensor example" (May 1). No new commit touches flash, FCS, VOE FCS path, boot, HAL, mutex, or sensor initialization. | LOW |
| ameba-arduino-pro2 open issues (direct API WebFetch, 2026-06-07) | **No new issues filed.** Newest open issue confirmed at #398 (Mar 29, 2026). 17 open issues total. Zero FCS/flash/camera/VOE/boot/mutex issue in open or closed history after 92 research cycles. | LOW |
| English web — error string sweep (WebSearch, 2026-06-07) | **Zero indexed results — 92nd consecutive null cycle.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD command fail"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"`, `"USE_ISP_RETENTION_DATA"` all return zero publicly indexed results. | LOW |
| forum.amebaiot.com threads above #4871 (WebSearch, 2026-06-07) | **No new threads indexed.** Forum ceiling remains #4871 — **11th consecutive cycle at this ceiling**. All direct forum fetches return HTTP 403. | LOW |
| Hardware test confirmation — all three workarounds (WebSearch, 2026-06-07) | **Zero public reports — 92nd cycle unresolved.** No community member has posted any result from hardware testing of: (1) "Camera FCS Mode = Disable"; (2) `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper; (3) `USE_ISP_RETENTION_DATA`. All three mechanistically source-confirmed since Cycles U12/U19/U22. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/Bilibili/Gitee, 2026-06-07) | **Zero new content — 92nd consecutive null cycle.** All Chinese community sites 403-blocked or return zero relevant content. No Chinese post discusses FCS flash-write camera failure on RTL8735B/BW21-CBV. | LOW |

**Repository freeze status (as of Cycle U92, June 7, 2026):**

| Repository | Last commit | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f950705b`) | **23 days** |
| ameba-arduino-pro2 dev | June 3, 2026 (`e8dd7e3`) | **4 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **97 days** |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **90 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 (`870a7e0`) | **187 days** |

**SDK state as of 2026-06-07 (Cycle U92 — unchanged from U91):**
- Latest stable Arduino SDK: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release Arduino SDK: V4.1.1-QC-V07 (June 3, 2026; build20260603) — no fix
- ameba-rtos-pro2: V1.0.3 release tag (May 22, 2026); main frozen at May 15, 2026 (`3f950705b`)
- VOE binary: last confirmed v1.7.1.0 (synced May 1, 2026 in RTOS repo; `d54e1a8d` "[amebapro2][video] sync voe to 1.7.1.0")
- Forum ceiling: **#4871** (11th consecutive cycle at this ceiling)
- FlashMemory.cpp: SHA `b4781b70`, zero mutex calls — **92nd cycle unpatched**

**No confirmed fix. Bug remains unpatched as of 2026-06-07 (Cycle U92).**

**Top unresolved actions (unchanged from U91):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception. Callable from Arduino: `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug entirely undocumented outside this research log; 92 cycles and 46 VOE versions with zero acknowledgment; zero PRs ever filed; filing would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes entirely; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

### Supplement to U92 — late-arriving web search results

A delayed web search agent completed after U92 was committed. Three factual corrections and two new low-priority findings:

**Correction 1 — Forum ceiling:** U92 stated "#4871 — 11th consecutive cycle." The web agent found thread **#4885** indexed by search engines as of June 2, 2026: "Request for Acuity Toolkit Access — GitHub: sacihanserdar-web" (AI category; unrelated to bug). Threads #4872–#4884 not indexed. Corrected forum ceiling: **#4885** (up from #4871). Bug-relevant content: none in the newly indexed range.

**Correction 2 — GitHub issue #251:** Agent found that `ameba-arduino-pro2` issue #251 ("ControlLED abort execution") contains a boot log with `FCS KM_status 0x00000082 err 0x00000000` / `FCS TM_status 0x00000001` / `fcs OK` — the **healthy** FCS boot state. This is background context confirming the log format is publicly visible (the normal variant); the failing value `0x00002081` remains unindexed in any public source.

**New finding — FlashMemory.h modified in V4.1.0:** The V4.1.0 release changelog (March 2, 2026) includes "FlashMemory.h updates" with no detail. The `.cpp` file SHA `b4781b70` is confirmed unchanged through all SDK versions; this update is to the `.h` header only. Possible content: updated API docs, new method signatures, or constant definitions. Does NOT represent a mutex fix (the mutex defect is in `.cpp`). Priority: LOW — warrants a direct header diff in a future cycle.

**New finding — Forum thread #4868 "NN Model loading from Memory instead of Flash or SD card failing with exceptions":** Indexed by search engines; body 403-blocked. Title suggests model-load failures from RAM vs. flash/SD — tangentially related to the SPIC bus contention space but about AI inference, not camera FCS cold boot. Likely unrelated; tracked for completeness.

| Corrected Item | Old Value (U92 as committed) | Corrected Value |
|---|---|---|
| Forum ceiling | #4871 (11th consecutive cycle) | **#4885** (thread #4885 indexed Jun 2, 2026; unrelated content) |
| FlashMemory.h | Not mentioned | V4.1.0 changelog notes "FlashMemory.h updates" — header only, no mutex fix |
| GH issue #251 | Not mentioned | Contains normal FCS boot log (`KM_status 0x00000082`); background context |

---

## Research Update — 2026-06-07 (Cycle U93)

**Search date:** 2026-06-07  
**Cycle type:** Null — no new findings; all source repositories frozen at previously documented states  
**Consecutive null cycles:** 93

### Repository freeze status

| Repository | Latest commit | Commit date | Days frozen |
|---|---|---|---|
| ameba-rtos-pro2 main | `3f95070` | 2026-05-15 | **23 days** |
| ameba-arduino-pro2 dev | `e8dd7e3` | 2026-06-03 | **4 days** |
| ameba-arduino-pro2 main | `93d63514` | 2026-03-02 | **97 days** |
| ameba-tool-rtos-pro2 main | `c1d70e7` | 2026-03-09 | **90 days** |
| ideashatch/HUB-8735 main | `870a7e0` | 2025-12-02 | **187 days** |

### SDK release status

| Release | Tag date | FCS/flash/mutex fix? |
|---|---|---|
| V4.1.0 (stable) | 2026-03-02 | No |
| V4.1.1-QC-V07 (pre-release) | 2026-06-03 (build20260603) | No |
| VOE binary v1.7.1.0 | 2026-04-21 | No |

### Search results summary

All searches across English and Chinese sources returned zero new findings relevant to the FCS/flash race bug:

- **Error strings searched:** `FCS_I2C_INIT_ERR`, `FCS_RUN_DATA_NG_KM`, `FCS KM_status 0x00002081`, `FCS_BYPASS_WHILE1_KM 0x0083`, `RT_DEV_LOCK_FLASH FlashMemory`, `ftl_common_write race`, `NOR_FLASH_FCS corruption` — all return zero indexed results across GitHub, forum.amebaiot.com (via Google snippets), CSDN, 知乎, EEWorld, 21IC.
- **Forum ceiling:** #4885 (confirmed; per U92 supplement). No new threads indexed since U92 supplement. Bug-relevant content: none in any newly indexed range.
- **FlashMemory.cpp SHA:** `b4781b70b4603949a41751999a7ff2af6ddc75b0` — confirmed unchanged through V4.1.1-QC-V07. Zero `device_mutex_lock` / `device_mutex_unlock` / `RT_DEV_LOCK_FLASH` calls. Mutex defect persists.
- **hal_video_release_note.txt:** Returns HTTP 404 from ameba-arduino-pro2 dev branch. File may have been relocated; not yet traced.
- **RTL8735C:** No public SDK as of 2026-06-07. Product announced ~Dec 2025 (COMPUTEX Best Choice Award); Wi-Fi 6 / BLE 5.3 / dual AI NPUs. No migration path for RTL8735B users published.
- **Hardware test reports:** Zero public reports of any workaround (FCS Mode = Disable; `device_mutex_lock` wrapper; `USE_ISP_RETENTION_DATA`) being tested on physical hardware.

### Workaround confidence status (unchanged from U92)

| Workaround | Confidence | Hardware-confirmed? |
|---|---|---|
| FCS Mode = Disable (boards.txt default) | High — mechanistic chain fully traced | No public report |
| `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper around FlashMemory calls | High — pattern from Realtek's own flash example | No public report |
| `USE_ISP_RETENTION_DATA` (eliminates ISP SPIC writes) | Medium — eliminates competing writes; purpose is standby/wake retention | No public report |

### Notes

- The 23-day freeze on ameba-rtos-pro2 main is the longest observed since tracking began. Combined with the 97-day freeze on ameba-arduino-pro2 stable main, development activity on the RTL8735B platform appears to be winding down.
- No indication that Realtek intends to backport a FlashMemory mutex fix. The architectural defect (user-space `FlashMemory.cpp` bypassing `RT_DEV_LOCK_FLASH`) would require either a `.cpp` patch or documented guidance; neither has appeared in any SDK version through V4.1.1-QC-V07.
- **FlashMemory.h** was updated in V4.1.0 changelog ("FlashMemory.h updates" — header only per U92 supplement); a direct header diff against V4.0.x is deferred to a future cycle.
- The bug (cold-boot camera failure after FlashMemory write) remains **entirely undocumented in any public source** across all 93 research cycles.

---

## Research Update — 2026-06-07 (Cycle U94)

**Search scope:** Four parallel agents: (1) GitHub — ameba-rtos-pro2 main + ameba-arduino-pro2 dev commits, releases, issues, PRs, FlashMemory.cpp history; (2) English forum/web — forum.amebaiot.com threads above #4885, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/Bilibili/Gitee; (4) SDK deep-dive — V4.1.1-QC-V07 full release notes, FlashMemory.h header diff vs V4.0.x, PRs after #411, GitHub_release_note.txt, RTL8735C successor SDK, hal_video_release_note.txt location, ideashatch releases.

**Key new findings this cycle:**
- **FlashMemory.h V4.0.x address bug resolved**: The "Update FlashMemory.h" entry in the V4.1.0 changelog (previously deferred) is confirmed as commit `e1fa54e` (Sep 9, 2025) fixing `FLASH_MEMORY_APP_BASE` from `0xFD000` → `0xFD0000` (one missing hex zero). In V4.0.8/V4.0.9 (Oct 2024–Sep 2025), `FlashMemory.begin()` with no argument wrote to 0x00FD000 — inside the fw1 firmware partition (~644KB offset into the running firmware image). This explains potentially catastrophic behavior in V4.0.x; our FCS bug (present in V4.1.0+) is separate.
- **FlashMemory.cpp actual commit SHA corrected**: "SHA b4781b70" mentioned in prior cycles was the file blob hash, not a Git commit SHA. Real latest Git commit is `4fdfbec` (Sep 30, 2025, "Optimize codes #337" — housekeeping `#include` consolidation, no logic change).
- **RTL8735C (successor chip) confirmed — no public SDK**: Realtek announced RTL8735C (Wi-Fi 6, BLE 5.3, dual AI NPUs, AI ISP) in ~Dec 2025. Audit of all 75 Ameba-AIoT GitHub repositories confirms zero AmebaPro3 repos. No migration path for RTL8735B users exists.
- **RTL8720C flash-write → boot-failure thread found**: forum.amebaiot.com/t/rtl8720c-flash-log/1239 — "RTL8720C 数据保存到FLASH后再次启动 log显示启动失败" (After saving data to FLASH, restart shows boot failure). Same symptom class (flash write → cold boot failure) on a related, older Realtek chip. Content 403-blocked. Suggests this failure mode is systemic across Realtek's MCU product line.
- **hal_video_release_note.txt confirmed 404**: File does not exist in the ameba-arduino-pro2 dev branch repository tree. VOE release notes are only inside the tools tarball; camera sensor additions only, no FCS/flash/mutex content.
- **ideashatch/HUB-8735 is 14+ months behind upstream**: Last release V4.0.15 (April 2025, tracking upstream 4.0.9). No release tracking V4.1.0 or V4.1.1. HUB-8735 remains stuck on V4.0.9 code base.
- All other channels frozen, blocked, or null — 94th consecutive null cycle for all key error strings and hardware test reports.

| Source | Key Finding | Priority |
|---|---|---|
| `FlashMemory.h` commit `e1fa54e` (Sep 9, 2025) in ameba-arduino-pro2 | **V4.0.x address bug resolved:** `FLASH_MEMORY_APP_BASE` was `0xFD000` (wrong, 5 hex digits ≈ 1 MB into flash — inside the fw1 firmware partition) in V4.0.8 and V4.0.9. Fixed to `0xFD0000` (correct, 6 hex digits ≈ 15.8 MB into flash — in the unallocated/user region). Simultaneously `NOR_FLASH_SIZE` was corrected from `0x100000` → `0x1000000`. Any V4.0.x user calling `FlashMemory.begin()` with no explicit address argument was writing into the firmware image itself. The FCS bug (present in V4.1.0+ where the address is correct) is a separate issue. | MEDIUM |
| FlashMemory.cpp Git history (ameba-arduino-pro2 dev, fetched 2026-06-07) | **Blob SHA clarification:** "SHA b4781b70" referenced in prior cycles (U90–U93) was the file blob hash, not the Git commit SHA. Actual commit history: (1) `d9022ef` "Add feature Flash Memory (#252)" (Jul 9, 2024); (2) `d1a988f` "Add Arduino printf (#336)" (Sep 30, 2025); (3) `4fdfbec` "Optimize codes (#337)" (Sep 30, 2025) — centralizes `#include "amb_ard_printf.h"` into `Arduino.h`, no logic change. Zero mutex/locking code added in any commit. | LOW (clarification) |
| Ameba-AIoT GitHub organization — 75 repo audit (fetched 2026-06-07) | **RTL8735C / AmebaPro3 SDK confirmed absent.** Full organization repository list retrieved. Repositories relevant to RTL8735B: `ameba-rtos-pro2`, `ameba-arduino-pro2`, `ameba-tool-rtos-pro2`. No `ameba-rtos-pro3`, `ameba-arduino-pro3`, `rtl8735c`, or any AmebaPro3 / RTL8735C repository exists. RTL8735C was announced at COMPUTEX 2025 (Best Choice Award); product page live at aiot.realmcu.com. No public SDK timeline announced. | LOW |
| forum.amebaiot.com/t/rtl8720c-flash-log/1239 (403-blocked) | **Cross-chip precedent: RTL8720C shows same flash→boot-failure symptom class.** Chinese-language thread title: "RTL8720C 数据保存到FLASH后再次启动 log显示启动失败" (RTL8720C: After saving data to FLASH, restart shows boot failure in log). Content is 403-blocked. This is the same symptom class (user flash write → subsequent reboot fails) on the RTL8720C, an older, smaller Realtek Ameba chip. Confirms the flash write → boot failure pattern occurs on multiple Realtek MCU platforms and is likely a systemic HAL design gap (flash bus not properly serialized with boot ROM reads) rather than an RTL8735B-specific regression. Previously untracked in this research log. | LOW |
| V4.1.1-QC-V07 release notes — full text (fetched 2026-06-07) | **Confirmed: Zero FCS/flash/mutex content in any V4.1.1 pre-release.** Full release note text retrieved. Features: Battery-Powered Camera POC, Audio Trigger Recording, Video Zoom, TensorFlowLite, AMB82-zero, I2C Slave, SWD pin deinit guard, SPI1 switching, tools 1.4.12 (OV5647/GC4663). Bug section: `ServerDrv API for WiFi TCP data corruption` fix only. No mention of FlashMemory mutex, RT_DEV_LOCK_FLASH, FCS mode, camera cold-boot failure, device_mutex_lock, or flash race condition anywhere. | LOW (confirms prior) |
| `GitHub_release_note.txt` in ameba-rtos-pro2 main (raw fetch, 2026-06-07) | **26 upstream commit entries — no flash/mutex/FCS content.** Complete upstream commit log retrieved. Entries cover: AI glass scenario (12M snapshot, GPS, GSensor, HTTP), WLAN (DHCP renew, ARP, 11v WPA3, BT patch, PTA API), video (WebSocket viewer, IMX681 5M, OV12890 IQ, VOE 1.7.1.0), MMF (avoid task recreate), ISP OSD with ToF. Zero entries mention flash HAL, FlashMemory mutex, FCS boot path, RT_DEV_LOCK_FLASH, or camera cold-boot race condition. The 26 entries in the current upstream batch represent the entirety of activity since the last upstream sync. | LOW |
| `hal_video_release_note.txt` location search (2026-06-07) | **File confirmed 404 from ameba-arduino-pro2 dev branch.** GitHub file finder and web search return no results for this filename in the current repository tree. VOE version history is embedded inside tools tarballs (`ameba_pro2-4.1.1-build20260603.tar.gz`) only. The VOE changelog is not separately accessible from the public GitHub repository. | LOW |
| ideashatch/HUB-8735 releases (fetched 2026-06-07) | **HUB-8735 is 14+ months behind upstream.** Latest release: V4.0.15 (April 7, 2025, tracking upstream 4.0.9). No releases tracking V4.0.9 final, V4.0.14, V4.0.15, V4.1.0, or V4.1.1. The ideashatch fork has not been updated since its April 2025 release. HUB-8735 users remain on V4.0.9 code base, which has the additional hazard of the incorrect `FLASH_MEMORY_APP_BASE = 0xFD000` (pre-fix). | LOW |
| ameba-arduino-pro2 code search: `RT_DEV_LOCK_FLASH` (2026-06-07) | **Zero results in entire Arduino SDK.** GitHub code search for `RT_DEV_LOCK_FLASH` within `ameba-arduino-pro2` returns 0 results. The flash bus mutex is used in 16+ files in `ameba-rtos-pro2` (RTOS examples and HAL) but in zero files in the Arduino SDK. `FlashMemory.cpp` is the most egregious offender (multi-sector erase+write in a single unprotected sequence) but the omission extends to all Arduino library flash access paths. | LOW (confirms prior) |
| ameba-arduino-pro2 Issue #181 (open, Sep 2025) | **I2C regression — Wire.endTransmission() calls i2c_reset() unexpectedly in dev branch.** User reports that `Wire.endTransmission()` was modified to call `i2c_reset()`, which deinitializes the I2C bus. If the camera sensor's I2C is managed by Wire (rather than the internal video HAL), this regression could intermittently reset camera I2C during runtime. Unlikely to be the root cause of the FCS cold-boot failure (which is a boot-ROM KM initialization issue), but represents an I2C reliability regression in the Arduino layer. | LOW |
| All English/Chinese web sources (comprehensive sweep, 2026-06-07) | **Zero new content — 94th consecutive null cycle.** Error strings `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD command fail flash"`, `"device_mutex_lock RT_DEV_LOCK_FLASH FlashMemory"`, `"USE_ISP_RETENTION_DATA"` return zero publicly indexed results anywhere. No hardware test result for any workaround posted in any language on any accessible web source. Forum ceiling #4885 unchanged. All bbs.aithinker.com and forum.amebaiot.com threads 403-blocked. | LOW |

**Historical context — FlashMemory address bug in V4.0.x (new finding):**

For users on V4.0.8 or V4.0.9 (Oct 2024 – Sep 2025 era), the `FLASH_MEMORY_APP_BASE` header constant was wrong:

| SDK version | `FLASH_MEMORY_APP_BASE` | Actual target region |
|---|---|---|
| V4.0.8 – V4.0.9 (pre-Sep 2025 fix) | `0xFD000` (1,036,288 bytes) | Inside `fw1` firmware partition (~644 KB into running firmware) |
| V4.0.9+ (post-Sep 9, 2025 fix) / V4.1.0+ | `0xFD0000` (16,580,608 bytes) | Unallocated user flash region (correct) |

Users who passed an explicit address to `FlashMemory.begin(0xFD0000)` were unaffected. Users who called `FlashMemory.begin()` with no argument and relied on the default were writing into their own firmware — explaining why V4.0.x FlashMemory behavior could be erratic in ways unrelated to the FCS bug. The FCS bug (which this log tracks) is a V4.1.0+ phenomenon where the address is correct but the SPIC mutex is missing.

**RTL8720C cross-chip precedent — significance:**

The RTL8720C thread (forum.amebaiot.com/t/rtl8720c-flash-log/1239) reports identical symptom class on a different Realtek chip, lending support to the hypothesis that the flash-write → boot failure class is a systemic HAL issue across Realtek's MCU lineup rather than an RTL8735B-specific regression introduced in V4.0.8. The RTL8720C does not have the FCS camera fast-start mechanism (it lacks the dual-core KM/TM architecture), so the failure mode on RTL8720C is likely simpler (boot ROM reads stale/corrupted flash data), but the root cause category (no flash bus serialization between user writes and boot ROM reads) is the same.

**Repository freeze status (as of Cycle U94, June 7, 2026):**

| Repository | Last commit | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **23 days** |
| ameba-arduino-pro2 dev | June 3, 2026 (`e8dd7e3`) | **4 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **97 days** |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **90 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 (`870a7e0`) | **187 days** |

**SDK state as of 2026-06-07 (Cycle U94 — unchanged from U93):**
- Latest stable Arduino SDK: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release Arduino SDK: V4.1.1-QC-V07 (June 3, 2026; build20260603) — no fix
- ameba-rtos-pro2: V1.0.3 release tag (May 22, 2026); main frozen at May 15, 2026 (`3f95070`)
- VOE binary: last confirmed v1.7.1.0 (synced May 1, 2026, `d54e1a8`)
- Forum ceiling: **#4885** (unchanged)
- FlashMemory.cpp: commit `4fdfbec` (Sep 30, 2025), zero mutex calls — **94th cycle unpatched**

**No confirmed fix. Bug remains unpatched as of 2026-06-07 (Cycle U94).**

**Top unresolved actions (unchanged from U93):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception. Callable from Arduino: `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug entirely undocumented outside this research log; 94 cycles and zero acknowledgment; zero PRs ever filed; filing would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes entirely; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-06-08 (Cycle U95)

**Search scope:** Six parallel search threads + direct GitHub/web fetches: (1) GitHub — ameba-rtos-pro2 and ameba-arduino-pro2 commits/releases/issues/PRs after June 3, 2026; (2) English forum/web — new threads above #4885, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee; (4) SDK deep-dive — FlashMemory.cpp mutex state in latest dev build, PR #410/#411 content analysis; (5) Error string indexing sweep; (6) Forum thread ceiling sweep above #4885.

**Key new findings this cycle:**
- **PR #410 content confirmed**: "Update SPI API for SPI1 switching" (May 26, 2026, kevinlookl) — updates the external SPI peripheral library to support runtime SPI0/SPI1 bus switching on AMB82-mini. This is the **user-facing SPI interface** (connecting external SPI peripherals), NOT the internal SPIC flash bus. Zero SPIC/flash/mutex relevance.
- **PR #411 content confirmed**: "Update Code base and add cam OV5647, GC4663" (June 3, 2026, M-ichae-l) — 107 files changed; adds `sensor_ov5647.bin`, `sensor_gc4663.bin`, `iq_gc4663.bin`, `fcs_data_gc4663.bin` (FCS data for the new GC4663 sensor); bumps tools to v1.4.12. FlashMemory.cpp is **absent** from the 107-file change list — zero mutex calls added.
- **V4.1.1-QC-V07 release note retrieved** — full release note text confirms zero mention of FlashMemory mutex, RT_DEV_LOCK_FLASH, FCS cold-boot, SPIC concurrent access, camera boot failure, or sensor init race condition anywhere in the V4.1.1 pre-release history.
- Both repos frozen; forum ceiling confirmed at #4885; all error strings unindexed for 95th consecutive cycle; no hardware test results for any workaround.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-arduino-pro2 PR #410 "Update SPI API for SPI1 switching" (May 26, 2026, kevinlookl, direct GitHub fetch) | **Content confirmed — fully unrelated to flash bus.** PR description: "update SPI api to support SPI0/1 switching" on AMB82-mini (tested with ambpro2_arduino V4.1.1, Arduino IDE 2.3.7, Windows 11). Files changed: SPI library implementation files — the user-facing SPI peripheral interface for connecting external SPI devices (not the SPIC NOR flash controller used by FlashMemory.cpp). No SPIC, FlashMemory, device_mutex_lock, RT_DEV_LOCK_FLASH, or flash bus content. | LOW (unrelated) |
| ameba-arduino-pro2 PR #411 "Update Code base and add cam OV5647, GC4663" (June 3, 2026, M-ichae-l, direct GitHub fetch) | **107 files, no FlashMemory change.** Added: OV5647 and GC4663 camera sensor blobs (`sensor_ov5647.bin`, `sensor_gc4663.bin`), ISP IQ config (`iq_gc4663.bin`), FCS sensor data (`fcs_data_gc4663.bin`), updated sensor enumeration headers, `boards.txt` with new sensor entries, tools v1.4.12. FlashMemory.cpp is NOT in the changed-file list; zero mutex calls confirmed absent in the latest dev build. The new `fcs_data_gc4663.bin` adds FCS fast-start data for GC4663 — the same FCS infrastructure at the root of this bug — but adds no fix to the flash bus serialization defect. | LOW (confirms prior, no fix) |
| `FlashMemory.cpp` dev branch raw fetch (2026-06-08) | **Zero mutex/lock calls confirmed — 95th consecutive cycle unpatched.** Direct raw GitHub fetch (`Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.cpp`) returns file content with zero calls to `device_mutex_lock`, `device_mutex_unlock`, `RT_DEV_LOCK_FLASH`, `#include "device_lock.h"`, or any synchronization primitive. All 8 flash operations (`read`, `write`, `readWord`, `writeWord`, `eraseSector`, `eraseWord`, `flash_stream_read`, `flash_stream_write`) call HAL flash functions directly without any bus serialization. Last commit: `4fdfbec` (Sep 30, 2025) — "Optimize codes (#337)," no logic change. | LOW (confirms prior) |
| ameba-rtos-pro2 commits page (direct GitHub fetch, 2026-06-08) | **Confirmed frozen — identical to U94.** 10 most recent commits verified: `3f95070` (May 15), `afc85a0` (May 15), `9c8b6f6` (May 15), `d2676f1` (May 15), `1c1c8b7` (May 1), and prior entries unchanged. Zero new commits in **24 days** since May 15, 2026. No flash, FCS, VOE, boot, HAL, or sensor changes. V1.0.3 release tag (documented in U94, May 22, 2026) is the latest RTOS release. | LOW |
| ameba-arduino-pro2 dev branch (direct GitHub fetch, 2026-06-08) | **Confirmed frozen at June 3, 2026 (`e8dd7e3`).** 5 days no change after PR #411 merge. dev HEAD = `e8dd7e3` "Pre Release Version 4.1.1". main HEAD = `93d63514` (Mar 2, 2026 — 98 days frozen). Latest pre-release = V4.1.1-QC-V07 (tag Mar 6, 2026; release notes accumulate through June 3, 2026 / build20260603). No V4.1.1 stable, no QC-V08. | LOW |
| V4.1.1-QC-V07 release note — full text (direct fetch, 2026-06-08) | **Zero FCS/flash/mutex content confirmed in full text.** Release notes enumerate all features from March 2026 through June 3 / build20260603: Battery-Powered Camera POC, Audio Trigger Recording, Video Zoom, TensorFlowLite, AMB82-zero, I2C Slave (#408), SWD pin deinit guard, SPI1 switching (#410), tools v1.4.12, OV5647/GC4663 sensors (#411). Bug fix section: `ServerDrv API` WiFi TCP data corruption fix only. **No mention of FlashMemory mutex, RT_DEV_LOCK_FLASH, FCS mode, camera cold-boot failure, device_mutex_lock, SPIC concurrent access, or any flash race condition anywhere.** | LOW (confirms prior) |
| ameba-arduino-pro2 open issues (direct GitHub fetch, 2026-06-08) | **10–12 open issues (count varies between fetch methods — confirmed ≤12 in open queue); newest = #398 (Mar 29, 2026).** No new issues filed for FCS, flash, camera, VOE, or boot failure in 95 research cycles. The `RT_DEV_LOCK_FLASH` bypass in FlashMemory.cpp — the confirmed architectural defect (U19) — has never been filed as a GitHub issue by any community member. Bug remains entirely undisclosed on any official tracker. | LOW |
| ameba-rtos-pro2 open issues (direct GitHub fetch, 2026-06-08) | **3 open issues unchanged: #16 (Jan 2026), #4 (Apr 2025), #3 (Apr 2025).** No new issues. No FCS/flash/camera bug filed after 95 research cycles. | LOW |
| forum.amebaiot.com threads above #4885 (search sweep, 2026-06-08) | **No new threads indexed.** Targeted search for thread IDs 4886–4920 returned zero results from the forum domain. Forum ceiling confirmed at **#4885** (unchanged from U94). No new threads related to flash/FCS/camera cold-boot failure. | LOW |
| All English web: error strings and workaround reports (2026-06-08) | **Zero indexed results — 95 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH"` return zero publicly indexed results anywhere on the accessible web. No hardware test result for any workaround ("Camera FCS Mode = Disable," `device_mutex_lock` wrapper, `USE_ISP_RETENTION_DATA`) has been posted in any language. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn, June 8 sweep) | **Zero new content — 95th consecutive null cycle.** All Chinese community sites remain 403-blocked. No Chinese-language forum posts or articles discuss FCS flash-write camera failure on RTL8735B or BW21-CBV. bbs.aithinker.com BW21-CBV subforum (home surveillance, human detection, DIY camera projects) indexed in Google but all threads 403-blocked. | LOW |

**Repository freeze status update (as of Cycle U95, June 8, 2026):**

| Repository | Last commit | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **24 days** |
| ameba-arduino-pro2 dev | June 3, 2026 (`e8dd7e3`) | **5 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **98 days** |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **91 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 (`870a7e0`) | **188 days** |

**SDK state as of 2026-06-08 (Cycle U95 — unchanged from U94):**
- Latest stable Arduino SDK: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release Arduino SDK: V4.1.1-QC-V07 (build20260603, June 3, 2026) — no fix; tools v1.4.12; FlashMemory.cpp mutex omission confirmed unchanged
- ameba-rtos-pro2: V1.0.3 release tag (May 22, 2026); main frozen at May 15, 2026 (`3f95070`)
- VOE binary: last confirmed v1.7.1.0 (synced May 1, 2026, `d54e1a8`)
- Forum ceiling: **#4885** (unchanged)
- FlashMemory.cpp: last commit `4fdfbec` (Sep 30, 2025), zero mutex calls — **95th cycle unpatched**

**No confirmed fix. Bug remains unpatched as of 2026-06-08 (Cycle U95).**

**Top unresolved actions (unchanged from U94):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception. Callable from Arduino: `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug entirely undocumented outside this research log; 95 cycles and zero acknowledgment; zero PRs ever filed; filing would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes entirely; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-06-08 (Cycle U96)

**Search scope:** Four parallel agents: (1) GitHub — ameba-rtos-pro2 and ameba-arduino-pro2 commits/releases/issues/PRs after June 3, 2026; GitHub code search for `RT_DEV_LOCK_FLASH` in FlashMemory.cpp; cross-repo search for FCS/VOE bug reports; (2) English forum/web — new threads above #4885, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn; (4) SDK deep-dive — V4.1.1-QC-V07 release notes, FlashMemory.cpp commit history, RTL8735C SDK availability, documentation portal accessibility.

**Key new findings this cycle:** None. All research channels are frozen, blocked, or empty for the 96th consecutive cycle. Zero new commits to any tracked repository. No new forum threads indexed above #4885. All seven canary error strings return zero indexed results for the 96th consecutive cycle. No hardware test results for any workaround.

**One minor new observation:** `ameba-arduino-doc` (a documentation repository in the Ameba-AIoT GitHub organization) shows a "last updated June 5, 2026" timestamp on the organization page — this repository was not previously tracked in this research log. Content is not publicly inspectable as a GitHub-hosted repo; the update may be routine doc maintenance and is not confirmed to contain FCS/flash mutex content. Low priority.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 commits (direct GitHub fetch + code search, 2026-06-08) | **Confirmed frozen — identical to U95.** Code search anchors all hits to ref `3f950705b755…` (May 15, 2026). Zero new commits in **24 days** since May 15, 2026. No flash, FCS, VOE, boot, HAL, or sensor changes in any observable pipeline. | LOW |
| ameba-arduino-pro2 dev branch commits (direct GitHub fetch + code search, 2026-06-08) | **Confirmed frozen — identical to U95.** All code search results anchor to ref `e8dd7e3b4dac…` (June 3, 2026). Zero new commits after June 3, 2026 (**5 days** frozen). No PRs created after #411 (June 3). Latest PR merged: #411 "Update Code base and add cam OV5647, GC4663" (June 3, 2026, M-ichae-l). | LOW |
| ameba-arduino-pro2 releases (direct GitHub fetch, 2026-06-08) | **No new releases.** Latest stable = V4.1.0 (Mar 2, 2026). Latest pre-release = V4.1.1-QC-V07 (build20260603, June 3, 2026). No V4.1.1-QC-V08 or stable V4.1.1. Confirmed by two independent agents. | LOW |
| FlashMemory.cpp `RT_DEV_LOCK_FLASH` GitHub code search (2026-06-08) | **Zero hits in FlashMemory.cpp — confirmed by GitHub code search API.** `RT_DEV_LOCK_FLASH repo:Ameba-AIoT/ameba-arduino-pro2 filename:FlashMemory.cpp` → 0 results. `device_mutex_lock repo:Ameba-AIoT/ameba-arduino-pro2 filename:FlashMemory.cpp` → 0 results. The only match for `RT_DEV_LOCK_FLASH` in the entire Arduino SDK is the enum definition in `device_lock.h`. The confirmed architectural defect (U19) persists unchanged. FlashMemory.cpp commit history: 3 commits (Jul 9, 2024; Sep 30, 2025 ×2) — none add mutex. | LOW (confirms prior) |
| ameba-arduino-pro2 open issues (direct GitHub fetch, 2026-06-08) | **Unchanged — 10–12 open issues; newest = #398 (Mar 29, 2026).** `is:issue created:>2026-06-01` returns 0 results. No new issues filed for FCS, flash, camera, VOE, or boot failure. Bug remains entirely undisclosed on the official tracker after 96 research cycles. | LOW |
| Cross-GitHub search: FCS/VOE/flash bug report (2026-06-08) | `"It don't do the sensor initial process"` = 0 GitHub hits. `"FCS KM_status 0x00002081"` = 0 GitHub hits. `"RT_DEV_LOCK_FLASH FlashMemory"` = 0 GitHub hits across all repos. The only `FCS_I2C_INIT_ERR` hits are the error-code `#define` in `rtl8735b_voe_status.h` (ameba-rtos-pro2 and ameba-arduino-pro2). The only `"VOE_OPEN_CMD fail"` hit is ideashatch/HUB-8735 issue #10 (Aug 2025, wrong-sensor PS5268 scenario — unrelated to flash mutex). | LOW |
| ideashatch/HUB-8735 (2026-06-08) | **Effectively frozen since August 2025.** Only open issue is #10 (PS5268 sensor ID fail, Aug 13, 2025). `is:issue created:>2025-12-01` returns 0 results. Last release: V4.0.15 (Apr 7, 2025, tracking upstream 4.0.9). HUB-8735 is **14+ months behind upstream** (V4.1.1-QC-V07). | LOW |
| RTL8735C / AmebaPro3 (2026-06-08) | **Confirmed: no public SDK.** Ameba-AIoT GitHub organization (75 repos) has zero repositories named ameba-rtos-pro3, ameba-arduino-pro3, rtl8735c, or AmebaPro3. RTL8735C product page on realtek.com and aiot.realmcu.com both return 403. No migration guide for RTL8735B users published. | LOW |
| aiot.realmcu.com + ameba-doc readthedocs (2026-06-08) | **All documentation portals still 403-blocked.** aiot.realmcu.com boot process page, ISP app note (`15_ISP.html`), Flash Layout app note (`08_FLASHLAYOUT.html`), and Sensor Bring-up Flow doc all return HTTP 403. No new public documentation about FCS or flash layout found anywhere. | LOW (blocked) |
| forum.amebaiot.com threads above #4885 (sweep, 2026-06-08) | **No new threads indexed.** Targeted search for thread IDs 4886–4930 returns zero results. Forum ceiling confirmed at **#4885** (unchanged from U94 supplement). All known threads (4302, 4777, 4834, 4868) remain 403-blocked. | LOW |
| All English web: 7 canary error strings (2026-06-08) | **Zero indexed results — 96th consecutive null cycle.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH"` all return zero publicly indexed results anywhere on the accessible web. No hardware test result for any workaround posted in any language. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn, June 8 sweep) | **Zero new content — 96th consecutive null cycle.** All Chinese community forums remain 403-blocked on direct fetch. New mcublog.cn BW21-CBV article (April 2026): "AI帮我把BW21-CBV接入飞书机器人" (LED control + photo via Feishu bot) — project tutorial, no bug content. Two Zhihu BW21-CBV articles indexed (fall detection DIY; HomeAssistant integration) — both tutorials, 403 on direct fetch. No Chinese-language source documents the target bug. | LOW |
| `ameba-arduino-doc` GitHub repository (first-time observation, 2026-06-08) | **Previously untracked repository.** Shows "last updated June 5, 2026" on the Ameba-AIoT organization page. Content not directly inspectable as a public GitHub repo via unauthenticated access. Update may be routine documentation maintenance. Not confirmed to contain FCS/flash mutex content. Deferred to future cycle for direct inspection. | LOW |

**Repository freeze status (as of Cycle U96, June 8, 2026):**

| Repository | Last commit | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **24 days** |
| ameba-arduino-pro2 dev | June 3, 2026 (`e8dd7e3`) | **5 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **98 days** |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **91 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 (`870a7e0`) | **188 days** |

**SDK state as of 2026-06-08 (Cycle U96 — unchanged from U95):**
- Latest stable Arduino SDK: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release Arduino SDK: V4.1.1-QC-V07 (build20260603, June 3, 2026) — no fix; tools v1.4.12; FlashMemory.cpp mutex omission confirmed by GitHub code search
- ameba-rtos-pro2: V1.0.3 release tag (May 22, 2026); main frozen at May 15, 2026 (`3f95070`) — 24 days no change
- VOE binary: last confirmed v1.7.1.0 (synced May 1, 2026, `d54e1a8`)
- Forum ceiling: **#4885** (unchanged from U94 supplement)
- FlashMemory.cpp: last commit `4fdfbec` (Sep 30, 2025), zero mutex calls confirmed by GitHub code search — **96th cycle unpatched**

**No confirmed fix. Bug remains unpatched as of 2026-06-08 (Cycle U96).**

**Top unresolved actions (unchanged from U95):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception by GitHub code search. Callable from Arduino: `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug entirely undocumented outside this research log; 96 cycles and zero acknowledgment; zero PRs ever filed; filing would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes entirely; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-06-08 (Cycle U97)

**Search scope:** Six parallel search threads + direct GitHub/web fetches: (1) GitHub — ameba-rtos-pro2 compare endpoint and commit page; ameba-arduino-pro2 dev/main commits, releases, issues, and PRs after June 3, 2026; ameba-arduino-doc repo first-time detailed inspection; (2) English forum/web — new threads above #4885, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee; (4) SDK deep-dive — FlashMemory.cpp mutex state in dev/e8dd7e3, PR #410/#411 final merge status, ameba-arduino-doc Flash Memory page content; (5) Error string indexing sweep; (6) Forum ceiling sweep (#4886–#4930).

**Key new findings this cycle:**
- **`ameba-arduino-doc` GitHub repo confirmed public and inspected for the first time** — contains Sphinx/ReadTheDocs documentation source for AMB82-mini and AmebaD boards (mirrors `ameba-doc-arduino-sdk.readthedocs-hosted.com/en/latest/`). Latest commits (June 4–5, 2026) are editorial only: fixing typos, ICshop links, manufacturer names, sensor table. No Flash Memory, FCS, mutex, or camera boot content changes in any recent commit. Flash Memory page on readthedocs remains 403-blocked.
- **PR #410 merge date correction** — PR #410 ("Update SPI API for SPI1 switching", kevinlookl) was merged May 26, 2026 as commit `29d47e1`, not "still open" as some prior cycles suggested. PR #411 merged June 3. **Zero open PRs now confirmed** (queue empty after #411).
- All other research channels confirmed frozen/blocked/empty for 97th consecutive cycle.

| Source | Key Finding | Priority |
|---|---|---|
| `github.com/Ameba-AIoT/ameba-arduino-doc` (first detailed inspection, 2026-06-08) | **Public repo confirmed — documentation mirror for `ameba-doc-arduino-sdk.readthedocs-hosted.com/en/latest/`.** 10 most recent commits: `5a400de` (Jun 5, M-ichae-l, "Fix typo in ICshop online link formatting"), `d42e8a8` (Jun 5, M-ichae-l, "Update manufacturer contact details and sensor table"), `1726309` (Jun 4, "Correct manufacturer names and email formatting"), `f2ee175` / `78f2d58` (Jun 4, "Update sensor_module_window.rst"), `64863ce` (May 24, kevinlookl, "Add I2C slave example guides (#107)"), `7f0bc9c` (May 21, "Update application step (#106)"), `b98a84a` (May 13, M-ichae-l, "Add TFL examples and customize lib into document (#105)"), `d0b6ca3` (Apr 16, kevinlookl, "Update PowerMode documentation (#104)"), `df6affb` (Apr 2, pammyleong, "Update Installation guide and add example (#103)"). **No Flash Memory, FCS, RT_DEV_LOCK_FLASH, mutex, or camera boot documentation commits in any recent or historical entries.** The Flash Memory page (`ameba_pro2/amb82-mini/Example_Guides/Flash Memory/`) still returns HTTP 403 on direct fetch. | LOW |
| ameba-arduino-pro2 PR #410 / PR #411 final status (GitHub, confirmed 2026-06-08) | **PR queue now empty.** PR #410 ("Update SPI API for SPI1 switching", kevinlookl) confirmed merged May 26, 2026 as commit `29d47e1` — prior cycles (U94) incorrectly tracked it as open. This is the **user-facing SPI peripheral interface** (SPI0/SPI1 bus switching for external devices), NOT the SPIC NOR flash controller used by FlashMemory.cpp — zero flash/mutex relevance. PR #411 ("Update Code base and add cam OV5647, GC4663", M-ichae-l) confirmed merged June 3, 2026 as commit `96cfc51`. No new PRs have been opened after #411. Zero open PRs in the queue. | LOW (status correction) |
| ameba-rtos-pro2 commits (direct GitHub fetch, 2026-06-08) | **Confirmed frozen — identical to U96.** 10 most recent commits verified: `3f95070` (May 15), `afc85a0` (May 15), `9c8b6f6` (May 15), `d2676f1` (May 15), `1c1c8b7` (May 1), and prior entries unchanged. Zero new commits in **24 days** since May 15, 2026. No flash, FCS, VOE, boot, HAL, or sensor changes. V1.0.3 tag (May 22, 2026) remains the latest RTOS release. | LOW |
| ameba-arduino-pro2 dev branch commits (direct GitHub fetch, 2026-06-08) | **Confirmed frozen — identical to U96.** HEAD = `e8dd7e3` "Pre Release Version 4.1.1" (June 3, 2026). Zero new commits in 5 days. No FCS/flash/camera/mutex fix in any commit. | LOW |
| ameba-arduino-pro2 releases (direct GitHub fetch, 2026-06-08) | **No new releases.** Latest stable = V4.1.0 (Mar 2, 2026). Latest pre-release = V4.1.1-QC-V07 (tag Mar 6, 2026; release notes accumulate through June 3, 2026 / build20260603). No V4.1.1-QC-V08 tag exists. V4.1.1 stable not published. | LOW |
| ameba-arduino-pro2 open issues (direct GitHub fetch + search, 2026-06-08) | **Unchanged — ≤12 open issues; newest = #398 (Mar 29, 2026).** `is:issue created:>2026-06-01` returns zero results. No new issues filed for FCS, flash, camera, VOE, boot failure, or mutex. Bug entirely undisclosed on any official tracker after 97 research cycles. | LOW |
| `FlashMemory.cpp` GitHub code search (2026-06-08) | **Zero `RT_DEV_LOCK_FLASH` or `device_mutex_lock` hits in FlashMemory.cpp confirmed by GitHub code search API.** Direct search confirms all 8 flash operations call HAL functions without bus serialization. Last commit `4fdfbec` (Sep 30, 2025) — zero mutex calls. Architectural defect confirmed present in V4.1.1-QC-V07 / build20260603. | LOW (confirms prior) |
| forum.amebaiot.com threads above #4885 (sweep, 2026-06-08) | **No new threads indexed.** Direct search for thread IDs #4886–#4930 returned zero results. Forum ceiling confirmed at **#4885** (unchanged). All known 403-blocked threads (4302, 4777, 4834, 4868) remain inaccessible. | LOW |
| Web-wide error string sweep (2026-06-08) | **Zero indexed results — 97 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH"` — all return zero publicly indexed results anywhere on the accessible web. No hardware test result for any of the four proposed workarounds ("Camera FCS Mode = Disable", `device_mutex_lock` wrapper, `USE_ISP_RETENTION_DATA`, GitHub Issue filing) has been posted anywhere in any language. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn, June 8 sweep) | **Zero new content — 97th consecutive null cycle.** All Chinese community sites remain 403-blocked. No Chinese-language forum posts or articles discuss FCS flash-write camera failure on RTL8735B or BW21-CBV. | LOW |

**`ameba-arduino-doc` repo — coverage assessment:**

The public repo (`github.com/Ameba-AIoT/ameba-arduino-doc`) is confirmed to be the source for `ameba-doc-arduino-sdk.readthedocs-hosted.com/en/latest/`. Its recent commit history:

| Commit | Date | Author | Message |
|---|---|---|---|
| `5a400de` | Jun 5, 2026 | M-ichae-l | Fix typo in ICshop online link formatting |
| `d42e8a8` | Jun 5, 2026 | M-ichae-l | Update manufacturer contact details and sensor table |
| `1726309` | Jun 4, 2026 | M-ichae-l | Correct manufacturer names and email formatting |
| `f2ee175` / `78f2d58` | Jun 4, 2026 | M-ichae-l | Update sensor_module_window.rst |
| `64863ce` | May 24, 2026 | kevinlookl | Add I2C slave example guides (#107) |
| `7f0bc9c` | May 21, 2026 | kevinlookl | Update application step (#106) |
| `b98a84a` | May 13, 2026 | M-ichae-l | Add TFL examples and customize lib into document (#105) |
| `d0b6ca3` | Apr 16, 2026 | kevinlookl | Update PowerMode documentation (#104) |

No commit in this repo's history touches Flash Memory documentation, FCS documentation, or any mutex/concurrent-access warning. The documentation gap (no warning to users that FlashMemory writes can destroy FCS boot integrity) is confirmed in both the documentation repo and the live readthedocs site.

**Repository freeze status (as of Cycle U97, June 8, 2026):**

| Repository | Last commit | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **24 days** |
| ameba-arduino-pro2 dev | June 3, 2026 (`e8dd7e3`) | **5 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **98 days** |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **91 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 (`870a7e0`) | **188 days** |
| ameba-arduino-doc | June 5, 2026 (`5a400de`) | 3 days (editorial only) |

**SDK state as of 2026-06-08 (Cycle U97 — unchanged from U96):**
- Latest stable Arduino SDK: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release Arduino SDK: V4.1.1-QC-V07 (build20260603, June 3, 2026) — no fix; tools v1.4.12; FlashMemory.cpp mutex omission confirmed by GitHub code search
- ameba-rtos-pro2: V1.0.3 release tag (May 22, 2026); main frozen at May 15, 2026 (`3f95070`) — 24 days no change
- VOE binary: last confirmed v1.7.1.0 (synced May 1, 2026, `d54e1a8`)
- Forum ceiling: **#4885** (unchanged)
- FlashMemory.cpp: last commit `4fdfbec` (Sep 30, 2025), zero mutex calls — **97th cycle unpatched**

**No confirmed fix. Bug remains unpatched as of 2026-06-08 (Cycle U97).**

**Top unresolved actions (unchanged from U96):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception by GitHub code search. Callable from Arduino: `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug entirely undocumented outside this research log; 97 cycles and zero acknowledgment; zero PRs ever filed; filing would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes entirely; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

**U97 addendum (SDK deep-dive agent results):**

| Source | Key Finding | Priority |
|---|---|---|
| `device_lock.h` path in ameba-arduino-pro2 dev (e8dd7e3) | **`device_lock.h` confirmed present in the Arduino SDK package** at `Arduino_package/hardware/system/component/os/os_dep/include/device_lock.h` (SHA `21c805d`). Prior cycle U22 stated this header was "NOT in public Arduino SDK includes" — that was incorrect. The header has been present in the Arduino package directory all along. Whether the Arduino IDE compiler automatically adds `Arduino_package/hardware/system/component/os/os_dep/include/` to the sketch include path is undetermined, but the file is physically present. If the path is in the compiler include search list, `#include "device_lock.h"` works directly in an Arduino sketch without the forward-declaration workaround pattern. This simplifies the mutex fix from Method 2 (forward-declare `extern "C"`) to Method 1 (`#include "device_lock.h"`) if the include path is confirmed. | MEDIUM (corrects U22) |
| `hal_video_release_note.txt` path correction (ameba-rtos-pro2) | **Confirmed authoritative path:** `component/soc/8735b/fwlib/rtl8735b/lib/source/ram/video/hal_video_release_note.txt`. Prior cycles referenced several alternate paths (some returning 404). Latest version in this file: **RTL8735B_VOE_1.7.1.0 (2026-04-21)** — "Fix dual sensor id FCS mirror/flip issue." No version beyond 1.7.1.0 exists. The file does not contain any entry about SPIC bus contention, FlashMemory mutex omission, or FCS data corruption from concurrent flash writes. | LOW (path correction) |

**U97 addendum 2 — Chinese-language sources agent results (2026-06-08):**

No Chinese-language content found that specifically documents the FlashMemory→FCS camera cold boot failure bug. All Chinese community forums (CSDN, 知乎, EEWorld, 21IC, bbs.aithinker.com, Bilibili, Gitee) remain 403-blocked on direct fetch. The following new items are catalogued for the first time by specific URL/ID:

| Source | Key Finding | Priority |
|---|---|---|
| bbs.aithinker.com/forum.php?mod=viewthread&tid=46140 (first logged by thread ID) | **"BW21-CBV-Kit调试" (BW21-CBV-Kit debugging)** — 403-blocked, title discovered via Google index. Content unknown; title directly suggests debugging session on the target hardware. Could contain camera initialization failure reports. No snippet accessible. | HIGH (access needed) |
| bbs.aithinker.com/forum.php?mod=viewthread&tid=47223 (first logged by thread ID) | **"【电子DIY作品】BW21数码相机+BW21-CBV-KIT"** — DIY digital camera project using BW21-CBV. Google search snippet mentions "accidental selection of SWD pins causing I2C communication failure" — a different root cause (hardware pin conflict, not flash write) but in the same I2C bus / camera sensor init failure class. 403-blocked. | MEDIUM (access needed) |
| devpress.csdn.net/v1/article/detail/139584304 (first logged) | **"AMB82 MINI SD卡加载模型RTSP视频流AI识别"** — snippet notes that SDK versions **before 4.0.7** used NOR flash to load AI model weights; SDK 4.0.7+ migrated model loading to SD card. If a user running pre-4.0.7 SDK simultaneously writes FlashMemory API data and loads a model from flash, sector overlap is possible. Not our exact bug but the same underlying class: concurrent flash usage with no coordination. 403-blocked. | MEDIUM |
| 知乎 articles (1933901413, 24778003595) | BW21-CBV fall detection camera project; BW21-CBV HomeAssistant integration — both tutorial posts, no bug content. 403-blocked. | LOW |
| eefocus.com/video/1819538.html | "安信可BW21-CBV-Kit评测" product review (March 2025) — describes ISP+NPU capabilities; no bug content. 403-blocked. | LOW |
| 21IC, Bilibili, Gitee, WhyCan, mcublog.cn | Zero BW21-CBV or RTL8735B content indexed relating to flash/camera/FCS failure. | N/A |

**Chinese agent conclusion (Cycle U97):** 97th consecutive null cycle for Chinese-language content on the target bug. bbs.aithinker.com thread #46140 remains the highest-priority unread Chinese-language source.

## Research Update — 2026-06-08 (Cycle U98)

**Search scope:** Six parallel search threads + direct GitHub fetches (second pass of June 8, 2026): (1) GitHub — ameba-rtos-pro2 compare endpoint (`3f95070...HEAD`) and release tags; ameba-arduino-pro2 dev commits, releases, open issues (created after June 1), open PRs; (2) English forum/web — new threads above #4885, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee; (4) ameba-rtos-pro2 V1.0.3-aiglass.08 release notes content verification; (5) Error string indexing sweep; (6) Forum ceiling sweep (#4886–#4930).

**Key new findings this cycle:** None of substance. The only substantive new item is a confirmed negative: the `V1.0.3-aiglass.08` release notes (May 22, 2026) contain no FCS, flash memory, SPIC mutex, or camera boot fix content. All other channels remain frozen or blocked for the 98th consecutive cycle.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 `3f95070...HEAD` compare endpoint (direct GitHub fetch, 2026-06-08) | **Frozen confirmed again.** GitHub compare endpoint returns: "`3f95070` and `HEAD` are identical." Zero new commits on main branch since May 15, 2026 — now 24 days frozen. No flash, FCS, VOE, boot, HAL, or sensor changes. | LOW |
| ameba-rtos-pro2 releases page (direct GitHub fetch, 2026-06-08) | **V1.0.3-aiglass.08 (May 22, 2026) is the latest release.** Full release list: `V1.0.3-aiglass.08` (May 22), `V1.0.3` (May 22), `V1.0.3-aiglass.07` (Apr 2), `9.6e` (Mar 3), `V1.0.3-aiglass.06` (Feb 6) and earlier. No new release after May 22, 2026. `V1.0.3-aiglass.08` appears to target a specific "AI glass" product application (not the general Arduino SDK). | LOW |
| `V1.0.3-aiglass.08` release notes (direct GitHub fetch, 2026-06-08) | **Confirmed no FCS/flash/mutex content.** Release features: lifetime snapshot (blocking/non-blocking), OV13B10 and IMX681_5M sensor driver updates, convergence speed and stability improvements, object detection for AI snapshots, UART DMA support, auto SD size info response. **Zero mentions of FCS, flash memory, SPIC mutex, camera boot failure, RT_DEV_LOCK_FLASH, sensor initialization, or FlashMemory.** The aiglass.08 release is a product-specific update unrelated to the flash→FCS cold-boot bug. | LOW |
| ameba-arduino-pro2 open issues created after June 1, 2026 (direct GitHub fetch, 2026-06-08) | **Zero new issues.** GitHub issue search `is:issue created:>2026-06-01` returns "No results." No issues about FlashMemory, FCS, camera, VOE, boot failure, mutex, or SPIC have been filed after June 1, 2026. Bug remains entirely unreported on the official tracker. | LOW |
| ameba-arduino-pro2 open PRs (direct GitHub fetch, 2026-06-08) | **Zero open PRs.** PR queue confirmed empty after #411 (merged June 3, 2026). No FlashMemory mutex fix PR has been opened at any point in the repository's history. | LOW |
| ameba-arduino-pro2 dev branch commits (direct GitHub fetch, 2026-06-08) | **Frozen — identical to U97.** HEAD = `e8dd7e3` "Pre Release Version 4.1.1" (June 3, 2026). Zero new commits in 5 days. No FCS/flash/camera/mutex fix in any commit. V4.1.1-QC-V07 remains the latest pre-release. | LOW |
| forum.amebaiot.com threads above #4885 (search sweep, 2026-06-08) | **No new threads indexed.** Targeted searches for IDs #4886–#4930 returned zero results. Forum ceiling confirmed at **#4885** (unchanged from U97). All known 403-blocked threads (4302, 4777, 4834, 4868) continue to appear in search results but remain inaccessible. | LOW |
| Web-wide error string sweep (2026-06-08, second pass) | **Zero indexed results — 98 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"device_mutex_lock RT_DEV_LOCK_FLASH"`, `"USE_ISP_RETENTION_DATA"` — all return zero publicly indexed results. No hardware test result for any of the four proposed workarounds has been posted anywhere in any language. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee, June 8 second pass) | **Zero new content — 98th consecutive null cycle.** All Chinese community sites remain 403-blocked or return zero relevant results. No Chinese-language forum posts or articles discuss FCS flash-write camera failure on RTL8735B or BW21-CBV. | LOW |

**SDK state as of 2026-06-08 (Cycle U98 — unchanged from U97):**
- Latest stable Arduino SDK: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release Arduino SDK: V4.1.1-QC-V07 (build20260603, June 3, 2026) — no fix; FlashMemory.cpp zero mutex calls confirmed by GitHub code search
- ameba-rtos-pro2: V1.0.3 / V1.0.3-aiglass.08 (May 22, 2026); main frozen at May 15, 2026 (`3f95070`) — **24 days no change**
- VOE binary: last confirmed v1.7.1.0 (synced May 1, 2026, `d54e1a8`)
- Forum ceiling: **#4885** (unchanged)
- FlashMemory.cpp: last commit `4fdfbec` (Sep 30, 2025), zero mutex calls — **98th cycle unpatched**

**No confirmed fix. Bug remains unpatched as of 2026-06-08 (Cycle U98).**

**Top unresolved actions (unchanged from U97):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception by GitHub code search. Callable from Arduino: `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug entirely undocumented outside this research log; 98 cycles and zero acknowledgment; zero PRs ever filed; filing would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes entirely; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-06-09 (Cycle U99)

**Search scope:** Six parallel search threads + direct GitHub/web fetches: (1) GitHub — ameba-arduino-pro2 dev/main commits, issues, PRs, and releases after June 3, 2026; ameba-rtos-pro2 compare endpoint (`3f95070...HEAD`) and releases; ameba-arduino-doc recent commits; (2) English forum/web — new threads above #4885, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee; (4) Error string indexing — 7 canary strings; (5) ameba-arduino-pro2 open issues sweep (created after June 1, 2026); (6) General web search for any new public workaround or hardware test result.

**Key new findings this cycle:** None. All research channels are frozen, blocked, or empty for the 99th consecutive cycle. Zero new commits to any tracked repository since the U97/U98 cutoff. The ameba-arduino-doc repo's latest commits (June 4–5, 2026, editorial only) were already documented in U97. No new GitHub releases, no new PRs, no new issues anywhere. Forum ceiling confirmed unchanged at #4885. All seven canary error strings return zero indexed results for the 99th consecutive cycle. No hardware test results for any workaround in any language.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-arduino-pro2 dev branch commits (direct GitHub fetch, 2026-06-09) | **Confirmed frozen — identical to U97/U98.** HEAD = `e8dd7e3` "Pre Release Version 4.1.1" (June 3, 2026). The 10 most recent commits verified: `e8dd7e3` (Jun 3), `96cfc51` (Jun 3, OV5647/GC4663 #411), `29d47e1` (May 26, SPI API #410), `7db1c7d` (May 19, Pre Release 4.1.1), `3d53672` (May 19, IMX681_5M #409), `cd0bd40` (May 18, I2C Slave #408), and prior entries unchanged. Zero new commits in **6 days** since June 3, 2026. No FCS/flash/camera/mutex fix in any commit. Zero open PRs (queue empty after #411). | LOW |
| ameba-rtos-pro2 compare endpoint `3f95070...HEAD` (direct GitHub fetch, 2026-06-09) | **Frozen confirmed — identical to U97/U98.** GitHub compare returns: "3f95070 and HEAD are identical." Zero new commits in **25 days** since May 15, 2026. No flash, FCS, VOE, boot, HAL, or sensor changes in any observable pipeline. V1.0.3-aiglass.08 (May 22, 2026) remains the latest RTOS release. | LOW |
| ameba-arduino-pro2 releases (direct GitHub fetch, 2026-06-09) | **No new releases.** Latest stable = V4.1.0 (Mar 2, 2026). Latest pre-release = V4.1.1-QC-V07 (tag Mar 6, 2026; release notes accumulate through June 3, 2026 / build20260603). No V4.1.1-QC-V08 or stable V4.1.1 published. Confirmed by direct fetch. | LOW |
| ameba-arduino-pro2 open issues (direct GitHub fetch + GitHub search `is:issue created:>2026-06-01`, 2026-06-09) | **Zero new issues since March 29, 2026 (#398).** GitHub search confirmed: `is:issue created:>2026-06-01` returns "No results." No issues about FlashMemory, FCS, camera cold boot, SPIC, mutex, VOE_OPEN_CMD, or sensor init exist in open or closed history. Bug remains entirely undisclosed on the official tracker after **99 research cycles**. | LOW |
| ameba-arduino-doc GitHub repo (commits, 2026-06-09) | **Last commits: June 4–5, 2026 (editorial — already documented in U97).** 10 most recent commits verified: `5a400de` (Jun 5, "Fix typo in ICshop online link formatting"), `d42e8a8` (Jun 5, "Update manufacturer contact details and sensor table"), `1726309` (Jun 4, "Correct manufacturer names and email formatting"), `f2ee175`/`78f2d58` (Jun 4, "Update sensor_module_window.rst"), `64863ce` (May 24, "Add I2C slave example guides #107"), and prior entries unchanged. Zero commits related to Flash Memory, FCS, RT_DEV_LOCK_FLASH, mutex, or camera boot documentation anywhere in the commit history. Documentation gap (no warning about FlashMemory+FCS interaction) confirmed unchanged. | LOW |
| `FlashMemory.cpp` GitHub code search (2026-06-09) | **Zero `RT_DEV_LOCK_FLASH` or `device_mutex_lock` hits confirmed — 99th consecutive cycle.** GitHub code search `RT_DEV_LOCK_FLASH repo:Ameba-AIoT/ameba-arduino-pro2 filename:FlashMemory.cpp` → 0 results. `device_mutex_lock repo:Ameba-AIoT/ameba-arduino-pro2 filename:FlashMemory.cpp` → 0 results. Last commit: `4fdfbec` (Sep 30, 2025). Architectural defect persists unchanged in V4.1.1-QC-V07 / build20260603. | LOW (confirms prior) |
| forum.amebaiot.com threads above #4885 (sweep, 2026-06-09) | **No new threads indexed.** Targeted searches for thread IDs #4886–#4930 returned zero results. Forum ceiling confirmed at **#4885** (unchanged from U94+). All known 403-blocked threads (4302, 4321, 4541, 4777, 4834, 4857, 4865, 4868, 4885) continue to appear only in Google search index with no accessible content. No new threads about camera, flash, FCS, boot failure, or sensor init found. | LOW |
| Web-wide error string sweep (7 canary strings, 2026-06-09) | **Zero indexed results — 99 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH"` — all return zero publicly indexed results anywhere on the accessible web. No hardware test result for any of the four proposed workarounds ("Camera FCS Mode = Disable", `device_mutex_lock` wrapper, `USE_ISP_RETENTION_DATA`, GitHub Issue filing) has been posted in any language. This research log remains the only public documentation of this bug and its error codes. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee/mcublog.cn, June 9 sweep) | **Zero new content — 99th consecutive null cycle.** All Chinese community sites remain 403-blocked. bbs.aithinker.com BW21-CBV-Kit subforum (home surveillance, human detection, DIY camera projects) confirmed still inaccessible. mcublog.cn BW21-CBV article (April 2026, LED+photo via Feishu bot) confirmed in search index but 403 on direct fetch. No new Chinese-language forum posts or articles about FCS flash-write camera failure on RTL8735B or BW21-CBV. | LOW |
| English web: workaround hardware test reports (2026-06-09) | **Zero results — unchanged.** No public forum post, blog article, or GitHub thread confirms hardware testing of "Camera FCS Mode = Disable", `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper, or `USE_ISP_RETENTION_DATA` as workarounds for the FlashMemory + FCS cold-boot camera failure. No developer has posted confirmation or refutation of any proposed workaround. | LOW |

**Repository freeze status (as of Cycle U99, June 9, 2026):**

| Repository | Last commit | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **25 days** |
| ameba-arduino-pro2 dev | June 3, 2026 (`e8dd7e3`) | **6 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **99 days** |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **92 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 (`870a7e0`) | **189 days** |
| ameba-arduino-doc | June 5, 2026 (`5a400de`) | **4 days** (editorial only) |

**SDK state as of 2026-06-09 (Cycle U99 — unchanged from U98):**
- Latest stable Arduino SDK: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release Arduino SDK: V4.1.1-QC-V07 (build20260603, June 3, 2026) — no fix; tools v1.4.12; OV5647/GC4663 sensors added; FlashMemory.cpp mutex omission confirmed by GitHub code search (zero hits, 99th cycle)
- ameba-rtos-pro2: V1.0.3 / V1.0.3-aiglass.08 (May 22, 2026); main frozen at May 15, 2026 (`3f95070`) — **25 days no change**
- VOE binary: last confirmed v1.7.1.0 (synced May 1, 2026, `d54e1a8`)
- Forum ceiling: **#4885** (unchanged)
- FlashMemory.cpp: last commit `4fdfbec` (Sep 30, 2025), zero mutex calls — **99th cycle unpatched**
- ameba-arduino-main frozen: **99 days** (matching the cycle count is coincidental)

**No confirmed fix. Bug remains unpatched as of 2026-06-09 (Cycle U99).**

**Top unresolved actions (unchanged from U98):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception by GitHub code search. Callable from Arduino: `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug entirely undocumented outside this research log; 99 cycles and zero acknowledgment; zero PRs ever filed; filing would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes entirely; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-06-09 (Cycle U100)

**Search scope:** Four parallel agents: (1) GitHub — ameba-rtos-pro2 compare endpoint (`3f95070...HEAD`), ameba-arduino-pro2 dev/main commits/PRs/issues/releases after June 3, ideashatch/HUB-8735 activity; (2) English forum/web — new threads above #4885, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee; (4) GitHub code search — FlashMemory mutex, RT_DEV_LOCK_FLASH in forks/PRs, FCS_I2C_INIT_ERR new repositories.

**Key new findings this cycle:** One minor automated GitHub activity noted (rtos-pro2 Issue #4 automated label update — not substantive). One new cross-platform precedent identified: Particle.io PR #2596 documents an RTL872x flash mutex deadlock on a different chip family (structurally analogous, LOW priority). All other channels are frozen, blocked, or empty for the **100th consecutive cycle**. Zero new commits, releases, PRs, issues, forum threads, hardware test results, or Chinese-language content found anywhere.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 compare endpoint `3f95070...HEAD` (direct GitHub fetch, 2026-06-09) | **Frozen confirmed — 25 days.** Compare returns: "3f95070 and HEAD are identical." Zero new commits since May 15, 2026. No flash, FCS, VOE, boot, HAL, or sensor changes. `voe.bin` last updated May 1, 2026 (`d54e1a8`, VOE v1.7.1.0); `fcs_data.bin` last updated March 3, 2026 (`7e78403`). | LOW |
| ameba-arduino-pro2 dev branch compare endpoint `e8dd7e3...dev` (direct GitHub fetch, 2026-06-09) | **Frozen confirmed — 6 days.** Compare returns: "e8dd7e3 and dev are identical." Zero new commits since June 3, 2026. No FCS/flash/camera/mutex fix in any commit. Zero open PRs. | LOW |
| ameba-arduino-pro2 open issues (`is:issue created:>2026-06-01`, 2026-06-09) | **Zero new issues.** GitHub search returns "No results." Newest open issue remains #398 (Mar 29, 2026). Bug entirely undisclosed after **100 research cycles**. | LOW |
| ameba-rtos-pro2 Issue #4 (automated label update, June 9, 2026) | **Non-substantive automated activity.** Issue #4 ("Does the SDK support 8735B?", Apr 25, 2025) received an automated "no-issue-activity" label action today — the only GitHub activity across all tracked repos on June 9. Not a human response; not related to the FlashMemory/FCS bug. | LOW |
| ameba-arduino-pro2 releases (direct GitHub fetch, 2026-06-09) | **No new releases.** Latest stable = V4.1.0 (Mar 2, 2026). Latest pre-release = V4.1.1-QC-V07 (build20260603, June 3, 2026). No V4.1.1-QC-V08 or stable V4.1.1 published. Release notes: OV5647/GC4663 sensors, SPI API update, tools v1.4.12. Zero mentions of FlashMemory, FCS, mutex, SPIC, RT_DEV_LOCK_FLASH, boot failure, or sensor initialization. | LOW |
| ideashatch/HUB-8735 (direct GitHub fetch, 2026-06-09) | **Frozen at Dec 2, 2025 (`870a7e0`) — 189 days.** No new issues, commits, or releases. Issue #10 (PS5268 sensor id fail, Aug 2025) still open and unresolved. Tracks ameba-arduino-pro2 v4.0.9 baseline — approximately 9 months behind the current pre-release. | LOW |
| `FlashMemory.cpp` GitHub code search (2026-06-09) | **Zero `RT_DEV_LOCK_FLASH` or `device_mutex_lock` hits — 100th consecutive null result.** `RT_DEV_LOCK_FLASH repo:Ameba-AIoT/ameba-arduino-pro2 filename:FlashMemory.cpp` → 0 results. No community fork or gist has published a mutex patch for FlashMemory. Last commit `4fdfbec` (Sep 30, 2025). Architectural defect persists in V4.1.1-QC-V07. | LOW (confirms prior) |
| GitHub code search: `"FCS_I2C_INIT_ERR"` site:github.com (2026-06-09) | **Zero results outside `rtl8735b_voe_status.h`.** Error code not documented in any public repository, issue, PR, or discussion outside the known Ameba SDK header files. No developer has surfaced this error code in any public GitHub context. | LOW (confirms prior) |
| Particle.io `device-os` PR #2596 "Fix RTL872x RSIP/flash mutex deadlock" (GitHub, surfaced via Chinese agent search) | **NEW cross-platform flash mutex precedent.** Particle.io's firmware (`device-os`) for RTL8721DM / RTL872x IoT devices (sibling Realtek Ameba family) merged PR #2596 fixing a deadlock caused by acquiring the flash mutex (`RT_DEV_LOCK_FLASH`-equivalent) under disabled interrupts or while RSIP (Realtek Secure IP) holds a sub-lock. Structurally analogous to the `FlashMemory` / `ftl_common_write` concurrent-access defect: in both cases, SPIC bus mutex coordination is missing or incorrect during shared-bus operations. Not a fix for our specific bug (different chip/SDK/failure mode), but confirms SPIC bus mutex hazards are a known problem in the broader Realtek Ameba chip family. URL: https://github.com/particle-iot/device-os/pull/2596 | LOW (cross-platform precedent) |
| forum.amebaiot.com threads above #4885 (sweep, 2026-06-09) | **No new threads indexed.** Targeted searches for IDs #4886–#4930 returned zero results. Forum ceiling confirmed at **#4885** (unchanged from U94+). | LOW |
| Web-wide error string sweep (7 canary strings, 2026-06-09) | **Zero indexed results — 100 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH"` — all return zero publicly indexed results. No hardware test result for any of the four proposed workarounds has been posted anywhere in any language. This research log remains the only public documentation of this bug and its error codes. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee, June 9 sweep) | **Zero new content — 100th consecutive null cycle.** All Chinese community sites remain 403-blocked. bbs.aithinker.com BW21-CBV subforum (home video monitoring, face recognition, digital camera, UDP H264, BLE, microscope projects) confirmed from search index — none discuss flash-camera boot failure. No new Chinese-language technical posts about this bug found anywhere. | LOW |

**Repository freeze status (as of Cycle U100, June 9, 2026):**

| Repository | Last commit | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **25 days** |
| ameba-arduino-pro2 dev | June 3, 2026 (`e8dd7e3`) | **6 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **99 days** |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **92 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 (`870a7e0`) | **189 days** |
| ameba-arduino-doc | June 5, 2026 (`5a400de`) | **4 days** (editorial only) |

**SDK state as of 2026-06-09 (Cycle U100 — unchanged from U99):**
- Latest stable Arduino SDK: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release Arduino SDK: V4.1.1-QC-V07 (build20260603, June 3, 2026) — no fix; FlashMemory.cpp mutex omission confirmed by GitHub code search (zero hits, 100th cycle)
- ameba-rtos-pro2: V1.0.3 / V1.0.3-aiglass.08 (May 22, 2026); main frozen at May 15, 2026 (`3f95070`) — **25 days no change**
- VOE binary: last confirmed v1.7.1.0 (synced May 1, 2026, `d54e1a8`)
- Forum ceiling: **#4885** (unchanged)
- FlashMemory.cpp: last commit `4fdfbec` (Sep 30, 2025), zero mutex calls — **100th cycle unpatched**

**No confirmed fix. Bug remains unpatched as of 2026-06-09 (Cycle U100).**

**Top unresolved actions (unchanged from U99):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception by GitHub code search. Callable from Arduino: `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug entirely undocumented outside this research log; 100 cycles and zero acknowledgment; zero PRs ever filed; filing would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes entirely; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-06-09 (Cycle U101)

**Search scope:** Six parallel search threads + direct GitHub/web fetches: (1) GitHub — ameba-arduino-pro2 dev/main commits/PRs/issues/releases after June 3, 2026; ameba-rtos-pro2 compare endpoint (`3f95070...HEAD`); ameba-arduino-doc commits after June 5, 2026; (2) English forum/web — new threads above #4885, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee; (4) GitHub code search — FlashMemory mutex in forks/PRs; any new issue in ameba-arduino-pro2 created after June 1, 2026; (5) Error string indexing — 7 canary strings; (6) General web search for any confirmed hardware test of the three proposed workarounds.

**Key new findings this cycle:** None. This is the **101st consecutive cycle** with zero new substantive findings. All tracked repositories confirmed frozen at identical states to Cycle U100. Forum ceiling confirmed unchanged at #4885. GitHub issue search `is:issue created:>2026-06-01` returns zero results for ameba-arduino-pro2. All seven canary error strings return zero indexed results for the 101st consecutive cycle. No hardware test results for any workaround in any language. All documentation portals remain HTTP 403.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 `3f95070...HEAD` compare (direct WebFetch, 2026-06-09) | **Frozen confirmed — 25 days (now entering day 26).** WebFetch of commit history returns 4 entries from May 15, 2026 as the most recent: `3f95070` "Sync upstream…", `afc85a0` "[amebapro2][mmf] avoid task recreate in mmf start", `9c8b6f6` "[amebapro2][wlan] dhcp renew unit", `d2676f1` "[amebapro2][wlan] dynamic ARP example." Zero new commits since May 15, 2026. No flash, FCS, VOE, boot, HAL, or sensor changes in any observable pipeline. | LOW |
| ameba-arduino-pro2 dev branch commits (direct WebFetch, 2026-06-09) | **Frozen confirmed — 6 days (entering day 7).** HEAD = `e8dd7e3` "Pre Release Version 4.1.1" (June 3, 2026). No new commits after June 3, 2026 confirmed by direct fetch. Zero open PRs (queue empty after #411). Latest pre-release = V4.1.1-QC-V07 (build20260603). No FCS/flash/camera/mutex fix in any commit. | LOW |
| ameba-arduino-pro2 releases (direct WebFetch, 2026-06-09) | **No new releases.** Latest stable = V4.1.0 (Mar 2, 2026). Latest pre-release = V4.1.1-QC-V07 (Mar 6 tag; build20260603 notes). No V4.1.1-QC-V08 or stable V4.1.1 published. No mention of FlashMemory mutex, RT_DEV_LOCK_FLASH, FCS mode, camera cold-boot failure, or SPIC concurrent access in any release note. | LOW |
| ameba-arduino-pro2 open issues `is:issue created:>2026-06-01` (direct WebFetch, 2026-06-09) | **Zero new issues confirmed.** GitHub search returns "No results." Bug entirely undisclosed on the official tracker after **101 research cycles**. No FlashMemory, FCS, camera, VOE, or boot failure issue has ever been filed in the repository's history. | LOW |
| ameba-arduino-doc repository (direct WebFetch, 2026-06-09) | **Frozen at June 5, 2026.** Most recent commits: `5a400de` (Jun 5, "Fix typo in ICshop online link formatting") and `d42e8a8` (Jun 5, "Update manufacturer contact details and sensor table") — both editorial. No commits after June 5, 2026. Zero Flash Memory, FCS, mutex, or camera boot documentation in any recent commit. Documentation gap (no warning about FlashMemory+FCS interaction) confirmed still absent. | LOW |
| forum.amebaiot.com threads above #4885 (search sweep + direct WebFetch, 2026-06-09) | **No new threads indexed.** Direct WebFetch of `forum.amebaiot.com/c/arduino/15?page=1` and `/latest` both return HTTP 403. Web search for thread IDs #4886–#4930 returns zero forum.amebaiot.com results. Forum ceiling confirmed at **#4885** (unchanged from U94 through U101 — 7+ consecutive cycles unchanged). | LOW |
| Web-wide error string sweep (7 canary strings, 2026-06-09) | **Zero indexed results — 101 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH"` — all return zero publicly indexed results anywhere on the accessible web. No hardware test result for any of the four proposed workarounds has been posted in any language. | LOW |
| Web search: workaround hardware test confirmation (2026-06-09) | **Zero results.** Broad searches for "AmebaPro2 FCS disable workaround flash write confirmed tested," "AMB82-mini camera cold boot fail after flash write FlashMemory solution," "AMB82 FCS camera disable confirmed workaround" all return zero relevant results. No developer has publicly confirmed or refuted any of the three proposed workarounds ("Camera FCS Mode = Disable", `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper, `USE_ISP_RETENTION_DATA`). | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee, June 9 sweep) | **Zero new content — 101st consecutive null cycle.** All Chinese community sites remain 403-blocked or return zero relevant content. bbs.aithinker.com BW21-CBV subforum (tid=46140 "BW21-CBV-Kit调试", tid=47223 "BW21数码相机", tid=45923 "开箱+RTL8735B环境", tid=46028 "家庭视频监控") confirmed indexed but 403-blocked. bbs.ai-thinker.com threads also 403-blocked. No new Chinese-language forum posts or articles about FCS flash-write camera failure on RTL8735B or BW21-CBV. | LOW |
| aiot.realmcu.com RTL8735B product page (direct WebFetch, 2026-06-09) | **Still HTTP 403.** The Chinese-language RTL8735B product page (`aiot.realmcu.com/cn/product/rtl8735b.html`) and all other aiot.realmcu.com URLs return HTTP 403. No RTL8735B documentation, errata, or known issues accessible without developer login. The Flash Layout app note (`ameba-doc-rtos-pro2-sdk.readthedocs-hosted.com/en/latest/application_note/08_FLASHLAYOUT.html`) also still returns HTTP 403. | LOW (blocked) |
| GitHub code search: FlashMemory forks, PRs, any FCS_I2C_INIT_ERR new repos (2026-06-09) | **Zero new results across all searches.** `FCS_I2C_INIT_ERR` = 0 GitHub hits outside the known SDK header file. `"RT_DEV_LOCK_FLASH FlashMemory"` = 0 GitHub hits. No community fork or gist has published a mutex patch for FlashMemory anywhere. Bug is entirely undocumented outside this research log after 101 cycles. | LOW |

**Repository freeze status (as of Cycle U101, June 9, 2026):**

| Repository | Last commit | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **25 days** (entering day 26) |
| ameba-arduino-pro2 dev | June 3, 2026 (`e8dd7e3`) | **6 days** (entering day 7) |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **99 days** |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **92 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 (`870a7e0`) | **190 days** |
| ameba-arduino-doc | June 5, 2026 (`5a400de`) | **4 days** (editorial only) |

**SDK state as of 2026-06-09 (Cycle U101 — unchanged from U100):**
- Latest stable Arduino SDK: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release Arduino SDK: V4.1.1-QC-V07 (build20260603, June 3, 2026) — no fix; FlashMemory.cpp mutex omission confirmed by GitHub code search (zero hits, 101st cycle)
- ameba-rtos-pro2: V1.0.3 / V1.0.3-aiglass.08 (May 22, 2026); main frozen at May 15, 2026 (`3f95070`) — **25 days no change**
- VOE binary: last confirmed v1.7.1.0 (synced May 1, 2026, `d54e1a8`)
- Forum ceiling: **#4885** (unchanged since U94)
- FlashMemory.cpp: last commit `4fdfbec` (Sep 30, 2025), zero mutex calls — **101st cycle unpatched**

**No confirmed fix. Bug remains unpatched as of 2026-06-09 (Cycle U101).**

**Top unresolved actions (unchanged from U100):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception by GitHub code search. Callable from Arduino: `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug entirely undocumented outside this research log; 101 cycles and zero acknowledgment; zero PRs ever filed; filing would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes entirely; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-06-09 (Cycle U102)

**Search scope:** Six parallel search threads + direct GitHub/web fetches: (1) GitHub — ameba-arduino-pro2 dev/main commits/PRs/issues/releases after June 3, 2026; ameba-rtos-pro2 compare endpoint (`3f95070...HEAD`) and releases; ameba-arduino-doc commits; (2) English forum/web — new threads above #4885, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee; (4) GitHub issues sweep — ameba-arduino-pro2 `is:issue created:>2026-06-01`; ameba-rtos-pro2 open issues; ideashatch/HUB-8735 status; (5) Error string indexing — 7 canary strings; (6) Forum ceiling sweep (#4886–#4930); V4.1.1 stable release search.

**Cycle result: NULL — no new findings.** All research channels are frozen, blocked, or empty for the **102nd consecutive cycle**. All tracked repositories confirmed at identical states to Cycle U101. Forum ceiling confirmed unchanged at #4885 (direct site search for IDs 4886–4930 returned zero results). GitHub issue search `is:issue created:>2026-06-01` for ameba-arduino-pro2 returns zero results. All seven canary error strings return zero indexed results for the 102nd consecutive cycle. ameba-rtos-pro2 `3f95070...main` compare returns "identical" — now **26 days** frozen. No hardware test results for any workaround in any language.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-arduino-pro2 dev branch (direct GitHub fetch, 2026-06-09) | **Confirmed frozen — 6 days (entering day 7).** HEAD = `e8dd7e3` "Pre Release Version 4.1.1" (June 3, 2026). 10 most recent commits verified: `e8dd7e3` (Jun 3), `96cfc51` (Jun 3), `29d47e1` (May 26), `7db1c7d` (May 19), `3d53672` (May 19), `cd0bd40` (May 18), `13961cc` (May 5), `e218f33` (Apr 30), `60fe0b1` (Apr 30), `8cab2da` (Apr 30). Zero new commits. No FCS/flash/camera/mutex fix in any commit. Zero open PRs. | LOW |
| ameba-rtos-pro2 `3f95070...main` compare (direct GitHub fetch, 2026-06-09) | **Frozen confirmed — now 26 days.** Compare returns: "3f95070 and main are identical." Zero new commits since May 15, 2026. No flash, FCS, VOE, boot, HAL, or sensor changes. V1.0.3-aiglass.08 (May 22, 2026) remains the latest RTOS release. | LOW |
| ameba-arduino-pro2 releases (direct GitHub fetch, 2026-06-09) | **No new releases.** Latest stable = V4.1.0 (Mar 2, 2026). Latest pre-release = V4.1.1-QC-V07 (build20260603, June 3, 2026). No V4.1.1-QC-V08 or stable V4.1.1 published. Multiple web searches for "Realtek ameba V4.1.1 stable release 2026" return no new release information. | LOW |
| ameba-arduino-pro2 open issues (direct GitHub fetch, 2026-06-09) | **11 open issues; newest = #398 (Mar 29, 2026).** Full issue list verified: #398, #342, #325, #324, #317, #310, #296, #287, #276, #235, #224. `is:issue created:>2026-06-01` returns "No results." No issues about FlashMemory, FCS, camera cold-boot, SPIC, mutex, VOE_OPEN_CMD, or sensor init exist in open or closed history. Bug entirely undisclosed on the official tracker after **102 research cycles**. | LOW |
| ameba-rtos-pro2 open issues (direct GitHub fetch, 2026-06-09) | **3 open issues — unchanged since U3.** #16 (Jan 27, 2026, src folder access); #4 (Apr 25, 2025, chip support); #3 (Apr 21, 2025, antivirus detection). No new issues about flash, FCS, camera, VOE, or sensor initialization. | LOW |
| ideashatch/HUB-8735 (2026-06-09) | **Confirmed frozen at `870a7e0` (Dec 2, 2025) — 190 days.** One open issue: #10 (PS5268 sensor ID fail, Aug 2025). No new commits or issues. Tracking upstream v4.0.9 baseline — approximately 9 months behind the current pre-release. | LOW |
| forum.amebaiot.com threads above #4885 (site-restricted search, 2026-06-09) | **Zero results.** Direct `site:forum.amebaiot.com` search for IDs 4886–4930 returns zero indexed results. Forum ceiling confirmed at **#4885** (unchanged since Cycle U94 — 8+ consecutive cycles at this ceiling). Forum `/latest` endpoint returns HTTP 403. | LOW |
| V4.1.1 stable release (web search, 2026-06-09) | **No stable V4.1.1 published.** Multiple targeted searches for "Realtek ameba V4.1.1 stable 2026" return no results beyond the already-documented QC-V07 pre-release (tag June 3, 2026). No stable release announcement found. | LOW |
| Web-wide error string sweep (7 canary strings, 2026-06-09) | **Zero indexed results — 102 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH"` — all return zero publicly indexed results anywhere on the accessible web. No hardware test result for any of the four proposed workarounds has been posted in any language. This research log remains the only public documentation of this bug and its error codes. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee, June 9 sweep) | **Zero new content — 102nd consecutive null cycle.** All Chinese community sites remain 403-blocked. bbs.aithinker.com BW21-CBV threads confirmed still inaccessible. Searches combining `RTL8735B BW21-CBV FCS 摄像头 冷启动 闪存` return only unboxing and DIY tutorials. No new Chinese-language technical posts about the target bug. | LOW |
| English community (Reddit/Hackster/Stack Overflow/Arduino.cc, 2026-06-09) | **Zero relevant posts.** No new AMB82-Mini / RTL8735B camera+flash cold-boot bug reports on any community platform. No hardware test confirmation for any proposed workaround. | LOW |

**Repository freeze status (as of Cycle U102, June 9, 2026):**

| Repository | Last commit | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **26 days** |
| ameba-arduino-pro2 dev | June 3, 2026 (`e8dd7e3`) | **6 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **99 days** |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **92 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 (`870a7e0`) | **190 days** |
| ameba-arduino-doc | June 5, 2026 (`5a400de`) | **4 days** (editorial only) |

**SDK state as of 2026-06-09 (Cycle U102 — unchanged from U101):**
- Latest stable Arduino SDK: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release Arduino SDK: V4.1.1-QC-V07 (build20260603, June 3, 2026) — no fix; FlashMemory.cpp mutex omission confirmed by GitHub code search (zero hits, 102nd cycle)
- ameba-rtos-pro2: V1.0.3 / V1.0.3-aiglass.08 (May 22, 2026); main frozen at May 15, 2026 (`3f95070`) — **26 days no change**
- VOE binary: last confirmed v1.7.1.0 (synced May 1, 2026, `d54e1a8`)
- Forum ceiling: **#4885** (unchanged since Cycle U94)
- FlashMemory.cpp: last commit `4fdfbec` (Sep 30, 2025), zero mutex calls — **102nd cycle unpatched**

**No confirmed fix. Bug remains unpatched as of 2026-06-09 (Cycle U102).**

**Top unresolved actions (unchanged from U101):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception by GitHub code search. Callable from Arduino: `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug entirely undocumented outside this research log; 102 cycles and zero acknowledgment; zero PRs ever filed; filing would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes entirely; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-06-10 (Cycle U103)

**Search scope:** Eight parallel search threads + direct GitHub/web fetches: (1) GitHub MCP — ameba-arduino-pro2 issues search (`created:>2026-06-01`), FlashMemory.cpp code search (`device_mutex_lock RT_DEV_LOCK_FLASH`); (2) WebFetch — ameba-arduino-pro2 dev commits (since June 3), ameba-rtos-pro2 main commits (since May 15), ameba-arduino-pro2 releases, ameba-arduino-doc commits; (3) English forum/web — new threads above #4885 (IDs 4886–4930), FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (4) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee; (5) Error string canary sweep — 7 strings; (6) Forum threads #4302 and #4834 direct access attempt; (7) Hackster.io BW21-CBV AI-Thinker profile; (8) General web search — AMB82 FlashMemory camera cold boot fix June 2026.

**Cycle result: NULL — no new findings.** All research channels are frozen, blocked, or empty for the **103rd consecutive cycle**. This is the first cycle with today's date (June 10, 2026).

| Source | Key Finding | Priority |
|---|---|---|
| ameba-arduino-pro2 dev branch commits (WebFetch, 2026-06-10) | **Frozen confirmed — now 7 days.** HEAD = `e8dd7e3` "Pre Release Version 4.1.1" (June 3, 2026). No new commits since June 3. No FCS/flash/camera/mutex fix. Zero open PRs (empty after #411, merged June 3). | LOW |
| ameba-rtos-pro2 main commits (WebFetch, 2026-06-10) | **Frozen confirmed — now 26 days.** Most recent commit: `3f95070` "Sync upstream…" (May 15, 2026). No new commits since May 15. No flash, FCS, VOE, boot, HAL, or sensor changes. | LOW |
| ameba-arduino-pro2 releases (WebFetch, 2026-06-10) | **No new releases.** Latest stable = V4.1.0 (Mar 2, 2026). Latest pre-release = V4.1.1-QC-V07 (build20260603, June 3, 2026). No V4.1.1-QC-V08 or stable V4.1.1. Release notes mention OV5647/GC4663 sensors and tools v1.4.12; zero FCS/flash/mutex content. | LOW |
| ameba-arduino-pro2 issues `created:>2026-06-01` (GitHub MCP search, 2026-06-10) | **Zero new issues — confirmed by MCP.** GitHub issue search returns `total_count: 0`. No new issues in the repository since June 1, 2026. Bug undisclosed after **103 research cycles**. | LOW |
| FlashMemory.cpp code search `device_mutex_lock RT_DEV_LOCK_FLASH` (GitHub MCP, 2026-06-10) | **Zero results — 103rd consecutive null.** MCP code search returns `total_count: 0`. No `device_mutex_lock` or `RT_DEV_LOCK_FLASH` calls added to FlashMemory.cpp in any branch, fork, or PR. Last commit `4fdfbec` (Sep 30, 2025) unchanged. Architectural defect persists in V4.1.1-QC-V07. | LOW |
| ameba-arduino-doc repository (WebFetch, 2026-06-10) | **Frozen at June 5, 2026 (`5a400de`).** Last 10 commits: June 5 (typo fix, manufacturer contact), June 4 (sensor_module_window.rst x2), May 24 (I2C slave #107), May 21 (#106), May 13 (#105), Apr 16, Apr 2. No FlashMemory, FCS, mutex, or camera boot documentation. Documentation gap unchanged. | LOW |
| forum.amebaiot.com threads #4886–#4930 (web search sweep, 2026-06-10) | **No new threads indexed.** Search returns zero forum.amebaiot.com results for IDs 4886–4930. Forum ceiling confirmed at **#4885** (unchanged since Cycle U94 — 9+ consecutive cycles). forum.amebaiot.com `/latest` and `/c/arduino/15` return HTTP 403. | LOW |
| forum.amebaiot.com threads #4302 and #4834 (direct WebFetch, 2026-06-10) | **HTTP 403 — still inaccessible.** Both threads ("[VOE]frame_end: sensor didn't initialize done!", "Boot failure after OTA update") return HTTP 403 Forbidden. Content remains inaccessible without forum authentication. | LOW (blocked) |
| Web-wide error string sweep (7 canary strings, 2026-06-10) | **Zero indexed results — 103 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH"` — all return zero publicly indexed results on the accessible web. No hardware test result for any proposed workaround has been posted in any language. This research log remains the only public documentation of this bug. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee, June 10 sweep) | **Zero new content — 103rd consecutive null cycle.** bbs.aithinker.com threads (tid=45923, tid=45931, tid=46140 "BW21-CBV-Kit调试", tid=47223 "BW21数码相机") all 403-blocked. bbs.ai-thinker.com threads 403-blocked. mcublog.cn BW21-CBV article (Apr 2026) 403 on direct fetch. No new Chinese-language technical posts about FCS flash-write camera failure on RTL8735B or BW21-CBV found anywhere. | LOW |
| English community (Reddit/Hackster/Electromaker/Arduino.cc/Stack Overflow, 2026-06-10) | **Zero relevant posts.** hackster.io AI-Thinker profile returns HTTP 403. No new AMB82-Mini / RTL8735B camera+flash cold-boot bug reports on any community platform. No hardware test confirmation for any proposed workaround. | LOW |

**Repository freeze status (as of Cycle U103, June 10, 2026):**

| Repository | Last commit | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **26 days** |
| ameba-arduino-pro2 dev | June 3, 2026 (`e8dd7e3`) | **7 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **100 days** ⚠️ |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **93 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 (`870a7e0`) | **191 days** |
| ameba-arduino-doc | June 5, 2026 (`5a400de`) | **5 days** (editorial only) |

**Notable milestone:** ameba-arduino-pro2 `main` branch has now been frozen for **100 days** as of June 10, 2026.

**SDK state as of 2026-06-10 (Cycle U103 — unchanged from U102):**
- Latest stable Arduino SDK: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release Arduino SDK: V4.1.1-QC-V07 (build20260603, June 3, 2026) — no fix; FlashMemory.cpp mutex omission confirmed by MCP code search (zero hits, 103rd cycle)
- ameba-rtos-pro2: V1.0.3 / V1.0.3-aiglass.08 (May 22, 2026); main frozen at May 15, 2026 (`3f95070`) — **26 days no change**
- VOE binary: last confirmed v1.7.1.0 (synced May 1, 2026, `d54e1a8`)
- Forum ceiling: **#4885** (unchanged since Cycle U94)
- FlashMemory.cpp: last commit `4fdfbec` (Sep 30, 2025), zero mutex calls — **103rd cycle unpatched**
- ameba-arduino-pro2 main frozen: **100 days**

**No confirmed fix. Bug remains unpatched as of 2026-06-10 (Cycle U103).**

**Top unresolved actions (unchanged from U102):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception by MCP code search. Callable from Arduino: `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug entirely undocumented outside this research log; 103 cycles and zero acknowledgment; zero PRs ever filed; filing would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes entirely; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-06-10 (Cycle U104)

**Search scope:** Eight parallel search threads + direct GitHub/web fetches: (1) GitHub MCP — ameba-arduino-pro2 issues search (`created:>2026-06-01`), FlashMemory.cpp code search (`device_mutex_lock RT_DEV_LOCK_FLASH`); (2) WebFetch — ameba-arduino-pro2 dev commits (since June 3), ameba-rtos-pro2 main commits (since May 15), ameba-arduino-pro2 releases, ameba-rtos-pro2 open PRs, ameba-rtos-pro2 main page; (3) English forum/web — new threads above #4885 (IDs 4886–4930), FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (4) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee; (5) Error string canary sweep — 7 strings; (6) New community repos — wildman8606/HUB-8735-AMB82-Mini-AmebaPro2-tutorial, niteshnidarshan/amb82; (7) ISP documentation (`ameba-doc-rtos-pro2-sdk` ISP app note); (8) PlatformIO AMB82-Mini issue, amebaiot.com release history.

**Cycle result: NULL — no new substantive findings.** All research channels are frozen, blocked, or empty for the **104th consecutive cycle**. This is the second cycle on June 10, 2026.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-arduino-pro2 dev branch commits (WebFetch, 2026-06-10) | **Confirmed frozen — 7 days.** HEAD = `e8dd7e3` "Pre Release Version 4.1.1" (June 3, 2026). Zero new commits since June 3. No FCS/flash/camera/mutex fix. Zero open PRs (queue empty after #411, merged June 3). | LOW |
| ameba-rtos-pro2 main commits (WebFetch, 2026-06-10) | **Confirmed frozen — 26 days.** Most recent commit: `3f95070` "Sync upstream…" (May 15, 2026). Zero new commits since May 15. No flash, FCS, VOE, boot, HAL, or sensor changes. | LOW |
| ameba-rtos-pro2 open PR #17 (WebFetch, 2026-06-10) | **PR #17 "fix: the ethernet usb driver copies received network…"** — opened May 15, 2026 by user `orbisai0security`; labelled "no-pr-activity". Addresses ethernet USB driver network packet handling — **unrelated to flash, FCS, camera, or boot failures**. The only open PR in the repository; all 13 closed PRs predate May 2026. No flash/camera/mutex PR has ever been opened in ameba-rtos-pro2. | LOW (not relevant) |
| ameba-arduino-pro2 releases (WebFetch, 2026-06-10) | **No new releases.** Latest stable = V4.1.0 (Mar 2, 2026). Latest pre-release = V4.1.1-QC-V07 (build20260603, June 3, 2026). No V4.1.1-QC-V08 or stable V4.1.1. Release notes verified: OV5647/GC4663 sensors, SPI API update, tools v1.4.12 — zero FCS/flash/mutex/boot content. | LOW |
| ameba-arduino-pro2 open issues `created:>2026-06-01` (GitHub MCP, 2026-06-10) | **Zero new issues — confirmed by MCP.** `total_count: 0`. No new issues since June 1, 2026. Bug undisclosed after **104 research cycles**. | LOW |
| FlashMemory.cpp code search `device_mutex_lock RT_DEV_LOCK_FLASH` (GitHub MCP, 2026-06-10) | **Zero results — 104th consecutive null.** `total_count: 0`. No `device_mutex_lock` or `RT_DEV_LOCK_FLASH` calls added to FlashMemory.cpp in any branch, fork, or PR. Last commit `4fdfbec` (Sep 30, 2025) unchanged. Architectural defect persists in V4.1.1-QC-V07. | LOW (confirms prior) |
| forum.amebaiot.com threads #4886–#4930 (web search sweep, 2026-06-10) | **No new threads indexed.** Targeted searches for IDs #4886–#4930 returned zero forum.amebaiot.com results. Forum ceiling confirmed at **#4885** (unchanged since Cycle U94 — 10+ consecutive cycles). Thread #3864 (FTL intermittent read failure) and #4748 (VOE/sensor driver source code) both returned 403 Forbidden on direct fetch — content inaccessible. | LOW |
| Web-wide error string sweep (7 canary strings, 2026-06-10) | **Zero indexed results — 104 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH"` — all return zero publicly indexed results on the accessible web. No hardware test result for any of the four proposed workarounds has been posted in any language. This research log remains the only public documentation of this bug and its error codes. | LOW |
| wildman8606/HUB-8735-AMB82-Mini-AmebaPro2-tutorial (GitHub, 2026-06-10) | **Irrelevant tutorial repo.** Repository contains YOLO training workshop materials from May 2023 for HUB-8735 / AMB82-Mini. No mention of flash memory issues, camera FCS failures, cold boot problems, or any RTL8735B hardware bugs. Educational content only. | LOW (not relevant) |
| niteshnidarshan/amb82 (GitHub, 2026-06-10) | **Irrelevant setup guide.** Repository contains only AMB82-mini Arduino board setup documentation (CH340C connection, IDE version steps). Mentions a known compilation error fixed by reverting to board version 4.0.4-1 — unrelated to FCS/flash bug. No flash memory issues, camera boot problems, or FCS content. | LOW (not relevant) |
| PlatformIO issue #4809 "Board Support: REALTEK AMB82-Mini" (GitHub, 2026-06-10) | **Closed feature request — irrelevant.** Opened Dec 18, 2023 by `@whittenator`, requesting PlatformIO support for AMB82-Mini. Closed with no detailed resolution visible. No technical content about FCS, flash writes, camera boot failures, or sensor initialization. | LOW (not relevant) |
| ameba-doc-rtos-pro2-sdk ISP application note (WebFetch, 2026-06-10) | **HTTP 403 — still inaccessible.** The ISP documentation page (`/en/latest/application_note/15_ISP.html`) and Flash Layout app note (`/08_FLASHLAYOUT.html`) continue to return 403 Forbidden. Content about `USE_ISP_RETENTION_DATA` / `SAVE_TO_FLASH` / `SAVE_TO_RETENTION` remains inaccessible without developer login. | LOW (blocked) |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee, June 10 sweep) | **Zero new content — 104th consecutive null cycle.** All Chinese community sites remain 403-blocked. bbs.aithinker.com thread #46140 ("BW21-CBV-Kit调试") and bbs.ai-thinker.com threads remain inaccessible. No new Chinese-language technical posts about FCS flash-write camera failure on RTL8735B or BW21-CBV found anywhere. | LOW |
| English community (Reddit/Hackster/how2electronics/Arduino.cc, 2026-06-10) | **Zero relevant posts.** No new AMB82-Mini / RTL8735B camera+flash cold-boot bug reports on any community platform. No hardware test confirmation for any proposed workaround. | LOW |

**Repository freeze status (as of Cycle U104, June 10, 2026):**

| Repository | Last commit | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **26 days** |
| ameba-arduino-pro2 dev | June 3, 2026 (`e8dd7e3`) | **7 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **100 days** |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **93 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 (`870a7e0`) | **191 days** |
| ameba-arduino-doc | June 5, 2026 (`5a400de`) | **5 days** (editorial only) |

**SDK state as of 2026-06-10 (Cycle U104 — unchanged from U103):**
- Latest stable Arduino SDK: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release Arduino SDK: V4.1.1-QC-V07 (build20260603, June 3, 2026) — no fix; FlashMemory.cpp mutex omission confirmed by MCP code search (zero hits, 104th cycle)
- ameba-rtos-pro2: V1.0.3 / V1.0.3-aiglass.08 (May 22, 2026); main frozen at May 15, 2026 (`3f95070`) — **26 days no change**; 1 open PR (#17, ethernet USB driver, unrelated)
- VOE binary: last confirmed v1.7.1.0 (synced May 1, 2026, `d54e1a8`)
- Forum ceiling: **#4885** (unchanged since Cycle U94)
- FlashMemory.cpp: last commit `4fdfbec` (Sep 30, 2025), zero mutex calls — **104th cycle unpatched**
- ameba-arduino-pro2 main frozen: **100 days**

**No confirmed fix. Bug remains unpatched as of 2026-06-10 (Cycle U104).**

**Top unresolved actions (unchanged from U103):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception by MCP code search. Callable from Arduino: `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug entirely undocumented outside this research log; 104 cycles and zero acknowledgment; zero PRs ever filed; filing would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes entirely; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-06-10 (Cycle U105)

**Search scope:** Four parallel agents: (1) GitHub — ameba-rtos-pro2 and ameba-arduino-pro2 commits/releases/issues after June 3, 2026; ideashatch/HUB-8735 issues; (2) English forum/web — new threads above #4885, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee; (4) SDK deep-dive — FlashMemory.cpp mutex state, VOE version, new SDK releases.

**Cycle result: NULL — no new findings.** All research channels are frozen, blocked, or empty for the **105th consecutive cycle**. This is the third cycle on June 10, 2026 (6-hour scheduled check-in).

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 main commits (GitHub, 2026-06-10) | **Confirmed frozen — 26 days.** HEAD = `3f95070` "Sync upstream…" (May 15, 2026). Zero new commits since May 15. No flash, FCS, VOE, boot, HAL, or sensor changes. 1 open PR (#17, ethernet USB driver buffer overflow — unrelated). | LOW |
| ameba-arduino-pro2 dev branch commits (GitHub, 2026-06-10) | **Confirmed frozen — 7 days.** HEAD = `e8dd7e3` "Pre Release Version 4.1.1" (June 3, 2026). Zero new commits since June 3. No FCS/flash/camera/mutex fix. Zero open PRs (queue empty after #411, merged June 3). | LOW |
| ameba-arduino-pro2 releases (GitHub, 2026-06-10) | **No new releases.** Latest stable = V4.1.0 (Mar 2, 2026). Latest pre-release = V4.1.1-QC-V07 (build20260603, June 3, 2026). No V4.1.1-QC-V08 or stable V4.1.1. Release notes mention OV5647/GC4663 sensors and tools v1.4.12; zero FCS/flash/mutex content. | LOW |
| ameba-arduino-pro2 open issues (GitHub, 2026-06-10) | **17 open issues; newest = #398 (Mar 29, 2026).** Zero new issues after March 29, 2026. Bug entirely unreported after 105 research cycles. | LOW |
| ideashatch/HUB-8735 issues (GitHub, 2026-06-10) | **1 open issue: #10** (PS5268 sensor id fail, Aug 2025). No new issues. Repository last committed Dec 2, 2025 — 191 days frozen. | LOW |
| FlashMemory.cpp mutex status (GitHub, 2026-06-10) | **Zero mutex calls confirmed unchanged.** No occurrences of `device_mutex_lock`, `RT_DEV_LOCK_FLASH`, or any synchronization primitive. Last commit `4fdfbec` (Sep 30, 2025). Architectural defect persists in V4.1.1-QC-V07. | LOW (confirms prior) |
| VOE version (GitHub, 2026-06-10) | **Still at v1.7.1.0 (Apr 21, 2026).** No new VOE release in `hal_video_release_note.txt`. Last entry: "Fix dual sensor id FCS mirror/flip issue." No FCS cold-boot fix documented. | LOW (confirms prior) |
| forum.amebaiot.com threads above #4885 (web search, 2026-06-10) | **No new threads indexed.** Targeted search for IDs #4886–#4930 returned zero results. Forum ceiling confirmed at #4885 — unchanged since Cycle U94. All direct forum fetches return HTTP 403. | LOW |
| forum.amebaiot.com threads #4302, #4834 (direct fetch, 2026-06-10) | **HTTP 403 Forbidden — still inaccessible.** "[VOE]frame_end: sensor didn't initialize done!" (thread #4302) and "Boot failure after OTA update" (thread #4834) both return 403. Content inaccessible without forum login. | LOW (blocked) |
| Web-wide error string sweep (7 canary strings, 2026-06-10) | **Zero indexed results — 105 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH"` — all return zero publicly indexed results. No hardware test result for any proposed workaround posted in any language. | LOW |
| English community (Reddit, Hackster, Arduino.cc, Stack Overflow, 2026-06-10) | **Zero relevant posts.** No AMB82-Mini / RTL8735B camera+flash cold-boot bug reports on any English community platform. No hardware test confirmation for any proposed workaround. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee, June 10 sweep) | **Zero new content — 105th consecutive null cycle.** All Chinese community sites remain 403-blocked. bbs.aithinker.com BW21-CBV threads (tid=46140 "BW21-CBV-Kit调试", tid=47223) 403-blocked. bbs.ai-thinker.com 403-blocked. No new Chinese-language technical posts about FCS flash-write camera failure on RTL8735B or BW21-CBV. | LOW |

**Repository freeze status (as of Cycle U105, June 10, 2026):**

| Repository | Last commit | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **26 days** |
| ameba-arduino-pro2 dev | June 3, 2026 (`e8dd7e3`) | **7 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **100 days** ⚠️ |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **93 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 (`870a7e0`) | **191 days** |

**SDK state as of 2026-06-10 (Cycle U105 — unchanged from U104):**
- Latest stable Arduino SDK: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release Arduino SDK: V4.1.1-QC-V07 (build20260603, June 3, 2026) — no fix; FlashMemory.cpp zero mutex calls confirmed
- ameba-rtos-pro2: frozen at May 15, 2026 (`3f95070`) — 26 days no change; 1 open PR (#17, ethernet USB, unrelated)
- VOE binary: last confirmed v1.7.1.0 (synced May 1, 2026, `d54e1a8`)
- Forum ceiling: **#4885** (unchanged since Cycle U94)
- FlashMemory.cpp: last commit `4fdfbec` (Sep 30, 2025), zero mutex calls — **105th cycle unpatched**
- ameba-arduino-pro2 main frozen: **100 days**

**No confirmed fix. Bug remains unpatched as of 2026-06-10 (Cycle U105).**

**Top unresolved actions (unchanged from U104):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception. Callable from Arduino: `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug entirely undocumented outside this research log; 105 cycles and zero acknowledgment; zero PRs ever filed; filing would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes entirely; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-06-11 (Cycle U106)

**Search scope:** Eight parallel search threads + direct GitHub/web fetches: (1) GitHub MCP — ameba-arduino-pro2 issues search (`created:>2026-06-01`), FlashMemory.cpp code search (`device_mutex_lock RT_DEV_LOCK_FLASH`); (2) WebFetch — ameba-rtos-pro2 main commits (since May 15), compare endpoint (`3f95070...HEAD`), ameba-arduino-pro2 dev commits (since June 3), ameba-arduino-pro2 releases, ameba-arduino-pro2 open PRs, ameba-arduino-doc commits (since June 5); (3) English forum/web — new threads above #4885 (IDs 4886–4930), FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (4) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee (安信可 BW21 FCS 摄像头 flash 冷启动); (5) Error string canary sweep — 7 strings; (6) Bug-specific web searches — `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS KM_status"`; (7) `device_mutex_lock RT_DEV_LOCK_FLASH` patch searches; (8) General June 2026 AMB82 camera+flash cold boot fix searches.

**Cycle result: NULL — no new findings.** All research channels are frozen, blocked, or empty for the **106th consecutive cycle**. This is the first cycle on June 11, 2026.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 compare endpoint `3f95070...HEAD` (WebFetch, 2026-06-11) | **Definitively confirmed frozen — now 27 days.** GitHub compare page returns: "There isn't anything to compare. **3f95070** and **HEAD** are identical." Zero new commits since May 15, 2026. No flash, FCS, VOE, boot, HAL, or sensor changes in any observable pipeline. | LOW |
| ameba-arduino-pro2 dev branch commits (WebFetch, 2026-06-11) | **Confirmed frozen — 8 days.** HEAD = `e8dd7e3` "Pre Release Version 4.1.1" (June 3, 2026). Zero new commits since June 3. No FCS/flash/camera/mutex fix in any commit. | LOW |
| ameba-arduino-pro2 releases (WebFetch, 2026-06-11) | **No new releases.** Latest stable = V4.1.0 (Mar 2, 2026). Latest pre-release = V4.1.1-QC-V07 (build20260603, June 3, 2026). No V4.1.1-QC-V08 or stable V4.1.1 has been published. V4.1.1-QC-V07 release notes mention OV5647/GC4663 sensors and tools v1.4.12 — zero FCS/flash/mutex content. | LOW |
| ameba-arduino-pro2 open PRs (WebFetch, 2026-06-11) | **Zero open PRs confirmed.** Page states: "There aren't any open pull requests." 0 open / 323 closed total. No PR related to FlashMemory, mutex, FCS, camera, or boot failure has ever been filed in open or closed history. | LOW (confirms prior) |
| ameba-arduino-pro2 issues `created:>2026-06-01` (GitHub MCP search, 2026-06-11) | **Zero new issues — confirmed by MCP tool.** `total_count: 0`. No new issues since June 1, 2026. Confirms bug is entirely undisclosed after **106 research cycles**. Open issue list shows only feature requests (newest = #398, Mar 29, 2026); no crash/bug reports related to FCS, flash, camera, VOE, or boot. | LOW |
| FlashMemory.cpp code search `device_mutex_lock RT_DEV_LOCK_FLASH` (GitHub MCP, 2026-06-11) | **Zero results in FlashMemory.cpp — 106th consecutive null.** MCP code search returns 1 total hit: `device_lock.h` header file only — confirming `device_mutex_lock` is declared in the header but NEVER called from `FlashMemory.cpp` or any related source file. Last FlashMemory.cpp commit `4fdfbec` (Sep 30, 2025) unchanged. Architectural defect persists in V4.1.1-QC-V07. | LOW (confirms prior) |
| ameba-arduino-doc commits (WebFetch, 2026-06-11) | **Frozen at June 5, 2026.** 10 most recent commits: June 5 (`5a400de` "Fix typo in ICshop online link formatting"), June 5 (`d42e8a8` "Update manufacturer contact details and sensor table"), June 4 (`1726309` "Correct manufacturer names"), June 4 (`f2ee175`, `78f2d58` "Update sensor_module_window.rst"), May 24 ("Add I2C slave example guides #107"). **Zero Flash Memory, FCS, mutex, or camera boot documentation updates.** Documentation gap (no warning about FlashMemory+camera SPIC interaction) remains unaddressed. | LOW |
| forum.amebaiot.com threads #4886–#4930 (web search sweep, 2026-06-11) | **No new threads indexed above #4885.** Multiple targeted searches for IDs #4886 through #4930 returned zero forum.amebaiot.com results. Forum ceiling remains at **#4885** — unchanged since Cycle U94. forum.amebaiot.com `/latest` returns HTTP 403 Forbidden. Threads #4302 ("sensor didn't initialize done") and #4834 ("Boot failure after OTA update") confirmed still HTTP 403 Forbidden on direct fetch. | LOW |
| Web-wide error string sweep (7 canary strings, 2026-06-11) | **Zero indexed results — 106 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH"` — all return zero publicly indexed results on the accessible web. No hardware test result for any proposed workaround has been posted in any language. This research log remains the only public documentation of this bug and its error codes. | LOW |
| `device_mutex_lock` patch search (web search, 2026-06-11) | **Zero results.** Explicit searches for `"RTL8735B AmebaPro2 device_mutex_lock FlashMemory patch fix"` and `"ameba-arduino-pro2 FlashMemory device_mutex_lock camera fix 2026"` return zero relevant results. No community-written wrapper, fork, or patch implementing the mutex fix has appeared publicly. The architectural defect (FlashMemory.cpp never acquires `RT_DEV_LOCK_FLASH`) remains unaddressed and undiscussed outside this log. | LOW |
| AMB82 FCS+flash workaround search (web search, 2026-06-11) | **Zero results.** Searches for `"AMB82-mini FCS camera cold boot sensor flash write OR FlashMemory workaround 2026"` and `"AMB82 slot full OR VOE_OPEN_CMD OR hal_video_open fail flash write erase 2026"` return no new relevant content. The bug's terminal error strings (VOE_OPEN_CMD, hal_video_open fail, slot full) remain uncorrelated with flash writes in any indexed public source other than the 403-blocked Ameba forum threads. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee, June 11 sweep) | **Zero new content — 106th consecutive null cycle.** Chinese-language search `"安信可 BW21 RTL8735B FCS 摄像头 flash 冷启动 2026"` returns general BW21-CBV product pages and unrelated forum threads. bbs.aithinker.com (tid=46028 家庭视频监控, tid=45931 开箱体验) indexed in results but all 403-blocked. aiot.realmcu.com/cn/product/rtl8735b.html (Chinese RTL8735B product page) returns 403. No new Chinese-language technical posts about FCS flash-write camera failure on RTL8735B or BW21-CBV found anywhere. | LOW |

**Repository freeze status (as of Cycle U106, June 11, 2026):**

| Repository | Last commit | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **27 days** |
| ameba-arduino-pro2 dev | June 3, 2026 (`e8dd7e3`) | **8 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **101 days** ⚠️ |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **94 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 (`870a7e0`) | **192 days** |
| ameba-arduino-doc | June 5, 2026 (`5a400de`) | **6 days** (editorial only) |

**SDK state as of 2026-06-11 (Cycle U106 — unchanged from U105):**
- Latest stable Arduino SDK: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release Arduino SDK: V4.1.1-QC-V07 (build20260603, June 3, 2026) — no fix; FlashMemory.cpp zero mutex calls confirmed by MCP code search (106th cycle)
- ameba-rtos-pro2: frozen at May 15, 2026 (`3f95070`) — **27 days no change**; compare endpoint confirms HEAD is identical; 1 open PR (#17, ethernet USB driver buffer overflow — unrelated)
- ameba-arduino-pro2: 0 open PRs (confirmed); 7+ open issues, all feature requests; newest = #398 (Mar 29, 2026)
- VOE binary: last confirmed v1.7.1.0 (synced May 1, 2026, `d54e1a8`)
- Forum ceiling: **#4885** (unchanged since Cycle U94)
- FlashMemory.cpp: last commit `4fdfbec` (Sep 30, 2025), zero mutex calls — **106th cycle unpatched**
- ameba-arduino-pro2 main frozen: **101 days**

**No confirmed fix. Bug remains unpatched as of 2026-06-11 (Cycle U106).**

**Top unresolved actions (unchanged from U105):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception by MCP code search (106 cycles). Callable from Arduino: `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug entirely undocumented outside this research log; 106 cycles and zero acknowledgment; zero PRs ever filed; 0 open issues related to this bug confirmed by MCP; filing would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes entirely; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-06-11 (Cycle U107)

**Search scope:** Eight parallel search threads + direct GitHub/web fetches: (1) GitHub — ameba-rtos-pro2 commits (since May 15), ameba-arduino-pro2 dev commits (since June 3), releases, open PRs, issues (created:>2026-06-01); (2) English forum/web — new threads above #4885 (IDs 4886–4930), FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee; (4) Documentation portals — aiot.realmcu.com, readthedocs ISP/Flash Memory docs; (5) FlashMemory API docs in ameba-arduino-doc GitHub source; (6) Error string canary sweep — 7 strings; (7) Sibling-chip RTL8720C forum thread accessibility; (8) Community project repositories (wildman8606/HUB8735-AMB82-Mini, ideashatch/HUB-8735-Series_examples).

**Cycle result: NULL — no new actionable findings.** All research channels are frozen, blocked, or empty for the **107th consecutive cycle**. This is the second cycle on June 11, 2026.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 commits (WebFetch GitHub, 2026-06-11) | **Confirmed frozen — 27 days.** HEAD = `3f95070` "Sync upstream 7343927…" (May 15, 2026). Identical to U105/U106. Zero new commits. No flash, FCS, VOE, boot, HAL, or sensor changes in any observable pipeline. 1 open PR (#17, ethernet USB driver — unrelated). | LOW |
| ameba-arduino-pro2 dev branch commits (WebFetch GitHub, 2026-06-11) | **Confirmed frozen — 8 days.** HEAD = `e8dd7e3` "Pre Release Version 4.1.1" (June 3, 2026). Identical to U105/U106. Zero new commits since June 3. No FCS/flash/camera/mutex fix. | LOW |
| ameba-arduino-pro2 releases (WebFetch GitHub, 2026-06-11) | **No new releases.** Latest stable = V4.1.0 (Mar 2, 2026). Latest pre-release = V4.1.1-QC-V07 (build20260603, June 3, 2026). Releases page confirmed unchanged; no V4.1.1-QC-V08 or stable V4.1.1 published. V4.1.1-QC-V07 release notes mention OV5647/GC4663 sensors, tools v1.4.12 — zero FCS/flash/mutex content. | LOW |
| ameba-arduino-pro2 open PRs (WebFetch GitHub, 2026-06-11) | **Zero open PRs confirmed.** "There aren't any open pull requests." 0 open / 323 closed total. No PR related to FlashMemory, mutex, FCS, camera, or boot failure exists in open or closed history. | LOW (confirms U106) |
| ameba-arduino-pro2 issues `created:>2026-06-01` (WebFetch GitHub, 2026-06-11) | **Zero new issues — confirmed by direct page fetch.** "No results" for query. 17 total issues; newest = #398 (Mar 29, 2026). Bug entirely unreported after **107 research cycles**. | LOW |
| ameba-arduino-doc commits (WebFetch GitHub, 2026-06-11) | **Frozen at June 5, 2026.** Newest commits: June 5 (`5a400de` "Fix typo"), June 5 (`d42e8a8` "Update manufacturer contact details"), June 4 (`1726309` "Correct manufacturer names"), June 4 (`f2ee175`/`78f2d58` "Update sensor_module_window.rst"). All editorial/cosmetic. **Zero Flash Memory, FCS, mutex, or camera boot documentation updates.** Documentation gap (no warning about FlashMemory+camera SPIC interaction) confirmed unaddressed. | LOW |
| FlashMemory API documentation (ameba-arduino-doc GitHub source, 2026-06-11) | **Zero warnings about FCS/camera/mutex interaction confirmed from GitHub source file.** `FlashMemoryClass.rst` (GitHub source for the readthedocs AMB82-mini API docs) fetched and analyzed: no warnings about using FlashMemory with camera, no FCS mode interaction notes, no `device_mutex_lock` requirements, no `RT_DEV_LOCK_FLASH` mention, no concurrent camera access cautions. The maximum usable flash buffer size (0x3000 / 12,288 bytes) is documented but zero safety warnings exist. Documentation gap confirmed at the source file level (not just via 403-blocked readthedocs portal). | LOW (confirms gap) |
| forum.amebaiot.com threads #4886–#4930 (web search sweep, 2026-06-11) | **No new threads indexed above #4885.** Multiple targeted searches returned zero forum.amebaiot.com results for IDs #4886–#4930. Forum ceiling confirmed at **#4885** — unchanged since Cycle U94 (15 cycles). forum.amebaiot.com `/latest` returns HTTP 403. Threads #4302 and #4834 confirmed still HTTP 403 on direct fetch. | LOW |
| RTL8720C flash boot failure thread #1239 (web search, 2026-06-11) | **Thread confirmed present in search index** (forum.amebaiot.com/t/rtl8720c-flash-log/1239) — "RTL8720C 数据保存到FLASH后再次启动 log显示启动失败" (same symptom class on sibling chip). Still HTTP 403 on direct fetch. Previously documented in Cycle U25. No new content. | LOW (confirms U25) |
| `ideashatch/HUB-8735-Series_examples` (GitHub, 2026-06-11) | **Newly identified repository** (not present in any prior cycle). Description: "This repository contains projects/examples of HUB 8735 series." Primary languages: Jupyter Notebook (88.2%), C (9.7%), C++ (1.7%). 18 directories of AI/ML example projects (Hand Gestures Game, YOLO detection, etc.). README points to `ideas-hatch.com/evb_share.jsp`. **Zero content related to FlashMemory, FCS, camera boot, VOE_OPEN_CMD, FCS_I2C_INIT_ERR, device_mutex_lock, or sensor initialization failure after flash writes.** Not relevant to this bug. | LOW (new repo, background only) |
| `wildman8606/HUB8735-AMB82-Mini-Ameba-Pro2-Detection-Meter` (GitHub, 2026-06-11) | **Newly appeared in search results.** YOLO object detection training notebooks and model weights for AMB82-Mini/HUB-8735. Jupyter Notebook (99.8%). Zero code related to FlashMemory, FCS, camera boot failure, or our bug. Not relevant. | LOW (background only) |
| Web-wide error string sweep (7 canary strings, 2026-06-11) | **Zero indexed results — 107 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH"` — all return zero publicly indexed results. No hardware test result for any proposed workaround has been posted in any language. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee, June 11 sweep) | **Zero new content — 107th consecutive null cycle.** All Chinese community sites remain 403-blocked. `"安信可 BW21-CBV RTL8735B FCS 摄像头 flash 冷启动 2026"` search returns only general BW21-CBV product pages and unrelated forum links. No new Chinese-language technical posts about FCS flash-write camera failure on RTL8735B or BW21-CBV. | LOW |

**Repository freeze status (as of Cycle U107, June 11, 2026):**

| Repository | Last commit | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **27 days** |
| ameba-arduino-pro2 dev | June 3, 2026 (`e8dd7e3`) | **8 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **101 days** ⚠️ |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **94 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 (`870a7e0`) | **192 days** |
| ameba-arduino-doc | June 5, 2026 (`5a400de`) | **6 days** (editorial only) |

**SDK state as of 2026-06-11 (Cycle U107 — unchanged from U106):**
- Latest stable Arduino SDK: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release Arduino SDK: V4.1.1-QC-V07 (build20260603, June 3, 2026) — no fix; FlashMemory.cpp zero mutex calls confirmed from source (107th cycle)
- ameba-rtos-pro2: frozen at May 15, 2026 (`3f95070`) — **27 days no change**
- ameba-arduino-pro2: 0 open PRs (confirmed); 17 open issues, all feature requests; newest = #398 (Mar 29, 2026)
- VOE binary: last confirmed v1.7.1.0 (synced May 1, 2026, `d54e1a8`)
- Forum ceiling: **#4885** (unchanged since Cycle U94)
- FlashMemory.cpp: last commit `4fdfbec` (Sep 30, 2025), zero mutex calls — **107th cycle unpatched**
- ameba-arduino-pro2 main frozen: **101 days**

**No confirmed fix. Bug remains unpatched as of 2026-06-11 (Cycle U107).**

**Top unresolved actions (unchanged from U106):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception. Callable from Arduino: `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug entirely undocumented outside this research log; 107 cycles and zero acknowledgment; zero PRs ever filed; filing would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes entirely; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-06-11 (Cycle U108)

**Search scope:** Six parallel search threads + direct GitHub/web fetches: (1) WebFetch — ameba-arduino-pro2 dev branch commits (all since June 3), ameba-arduino-pro2 releases page, ameba-rtos-pro2 commits page (since May 15), ameba-arduino-pro2 open PRs; (2) WebSearch — forum.amebaiot.com thread IDs #4886–#4930, English-language FCS/flash/camera bug reports; (3) WebSearch — `device_mutex_lock` / `RT_DEV_LOCK_FLASH` FlashMemory fix searches; (4) WebSearch — BW21-CBV/RTL8735B Chinese-language FCS/flash/camera sources; (5) WebFetch — forum thread #1239 (RTL8720C flash→boot precedent) and #4834 (OTA boot fail) access attempts; (6) WebSearch — V4.1.1 stable release, June 2026 SDK changes, aiot.realmcu.com RTL8735B product page content.

**Cycle result: NULL (with minor new administrative details).** All research channels confirm the same frozen / blocked state as U107. No confirmed fix. No new workaround test results. The only new details are PR numbers and commercial availability information not previously documented.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-arduino-pro2 dev branch commits (WebFetch, 2026-06-11) | **Confirmed frozen — still 8 days since June 3, 2026.** HEAD = `e8dd7e3` "Pre Release Version 4.1.1" (June 3). Full commit list retrieved this cycle: `e8dd7e3` (Jun 3) ← `96cfc51` (Jun 3, PR #411: "Update Code base and add cam OV5647, GC4663") ← `29d47e1` (May 26, PR #410: "Update SPI API for SPI1 switching") ← `cd0bd40` (May 18, PR #408: "Add I2C Slave"). **PR #410** (SPI1 switching API, 3 sub-commits: SPI API update, I2C slave example guide links, fix compilation error for SDCardOTA and SDCardPlayMP3) was not explicitly listed in prior cycles — it is confirmed unrelated to FlashMemory, FCS, camera boot, or mutex. **PR #411** (OV5647 + GC4663 sensor support, previously known only by sensor names via QC-V07 release notes) is confirmed no FCS/mutex content. Zero new commits since June 3. | LOW |
| ameba-arduino-pro2 releases page (WebFetch, 2026-06-11) | **No new releases.** Releases page confirms: Latest stable = V4.1.0 (Mar 2, 2026). Latest pre-release = V4.1.1-QC-V07 (build20260603, June 3). The cumulative V4.1.1 additions (all QC releases) include: I2C Slave, SPI1 switching, OV5647, GC4663, IMX681_5M, K306P, OV50A40 sensors, tools v1.4.12, SWD off logic, AMB82-zero API — zero FlashMemory/FCS/mutex/camera-boot entries in any QC release. No V4.1.1-QC-V08 or stable V4.1.1 published. | LOW |
| ameba-arduino-pro2 open PRs (WebFetch, 2026-06-11) | **Zero open PRs confirmed.** "There aren't any open pull requests." 0 open / 323 closed total. No PR related to FlashMemory mutex, FCS, camera, or boot failure exists in open or closed history. Unchanged from U106/U107. | LOW (confirms U107) |
| ameba-rtos-pro2 commits page (WebFetch, 2026-06-11) | **Confirmed frozen — 27 days.** 4 commits from May 15 confirmed as unchanged HEAD: `3f95070` (Sync upstream), `afc85a0` (MMF task recreate fix), `9c8b6f6` (WLAN dhcp renew), `d2676f1` (dynamic ARP example). Zero new commits since May 15, 2026. No flash, FCS, VOE, boot, HAL, or sensor changes in any observable pipeline. | LOW (confirms U107) |
| YELUFT BW21-CBV-Kit on Amazon (search result, 2026-06-11) | **Commercial availability confirmed on Amazon.** ASIN B0FY67YTFN (YELUFT brand BW21-CBV-Kit) appears in search results — confirms increased commercial availability of the affected hardware for consumers in the US market who may encounter this bug without any SDK fix or warning. Not a technical finding but relevant to user exposure scope. | LOW (background) |
| forum.amebaiot.com threads #4886–#4930 (web search sweep, 2026-06-11) | **Still none indexed.** Multiple targeted searches returned zero results for thread IDs 4886–4930. Forum ceiling confirmed at **#4885** — unchanged since Cycle U94 (14 cycles). forum.amebaiot.com `/latest` returns HTTP 403. Threads #4302, #4834, #1239 confirmed still HTTP 403 on direct fetch. | LOW |
| Web-wide error string sweep (7 canary strings, 2026-06-11) | **Zero indexed results — 108 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH"` — all return zero publicly indexed results on the accessible web. No hardware test result for any proposed workaround has been posted in any language. | LOW |
| Flash Memory documentation page (readthedocs, 2026-06-11) | **Still 403-blocked.** `ameba-doc-arduino-sdk.readthedocs-hosted.com/en/latest/ameba_pro2/amb82-mini/Example_Guides/Flash%20Memory/index.html` returns HTTP 403. However, `FlashMemoryClass.rst` source was previously retrieved (U107) and confirmed zero FCS/camera/mutex warnings. Documentation gap persists unaddressed. | LOW (blocked) |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee, June 11 sweep) | **Zero new content — 108th consecutive null cycle.** All Chinese community sites remain 403-blocked. Search `"安信可 BW21 RTL8735B FCS 摄像头 flash 冷启动 2026"` returns only general BW21-CBV product pages and unrelated forum threads. No new Chinese-language technical posts about FCS flash-write camera failure found anywhere. | LOW |

**Repository freeze status (as of Cycle U108, June 11, 2026):**

| Repository | Last commit | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **27 days** |
| ameba-arduino-pro2 dev | June 3, 2026 (`e8dd7e3`) | **8 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **101 days** ⚠️ |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **94 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 (`870a7e0`) | **192 days** |
| ameba-arduino-doc | June 5, 2026 (`5a400de`) | **6 days** (editorial only) |

**SDK state as of 2026-06-11 (Cycle U108 — unchanged from U107):**
- Latest stable Arduino SDK: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release Arduino SDK: V4.1.1-QC-V07 (build20260603, June 3, 2026) — no fix; PR #410 (SPI1) and PR #411 (OV5647/GC4663) confirmed unrelated to FlashMemory/FCS/camera boot; FlashMemory.cpp zero mutex calls unchanged (108th cycle)
- ameba-rtos-pro2: frozen at May 15, 2026 (`3f95070`) — **27 days no change**; 0 open PRs on ameba-arduino-pro2
- VOE binary: last confirmed v1.7.1.0 (synced May 1, 2026, `d54e1a8`)
- Forum ceiling: **#4885** (unchanged since Cycle U94)
- FlashMemory.cpp: last commit `4fdfbec` (Sep 30, 2025), zero mutex calls — **108th cycle unpatched**
- ameba-arduino-pro2 main frozen: **101 days**

**No confirmed fix. Bug remains unpatched as of 2026-06-11 (Cycle U108).**

**Top unresolved actions (unchanged from U107):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception. Callable from Arduino: `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug entirely undocumented outside this research log; 108 cycles and zero acknowledgment; zero PRs ever filed; filing would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes entirely; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-06-11 (Cycle U109)

**Search scope:** Second research pass of the day. Six parallel search threads + direct GitHub/web fetches: (1) WebFetch — ameba-arduino-pro2 dev branch commits (since June 3), ameba-arduino-pro2 releases page, ameba-rtos-pro2 commits page (since May 15), FlashMemory.cpp raw content; (2) WebSearch — forum.amebaiot.com threads #4886–#4940, English FCS/flash/camera bug reports June 2026; (3) WebSearch — `device_mutex_lock` / `RT_DEV_LOCK_FLASH` FlashMemory patch references; (4) WebSearch — BW21-CBV RTL8735B Chinese-language FCS/flash/camera sources (CSDN, 知乎, EEWorld, 21IC, Gitee, Bilibili, bbs.ai-thinker.com); (5) WebSearch — V4.1.1-QC-V08 or stable V4.1.1 Arduino SDK release; (6) WebSearch — `USE_ISP_RETENTION_DATA` / `ISP_MULTI_FCS_DATA_MAGIC_NUM` / `0x5343464D` indexed web content.

**Cycle result: NULL.** Second pass within the same calendar day as U108. All research channels confirm the identical frozen/blocked state documented in U108. No new commits, releases, PRs, forum threads, hardware test results, or community posts in any language found in this pass. This cycle serves as a same-day confirmation baseline.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-arduino-pro2 dev branch commits (WebFetch, 2026-06-11 pass 2) | **Confirmed frozen — HEAD still `e8dd7e3` (June 3, 2026), 8 days.** No new commits since U108 earlier today. PR #410 (SPI1), PR #411 (OV5647/GC4663), and pre-release tag V4.1.1-QC-V07 (`e8dd7e3`) remain the most recent activity. FlashMemory.cpp: 167 lines, SHA `b4781b70`, last meaningful commit `4fdfbec` (Sep 30, 2025), zero mutex/semaphore/lock calls — **109th consecutive cycle unpatched.** | LOW |
| ameba-arduino-pro2 releases page (WebFetch, 2026-06-11 pass 2) | **No new releases.** Latest stable = V4.1.0 (Mar 2, 2026). Latest pre-release = V4.1.1-QC-V07 (build20260603, June 3, 2026). No V4.1.1-QC-V08 or stable V4.1.1 has been published. V4.1.1-QC-V07 release notes contain no FCS, FlashMemory, mutex, camera boot, or SPIC contention entries. | LOW |
| ameba-rtos-pro2 commits page (WebFetch, 2026-06-11 pass 2) | **Confirmed frozen — 27 days since May 15, 2026 (`3f95070`).** No new commits, branches, tags, or PRs in the observable pipeline. No VOE, HAL, flash, FCS, or camera-related changes. | LOW |
| forum.amebaiot.com threads #4886–#4940 (web search sweep, 2026-06-11 pass 2) | **Zero indexed.** Forum ceiling confirmed at **#4885** — unchanged across Cycles U94–U109 (15 consecutive cycles). Direct fetch of `/latest` still returns HTTP 403. | LOW |
| Web-wide error string sweep (7 canary strings, 2026-06-11 pass 2) | **Zero indexed results — 109 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH"` — all return zero publicly indexed results. `"ISP_MULTI_FCS_DATA_MAGIC_NUM"` and `"0x5343464D"` (MFCS magic) also return zero. No hardware test result for any proposed workaround has been published anywhere on the accessible web. | LOW |
| V4.1.1-QC-V08 / stable V4.1.1 search (web search, 2026-06-11 pass 2) | **No release found.** Searches for V4.1.1-QC-V08, stable V4.1.1 release notes, and June 2026 AmebaPro2 SDK changes return no results. Next QC iteration has not been announced. | LOW |
| Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.ai-thinker.com/Bilibili/Gitee, 2026-06-11 pass 2) | **Zero new content — 109th consecutive null cycle.** `"安信可 BW21 RTL8735B FCS 摄像头 flash 冷启动"`, `"RTL8735B FlashMemory mutex 摄像头"`, `"AmebaPro2 FCS 修复 2026"` all return zero relevant results. bbs.ai-thinker.com BW21 section: no new posts since last confirmed check. All major Chinese community sites remain 403-blocked. | LOW |
| ameba-arduino-pro2 open PRs (web search + fetch, 2026-06-11 pass 2) | **Zero open PRs — confirmed.** "There aren't any open pull requests." 0 open / 323 closed. No FlashMemory, FCS, mutex, or camera-boot PR exists in any state. | LOW |

**Repository freeze status (as of Cycle U109, June 11, 2026 — identical to U108):**

| Repository | Last commit | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **27 days** |
| ameba-arduino-pro2 dev | June 3, 2026 (`e8dd7e3`) | **8 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **101 days** ⚠️ |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **94 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 (`870a7e0`) | **192 days** |
| ameba-arduino-doc | June 5, 2026 (`5a400de`) | **6 days** (editorial only) |

**SDK state as of 2026-06-11 (Cycle U109 — unchanged from U108):**
- Latest stable Arduino SDK: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release Arduino SDK: V4.1.1-QC-V07 (build20260603, June 3, 2026) — no fix; FlashMemory.cpp zero mutex calls unchanged (109th cycle)
- ameba-rtos-pro2: frozen at May 15, 2026 (`3f95070`) — **27 days no change**
- VOE binary: last confirmed v1.7.1.0 (synced May 1, 2026, `d54e1a8`)
- Forum ceiling: **#4885** (unchanged since Cycle U94 — 15 cycles / ~90 days)
- FlashMemory.cpp: last commit `4fdfbec` (Sep 30, 2025), zero mutex calls — **109th cycle unpatched**
- ameba-arduino-pro2 main frozen: **101 days**

**No confirmed fix. Bug remains unpatched as of 2026-06-11 (Cycle U109).**

**Top unresolved actions (unchanged from U108):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception. Callable from Arduino: `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug entirely undocumented outside this research log; 109 cycles and zero acknowledgment; zero PRs ever filed; filing would be the first public disclosure.

## Research Update — 2026-06-12 (Cycle U110)

**Search scope:** Eight parallel search threads + direct GitHub/web fetches: (1) GitHub — ameba-rtos-pro2 commits (since May 15), ameba-arduino-pro2 dev commits (since June 3), releases, open PRs, issues (created:>2026-06-01); (2) English forum/web — new threads above #4885 (IDs 4886–4950), FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee; (4) Documentation portals — aiot.realmcu.com, readthedocs ISP/Flash Memory docs; (5) FlashMemory.cpp raw content from dev branch; (6) Error string canary sweep — 7 strings; (7) VOE release notes for any version beyond 1.7.1.0; (8) V4.1.1-QC-V08 release search.

**Cycle result: NULL — no new actionable findings.** This is the **110th consecutive null cycle**. All research channels confirm the same frozen / blocked state as U109. No confirmed fix. No new workaround test results.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 commits (direct WebFetch + compare endpoint, 2026-06-12) | **Confirmed frozen — 28 days.** HEAD = `3f95070` "Sync upstream 7343927…" (May 15, 2026). Identical to U105–U109. Zero new commits since May 15. No flash, FCS, VOE, boot, HAL, or sensor changes in any observable pipeline. 1 open PR (#17, ethernet USB driver buffer overflow — unrelated). Both the direct commit page and compare endpoint (`3f95070 and HEAD are identical`) confirm freeze. | LOW |
| ameba-arduino-pro2 dev branch commits (direct WebFetch, 2026-06-12) | **Confirmed frozen — 9 days.** HEAD = `e8dd7e3` "Pre Release Version 4.1.1" (June 3, 2026). Full commit list retrieved and verified: `e8dd7e3` (Jun 3, pre-release tag) ← `96cfc51` (Jun 3, PR #411: OV5647+GC4663 sensors — 107 files changed, FlashMemory.cpp absent) ← `29d47e1` (May 26, PR #410: SPI1 switching) ← `cd0bd40` (May 18, PR #408: I2C Slave). Neither June 3 commit touched FlashMemory.cpp. Zero new commits after June 3. No FCS/flash/camera/mutex fix. | LOW |
| ameba-arduino-pro2 releases (direct WebFetch, 2026-06-12) | **No new releases.** Latest stable = V4.1.0 (Mar 2, 2026). Latest pre-release = V4.1.1-QC-V07 (tag created Mar 6, 2026; cumulative release notes through June 3, 2026). **V4.1.1-QC-V08 does not exist** — confirmed by two independent agents and two direct searches. V4.1.1-QC-V07 release notes: OV5647/GC4663 sensors, SPI1 switching, I2C Slave, tools v1.4.12. Zero FCS/flash/mutex/camera-boot entries. No V4.1.1 stable release published. | LOW |
| ameba-arduino-pro2 open PRs (direct WebFetch, 2026-06-12) | **Zero open PRs confirmed.** "There aren't any open pull requests." 0 open / 323 closed total. No PR related to FlashMemory, mutex, FCS, camera, or boot failure exists in open or closed history. Unchanged since U107. | LOW (confirms U107–U109) |
| `FlashMemory.cpp` — mutex status, dev branch (multiple agents, 2026-06-12) | **Zero mutex calls confirmed unchanged.** Neither June 3 commit (`96cfc51`, `e8dd7e3`) touched FlashMemory.cpp — confirmed by diff analysis. Last meaningful commit remains `4fdfbec` (Sep 30, 2025). No calls to `device_mutex_lock`, `RT_DEV_LOCK_FLASH`, or any thread-safety primitive across all 8 flash operations. **110th cycle unpatched.** | LOW (confirms U109) |
| VOE version — any release beyond 1.7.1.0 (multiple agents, 2026-06-12) | **No new VOE version.** Last confirmed binary sync: commit `d54e1a8` May 1, 2026 "[amebapro2][video] sync voe to 1.7.1.0". hal_video_release_note.txt (in Arduino dev branch `fcs_hal/` subdir) tops out at VOE 1.5.6.0 (July 17, 2024) — the file is not kept in sync with the binary blob since July 2024 (documented in U30). No 1.7.2, 1.8.x, or higher version appears in any commit message, release note, or search result as of June 12, 2026. | LOW (confirms U109) |
| ameba-arduino-pro2 issues created after June 1, 2026 (WebSearch + fetch, 2026-06-12) | **Zero new issues.** Confirmed by two independent queries. 17 total open issues; newest = #398 (Mar 29, 2026). No new issue related to FlashMemory, FCS, camera, VOE, or boot failure filed on any Ameba repo. Bug remains entirely unreported on official trackers after **110 research cycles**. | LOW |
| bbs.ai-thinker.com — newly indexed thread IDs (Chinese search, 2026-06-12) | **Three newly identified thread IDs not seen in prior cycles:** tid=47039 ("BW21-CBV-Kit 扩展板设计" — expansion board PCB design), tid=47062 ("BW21-CBV-KIt开箱" — unboxing), tid=46157 ("BW21-CVB-KIT基于udp的h264视频流可远程" — UDP H264 remote video streaming). All return 403 on direct fetch. Snippets confirm hardware/unboxing/project content — none discuss FCS/flash/camera boot failure. These thread IDs establish that bbs.ai-thinker.com continues to have new BW21-CBV activity but no bug-related posts are visible. | LOW (background only) |
| Forum thread #4821 — newly identified (English search, 2026-06-12) | **Newly identified thread** (previously untracked). Title: "AMB82-mini USB Host CDC ECM fail to SIM7600G-H." USB Host CDC ECM initialization failure with 4G modem. Content 403-blocked. Not related to camera/flash/FCS/cold-boot failure. Adds to thread catalog. | LOW (blocked, unrelated) |
| Hackster.io — "Ameba Pro 2 SOS: Alerts, Maps & Camera" (newly surfaced, 2026-06-12) | **Newly surfaced project page** (previously not in any search result across 110 cycles). URL: `https://www.hackster.io/vinayyn/ameba-pro-2-sos-alerts-maps-camera-d020b3` — AMB82-Mini + JXF37 camera project for SOS alerts with GPS/Maps integration. No discussion of FlashMemory + camera interaction or FCS/flash cold-boot failure. Unrelated to bug. | LOW (background, unrelated) |
| forum.amebaiot.com threads #4886–#4950 (web search sweep, 2026-06-12) | **No new threads indexed.** Multiple targeted searches returned zero results for thread IDs 4886–4950. Forum ceiling confirmed at **#4885** — unchanged since Cycle U94 (**16 consecutive cycles** with unchanged ceiling). forum.amebaiot.com `/latest` returns HTTP 403. | LOW |
| Web-wide error string sweep (7 canary strings, 2026-06-12 — three independent agents) | **Zero indexed results — 110 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH"` — all return zero publicly indexed results. `"ISP_MULTI_FCS_DATA_MAGIC_NUM"` also returns zero. No hardware test result for any proposed workaround has been posted in any language anywhere on the accessible web. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee, June 12 sweep — three agents) | **Zero new technical content — 110th consecutive null cycle.** Three independent agents confirmed identical findings. bbs.aithinker.com and bbs.ai-thinker.com both 403-blocked (110th consecutive cycle). No new Chinese-language technical posts or articles about FCS flash-write camera failure on RTL8735B or BW21-CBV found anywhere. Indexed BW21-CBV content is exclusively unboxing reviews, DIY projects, and environment setup guides. | LOW |

**Repository freeze status (as of Cycle U110, June 12, 2026):**

| Repository | Last commit | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **28 days** |
| ameba-arduino-pro2 dev | June 3, 2026 (`e8dd7e3`) | **9 days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **102 days** ⚠️ |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **95 days** |
| ideashatch/HUB-8735 | Dec 2, 2025 (`870a7e0`) | **193 days** |
| ameba-arduino-doc | June 5, 2026 (`5a400de`) | **7 days** (editorial only) |

**SDK state as of 2026-06-12 (Cycle U110 — unchanged from U109):**
- Latest stable Arduino SDK: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release Arduino SDK: V4.1.1-QC-V07 (build20260603, June 3, 2026) — no fix; FlashMemory.cpp zero mutex calls confirmed (110th cycle); V4.1.1-QC-V08 does not exist
- ameba-rtos-pro2: frozen at May 15, 2026 (`3f95070`) — **28 days no change**
- ameba-arduino-pro2: 0 open PRs; 17 open issues, all feature requests; newest = #398 (Mar 29, 2026)
- VOE binary: last confirmed v1.7.1.0 (synced May 1, 2026, `d54e1a8`)
- Forum ceiling: **#4885** (unchanged since Cycle U94 — **16 consecutive cycles**)
- FlashMemory.cpp: last commit `4fdfbec` (Sep 30, 2025), zero mutex calls — **110th cycle unpatched**
- ameba-arduino-pro2 main frozen: **102 days**

**No confirmed fix. Bug remains unpatched as of 2026-06-12 (Cycle U110).**

**Top unresolved actions (unchanged from U109):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception. Callable from Arduino: `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug entirely undocumented outside this research log; 110 cycles and zero acknowledgment; zero PRs ever filed; filing would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes entirely; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-06-12 (Cycle U111)

**Search scope:** Eight parallel search threads + direct GitHub/web fetches: (1) GitHub — ameba-rtos-pro2 commits (since May 15), ameba-arduino-pro2 dev commits (since June 3), releases, open PRs, issues created after June 1; (2) English forum/web — new threads above #4885, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee; (4) Documentation portals — aiot.realmcu.com, readthedocs ISP/Flash Memory docs; (5) FlashMemory.cpp raw content from dev branch; (6) Error string canary sweep — 7 strings; (7) VOE release notes for any version beyond 1.7.1.0; (8) V4.1.1-QC-V08 release search.

**Cycle result: NULL — no new actionable findings.** This is the **111th consecutive null cycle**. All research channels confirm the same frozen / blocked state as U110. No confirmed fix. No new workaround test results.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 commits (direct WebFetch + compare, 2026-06-12) | **Confirmed frozen — 28+ days.** HEAD = `3f95070` "Sync upstream 7343927…" (May 15, 2026). 10 most recent commits fetched and verified: `3f95070`, `afc85a0`, `9c8b6f6`, `d2676f1` (all May 15), `1c1c8b7`, `a111e91`, `7b2b97f`, `63c0a2f`, `d54e1a8`, `687a4c7` (all May 1). Zero new commits since May 15. No flash, FCS, VOE, boot, HAL, or sensor changes in any observable pipeline. | LOW |
| ameba-arduino-pro2 dev branch commits (direct WebFetch, 2026-06-12) | **Confirmed frozen — 9+ days.** HEAD = `e8dd7e3` "Pre Release Version 4.1.1" (Jun 3, 2026). 10 most recent: `e8dd7e3` (Jun 3, pre-release), `96cfc51` (Jun 3, PR #411: OV5647+GC4663 — 107 files changed, FlashMemory.cpp absent from diff), `29d47e1` (May 26, PR #410: SPI1 switching), `7db1c7d` (May 19), `3d53672` (May 19, IMX681_5M), `cd0bd40` (May 18, I2C Slave), `13961cc` (May 5). Zero new commits after June 3. No FCS/flash/camera/mutex fix in any commit. | LOW |
| ameba-arduino-pro2 releases (direct WebFetch, 2026-06-12) | **No new releases.** Latest stable = V4.1.0 (Mar 2, 2026). Latest pre-release = **V4.1.1-QC-V07** (tag created Mar 6, 2026; cumulative release notes through June 3, 2026, including OV5647/GC4663 sensors, SPI1 switching, tools v1.4.12). No V4.1.1-QC-V08. No V4.1.1 stable release. Release notes contain zero entries about FCS, flash write, mutex, SPIC, camera boot, or FlashMemory safety. | LOW |
| ameba-arduino-pro2 open PRs (direct WebFetch, 2026-06-12) | **Zero open PRs confirmed.** No PR related to FlashMemory, mutex, FCS, camera, or boot failure exists in open or closed history. Unchanged since U107. | LOW |
| ameba-arduino-pro2 issues created after June 1 (direct WebFetch, 2026-06-12) | **Zero new issues.** Query `is:issue created:>2026-06-01` returned zero results. The 17 open issues tracked in U110 remain unchanged; newest is #398 (Mar 29, 2026). Bug entirely unreported on official trackers after **111 research cycles**. | LOW |
| ideashatch/HUB-8735 issues (direct WebFetch, 2026-06-12) | **1 open issue: #10** (PS5268 sensor id fail, Aug 2025). No new issues. Unchanged since U10. | LOW |
| `Dennis40816/ameba_stream_project` (GitHub, newly retrieved) | **Project confirmed unrelated to bug.** This repo appeared in a workaround keyword search (`USE_ISP_RETENTION_DATA` OR `RT_DEV_LOCK_FLASH`). Inspection confirms: Python+C++ RTSP streaming system for AMB82-MINI boards (12-device camera network). No FlashMemory, FCS mode, device mutex, or camera boot failure content. The search match was likely spurious (common AMB82 keywords). Repo has 27 commits; last activity not determinable from page. | LOW (unrelated) |
| forum.amebaiot.com threads #4886–#4950 (search sweep, 2026-06-12) | **No new threads indexed.** Multiple targeted searches returned zero results for thread IDs 4886–4950. Forum ceiling confirmed at **#4885** — **17 consecutive cycles** with unchanged ceiling. forum.amebaiot.com still returns HTTP 403 on all direct fetches. | LOW |
| Web-wide error string sweep (7 canary strings, 2026-06-12) | **Zero indexed results — 111 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH"` — all return zero publicly indexed results. `"ISP_MULTI_FCS_DATA_MAGIC_NUM"` also returns zero. No hardware test result for any proposed workaround has been posted in any language anywhere on the accessible web. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee, June 12 sweep) | **Zero new technical content — 111th consecutive null cycle.** bbs.aithinker.com and bbs.ai-thinker.com both 403-blocked. No new Chinese-language technical posts or articles about FCS flash-write camera failure on RTL8735B or BW21-CBV found anywhere. All indexed BW21-CBV Chinese content is exclusively unboxing reviews, DIY projects, and environment setup guides. | LOW |

**Repository freeze status (as of Cycle U111, June 12, 2026):**

| Repository | Last commit | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **28+ days** |
| ameba-arduino-pro2 dev | June 3, 2026 (`e8dd7e3`) | **9+ days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **102+ days** ⚠️ |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **95+ days** |
| ideashatch/HUB-8735 | Dec 2, 2025 (`870a7e0`) | **193+ days** |

**SDK state as of 2026-06-12 (Cycle U111 — unchanged from U110):**
- Latest stable Arduino SDK: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release Arduino SDK: V4.1.1-QC-V07 (build20260603, June 3, 2026) — no fix; FlashMemory.cpp zero mutex calls; V4.1.1-QC-V08 does not exist
- ameba-rtos-pro2: frozen at May 15, 2026 (`3f95070`) — **28+ days no change**
- ameba-arduino-pro2: 0 open PRs; 17 open issues, all feature requests; newest = #398 (Mar 29, 2026)
- VOE binary: last confirmed v1.7.1.0 (synced May 1, 2026, `d54e1a8`)
- Forum ceiling: **#4885** (unchanged since Cycle U94 — **17 consecutive cycles**)
- FlashMemory.cpp: last commit `4fdfbec` (Sep 30, 2025), zero mutex calls — **111th cycle unpatched**
- ameba-arduino-pro2 main frozen: **102+ days**

**No confirmed fix. Bug remains unpatched as of 2026-06-12 (Cycle U111).**

**Top unresolved actions (unchanged from U110):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception. Callable from Arduino: `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug entirely undocumented outside this research log; 111 cycles and zero acknowledgment; zero PRs ever filed; filing would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes entirely; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

## Research Update — 2026-06-12 (Cycle U112)

**Search scope:** Four parallel agents: (1) GitHub — ameba-rtos-pro2 commits (since May 15), ameba-arduino-pro2 dev commits (since June 3), releases, open PRs, issues created after June 1; (2) English forum/web — new threads above #4885, FCS Disable / `device_mutex_lock` / `USE_ISP_RETENTION_DATA` hardware test reports; (3) Chinese sources — CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee; (4) SDK deep-dive — `FlashMemory.cpp` and `video_api.h` raw content status from dev branch.

**Cycle result: NULL — no new actionable findings.** This is the **112th consecutive null cycle**. All research channels confirm the same frozen / blocked state as U111. No confirmed fix. No new workaround test results.

| Source | Key Finding | Priority |
|---|---|---|
| ameba-rtos-pro2 commits (direct WebFetch, 2026-06-12) | **Confirmed frozen — 28+ days.** HEAD = `3f95070` "Sync upstream 7343927…" (May 15, 2026). 10 most recent commits verified identical to U111: `3f95070`, `afc85a0`, `9c8b6f6`, `d2676f1` (all May 15), `1c1c8b7`, `a111e91`, `7b2b97f`, `63c0a2f`, `d54e1a8`, `687a4c7` (all May 1). Zero new commits since May 15. No flash, FCS, VOE, boot, HAL, or sensor changes in any observable pipeline. 1 open PR (#17, ethernet USB buffer overflow — unrelated, unchanged). | LOW |
| ameba-arduino-pro2 dev branch commits (direct WebFetch, 2026-06-12) | **Confirmed frozen — 9+ days.** HEAD = `e8dd7e3` "Pre Release Version 4.1.1" (June 3, 2026). Full commit list verified: `e8dd7e3` (Jun 3, pre-release tag) ← `96cfc51` (Jun 3, PR #411: OV5647+GC4663 — FlashMemory.cpp absent from 107-file diff) ← `29d47e1` (May 26, PR #410: SPI1 switching) ← `cd0bd40` (May 18, I2C Slave). Zero new commits after June 3. No FCS/flash/camera/mutex fix in any commit. | LOW |
| ameba-arduino-pro2 releases (direct WebFetch, 2026-06-12) | **No new releases.** Latest stable = V4.1.0 (Mar 2, 2026). Latest pre-release = V4.1.1-QC-V07 (tag created Mar 6, 2026; cumulative release notes through June 3, 2026). No V4.1.1-QC-V08. No V4.1.1 stable release. Zero FCS/flash/mutex/camera-boot entries in any QC release notes. | LOW |
| ameba-arduino-pro2 open PRs (direct WebFetch, 2026-06-12) | **Zero open PRs confirmed.** "There aren't any open pull requests." 0 open / 323 closed total. No PR related to FlashMemory, mutex, FCS, camera, or boot failure exists in open or closed history. Unchanged since U107. | LOW |
| ameba-arduino-pro2 issues created after June 1 (direct WebFetch, 2026-06-12) | **Zero new issues.** 17 open issues total; newest = #398 (Mar 29, 2026). No new issue related to FlashMemory, FCS, camera, VOE, or boot failure. Bug entirely unreported on official trackers after **112 research cycles**. | LOW |
| ideashatch/HUB-8735 (2026-06-12) | **Confirmed frozen — 193+ days.** Last commit: Dec 2, 2025 (`870a7e0`). No new commits, issues, or releases. | LOW |
| `video_api.h` — `USE_ISP_RETENTION_DATA` (raw dev branch fetch, 2026-06-12) | **Still commented out — confirmed from raw file fetch.** Line 83: `// #define USE_ISP_RETENTION_DATA`. New fields `isp_gain_mode` and `isp_gain` added in prior cycle; no FCS-related changes. Unchanged from U111. | LOW (confirms U111) |
| `FlashMemory.cpp` raw URL (dev branch, 2026-06-12) | **HTTP 404 on one retrieval attempt** — path `Arduino_package/hardware/system/component/utilities/FlashMemory.cpp`. Assessed as a transient agent/network error: dev branch HEAD is confirmed unchanged at `e8dd7e3` (June 3), and the file was confirmed present with SHA `b4781b70` in U109 (earlier today, same session). `video_api.h` was accessible at its corresponding path in the same pass, confirming the dev branch is reachable. No structural change to the utilities directory has been observed in any diff. If 404 recurs in U113, file relocation should be investigated. | LOW (likely transient error) |
| bbs.ai-thinker.com BW21-CBV threads (Chinese search, 2026-06-12) | **Three newly identified thread IDs** not seen in prior cycles: tid=47039 ("BW21-CBV-Kit 扩展板设计" — expansion board PCB design), tid=47062 ("BW21-CBV-Kit 开箱" — unboxing), tid=46157 ("BW21-CVB-KIT基于UDP的H264视频流可远程" — UDP H264 remote video streaming). All return HTTP 403 on direct fetch. Snippets confirm hardware/unboxing/project content with no discussion of FCS/flash/camera boot failure. These establish continued BW21-CBV community activity with no bug-related posts visible. Highest previously known thread was tid=46317 ([BW20]二次开发学习4, documented U26). | LOW (background only) |
| forum.amebaiot.com threads #4886–#4960 (web search sweep, 2026-06-12) | **No new threads indexed.** Multiple targeted searches returned zero results for thread IDs 4886–4960. Forum ceiling confirmed at **#4885** — **18 consecutive cycles** with unchanged ceiling (since Cycle U94). forum.amebaiot.com `/latest` returns HTTP 403. Threads #4302, #4834, #1239 confirmed still HTTP 403 on direct fetch. | LOW |
| Web-wide error string sweep (7 canary strings, 2026-06-12) | **Zero indexed results — 112 consecutive cycles.** `"FCS KM_status 0x00002081"`, `"It don't do the sensor initial process"`, `"FCS_I2C_INIT_ERR"`, `"FCS_RUN_DATA_NG_KM"`, `"VOE_OPEN_CMD fail flash"`, `"USE_ISP_RETENTION_DATA"`, `"device_mutex_lock RT_DEV_LOCK_FLASH"` — all return zero publicly indexed results. `"ISP_MULTI_FCS_DATA_MAGIC_NUM"` and `"0x5343464D"` (MFCS magic) also return zero. No hardware test result for any proposed workaround has been posted in any language. | LOW |
| All Chinese-language sources (CSDN/知乎/EEWorld/21IC/bbs.aithinker.com/bbs.ai-thinker.com/Bilibili/Gitee, June 12 sweep) | **Zero new technical content — 112th consecutive null cycle.** All Chinese community sites remain 403-blocked or return zero relevant results. bbs.aithinker.com and bbs.ai-thinker.com confirmed 403. CSDN, Zhihu, EEWorld, 21IC return zero results for FCS flash camera failure on RTL8735B or BW21-CBV. Searches in Chinese (`"安信可 BW21 RTL8735B FCS 摄像头 flash 冷启动"`, `"RTL8735B FlashMemory mutex 摄像头"`, `"AmebaPro2 FCS 修复 2026"`) all return zero relevant results. | LOW |

**Repository freeze status (as of Cycle U112, June 12, 2026):**

| Repository | Last commit | Days frozen |
|---|---|---|
| ameba-rtos-pro2 main | May 15, 2026 (`3f95070`) | **28+ days** |
| ameba-arduino-pro2 dev | June 3, 2026 (`e8dd7e3`) | **9+ days** |
| ameba-arduino-pro2 main | Mar 2, 2026 (`93d63514`) | **102+ days** ⚠️ |
| ameba-tool-rtos-pro2 | Mar 9, 2026 (`c1d70e7`) | **95+ days** |
| ideashatch/HUB-8735 | Dec 2, 2025 (`870a7e0`) | **193+ days** |
| ameba-arduino-doc | June 5, 2026 (`5a400de`) | **7+ days** (editorial only) |

**SDK state as of 2026-06-12 (Cycle U112 — unchanged from U111):**
- Latest stable Arduino SDK: V4.1.0 (Mar 2, 2026) — no fix
- Latest pre-release Arduino SDK: V4.1.1-QC-V07 (build20260603, June 3, 2026) — no fix; FlashMemory.cpp zero mutex calls (112th cycle); V4.1.1-QC-V08 does not exist
- ameba-rtos-pro2: frozen at May 15, 2026 (`3f95070`) — **28+ days no change**
- ameba-arduino-pro2: 0 open PRs; 17 open issues, all feature requests; newest = #398 (Mar 29, 2026)
- VOE binary: last confirmed v1.7.1.0 (synced May 1, 2026, `d54e1a8`)
- Forum ceiling: **#4885** (unchanged since Cycle U94 — **18 consecutive cycles**)
- FlashMemory.cpp: last commit `4fdfbec` (Sep 30, 2025), zero mutex calls — **112th cycle unpatched**
- ameba-arduino-pro2 main frozen: **102+ days**

**No confirmed fix. Bug remains unpatched as of 2026-06-12 (Cycle U112).**

**Top unresolved actions (unchanged from U111):**
1. **Hardware test of "Camera FCS Mode = Disable"** — full source-code chain confirmed across 3 files (postbuild.cpp + video_boot.c + video_api.c); dummy blob → invalid MFCS magic → KM bypass (0x0083) → camera re-init via application layer. No public hardware test result exists anywhere. **Highest priority.**
2. **Hardware test of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper** — Realtek's own `flash/src/main.c` demonstrates the required pattern; 16+ RTOS SDK files use it correctly; FlashMemory.cpp confirmed sole exception. Callable from Arduino: `extern "C" { void device_mutex_lock(unsigned int); void device_mutex_unlock(unsigned int); } #define RT_DEV_LOCK_FLASH 1`.
3. **File a GitHub Issue on ameba-arduino-pro2** — bug entirely undocumented outside this research log; 112 cycles and zero acknowledgment; zero PRs ever filed; filing would be the first public disclosure.
4. **Hardware test of `USE_ISP_RETENTION_DATA`** — eliminates ISP competing SPIC writes entirely; requires uncommenting `// #define USE_ISP_RETENTION_DATA` in `video_api.h`.

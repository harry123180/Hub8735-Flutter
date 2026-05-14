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

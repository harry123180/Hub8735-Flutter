# RTL8735B FCS Flash Bug — Research Supplement 2026-05-13 (Cycle U3)

This supplement covers the 6-hour research cycle completed 2026-05-13 (third cycle of the day).
Findings are numbered 116–121 continuing from the previous confirmed highest (Finding 116 in
FLASH_RESEARCH_SUPPLEMENT_20260512_U3.md).

**HIGH priority finding this cycle: KM error codes fully decoded from SDK header file.**

---

## Finding 116 — KM Status & Error Codes Decoded from rtl8735b_voe_status.h

**Source:** `ameba-rtos-pro2` — `component/soc/8735b/fwlib/rtl8735b/lib/source/ram/video/rtl8735b_voe_status.h`  
https://raw.githubusercontent.com/Ameba-AIoT/ameba-rtos-pro2/main/component/soc/8735b/fwlib/rtl8735b/lib/source/ram/video/rtl8735b_voe_status.h  
**Priority:** HIGH — First definitive decoding of the exact boot ROM error codes from the bug report

The exact error codes printed by boot ROM are now definitively decoded:

```
KM_status 0x00002081  →  FCS_RUN_DATA_NG_KM
err       0x0000200a  →  FCS_I2C_INIT_ERR
```

### Full FCS KM State Machine Constants

```c
FCS_INIT_ROM_RDY_KM   = 0x0080  // KM ROM ready
FCS_WAIT_SNR_CLK_KM   = 0x0081  // KM waiting for sensor clock
FCS_RUN_DATA_OK_KM    = 0x0082  // FCS ran successfully (normal working boot)
FCS_BYPASS_WHILE1_KM  = 0x0083  // FCS bypassed — KM stuck in while(1)
FCS_RUN_DATA_NG_KM    = 0x2081  // FCS ran, data NG (our bug's KM_status)
```

**Normal working boot** (from GitHub issue #251 reference): `KM_status 0x00000082` = `FCS_RUN_DATA_OK_KM`.
**Bug state**: `KM_status 0x00002081` = `FCS_RUN_DATA_NG_KM` (0x2000 error-flag OR'd with 0x0081).

### Full FCS KM-side Error Codes

```c
KM_ERROR             = 0x2000  // base KM error flag
FCS_CMD_INVALID_ERR  = 0x2006
FCS_ERR_CMDID        = 0x2007
FCS_SNR_CLK_TYPE_ERR = 0x2008
FCS_GPIO_INIT_ERR    = 0x2009
FCS_I2C_INIT_ERR     = 0x200A  // ← our bug's err code
FCS_ADC_INIT_ERR     = 0x200B
```

### TM-side Error Codes (for completeness)

```c
FCS_WAIT_KM_TMOUT_ERR = 0x1009  // TM timed out waiting for KM
FCS_KM_PROC_NK        = 0x1207
FCS_KM_PROC_NG        = 0x1208
FCS_KM_PROC_BYPASS    = 0x1209
```

### KM Hardware Register Addresses

```c
KM_STATUS        = 0x40492004  // read KM status (check against FCS_RUN_DATA_OK_KM)
KM_FCS_ERROR_REG = 0x40492008  // read KM FCS error code
TM_STATUS        = 0x40009154  // TM status register
```

### Interpretation of the Bug's Error Path

The KM co-processor executes this sequence during FCS cold boot:
1. KM ROM ready → `FCS_INIT_ROM_RDY_KM` (0x0080)
2. KM reads `fcs_data_<sensor>.bin` from NOR flash (fcsdata partition at 0x8000) and/or runtime
   AE/AWB data from `NOR_FLASH_FCS` (0xF0D000)
3. KM initializes I2C to configure the camera sensor using parameters from step 2
4. **On a cold boot following FlashMemory.write():** step 3 fails → `FCS_I2C_INIT_ERR` (0x200A)
5. KM sets status → `FCS_RUN_DATA_NG_KM` (0x2081)
6. Boot ROM sees KM_status ≠ `FCS_RUN_DATA_OK_KM` → prints "It don't do the sensor initial process"
7. Camera sensor is NOT initialized at boot ROM level; VOE layer then fails to find a running sensor

**Why I2C init fails after flash writes (most likely mechanism):** The FCS data stored at
0xF0D000 (written by `video_pre_init_save_cur_params()` during the previous session) contains
the I2C configuration sequence for the sensor. If a concurrent or preceding `FlashMemory.write()`
or sector erase leaves the SPI flash in a busy (WIP=1) state or partially overwrites the FCS
data area, the KM reads corrupted or incomplete I2C configuration → I2C initialization fails.

*Caveat:* This file was fetched by an automated research agent. The exact symbol names and
values should be verified by manually fetching the URL above.

---

## Finding 117 — FCS_BYPASS_WHILE1_KM Explains the "slot full" Deadlock (Mild Case)

**Source:** `rtl8735b_voe_status.h` (same as Finding 116)  
**Priority:** MEDIUM — Connects the mild symptom to a distinct KM state

The `[VOE][WARN]slot full` deadlock (observed with 70× `flash_write_word`, no erase) likely
corresponds to `FCS_BYPASS_WHILE1_KM = 0x0083`. This state means the KM co-processor entered a
`while(1)` bypass loop instead of completing FCS initialization.

**Severity ladder now mapped to KM states:**

| Flash operations | Symptom | KM state |
|---|---|---|
| 0 writes | Boot OK | `FCS_RUN_DATA_OK_KM` (0x0082) |
| 1× write\_word | Boot OK | `FCS_RUN_DATA_OK_KM` (0x0082) |
| 70× write\_word | `[VOE][WARN]slot full` deadlock | Likely `FCS_BYPASS_WHILE1_KM` (0x0083) |
| Any sector erase | `VOE_OPEN_CMD fail` + `hal_video_open fail` | `FCS_RUN_DATA_NG_KM` (0x2081) + `FCS_I2C_INIT_ERR` (0x200A) |

The "slot full" case (KM partially initializes but ends up in while(1) bypass) may mean the KM
received partially valid FCS data — enough to pass the initial header check but insufficient to
complete I2C init — so it bypasses rather than errors out completely.

---

## Finding 118 — VOE Version History: 1.5.6.0 "Reinit GPIO in FCS mode"; 1.6.8.0 "Fix share buffer cache"

**Source:** `hal_video_release_note.txt` (ameba-rtos-pro2 main, SHA `d54e1a8`)  
https://raw.githubusercontent.com/Ameba-AIoT/ameba-rtos-pro2/main/component/soc/8735b/fwlib/rtl8735b/lib/source/ram/video/hal_video_release_note.txt  
**Priority:** LOW — Two previously unrecorded VOE versions; neither addresses the flash mutex race

Two VOE versions not previously documented in research logs:

| VOE Version | Date | Fix |
|---|---|---|
| **1.6.8.0** | Dec 2, 2025 | "Fix hal_video.c share buffer cache issue" |
| **1.5.6.0** | Jul 17, 2024 | **"Reinit GPIO in FCS mode"** |

`1.5.6.0` "Reinit GPIO in FCS mode" is noteworthy: Realtek previously acknowledged that FCS mode
requires explicit GPIO re-initialization, implying the FCS path has known hardware initialization
sensitivities. However, this fix addresses GPIO (not I2C or flash timing), and was shipped in
mid-2024 — predating the FlashMemory library introduction in V4.0.8. It does NOT address the
FCS I2C init failure caused by concurrent flash SPI operations.

Complete FCS-related VOE history (all versions, oldest→newest):

| Version | Fix |
|---|---|
| 1.4.3.1 | "terminating FCS flow weak func and example code" |
| 1.4.7.0 | "HDR sensor FCS fail issue" fix |
| 1.5.0.0 | "FCS NV12+RGB" capability |
| 1.5.1.0 | "FCS RGB stream drop frame" support |
| **1.5.6.0** | **"Reinit GPIO in FCS mode"** |
| 1.7.1.0 | "Fix dual sensor id FCS mirror/flip issue" |

**None of these fix FCS I2C init failure caused by flash write operations.**

---

## Finding 119 — hal_video_common.h: fcs Field Confirms Two Boot Paths

**Source:** `ameba-rtos-pro2` — `hal_video_common.h`  
https://raw.githubusercontent.com/Ameba-AIoT/ameba-rtos-pro2/main/component/soc/8735b/fwlib/rtl8735b/lib/source/ram/video/hal_video_common.h  
**Priority:** MEDIUM — Confirms the two boot paths and what happens when FCS fails

The `commandLine_s` structure's `fcs` field is documented as:

> **"1: fcs flow ROM load sensor, 0: normal flow need init. sensor"**

This confirms:
- When `fcs = 1`: Boot ROM loads sensor configuration via FCS (KM co-processor)
- When `fcs = 0`: Normal flow requires explicit sensor initialization

The boot ROM message "It don't do the sensor initial process" indicates the boot ROM detected
`fcs = 1` (FCS mode enabled) but FCS failed → it does NOT fall back to `fcs = 0` (normal init).
The camera sensor is left completely uninitialized.

**Implication for application workaround:** If the application could detect
`KM_STATUS (0x40492004) == FCS_RUN_DATA_NG_KM (0x2081)` at startup and explicitly call the
sensor initialization sequence that FCS would have performed, the camera might still open
successfully. This is speculative — the sensor init API may not be exposed at the Arduino layer —
but the register address is now known.

---

## Finding 120 — SPI NOR Flash WIP-Bit Boot Failure: Cross-Platform Precedent (Zephyr #51713)

**Source:** https://github.com/zephyrproject-rtos/zephyr/issues/51713  
**Priority:** MEDIUM — Confirms the flash-busy-at-boot mechanism is a known cross-platform failure class

Zephyr project issue #51713 documents the same fundamental failure pattern:

> When a page-program or erase operation is in progress and the system cold-boots, the flash
> chip does not respond to JEDEC identification commands (returns 0x00 0x00 0x00) because SPI
> NOR flash chips do not decode most instructions while the WIP (Write In Progress) bit is set.

**Application to the RTL8735B bug:**

If `FlashMemory.write()` or `flash_stream_write()` is called in an application, the SPI NOR
flash enters a page-program or erase cycle. If the device is then power-cycled while the WIP bit
is still set (or shortly afterward — some flash chips hold the SPI interface in a degraded state
for a window after WIP clears), the boot ROM's first flash read (JEDEC ID, then FCS data at
0x8000 / 0xF0D000) may receive corrupted data.

However, the RTL8735B bug persists even on the NEXT cold boot (not just the immediately
following one), which suggests data corruption at 0xF0D000 is the more likely mechanism than
WIP timing — unless the partial write itself permanently alters data adjacent to the FCS region.

**Cross-platform significance:** Flash WIP-induced boot failure is a known hardware class, not a
quirk unique to Realtek. Properly written embedded flash drivers always poll WIP to 0 before
releasing the SPI bus. If `FlashMemory.cpp` releases the SPI bus while WIP is still asserted
(possible if it lacks a final WIP poll after page program), the next SPI master (boot ROM's KM)
could be confused.

---

## Finding 121 — V4.1.1 Pre-Release Series: QC-V03 (Apr 2) and QC-V04 (Apr 17) Documented; No FCS Fix

**Source:** https://github.com/Ameba-AIoT/ameba-arduino-pro2/releases  
**Priority:** LOW — Release catalog update; confirms no V4.1.1 stable release; no FCS/flash fix in any pre-release

Four V4.1.1 pre-release tags exist (all 404 for V4.1.1 stable):

| Tag | Date | Notable Changes |
|---|---|---|
| V4.1.1-QC-V05 | Mar 6, 2026 | Battery camera POC, audio trigger, video zoom, TFLite, AMB82-zero, K306P sensor |
| V4.1.1-QC-V04 | Apr 2, 2026 | "Update tools" — no camera/FCS/flash changes noted |
| **V4.1.1-QC-V03** | **Apr 17, 2026** | **"Update PowerMode examples and API to support multiple wakeup sources"** |
| V4.1.1-QC-V06 | — | **HTTP 404 — does not exist** |
| V4.1.1-QC-V07 | — | **HTTP 404 — does not exist** |

(Tag ordering is inverted: QC-V05 is the oldest tag, QC-V03 is the most recent.)

**No changelog**: There is no `CHANGELOG.md` in the dev branch (HTTP 404).

**No FCS or FlashMemory fix in any V4.1.1 pre-release.** The bug remains unaddressed across all
four pre-release milestones between March and April 2026. No V4.1.1 stable release exists.

---

## Status Confirmation (Cycle U3, 2026-05-13)

| Repository / Source | Status |
|---|---|
| ameba-arduino-pro2 (dev) | Last commit: `13961cc` May 5, 2026 — **no new commits** |
| ameba-rtos-pro2 (main) | Last commit: `1c1c8b7` May 1, 2026 — **no new commits** |
| ameba-arduino-pro2 releases | Latest stable: V4.1.0; latest pre-release: V4.1.1-QC-V03 (Apr 17) — **no new releases** |
| ameba-arduino-pro2 issues | Highest: #398 (Mar 2026) — **no new issues** |
| ameba-rtos-pro2 issues | Highest: #16 (Jan 2026) — **no new issues** |
| ideashatch/HUB-8735 issues | Highest: #10 (Aug 2025) — **no new issues** |
| forum.amebaiot.com | Threads #4841–#4845 = **HTTP 403** (exist but inaccessible) |
| FlashMemory.cpp (dev) | **No mutex guards added** |
| video_api.c (main) | **No mutex guards at ftl_common_write() call sites** |
| Chinese-language sources | **Zero new FCS/flash/camera bug articles** |
| Public `"FCS KM_status 0x00002081"` | **Zero indexed results** |

**Bug status: Publicly undocumented and unpatched as of 2026-05-13 cycle U3.**

---

## Sources Added (Cycle U3, 2026-05-13)

- rtl8735b_voe_status.h (KM/TM FCS error codes + hardware registers): https://raw.githubusercontent.com/Ameba-AIoT/ameba-rtos-pro2/main/component/soc/8735b/fwlib/rtl8735b/lib/source/ram/video/rtl8735b_voe_status.h
- hal_video_common.h (fcs field "1: fcs flow ROM load sensor, 0: normal flow"): https://raw.githubusercontent.com/Ameba-AIoT/ameba-rtos-pro2/main/component/soc/8735b/fwlib/rtl8735b/lib/source/ram/video/hal_video_common.h
- hal_video_release_note.txt (VOE 1.5.6.0 "Reinit GPIO in FCS mode"; 1.6.8.0 share buffer cache fix): https://raw.githubusercontent.com/Ameba-AIoT/ameba-rtos-pro2/main/component/soc/8735b/fwlib/rtl8735b/lib/source/ram/video/hal_video_release_note.txt
- ameba-arduino-pro2 releases (V4.1.1-QC-V03 Apr 17, V4.1.1-QC-V04 Apr 2 documented; no FCS fix): https://github.com/Ameba-AIoT/ameba-arduino-pro2/releases
- Zephyr issue #51713 (SPI NOR WIP-bit boot failure cross-platform precedent): https://github.com/zephyrproject-rtos/zephyr/issues/51713
- forum.amebaiot.com threads #4841–#4845 (HTTP 403; exist but inaccessible): https://forum.amebaiot.com/

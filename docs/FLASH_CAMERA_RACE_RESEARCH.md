# RTL8735B Flash → Camera Boot Race — Research Log

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

---

## Research Update — 2026-04-28

### Finding 1 — SDK Version Where Both Features Were Added Simultaneously
**Source:** https://github.com/Ameba-AIoT/ameba-arduino-pro2/releases/tag/V4.0.8  
**Priority:** HIGH — Points directly at the bug introduction window

SDK **v4.0.8 (October 29, 2024)** added BOTH features in the same release:
- `"Add feature Flash Memory"` — the Arduino `FlashMemory.write/writeWord/flash_stream_write` API
- `"FCS mode support across all compatible sensors"` — camera Fast Cold Start

Tools package **v1.3.11** simultaneously added `"FCS file support"` and `"Multi-sensor build process improvements"`.

This timing is highly suspicious. The FlashMemory API and FCS mode were developed and shipped together with no apparent validation of their interaction. No subsequent release (v4.0.9 Aug 2025, v4.1.0 Mar 2026, v4.1.1 Mar 2026) has an explicit changelog entry fixing a flash/FCS interaction bug.

---

### Finding 2 — FlashMemory Base Address Confirmed: 0xFD0000
**Source:** GitHub raw: `ameba-arduino-pro2/dev/.../FlashMemory.h` (fetched directly)  
**Priority:** HIGH — Core address needed to understand overlap

Key constants extracted from `FlashMemory.h`:
```c
#define NOR_FLASH_SIZE          0x1000000   // 16 MB total flash
#define FLASH_MEMORY_APP_BASE   0xFD0000    // User FlashMemory area starts here
#define FLASH_SECTOR_SIZE       0x1000      // 4 KB per sector
// MAX_FLASH_MEMORY_APP_SIZE = 0x1000000 - 0xFD0000 = 0x30000 (192 KB)
```

The `FlashMemory` API occupies flash offsets **0xFD0000 – 0xFFFFFF** (48 sectors, 192 KB).

The `write()` method **erases all sectors in this range then rewrites**. The `writeWord()` method has a fallback: on write failure, it reads-erases-rewrites the full sector (4 KB).

**No FCS or camera region avoidance code is present in FlashMemory.cpp.**

---

### Finding 3 — FCS Saves AE/AWB Camera Parameters TO FLASH
**Source:** https://ameba-doc-rtos-pro2-sdk.readthedocs-hosted.com/en/latest/application_note/15_ISP.html (search extract)  
**Priority:** HIGH — Explains the mechanism of how flash writes corrupt FCS

The AmebaPro2 FCS mechanism uses `CMD_VIDEO_PRE_INIT_LOAD` with three storage modes:
- `SAVE_TO_STRUCTURE` — load AE/AWB from RAM structure
- **`SAVE_TO_FLASH`** — load video initial AE/AWB settings from flash ← **FCS mode uses this**
- `SAVE_TO_RETENTION` — load from SRAM retention

The documentation states: **"For FCS mode, it will automatically load video initial parameters from flash and retention."**

This means the FCS mechanism writes camera calibration parameters (AE, AWB) into a specific flash sector during operation. On the **next cold boot**, the boot ROM reads those parameters from flash to fast-initialize the sensor. If that flash sector was erased by a user flash write, the boot ROM finds garbage/blank data, the KM (Key Management) verification fails (`KM_status 0x00002081 err 0x0000200a`), and the boot ROM prints `"It don't do the sensor initial process"`.

**This is the most plausible root cause**: the FCS parameter sector and the FlashMemory user area likely overlap or are adjacently managed, and erasing the FlashMemory area destroys the FCS-saved camera state.

---

### Finding 4 — VOE Flash Location: 0x807e080 (Offset 0x7e080)
**Source:** GitHub Issue #251 boot log, ameba-arduino-pro2 repo  
**Priority:** MEDIUM — Establishes where the VOE binary lives (separate from FCS parameters)

The VOE binary itself (not the FCS parameter data) is at:
- Memory-mapped address: `0x807e080`
- Flash physical offset: `0x7e080` (~494 KB from flash start, within the boot region before fw1 at 0x100000)

The **VOE binary** is in the low flash area (boot region). However, the **FCS run-time parameter data** (SAVE_TO_FLASH) is likely stored at a separate, higher flash address — possibly within or adjacent to the FlashMemory user area (0xFD0000+).

The exact FCS parameter flash address is not yet confirmed from public sources.

---

### Finding 5 — KM_status Bit Interpretation
**Source:** Boot logs from Issue #251 vs bug report comparison  
**Priority:** MEDIUM — Helps diagnose state at boot

| Field | Normal (working) | Bug state |
|---|---|---|
| `FCS KM_status` | `0x00000082` | `0x00002081` |
| `FCS err` | `0x00000000` | `0x0000200a` |

Bit differences in KM_status:
- Bit 13 (`0x2000`): set in bug state → likely "FCS key/data verification FAILED" flag
- Bit 7 (`0x80`): set in both → likely "KM module present" or "KM loaded" flag
- Bit 1 vs Bit 0: `0x02` (normal) → `0x01` (bug) — possibly "OK" vs "error" mode bit

The `err 0x200a` = `0b 0010 0000 0000 1010`. Without the Realtek datasheet, exact bit definitions are unknown, but it appears to be a compound error code (possibly: bits indicating "checksum mismatch" + "flash read error").

---

### Finding 6 — RTL8735B Security Hardware Features
**Source:** https://aiot.realmcu.com/en/product/rtl8735b.html (search extract)  
**Priority:** MEDIUM — Explains WHY boot ROM does KM verification

The RTL8735B includes:
- Arm TrustZone®
- Secure boot
- Flash XIP (Execute In Place) decryption
- HUK (Hardware Unique Key)
- OTP storage
- Symmetric/asymmetric encryption, TRNG

The "KM" (Key Management) sub-system in the boot ROM verifies FCS data integrity before loading it. If the FCS parameter sector checksum doesn't match the stored KM verification data, boot ROM refuses to initialize the sensor ("It don't do the sensor initial process").

---

### Finding 7 — Subsequent SDK Releases (v4.0.9 → v4.1.1) — No Fix Found
**Source:** https://github.com/Ameba-AIoT/ameba-arduino-pro2/releases/  
**Priority:** MEDIUM — Establishes the bug is likely still present

Release highlights AFTER v4.0.8:

| Version | Date | Relevant changes |
|---|---|---|
| v4.0.9 | Aug 6, 2025 | New sensors (IMX307, GC4653, etc.), GenAI, USB Mass Storage — **no flash/FCS fix mentioned** |
| v4.1.0 | Mar 2, 2026 | SD Card OTA, IPv6, tools 1.4.6 with updated voe.bin — **no flash/FCS fix mentioned** |
| v4.1.1-QC-V04 | Mar 6, 2026 | New sensors (IMX681, OV50A40) — **no flash/FCS fix mentioned** |

The flash-camera interaction bug is likely **still present** in all SDK versions from v4.0.8 through at least v4.1.1 (latest as of this research).

---

### Finding 8 — Confirmed: No Avoidance Code in FlashMemory.cpp
**Source:** GitHub raw fetch of FlashMemory.cpp  
**Priority:** HIGH — Confirms the SDK has no guard against this

The `FlashMemory.cpp` implementation:
1. `write()` — erases ALL sectors in 0xFD0000–0xFFFFFF range, then programs
2. `writeWord()` — fallback erase+rewrite triggers on ANY bit-0-to-1 transition
3. No bounds check against FCS parameter address
4. No warning in API documentation about camera FCS incompatibility

---

## Hypotheses (Ranked by Likelihood)

### Hypothesis A — FCS SAVE_TO_FLASH Data Overlaps FlashMemory Area ★★★★★
The FCS mechanism writes camera AE/AWB parameters to a flash sector at or near 0xFD0000 (FlashMemory base). When `FlashMemory.write()` erases all 48 sectors in that range, it destroys the FCS parameter data. On next cold boot, the boot ROM KM verification fails because the parameter checksum is invalid (all-FFs or zeros).

**Evidence:**
- Sector erase = complete fail (FCS params destroyed)
- Write without erase = mild fail (partial bit disturbance in FCS param cells)
- No writes = OK (FCS params intact)
- v4.0.8 introduced both features simultaneously without conflict testing

**To confirm:** Find the exact flash address used by `SAVE_TO_FLASH` in `video_user_boot.c` or the partition table.

### Hypothesis B — FCS Verification Hash Stored Near FlashMemory Area ★★★★
The boot ROM computes/verifies a hash of the FCS parameter data and stores this hash in a dedicated sector near the FlashMemory area. Erasing the FlashMemory area erases this hash, causing KM verification failure even if the FCS binary itself (at 0x7e080) is intact.

### Hypothesis C — NOR Flash Write-Disturb on FCS Cells ★★
Multiple page programs at 0xFD0000 cause read-disturb on flash cells in a nearby sector containing FCS data. This could explain why 70× writes cause a mild failure. Unlikely to explain the erase-only scenario.

---

## Known Workarounds (Unconfirmed)

1. **Disable Camera FCS mode** — Arduino IDE `Camera FCS mode process = Disable`. This bypasses the fast cold start entirely but increases boot time. Does NOT fix the camera, just falls back to slow boot.

2. **Avoid sector erase** — Use only `writeWord()` with values that only flip 1→0 bits (no erase needed). Unreliable for arbitrary user data.

3. **Change `FLASH_MEMORY_APP_BASE`** — Recompile SDK with a different base address that doesn't conflict with FCS parameters. Requires source SDK access.

4. **Re-trigger FCS parameter save after flash write** — After any FlashMemory operation, call `CMD_VIDEO_PRE_INIT_LOAD` with `SAVE_TO_FLASH` to re-write FCS parameters before next power cycle. Feasibility depends on API availability at user level.

5. **Use software reset instead of power cycle** — The bug only manifests on cold boot. A software reset (no power interruption) may preserve DRAM retention of FCS state. Not viable for real deployment.

---

## Open Questions

1. **What exact flash address does `SAVE_TO_FLASH` use?** — This is the critical unknown. Find in `video_user_boot.c` source or `amebapro2_partitiontable.json`.

2. **Does disabling FCS mode in Arduino IDE actually prevent the bug?** — Needs experimental verification.

3. **Is the FCS parameter address configurable?** — If it can be moved to a non-user area, that fixes the problem without breaking FlashMemory.

4. **Is the bug present in v4.0.7 (before FlashMemory was added)?** — Would confirm v4.0.8 as the introduction point.

5. **Has Realtek been notified?** — No public GitHub issue or forum post directly reporting this specific flash/FCS interaction found.

---

## Sources Referenced

- GitHub ameba-arduino-pro2 issues list: https://github.com/Ameba-AIoT/ameba-arduino-pro2/issues
- Issue #251 (FCS boot log): https://github.com/Ameba-AIoT/ameba-arduino-pro2/issues/251
- Release v4.0.8: https://github.com/Ameba-AIoT/ameba-arduino-pro2/releases/tag/V4.0.8
- Releases page: https://github.com/Ameba-AIoT/ameba-arduino-pro2/releases/
- AmebaPro2 ISP docs: https://ameba-doc-rtos-pro2-sdk.readthedocs-hosted.com/en/latest/application_note/15_ISP.html
- AmebaPro2 Flash Layout: https://ameba-doc-rtos-pro2-sdk.readthedocs-hosted.com/en/latest/application_note/08_FLASHLAYOUT.html
- AmebaPro2 MMF Architecture: https://ameba-doc-rtos-pro2-sdk.readthedocs-hosted.com/en/latest/application_note/06_MMF.html
- RTL8735B product page: https://aiot.realmcu.com/en/product/rtl8735b.html
- Forum: Sensor fail on AMB82 Mini: https://forum.amebaiot.com/t/sensor-fail-on-amb82-mini/3429
- Forum: Boot failure after OTA: https://forum.amebaiot.com/t/boot-failure-after-ota-update/4834
- Forum: VOE frame_end sensor not init: https://forum.amebaiot.com/t/voe-frame-end-sensor-didnt-initialize-done/4302
- BW21-CBV Ai-Thinker forum: https://bbs.ai-thinker.com/forum.php?mod=viewthread&tid=46140
- Flash Memory API docs: https://www.amebaiot.com/en/ameba-arduino-flash/
- Flash Write Word example: https://www.amebaiot.com/en/amebapro2-arduino-flash-writeword/

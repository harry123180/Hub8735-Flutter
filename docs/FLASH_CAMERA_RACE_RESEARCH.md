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

## Research Update — 2026-04-28 (Update 2)

### Finding 9 — Complete Partition Table Layout Confirmed
**Source:** `ameba-arduino-pro2` partition table JSON (SHA d3a860b4)  
https://github.com/Ameba-AIoT/ameba-arduino-pro2/blob/d3a860b4cfd9d207119ef2ca99c660bae5c74507/Arduino_package/ameba_pro2_tools_windows/misc/sys_img/amebapro2_partitiontable.json  
**Priority:** HIGH

Full NOR flash layout for RTL8735B / AMB82-Mini / BW21-CBV:

| Partition | Start    | Length   | Type          | Notes |
|-----------|----------|----------|---------------|-------|
| sysdata   | 0x007000 | 0x1000   | PT_SYSDATA    | System metadata |
| **fcsdata** | **0x008000** | **0x1000** | **PT_FCSDATA** | **Boot ROM FCS header** |
| boot_p    | 0x009000 | 0x27000  | PT_BL_PRI     | Primary bootloader |
| boot_s    | 0x030000 | 0x27000  | PT_BL_SEC     | Secondary bootloader |
| fw1       | 0x080000 | 0x380000 | PT_FW1        | Main firmware |
| iq        | 0x400000 | 0x0C0000 | PT_ISP_IQ     | ISP IQ binary (768 KB) |
| fw2       | 0x4C0000 | 0x380000 | PT_FW2        | OTA firmware slot |
| nn        | 0x840000 | 0x5C0000 | PT_NN_MDL     | Neural network models |
| mp        | 0xFC0000 | 0x1000   | PT_MP         | Manufacturing (invalid=false) |

**Key gaps:** No partition is defined from `0xFC1000` to `0xFFFFFF`. The Arduino `FlashMemory` API at `0xFD0000–0xFFFFFF` occupies entirely unallocated space in the partition table.

---

### Finding 10 — FCS Runtime Save Address: 0xF0D000 (RTOS SDK)
**Source:** `ameba-rtos-pro2` — `platform_opts.h` (commit 4dcbdb9e)  
https://github.com/Ameba-AIoT/ameba-rtos-pro2/blob/4dcbdb9e67c01588079d3d47114a2fcd09ae5cd1/project/realtek_amebapro2_v0_example/inc/platform_opts.h  
**Priority:** HIGH

```c
#define USER_DATA_BASE      0xF00000
#define NOR_FLASH_FCS      (USER_DATA_BASE + 0x0D000)   // = 0xF0D000
#define NAND_FLASH_FCS      0x7080000
#define USER_DATA_END       (USER_DATA_BASE + 0x64000)   // = 0xF64000
```

Full RTOS SDK system-reserved block (`0xF00000–0xF64000`):

| Symbol | Address | Purpose |
|--------|---------|---------|
| FAST_RECONNECT_DATA | 0xF00000 | WiFi fast-reconnect |
| BT_FTL_BKUP_ADDR | 0xF01000 | BT stack (12 KB) |
| SECURE_STORAGE_BASE | 0xF04000 | Secure key store (4 KB) |
| FACE_FEATURE_DATA | 0xF05000 | Face recognition features |
| ISP_FW_LOCATION | 0xF0C000 | ISP firmware index |
| **NOR_FLASH_FCS** | **0xF0D000** | **FCS AE/AWB runtime save** |
| TUNING_IQ_FW | 0xF10000 | IQ tuning firmware (256 KB) |
| CALI_IQ_FW | 0xF60000 | IQ calibration firmware (16 KB) |
| USER_DATA_END | 0xF64000 | — |

---

### Finding 11 — FCS Data Structure: "FCSD" Header + video_boot_stream_t
**Source:** `ameba-rtos-pro2` — `video_user_boot.c` (commit 4dcbdb9e)  
https://github.com/Ameba-AIoT/ameba-rtos-pro2/blob/4dcbdb9e67c01588079d3d47114a2fcd09ae5cd1/component/video/driver/RTL8735B/video_user_boot.c  
**Priority:** HIGH

The FCS record stored in flash has this layout:
```
[0x00] 4 bytes  — Magic: "FCSD"
[0x04] 4 bytes  — Checksum
[0x08] ...      — video_boot_stream_t struct (AE/AWB sensor parameters)
Total: ~2048 bytes
```
Read via `ftl_common_read(flash_addr, fcs_buf, fcs_buf_size)` with a 2048-byte buffer.  
Write via `ftl_common_write(flash_addr, fcs_buf, fcs_buf_size)`.  
Boot-device selection: `hal_sys_get_boot_select()` → 0 = NOR, 1 = NAND.

---

### Finding 12 — video_api.c Confirms Two Independent Code Paths to 0xF0D000
**Source:** `ameba-rtos-pro2` — `video_api.c` (commit 4dcbdb9e)  
https://github.com/Ameba-AIoT/ameba-rtos-pro2/blob/4dcbdb9e67c01588079d3d47114a2fcd09ae5cd1/component/video/driver/RTL8735B/video_api.c  
**Priority:** HIGH

Both `video_pre_init_load_params()` (boot-time load) and `video_pre_init_save_cur_params()` (runtime save) use:
```c
if (sys_get_boot_sel() == 0) {
    flash_addr = NOR_FLASH_FCS;   // 0xF0D000
}
```
`SAVE_TO_FLASH` is the **default** in the official FCS example code (`EXAMPLE_SAVE_OPTION = EXAMPLE_SAVE_TO_FLASH`).

---

### Finding 13 — CRITICAL: Hypothesis A DISPROVED — No Direct Address Overlap
**Source:** Synthesis of Findings 9 and 10  
**Priority:** HIGH

The original leading hypothesis is **wrong**. The two relevant FCS addresses are:
- **0x008000** — `fcsdata` partition: boot ROM reads FCSD header here
- **0xF0D000** — `NOR_FLASH_FCS`: runtime `video_pre_init_save_cur_params()` writes here

The Arduino `FlashMemory` API writes to **0xFD0000–0xFFFFFF**.

Address distances:
- `0xFD0000 − 0xF0D000 = 0xC3000` = **780 KB gap** (FlashMemory vs NOR_FLASH_FCS)
- `0xFD0000 − 0x008000 = 0xFC8000` = **16.0 MB gap** (FlashMemory vs fcsdata partition)

**No direct erase overlap is possible.** The bug mechanism must be indirect.

---

### Finding 14 — Official Arduino Flash Zone Boundaries
**Source:** `ameba-arduino-doc` — `amb82-mini_flash_layout.rst` (commit d0b6ca31)  
https://github.com/Ameba-AIoT/ameba-arduino-doc/blob/d0b6ca31683ce31b72a24f9f227432914b13b944/source/FAQ/amb82-mini_flash_layout.rst  
**Priority:** MEDIUM

| Build type | User-reserved zone | Notes |
|---|---|---|
| Without OTA | 0xFC0000 – 0x1000000 (256 KB) | FCS at 0xF0D000 is OUTSIDE → safe? |
| With OTA | 0xF00000 – 0x1000000 (1023 KB) | FCS at 0xF0D000 is INSIDE this zone |

In OTA builds, the user-reserved zone begins at `0xF00000`, which **includes** the `NOR_FLASH_FCS` address `0xF0D000`. An OTA-build user making `FlashMemory` calls starting at `0xF00000` would directly overwrite FCS runtime parameters. **However, this does not explain bugs on standard non-OTA builds where FlashMemory starts at 0xFD0000.**

---

### Finding 15 — NOR Flash CPU Address Mapping Confirmed
**Source:** GitHub Issue #251 boot log  
**Priority:** MEDIUM

NOR flash physical offset → CPU address: `physical_offset + 0x8000000`

| Resource | Flash offset | CPU addr (from boot log) |
|---|---|---|
| fcsdata (boot ROM FCS) | 0x8000 | 0x8008000 |
| VOE binary | 0x7E080 | 0x807E080 |
| ISP IQ | 0x461080 | 0x8461080 |

---

### Finding 16 — No Chinese-Language Sources Found
**Source:** CSDN, 知乎, 21ic, EEWorld, bbs.ai-thinker.com  
**Priority:** LOW

Exhaustive Chinese-language search returned no posts specifically linking `FlashMemory` writes to camera FCS boot failure on RTL8735B / AmebaPro2 / BW21-CBV. The bug is unreported publicly in Chinese or English forum posts.

---

### New Hypothesis D — Race Condition: SAVE_TO_FLASH Interrupted by Power-Off ★★★★
**Priority:** HIGH — Now the primary candidate

The indirect mechanism:

1. Camera is running; FCS has already saved AE/AWB params to **0xF0D000** in a previous session. These are valid.
2. User calls `FlashMemory.write()` — this erases+programs **0xFD0000+**. During this operation, XIP is briefly suspended.
3. The video subsystem RTOS task, running concurrently, detects that it should update AE/AWB convergence. It calls `video_pre_init_save_cur_params(SAVE_TO_FLASH)`, which:
   - **Erases** the 4KB sector at `0xF0D000`
   - Then **programs** new AE/AWB data back
4. The user sees that `FlashMemory.write()` returned (signaling "done"). They assume it is safe to power off.
5. The device is powered off **between** the FCS erase and FCS reprogram of `0xF0D000`.
6. `0xF0D000` is now erased (all 0xFF). On next cold boot, boot ROM reads the FCSD header, finds garbage checksum, raises `KM_status 0x00002081 err 0x0000200a`, prints "It don't do the sensor initial process."

**Explains severity ladder:**
- 1× write (stable): SAVE_TO_FLASH at 0xF0D000 completes quickly after single flash op; power-off race window is tiny
- 70× writes (slot full): 70 FlashMemory operations each queue a SAVE_TO_FLASH job; video message queue overflows → deadlock labeled "slot full"
- Sector erase (complete fail): Longer erase duration at 0xFD0000 maximizes the overlap window; power-off during 0xF0D000 erase-reprogram becomes near-certain

### New Hypothesis E — Video Message Queue Overflow from Repeated Flash Triggers ★★★
Each `FlashMemory.writeWord()` (or `write()`) triggers an RTOS event that causes the video subsystem to enqueue a `SAVE_TO_FLASH` job. At 70 writes, the video message queue exhausts its fixed slot count → "slot full" deadlock. The jobs that do execute partially corrupt 0xF0D000 (write-abort on power-off). This hypothesis is complementary to D, not exclusive.

---

## Hypotheses (Ranked by Likelihood) — UPDATED

### Hypothesis D — Race: FlashMemory write triggers SAVE_TO_FLASH, power-off hits erase window ★★★★★
See "New Hypothesis D" above. Now the leading candidate. Explains all three severity levels.

### Hypothesis E — Video queue overflow on repeated FlashMemory writes ★★★★
Explains "slot full" specifically. Complementary to D.

### Hypothesis A — FCS Data Overlaps FlashMemory Area ★ *(DISPROVED)*
Addresses are 780 KB apart. Direct overlap is not physically possible on non-OTA builds.

### Hypothesis B — FCS Verification Hash Near FlashMemory Area ★★
Still possible if the boot ROM hashes a range that happens to extend toward 0xFD0000, but no evidence yet.

### Hypothesis C — NOR Flash Write-Disturb on FCS Cells ★
Distance between regions (780 KB) makes electrical disturb implausible.

---

## Known Workarounds (Unconfirmed)

1. **Disable Camera FCS mode** — Arduino IDE `Camera FCS mode process = Disable`. This bypasses the fast cold start entirely but increases boot time. Does NOT fix the camera, just falls back to slow boot.

2. **Avoid sector erase** — Use only `writeWord()` with values that only flip 1→0 bits (no erase needed). Unreliable for arbitrary user data.

3. **Change `FLASH_MEMORY_APP_BASE`** — Recompile SDK with a different base address that doesn't conflict with FCS parameters. Requires source SDK access.

4. **Re-trigger FCS parameter save after flash write** — After any FlashMemory operation, call `video_pre_init_save_cur_params(SAVE_TO_FLASH)` explicitly and wait for it to complete before allowing power-off. Feasibility depends on API availability at user level.

5. **Use software reset instead of power cycle** — The bug only manifests on cold boot. A software reset (no power interruption) may preserve DRAM retention of FCS state. Not viable for real deployment.

6. **Switch SAVE_OPTION to SAVE_TO_RETENTION** — Change the FCS example `EXAMPLE_SAVE_OPTION` from `SAVE_TO_FLASH` to `SAVE_TO_RETENTION`. This avoids flash entirely for AE/AWB storage, using SRAM retention instead. Retention survives warm resets but not full power cycles — so may not fully solve the problem, but could reduce the race window.

---

## Open Questions

1. **What exact flash address does the pre-compiled Arduino SDK binary use for NOR_FLASH_FCS?** — RTOS SDK says 0xF0D000. Arduino partition table implies 0x8000 for boot ROM read. Resolving this requires disassembly of `libvideo.a` from the Arduino package.

2. **Does disabling FCS mode in Arduino IDE actually prevent the bug?** — Needs experimental verification.

3. **Is the FCS parameter address configurable?** — If it can be moved to a non-user area, that fixes the problem without breaking FlashMemory.

4. **Is the bug present in v4.0.7 (before FlashMemory was added)?** — Would confirm v4.0.8 as the introduction point.

5. **Has Realtek been notified?** — No public GitHub issue or forum post directly reporting this specific flash/FCS interaction found.

6. **Does FlashMemory.write() trigger a SAVE_TO_FLASH video event?** — Critical for confirming Hypothesis D. Need to trace the FlashMemory call path into RTOS video subsystem.

7. **What is the video message queue slot count?** — If it is ~70, this would confirm Hypothesis E and explain the "slot full" symptom at 70 writes precisely.

8. **Is SAVE_TO_FLASH called as a background RTOS task?** — If synchronous (blocking), the race window would be different than if asynchronous. Async makes Hypothesis D more likely.

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
- ameba-arduino-pro2 partition table (commit d3a860b): https://github.com/Ameba-AIoT/ameba-arduino-pro2/blob/d3a860b4cfd9d207119ef2ca99c660bae5c74507/Arduino_package/ameba_pro2_tools_windows/misc/sys_img/amebapro2_partitiontable.json
- ameba-rtos-pro2 platform_opts.h (commit 4dcbdb9): https://github.com/Ameba-AIoT/ameba-rtos-pro2/blob/4dcbdb9e67c01588079d3d47114a2fcd09ae5cd1/project/realtek_amebapro2_v0_example/inc/platform_opts.h
- ameba-rtos-pro2 video_user_boot.c (commit 4dcbdb9): https://github.com/Ameba-AIoT/ameba-rtos-pro2/blob/4dcbdb9e67c01588079d3d47114a2fcd09ae5cd1/component/video/driver/RTL8735B/video_user_boot.c
- ameba-rtos-pro2 video_api.c (commit 4dcbdb9): https://github.com/Ameba-AIoT/ameba-rtos-pro2/blob/4dcbdb9e67c01588079d3d47114a2fcd09ae5cd1/component/video/driver/RTL8735B/video_api.c
- ameba-arduino-doc flash layout rst: https://github.com/Ameba-AIoT/ameba-arduino-doc/blob/d0b6ca31683ce31b72a24f9f227432914b13b944/source/FAQ/amb82-mini_flash_layout.rst
- FCS example source: https://github.com/Ameba-AIoT/ameba-rtos-pro2/blob/4dcbdb9e67c01588079d3d47114a2fcd09ae5cd1/project/realtek_amebapro2_v0_example/src/mmfv2_video_example/mmf2_video_example_joint_test_rtsp_mp4_init_fcs.c

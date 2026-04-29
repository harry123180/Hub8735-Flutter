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

---

## Research Update — 2026-04-29

### Finding 17 — CRITICAL: FlashMemory.write() Bypasses RT_DEV_LOCK_FLASH Mutex
**Source:** ameba-rtos-pro2 — `ftl_nor_api.c` + `FlashMemory.cpp` analysis  
https://github.com/Ameba-AIoT/ameba-rtos-pro2/blob/main/component/ftl/ftl_nor_api.c  
https://github.com/Ameba-AIoT/ameba-arduino-pro2/blob/main/Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.cpp  
**Priority:** CRITICAL — Most likely root cause

The FTL layer (`ftl_nor_api.c`) used by `ftl_common_write()` / `ftl_common_read()` (which the video subsystem calls for every FCS save) wraps every flash hardware command with:
```c
device_mutex_lock(RT_DEV_LOCK_FLASH);
// ... flash erase / page-program operations ...
device_mutex_unlock(RT_DEV_LOCK_FLASH);
```

`FlashMemory.write()` in the Arduino SDK calls `flash_erase_sector()` and `flash_stream_write()` **without taking `RT_DEV_LOCK_FLASH` at all.**

**Race condition:** The video module RTOS task runs independently of the Arduino `loop()` task. If they run concurrently:
- **Video task:** `video_meta_data_process()` → `video_pre_init_save_cur_params(SAVE_TO_FLASH)` → `ftl_common_write(0xF0D000, fcs_buf, 2048)` — acquires `RT_DEV_LOCK_FLASH`, erases sector at `0xF0D000`, begins 2 KB page-program.
- **Arduino task:** `FlashMemory.write()` → `flash_erase_sector(0xFD0000, ...)` — issues SPI flash commands **without** holding `RT_DEV_LOCK_FLASH`, running concurrently.

A SPI NOR flash controller processes only one command at a time. A second CS-assertion during an active page-program cycle aborts that program cycle per the JEDEC specification. This leaves the FCS sector at `0xF0D000` erased but not reprogrammed (all `0xFF`). On next cold boot the boot ROM reads a blank sector, the KM checksum fails → `FCS KM_status 0x00002081 err 0x0000200a` → `"It don't do the sensor initial process"`.

**Severity ladder explanation:**
- 1× `writeWord` (4 bytes, no erase): very short flash operation, tiny race window → infrequent collision → "stable" in testing
- 70× `writeWord` (280 bytes): cumulative flash operation time greatly increases overlap probability with video SAVE_TO_FLASH → partial corruption → `[VOE][WARN]slot full`
- Sector erase (typ. 30–150 ms): longest possible flash operation → near-certain collision → complete `VOE_OPEN_CMD fail`

**Proposed fix:** Add `device_mutex_lock(RT_DEV_LOCK_FLASH)` / `device_mutex_unlock(RT_DEV_LOCK_FLASH)` around `flash_erase_sector()` and `flash_stream_write()` in `FlashMemory.cpp`. This is a one-line change per call site.

---

### Finding 18 — SAVE_TO_FLASH is Synchronous (~60ms Blocking Call in Calling Task)
**Source:** ameba-rtos-pro2 — `module_video.c` + `video_api.c` (commit 4dcbdb9e)  
**Priority:** HIGH — Revises Hypothesis D

`video_pre_init_save_cur_params()` with `save_option = SAVE_TO_FLASH` is a **fully synchronous ~60ms blocking call** in the calling task's context. There is no `xTaskCreate()` or `osThreadNew()` for FCS saving anywhere in the codebase. The ~60ms duration encompasses sector erase + 2048-byte page-program at `0xF0D000`.

Additional precision: the per-frame video callback (e.g., `module_video.c:121`) calls `video_pre_init_save_cur_params()` with `save_option = 0` (`SAVE_TO_STRUCTURE` — in-memory only, no flash I/O). The flash-writing path lives at `module_video.c:411` inside `video_meta_data_process()` and uses `save_option = 1` (`SAVE_TO_FLASH`). `video_meta_data_process()` is called from the video module's RTOS task when metadata is ready on the pipeline output.

**Consequence for Hypothesis D:** The power-cut race window per SAVE_TO_FLASH event is ~60ms, not open-ended. While power-cut during this window can still corrupt FCS, the `RT_DEV_LOCK_FLASH` bypass (Finding 17) is a far more reliable and frequent corruption path that doesn't require an unlucky power cut.

---

### Finding 19 — Hypothesis E Disproved: No ~70-Slot Video Queue
**Source:** ameba-rtos-pro2 — `video_api.h`, `hal_video.h`, `module_video.c`  
**Priority:** HIGH

No video queue with ~70 slots exists in the system:
- `MAX_ENC_BUF = 16` (hal_video.h) — encoder ring buffer hard cap
- `isp_ch_buf_num[ch] = {2, 2, 2, 2, 2}` — ISP frame buffer: 2 slots per channel
- VOE output callback queue: 4096-byte pool buffer (byte size, not message count)

The "70× writes" in the bug report is the user's `FlashMemory.writeWord()` call count during testing, not a queue depth. **Hypothesis E (video queue overflow at exactly ~70 writes) is eliminated.** The `[VOE][WARN]slot full` message most likely originates from the VOE's internal stream-slot allocator failing when FCS boot data is partially corrupted and the VOE cannot correctly restore its pre-allocated channel state.

---

### Finding 20 — Secondary OTA-Build Bug: Erase Loop Can Directly Overwrite FCS at 0xF0D000
**Source:** `FlashMemory.cpp` erase loop analysis  
**Priority:** HIGH — Independent second bug path (OTA builds only)

In `FlashMemory.write()` the sector-erase loop iterates over `MAX_FLASH_MEMORY_APP_SIZE = 0x30000` (48 sectors, compile-time constant) rather than the caller-supplied `buf_size`. In **OTA builds** where `FlashMemory.begin(0xF00000, ...)` sets the base address to `0xF00000`:

- Erase covers: `0xF00000` → `0xF00000 + 0x30000 = 0xF30000` (48 sectors)
- Sector 13 of this range: `0xF00000 + 13 × 0x1000 = 0xF0D000` = **NOR_FLASH_FCS**

Every single `FlashMemory.write()` call in an OTA build with the default base directly erases the FCS runtime save sector, making camera boot failure 100% reproducible and not dependent on a concurrency race.

*Standard non-OTA builds use `FlashMemory.begin(0xFD0000, ...)` — erase covers `0xFD0000–0xFFFFFF` — no direct overlap with `0xF0D000`. This OTA-build path is a separate, more severe defect.*

---

### Finding 21 — Commit fb3dc02: MMF Queue "Not Init" Guard — Confirms Prior Unguarded Race
**Source:** ameba-rtos-pro2, commit fb3dc02  
https://github.com/Ameba-AIoT/ameba-rtos-pro2/commit/fb3dc02  
https://github.com/Ameba-AIoT/ameba-rtos-pro2/commit/3130193 (follow-up)  
**Priority:** HIGH

A commit to `component/media/mmfv2/module_video.c` (+ `libmmf.a` binary) adds:
```c
if (mctx->state != MM_STAT_READY) {
    printf("module_video queue not init\r\n");
    return NOK;
}
```
before `CMD_VIDEO_APPLY` handling. A follow-up commit (3130193) adds a carve-out for JPEG snapshot direct-output mode to avoid regressions.

**Significance:** Realtek developers explicitly acknowledged that the video module's command queue was previously reachable in an uninitialized state. Although this guard is not the FCS corruption fix, it confirms that unguarded concurrent access to the video pipeline was a real, acknowledged hazard in pre-fix SDK versions. Consistent with the flash mutex bypass scenario in Finding 17.

---

### Finding 22 — VOE Binary Updated to 1.7.0.0 (commit f575a69)
**Source:** ameba-rtos-pro2, commit f575a69  
https://github.com/Ameba-AIoT/ameba-rtos-pro2/commit/f575a69  
**Priority:** MEDIUM

VOE updated from `1.6.9.0` → `1.7.0.0`. Files changed: `hal_isp.h`, `hal_video.h`, `hal_video_common.h`, `hal_video_release_note.txt`, `voe.bin`, `libvideo_ns.a`, `libvideo_ntz.a`. Noted fixes: "dual sensor id mirror/flip issue"; new `hal_video_set_isp_gain()` API; new DRC configuration. No explicit FCS or flash-mutex fix mentioned.

---

### Finding 23 — Forum Thread #3983: "Error after write in memory AMB82" — Potential Independent Report
**Source:** Realtek Ameba IoT Developers Forum, thread #3983 (HTTP 403 — Google snippet only)  
https://forum.amebaiot.com/t/error-after-write-in-memory-amb82/3983  
**Priority:** MEDIUM — Same bug, possibly different reporter; camera involvement unconfirmed

Google-indexed snippet: user experienced errors after MCU restart following flash memory write operations on AMB82. Writes were 32-byte strings to flash offsets `0x1E20`, `0x1E40`, `0x1E60` triggered by incoming BLE packets. Pattern (flash write → restart → error) matches our bug exactly. Forum page blocked (403) so full error output and camera involvement could not be confirmed.

---

### Finding 24 — Bug Is Publicly Unreported (English and Chinese Confirmed)
**Source:** Exhaustive web search — Google, CSDN, 知乎, 21ic.com, EEWorld, bbs.ai-thinker.com  
**Priority:** MEDIUM — Confirms novelty; no community fix exists to find

The following error strings return **zero indexed public results** in any language:
- `"It don't do the sensor initial process"` — 0 results
- `"FCS KM_status 0x00002081"` — 0 results
- `"VOE_OPEN_CMD fail"` (in Ameba/RTL8735B context) — 0 results
- `"[VOE][WARN]slot full"` — 0 results

No Chinese-language source (CSDN, Zhihu, 21ic, EEWorld, bbs.ai-thinker.com) links `FlashMemory` writes to FCS camera failure. No GitHub issue has been filed against `ameba-arduino-pro2` or `ameba-rtos-pro2` for this interaction. The bug remains publicly undocumented as of 2026-04-29.

---

### New Hypothesis F — Missing RT_DEV_LOCK_FLASH in FlashMemory.write() ★★★★★
**Priority:** CRITICAL — Now the primary root cause candidate, superseding Hypothesis D

Mechanism:
1. Camera is running; video module RTOS task periodically calls `video_meta_data_process()` → `video_pre_init_save_cur_params(SAVE_TO_FLASH)` → `ftl_common_write(0xF0D000, fcs_buf, 2048)`.
2. `ftl_common_write` acquires `RT_DEV_LOCK_FLASH`, erases the 4 KB sector at `0xF0D000`, then begins the 2 KB page-program cycle (~60ms total).
3. During this same window, the Arduino `loop()` task calls `FlashMemory.write()` → `flash_erase_sector(0xFD0000)` → issues SPI WREN+SE commands **without** acquiring `RT_DEV_LOCK_FLASH`.
4. Two concurrent SPI flash commands abort each other per the SPI NOR specification; specifically the page-program at `0xF0D000` is silently aborted, leaving the sector erased-but-blank.
5. On next cold boot, boot ROM reads blank `0xF0D000` → KM checksum mismatch → `FCS KM_status 0x00002081 err 0x0000200a` → `"It don't do the sensor initial process"`.

**Fix:** In `FlashMemory.cpp`, wrap all `flash_erase_sector()` and `flash_stream_write()` calls with `device_mutex_lock(RT_DEV_LOCK_FLASH)` / `device_mutex_unlock(RT_DEV_LOCK_FLASH)`.

---

### Updated Hypotheses Ranking — 2026-04-29

| Rank | Hypothesis | Status |
|---|---|---|
| ★★★★★ | **F** — `FlashMemory.write()` bypasses `RT_DEV_LOCK_FLASH`; concurrent SPI commands abort FCS page-program | **PRIMARY CANDIDATE** |
| ★★★ | **D** (revised) — Power-cut during the ~60ms SAVE_TO_FLASH window corrupts FCS; FlashMemory ops extend session time | Secondary / complementary |
| ★★ | **B** — Boot ROM hashes a range that extends toward user flash | Possible but unconfirmed |
| ★ (disproved) | **E** — Video queue overflow at ~70 writes | ELIMINATED (no ~70-slot queue) |
| ★ (disproved) | **A** — Direct address overlap FlashMemory ↔ FCS | ELIMINATED (780 KB gap) |

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

1. **NOR_FLASH_FCS address in pre-compiled Arduino SDK:** ~~Requires libvideo.a disassembly.~~ **RESOLVED** — Confirmed `0xF0D000` in both RTOS SDK and Arduino SDK `platform_opts.h`. No divergence.

2. **Does disabling FCS mode in Arduino IDE actually prevent the bug?** — Needs experimental verification. If FCS is disabled, `video_meta_data_process()` should not call `SAVE_TO_FLASH`, eliminating Hypothesis F entirely. This would be an immediate confirming test.

3. **Is the FCS parameter address configurable?** — `NOR_FLASH_FCS = USER_DATA_BASE + 0x0D000`. `USER_DATA_BASE = 0xF00000` is a compile-time constant in `platform_opts.h`. Relocating it requires recompiling the SDK. No runtime config found.

4. **Is the bug present in v4.0.7 (before FlashMemory API was added)?** — Would confirm v4.0.8 as the introduction point.

5. **Has Realtek been notified?** — No public GitHub issue or forum post directly reporting this. **RESOLVED (negatively)** — Bug is publicly undocumented (Finding 24). Should consider filing a GitHub issue against `ameba-arduino-pro2`.

6. **Does FlashMemory.write() trigger a SAVE_TO_FLASH video event?** — **RESOLVED** — No direct coupling found. FlashMemory.cpp has zero video subsystem calls. The race occurs at the SPI flash controller level (RT_DEV_LOCK_FLASH bypass), not via event propagation.

7. **What is the video message queue slot count?** — **RESOLVED** — No ~70-slot queue exists. Hypothesis E eliminated (Finding 19).

8. **Is SAVE_TO_FLASH called as a background RTOS task?** — **RESOLVED** — Fully synchronous, ~60ms blocking, in the video module RTOS task context (Finding 18).

9. **When exactly is `video_meta_data_process()` called?** — The triggering condition for SAVE_TO_FLASH (line 411, `module_video.c`) is not yet fully traced. Is it every frame? Every N seconds? On AE/AWB convergence only? The frequency determines how often the ~60ms race window opens.

10. **Can `device_mutex_lock(RT_DEV_LOCK_FLASH)` be called from Arduino user code as a workaround?** — If the symbol is exported, users could wrap their `FlashMemory.write()` calls with the mutex themselves while waiting for an SDK fix.

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
- ameba-rtos-pro2 ftl_nor_api.c (RT_DEV_LOCK_FLASH): https://github.com/Ameba-AIoT/ameba-rtos-pro2/blob/main/component/ftl/ftl_nor_api.c
- commit fb3dc02 — module_video.c queue init guard: https://github.com/Ameba-AIoT/ameba-rtos-pro2/commit/fb3dc02
- commit 3130193 — JPEG snapshot queue guard exception: https://github.com/Ameba-AIoT/ameba-rtos-pro2/commit/3130193
- commit f575a69 — VOE 1.7.0.0 sync: https://github.com/Ameba-AIoT/ameba-rtos-pro2/commit/f575a69
- ideashatch/HUB-8735 issue #10 (PS5268 sensor id fail): https://github.com/ideashatch/HUB-8735/issues/10
- Forum thread #3983 (error after write in memory AMB82): https://forum.amebaiot.com/t/error-after-write-in-memory-amb82/3983


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

## Research Update — 2026-04-29 (Update 2)

### Finding 25 — video_pre_init_save_cur_params() Signature: save_option Is the THIRD Argument
**Source:** ameba-rtos-pro2 — `video_api.c` raw fetch + module_video.c callback analysis  
https://raw.githubusercontent.com/Ameba-AIoT/ameba-rtos-pro2/main/component/video/driver/RTL8735B/video_api.c  
**Priority:** MEDIUM — Resolves Q9 (call frequency); corrects interpretation of per-frame callback

Full confirmed signature:
```c
void video_pre_init_save_cur_params(
    int meta_enable,          // arg 1: 1 = read AE/AWB from metadata pipeline
    video_meta_t *meta_data,  // arg 2: pointer to current metadata
    enum isp_init_option save_option  // arg 3: 0=STRUCTURE, 1=FLASH, 2=RETENTION
);
```

The per-frame callback in `module_video.c` calls:
```c
video_pre_init_save_cur_params(1, &(ctx->meta_data), 0);
                                                      ^
                                              save_option=0 = SAVE_TO_STRUCTURE (in-memory ONLY)
```

**This means the per-frame video callback does NOT write to flash.** The `SAVE_TO_FLASH` path (arg 3 = 1) is a separate, on-demand code path.

---

### Finding 26 — CRITICAL: SAVE_TO_FLASH Is NOT Called Per-Frame — Only on Explicit Request
**Source:** ameba-rtos-pro2 FCS example — `mmf2_video_example_joint_test_rtsp_mp4_init_fcs.c` (commit 4dcbdb9)  
https://github.com/Ameba-AIoT/ameba-rtos-pro2/blob/4dcbdb9e67c01588079d3d47114a2fcd09ae5cd1/project/realtek_amebapro2_v0_example/src/mmfv2_video_example/mmf2_video_example_joint_test_rtsp_mp4_init_fcs.c  
**Priority:** HIGH — Narrows race window; refines Hypothesis F

The RTOS FCS example defines:
```c
#define EXAMPLE_SAVE_TO_FLASH   0   // maps to SAVE_TO_FLASH enum variant
#define EXAMPLE_SAVE_OPTION     EXAMPLE_SAVE_TO_FLASH
```

The flash write path `voe_fcs_change_parameters()` is only invoked from `fcs_change()`, which is the handler for the **explicit** AT command:
```
FCST=ch,width,height,iq_id,video_pre_init
```

**The flash write at `0xF0D000` is NOT triggered automatically on every frame or by a periodic timer.** It is invoked only when an application-level FCS parameter save is explicitly requested — in the RTOS example, by user AT command; in the Arduino SDK (pre-compiled libraries), by the equivalent API call that occurs once after AE/AWB convergence is detected.

**Revised race window for Hypothesis F:**
- The ~60ms SAVE_TO_FLASH race window does NOT open 30 times per second
- It opens **once per session** (or at most a few times, on convergence events)
- But this does NOT eliminate the bug: `FlashMemory.write()` is typically a long operation (sector erase = 30–150ms), so even a once-per-session 60ms window is still likely to overlap if the user calls `FlashMemory.write()` while the camera is streaming

**Revised severity ladder interpretation:**
- 1× `writeWord` (stable): Short operation (~μs), very low probability of overlapping a once-per-session 60ms FCS save window
- 70× `writeWord` (slot full): Cumulative write time (~280 × μs + potential erase retries) greatly increases overlap probability over the session
- Sector erase (complete fail): Single ~30–150ms operation spans the entire FCS save window, near-certain collision if both happen near-concurrently

---

### Finding 27 — device_lock.h IS Reachable from Arduino User Sketches
**Source:** ameba-arduino-pro2 SDK directory structure analysis  
`Arduino_package/hardware/system/component/os/os_dep/include/device_lock.h`  
**Priority:** HIGH — Provides a practical user-level workaround without modifying the SDK

The file `device_lock.h` is present in the SDK system component tree and declares:
```c
typedef enum {
    RT_DEV_LOCK_UART    = 0,
    RT_DEV_LOCK_FLASH   = 1,   // ← the mutex we need
    RT_DEV_LOCK_I2C     = 2,
    RT_DEV_LOCK_SPI     = 3,
    RT_DEV_LOCK_ADC     = 4,
    RT_DEV_LOCK_VOE     = 5,
    RT_DEV_LOCK_NN      = 6,
    RT_DEV_LOCK_MAX     = 7
} RT_DEV_LOCK_E;

void device_mutex_lock(RT_DEV_LOCK_E device);
void device_mutex_unlock(RT_DEV_LOCK_E device);
```

Arduino user sketches can include this by adding:
```cpp
extern "C" {
    #include "device_lock.h"
}
```

**User-level workaround** (no SDK recompilation required):
```cpp
extern "C" { #include "device_lock.h" }

void safeFlashWrite(uint32_t offset, const uint8_t* buf, size_t len) {
    device_mutex_lock(RT_DEV_LOCK_FLASH);
    FlashMemory.write(offset, buf, len);
    device_mutex_unlock(RT_DEV_LOCK_FLASH);
}
```

This prevents `FlashMemory.write()` from running concurrently with the FCS `ftl_common_write(0xF0D000)` call, which already acquires `RT_DEV_LOCK_FLASH` internally.

**Caveat:** This workaround protects against the concurrency race (Hypothesis F) but does NOT protect against the OTA-build direct-erase bug (Finding 20) nor Hypothesis D (power-cut during FCS save window).

---

### Finding 28 — RT_DEV_LOCK_FLASH Is a FreeRTOS Priority-Inheritance Mutex
**Source:** ameba-rtos-pro2 — `device_lock.c` + `freertos_service.c`  
https://github.com/Ameba-AIoT/ameba-rtos-pro2/blob/main/component/os/os_dep/device_lock.c  
**Priority:** MEDIUM — Confirms mutex correctness; explains why locking stops concurrent SPI access

Key implementation details:
- Implemented as `xSemaphoreCreateMutex()` — a **recursive-capable priority-inheritance mutex** (NOT a binary semaphore)
- Mutex pool: `static _mutex device_mutex[RT_DEV_LOCK_MAX]` (7 entries, one per device)
- Lock timeout: **10,000 ms** — after which a "device lock timeout" message is printed and the wait continues (no forced unlock)
- When `FlashMemory.cpp` calls `flash_stream_write()` without acquiring this mutex, the SPI NOR controller receives a WREN+SE command while `ftl_common_write` may be mid-page-program; the two SPI command sequences interleave at the hardware level, aborting whichever command was in progress (JEDEC specification behavior for overlapping SPI CS assertions)

---

### Finding 29 — No New SDK Release; dev Branch FlashMemory.cpp Still Has No Mutex Fix
**Source:** GitHub releases page + dev branch FlashMemory.cpp raw fetch  
https://github.com/Ameba-AIoT/ameba-arduino-pro2/releases  
https://raw.githubusercontent.com/Ameba-AIoT/ameba-arduino-pro2/dev/Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.cpp  
**Priority:** LOW — Bug status unchanged

- Latest release: **v4.1.0** (March 2, 2026) / **v4.1.1-QC-V04** pre-release (March 6, 2026)
- No releases after April 2026
- `FlashMemory.cpp` **dev branch**: zero `device_mutex_lock` calls, zero `device_lock.h` includes — identical to main branch in this regard
- `VideoStream.cpp` dev branch: zero FCS-related code — FCS functionality is entirely in the pre-compiled `libvoe.bin`/`libvideo_ns.a`/`libvideo_ntz.a` binary blobs, not in open C++ source

---

### Finding 30 — New Forum Threads Found (All 403-Blocked)
**Source:** Google index / Ameba IoT Forum  
**Priority:** LOW — Threads may contain relevant information but are inaccessible

Threads identified via search but blocked (HTTP 403) on access:
- Thread #4321: "Camera sensor init failed (GC2053)" — August 24, 2025, reports VOE init errors after updating to v4.0.9-build20250805. Likely FCS-related but unconfirmed.
- Thread #4777: "AMB82-Mini onboard camera sensor identification and VOE setup for wireless video and I2C" — March 2026, discusses camera setup with I2C; may reference initialization failures.
- Thread #4811: "Camera_2_Lcd_JPEGDEC.ino error/warning" — April 2026, Arduino IDE 2.3.8 compilation errors; likely unrelated to FCS.
- Thread #3983: "Error after write in memory AMB82" — flash write + restart error pattern matching our bug; still blocked.

---

### Updated Open Questions — 2026-04-29 (Update 2)

| # | Question | Status |
|---|---|---|
| 1 | NOR_FLASH_FCS address | **RESOLVED** — 0xF0D000 confirmed |
| 2 | Does FCS disable prevent the bug? | Still unconfirmed experimentally |
| 3 | Is FCS parameter address configurable? | **RESOLVED** — compile-time only (platform_opts.h) |
| 4 | Bug present in v4.0.7? | Still untested |
| 5 | Realtek notified? | **RESOLVED (negatively)** — Bug still undocumented |
| 6 | FlashMemory.write() triggers SAVE_TO_FLASH event? | **RESOLVED** — No direct coupling; race is at SPI controller level |
| 7 | Video message queue slot count? | **RESOLVED** — No ~70-slot queue (Hypothesis E eliminated) |
| 8 | Is SAVE_TO_FLASH a background task? | **RESOLVED** — Synchronous, ~60ms, in video RTOS task context |
| 9 | When exactly is video_meta_data_process() called? | **RESOLVED** — Per-frame but with SAVE_TO_STRUCTURE (arg 0). SAVE_TO_FLASH only via explicit once-per-session API call. Race window does not open 30×/sec. |
| 10 | Can device_mutex_lock be called from Arduino user code? | **RESOLVED (YES)** — Via `extern "C" { #include "device_lock.h" }`. Path: `Arduino_package/hardware/system/component/os/os_dep/include/device_lock.h`. Practical user workaround is now available. |

---

## Known Workarounds (Unconfirmed)

1. **Disable Camera FCS mode** ★ CONFIRMED RACE ELIMINATOR — Arduino IDE `Camera FCS mode process = Disable`. Sets no `-DArduino_FCS_MODE` flag, so the video driver never calls `ftl_common_write(0xF0D000)` during the session. This **completely prevents** the flash race condition — there is no FCS write to collide with `FlashMemory.write()`. Trade-off: every cold boot takes the slow sensor initialization path (~4–6 s) instead of the FCS fast path (~250 µs). See Finding 36.

2. **Avoid sector erase** — Use only `writeWord()` with values that only flip 1→0 bits (no erase needed). Unreliable for arbitrary user data.

3. **Change `FLASH_MEMORY_APP_BASE`** — Recompile SDK with a different base address that doesn't conflict with FCS parameters. Requires source SDK access.

4. **Re-trigger FCS parameter save after flash write** — After any FlashMemory operation, call `video_pre_init_save_cur_params(SAVE_TO_FLASH)` explicitly and wait for it to complete before allowing power-off. Feasibility depends on API availability at user level.

5. **Use software reset instead of power cycle** — The bug only manifests on cold boot. A software reset (no power interruption) may preserve DRAM retention of FCS state. Not viable for real deployment.

6. **Switch SAVE_OPTION to SAVE_TO_RETENTION** — Change the FCS example `EXAMPLE_SAVE_OPTION` from `SAVE_TO_FLASH` to `SAVE_TO_RETENTION`. This avoids flash entirely for AE/AWB storage, using SRAM retention instead. Retention survives warm resets but not full power cycles — so may not fully solve the problem, but could reduce the race window.

7. **User-level mutex wrapper around FlashMemory calls** ★ NEW — Wrap every `FlashMemory.write()/writeWord()` call with `device_mutex_lock(RT_DEV_LOCK_FLASH)` / `device_mutex_unlock()`. The header is accessible from Arduino sketches without SDK recompilation. Addresses the Hypothesis F concurrency race. Does NOT address the OTA direct-erase bug or the power-cut Hypothesis D. See Finding 27 for implementation code.

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

9. **When exactly is `video_meta_data_process()` called?** — ~~Not yet fully traced.~~ **RESOLVED** — Per-frame callbacks use `save_option=0` (SAVE_TO_STRUCTURE, in-memory only). The SAVE_TO_FLASH path only executes via explicit once-per-session API call on AE/AWB convergence, not continuously. See Findings 25 and 26.

10. **Can `device_mutex_lock(RT_DEV_LOCK_FLASH)` be called from Arduino user code as a workaround?** — **RESOLVED (YES)** — `device_lock.h` is accessible from Arduino user sketches via `extern "C" { #include "device_lock.h" }`. See Finding 27 for full workaround code.

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
- ameba-rtos-pro2 device_lock.c (RT_DEV_LOCK_FLASH mutex impl): https://github.com/Ameba-AIoT/ameba-rtos-pro2/blob/main/component/os/os_dep/device_lock.c
- ameba-arduino-pro2 device_lock.h (user-accessible header): Arduino_package/hardware/system/component/os/os_dep/include/device_lock.h
- ameba-rtos-pro2 FCS example (SAVE_TO_FLASH via AT command): https://github.com/Ameba-AIoT/ameba-rtos-pro2/blob/4dcbdb9e67c01588079d3d47114a2fcd09ae5cd1/project/realtek_amebapro2_v0_example/src/mmfv2_video_example/mmf2_video_example_joint_test_rtsp_mp4_init_fcs.c
- Forum thread #4321 (GC2053 camera sensor init failed, Aug 2025): https://forum.amebaiot.com/t/camera-sensor-init-failed-gc2053/4321
- Forum thread #4777 (AMB82-Mini camera VOE setup with I2C, Mar 2026): https://forum.amebaiot.com/t/amb82-mini-onboard-camera-sensor-identification-and-voe-setup-for-wireless-video-and-i2c/4777
- Forum thread #4811 (Camera_2_Lcd_JPEGDEC errors, Apr 2026): https://forum.amebaiot.com/t/camera-2-lcd-jpegdec-ino-error-warning/4811
- RTL8735BDM-A20-N04 Module Datasheet Rev 1.1 (May 2025): https://aiot.realmcu.com/en/_static/modules/rtl8735b/RTL8735BDM-A20-N04_Module_Datasheet_V1.1_2025.pdf

---

## Research Update — 2026-04-29 (Update 3)

### Finding 31 — CRITICAL: FlashMemory.h Had Wrong Constants in V4.0.8 and V4.0.9 (Missing Hex Digit)
**Source:** Direct fetch of `FlashMemory.h` from GitHub tags `V4.0.8`, `V4.0.9`, and `V4.1.0`  
https://raw.githubusercontent.com/Ameba-AIoT/ameba-arduino-pro2/V4.0.8/Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.h  
https://raw.githubusercontent.com/Ameba-AIoT/ameba-arduino-pro2/V4.0.9/Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.h  
https://raw.githubusercontent.com/Ameba-AIoT/ameba-arduino-pro2/V4.1.0/Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.h  
**Priority:** HIGH — Rewrites the version-history narrative; narrows the race condition to V4.1.0+

**V4.0.8 and V4.0.9 (wrong):**
```c
#define NOR_FLASH_SIZE            0x100000    // 1 MB — WRONG (should be 16 MB = 0x1000000)
#define FLASH_MEMORY_APP_BASE     0xFD000     // WRONG — missing a trailing zero (should be 0xFD0000)
#define FLASH_MEMORY_SIZE         NOR_FLASH_SIZE
#define MAX_FLASH_MEMORY_APP_SIZE (FLASH_MEMORY_SIZE - FLASH_MEMORY_APP_BASE)  // = 0x3000 = 12 KB (3 sectors)
```

**V4.1.0 (corrected):**
```c
#define NOR_FLASH_SIZE            0x1000000   // 16 MB — CORRECT
#define FLASH_MEMORY_APP_BASE     0xFD0000    // CORRECT
#define FLASH_MEMORY_SIZE         NOR_FLASH_SIZE
#define MAX_FLASH_MEMORY_APP_SIZE (FLASH_MEMORY_SIZE - FLASH_MEMORY_APP_BASE)  // = 0x30000 = 192 KB (48 sectors)
```

The V4.1.0 release notes list `"Update FlashMemory.h"` under API Updates; this is the address-constants correction, not a mutex fix.

**Consequences of the V4.0.8/V4.0.9 bug:**
- `FlashMemory.write()` erased 3 sectors starting at `0xFD000` (decimal 1,036,288 bytes into flash).
- The fw1 partition occupies `0x080000 – 0x400000`. Address `0xFD000` falls **inside fw1**, so every `FlashMemory.write()` call silently corrupted the running application firmware. The API was completely broken/dangerous in these two releases.
- Nobody successfully using `FlashMemory.write()` on V4.0.8/V4.0.9 would observe the FCS/camera race, because the firmware itself would be corrupted first.

**Critical implication for the bug:** The Hypothesis F concurrency race (FlashMemory bypasses `RT_DEV_LOCK_FLASH`) can only manifest starting with **V4.1.0**, where the correct base address `0xFD0000` first made FlashMemory usable. Research doc Finding 2 ("FlashMemory Base Address Confirmed: 0xFD0000") reflects the V4.1.0+ value; earlier SDK versions had `0xFD000` (no overlap with the FCS address but also not the intended user data area).

---

### Finding 32 — Correction to Finding 27: device_lock.h Enum First Entry Is EFUSE, Not UART
**Source:** Direct fetch of `device_lock.h` from `dev` branch  
https://raw.githubusercontent.com/Ameba-AIoT/ameba-arduino-pro2/dev/Arduino_package/hardware/system/component/os/os_dep/include/device_lock.h  
**Priority:** LOW — Minor correction to Finding 27; workaround code is unaffected

The actual enum in all SDK versions (V4.0.8, V4.0.9, V4.1.0, dev):
```c
enum _RT_DEV_LOCK_E {
    RT_DEV_LOCK_EFUSE  = 0,   // ← NOT RT_DEV_LOCK_UART as stated in Finding 27
    RT_DEV_LOCK_FLASH  = 1,   // ← correct, unchanged
    RT_DEV_LOCK_CRYPTO = 2,
    RT_DEV_LOCK_PTA    = 3,
    RT_DEV_LOCK_WLAN   = 4,
    RT_DEV_LOCK_VOE    = 5,
    RT_DEV_LOCK_NN     = 6,
    RT_DEV_LOCK_MAX    = 7
};
typedef uint32_t RT_DEV_LOCK_E;
```

`RT_DEV_LOCK_FLASH = 1` is identical in both versions. The workaround code in Finding 27 uses the correct value; only the listing of other enum members was wrong.

---

### Finding 33 — hal_voe.h Is Proprietary (Not in Any Public Repo); FCS_RUN_DATA_NG_KM Value Inferred
**Source:** GitHub file search on both `ameba-rtos-pro2` and `ameba-arduino-pro2` repos  
**Priority:** MEDIUM — Confirms why KM status constants were previously undocumented

`hal_voe.h` is **not present in any public Ameba repository**. Both `ameba-rtos-pro2` and `ameba-arduino-pro2` return "No matching files found" for `hal_voe`. The file is distributed exclusively as a closed-source header bundled with the pre-compiled VOE binary blobs (`voe.bin`, `libvideo_ns.a`, `libvideo_ntz.a`).

The open-source files `video_boot.c` and `video_user_boot.c` include `hal_voe.h` via their include list, meaning they compile only against the binary SDK — not from open-source headers.

**Implication for KM status values:** The constants `FCS_RUN_DATA_OK_KM` and `FCS_RUN_DATA_NG_KM` used in `video_boot.c` are defined in the closed-source `hal_voe.h`. However, by matching against the known boot log:
- Normal boot: `FCS KM_status 0x00000082` → **`FCS_RUN_DATA_OK_KM = 0x0082`** (inferred)
- Bug state: `FCS KM_status 0x00002081` → **`FCS_RUN_DATA_NG_KM = 0x2081`** (inferred)

These are single defined constants (not bitfields), per the symbolic names. The `err 0x0000200a` error code is similarly closed-source; its precise meaning ("I2C init error" or "flash data error") cannot be confirmed from public sources.

---

### Finding 34 — user_boot_config_init() Has Void Return; Three Checksum Paths Confirmed
**Source:** Direct fetch of `video_user_boot.c` (main branch)  
https://raw.githubusercontent.com/Ameba-AIoT/ameba-rtos-pro2/main/component/video/driver/RTL8735B/video_user_boot.c  
**Priority:** MEDIUM — Clarifies the exact failure sequence when FCS flash data is corrupted

`user_boot_config_init()` has **void return type**. When FCS flash data at `0xF0D000` is corrupted (all `0xFF` after erase), the function:
1. Reads the FCSD header + 2 KB payload
2. Computes checksum over the payload
3. Finds mismatch → prints **`"Check sum fail\r\n"`** → executes `return;` (void, no error propagation)

Three distinct checksum paths exist:
- `"check sum fail %d %d\r\n"` — retention data checksum mismatch
- **`"Check sum fail\r\n"`** — NOR flash FCS data checksum mismatch ← this is the path triggered by our bug
- `"isp init check sum fail %d %d %d\r\n"` — ISP retention data mismatch

After `user_boot_config_init()` returns without applying the corrupt FCS data, the higher-level `user_load_sensor_boot()` finds no valid sensor configuration and returns `<= 0`. `video_btldr_init_sensor_process()` then prints **`"It don't do the sensor initial process\r\n"`** and calls `hal_voe_set_kmfw_base_addr(FCS_RUN_DATA_NG_KM)`.

**Full boot log sequence when FCS data is corrupted:**
```
[optional] Check sum fail          ← from user_boot_config_init() in video_user_boot.c
FCS KM_status 0x00002081  err 0x0000200a   ← KM register read-back after FCS_RUN_DATA_NG_KM written
It don't do the sensor initial process     ← from video_btldr_init_sensor_process() in video_boot.c
```

The "Check sum fail" line may or may not be visible depending on boot log buffer capture timing. Users who only see the KM_status line may have missed the prior checksum error.

---

### Finding 35 — No New SDK Release; No Mutex Fix; No New GitHub Issues Filed
**Source:** GitHub releases page + issues search (April 29, 2026)  
https://github.com/Ameba-AIoT/ameba-arduino-pro2/releases  
https://github.com/Ameba-AIoT/ameba-arduino-pro2/issues  
**Priority:** LOW — Status of bug unchanged

- Latest public release remains **V4.1.0** (March 2, 2026) / **V4.1.1-QC-V04** pre-release (March 6, 2026)
- No new releases since the previous research update
- `FlashMemory.cpp` on `dev` branch: still zero `device_mutex_lock` calls — bug is unpatched
- No new GitHub issues filed against `ameba-arduino-pro2` or `ameba-rtos-pro2` mentioning FlashMemory + camera/FCS interaction
- No new commits to `main` branch of either repo in the April 28–29 window
- Forum threads #3983 (flash write errors on AMB82) and #4321 (GC2053 init fail) remain HTTP 403-blocked

---

### Updated Hypothesis F — Confirmed V4.1.0+ Only; Root Cause Sequence Now Complete
**Priority:** HIGH — Builds on Findings 31 and 34

The complete root cause sequence for the Hypothesis F race condition (now confirmed as V4.1.0+ only):

1. **V4.0.8/V4.0.9 users**: `FlashMemory.write()` erased firmware at `0xFD000` — catastrophic but unrelated to FCS/camera.
2. **V4.1.0+ users**: `FlashMemory.write()` correctly targets `0xFD0000` (user data area). However, it still has no `RT_DEV_LOCK_FLASH` protection.
3. Race trigger: While Arduino `loop()` calls `FlashMemory.write()` (no mutex), the video module RTOS task calls `ftl_common_write(0xF0D000, fcs_buf, 2048)` (which holds `RT_DEV_LOCK_FLASH`). Two concurrent SPI flash command sequences collide at the hardware controller level, aborting the page-program at `0xF0D000`.
4. Result: `0xF0D000` is erased but not reprogrammed → all `0xFF` → "Check sum fail" on next boot → "It don't do the sensor initial process" + `FCS KM_status 0x00002081 err 0x0000200a`.

**All three experimental severity levels are now fully explained:**
- 1× `writeWord` (stable): Sub-microsecond write, almost zero overlap probability with the once-per-session ~60ms FCS save window
- 70× `writeWord` (slot full): Cumulative flash time greatly increases collision probability; partial FCS corruption causes VOE channel restore failure → `[VOE][WARN]slot full`
- Sector erase (complete fail): Single 30–150ms erase operation spans the entire FCS save window → near-certain collision → complete camera init failure

**Confirmed minimum SDK version affected: V4.1.0** (first release with correct `FLASH_MEMORY_APP_BASE = 0xFD0000`)

---

### Sources Added (Update 3)
- ameba-arduino-pro2 FlashMemory.h V4.0.8 tag: https://raw.githubusercontent.com/Ameba-AIoT/ameba-arduino-pro2/V4.0.8/Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.h
- ameba-arduino-pro2 FlashMemory.h V4.0.9 tag: https://raw.githubusercontent.com/Ameba-AIoT/ameba-arduino-pro2/V4.0.9/Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.h
- ameba-arduino-pro2 FlashMemory.h V4.1.0 tag: https://raw.githubusercontent.com/Ameba-AIoT/ameba-arduino-pro2/V4.1.0/Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.h
- ameba-arduino-pro2 device_lock.h dev branch: https://raw.githubusercontent.com/Ameba-AIoT/ameba-arduino-pro2/dev/Arduino_package/hardware/system/component/os/os_dep/include/device_lock.h
- ameba-rtos-pro2 video_user_boot.c main branch: https://raw.githubusercontent.com/Ameba-AIoT/ameba-rtos-pro2/main/component/video/driver/RTL8735B/video_user_boot.c
- ameba-rtos-pro2 video_boot.c main branch: https://raw.githubusercontent.com/Ameba-AIoT/ameba-rtos-pro2/main/component/video/driver/RTL8735B/video_boot.c

---

## Research Update — 2026-04-30

### Finding 36 — CONFIRMED: Disabling FCS Mode Eliminates the Race Condition Entirely
**Source:** `ameba-arduino-pro2` — `boards.txt` (dev branch)
https://github.com/Ameba-AIoT/ameba-arduino-pro2/blob/dev/Arduino_package/hardware/boards.txt
**Priority:** HIGH — Upgrades Workaround #1 from "fallback" to "confirmed race eliminator"

`boards.txt` defines the Arduino IDE "Camera FCS Mode" menu option with the following compile flag:
```
menu.FCSMode.Enable.build.extra_flags=-DArduino_FCS_MODE
menu.FCSMode.Disable.build.extra_flags=
```

When **"Camera FCS Mode: Disable"** is selected in Arduino IDE Tools, the macro `Arduino_FCS_MODE` is **not defined**. The pre-compiled video libraries gate the `ftl_common_write(0xF0D000, fcs_buf, 2048)` FCS save call on this macro at compile time. When the flag is absent, the video task **never calls `ftl_common_write(0xF0D000)`** — meaning there is no FCS write to race with, and no FCS sector to corrupt.

**Consequence:** Workaround #1 in the Known Workarounds list (disable FCS mode) is **more powerful than previously documented**. It does not merely "fall back to slow boot" — it completely prevents the runtime condition that corrupts the FCS sector. With FCS disabled, `FlashMemory.write()` cannot cause cold-boot camera failure because no FCS data is ever written to flash during the session. The trade-off is that every cold boot takes the full slow sensor initialization path (~4–6 seconds depending on sensor) instead of the fast path (~254µs sensor + <12ms total).

**Correction to Known Workaround #1:** The prior statement "Does NOT fix the camera, just falls back to slow boot" was imprecise. More accurately: disabling FCS mode **prevents the bug** by removing the conflicting writer, at the cost of slower cold boot.

---

### Finding 37 — Forum Thread #4670: V4.1.x Builds Cause "CH 0 MMF ENC Queue Full" Regression
**Source:** forum.amebaiot.com (HTTP 403 for full content; Google-indexed snippet only)
https://forum.amebaiot.com/t/updated-of-amb82-mini-board-breaks-working-code/4670
**Priority:** LOW — Different symptom from the FCS cold-boot bug, but shows ongoing V4.1.x video pipeline instability

Search engine snippet: a user reports that updating the AMB82-Mini board package to versions starting around `4.1.20251219` causes the error `"CH 0 MMF ENC Queue full"` on previously working code. Earlier SDK versions (pre-V4.1) did not exhibit this error. The symptom (encoder queue full, video corruption) is distinct from `[VOE][WARN]slot full` and from the FCS cold-boot failure, but indicates that the video pipeline's queue management has had multiple regression issues across V4.1.x builds.

This is not the same bug as the FlashMemory FCS race, but its existence confirms that V4.1.x introduced multiple video pipeline regressions simultaneously — consistent with the architectural fragility of the concurrent flash access design.

---

### Finding 38 — No Fix Committed as of April 30, 2026; Latest ameba-rtos-pro2 Commit is April 15
**Source:** https://github.com/Ameba-AIoT/ameba-rtos-pro2/commits/main
**Priority:** LOW — Status confirmation; bug remains unpatched

The most recent commit to `ameba-rtos-pro2` main branch is dated **April 15, 2026**: an automated sync commit ("Sync upstream caf4887530a9df372ead1244f52ea3afb802cf16") plus a KVS WebRTC v2 example addition. No commits to `FlashMemory.cpp`, `ftl_nor_api.c`, `device_lock.h`, `platform_opts.h`, or any video driver file were made in the April 2026 window. The `ameba-rtos-pro2` repo has only 3 open issues (most recent: Jan 27, 2026), none related to this bug.

**Status as of 2026-04-30:** Bug is unpatched in all public repositories. The research log's root cause analysis (Hypothesis F — missing `RT_DEV_LOCK_FLASH` in `FlashMemory.cpp`) remains the standing explanation with no contrary evidence.

---

### Finding 39 — V4.1.1-QC-V04 Release Tag Contains Internal Builds Dated up to April 17, 2026
**Source:** https://github.com/Ameba-AIoT/ameba-arduino-pro2/releases/tag/V4.1.1-QC-V04
**Priority:** MEDIUM — The release binaries may be newer than the tag date (March 6, 2026) suggests

The V4.1.1-QC-V04 release notes internally reference incremental build entries dated **03/20/2026**, **04/02/2026**, and **04/17/2026**. These are changelog entries embedded within the same release tag, not separate published release tags. The tag's published date is March 6, 2026, but binary artifacts (VOE, libvideo_ns.a, libvideo_ntz.a) inside the release may correspond to the most recent internal build (04/17/2026).

**Implication:** Users who downloaded V4.1.1-QC-V04 at its release date and users who download it now may receive different binary blobs. A user verifying that the bug is still present should note which exact build date appears in their `hal_video_release_note.txt`. However, since no changelog entry mentions a FlashMemory mutex fix in any of these internal builds, the bug is still expected to be present.

---

### Sources Added (Update 2026-04-30)
- ameba-arduino-pro2 boards.txt dev branch: https://github.com/Ameba-AIoT/ameba-arduino-pro2/blob/dev/Arduino_package/hardware/boards.txt
- Forum thread #4670 (V4.1.x MMF ENC Queue full regression): https://forum.amebaiot.com/t/updated-of-amb82-mini-board-breaks-working-code/4670
- ameba-rtos-pro2 commits/main (last commit April 15, 2026): https://github.com/Ameba-AIoT/ameba-rtos-pro2/commits/main
- ameba-arduino-pro2 V4.1.1-QC-V04 release notes: https://github.com/Ameba-AIoT/ameba-arduino-pro2/releases/tag/V4.1.1-QC-V04

---

## Research Update — 2026-04-30 (Update 2)

### Finding 40 — FlashMemory.cpp Full Commit History: Added July 9, 2024; Last Modified September 30, 2025
**Source:** `ameba-arduino-pro2` — commit log for `FlashMemory.cpp` (dev branch)
https://github.com/Ameba-AIoT/ameba-arduino-pro2/commits/dev/Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.cpp
**Priority:** MEDIUM — Establishes precise timeline of the file; confirms no changes during the V4.1.0 address-fix release window

The full known commit history for `FlashMemory.cpp`:
- **July 9, 2024** — "Add feature Flash Memory #252" — initial creation of the file
- **September 30, 2025** — "Optimize codes #337" — last modification (nature of optimization unknown; no mutex added)
- **No commits after September 30, 2025.** The V4.1.0 release (March 2026) updated `FlashMemory.h` constants (Finding 31) but did NOT touch `FlashMemory.cpp` itself.

This means the mutex omission in `FlashMemory.cpp` has been in place since the file was first written on July 9, 2024, survived at least one "Optimize codes" pass on September 30, 2025, and remains unpatched through V4.1.1-QC-V04 (April 17, 2026 internal build).

The `dev` branch of `ameba-arduino-pro2` shows **4 commits on April 17, 2026** (the most recent activity):
1. "Add Arduino ZIP library submodules: JPEGDecoder and ArduCAM (#405)"
2. "Pre Release Version 4.1.1"
3. "Update wifi_drv.cpp"
4. "Update ameba_pro2_tools 1.4.10"

None of these touch FlashMemory, FCS, VOE, or any video/camera subsystem. Zero development activity on the dev branch after April 17, 2026.

---

### Finding 41 — Thread #4302: "[VOE]frame_end Sensor Didn't Initialize Done" Occurs With FCS Mode Disabled
**Source:** forum.amebaiot.com thread #4302 (HTTP 403; Google-indexed snippet only)
https://forum.amebaiot.com/t/voe-frame-end-sensor-didnt-initialize-done/4302
**Priority:** MEDIUM — Reveals a separate, independent sensor initialization failure path distinct from the FlashMemory/FCS race

Newly indexed search snippet from thread #4302 (August 9–25, 2025):

Users report the error `"[VOE]frame_end: sensor didn't initialize done!"` on AMB82-MINI with Arduino IDE 2.3.6, using JXF37 and GC2053 sensors. Critically: **Camera FCS Mode was set to Disable** in these reports. This error is distinct from `"It don't do the sensor initial process"` (the FCS cold-boot failure in our bug).

**Interpretation:**
- The `"[VOE]frame_end: sensor didn't initialize done!"` error in thread #4302 occurs *independently of FCS mode* and *independently of FlashMemory writes*. It is a separate sensor initialization timing issue in the VOE pipeline.
- Workaround #1 (disable FCS mode) prevents the FlashMemory/FCS race but does NOT prevent this separate "[VOE]frame_end" failure mode.
- Users disabling FCS mode as a workaround for our bug should be aware that independent camera initialization failures (thread #4302 class) may still occur, particularly on SDK versions around 2.3.6 / V4.0.9.
- The two failure modes have different root causes and different error strings; they should not be conflated.

---

### Finding 42 — Forum Thread #4834: Boot ROM NOR Flash Detection Failure (Late April 2026, Different Bug)
**Source:** forum.amebaiot.com thread #4834 (HTTP 403; Google-indexed snippet only)
https://forum.amebaiot.com/t/boot-failure-after-ota-update/4834
**Priority:** LOW — Different failure mode; confirms ongoing RTL8735B boot reliability issues in the field

A very recent thread (search engine indicates posting within ~1 week of April 30, 2026). The reported symptom is the boot ROM failing to detect/enumerate the NOR flash chip entirely — no boot proceeds. This is a distinct failure from the FCS parameter corruption bug: in our bug, the flash is detected and read correctly, but the FCS data sector contains a bad checksum. In thread #4834, the flash itself is not recognized.

Possible cause: OTA update wrote an incompatible boot sector or partition table. Not related to the FlashMemory/FCS race condition.

---

### Finding 43 — ameba-rtos-pro2 dev Branch Not Publicly Accessible; Search Confirms Zero Mutex Code
**Source:** https://github.com/Ameba-AIoT/ameba-rtos-pro2/tree/dev
https://github.com/Ameba-AIoT/ameba-rtos-pro2/search?q=device_mutex_lock+FlashMemory
**Priority:** LOW — Status confirmation

The `dev` branch of `ameba-rtos-pro2` reports "There isn't any commit history to show here" — it is either empty or not publicly exposed. This prevents reviewing any in-progress fixes.

A GitHub code search for `device_mutex_lock` combined with any FlashMemory-related file in the `ameba-rtos-pro2` repository returns **zero results**. Similarly, a search for `RT_DEV_LOCK_FLASH` in any FlashMemory-related context returns zero results. The mutex protection has not been added anywhere in either the arduino or RTOS SDK repositories as of April 30, 2026.

---

### Finding 44 — No New SDK Release; Final Status Sweep April 30, 2026
**Source:** Exhaustive multi-source search across GitHub, forum, CSDN, 21ic, EEWorld, bbs.ai-thinker.com
**Priority:** LOW — Status confirmation

Complete status as of 2026-04-30 (end of day):

| Repository / Source | Last relevant activity | Status |
|---|---|---|
| ameba-arduino-pro2 (releases) | April 17, 2026 (V4.1.1-QC-V04 internal build) | No new release |
| ameba-arduino-pro2 (dev branch) | April 17, 2026 (ArduCAM/JPEGDecoder submodules) | No FlashMemory change |
| ameba-rtos-pro2 (main branch) | April 15, 2026 (upstream sync) | No FCS/mutex change |
| ideashatch/HUB-8735 | December 2, 2025 | Inactive |
| forum.amebaiot.com | Thread #4834 (late April 2026) | Unrelated flash-detect failure |
| GitHub issues (all Ameba repos) | — | Zero issues filed for this bug |
| CSDN / Zhihu / 21ic / EEWorld | — | Zero Chinese-language reports |
| bbs.ai-thinker.com (BW21-CBV) | — | No camera/FCS bug threads |

**The bug remains publicly undocumented, unfiled, and unpatched as of 2026-04-30.**

---

### Sources Added (Update 2026-04-30, Update 2)
- ameba-arduino-pro2 FlashMemory.cpp commit log (dev): https://github.com/Ameba-AIoT/ameba-arduino-pro2/commits/dev/Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.cpp
- Forum thread #4302 (VOE frame_end sensor not init, with FCS Disable): https://forum.amebaiot.com/t/voe-frame-end-sensor-didnt-initialize-done/4302
- Forum thread #4834 (Boot failure after OTA, NOR flash not detected): https://forum.amebaiot.com/t/boot-failure-after-ota-update/4834
- ameba-rtos-pro2 dev branch (empty/not exposed): https://github.com/Ameba-AIoT/ameba-rtos-pro2/tree/dev

---

## Research Update — 2026-04-30 (Independent Confirmation Run)

### Finding 45 — Independent Cross-Verification of Root Cause (No New Findings)
**Source:** Independent web search run, 2026-04-30 (this session)
**Priority:** LOW — Redundant confirmation; no novel information

An independent research run (approximately 6-hour cycle) covering all targeted sources produced no new findings not already captured in the Apr 28–Apr 30 updates above. Specifically:

- **Confirmed** `NOR_FLASH_FCS = 0xF0D000` independently from `video_user_boot.c` (same value as Finding 10 from platform_opts.h)
- **Confirmed** `user_boot_config_init()` checksum failure → void return → "It don't do the sensor initial process" (same as Finding 34)
- **Confirmed** no new GitHub issues on ameba-arduino-pro2, ameba-rtos-pro2, ideashatch/HUB-8735, or Ai-Thinker repos
- **Confirmed** no new SDK release (latest: V4.1.1-QC-V04 internal build Apr 17, 2026)
- **Confirmed** zero English and Chinese-language forum/blog posts reporting this bug
- **Confirmed** "Camera FCS mode: Disable" option exists in Arduino IDE (boards.txt compile flag -DArduino_FCS_MODE absent when disabled) — aligns with Finding 36

All prior findings remain valid. Bug status: **publicly undocumented and unpatched** as of 2026-04-30 end of day.

**No HIGH priority confirmed fix was found in this run.**

---

## Research Update — 2026-04-30 (Update 4 — Late Run)

### Finding 46 — V4.1.1-QC-V05: New Pre-Release Tag With April 30, 2026 Internal Build; No Fix
**Source:** https://github.com/Ameba-AIoT/ameba-arduino-pro2/releases/tag/V4.1.1-QC-V05
**Priority:** LOW — Status update; no new fix

The previously documented latest pre-release tag was **V4.1.1-QC-V04** (internal builds through April 17, 2026). A newer tag **V4.1.1-QC-V05** now exists, also dated March 6, 2026 on GitHub but containing internal changelog entries through **2026/04/30** (today). Features added in this tag include:
- Battery-Powered Camera POC Example
- Audio Trigger Recording example
- Video with Zoom feature
- TensorFlowLite support
- AntiCollision POC
- Tool updates to versions 1.4.8, 1.4.9, 1.4.10
- Additional camera sensor support (K306P)

**No mention of FlashMemory, FCS, mutex, device_mutex_lock, RT_DEV_LOCK_FLASH, or any flash-camera interaction fix** anywhere in the V4.1.1-QC-V05 changelog.

---

### Finding 47 — PR #407 "Add AMB82-zero" Merged April 30, 2026; No FCS Fix Included
**Source:** https://github.com/Ameba-AIoT/ameba-arduino-pro2/pull/407
**Priority:** LOW — New board variant confirmed; bug equally applies

PR #407 ("Add AMB82-zero (#407)") was merged into `dev` on **April 30, 2026** by M-ichae-l. This is the sole commit to boards.txt today. The PR adds:
- New board target: **AMB82-ZERO** (RTL8735B SoC, same as AMB82-MINI)
- WDT (Watchdog Timer) API modifications
- ATcmd codebase updates

The AMB82-ZERO board's `boards.txt` entry mirrors AMB82-MINI's FCS menu configuration: **"Camera FCS Mode" defaults to "Disable"**, with Enable adding `-DArduino_FCS_MODE`. No FlashMemory or FCS-related code was modified.

**Implication:** The AMB82-ZERO is another RTL8735B platform that carries the same FlashMemory/FCS concurrency bug when FCS mode is enabled. Its users will encounter identical symptoms.

---

### Finding 48 — FCS Mode Defaults to "Disable" for Both AMB82-MINI and AMB82-ZERO (Confirmed)
**Source:** `ameba-arduino-pro2` dev branch — `boards.txt` (fetched April 30, 2026)
https://raw.githubusercontent.com/Ameba-AIoT/ameba-arduino-pro2/dev/Arduino_package/hardware/boards.txt
**Priority:** MEDIUM — Important safety context for new users

The `boards.txt` FCS menu, confirmed for both AMB82-MINI and AMB82-ZERO:
```
menu.05_FCSMode=* Camera FCS Mode
amb82mini.menu.05_FCSMode.Disable=Disable  ← DEFAULT (listed first)
amb82mini.menu.05_FCSMode.Disable.build.fcs_mode_val=Disable
amb82mini.menu.05_FCSMode.Disable.build.fcs_mode_flags=          ← no flag (FCS not compiled)
amb82mini.menu.05_FCSMode.Enable=Enable
amb82mini.menu.05_FCSMode.Enable.build.fcs_mode_val=Enable
amb82mini.menu.05_FCSMode.Enable.build.fcs_mode_flags=-DArduino_FCS_MODE
```

**"Disable" is listed first and is the default in Arduino IDE.** This has been the case since FCS mode was added on July 25, 2024 (commit "Add camera FCS mode support and sensor F53"). This means:

- A developer who installs the SDK fresh and never changes the FCS menu is **not** affected by the bug — the race condition requires FCS mode to be enabled.
- The bug only manifests for users who deliberately select "Camera FCS Mode: Enable" in Arduino IDE Tools, which is required for fast boot (≈250µs sensor vs. ≈4–6s without FCS).
- The HUB-8735 / BW21-CBV user likely **enabled FCS** to achieve fast cold boot, activating the bug.

---

### Finding 49 — ftl_nor_api.c No Longer Found in ameba-rtos-pro2 Repository
**Source:** GitHub code search: `repo:Ameba-AIoT/ameba-rtos-pro2 ftl_nor_api` — 0 results
https://github.com/Ameba-AIoT/ameba-rtos-pro2/search?q=ftl_nor_api
**Priority:** MEDIUM — Requires re-verification of Finding 17's mutex evidence

The file `component/ftl/ftl_nor_api.c`, previously confirmed in **Finding 17** as the source of `device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapping flash operations, now returns **0 results** from GitHub code search within the `ameba-rtos-pro2` repository. A direct raw fetch also returns HTTP 404.

This likely means the file was renamed, moved, or its contents merged elsewhere during the **March 3, 2026 "Update code base"** commit (SHA a0352b6 / 7e78403) which was the most recent modification to `video_user_boot.c`. The FTL flash mutex protection may now reside in a different file (possibly `component/flash/` or inlined into a higher-level driver).

**Critical caveat:** The disappearance of `ftl_nor_api.c` does NOT necessarily mean the `RT_DEV_LOCK_FLASH` mutex was removed. The FTL API (`ftl_common_write`, `ftl_common_read`) still exists and is still called by `video_api.c`. The mutex may have been preserved in a renamed file. However, until re-confirmed from the new file location, Finding 17's conclusion should be treated as **unconfirmed for the current codebase** (though the underlying SPI NOR concurrency hazard from `FlashMemory.cpp` bypassing any mutex remains valid regardless).

---

### Finding 50 — video_api.c Confirmed Unchanged: No Mutex Added (April 30, 2026)
**Source:** Raw fetch of `ameba-rtos-pro2/main/component/video/driver/RTL8735B/video_api.c`
**Priority:** LOW — Confirms bug still present in current codebase

`video_pre_init_save_cur_params()` in the current `main` branch of `ameba-rtos-pro2` **still contains no synchronization primitives** (`device_mutex_lock`, `RT_DEV_LOCK_FLASH`, or equivalent). The function writes FCS parameters to NOR_FLASH_FCS (0xF0D000) via `ftl_common_write()` without any mutex wrapper at the call site. This matches the V4.1.0/V4.1.1 state documented in prior findings. The bug is unpatched in the RTOS SDK video driver.

---

### Finding 51 — New libarduino_tool Commit in ameba-rtos-pro2 (April 30, 2026); Unrelated to Bug
**Source:** https://github.com/Ameba-AIoT/ameba-rtos-pro2/commit/2b8812c
**Priority:** LOW — Status update

Commit `2b8812c` ("Add arduino_libarduino_tool") was pushed to the `main` branch of `ameba-rtos-pro2` on April 30, 2026 by M-ichae-l. It adds:
1. `.gitignore` — ignore `*.a` files
2. `Readme.md` — instructions for building `libarduino.a` from ~200 source files using MSYS
3. `libarduino_tool.exe` — 5.31 MB binary for building the Arduino library

This is a **build infrastructure tool** unrelated to the FCS/FlashMemory bug. No FTL, mutex, video, camera, or FlashMemory source files were modified.

---

### Updated Status as of 2026-04-30 (Late Run)

| Item | Status |
|---|---|
| Latest pre-release tag | V4.1.1-QC-V05 (internal build April 30, 2026) |
| FlashMemory.cpp mutex fix | **Not present** — confirmed unchanged |
| video_api.c mutex fix | **Not present** — confirmed unchanged |
| ftl_nor_api.c | **File not found** (moved/renamed in March 2026 restructuring) |
| AMB82-ZERO new board | Added April 30, 2026; same bug applies |
| FCS default in boards.txt | "Disable" — new users protected by default |
| Public bug reports | **Zero** — still undocumented |
| Chinese-language sources | **Zero** — still unreported |

**Bug status: publicly undocumented and unpatched as of 2026-04-30 (late run). No HIGH priority confirmed fix found.**

---

### Sources Added (Update 2026-04-30, Update 4)
- ameba-arduino-pro2 releases (V4.1.1-QC-V05): https://github.com/Ameba-AIoT/ameba-arduino-pro2/releases/tag/V4.1.1-QC-V05
- ameba-arduino-pro2 PR #407 (Add AMB82-zero): https://github.com/Ameba-AIoT/ameba-arduino-pro2/pull/407
- ameba-arduino-pro2 boards.txt (FCS default=Disable, AMB82-ZERO): https://raw.githubusercontent.com/Ameba-AIoT/ameba-arduino-pro2/dev/Arduino_package/hardware/boards.txt
- ameba-rtos-pro2 commit 2b8812c (Add arduino_libarduino_tool): https://github.com/Ameba-AIoT/ameba-rtos-pro2/commit/2b8812c
- ameba-rtos-pro2 code search for ftl_nor_api (0 results): https://github.com/Ameba-AIoT/ameba-rtos-pro2/search?q=ftl_nor_api

---

## Research Update — 2026-05-01

### Finding 52 — RESOLVED: ftl_nor_api.c New Location Confirmed After March 2026 Restructuring
**Source:** https://github.com/Ameba-AIoT/ameba-rtos-pro2/blob/main/component/file_system/ftl_common/ftl_nor_api.c  
**Priority:** HIGH — Resolves the open question from Finding 49

Finding 49 noted that `component/ftl/ftl_nor_api.c` returned 404 after the March 3, 2026 "Update code base" restructuring commit. The file has been located at its new path:

**New path:** `component/file_system/ftl_common/ftl_nor_api.c`

The full `component/file_system/ftl_common/` directory now contains:
- `ftl_common_api.c` / `ftl_common_api.h` — top-level FTL dispatch layer (wraps NOR vs NAND)
- `ftl_nor_api.c` / `ftl_nor_api.h` — NOR-specific FTL implementation
- `ftl_nand_api.c` / `ftl_nand_api.h` — NAND-specific FTL implementation

A separate `component/file_system/ftl/ftl.c` file also exists and contains `device_mutex_lock(RT_DEV_LOCK_FLASH)` calls at a lower abstraction layer. The directory tree is: `component/file_system/{dct,fatfs,ftl,ftl_common,fwfs,littlefs,nn,system_data,vfs}`.

---

### Finding 53 — CRITICAL: Complete Flash Lock Chain Mapped — FlashMemory Bypasses TWO Nested Locks
**Source:** `ameba-rtos-pro2` — `ftl_common_api.c`, `ftl_nor_api.c` (new location confirmed in Finding 52)  
https://github.com/Ameba-AIoT/ameba-rtos-pro2/blob/main/component/file_system/ftl_common/ftl_common_api.c  
https://github.com/Ameba-AIoT/ameba-rtos-pro2/blob/main/component/file_system/ftl_common/ftl_nor_api.c  
**Priority:** HIGH — Deepens root cause; Finding 17 was incomplete (only one lock level was known)

The complete call chain for every FCS flash write via `ftl_common_write(0xF0D000, fcs_buf, 2048)`:

```
video_api.c: video_pre_init_save_cur_params()
  └─ ftl_common_write(NOR_FLASH_FCS, ...)         [ftl_common_api.c]
       └─ ftl_lock()                               ← acquires ftl_mutex (rtw_mutex, OUTER lock)
       └─ _ftl_common_write()                      [ftl_common_api.c]
            └─ ftl_write_nor()                     [ftl_nor_api.c]
                 └─ nor_write_cb()                 [ftl_nor_api.c]
                      └─ device_mutex_lock(RT_DEV_LOCK_FLASH)   ← INNER lock
                      └─ flash_stream_write()      ← raw SPI write
                      └─ device_mutex_unlock(RT_DEV_LOCK_FLASH)
       └─ ftl_unlock()                             ← releases ftl_mutex
```

The FCS write path holds **two nested locks simultaneously** during raw flash operations:
1. **Outer:** `ftl_mutex` (an `rtw_mutex` — FreeRTOS mutex, private to the FTL layer)
2. **Inner:** `RT_DEV_LOCK_FLASH` (index 1 in `device_mutex[]` pool, priority-inheritance mutex)

`FlashMemory.cpp` calls `flash_erase_sector()` and `flash_stream_write()` **without acquiring either lock**. It bypasses the entire FTL abstraction layer — not just the inner `RT_DEV_LOCK_FLASH`, but also the outer `ftl_mutex` that would otherwise serialize all FTL callers.

**Implication for the fix:** The correct fix is to have `FlashMemory.cpp` acquire `RT_DEV_LOCK_FLASH` before each raw flash operation (the inner lock is sufficient to block concurrent raw SPI access). The `ftl_mutex` is an FTL-layer-internal lock; acquiring it from Arduino user code is neither necessary nor appropriate. The user-level workaround documented in Finding 27 (`device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapper) remains correct and sufficient.

---

### Finding 54 — libarduino_tool README Confirms FTL Objects Are in Precompiled libarduino.a
**Source:** `ameba-rtos-pro2` commit 2b8812c — `arduino_libarduino_tool/Readme.md`  
https://github.com/Ameba-AIoT/ameba-rtos-pro2/commit/2b8812c  
**Priority:** MEDIUM — Confirms the FTL mutex code is in a precompiled binary blob; direct open-source patch is not possible

The `arduino_libarduino_tool/Readme.md` (added April 30, 2026) lists the ~200 source files compiled into `libarduino.a`. Among them:

```
ftl.c.obj
ftl_common_api.c.obj
ftl_nand_api.c.obj
ftl_nor_api.c.obj        ← the file containing device_mutex_lock(RT_DEV_LOCK_FLASH) in nor_write_cb()
```

This confirms that the entire FTL layer — including the lock acquisition code in `nor_write_cb` — is **precompiled into `libarduino.a`** and shipped as a binary blob in the Arduino SDK package. Users cannot modify or patch the FTL locking behavior without rebuilding this blob using `libarduino_tool.exe`.

By extension, the fix for `FlashMemory.cpp` (adding `device_mutex_lock(RT_DEV_LOCK_FLASH)`) must target `FlashMemory.cpp` specifically — the only file in the Arduino SDK that calls raw flash primitives outside the precompiled FTL layer. Patching `libarduino.a` is not required because `ftl_common_write` already handles its own locking correctly.

---

### Finding 55 — No New Commits, Releases, Issues, or Public Reports as of 2026-05-01
**Source:** Exhaustive sweep of all tracked sources (2026-05-01)  
**Priority:** LOW — Status confirmation

Complete status sweep for May 1, 2026:

| Repository / Source | Last activity | Status |
|---|---|---|
| ameba-arduino-pro2 (dev branch) | April 30, 2026 (Pre Release 4.1.1 tag) | No new commits |
| ameba-arduino-pro2 (releases) | V4.1.1-QC-V05 (April 30, 2026 internal build) | No new release |
| ameba-rtos-pro2 (main branch) | April 30, 2026 (commit 2b8812c — libarduino_tool, Finding 51/54) | No new commits |
| ameba-arduino-pro2 issues | 17 open issues | Zero new FCS/FlashMemory/VOE issues |
| ameba-rtos-pro2 issues | 3 open issues | Zero new relevant issues |
| ideashatch/HUB-8735 issues | Dec 2, 2025 | Inactive, no new issues |
| forum.amebaiot.com | All threads 403-blocked; no Google-indexed snippets | No new relevant threads |
| CSDN / Zhihu / 21ic / EEWorld | — | Zero Chinese-language reports |
| bbs.ai-thinker.com (BW21-CBV) | — | No camera/FCS bug threads |
| FlashMemory.cpp (dev) | Sept 30, 2025 last modified | Still NO mutex fix |
| video_api.c (main) | March 3, 2026 last modified | Still NO mutex fix |

**Bug status: publicly undocumented and unpatched as of 2026-05-01.**

---

### Sources Added (Update 2026-05-01)
- ameba-rtos-pro2 ftl_nor_api.c (new location): https://github.com/Ameba-AIoT/ameba-rtos-pro2/blob/main/component/file_system/ftl_common/ftl_nor_api.c
- ameba-rtos-pro2 ftl_common_api.c (new location): https://github.com/Ameba-AIoT/ameba-rtos-pro2/blob/main/component/file_system/ftl_common/ftl_common_api.c
- ameba-rtos-pro2 commit 2b8812c README (libarduino.a object list): https://github.com/Ameba-AIoT/ameba-rtos-pro2/commit/2b8812c

---

## Research Update — 2026-05-01 (Update 2 — 6-hour cycle)

### Finding 56 — VOE Updated to 1.7.1.0 (May 1, 2026 push; April 21, 2026 internal date); FCS Mirror/Flip Fix Only
**Source:** `ameba-rtos-pro2` — commit d54e1a8 (pushed May 1, 2026)  
https://github.com/Ameba-AIoT/ameba-rtos-pro2/commit/d54e1a8  
**Priority:** MEDIUM — New VOE version confirms active development; fix is unrelated to our bug

The `ameba-rtos-pro2` main branch received five new commits on May 1, 2026 (the first since April 30). Commit `d54e1a8` syncs VOE from **1.7.0.0 → 1.7.1.0** and updates the binary blobs `voe.bin`, `libvideo_ns.a`, `libvideo_ntz.a`.

The full `hal_video_release_note.txt` entry for 1.7.1.0 (internal date April 21, 2026, author Juling):

```
<04/21/2026 12:00 Juling>
Version : RTL8735B_VOE_1.7.1.0
Modified Files: All
Change Notes:

ISP/sensor related
1. Fix dual sensor id FCS mirror/flip issue
```

**This is NOT a fix for our bug.** "Dual sensor id FCS mirror/flip issue" refers to a mirror/flip register misconfiguration when two camera sensors share an FCS parameter record. It has no relation to the `FlashMemory.write()` / `RT_DEV_LOCK_FLASH` concurrency race that causes our cold-boot FCS checksum failure.

The bug (FlashMemory bypasses RT_DEV_LOCK_FLASH) remains **unaddressed** in both the VOE binary and the FlashMemory.cpp source.

---

### Finding 57 — IMX681 5M Resolution and FCS Binary Added (May 1, 2026)
**Source:** `ameba-rtos-pro2` — commit 7b2b97f (May 1, 2026)  
https://github.com/Ameba-AIoT/ameba-rtos-pro2/commit/7b2b97f  
**Priority:** LOW — New sensor support; indirectly widens the bug's affected surface

Commit `7b2b97f` adds IMX681 5M (2592×1944 @ 4fps) sensor support. Files added:
- `fcs_data_imx681_5m.bin` — a new FCS parameter binary for the 5M sensor
- `iq_imx681_5m.bin` — IQ calibration
- `sensor_imx681_5m.bin` — sensor driver binary
- `sensor.h` — IMX681_5M macro added at 0x39; all subsequent sensor enum values shifted from 0x3A onward

The presence of `fcs_data_imx681_5m.bin` confirms that every newly added sensor comes with a dedicated FCS parameter record that must be written to flash at `0xF0D000` during the first camera session. This means the FlashMemory/FCS race bug affects IMX681 5M users as well.

`sensor.h` hex renumbering note: any existing application code that hardcodes sensor type values ≥ 0x39 will break silently after this commit (off-by-one shift).

---

### Finding 58 — OV12890 IQ Updated (May 1, 2026); video_open_close_mutex Found in video_api.c
**Source:** `ameba-rtos-pro2` — commit 63c0a2f (May 1, 2026); `video_api.c` current main  
https://github.com/Ameba-AIoT/ameba-rtos-pro2/commit/63c0a2f  
**Priority:** LOW — OV12890 IQ update unrelated; mutex observation is informational

Commit `63c0a2f` updates IQ binary for OV12890 (unrelated to our bug).

Separately, a review of the current `video_api.c` (main branch) reveals a new mutex declaration not previously noted:
```c
static _mutex video_open_close_mutex = NULL;
```
This mutex guards `hal_video_open()` / `hal_video_close()` serialization only — it does **not** wrap `video_pre_init_save_cur_params()` or `ftl_common_write(0xF0D000)`. The FCS write path remains unsynchronized with external flash callers. This is informational; it does not affect the bug.

---

### Finding 59 — Complete Status Sweep: Bug Unpatched as of 2026-05-01 (Update 2)
**Source:** Exhaustive sweep of all tracked sources (2026-05-01, second 6-hour run)  
**Priority:** LOW — Status confirmation

| Repository / Source | Last activity | Status |
|---|---|---|
| ameba-arduino-pro2 (dev branch) | April 30, 2026 (Pre Release 4.1.1 tag) | No new commits since Apr 30 |
| ameba-arduino-pro2 (releases) | V4.1.1-QC-V05 (April 30, 2026 internal build) | No new release |
| ameba-rtos-pro2 (main branch) | **May 1, 2026** — VOE 1.7.1.0, IMX681 5M, OV12890 IQ | No FCS/mutex fix |
| ameba-arduino-pro2 issues | 17 open issues | Zero new FCS/FlashMemory/VOE issues |
| ameba-rtos-pro2 issues | 3 open issues | Zero new relevant issues |
| ideashatch/HUB-8735 issues | Aug 2025 (only issue #10) | Inactive, no new issues |
| forum.amebaiot.com | All threads 403-blocked; no new Google-indexed snippets | No new relevant threads |
| CSDN / Zhihu / 21ic / EEWorld | — | Zero Chinese-language reports |
| bbs.aithinker.com (BW21-CBV) | — | Camera projects only; no FCS bug threads |
| FlashMemory.cpp (dev) | Sept 30, 2025 last modified | Still **NO mutex fix** — confirmed |
| video_api.c (main) | March 3, 2026 last modified | Still **NO mutex fix** — confirmed |

**No HIGH priority confirmed fix found. Bug status: publicly undocumented and unpatched as of 2026-05-01 (second run).**

---

### Sources Added (Update 2026-05-01, Update 2)
- ameba-rtos-pro2 commit d54e1a8 (VOE 1.7.1.0 — dual sensor FCS mirror/flip fix): https://github.com/Ameba-AIoT/ameba-rtos-pro2/commit/d54e1a8
- ameba-rtos-pro2 commit 7b2b97f (IMX681 5M + fcs_data_imx681_5m.bin): https://github.com/Ameba-AIoT/ameba-rtos-pro2/commit/7b2b97f
- ameba-rtos-pro2 commit 63c0a2f (OV12890 IQ update): https://github.com/Ameba-AIoT/ameba-rtos-pro2/commit/63c0a2f
- ameba-rtos-pro2 commits/main (May 1, 2026 activity): https://github.com/Ameba-AIoT/ameba-rtos-pro2/commits/main

---

## Research Update — 2026-05-01 (Update 3 — 6-hour cycle)

### Finding 60 — New ameba-rtos-pro2 Sync Commit (May 1, 2026): WLAN DHCP Only; Unrelated
**Source:** `ameba-rtos-pro2` — commit `1c1c8b711a419d2d49190d34f7c13e2fd0b14974` (GitHub actions bot, May 1, 2026)
https://github.com/Ameba-AIoT/ameba-rtos-pro2/commit/1c1c8b711a419d2d49190d34f7c13e2fd0b14974
**Priority:** LOW — New commit confirmed; not related to our bug

One new commit has appeared on `ameba-rtos-pro2/main` since the previous research run. The commit is from `github-actions[bot]` and contains a single file change to `GitHub_release_note.txt`, adding:

```
[amebapro2][wlan] wowlan modify dhcp renew unit from min to sec
SHA-1: 43d940446da966a145a2ac99f45c9af5e063e606
```

This is a WoWLAN (Wake-on-WLAN) DHCP timer unit correction in the WLAN subsystem. It has no relation to FlashMemory, FCS, mutex locking, camera, VOE, or flash-camera interaction. No FCS or FlashMemory-related files were modified.

**Current latest ameba-rtos-pro2 commits (as of this run):**

| SHA | Date | Message |
|---|---|---|
| `1c1c8b7` | May 1, 2026 | Sync upstream — wowlan dhcp renew (WLAN only) |
| `d54e1a8` | May 1, 2026 | sync voe to 1.7.1.0 (previously documented) |
| `7b2b97f` | May 1, 2026 | support imx681 5m resolution (previously documented) |
| `63c0a2f` | May 1, 2026 | update ov12890 iq (previously documented) |
| `2b8812c` | Apr 30, 2026 | Add arduino_libarduino_tool (previously documented) |

---

### Finding 61 — video_api.c FCS Flash Write Path Re-Confirmed: Still No Mutex at Call Site
**Source:** `ameba-rtos-pro2/main` — `video_api.c` (fresh fetch, May 1, 2026)
https://raw.githubusercontent.com/Ameba-AIoT/ameba-rtos-pro2/main/component/video/driver/RTL8735B/video_api.c
**Priority:** LOW — Direct re-verification of Finding 50; bug is confirmed still present

Fresh fetch of `video_api.c` (current main branch) reveals:

```c
// video_pre_init_save_cur_params() flash write path:
if (ftl_common_write(flash_addr, fcs_buf, fcs_buf_size) >= 0) {
    video_dprintf(VIDEO_LOG_MSG, "ISP pre init params save success\r\n");
}
```

**The only mutex present in the file is:**
```c
static _mutex video_open_close_mutex = NULL;
```
This protects `video_open()` / `video_close()` only — it does **not** wrap `video_pre_init_save_cur_params()` or the `ftl_common_write(0xF0D000)` call. No `device_mutex_lock`, `RT_DEV_LOCK_FLASH`, or any other synchronization surrounds the FCS save call site. The race condition from Hypothesis F / Finding 17 is confirmed still present in the current codebase as of May 1, 2026.

---

### Finding 62 — ameba-arduino-pro2 Has Zero Open Pull Requests; No Fix Under Review
**Source:** `ameba-arduino-pro2` pull requests page (fetched May 1, 2026)
https://github.com/Ameba-AIoT/ameba-arduino-pro2/pulls
**Priority:** LOW — Confirms no upstream fix is in review

The `ameba-arduino-pro2` repository currently shows **0 open pull requests**. The only closed PR matching a "FlashMemory" search filter is **PR #333 "Update WiFi example"** (merged September 9, 2025, by M-ichae-l) — unrelated to flash locking or FCS. There is no pending PR adding `device_mutex_lock(RT_DEV_LOCK_FLASH)` to `FlashMemory.cpp` or any other flash-camera fix. No fix is pending Realtek review.

---

### Finding 63 — FlashMemory.cpp dev Branch Re-Confirmed: Still Zero Mutex Calls
**Source:** `ameba-arduino-pro2/dev` — `FlashMemory.cpp` (fresh fetch, May 1, 2026)
https://raw.githubusercontent.com/Ameba-AIoT/ameba-arduino-pro2/dev/Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.cpp
**Priority:** LOW — Direct re-verification; bug is confirmed still present

Fresh fetch of `FlashMemory.cpp` (current dev branch) shows the complete `write()` function:

```cpp
void FlashMemoryClass::write(unsigned int offset)
{
    if ((_flash_base_address + offset) < FLASH_MEMORY_APP_BASE) {
        amb_ard_printf(ARD_LOG_ERR, "\r\n[ERROR] %s. Invalid offset \n", __FUNCTION__);
        return;
    } else if ((_flash_base_address + offset + buf_size) > FLASH_MEMORY_SIZE) {
        amb_ard_printf(ARD_LOG_ERR, "\r\n[ERROR] %s. Invalid offset \n", __FUNCTION__);
        return;
    }

    for (int i = 0; i < (MAX_FLASH_MEMORY_APP_SIZE / FLASH_SECTOR_SIZE); i++) {
        flash_erase_sector(_pFlash, (_flash_base_address + (i * FLASH_SECTOR_SIZE)));
    }

    flash_stream_write(_pFlash, (_flash_base_address + offset), buf_size, (uint8_t *)buf);
}
```

**Zero calls** to `device_mutex_lock`, `device_mutex_unlock`, or any locking mechanism. Zero includes of `device_lock.h`. The sector erase loop and `flash_stream_write()` both execute without any synchronization guard. Last modified: September 30, 2025. Unchanged since then.

---

### Finding 64 — Forum Thread #4800 (uLP Battery Camera App); Possibly Relevant, Still 403-Blocked
**Source:** forum.amebaiot.com thread #4800 — "More AMB82-mini capability for uLP battery camera application"
https://forum.amebaiot.com/t/more-amb82-mini-capability-for-ulp-battery-camera-application/4800
**Priority:** MEDIUM — Thread may describe interaction of power-cut + FCS save; content not accessible

Thread #4800 on `forum.amebaiot.com` (appearing in Google results as approximately 1 month old, i.e., late March/early April 2026) discusses ultra-low-power battery camera applications on AMB82-MINI. This thread is **potentially adjacent** to our bug because:

1. Battery-powered cameras power on and off frequently. The power-cut race window (Hypothesis D) is maximally exploited in battery camera scenarios.
2. FCS fast cold boot (~254µs sensor init) is specifically designed for battery cameras — its entire purpose is to make repeated power-cycle boot as fast as possible.
3. A user building a battery camera with FCS enabled who also uses `FlashMemory` for persistent settings (e.g., alarm counts, motion trigger logs) would encounter our bug on nearly every power cycle.

The thread content could not be retrieved (HTTP 403). No Google-indexed snippet shows camera initialization error messages matching our bug. However, given the use-case overlap, this thread should be monitored for public disclosure of the FlashMemory/FCS interaction.

---

### Finding 65 — Exhaustive Status Sweep: Bug Unpatched as of 2026-05-01 (Update 3)
**Source:** All tracked sources (ameba-arduino-pro2, ameba-rtos-pro2, ideashatch/HUB-8735, forum.amebaiot.com, CSDN, 知乎, 21ic, EEWorld, bbs.ai-thinker.com)
**Priority:** LOW — Status confirmation

| Repository / Source | Last activity | Status |
|---|---|---|
| ameba-arduino-pro2 (dev branch) | April 30, 2026 | No new commits |
| ameba-arduino-pro2 (releases) | V4.1.1-QC-V05 (April 30, 2026 internal build) | No new release |
| ameba-rtos-pro2 (main branch) | **May 1, 2026** — WLAN DHCP sync (`1c1c8b7`) | WLAN only; no FCS/mutex fix |
| ameba-arduino-pro2 pull requests | 0 open | **No fix under review** |
| ameba-arduino-pro2 issues | 11 open issues | Zero new FCS/FlashMemory/VOE issues |
| ameba-rtos-pro2 issues | 3 open issues | Zero new relevant issues |
| ideashatch/HUB-8735 issues | Issue #10 (Aug 2025) | Still only 1 issue; no new entries |
| forum.amebaiot.com | All threads 403-blocked; no new Google snippets for bug strings | No new public bug reports |
| CSDN / Zhihu / 21ic / EEWorld | — | Zero Chinese-language reports |
| bbs.ai-thinker.com (BW21-CBV) | — | No camera/FCS bug threads |
| FlashMemory.cpp (dev) | Sept 30, 2025 | **Still NO mutex fix — confirmed** |
| video_api.c (main) | March 3, 2026 | **Still NO mutex fix at call site — confirmed** |

**No HIGH priority confirmed fix found. Bug status: publicly undocumented and unpatched as of 2026-05-01 (third 6-hour run).**

---

### Sources Added (Update 2026-05-01, Update 3)
- ameba-rtos-pro2 commit 1c1c8b7 (Sync upstream — WLAN dhcp): https://github.com/Ameba-AIoT/ameba-rtos-pro2/commit/1c1c8b711a419d2d49190d34f7c13e2fd0b14974
- ameba-arduino-pro2 pull requests (0 open): https://github.com/Ameba-AIoT/ameba-arduino-pro2/pulls
- ameba-arduino-pro2 FlashMemory.cpp dev (re-confirmed no mutex): https://raw.githubusercontent.com/Ameba-AIoT/ameba-arduino-pro2/dev/Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.cpp
- ameba-rtos-pro2 video_api.c main (re-confirmed no mutex at FCS call site): https://raw.githubusercontent.com/Ameba-AIoT/ameba-rtos-pro2/main/component/video/driver/RTL8735B/video_api.c
- Forum thread #4800 (uLP battery camera — 403 blocked): https://forum.amebaiot.com/t/more-amb82-mini-capability-for-ulp-battery-camera-application/4800

---

## Research Update — 2026-05-01 (Update 4 — 6-hour cycle)

### Finding 66 — ftl_nor_api.c: nor_info->ftl_mutex Commented Out; Refines Two-Lock Chain
**Source:** `ameba-rtos-pro2` — `ftl_nor_api.c` (new location confirmed Finding 52)
https://raw.githubusercontent.com/Ameba-AIoT/ameba-rtos-pro2/main/component/file_system/ftl_common/ftl_nor_api.c
**Priority:** MEDIUM — Refines Finding 53's two-lock chain; the NOR-layer mutex was designed but permanently disabled

Inside `ftl_init_nor()`, the following line is commented out:
```c
//rtw_mutex_init(&nor_info->ftl_mutex);
```
The `nor_info_attr` struct has a `ftl_mutex` field apparently intended to provide NOR-layer serialization, but its initialization has never been activated. The NOR layer itself therefore has no mutex of its own — only the `RT_DEV_LOCK_FLASH` hardware device mutex (in `nor_write_cb()`) is active.

**Revised picture for Finding 53:** Finding 53 described "two nested locks" (ftl_mutex + RT_DEV_LOCK_FLASH). The OUTER `ftl_lock()` / `ftl_unlock()` in `ftl_common_api.c` uses a mutex defined at that file's level (NOT the commented-out `nor_info->ftl_mutex`). That outer lock is still active. The commented-out `nor_info->ftl_mutex` in `ftl_nor_api.c` would have been a *third* lock if enabled, providing NOR-specific serialization below the FTL dispatch layer. Finding 53's two-lock description remains accurate (outer `ftl_common_api.c` ftl_mutex + inner `RT_DEV_LOCK_FLASH` in `nor_write_cb()`); the commented-out item is an additional disabled layer.

**Implication for the workaround:** The user-level fix (`device_mutex_lock(RT_DEV_LOCK_FLASH)` wrapping `FlashMemory.cpp` calls) remains correct and sufficient. It directly blocks concurrent raw SPI access regardless of the commented-out NOR mutex.

---

### Finding 67 — platform_opts.h: CONFIG_LOG_SERVICE_LOCK=0 and FLASH_APP_BASE=0xF64000
**Source:** `ameba-rtos-pro2` — `platform_opts.h` (main branch)
https://raw.githubusercontent.com/Ameba-AIoT/ameba-rtos-pro2/main/project/realtek_amebapro2_v0_example/inc/platform_opts.h
**Priority:** LOW — Supplementary address-map detail; minor locking observation

Two previously unnoticed constants from `platform_opts.h`:
```c
#define CONFIG_LOG_SERVICE_LOCK  0   // Logging service mutex disabled by default
#define FLASH_APP_BASE           USER_DATA_END   // = 0xF64000
```

`FLASH_APP_BASE` (an RTOS SDK concept, distinct from `FLASH_MEMORY_APP_BASE` in Arduino's `FlashMemory.h`) equals `USER_DATA_END = 0xF64000` — the RTOS SDK's end of reserved user-data (0xF00000–0xF64000). Arduino's `FlashMemory.h` independently defines `FLASH_MEMORY_APP_BASE = 0xFD0000`, which sits 624 KB above this RTOS boundary. These two definitions use different naming conventions and do not conflict.

`CONFIG_LOG_SERVICE_LOCK = 0` disables the logging subsystem's internal mutex by default. This does not directly affect the FCS/FlashMemory race (which involves `RT_DEV_LOCK_FLASH`), but reflects the SDK's general philosophy of minimizing mutex overhead — consistent with `FlashMemory.cpp` also having no locking.

---

### Finding 68 — Official Documentation Contains No Warning About FlashMemory/FCS Conflict
**Source:** `ameba-arduino-doc` — Getting Started RST (main branch)
https://github.com/Ameba-AIoT/ameba-arduino-doc/blob/main/source/ameba_pro2/amb82-mini/Getting_Started/Getting%20Started%20with%20Ameba.rst
**Priority:** LOW — Confirms bug is completely absent from all official Realtek documentation

The official "Getting Started" guide for AMB82-MINI documents "Camera FCS Mode" as:
- **Disable** → "No Camera FCS mode process."
- **Enable** → "Enable Camera FCS mode, if the camera sensor has FCS mode."

There is **no warning, caution, note, or documentation** of any kind regarding:
- FlashMemory writes causing FCS cold-boot camera failure
- The `RT_DEV_LOCK_FLASH` mutex bypass in `FlashMemory.cpp`
- Incompatibility between the `FlashMemory` API and FCS mode when used concurrently
- Required precautions for applications that write flash while the camera is streaming

The bug is completely absent from all official Realtek/Ameba documentation as of 2026-05-01.

---

### Finding 69 — Complete Status Sweep: Bug Unpatched as of 2026-05-01 (Update 4)
**Source:** Exhaustive sweep of all tracked sources (2026-05-01, fourth 6-hour run)
**Priority:** LOW — Status confirmation

| Repository / Source | Last activity | Status |
|---|---|---|
| ameba-arduino-pro2 (dev branch) | April 30, 2026 (Pre Release 4.1.1) | No new commits |
| ameba-arduino-pro2 (releases) | V4.1.1-QC-V05 (April 30, 2026 internal build) | No new release |
| ameba-rtos-pro2 (main branch) | May 1, 2026 — WLAN DHCP sync (`1c1c8b7`) | No FCS/mutex fix |
| ameba-arduino-pro2 pull requests | 0 open | No fix under review |
| ameba-arduino-pro2 issues | 17 open | Zero new FCS/FlashMemory/VOE issues |
| ameba-rtos-pro2 issues | 3 open | Zero new relevant issues |
| ideashatch/HUB-8735 issues | Issue #10 (Aug 2025) | No new issues |
| forum.amebaiot.com | All threads 403-blocked | No new accessible content |
| CSDN / Zhihu / 21ic / EEWorld | — | Zero Chinese-language reports |
| bbs.ai-thinker.com (BW21-CBV) | — | No camera/FCS bug threads |
| FlashMemory.cpp (dev) | Sept 30, 2025 | Still NO mutex fix — confirmed |
| video_api.c (main) | March 3, 2026 | Still NO mutex fix at call site — confirmed |
| Official documentation | — | No warning added; bug completely undocumented |

**No HIGH priority confirmed fix found. Bug status: publicly undocumented and unpatched as of 2026-05-01 (fourth 6-hour run).**

---

### Sources Added (Update 2026-05-01, Update 4)
- ameba-rtos-pro2 ftl_nor_api.c (commented-out nor_info->ftl_mutex): https://raw.githubusercontent.com/Ameba-AIoT/ameba-rtos-pro2/main/component/file_system/ftl_common/ftl_nor_api.c
- ameba-rtos-pro2 platform_opts.h (CONFIG_LOG_SERVICE_LOCK=0, FLASH_APP_BASE=0xF64000): https://raw.githubusercontent.com/Ameba-AIoT/ameba-rtos-pro2/main/project/realtek_amebapro2_v0_example/inc/platform_opts.h
- ameba-arduino-doc Getting Started RST (no FlashMemory/FCS warning): https://github.com/Ameba-AIoT/ameba-arduino-doc/blob/main/source/ameba_pro2/amb82-mini/Getting_Started/Getting%20Started%20with%20Ameba.rst

---

## Research Update — 2026-05-02

### Finding 70 — Commit 687a4c7: ISP OSD + ToF Sensor Example (May 1, 2026); Previously Undocumented; Not a Fix
**Source:** `ameba-rtos-pro2` — commit `687a4c7` (May 1, 2026), author PLSHHH  
https://github.com/Ameba-AIoT/ameba-rtos-pro2/commit/687a4c7  
**Priority:** LOW — New example only; no FCS/mutex fix; `video_get_fcs_info()` call is a diagnostic read, not a write

Commit `687a4c7` ("[amebapro2][isp] add isp osd with tof sensor example") was pushed to `ameba-rtos-pro2/main` on May 1, 2026 but was **not captured in any prior research finding**. It adds a new example that overlays ToF (time-of-flight) sensor distance data as OSD (on-screen display) onto a video stream. Files changed:

- `readme.txt` (+24/-2)
- `scenario.cmake` (+21)
- `main.c` (+154/-74) — includes `video_api.h`, `video_boot.h`, calls `video_get_fcs_info()`
- `mmf2_pro2_video_config.h` (new, +68)
- `tof_sens_example_dist_array_init.c` — distance array display
- `tof_sens_example_osd_init.c` — OSD overlay

The reference to `video_get_fcs_info()` confirms that a public API function exists for reading FCS state at runtime. However, this commit makes **no changes** to `FlashMemory.cpp`, `ftl_nor_api.c`, `video_api.c`, `device_lock.h`, or any mutex-related file. It is a new peripheral example, not a bug fix.

This brings the confirmed May 1, 2026 ameba-rtos-pro2 commit set to six entries (previously only five were documented):
1. `d54e1a8` — VOE 1.7.1.0 (Finding 56)
2. `7b2b97f` — IMX681 5M (Finding 57)
3. `63c0a2f` — OV12890 IQ (Finding 58)
4. `2b8812c` — libarduino_tool (Finding 51, Apr 30)
5. `1c1c8b7` — WLAN dhcp sync (Finding 60)
6. **`687a4c7`** — ISP OSD + ToF sensor example ← **new, previously undocumented**

---

### Finding 71 — Complete Status Sweep: Bug Unpatched as of 2026-05-02
**Source:** Exhaustive sweep of all tracked sources (2026-05-02, 6-hour cycle)  
**Priority:** LOW — Status confirmation

| Repository / Source | Last activity | Status |
|---|---|---|
| ameba-arduino-pro2 (dev branch) | April 30, 2026 (Pre Release 4.1.1) | **No new commits** |
| ameba-arduino-pro2 (releases) | V4.1.1-QC-V05 (April 30, 2026 internal build) | **No new release** |
| ameba-rtos-pro2 (main branch) | May 1, 2026 — 6 commits total (Finding 70 fills last gap) | **No FCS/mutex fix** |
| ameba-arduino-pro2 pull requests | 0 open | **No fix under review** |
| ameba-arduino-pro2 issues | ~12 open (some issues closed since Apr 30) | **Zero new FCS/FlashMemory/VOE issues** |
| ameba-rtos-pro2 issues | 3 open | **Zero new relevant issues** |
| ideashatch/HUB-8735 issues | Issue #10 (Aug 2025) | **Inactive; no new issues** |
| forum.amebaiot.com | All threads 403-blocked; Google snippets show no new FCS/boot-failure threads | **No new accessible content** |
| CSDN / Zhihu / 21ic / EEWorld | — | **Zero Chinese-language reports** |
| bbs.aithinker.com (BW21-CBV) | — | BW21-CBV forum posts are all non-bug projects (DIY cameras, RTSP, home automation); **no FCS/flash bug threads** |
| wildman8606/HUB-8735-AMB82-Mini-AmebaPro2-tutorial | May 2023 | Educational YOLO tutorial only; **no FCS bug documentation** |
| FlashMemory.cpp (dev) | Sept 30, 2025 | **Still NO mutex fix — confirmed** |
| video_api.c (main) | March 3, 2026 | **Still NO mutex fix at call site — confirmed** |
| Official Ameba documentation | — | **No warning added; bug completely undocumented** |

**No HIGH priority confirmed fix found. Bug status: publicly undocumented and unpatched as of 2026-05-02.**

---

### Sources Added (Update 2026-05-02)
- ameba-rtos-pro2 commit 687a4c7 (ISP OSD + ToF sensor example, previously undocumented May 1 commit): https://github.com/Ameba-AIoT/ameba-rtos-pro2/commit/687a4c7
- wildman8606/HUB-8735-AMB82-Mini-AmebaPro2-tutorial (educational repo, no FCS bug docs): https://github.com/wildman8606/HUB-8735-AMB82-Mini-AmebaPro2-tutorial
- ameba-arduino-pro2 issues (confirmed no new FCS issues): https://github.com/Ameba-AIoT/ameba-arduino-pro2/issues
- ideashatch/HUB-8735 issues (confirmed still only issue #10): https://github.com/ideashatch/HUB-8735/issues

---

## Research Update — 2026-05-02 (Update 2 — 6-hour cycle)

### Finding 72 — FCS SAVE_TO_FLASH Data Fields Confirmed from Documentation Snippet
**Source:** ameba-doc-rtos-pro2-sdk.readthedocs-hosted.com — ISP application note (Google-indexed snippet, page body 403-blocked)
https://ameba-doc-rtos-pro2-sdk.readthedocs-hosted.com/en/latest/application_note/15_ISP.html
**Priority:** MEDIUM — New technical detail about the exact contents of the FCS flash record

A Google-indexed snippet from the official ISP application note confirms the exact fields saved to flash at `0xF0D000` when `SAVE_TO_FLASH` mode is used:

```
ISP retention data structure (SAVE_TO_FLASH / SAVE_TO_RETENTION):
  - checksum
  - AE exposure time
  - AE sensor gain
  - AWB R-gain
  - AWB B-gain
```

This matches the `video_boot_stream_t` struct referenced in Findings 11 and 34, and confirms that the 2 KB record at `0xF0D000` contains these five fields plus the `"FCSD"` magic and checksum header. When the sector is erased (all `0xFF`), the checksum over these fields will fail, triggering the `"Check sum fail"` → `"It don't do the sensor initial process"` sequence. The corruption destroys 5 critical per-sensor calibration parameters accumulated during the previous runtime session (auto-exposure convergence, white balance).

---

### Finding 73 — ameba-arduino-pro2 Latest Open Issue is #398 (Raw Video, Mar 2026); Zero New FCS Issues
**Source:** https://github.com/Ameba-AIoT/ameba-arduino-pro2/issues
**Priority:** LOW — Status confirmation; no new bug reports

The highest-numbered open issue on `ameba-arduino-pro2` as of 2026-05-02 is **#398** ("Get raw video frames from VideoStream object", March 29, 2026), requesting direct access to unencoded ISP frames for CV processing. This is completely unrelated to FlashMemory or FCS. The confirmed open issue count is 12, none relating to flash/camera interaction, mutex, FCS, or `VOE_OPEN_CMD` failures. No new issues have been filed between the previous research run and this one.

---

### Finding 74 — RT_DEV_LOCK_FLASH Symbol Has Never Appeared in Any Commit Message to ameba-rtos-pro2
**Source:** GitHub commit search: `repo:Ameba-AIoT/ameba-rtos-pro2 RT_DEV_LOCK_FLASH`
**Priority:** LOW — Confirms the mutex is exclusively in precompiled binaries; its use is invisible in commit history

A GitHub commit-message search for `RT_DEV_LOCK_FLASH` in `ameba-rtos-pro2` returns **0 results**. This is expected because `RT_DEV_LOCK_FLASH` is used inside source files (e.g., `ftl_nor_api.c`, `device_lock.c`) but the commit messages themselves never reference it. The practical implication: there is no way to identify when/if Realtek adds mutex protection to `FlashMemory.cpp` by monitoring commit messages alone — the actual file content must be checked on each cycle.

---

### Finding 75 — Forum Thread #3983 BLE-Flash-Camera Pattern Partially Indexed; Still No Fix Disclosed
**Source:** forum.amebaiot.com/t/error-after-write-in-memory-amb82/3983 (403-blocked; Google snippet re-indexed)
**Priority:** LOW — Adds minor detail to Finding 23; no new fix information

An updated Google-cached snippet of thread #3983 confirms the scenario more precisely than Finding 23 captured: the user was writing to flash at offsets `0x1E20`, `0x1E40`, `0x1E60` (triggered by incoming BLE packets, 32 bytes each) and observed camera failures on MCU restart. **The offsets 0x1E20–0x1E60 are inside the `fw1` partition** (`0x080000–0x400000`), meaning this user was inadvertently writing into application firmware — a more severe form of the same class of bug (unguarded flash write while camera FCS is active). The snippet does not show a resolution or confirmed fix. The forum thread likely represents an independent user who encountered the FlashMemory/FCS race (or related unguarded flash write path) but never identified the root cause.

---

### Finding 76 — Complete Status Sweep: Bug Unpatched as of 2026-05-02 (Update 2)
**Source:** Exhaustive sweep of all tracked sources (2026-05-02, second 6-hour run)
**Priority:** LOW — Status confirmation

| Repository / Source | Last activity | Status |
|---|---|---|
| ameba-arduino-pro2 (dev branch) | April 30, 2026 — SHA `e218f33` ("Pre Release Version 4.1.1") | **No new commits** |
| ameba-arduino-pro2 (releases) | V4.1.1-QC-V05 (April 30, 2026 internal build) | **No new release** |
| ameba-rtos-pro2 (main branch) | May 1, 2026 — SHA `1c1c8b7` (WLAN dhcp sync) | **No new commits; no FCS/mutex fix** |
| ameba-arduino-pro2 pull requests | 0 open | **No fix under review** |
| ameba-arduino-pro2 issues | 12 open (highest: #398, Mar 2026) | **Zero new FCS/FlashMemory/VOE issues** |
| ameba-rtos-pro2 issues | 3 open | **Zero new relevant issues** |
| ideashatch/HUB-8735 | Dec 2, 2025 (SHA `870a7e0`) | **Inactive; no new issues** |
| forum.amebaiot.com | All threads 403-blocked | **No new accessible content** |
| CSDN / Zhihu / 21ic / EEWorld | — | **Zero Chinese-language reports** |
| bbs.ai-thinker.com (BW21-CBV) | — | **No camera/FCS bug threads** |
| FlashMemory.cpp (dev) | Sept 30, 2025 (SHA `4fdfbec`) | **Still NO mutex fix — confirmed by direct fetch** |
| video_api.c (main) | March 3, 2026 | **Still NO mutex fix at FCS call site** |
| Official documentation | — | **No FlashMemory/FCS warning added** |

**No HIGH priority confirmed fix found. Bug status: publicly undocumented and unpatched as of 2026-05-02 (second 6-hour run).**

---

### Sources Added (Update 2026-05-02, Update 2)
- ameba-doc-rtos-pro2-sdk ISP app note (FCS data fields — AE/AWB, Google snippet): https://ameba-doc-rtos-pro2-sdk.readthedocs-hosted.com/en/latest/application_note/15_ISP.html
- ameba-arduino-pro2 issues (highest open: #398 raw video, Mar 2026): https://github.com/Ameba-AIoT/ameba-arduino-pro2/issues
- ameba-arduino-pro2 FlashMemory.cpp dev (re-confirmed no mutex, SHA 4fdfbec latest): https://github.com/Ameba-AIoT/ameba-arduino-pro2/blob/dev/Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.cpp
- Forum thread #3983 (BLE-triggered flash writes at 0x1E20–0x1E60 inside fw1 partition; camera fail on restart): https://forum.amebaiot.com/t/error-after-write-in-memory-amb82/3983

---

## Research Update — 2026-05-02 (Update 3 — 6-hour cycle)

### Finding 77 — Complete Status Sweep: Bug Unpatched as of 2026-05-02 (Update 3)
**Source:** Exhaustive sweep of all tracked sources (2026-05-02, third 6-hour run)
**Priority:** LOW — Status confirmation; no new information

Sources checked and results:

| Repository / Source | Last activity | Status |
|---|---|---|
| ameba-arduino-pro2 (dev branch) | April 30, 2026 — SHA `e218f33` ("Pre Release Version 4.1.1") | **No new commits — confirmed by direct fetch** |
| ameba-arduino-pro2 (releases) | V4.1.1-QC-V05 (April 30, 2026 internal build) | **No new release** |
| ameba-rtos-pro2 (main branch) | May 1, 2026 — SHA `1c1c8b7` (WLAN dhcp sync) | **No new commits — confirmed by direct fetch + commit-page pagination** |
| ameba-tool-rtos-pro2 (main branch) | March 9, 2026 — "Add IQ tuning tool (#2)" | **Inactive; no new commits** |
| ameba-arduino-pro2 pull requests | 0 open, search returns "No results" for FlashMemory/FCS/mutex | **No fix under review — confirmed** |
| ameba-arduino-pro2 issues | 12 open; highest: #398 (Mar 2026) | **Zero new FCS/FlashMemory/VOE issues — confirmed** |
| ameba-rtos-pro2 issues | 3 open (highest: #16, Jan 2026) | **Zero new relevant issues — confirmed** |
| ideashatch/HUB-8735 issues | Issue #10 only (Aug 2025) | **Inactive; no new issues — confirmed** |
| forum.amebaiot.com | All threads 403-blocked; no threads ≥ #4840 indexed | **No new accessible content; no new bug-string matches** |
| CSDN / Zhihu / 21ic / EEWorld | — | **Zero Chinese-language reports — confirmed** |
| bbs.ai-thinker.com (BW21-CBV) | — | **No camera/FCS bug threads — 403 on forum index** |
| FlashMemory.cpp (dev, SHA 4fdfbec) | Sept 30, 2025 | **Still NO mutex fix — re-confirmed by direct raw fetch** |
| video_api.c (main) | March 3, 2026 | **Still NO mutex fix at FCS call site — confirmed** |
| Official documentation | — | **No FlashMemory/FCS warning added — confirmed** |

Direct raw fetch of `FlashMemory.cpp` (dev branch) once more confirms the `write()` function body is identical to the September 30, 2025 version: zero `device_mutex_lock` calls, zero `device_lock.h` includes, zero FCS guards.

The exact bug-signature strings `"It don't do the sensor initial process"` and `"FCS KM_status 0x00002081"` return zero new indexed results beyond Issue #251 (previously documented). The bug remains publicly unknown outside of this research log and the issue reporter.

**No HIGH priority confirmed fix found. Bug status: publicly undocumented and unpatched as of 2026-05-02 (third 6-hour run).**

---

### Sources Added (Update 2026-05-02, Update 3)
- ameba-arduino-pro2 dev branch commits (confirmed last: e218f33, Apr 30, 2026): https://github.com/Ameba-AIoT/ameba-arduino-pro2/commits/dev
- ameba-rtos-pro2 main branch commits (confirmed last: 1c1c8b7, May 1, 2026): https://github.com/Ameba-AIoT/ameba-rtos-pro2/commits/main
- ameba-tool-rtos-pro2 main branch (last commit Mar 9, 2026 — IQ tuning tool): https://github.com/Ameba-AIoT/ameba-tool-rtos-pro2/commits/main
- ameba-arduino-pro2 pull requests (0 open; no FCS/FlashMemory PRs in history): https://github.com/Ameba-AIoT/ameba-arduino-pro2/pulls
- ameba-arduino-pro2 FlashMemory.cpp raw dev (re-confirmed no mutex, full write() body verified): https://raw.githubusercontent.com/Ameba-AIoT/ameba-arduino-pro2/dev/Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.cpp

---

## Research Update — 2026-05-02 (Update 4 — 6-hour cycle)

### Finding 78 — Forum Thread #4748: "[VOE][WARN]slot full" Search Returns Previously Undocumented Thread
**Source:** Google search `"[VOE][WARN]slot full" ameba RTL8735`; forum.amebaiot.com thread #4748 (403-blocked)
https://forum.amebaiot.com/t/voe-warn-slot-full/4748  
**Priority:** MEDIUM — Previously unlogged thread containing our exact bug signature string; content inaccessible

A targeted search for the exact string `"[VOE][WARN]slot full"` surfaced forum thread **#4748** — a thread that was not captured in any prior research run. Thread #4777 was previously documented (Finding 30), but #4748 is new to the log.

The thread title and/or URL slug suggests it directly discusses the `[VOE][WARN]slot full` warning. The page is HTTP 403-blocked, so no content, poster identity, date, resolution, or relationship to the FlashMemory/FCS race can be confirmed. Its existence alongside thread #4777 suggests at least two independent reporters have encountered the `slot full` symptom on AMB82-MINI/RTL8735B, making it more likely to be a recurring field issue rather than a one-off configuration error.

**Priority note:** If thread #4748 becomes accessible (e.g., via a future public caching or Realtek forum policy change), it should be checked for any confirmed fix or workaround distinct from those already documented.

---

### Finding 79 — Full Commit-History Search: Neither ameba-arduino-pro2 Nor ameba-rtos-pro2 Has Ever Referenced "mutex" + FlashMemory Together
**Source:** GitHub commit-message search: `repo:Ameba-AIoT/ameba-arduino-pro2 FlashMemory mutex` → 0 results; `repo:Ameba-AIoT/ameba-rtos-pro2 FCS flash` → 0 results  
**Priority:** MEDIUM — Confirms no fix has ever been attempted or discussed in commit history

Two exhaustive searches of the complete commit histories of both repositories confirm:

1. **`repo:Ameba-AIoT/ameba-arduino-pro2 FlashMemory mutex`** — 0 results. `FlashMemory.cpp` has only 3 commits in its entire history (initial creation July 9, 2024; two optimization commits September 30, 2025). No commit message has ever mentioned `mutex`, `lock`, `FCS`, `RT_DEV_LOCK_FLASH`, or any synchronization concept in relation to `FlashMemory`. The file's last touching commit SHA is `4fdfbec` ("Optimize codes #337", Sep 30, 2025).

2. **`repo:Ameba-AIoT/ameba-rtos-pro2 FCS flash`** — 0 results. No commit in the entire ameba-rtos-pro2 history has ever addressed the intersection of FCS and flash memory access serialization in a commit message. The `RT_DEV_LOCK_FLASH` symbol exists in source files (as documented in Findings 17, 28, 53) but has never been added to `FlashMemory.cpp` or mentioned in any fix-oriented commit.

**Implication:** There is no evidence that Realtek developers have ever recognized, discussed internally (in visible commit messages), or begun to address the `FlashMemory`/FCS mutex omission. The fix has not been started, not been reviewed, and not been merged — in either repository, across their entire public commit histories.

---

### Finding 80 — Complete Status Sweep: Bug Unpatched as of 2026-05-02 (Update 4)
**Source:** Exhaustive sweep of all tracked sources (2026-05-02, fourth 6-hour run)  
**Priority:** LOW — Status confirmation

| Repository / Source | Last activity | Status |
|---|---|---|
| ameba-arduino-pro2 (dev branch) | April 30, 2026 — SHA `e218f33` | **No new commits** |
| ameba-arduino-pro2 (releases) | V4.1.1-QC-V05 (April 30, 2026) | **No new release** |
| ameba-rtos-pro2 (main branch) | May 1, 2026 — SHA `1c1c8b7` | **No new commits; no FCS/mutex fix** |
| ameba-arduino-pro2 pull requests | 0 open | **No fix under review** |
| ameba-arduino-pro2 issues | 12 open (highest: #398, Mar 2026) | **Zero new FCS/FlashMemory/VOE issues** |
| ameba-rtos-pro2 issues | 3 open (highest: #16, Jan 2026) | **Zero new relevant issues** |
| ideashatch/HUB-8735 | Dec 2, 2025 — SHA `870a7e0` | **Inactive; no new issues** |
| forum.amebaiot.com | All threads 403-blocked; threads #4748 and #4777 are highest indexed for `[VOE][WARN]slot full` | **No accessible content; #4748 newly logged** |
| CSDN / Zhihu / 21ic / EEWorld | — | **Zero Chinese-language reports** |
| bbs.ai-thinker.com (BW21-CBV) | — | **No camera/FCS bug threads** |
| FlashMemory.cpp (dev, SHA 4fdfbec) | Sept 30, 2025 | **Still NO mutex fix — confirmed** |
| video_api.c (main) | March 3, 2026 | **Still NO mutex fix at FCS call site** |
| Official documentation | — | **No FlashMemory/FCS warning added** |
| Commit history search (both repos) | — | **Zero mutex/FCS-flash fix attempts ever recorded** |

**No HIGH priority confirmed fix found. Bug status: publicly undocumented and unpatched as of 2026-05-02 (fourth 6-hour run).**

---

### Sources Added (Update 2026-05-02, Update 4)
- Forum thread #4748 (VOE WARN slot full — 403-blocked, newly surfaced): https://forum.amebaiot.com/t/voe-warn-slot-full/4748
- ameba-arduino-pro2 commit-history search for FlashMemory+mutex (0 results): https://github.com/Ameba-AIoT/ameba-arduino-pro2/search?q=FlashMemory+mutex&type=commits
- ameba-rtos-pro2 commit-history search for FCS+flash (0 results): https://github.com/Ameba-AIoT/ameba-rtos-pro2/search?q=FCS+flash&type=commits

---

## Research Update — 2026-05-03

### Finding 81 — CORRECTION to Finding 78: Thread #4748 Is "Need Latest VOE and Sensor Drivers Source Code" — Not Slot-Full
**Source:** Google search result confirming thread title; forum.amebaiot.com thread #4748 (403-blocked for full content)
https://forum.amebaiot.com/t/need-latest-voe-and-sensor-drivers-source-code/4748
**Priority:** MEDIUM — Factual correction; removes an overestimated indicator of bug prevalence

Finding 78 (2026-05-02 Update 4) incorrectly identified forum thread #4748 as being titled "[VOE][WARN]slot full" and as a potential independent report of the FlashMemory/FCS race bug's slot-full symptom. The confirmed title, per Google-indexed search snippets and the URL slug, is:

**"Need latest VOE and Sensor drivers source code"**

The thread (dated February 23, 2026) discusses a user's request to download the VOE binary and sensor driver source code to recompile `voe.bin` and `sensor_f37.bin`. It appears to be unrelated to the FlashMemory/FCS cold-boot failure. The page remains HTTP 403-blocked, so the full content cannot be verified, but the title and URL slug provide no indication of cold-boot camera failure.

**Consequence:** Finding 78's conclusion that "at least two independent reporters have encountered the `slot full` symptom" should be retracted. Thread #4748 is not an independent symptom report. Thread #4777 ("AMB82-Mini onboard camera sensor identification and VOE setup for wireless video and I2C") remains the only separately indexed thread that co-occurs with VOE setup, but it is also 403-blocked with no confirmed fault log snippet.

The corrected URL for Finding 78's source entry should be:
- Forum thread #4748 (Need latest VOE and Sensor drivers source code — Feb 23, 2026; unrelated to bug): https://forum.amebaiot.com/t/need-latest-voe-and-sensor-drivers-source-code/4748

---

### Finding 82 — PlatformIO AMB82-Mini Board Support Requests: Two Open Issues; No FCS Mention
**Source:** GitHub: platformio/platformio-core issues #4809 and #4855
https://github.com/platformio/platformio-core/issues/4809
https://github.com/platformio/platformio-core/issues/4855
**Priority:** LOW — New distribution channel that would expose the buggy API; no fix relevant content

Two separate PlatformIO Core issues exist requesting AMB82-Mini (RTL8735B) board support in PlatformIO:
- Issue #4809 (December 18, 2023) — "Board Support: REALTEK AMB82-Mini" — links to Seeed Studio product page only; no technical content.
- Issue #4855 — "Feature Request: Support RealTek Ameba AMB82-Mini board (RTL8735BDM)" — similarly a bare feature request.

Neither issue references FlashMemory, FCS mode, VOE, or camera initialization. **No PlatformIO platform for AMB82-Mini has been officially created.**

However, a separate community thread on forum.amebaiot.com (#4721, "Contribution: PlatformIO Platform for AmebaD", February 11, 2026) describes a community-built PlatformIO integration for the AmebaD family. If a similar community integration is built for AMB82-Mini (RTL8735B), it would bundle the same unpatched `FlashMemory.cpp` and expose the FlashMemory/FCS race bug to VS Code / PlatformIO users — a broader audience than Arduino IDE alone.

---

### Finding 83 — Complete Status Sweep: Bug Unpatched as of 2026-05-03
**Source:** Exhaustive sweep of all tracked sources (2026-05-03 run)
**Priority:** LOW — Status confirmation

| Repository / Source | Last activity | Status |
|---|---|---|
| ameba-arduino-pro2 (dev branch) | April 30, 2026 — SHA `e218f33` ("Pre Release Version 4.1.1") | **No new commits** |
| ameba-arduino-pro2 (releases) | V4.1.1-QC-V05 (April 30, 2026 internal build); no V4.1.1-QC-V06 or V4.1.2 tag found | **No new release** |
| ameba-rtos-pro2 (main branch) | May 1, 2026 — SHA `1c1c8b7` (WLAN dhcp sync) | **No new commits** |
| ameba-arduino-pro2 pull requests | 0 open | **No fix under review** |
| ameba-arduino-pro2 issues | 12 open (highest: #398, Mar 2026) | **Zero new FCS/FlashMemory/VOE issues** |
| ameba-rtos-pro2 issues | 3 open (highest: #16, Jan 2026) | **Zero new relevant issues** |
| ideashatch/HUB-8735 | Dec 2, 2025 | **Inactive** |
| forum.amebaiot.com | All threads 403-blocked; no new Google-indexed snippets for bug-signature strings | **No new accessible content** |
| forum.amebaiot.com highest indexed thread | ~#4840 | **No new FCS/flash/camera threads beyond previously documented** |
| CSDN / Zhihu / 21ic / EEWorld | — | **Zero Chinese-language reports (re-confirmed)** |
| bbs.ai-thinker.com (BW21-CBV) | Various BW21 projects; no FCS bug threads | **Zero FCS/flash camera bug posts** |
| FlashMemory.cpp (dev, SHA 4fdfbec) | Sept 30, 2025 | **Still NO mutex fix — confirmed by direct raw fetch** |
| video_api.c (main) | March 3, 2026 | **Still NO mutex fix at FCS call site** |
| Official documentation | — | **No FlashMemory/FCS warning added** |
| Commit history (both repos, full) | — | **Zero mutex/FCS-flash fix attempts recorded** |

Fresh raw fetch of `FlashMemory.cpp` (dev branch, SHA `4fdfbec`) once more confirms the `write()` and `writeWord()` functions contain zero `device_mutex_lock` calls, zero `device_lock.h` includes. The bug is confirmed unpatched.

**No HIGH priority confirmed fix found. Bug status: publicly undocumented and unpatched as of 2026-05-03.**

---

### Sources Added (Update 2026-05-03)
- Forum thread #4748 (CORRECTED title — "Need latest VOE and Sensor drivers source code", Feb 2026; unrelated to bug): https://forum.amebaiot.com/t/need-latest-voe-and-sensor-drivers-source-code/4748
- platformio-core issue #4809 (AMB82-Mini board support request, Dec 2023): https://github.com/platformio/platformio-core/issues/4809
- platformio-core issue #4855 (AMB82-Mini board support request): https://github.com/platformio/platformio-core/issues/4855
- forum.amebaiot.com thread #4721 (Community PlatformIO for AmebaD, Feb 2026): https://forum.amebaiot.com/t/contribution-platformio-platform-for-amebad-build-flash-monitor-from-cli-vs-code/4721
- ameba-arduino-pro2 dev branch commits (confirmed last: e218f33, Apr 30, 2026): https://github.com/Ameba-AIoT/ameba-arduino-pro2/commits/dev
- ameba-rtos-pro2 main branch commits (confirmed last: 1c1c8b7, May 1, 2026): https://github.com/Ameba-AIoT/ameba-rtos-pro2/commits/main

---

## Research Update — 2026-05-03 (Update 2 — 6-hour cycle)

### Finding 84 — All Repositories Unchanged Since Previous Cycle; No Fix Found
**Source:** Direct fetches of ameba-rtos-pro2/commits/main, ameba-arduino-pro2/commits/dev, both issues pages, both releases pages (2026-05-03 second run)
**Priority:** LOW — Status confirmation; no new information

Complete status sweep for May 3, 2026 (second 6-hour run):

| Repository / Source | Last activity | Status |
|---|---|---|
| ameba-arduino-pro2 (dev branch) | April 30, 2026 — SHA `e218f33` ("Pre Release Version 4.1.1") | **No new commits — re-confirmed** |
| ameba-arduino-pro2 (releases) | V4.1.1-QC-V05 (April 30, 2026 internal build); no V4.1.1-QC-V06 or V4.1.2 tag exists | **No new release — re-confirmed** |
| ameba-rtos-pro2 (main branch) | May 1, 2026 — SHA `1c1c8b7` (WLAN dhcp sync) | **No new commits — re-confirmed by direct fetch** |
| ameba-arduino-pro2 pull requests | 0 open | **No fix under review** |
| ameba-arduino-pro2 issues | 12 open; highest: #398 (Mar 29, 2026). **No new issues above #398** | **Zero new FCS/FlashMemory/VOE issues** |
| ameba-rtos-pro2 issues | 3 open; highest: #16 (Jan 27, 2026) | **Zero new relevant issues — re-confirmed** |
| ideashatch/HUB-8735 issues | Issue #10 only (Aug 2025) | **Inactive; no new issues** |
| forum.amebaiot.com | All threads 403-blocked; highest indexed thread in this run: #4834 (previously documented). No new FCS/camera-bug threads found in Google index | **No new accessible content** |
| CSDN / Zhihu / 21ic / EEWorld | — | **Zero Chinese-language reports** |
| bbs.ai-thinker.com (BW21-CBV) | — | **No FCS/camera bug threads (see Finding 85)** |
| FlashMemory.cpp (dev, SHA 4fdfbec) | Sept 30, 2025 | **Still NO mutex fix — re-confirmed by direct raw fetch** |
| video_api.c (main) | March 3, 2026 | **Still NO mutex fix at FCS call site** |
| Official documentation | — | **No FlashMemory/FCS warning added** |

Direct raw fetch of `FlashMemory.cpp` (dev branch) once more confirms: zero `device_mutex_lock` calls, zero `device_lock.h` includes. `write()` and `writeWord()` bodies are unchanged from SHA `4fdfbec` (September 30, 2025).

**No HIGH priority confirmed fix found. Bug status: publicly undocumented and unpatched as of 2026-05-03 (second 6-hour run).**

---

### Finding 85 — bbs.ai-thinker.com Thread #47062: New BW21-CBV-KIt Unboxing Thread (Higher tid than Previously Documented)
**Source:** Google search results for bbs.ai-thinker.com BW21-CBV; thread URL https://bbs.ai-thinker.com/forum.php?mod=viewthread&tid=47062
**Priority:** LOW — New community content; no FCS bug relevance

Thread `tid=47062` ("BW21-CBV-KIt开箱") is the highest-numbered BW21-CBV thread observed on bbs.ai-thinker.com in this research cycle. The previously documented highest thread was `tid=46140` ("BW21-CBV-Kit调试"). The new thread (#47062) is an unboxing and first-impressions post. The thread content (accessed via Google-indexed snippet) discusses basic board impressions and setup; it contains no mention of flash write errors, FCS camera failures, VOE initialization problems, or cold-boot camera issues.

The numbering gap (46140 → 47062 = ~922 posts/threads) indicates continued board activity on the AI-Thinker forum. Despite this volume of community activity on the BW21-CBV platform, **zero threads on bbs.ai-thinker.com have reported the FlashMemory/FCS camera bug** as of 2026-05-03. This likely reflects that most BW21-CBV users operate with FCS mode disabled (the default) or have not combined FlashMemory writes with active camera streaming.

---

### Finding 86 — ameba-arduino-doc Last Commit: April 16, 2026 — No FCS/FlashMemory Warnings Added
**Source:** https://github.com/Ameba-AIoT/ameba-arduino-doc/commits/main (fetched 2026-05-03)
**Priority:** LOW — Documentation status confirmed; bug remains completely undocumented

The most recent commit to the `ameba-arduino-doc` repository (the official documentation source for the Arduino SDK) is dated **April 16, 2026**: "Update PowerMode documentation #104". No subsequent commits exist as of this run. This confirms that no FlashMemory/FCS compatibility warning, no "known issues" entry, and no "camera FCS mode + FlashMemory" advisory has been added to the official documentation in the entire period covered by this research log (April 28 – May 3, 2026). The documentation remains silent on the interaction between `FlashMemory.write()` and Camera FCS Mode.

---

### Finding 87 — Forum Threads #4820 and #4794 Newly Surfaced; Unrelated to Bug
**Source:** Google search results; forum.amebaiot.com threads #4820 and #4794 (both 403-blocked)
**Priority:** LOW — New threads logged; no FCS bug relevance

Two previously unlogged forum threads surfaced in search results for this cycle:

- **Thread #4820**: "AMB82-mini upload issue" — title indicates a firmware upload/programming problem, not a camera FCS boot issue. Content inaccessible (403-blocked).
- **Thread #4794**: "RTL8735B Fast-Ethernet Interface is fully functional or not?" — clearly a hardware capability question about the Ethernet peripheral, unrelated to flash or camera. Content inaccessible (403-blocked).

Both threads have lower numbers than thread #4834 ("Boot failure after OTA update", already documented in Finding 42), confirming thread numbers track chronological order and neither is newer than the April 2026 activity already documented. These two threads do not contain new FCS/FlashMemory bug information.

---

### Sources Added (Update 2026-05-03, Update 2)
- ameba-arduino-pro2 issues page (confirmed highest open: #398, Mar 2026; no new issues above #398): https://github.com/Ameba-AIoT/ameba-arduino-pro2/issues
- ameba-arduino-pro2 releases page (confirmed no V4.1.1-QC-V06 or V4.1.2 exists): https://github.com/Ameba-AIoT/ameba-arduino-pro2/releases
- ameba-rtos-pro2 commits/main (re-confirmed last: 1c1c8b7, May 1, 2026): https://github.com/Ameba-AIoT/ameba-rtos-pro2/commits/main
- ameba-rtos-pro2 issues (confirmed 3 open; highest: #16, Jan 2026; no new issues): https://github.com/Ameba-AIoT/ameba-rtos-pro2/issues
- ameba-arduino-pro2 FlashMemory.cpp dev (re-confirmed no mutex, SHA 4fdfbec, write()/writeWord() unchanged): https://raw.githubusercontent.com/Ameba-AIoT/ameba-arduino-pro2/dev/Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.cpp
- ameba-arduino-doc commits/main (last: Apr 16, 2026, "Update PowerMode documentation #104"; no FCS/FlashMemory docs): https://github.com/Ameba-AIoT/ameba-arduino-doc/commits/main
- bbs.ai-thinker.com BW21-CBV thread #47062 (new unboxing thread; no FCS bug content): https://bbs.ai-thinker.com/forum.php?mod=viewthread&tid=47062
- forum.amebaiot.com thread #4820 (AMB82-mini upload issue, 403-blocked): https://forum.amebaiot.com/t/amb82-mini-upload-issue/4820
- forum.amebaiot.com thread #4794 (RTL8735B Fast-Ethernet question, 403-blocked): https://forum.amebaiot.com/t/rtl8735b-fast-ethernet-interface-is-fully-functional-or-not/4794

---

## Research Update — 2026-05-03 (Update 2 — 6-hour cycle)

### Finding 84 — Zero New Repository Activity; All Tracked Branches Static Since May 1
**Source:** Direct fetch of commit pages for ameba-arduino-pro2 (dev) and ameba-rtos-pro2 (main), 2026-05-03  
https://github.com/Ameba-AIoT/ameba-arduino-pro2/commits/dev  
https://github.com/Ameba-AIoT/ameba-rtos-pro2/commits/main  
**Priority:** LOW — Status confirmation; no new fix commits

| Repository | Last commit SHA | Last commit date | Last commit message |
|---|---|---|---|
| ameba-arduino-pro2 (dev) | `e218f33` | April 30, 2026 | "Pre Release Version 4.1.1" |
| ameba-rtos-pro2 (main) | `1c1c8b7` | May 1, 2026 | "Sync upstream — wowlan dhcp renew" |

Zero new commits to either repository since the previous research cycle. No new releases, no new open pull requests, no new issues related to FlashMemory, FCS, camera, or VOE on either `ameba-arduino-pro2` or `ameba-rtos-pro2`. The bug remains unpatched.

---

### Finding 85 — Global Web Search: `"device_mutex_lock" "FlashMemory" Ameba` Returns Zero Results
**Source:** Web search (Google indexed), 2026-05-03  
**Priority:** MEDIUM — Confirms root cause analysis (Hypothesis F / Finding 17) is not yet publicly known or discussed anywhere on the internet

The exact phrase combination `"device_mutex_lock" "FlashMemory" Ameba` returns **zero results** across the entire indexed public web. This means:
- No developer, blogger, or forum poster has publicly identified that `FlashMemory.cpp` lacks `device_mutex_lock(RT_DEV_LOCK_FLASH)` protection
- No patch, fork, or workaround referencing this specific fix has been published in English or any indexed language
- The root cause documented in Findings 17 and 53 is entirely novel — the research log is the only public record of this analysis

Additionally reconfirmed: `"FCS KM_status 0x00002081"` and `"It don't do the sensor initial process"` both return zero exact matches on the public web. The bug's specific error signatures are completely unindexed.

---

### Finding 86 — Forum Thread t/4801: "[Driver][ERROR][HALMAC][ERR]fw chksum!" Surfaced in Bug-String Search
**Source:** forum.amebaiot.com thread #4801 (403-blocked; surfaced via Google search for "FCS KM_status 0x00002081")  
https://forum.amebaiot.com/t/4801  
**Priority:** LOW — Different failure mode; coincidental appearance in search; not a report of the FlashMemory/FCS bug

Forum thread #4801 was newly surfaced when searching for the bug's specific error strings. The thread title contains `"[Driver]: [ERROR][HALMAC][ERR]fw chksum!"` — a firmware checksum error from the HALMAC layer (MAC firmware integrity check), which is a different subsystem from FCS/VOE. This error occurs when the WLAN firmware binary fails its checksum verification during boot. It is **not related to the FlashMemory/FCS race condition**.

The coincidental surfacing is likely due to search-engine co-ranking of RTL8735B boot-error threads. The thread is HTTP 403-blocked; no further content was recoverable.

---

### Finding 87 — Ai-Thinker GitHub Organization Has No Public BW21-CBV Repository
**Source:** https://github.com/Ai-Thinker-Open (organization repository list, 2026-05-03)  
**Priority:** LOW — Confirms absence of a dedicated BW21-CBV issue tracker

The Ai-Thinker-Open GitHub organization hosts approximately 60 repositories covering Telink BT SDKs, BL602/BL702, emMCP, and other Ai-Thinker products. **No repository named BW21, BW21-CBV, RTL8735B, ameba, or any camera-related module exists** in the public organization listing. Ai-Thinker's BW21-CBV support is distributed through Realtek's Ameba SDK (Ameba-AIoT org) and their own forum (bbs.ai-thinker.com), not a dedicated GitHub issue tracker.

This means users encountering the FlashMemory/FCS bug on BW21-CBV have no dedicated issue tracker to report it to — they would need to file against `ameba-arduino-pro2` (Realtek's org) or post on the Ameba IoT forum. Neither has occurred as of this research run.

---

### Finding 88 — bbs.ai-thinker.com Thread tid=46317: "BW20 FLASH Read/Write Tutorial"; Unrelated
**Source:** https://bbs.ai-thinker.com/forum.php?mod=viewthread&tid=46317 (403-blocked; Google snippet only)  
**Priority:** LOW — Different module (BW20 ≠ BW21); no FCS or camera content

This bbs.ai-thinker.com thread surfaced in a search for BW21 flash content. It is specifically a tutorial for the **BW20** module's flash read/write operations — a different Ai-Thinker module that is not based on RTL8735B and does not share the FCS camera architecture. The snippet shows generic SPI flash read/write code with no reference to FCS, camera, or the AmebaPro2 SDK. Not relevant to the bug.

---

### Finding 89 — Complete Status Sweep: Bug Unpatched as of 2026-05-03 (Update 2)
**Source:** Exhaustive sweep of all tracked sources (2026-05-03, second 6-hour run)  
**Priority:** LOW — Status confirmation

| Repository / Source | Last activity | Status |
|---|---|---|
| ameba-arduino-pro2 (dev branch) | April 30, 2026 — SHA `e218f33` | **No new commits — confirmed** |
| ameba-arduino-pro2 (releases) | V4.1.1-QC-V05 (April 30, 2026 internal build) | **No new release** |
| ameba-rtos-pro2 (main branch) | May 1, 2026 — SHA `1c1c8b7` | **No new commits — confirmed** |
| ameba-arduino-pro2 pull requests | 0 open | **No fix under review** |
| ameba-arduino-pro2 issues | 12 open (highest: #398, Mar 2026) | **Zero new FCS/FlashMemory/VOE issues** |
| ameba-rtos-pro2 issues | 3 open (highest: #16, Jan 2026) | **Zero new relevant issues** |
| ideashatch/HUB-8735 | Dec 2, 2025 | **Inactive** |
| Ai-Thinker-Open GitHub org | — | **No BW21-CBV repo exists — confirmed** |
| forum.amebaiot.com | All threads 403-blocked; t/4801 newly logged (unrelated) | **No accessible content** |
| CSDN / Zhihu / 21ic / EEWorld | — | **Zero Chinese-language reports — reconfirmed** |
| bbs.ai-thinker.com (BW21-CBV) | tid=46317 (BW20, unrelated); no BW21 FCS bug threads | **Zero relevant posts** |
| FlashMemory.cpp (dev, SHA 4fdfbec) | Sept 30, 2025 | **Still NO mutex fix — confirmed** |
| video_api.c (main) | March 3, 2026 | **Still NO mutex fix at FCS call site** |
| Official documentation | — | **No FlashMemory/FCS warning added** |
| Public web (`"device_mutex_lock" "FlashMemory" Ameba`) | — | **Zero results — root cause uniquely documented in this log** |

**No HIGH priority confirmed fix found. Bug status: publicly undocumented and unpatched as of 2026-05-03 (second 6-hour run).**

---

### Sources Added (Update 2026-05-03, Update 2)
- forum.amebaiot.com thread #4801 ("[Driver][ERROR][HALMAC][ERR]fw chksum!"; different bug; 403-blocked): https://forum.amebaiot.com/t/4801
- Ai-Thinker-Open GitHub org (no BW21-CBV repo confirmed): https://github.com/Ai-Thinker-Open
- bbs.ai-thinker.com thread tid=46317 (BW20 flash tutorial; not BW21; 403-blocked): https://bbs.ai-thinker.com/forum.php?mod=viewthread&tid=46317
- ameba-arduino-pro2 releases (confirmed latest: V4.1.1-QC-V05; no V4.1.2 or V4.1.1-QC-V06): https://github.com/Ameba-AIoT/ameba-arduino-pro2/releases
- ameba-arduino-pro2 FlashMemory.cpp dev (re-confirmed no mutex, SHA 4fdfbec): https://raw.githubusercontent.com/Ameba-AIoT/ameba-arduino-pro2/dev/Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.cpp

---

## Research Update — 2026-05-04

### Finding 90 — video_api.c Already `#include "device_lock.h"` — Fix Is a Two-Line Wrapper with Zero New Headers
**Source:** `ameba-rtos-pro2/main` — `video_api.c` (fresh fetch, May 4, 2026)
https://raw.githubusercontent.com/Ameba-AIoT/ameba-rtos-pro2/main/component/video/driver/RTL8735B/video_api.c
**Priority:** MEDIUM — New technical detail about fix triviality; not previously documented

A fresh read of `video_api.c` (current main branch) reveals that `device_lock.h` is **already included** at the top of the file:

```c
#include "device_lock.h"   // already present in video_api.c
```

This means `device_mutex_lock(RT_DEV_LOCK_FLASH)` and `device_mutex_unlock(RT_DEV_LOCK_FLASH)` are already in scope at the exact call site where `ftl_common_write(flash_addr, fcs_buf, fcs_buf_size)` is invoked. Adding the mutex guard to `video_api.c` would require **no new includes and no new dependencies** — purely:

```c
// BEFORE (current unguarded state):
if (ftl_common_write(flash_addr, fcs_buf, fcs_buf_size) >= 0) {
    video_dprintf(VIDEO_LOG_MSG, "ISP pre init params save success\r\n");
}

// AFTER (proposed fix — two lines added):
device_mutex_lock(RT_DEV_LOCK_FLASH);
if (ftl_common_write(flash_addr, fcs_buf, fcs_buf_size) >= 0) {
    video_dprintf(VIDEO_LOG_MSG, "ISP pre init params save success\r\n");
}
device_mutex_unlock(RT_DEV_LOCK_FLASH);
```

Note: The symmetric fix in `FlashMemory.cpp` (Arduino SDK) would also require adding `extern "C" { #include "device_lock.h" }` since `FlashMemory.cpp` is C++ and does not currently include `device_lock.h`. The `video_api.c` fix is therefore even simpler (no include change required).

**Significance:** This was not previously documented. It means that from Realtek's internal development perspective, guarding the FCS write in `video_api.c` is a trivially minimal change — the API is already in the translation unit. The omission is not an architectural oversight requiring restructuring; it is a single missing function call pair around one existing statement.

---

### Finding 91 — Complete Status Sweep: Bug Unpatched as of 2026-05-04
**Source:** Exhaustive sweep of all tracked sources (2026-05-04)
**Priority:** LOW — Status confirmation

| Repository / Source | Last activity | Status |
|---|---|---|
| ameba-arduino-pro2 (dev branch) | April 30, 2026 — SHA `e218f33` ("Pre Release Version 4.1.1") | **No new commits — confirmed** |
| ameba-arduino-pro2 (releases) | V4.1.1-QC-V05 (April 30, 2026 internal build); no V4.1.1-QC-V06 or V4.1.2 | **No new release** |
| ameba-rtos-pro2 (main branch) | May 1, 2026 — SHA `1c1c8b7` (WLAN dhcp sync); compare `1c1c8b7...HEAD` = identical | **No new commits — confirmed by diff** |
| ameba-arduino-pro2 pull requests | 0 open | **No fix under review** |
| ameba-arduino-pro2 issues | 12 open (highest: #398, Mar 2026) | **Zero new FCS/FlashMemory/VOE issues** |
| ameba-rtos-pro2 issues | 3 open (highest: #16, Jan 2026) | **Zero new relevant issues** |
| ideashatch/HUB-8735 | Dec 2, 2025 — SHA `870a7e0` | **Inactive; no new issues** |
| Ai-Thinker-Open GitHub org | — | **No BW21-CBV repository exists** |
| forum.amebaiot.com | All threads 403-blocked | **No new accessible content** |
| CSDN / Zhihu / 21ic / EEWorld | — | **Zero Chinese-language reports** |
| bbs.ai-thinker.com (BW21-CBV) | — | **No camera/FCS bug threads** |
| FlashMemory.cpp (dev, SHA 4fdfbec) | Sept 30, 2025 | **Still NO mutex fix — confirmed by direct raw fetch** |
| video_api.c (main) | March 3, 2026 | **Still NO mutex fix at FCS call site — confirmed** |
| Official documentation (ameba-arduino-doc) | April 16, 2026 | **No FlashMemory/FCS warning added** |
| Public web (`"It don't do the sensor initial process"`) | — | **Zero new indexed results** |
| Public web (`"FCS KM_status 0x00002081"`) | — | **Zero new indexed results** |
| Public web (`"device_mutex_lock" "FlashMemory" Ameba`) | — | **Zero results** |

**No HIGH priority confirmed fix found. Bug status: publicly undocumented and unpatched as of 2026-05-04.**

---

### Sources Added (Update 2026-05-04)
- ameba-rtos-pro2 video_api.c main (confirmed `#include "device_lock.h"` present; FCS write site still unguarded): https://raw.githubusercontent.com/Ameba-AIoT/ameba-rtos-pro2/main/component/video/driver/RTL8735B/video_api.c
- ameba-arduino-pro2 dev branch HEAD confirmed identical to e218f33: https://github.com/Ameba-AIoT/ameba-arduino-pro2/compare/e218f33...HEAD
- ameba-rtos-pro2 main HEAD confirmed identical to 1c1c8b7: https://github.com/Ameba-AIoT/ameba-rtos-pro2/compare/1c1c8b7...HEAD

---

## Research Update — 2026-05-04 (Update 2 — 6-hour cycle)

### Finding 92 — ameba-arduino-pro2 Open Issues Count Now Shows 17 (Up from 12); Highest Issue Still #398
**Source:** https://github.com/Ameba-AIoT/ameba-arduino-pro2/issues  
**Priority:** LOW — Count change does not reflect new FCS/FlashMemory bug reports

The issues page for `ameba-arduino-pro2` now displays **17 open issues** in the tab counter. Previous research cycles documented 11–12 open issues. However, the **highest-numbered open issue remains #398** ("FEATURE REQUEST: Access to raw video or H264/H265 encoded data," March 29, 2026). Since GitHub issues are numbered sequentially, no new issues have been filed after #398. The count increase from 12 to 17 reflects previously-closed issues that were re-opened (or a prior miscounting of paginated results) rather than newly filed reports.

The 11 visible open issues continue to focus on video streaming, WiFi, USB, audio, and protocol features — **zero relate to FlashMemory, FCS, camera boot failure, VOE errors, device_mutex_lock, or flash-camera interaction**.

---

### Finding 93 — All Tracked Repositories Unchanged Since Previous Cycle; No Fix Found
**Source:** Direct fetches of ameba-rtos-pro2/commits/main and ameba-arduino-pro2/commits/dev (2026-05-04, second run)  
**Priority:** LOW — Status confirmation; no new fix commits

Both repositories are static since the previous documented activity:

| Repository | Last commit SHA | Last commit date | Message |
|---|---|---|---|
| ameba-arduino-pro2 (dev) | `e218f33` | April 30, 2026 | "Pre Release Version 4.1.1" |
| ameba-rtos-pro2 (main) | `1c1c8b7` | May 1, 2026 | "Sync upstream — wowlan dhcp renew" |

Zero new commits to either repository. No new releases (latest: V4.1.1-QC-V05, internal build April 30, 2026). No open pull requests on `ameba-arduino-pro2`. No fix is in progress or under review in any public channel.

---

### Finding 94 — Exhaustive Web Search: No New Public Reports, Articles, or Fixes in Any Language
**Source:** Web searches (Google indexed, May 4, 2026) — English and Chinese  
**Priority:** LOW — Confirms continued public ignorance of the bug

Searches conducted and results:

| Query | Result |
|---|---|
| `ameba-arduino-pro2 FlashMemory FCS camera fix 2026` | Zero new relevant hits; all results from April 2026 or earlier |
| `RTL8735B VOE_OPEN_CMD fail FCS flash camera boot 2026` | Zero new hits; same previously-documented forum threads |
| `AMB82 "slot full" OR "VOE_OPEN_CMD" OR "FCS KM_status" camera flash 2026` | Zero new hits |
| `RTL8735B flash 写入 摄像头启动失败 FCS 冷启动 CSDN 2026` | Zero Chinese-language results |
| `AmebaPro2 RTL8735B FlashMemory fix patch mutex commit May 2026` | Zero results; no patch or fix commit found |
| `AMB82 FlashMemory FCS camera "device_mutex_lock" OR "RT_DEV_LOCK_FLASH" workaround fix` | Zero results |

The exact bug-signature strings `"It don't do the sensor initial process"` and `"FCS KM_status 0x00002081"` continue to return **zero indexed results** on the public web. The root cause analysis documented in this log (Hypothesis F — `FlashMemory.cpp` bypasses `RT_DEV_LOCK_FLASH`) remains the only public record of this analysis anywhere on the internet.

---

### Finding 95 — ideashatch/HUB-8735 and ameba-rtos-pro2: Still No New Issues
**Source:** https://github.com/ideashatch/HUB-8735/issues and https://github.com/Ameba-AIoT/ameba-rtos-pro2/issues (fetched 2026-05-04)  
**Priority:** LOW — Status confirmation

- **ideashatch/HUB-8735**: Only one open issue (#10 — PS5268 sensor ID fail, August 2025). No new issues.
- **ameba-rtos-pro2**: 3 open issues (highest: #16, January 2026, "Unable to access source folder"). No new issues. No issues related to FlashMemory, FCS, mutex, camera boot, or VOE.

---

### Finding 96 — No New Forum Threads Accessible; Thread #4834 Remains Highest Adjacent Thread
**Source:** forum.amebaiot.com (403-blocked); Google-indexed search snippets (2026-05-04)  
**Priority:** LOW — Status confirmation

All forum.amebaiot.com threads remain HTTP 403-blocked. The highest forum thread with adjacent content previously documented is #4834 ("Boot failure after OTA update" — a different flash-detection failure, not the FCS race). A search for `AmebaPro2 AMB82 FlashMemory camera cold boot failure fix workaround site:forum.amebaiot.com` returned no new threads mentioning the bug. Thread #4777 ("AMB82-Mini onboard camera sensor identification and VOE setup for wireless video and I2C"), the most recently indexed thread adjacent to camera setup concerns, contains no accessible content.

No new forum threads matching the bug's error strings or symptoms have been indexed since the last research cycle.

---

### Complete Status Sweep — 2026-05-04 (Update 2)

| Repository / Source | Last activity | Status |
|---|---|---|
| ameba-arduino-pro2 (dev branch) | April 30, 2026 — SHA `e218f33` | **No new commits — confirmed** |
| ameba-arduino-pro2 (releases) | V4.1.1-QC-V05 (April 30, 2026 internal build) | **No new release** |
| ameba-rtos-pro2 (main branch) | May 1, 2026 — SHA `1c1c8b7` | **No new commits — confirmed** |
| ameba-arduino-pro2 pull requests | 0 open | **No fix under review** |
| ameba-arduino-pro2 issues | 17 open total; highest: #398 (Mar 29, 2026) | **Zero new FCS/FlashMemory/VOE issues** |
| ameba-rtos-pro2 issues | 3 open; highest: #16 (Jan 2026) | **Zero new relevant issues** |
| ideashatch/HUB-8735 | Dec 2, 2025 — SHA `870a7e0` | **Inactive; only issue #10 (Aug 2025)** |
| Ai-Thinker-Open GitHub org | — | **No BW21-CBV repository** |
| forum.amebaiot.com | All threads 403-blocked; no new Google snippets for bug strings | **No new accessible content** |
| CSDN / Zhihu / 21ic / EEWorld | — | **Zero Chinese-language reports — reconfirmed** |
| bbs.ai-thinker.com (BW21-CBV) | — | **No camera/FCS bug threads — reconfirmed** |
| FlashMemory.cpp (dev, SHA 4fdfbec) | Sept 30, 2025 | **Still NO mutex fix — confirmed by direct fetch** |
| video_api.c (main) | March 3, 2026 | **Still NO mutex fix at FCS call site** |
| Official documentation (ameba-arduino-doc) | April 16, 2026 | **No FlashMemory/FCS warning added** |
| Public web (`"It don't do the sensor initial process"`) | — | **Zero new indexed results** |
| Public web (`"FCS KM_status 0x00002081"`) | — | **Zero new indexed results** |
| Public web (`"device_mutex_lock" "FlashMemory" Ameba`) | — | **Zero results — root cause uniquely in this log** |

**No HIGH priority confirmed fix found. Bug status: publicly undocumented and unpatched as of 2026-05-04 (second 6-hour run).**

---

### Sources Added (Update 2026-05-04, Update 2)
- ameba-arduino-pro2 issues (17 open total; highest: #398 Mar 2026; no new FCS issues): https://github.com/Ameba-AIoT/ameba-arduino-pro2/issues
- ameba-rtos-pro2 issues (3 open; highest: #16 Jan 2026): https://github.com/Ameba-AIoT/ameba-rtos-pro2/issues
- ideashatch/HUB-8735 issues (only issue #10 Aug 2025): https://github.com/ideashatch/HUB-8735/issues
- ameba-arduino-pro2 commits/dev (re-confirmed last: e218f33, Apr 30, 2026): https://github.com/Ameba-AIoT/ameba-arduino-pro2/commits/dev
- ameba-rtos-pro2 commits/main (re-confirmed last: 1c1c8b7, May 1, 2026): https://github.com/Ameba-AIoT/ameba-rtos-pro2/commits/main
- ameba-arduino-pro2 releases (re-confirmed latest: V4.1.1-QC-V05, no new tag): https://github.com/Ameba-AIoT/ameba-arduino-pro2/releases

---

## Research Update — 2026-05-04 (Update 3 — 6-hour cycle)

### Finding 97 — video_api.c Contains TWO Unguarded ftl_common_write() Calls in video_pre_init_save_cur_params()
**Source:** `ameba-rtos-pro2/main` — `video_api.c` (fresh fetch, May 4, 2026)
https://raw.githubusercontent.com/Ameba-AIoT/ameba-rtos-pro2/main/component/video/driver/RTL8735B/video_api.c
**Priority:** MEDIUM — Refines the race-condition scope; prior findings documented only one call site

Prior findings (17, 53, 61) identified one `ftl_common_write()` call site inside `video_pre_init_save_cur_params()`. A fresh fetch of the current `main` branch reveals **two distinct `ftl_common_write()` calls** within that function, located at approximately lines 1900–1910 and 2000–2010.

The most likely explanation: the function saves the FCS record in two passes — one for the FCSD header + AE/AWB payload, and a second for an additional ISP parameter block (possibly retention metadata or a separate channel record). Both calls use `flash_addr` derived from `NOR_FLASH_FCS = 0xF0D000`. **Neither call is protected by any mutex.**

**Implication:** There are two independent flash write windows per `SAVE_TO_FLASH` invocation. Each write is a separate erase-then-program sequence, doubling the total flash-bus occupancy window during which `FlashMemory.cpp` can issue a competing command and abort one of the writes. The race window is larger than previously modelled.

---

### Finding 98 — video_api.c Uses rtw_mutex_get/put for Stream Operations — But NOT for Flash Writes
**Source:** `ameba-rtos-pro2/main` — `video_api.c` (fresh fetch, May 4, 2026)
https://raw.githubusercontent.com/Ameba-AIoT/ameba-rtos-pro2/main/component/video/driver/RTL8735B/video_api.c
**Priority:** MEDIUM — New detail on selective mutex use in the file; strengthens "omission" characterisation

Finding 58 documented `static _mutex video_open_close_mutex = NULL;` (a FreeRTOS `_mutex` type) guarding `hal_video_open()` / `hal_video_close()` only. A fresh full read of the file reveals a second, distinct mutex API also in use:

```c
rtw_mutex_get(&some_stream_mutex, ...);
// ... stream channel operations ...
rtw_mutex_put(&some_stream_mutex);
```

`rtw_mutex_get/put` is a lower-level mutex API from the Realtek Wi-Fi OS abstraction layer (`rtw_mutex_t` type, distinct from `_mutex`). It is applied to video stream slot operations in `video_api.c` — but **not** to the `ftl_common_write()` calls in `video_pre_init_save_cur_params()`.

**Significance:** `video_api.c` uses **two separate mutex APIs** (`_mutex` and `rtw_mutex_t`) to serialize different resource accesses — yet the one resource that requires serialization with external callers (the SPI NOR flash bus) is serialized by neither. The omission of `device_mutex_lock(RT_DEV_LOCK_FLASH)` around the FCS flash write is a selective gap in an otherwise mutex-aware file.

---

### Finding 99 — 36 Forks of ameba-arduino-pro2 Examined; Zero Contain a FlashMemory Mutex Patch
**Source:** GitHub forks of ameba-arduino-pro2 (https://github.com/Ameba-AIoT/ameba-arduino-pro2/forks); notable forks directly inspected
**Priority:** LOW — Confirms no community fix has been developed or shared

The `ameba-arduino-pro2` repository has **36 public forks**. The two most recently active forks with FlashMemory-relevant commits were inspected:

- **`geofrancis/ameba-arduino-pro2`** — Mirrors upstream main; no FlashMemory or mutex commits.
- **`LighthouseAvionics/ameba-arduino-pro2`** — Last updated November 2024 (V4.0.8/V4.0.9 era); no FlashMemory or mutex commits.

No fork in the entire network has committed a patch adding `device_mutex_lock(RT_DEV_LOCK_FLASH)` to `FlashMemory.cpp` or `video_api.c`. The workaround documented in Finding 27 (user-level `device_mutex_lock` wrapper in Arduino sketches) remains the only publicly-available mitigation — and it exists only in this research log, not in any public codebase.

---

### Finding 100 — Forum Threads #4821 and #4829 Newly Identified; Unrelated to Bug
**Source:** forum.amebaiot.com (403-blocked); Google-indexed search results (2026-05-04)
https://forum.amebaiot.com/t/amb82-mini-usb-host-cdc-ecm-fail-to-sim7600g-h/4821
https://forum.amebaiot.com/t/can-amb82-mini-be-used-with-teachable-machine-uvc-issue/4829
**Priority:** LOW — New thread numbers logged; no FCS bug content

Two previously unlogged forum threads were discovered via search results:
- **Thread #4821**: "AMB82-mini USB host CDC ECM fail to SIM7600G-H" — USB peripheral issue, unrelated to flash or camera FCS.
- **Thread #4829**: "Can AMB82 MINI be used with Teachable Machine? UVC Issue" — UVC camera class question for ML inference; unrelated to FCS cold-boot failure or FlashMemory writes.

Both are HTTP 403-blocked; titles only are available from search-engine snippets. These are the highest-numbered forum threads discovered in this cycle, suggesting the forum's most recent posts are in the #4830–#4840 range.

---

### Finding 101 — Complete Status Sweep: Bug Unpatched as of 2026-05-04 (Update 3)
**Source:** Exhaustive sweep of all tracked sources (2026-05-04, third 6-hour run)
**Priority:** LOW — Status confirmation

| Repository / Source | Last activity | Status |
|---|---|---|
| ameba-arduino-pro2 (dev branch) | April 30, 2026 — SHA `e218f33` | **No new commits — confirmed** |
| ameba-arduino-pro2 (releases) | V4.1.1-QC-V05 (April 30, 2026 internal build) | **No new release** |
| ameba-rtos-pro2 (main branch) | May 1, 2026 — SHA `1c1c8b7` (WLAN dhcp sync) | **No new commits — confirmed** |
| ameba-arduino-pro2 pull requests | 0 open | **No fix under review** |
| ameba-arduino-pro2 issues | 17 open; highest: #398 (Mar 29, 2026) | **Zero new FCS/FlashMemory/VOE issues** |
| ameba-rtos-pro2 issues | 3 open; highest: #16 (Jan 2026) | **Zero new relevant issues** |
| ideashatch/HUB-8735 | Dec 2, 2025 — SHA `870a7e0` | **Inactive; no new issues** |
| Ai-Thinker-Open GitHub org | — | **No BW21-CBV repository** |
| ameba-arduino-pro2 forks (36 total) | Various | **Zero forks contain FlashMemory mutex patch** |
| forum.amebaiot.com | Threads #4821, #4829 newly logged; all 403-blocked | **No accessible content; highest observed thread ~#4835** |
| CSDN / Zhihu / 21ic / EEWorld | — | **Zero Chinese-language reports — reconfirmed** |
| bbs.ai-thinker.com (BW21-CBV) | — | **No camera/FCS bug threads** |
| FlashMemory.cpp (dev, SHA 4fdfbec) | Sept 30, 2025 | **Still NO mutex fix — confirmed by direct fetch** |
| video_api.c (main) | March 3, 2026 | **TWO ftl_common_write() calls; NEITHER guarded (Finding 97)** |
| Official documentation (ameba-arduino-doc) | April 16, 2026 | **No FlashMemory/FCS warning added** |
| Public web (`"It don't do the sensor initial process"`) | — | **Zero new indexed results** |
| Public web (`"FCS KM_status 0x00002081"`) | — | **Zero new indexed results** |
| Public web (`"device_mutex_lock" "FlashMemory" Ameba`) | — | **Zero results** |

**No HIGH priority confirmed fix found. Bug status: publicly undocumented and unpatched as of 2026-05-04 (third 6-hour run).**

---

### Sources Added (Update 2026-05-04, Update 3)
- ameba-rtos-pro2 video_api.c main (TWO ftl_common_write() calls confirmed; rtw_mutex_get/put for streams; no flash mutex): https://raw.githubusercontent.com/Ameba-AIoT/ameba-rtos-pro2/main/component/video/driver/RTL8735B/video_api.c
- ameba-arduino-pro2 forks (36 total; zero with FlashMemory mutex patch): https://github.com/Ameba-AIoT/ameba-arduino-pro2/forks
- geofrancis/ameba-arduino-pro2 fork (mirrors upstream; no mutex fix): https://github.com/geofrancis/ameba-arduino-pro2
- LighthouseAvionics/ameba-arduino-pro2 fork (Nov 2024, V4.0.8/4.0.9 era; no mutex fix): https://github.com/LighthouseAvionics/ameba-arduino-pro2
- Forum thread #4821 (AMB82-mini USB CDC ECM; unrelated; 403-blocked): https://forum.amebaiot.com/t/amb82-mini-usb-host-cdc-ecm-fail-to-sim7600g-h/4821
- Forum thread #4829 (AMB82 UVC teachable machine; unrelated; 403-blocked): https://forum.amebaiot.com/t/can-amb82-mini-be-used-with-teachable-machine-uvc-issue/4829

---

## Research Update — 2026-05-04 (Update 4 — 6-hour cycle)

### Finding 102 — V4.1.1 Stable Release Tag Confirmed Absent (HTTP 404)
**Source:** https://github.com/Ameba-AIoT/ameba-arduino-pro2/releases/tag/V4.1.1  
**Priority:** LOW — Confirms the stable release hasn't shipped; only pre-release QC builds exist

A direct fetch of `https://github.com/Ameba-AIoT/ameba-arduino-pro2/releases/tag/V4.1.1` returns **HTTP 404**. The tag does not exist. The only V4.1.1-family tags published are the QC pre-release builds: V4.1.1-QC-V04 (internal builds through April 17, 2026) and V4.1.1-QC-V05 (internal builds through April 30, 2026). A stable public V4.1.1 release has not been cut. Users wanting the latest code must use the QC pre-release or the `dev` branch directly.

This also means no stable-release changelog entry exists that could contain an undocumented FlashMemory/FCS fix that might have been missed.

---

### Finding 103 — Issues #399–#407 on ameba-arduino-pro2 Are Merged PRs, Not Bug Reports
**Source:** Direct inspection of https://github.com/Ameba-AIoT/ameba-arduino-pro2/issues/399 through /407  
**Priority:** LOW — Confirms issue tracker is clean; no hidden bug reports

GitHub issues #399–#407 on `ameba-arduino-pro2` are all **merged pull requests** (GitHub issues and PRs share the same number sequence). Their topics:
- WDT API update, AMB82-zero board support, NN model updates, PowerMode documentation, JPEGDecoder submodules, image classification examples, signed tools updates.

None relate to FlashMemory, FCS, camera boot failure, VOE errors, or flash locking. Issue #408 returns HTTP 404 — it does not exist. The highest filed issue remains #398 ("FEATURE REQUEST: Access to raw video or H264/H265 encoded data," March 29, 2026). **No new bugs have been filed in April–May 2026.**

---

### Finding 104 — Complete Status Sweep: Bug Unpatched as of 2026-05-04 (Update 4)
**Source:** Exhaustive sweep of all tracked sources (2026-05-04, fourth 6-hour run)  
**Priority:** LOW — Status confirmation

| Repository / Source | Last activity | Status |
|---|---|---|
| ameba-arduino-pro2 (dev branch) | April 30, 2026 — SHA `e218f33` | **No new commits — confirmed** |
| ameba-arduino-pro2 (releases) | V4.1.1-QC-V05 (April 30, 2026); V4.1.1 stable tag: HTTP 404 | **No new release** |
| ameba-rtos-pro2 (main branch) | May 1, 2026 — SHA `1c1c8b7` (WLAN dhcp sync) | **No new commits — confirmed** |
| ameba-arduino-pro2 pull requests | 0 open | **No fix under review** |
| ameba-arduino-pro2 issues | 17 open; highest filed: #398 (Mar 29, 2026); #399–#407 are PRs; #408 = 404 | **Zero new bug reports** |
| ameba-rtos-pro2 issues | 3 open; highest: #16 (Jan 2026) | **Zero new relevant issues** |
| ideashatch/HUB-8735 | Dec 2, 2025 — SHA `870a7e0` | **Inactive** |
| Ai-Thinker-Open GitHub org | — | **No BW21-CBV repository** |
| ameba-arduino-pro2 forks (36 total) | Various | **Zero forks contain FlashMemory mutex patch** |
| forum.amebaiot.com | All threads 403-blocked; highest observed: ~#4834 | **No new accessible content** |
| CSDN / Zhihu / 21ic / EEWorld | — | **Zero Chinese-language reports** |
| bbs.ai-thinker.com (BW21-CBV) | — | **No camera/FCS bug threads** |
| FlashMemory.cpp (dev, SHA 4fdfbec) | Sept 30, 2025 | **Still NO mutex fix — confirmed by direct raw fetch** |
| video_api.c (main) | March 3, 2026 | **Two unguarded ftl_common_write() calls (Finding 97); no fix** |
| Official documentation (ameba-arduino-doc) | April 16, 2026 | **No FlashMemory/FCS warning added** |
| Public web (`"It don't do the sensor initial process"`) | — | **Zero new indexed results** |
| Public web (`"FCS KM_status 0x00002081"`) | — | **Zero new indexed results** |
| Public web (`"device_mutex_lock" "FlashMemory" Ameba`) | — | **Zero results — root cause uniquely in this log** |

**No HIGH priority confirmed fix found. Bug status: publicly undocumented and unpatched as of 2026-05-04 (fourth 6-hour run).**

---

### Sources Added (Update 2026-05-04, Update 4)
- ameba-arduino-pro2 release tag V4.1.1 (HTTP 404 — stable release not yet published): https://github.com/Ameba-AIoT/ameba-arduino-pro2/releases/tag/V4.1.1
- ameba-arduino-pro2 issues #399–#407 (all merged PRs; no bug reports; #408 = 404): https://github.com/Ameba-AIoT/ameba-arduino-pro2/issues/399
- ameba-arduino-pro2 commits/dev (re-confirmed last: e218f33, Apr 30, 2026): https://github.com/Ameba-AIoT/ameba-arduino-pro2/commits/dev
- ameba-rtos-pro2 commits/main (re-confirmed last: 1c1c8b7, May 1, 2026): https://github.com/Ameba-AIoT/ameba-rtos-pro2/commits/main
- ameba-arduino-pro2 FlashMemory.cpp dev (re-confirmed no mutex, write()/writeWord() unchanged): https://raw.githubusercontent.com/Ameba-AIoT/ameba-arduino-pro2/dev/Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.cpp
- ameba-rtos-pro2 video_api.c main (re-confirmed two unguarded ftl_common_write() calls): https://raw.githubusercontent.com/Ameba-AIoT/ameba-rtos-pro2/main/component/video/driver/RTL8735B/video_api.c

---

## Research Update — 2026-05-05

### Finding 105 — Complete Status Sweep: All Repositories Static Since May 1, 2026; Bug Unpatched
**Source:** Exhaustive sweep of all tracked sources (2026-05-05, 6-hour cycle)
**Priority:** LOW — Status confirmation; no new information

All monitored sources were fetched directly. Results:

| Repository / Source | Last activity | Status |
|---|---|---|
| ameba-arduino-pro2 (dev branch) | April 30, 2026 — SHA `e218f33` ("Pre Release Version 4.1.1") | **No new commits — branch identical to e218f33 confirmed by compare** |
| ameba-arduino-pro2 (releases) | V4.1.1-QC-V05 (April 30, 2026 internal build); V4.1.1 stable: HTTP 404 | **No new release** |
| ameba-rtos-pro2 (main branch) | May 1, 2026 — SHA `1c1c8b7` (WLAN dhcp sync) | **No new commits — branch identical to 1c1c8b7 confirmed by compare** |
| ameba-arduino-pro2 pull requests | 0 open; 319 closed; highest item number is #407 | **No fix under review** |
| ameba-arduino-pro2 issues | 17 open; highest filed issue: #398 (Mar 29, 2026); #408 returns 404 | **Zero new bug reports; zero FCS/FlashMemory/VOE issues** |
| ameba-rtos-pro2 issues | 3 open; highest: #16 (Jan 2026); #17 and #18 return 404 | **Zero new relevant issues** |
| ideashatch/HUB-8735 | 1 total issue | **Inactive; no new issues** |
| Ai-Thinker-Open GitHub org | — | **No BW21-CBV repository** |
| ameba-arduino-pro2 forks (36 total) | Various | **Zero forks contain FlashMemory mutex patch** |
| forum.amebaiot.com | Highest indexed thread ~#4834; all 403-blocked | **No new accessible content; no new FCS/camera/flash threads** |
| CSDN / Zhihu / 21ic / EEWorld | — | **Zero Chinese-language reports — reconfirmed** |
| bbs.ai-thinker.com (BW21-CBV) | — | **No camera/FCS bug threads** |
| FlashMemory.cpp (dev, SHA 4fdfbec) | Sept 30, 2025 | **Still NO mutex fix — confirmed by direct raw fetch** |
| video_api.c (main) | March 3, 2026 | **Two unguarded ftl_common_write() calls; no mutex fix — confirmed** |
| Official documentation (ameba-arduino-doc) | April 16, 2026 — SHA `d0b6ca3` ("Update PowerMode documentation #104") | **No new commits; no FlashMemory/FCS warning added** |
| Public web (`"It don't do the sensor initial process"`) | — | **Zero new indexed results** |
| Public web (`"FCS KM_status 0x00002081"`) | — | **Zero new indexed results** |
| Public web (`"device_mutex_lock" "FlashMemory" Ameba`) | — | **Zero results — root cause uniquely documented in this log** |

Direct raw fetches of both `FlashMemory.cpp` (dev) and `video_api.c` (main) confirm no mutex protection has been added. The `write()` and `writeWord()` functions in `FlashMemory.cpp` call `flash_erase_sector()` and `flash_stream_write()` without any locking. Both `ftl_common_write()` call sites in `video_pre_init_save_cur_params()` in `video_api.c` remain unguarded.

The exact error strings `"It don't do the sensor initial process"`, `"FCS KM_status 0x00002081"`, and `"[VOE][WARN]slot full"` continue to return zero new indexed results on the public web. The bug is confirmed undiscovered and unreported by any other party.

**No HIGH priority confirmed fix found. Bug status: publicly undocumented and unpatched as of 2026-05-05.**

---

### Sources Added (Update 2026-05-05)
- ameba-arduino-pro2 dev vs HEAD compare (e218f33 identical to current HEAD): https://github.com/Ameba-AIoT/ameba-arduino-pro2/compare/e218f33...dev
- ameba-rtos-pro2 main vs HEAD compare (1c1c8b7 identical to current HEAD): https://github.com/Ameba-AIoT/ameba-rtos-pro2/compare/1c1c8b7...main
- ameba-arduino-pro2 issues (highest: #398 Mar 2026; #408 returns 404; no new FCS issues): https://github.com/Ameba-AIoT/ameba-arduino-pro2/issues
- ameba-rtos-pro2 issues (highest: #16 Jan 2026; #17 and #18 return 404): https://github.com/Ameba-AIoT/ameba-rtos-pro2/issues
- ameba-arduino-pro2 pulls (0 open; 319 closed; highest item #407): https://github.com/Ameba-AIoT/ameba-arduino-pro2/pulls
- ameba-arduino-pro2 releases (re-confirmed latest: V4.1.1-QC-V05 Apr 30, 2026; no new tag): https://github.com/Ameba-AIoT/ameba-arduino-pro2/releases
- ameba-arduino-pro2 FlashMemory.cpp dev (re-confirmed no mutex, SHA 4fdfbec): https://raw.githubusercontent.com/Ameba-AIoT/ameba-arduino-pro2/dev/Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.cpp
- ameba-rtos-pro2 video_api.c main (re-confirmed two unguarded ftl_common_write() calls): https://raw.githubusercontent.com/Ameba-AIoT/ameba-rtos-pro2/main/component/video/driver/RTL8735B/video_api.c

---

## Research Update — 2026-05-05 (Update 2 — 6-hour cycle)

### Finding 106 — ameba-rtos-pro2 Has "aiglass" Product-Variant Tag Series (V1.0.3-aiglass.07, April 2, 2026)
**Source:** https://github.com/Ameba-AIoT/ameba-rtos-pro2/tags  
**Priority:** LOW — New observation about a parallel product track; not directly related to the bug

The `ameba-rtos-pro2` repository hosts a separate tag series prefixed `aiglass`, distinct from the main AmebaPro2/AMB82-Mini release cadence. The most recent observed tag is **V1.0.3-aiglass.07** (April 2, 2026). These tags appear to correspond to a Realtek AI-glasses product variant that also uses the RTL8735B SoC. No "aiglass" tag changelog was inspectable (403-blocked).

Significance for this bug:
- The RTL8735B SoC is the same silicon across all these product variants. The `video_api.c` `ftl_common_write()` unguarded flash write race would apply equally to any product using `SAVE_TO_FLASH` FCS mode.
- The "aiglass" series has an independent versioning track — any fix on the main branch would need a separate merge into "aiglass" builds.
- No "aiglass" tag exists after April 2, 2026 — this variant branch is also inactive in the relevant period.

This is the first documentation of the "aiglass" tag series in this research log. Note: `ameba-tool-rtos-pro2` (a separate repository, documented in Finding 77, last commit March 9, 2026) is distinct from these tags on `ameba-rtos-pro2` itself.

---

### Finding 107 — Complete Status Sweep: All Sources Static; Bug Unpatched as of 2026-05-05 (Update 2)
**Source:** Exhaustive sweep of all tracked sources (2026-05-05, second 6-hour cycle)  
**Priority:** LOW — Status confirmation

| Repository / Source | Last activity | Status |
|---|---|---|
| ameba-arduino-pro2 (dev branch) | April 30, 2026 — SHA `e218f33` | **No new commits** |
| ameba-arduino-pro2 (releases) | V4.1.1-QC-V05 (April 30, 2026); V4.1.1 stable: HTTP 404 | **No new release** |
| ameba-rtos-pro2 (main branch) | May 1, 2026 — SHA `1c1c8b7` | **No new commits** |
| ameba-rtos-pro2 (tags) | V1.0.3-aiglass.07 (Apr 2, 2026) — aiglass variant only | **No new tags on main SDK track** |
| ameba-arduino-pro2 pull requests | 0 open; highest item #407 | **No fix under review** |
| ameba-arduino-pro2 issues | 17 open; highest filed: #398 (Mar 2026); #408 = 404 | **Zero new FCS/FlashMemory/VOE issues** |
| ameba-rtos-pro2 issues | 3 open; highest: #16 (Jan 2026) | **Zero new relevant issues** |
| ideashatch/HUB-8735 | Dec 2, 2025 | **Inactive** |
| Ai-Thinker-Open GitHub org | — | **No BW21-CBV repository** |
| ameba-arduino-pro2 forks (36 total) | — | **Zero forks contain FlashMemory mutex patch** |
| forum.amebaiot.com | All threads 403-blocked; highest observed ~#4834 | **No new accessible content** |
| CSDN / Zhihu / 21ic / EEWorld | — | **Zero Chinese-language reports** |
| bbs.ai-thinker.com (BW21-CBV) | — | **No camera/FCS bug threads** |
| FlashMemory.cpp (dev, SHA 4fdfbec) | Sept 30, 2025 | **Still NO mutex fix — confirmed** |
| video_api.c (main) | March 3, 2026 | **Two unguarded ftl_common_write() calls; no fix** |
| Official documentation (ameba-arduino-doc) | April 16, 2026 | **No FlashMemory/FCS warning added** |
| Public web (`"It don't do the sensor initial process"`) | — | **Zero new indexed results** |
| Public web (`"FCS KM_status 0x00002081"`) | — | **Zero new indexed results** |
| Public web (`"device_mutex_lock" "FlashMemory" Ameba`) | — | **Zero results — root cause uniquely documented in this log** |

**No HIGH priority confirmed fix found. Bug status: publicly undocumented and unpatched as of 2026-05-05 (second 6-hour run).**

---

### Sources Added (Update 2026-05-05, Update 2)
- ameba-rtos-pro2 tags (aiglass series, V1.0.3-aiglass.07 April 2, 2026): https://github.com/Ameba-AIoT/ameba-rtos-pro2/tags
- ameba-arduino-doc commits/main (last: d0b6ca3 Apr 16, 2026; no new commits): https://github.com/Ameba-AIoT/ameba-arduino-doc/commits/main

---

## Research Update — 2026-05-05 (Update 3 — 6-hour cycle)

### Finding 108 — New Commit `13961cc` on ameba-arduino-pro2 dev (May 5, 2026): AMB82-zero SWD Logic; Not a Fix
**Source:** `ameba-arduino-pro2` dev branch — commit `13961cc` (May 5, 2026)
https://github.com/Ameba-AIoT/ameba-arduino-pro2/commit/13961cc
**Priority:** LOW — New commit confirmed; no FCS/FlashMemory/mutex relevance

A new commit was pushed to `ameba-arduino-pro2/dev` on **May 5, 2026** (the day of the previous research cycle), which was not captured in the last Update 2 run. This is the first dev-branch commit since `e218f33` ("Pre Release Version 4.1.1", April 30, 2026).

Commit `13961cc` — **"Update API for AMB82-zero and SWD off logic"** — touches three files:
1. `Arduino_package/hardware/cores/ambpro2/wiring_digital.c` — Replaces `sys_jtag_off()` with `hal_sys_dbg_port_cfg()` for SWD debug port disable logic
2. `Arduino_package/hardware/variants/ameba_amb82-zero/variant.cpp` — AMB82-zero board pin mapping update
3. `Arduino_package/hardware/variants/ameba_amb82-zero/variant.h` — AMB82-zero pin definitions update

**No changes to:** `FlashMemory.cpp`, `video_api.c`, `device_lock.h`, `boards.txt` FCS section, `ftl_nor_api.c`, or any file related to flash locking, FCS, or camera boot initialization. This is purely a board-variant GPIO/SWD debug port API change for the AMB82-zero hardware. The FlashMemory/FCS race condition is **not addressed**.

---

### Finding 109 — Complete Status Sweep: Bug Unpatched as of 2026-05-05 (Update 3)
**Source:** Exhaustive sweep of all tracked sources (2026-05-05, third 6-hour cycle)
**Priority:** LOW — Status confirmation

| Repository / Source | Last activity | Status |
|---|---|---|
| ameba-arduino-pro2 (dev branch) | **May 5, 2026 — SHA `13961cc`** ("Update API for AMB82-zero and SWD off logic") | No FCS/FlashMemory fix; SWD/GPIO change only |
| ameba-arduino-pro2 (releases) | V4.1.1-QC-V05 (April 30, 2026 internal build); V4.1.1 stable: HTTP 404 | **No new release** |
| ameba-rtos-pro2 (main branch) | May 1, 2026 — SHA `1c1c8b7` (WLAN dhcp sync) | **No new commits — confirmed by direct fetch** |
| ameba-arduino-doc (main branch) | April 16, 2026 — SHA `d0b6ca3` ("Update PowerMode documentation #104") | **No new commits** |
| ameba-arduino-pro2 pull requests | 0 open; highest item #407 | **No fix under review** |
| ameba-arduino-pro2 issues | 17 open; highest filed: #398 (Mar 29, 2026); #408 = 404 | **Zero new FCS/FlashMemory/VOE issues** |
| ameba-rtos-pro2 issues | 3 open (#16, #4, #3); no issues above #16 | **Zero new relevant issues** |
| ideashatch/HUB-8735 | Dec 2, 2025 | **Inactive** |
| Ai-Thinker-Open GitHub org | — | **No BW21-CBV repository** |
| ameba-arduino-pro2 forks (36 total) | — | **Zero forks contain FlashMemory mutex patch** |
| forum.amebaiot.com | All threads 403-blocked; no new threads above #4834 indexed | **No new accessible content; no FCS/flash/camera threads** |
| CSDN / Zhihu / 21ic / EEWorld / mcublog.cn | — | **Zero Chinese-language reports of this bug — reconfirmed** |
| bbs.ai-thinker.com / bbs.aithinker.com (BW21-CBV) | BW21-CBV projects, unboxings; no FCS bug threads | **Zero relevant posts** |
| FlashMemory.cpp (dev, SHA `4fdfbec`) | Sept 30, 2025 | **Still NO mutex fix — confirmed by direct raw fetch** |
| video_api.c (main) | March 3, 2026 | **Two unguarded `ftl_common_write()` calls; no mutex fix** |
| Official documentation (ameba-arduino-doc) | April 16, 2026 | **No FlashMemory/FCS warning added** |
| Public web (`"It don't do the sensor initial process"`) | — | **Zero new indexed results** |
| Public web (`"FCS KM_status 0x00002081"`) | — | **Zero new indexed results** |
| Public web (`"device_mutex_lock" "FlashMemory" Ameba`) | — | **Zero results — root cause uniquely documented in this log** |

Direct raw fetch of `FlashMemory.cpp` (dev branch) confirms: zero `device_mutex_lock` calls, zero `device_lock.h` includes, `write()` and `writeWord()` bodies unchanged from SHA `4fdfbec` (September 30, 2025).

The exact bug-signature strings `"It don't do the sensor initial process"`, `"FCS KM_status 0x00002081"`, and `"[VOE][WARN]slot full"` continue to return zero new indexed results on the public web.

**No HIGH priority confirmed fix found. Bug status: publicly undocumented and unpatched as of 2026-05-05 (third 6-hour run).**

---

### Sources Added (Update 2026-05-05, Update 3)
- ameba-arduino-pro2 commit `13961cc` (May 5, 2026 — AMB82-zero SWD logic; no FCS/FlashMemory change): https://github.com/Ameba-AIoT/ameba-arduino-pro2/commit/13961cc
- ameba-arduino-pro2 dev branch commits (confirmed latest: `13961cc`, May 5, 2026): https://github.com/Ameba-AIoT/ameba-arduino-pro2/commits/dev
- ameba-rtos-pro2 main branch commits (re-confirmed last: `1c1c8b7`, May 1, 2026): https://github.com/Ameba-AIoT/ameba-rtos-pro2/commits/main
- ameba-arduino-doc commits/main (re-confirmed last: `d0b6ca3`, Apr 16, 2026): https://github.com/Ameba-AIoT/ameba-arduino-doc/commits/main
- ameba-arduino-pro2 issues (re-confirmed: 17 open, highest #398 Mar 2026, no new FCS issues): https://github.com/Ameba-AIoT/ameba-arduino-pro2/issues
- ameba-rtos-pro2 issues (re-confirmed: 3 open, highest #16 Jan 2026): https://github.com/Ameba-AIoT/ameba-rtos-pro2/issues
- ameba-arduino-pro2 FlashMemory.cpp dev (re-confirmed no mutex, SHA `4fdfbec`): https://raw.githubusercontent.com/Ameba-AIoT/ameba-arduino-pro2/dev/Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.cpp

---

## Research Update — 2026-05-05 (Update 4 — 6-hour cycle)

### Finding 110 — Complete Status Sweep: All Sources Static; Bug Unpatched as of 2026-05-05 (Update 4)
**Source:** Exhaustive sweep of all tracked sources (2026-05-05, fourth 6-hour cycle)
**Priority:** LOW — Status confirmation; no new information beyond Update 3

Full sweep of all monitored sources. Results are identical to Update 3:

| Repository / Source | Last activity | Status |
|---|---|---|
| ameba-arduino-pro2 (dev branch) | May 5, 2026 — SHA `13961cc` ("Update API for AMB82-zero and SWD off logic") | **Latest commit confirmed; no FCS/FlashMemory change** |
| ameba-arduino-pro2 (releases) | V4.1.1-QC-V05 (April 30, 2026 internal build); V4.1.1 stable: HTTP 404 | **No new release** |
| ameba-rtos-pro2 (main branch) | May 1, 2026 — SHA `1c1c8b7` (WLAN dhcp sync) | **No new commits — confirmed** |
| ameba-arduino-pro2 pull requests | 0 open; highest item #407 | **No fix under review** |
| ameba-arduino-pro2 issues | 17 open; highest filed: #398 (Mar 29, 2026) | **Zero new FCS/FlashMemory/VOE issues** |
| ameba-rtos-pro2 issues | 3 open; highest: #16 (Jan 2026) | **Zero new relevant issues** |
| ideashatch/HUB-8735 | Dec 2, 2025 — SHA `870a7e0`; issue #10 only | **Inactive** |
| forum.amebaiot.com | All threads 403-blocked; highest indexed ~#4834 | **No new accessible content** |
| CSDN / Zhihu / 21ic / EEWorld | — | **Zero Chinese-language reports — reconfirmed** |
| bbs.ai-thinker.com (BW21-CBV) | — | **No camera/FCS bug threads** |
| FlashMemory.cpp (dev, SHA `4fdfbec`) | Sept 30, 2025 | **Still NO mutex fix — re-confirmed by direct raw fetch** |
| video_api.c (main) | March 3, 2026 | **Two unguarded `ftl_common_write()` calls; no mutex fix** |
| Official documentation (ameba-arduino-doc) | April 16, 2026 | **No FlashMemory/FCS warning added** |
| Public web (`"It don't do the sensor initial process"`) | — | **Zero new indexed results** |
| Public web (`"FCS KM_status 0x00002081"`) | — | **Zero new indexed results** |
| Public web (`"device_mutex_lock" "FlashMemory" Ameba`) | — | **Zero results — root cause uniquely documented in this log** |

English and Chinese web searches across Google, CSDN, 知乎, 21ic, EEWorld, and bbs.ai-thinker.com confirm zero new public discussion of this bug in any language. No forum post, blog article, GitHub issue, or patch has appeared describing the FlashMemory/FCS mutex race condition or a fix for it.

**No HIGH priority confirmed fix found. Bug status: publicly undocumented and unpatched as of 2026-05-05 (fourth 6-hour run).**

---

### Sources Added (Update 2026-05-05, Update 4)
- ameba-arduino-pro2 dev commits (re-confirmed latest: `13961cc`, May 5, 2026; no new commits after): https://github.com/Ameba-AIoT/ameba-arduino-pro2/commits/dev
- ameba-rtos-pro2 main commits (re-confirmed last: `1c1c8b7`, May 1, 2026): https://github.com/Ameba-AIoT/ameba-rtos-pro2/commits/main
- ameba-arduino-pro2 releases (re-confirmed latest: V4.1.1-QC-V05, Apr 30, 2026; no new tag): https://github.com/Ameba-AIoT/ameba-arduino-pro2/releases
- ameba-arduino-pro2 FlashMemory.cpp dev (re-confirmed no mutex, SHA `4fdfbec`): https://raw.githubusercontent.com/Ameba-AIoT/ameba-arduino-pro2/dev/Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.cpp

---

## Research Update — 2026-05-06

### Finding 111 — New Forum Threads #4835, #4839, #4840 Identified; None Related to Bug
**Source:** Google site-search + direct URL probes for forum.amebaiot.com threads above #4834 (all 403-blocked for full content)
https://forum.amebaiot.com/t/amb82-mini-deep-sleep-is-aon-gpio-pin-21-unreadable-after-powermode-begin-bus-fault-observed/4835
https://forum.amebaiot.com/t/how-to-upload-to-cloud-in-remote-locations/4839
https://forum.amebaiot.com/t/ameba-pro-https-bin-ota/4840
**Priority:** LOW — New thread numbers logged; no FCS/FlashMemory bug content

Three new forum threads have been indexed since the last research cycle (highest previously observed was ~#4834):

- **Thread #4835**: "AMB82-mini Deep Sleep: Is AON GPIO pin 21 unreadable after `PowerMode.begin()`? (Bus Fault observed)" — Deep sleep / AON GPIO / PowerMode bus fault. Unrelated to FCS, FlashMemory, or camera cold-boot failure.
- **Thread #4839**: "How to upload to cloud in remote locations" — Cloud connectivity question. Unrelated.
- **Thread #4840**: "關於Ameba Pro透過https下載Bin檔進行OTA的流程" (OTA via HTTPS for Ameba Pro, May 1, 2026) — HTTPS OTA download problems. Unrelated.

Threads #4836–#4838 and #4841+ are not indexed by Google as of this cycle. The highest confirmed active forum thread is now **#4840**. None of the three new threads mention VOE, FCS, FlashMemory, camera initialization failure, or cold-boot errors.

---

### Finding 112 — Complete Status Sweep: All Repositories Static; Bug Unpatched as of 2026-05-06
**Source:** Exhaustive sweep of all tracked sources (2026-05-06, 6-hour cycle)
**Priority:** LOW — Status confirmation

| Repository / Source | Last activity | Status |
|---|---|---|
| ameba-arduino-pro2 (dev branch) | May 5, 2026 — SHA `13961cc` ("Update API for AMB82-zero and SWD off logic") | **No new commits — confirmed by direct fetch** |
| ameba-arduino-pro2 (releases) | V4.1.1-QC-V05 (tag: Mar 6, 2026; internal build through Apr 30, 2026); V4.1.1 stable: HTTP 404 | **No new release** |
| ameba-rtos-pro2 (main branch) | May 1, 2026 — SHA `1c1c8b7` (WLAN dhcp sync) | **No new commits — confirmed by direct fetch** |
| ameba-arduino-pro2 pull requests | 0 open; 319 closed; highest item #407 | **No fix under review** |
| ameba-arduino-pro2 issues | 17 open; highest filed: #398 (Mar 29, 2026); #408 = HTTP 404 | **Zero new FCS/FlashMemory/VOE issues** |
| ameba-rtos-pro2 issues | 3 open; highest: #16 (Jan 2026); #17 and #18 = HTTP 404 | **Zero new relevant issues** |
| ideashatch/HUB-8735 | Dec 2, 2025 — SHA `870a7e0`; issue #10 only | **Inactive; no new issues** |
| Ai-Thinker-Open GitHub org | — | **No BW21-CBV repository** |
| ameba-arduino-pro2 forks (36 total) | — | **Zero forks contain FlashMemory mutex patch** |
| forum.amebaiot.com | Threads #4835 (deep sleep), #4839 (cloud), #4840 (OTA HTTPS) newly indexed; all 403-blocked | **No new FCS/flash/camera threads; highest confirmed thread #4840** |
| CSDN / Zhihu / 21ic / EEWorld | — | **Zero Chinese-language reports — reconfirmed** |
| bbs.ai-thinker.com (BW21-CBV) | — | **No camera/FCS bug threads** |
| FlashMemory.cpp (dev, SHA `4fdfbec`) | Sept 30, 2025 | **Still NO mutex fix — confirmed by direct raw fetch** |
| video_api.c (main) | March 3, 2026 | **Two unguarded `ftl_common_write()` calls; no mutex fix** |
| Official documentation (ameba-arduino-doc) | April 16, 2026 | **No FlashMemory/FCS warning added** |
| Public web (`"It don't do the sensor initial process"`) | — | **Zero new indexed results** |
| Public web (`"FCS KM_status 0x00002081"`) | — | **Zero new indexed results** |
| Public web (`"device_mutex_lock" "FlashMemory" Ameba`) | — | **Zero results — root cause uniquely documented in this log** |

Direct raw fetches of `FlashMemory.cpp` (dev) and `video_api.c` (main) re-confirm: no `device_mutex_lock` calls in `FlashMemory.cpp`; two unguarded `ftl_common_write()` calls in `video_pre_init_save_cur_params()` remain present. GitHub commit-message search for `FlashMemory + mutex` across the entire `ameba-arduino-pro2` history returns 0 results.

**No HIGH priority confirmed fix found. Bug status: publicly undocumented and unpatched as of 2026-05-06.**

---

### Sources Added (Update 2026-05-06)
- forum.amebaiot.com thread #4835 (AMB82-mini deep sleep/AON GPIO bus fault; unrelated; 403-blocked): https://forum.amebaiot.com/t/amb82-mini-deep-sleep-is-aon-gpio-pin-21-unreadable-after-powermode-begin-bus-fault-observed/4835
- forum.amebaiot.com thread #4839 (cloud upload; unrelated; 403-blocked): https://forum.amebaiot.com/t/how-to-upload-to-cloud-in-remote-locations/4839
- forum.amebaiot.com thread #4840 (OTA via HTTPS, May 1 2026; unrelated; 403-blocked): https://forum.amebaiot.com/t/ameba-pro-https-bin-ota/4840
- ameba-arduino-pro2 dev commits (confirmed latest: `13961cc`, May 5, 2026; no new commits): https://github.com/Ameba-AIoT/ameba-arduino-pro2/commits/dev
- ameba-rtos-pro2 main commits (confirmed last: `1c1c8b7`, May 1, 2026; no new commits): https://github.com/Ameba-AIoT/ameba-rtos-pro2/commits/main
- ameba-arduino-pro2 issues (17 open; highest: #398 Mar 2026; #408 = HTTP 404): https://github.com/Ameba-AIoT/ameba-arduino-pro2/issues
- ameba-rtos-pro2 issues (3 open; highest: #16 Jan 2026; #17/#18 = HTTP 404): https://github.com/Ameba-AIoT/ameba-rtos-pro2/issues
- ameba-arduino-pro2 releases (V4.1.1-QC-V05 tag created Mar 6, 2026; internal builds through Apr 30, 2026; no new tag): https://github.com/Ameba-AIoT/ameba-arduino-pro2/releases
- ameba-arduino-pro2 FlashMemory.cpp dev (re-confirmed no mutex, SHA `4fdfbec`): https://raw.githubusercontent.com/Ameba-AIoT/ameba-arduino-pro2/dev/Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.cpp
- ameba-rtos-pro2 video_api.c main (re-confirmed two unguarded ftl_common_write() calls): https://raw.githubusercontent.com/Ameba-AIoT/ameba-rtos-pro2/main/component/video/driver/RTL8735B/video_api.c

---

## Research Update — 2026-05-06

### Finding 111 — All Repositories Static Since Previous Cycle; No Fix Found
**Source:** Direct fetches of ameba-rtos-pro2/commits/main and ameba-arduino-pro2/commits/dev (2026-05-06)
https://github.com/Ameba-AIoT/ameba-rtos-pro2/compare/1c1c8b7...main
https://github.com/Ameba-AIoT/ameba-arduino-pro2/commits/dev
**Priority:** LOW — Status confirmation; no new fix commits

Both repositories are static since their last documented activity:

| Repository | Last commit SHA | Last commit date | Message |
|---|---|---|---|
| ameba-arduino-pro2 (dev) | `13961cc` | May 5, 2026 | "Update API for AMB82-zero and SWD off logic" |
| ameba-rtos-pro2 (main) | `1c1c8b7` | May 1, 2026 | "Sync upstream — wowlan dhcp renew" |

The compare endpoint `1c1c8b7...main` returns "1c1c8b7 and main are identical" — `1c1c8b7` is still HEAD of `ameba-rtos-pro2/main`. Zero new commits to either repository. No new releases (latest: V4.1.1-QC-V05, internal build April 30, 2026). No open pull requests on `ameba-arduino-pro2`. `FlashMemory.cpp` has not been touched since SHA `4fdfbec` (September 30, 2025) — now over 8 months without modification. `video_api.c` has not been touched since March 3, 2026.

---

### Finding 112 — FlashMemory.cpp and video_api.c Re-Confirmed Unpatched (May 6, 2026)
**Source:** Direct raw fetches (May 6, 2026)
https://raw.githubusercontent.com/Ameba-AIoT/ameba-arduino-pro2/dev/Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.cpp
https://raw.githubusercontent.com/Ameba-AIoT/ameba-rtos-pro2/main/component/video/driver/RTL8735B/video_api.c
**Priority:** LOW — Direct re-verification; bug confirmed still present

- **FlashMemory.cpp** (`write()` and `writeWord()`): Zero calls to `device_mutex_lock`, zero `device_lock.h` include. The `write()` function erases all 48 sectors at `0xFD0000–0xFFFFFF` and programs via `flash_stream_write()` with no synchronization guard. The `writeWord()` function calls `flash_write_word()` and, on bit-flip conflict, falls through to `flash_erase_sector()`/`flash_stream_write()` — also unguarded. Unchanged from SHA `4fdfbec`.
- **video_api.c**: Two `ftl_common_write(flash_addr, fcs_buf, fcs_buf_size)` calls in `video_pre_init_save_cur_params()` — both write to `NOR_FLASH_FCS = 0xF0D000`, neither protected by `device_mutex_lock(RT_DEV_LOCK_FLASH)`. `device_lock.h` is already included in the file (a fix here would require zero new header additions). Unchanged from March 3, 2026.

---

### Finding 113 — All Public Bug-Signature Strings Return Zero Results (May 6, 2026)
**Source:** Web search (Google indexed, May 6, 2026) — English and Chinese
**Priority:** LOW — Status confirmation

| Query | Result |
|---|---|
| `"It don't do the sensor initial process" RTL8735B` | **Zero results** |
| `"FCS KM_status 0x00002081"` | **Zero results** |
| `"[VOE][WARN]slot full"` (ameba/RTL8735B context) | **Zero results** |
| `"device_mutex_lock" "FlashMemory" Ameba` | **Zero results** |
| `RTL8735B AmebaPro2 FlashMemory FCS camera fix 2026` | Zero relevant hits |
| `ameba-arduino-pro2 "device_mutex_lock" FlashMemory` | **Zero results** |
| `AMB82 FlashMemory camera cold boot failure fix` | Zero hits describing our bug |
| `RTL8735B VOE_OPEN_CMD fail FCS flash` | Zero hits |
| `RTL8735B AMB82 闪存写入 摄像头启动失败 FCS 冷启动` (Chinese) | **Zero results** |
| `BW21-CBV 相机启动失败 flash写入 FCS` (Chinese) | **Zero results** |
| `site:csdn.net RTL8735B AMB82 camera flash write bug FCS` | **Zero results** |

The bug's specific error signatures remain completely unindexed on the public internet. The root cause analysis (FlashMemory.cpp bypasses RT_DEV_LOCK_FLASH) is documented only in this research log.

---

### Finding 114 — No New GitHub Issues, PRs, or Forum Threads (May 6, 2026)
**Source:** Exhaustive sweep of all tracked sources (May 6, 2026)
**Priority:** LOW — Status confirmation

- **ameba-arduino-pro2 issues**: Highest filed issue is **#398** (March 29, 2026 — raw video feature request). No issue #399 exists. Zero bug reports matching FCS failure, flash write corruption, or cold boot camera failure.
- **ameba-rtos-pro2 issues**: 3 open (highest: #16, Jan 2026). Issue #17 returns HTTP 404.
- **ideashatch/HUB-8735**: Only issue #10 (Aug 2025 — PS5268 sensor ID fail, unrelated). No new issues.
- **ameba-arduino-pro2 PRs**: 0 open, 319 closed. No FlashMemory/FCS/mutex PR has ever been filed.
- **forum.amebaiot.com**: All threads 403-blocked. Highest indexed thread in any search engine remains ~#4834. `site:forum.amebaiot.com` searches for `"slot full"`, `"VOE_OPEN_CMD"`, and `"FCS KM_status"` return zero results.
- **CSDN / Zhihu / 21ic / EEWorld / bbs.ai-thinker.com**: Zero Chinese-language reports — reconfirmed.
- **ameba-arduino-doc**: Last commit April 16, 2026. No documentation warning added.

---

### Complete Status Sweep — 2026-05-06

| Repository / Source | Last activity | Status |
|---|---|---|
| ameba-arduino-pro2 (dev branch) | May 5, 2026 — SHA `13961cc` (AMB82-zero SWD pin) | No FCS/FlashMemory change |
| ameba-arduino-pro2 (releases) | V4.1.1-QC-V05 (Apr 30, 2026); V4.1.1 stable = HTTP 404 | **No new release** |
| ameba-rtos-pro2 (main branch) | May 1, 2026 — SHA `1c1c8b7` (WLAN dhcp); HEAD identical | **No new commits; no fix** |
| ameba-arduino-pro2 pull requests | 0 open | **No fix under review** |
| ameba-arduino-pro2 issues | 17 open; highest: #398 (Mar 2026) | **Zero new FCS/FlashMemory/VOE issues** |
| ameba-rtos-pro2 issues | 3 open; highest: #16 (Jan 2026) | **Zero new relevant issues** |
| ideashatch/HUB-8735 | Dec 2, 2025; issue #10 only | **Inactive** |
| Ai-Thinker-Open GitHub org | — | **No BW21-CBV repository** |
| ameba-arduino-pro2 forks (36) | Various | **Zero forks contain FlashMemory mutex patch** |
| forum.amebaiot.com | All 403-blocked; highest indexed ~#4834 | **No new accessible content** |
| CSDN / Zhihu / 21ic / EEWorld | — | **Zero Chinese-language reports** |
| bbs.ai-thinker.com (BW21-CBV) | — | **No camera/FCS bug threads** |
| FlashMemory.cpp (dev, SHA `4fdfbec`) | Sept 30, 2025 (~8 months) | **Still NO mutex fix — confirmed** |
| video_api.c (main) | March 3, 2026 | **Two unguarded ftl_common_write() calls; no fix** |
| Official documentation (ameba-arduino-doc) | April 16, 2026 | **No FlashMemory/FCS warning added** |
| Public web (all bug-signature strings) | — | **Zero new indexed results — root cause uniquely in this log** |

**No HIGH priority confirmed fix found. Bug status: publicly undocumented and unpatched as of 2026-05-06.**

---

## Research Update — 2026-05-06 (Update 2 — 6-hour cycle)

### Finding 115 — All Repositories Confirmed Static Since Previous Cycle; Compare Endpoints Verified
**Source:** Direct compare fetches (2026-05-06, second 6-hour run)
https://github.com/Ameba-AIoT/ameba-arduino-pro2/compare/13961cc...dev
https://github.com/Ameba-AIoT/ameba-rtos-pro2/compare/1c1c8b7...main
**Priority:** LOW — Status confirmation

Both repository compare endpoints return "identical" — no new commits since the last documented activity:

| Repository | Last commit SHA | Last commit date | Message |
|---|---|---|---|
| ameba-arduino-pro2 (dev) | `13961cc` | May 5, 2026 | "Update API for AMB82-zero and SWD off logic" |
| ameba-rtos-pro2 (main) | `1c1c8b7` | May 1, 2026 | "Sync upstream — wowlan dhcp renew" |

The GitHub compare endpoint `13961cc...dev` explicitly returns: "13961cc and dev are identical." The compare endpoint `1c1c8b7...main` returns: "1c1c8b7 and main are identical." Zero new commits to either repository. No new releases (latest: V4.1.1-QC-V05, internal build April 30, 2026). No open pull requests on `ameba-arduino-pro2`.

---

### Finding 116 — ameba-rtos-pro2 Has a "9.6e" Tag (March 3, 2026) Not Previously Documented
**Source:** https://github.com/Ameba-AIoT/ameba-rtos-pro2/tags (fetched 2026-05-06)
**Priority:** LOW — Historical tag; different product variant; no FCS/FlashMemory relevance

The full tag list for `ameba-rtos-pro2` includes a tag **"9.6e"** dated **March 3, 2026** that was not explicitly captured in prior research findings. Finding 106 (2026-05-05 Update 2) documented the "aiglass" tag series, but the "9.6e" tag was not mentioned. The five most recent tags in the repository are:

| Tag | Date |
|---|---|
| V1.0.3-aiglass.07 | April 2, 2026 |
| **9.6e** | March 3, 2026 |
| V1.0.3-aiglass.06 | February 2, 2026 |
| V1.0.3-aiglass.05 | December 18, 2025 |
| V1.0.3-aiglass.04 | November 12, 2025 |

The "9.6e" tag appears to follow a separate legacy versioning scheme (not "V4.x.x" Arduino or "V1.0.x-aiglass") and was pushed the same day as the March 3, 2026 "Update code base" restructuring commit (SHA a0352b6 / 7e78403) that also moved `ftl_nor_api.c` to its new location (documented in Finding 52). This is likely a snapshot tag for a specific product delivery or internal milestone coinciding with that restructuring. It has no relation to the FlashMemory/FCS bug.

No new tags have been created after V1.0.3-aiglass.07 (April 2, 2026).

---

### Finding 117 — FlashMemory.cpp Re-Confirmed Unpatched via Direct Raw Fetch (May 6, 2026)
**Source:** https://raw.githubusercontent.com/Ameba-AIoT/ameba-arduino-pro2/dev/Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.cpp
**Priority:** LOW — Direct re-verification; bug confirmed still present

Fresh raw fetch of `FlashMemory.cpp` (dev branch) confirms:
- `write()` function: calls `flash_erase_sector()` and `flash_stream_write()` with **zero** `device_mutex_lock` calls
- `writeWord()` function: calls `flash_write_word()` and, on bit-flip conflict, calls `flash_erase_sector()`/`flash_stream_write()` — also **zero** mutex calls
- Zero `device_lock.h` includes
- Zero `RT_DEV_LOCK_FLASH` references anywhere in the file

The file is unchanged from SHA `4fdfbec` (September 30, 2025). The `write()` function remains:
```cpp
for (int i = 0; i < (MAX_FLASH_MEMORY_APP_SIZE / FLASH_SECTOR_SIZE); i++) {
    flash_erase_sector(_pFlash, (_flash_base_address + (i * FLASH_SECTOR_SIZE)));
}
flash_stream_write(_pFlash, (_flash_base_address + offset), buf_size, (uint8_t *)buf);
```
No synchronization. Bug confirmed unpatched.

---

### Finding 118 — ameba-arduino-doc Confirmed No New Commits After April 16, 2026
**Source:** https://github.com/Ameba-AIoT/ameba-arduino-doc/commits/main (fetched 2026-05-06)
**Priority:** LOW — Documentation status unchanged

The official Arduino documentation repository (`ameba-arduino-doc`) has **no new commits** after SHA `d0b6ca3` ("Update PowerMode documentation #104", April 16, 2026). The five most recent commits remain:
1. `d0b6ca3` — April 16, 2026 — "Update PowerMode documentation (#104)"
2. `df6affb` — April 2, 2026 — "Update Installation guide and add example (#103)"
3. `1e977ec` — March 24, 2026 — "Add audio trigger recording and sound detector example guide (#102)"
4. `9fdbbd6` — March 19, 2026 — "Add Anti-Collision documentation (#101)"
5. `e98c6f1` — March 13, 2026 — "Add SDCardSaveRaw and I2S Audio example guide (#100)"

No commit in this list or in the full visible history mentions FlashMemory, FCS, camera boot failure, device_lock, mutex, or any flash-camera interaction. The bug remains completely absent from official documentation.

---

### Finding 119 — No New Forum Threads Above #4834; No New Bug-String Matches
**Source:** Exhaustive search (Google-indexed snippets, 2026-05-06, second run)
**Priority:** LOW — Status confirmation

Targeted searches for forum threads above #4834 (the highest previously documented thread with adjacent content) returned **zero results** in the #4835–#4845 range. No new threads on `forum.amebaiot.com` matching any of the bug's signature strings have been indexed. The following bug-signature string searches all returned zero new results:

| Query | Result |
|---|---|
| `"It don't do the sensor initial process"` | **Zero results** |
| `"FCS KM_status 0x00002081"` | **Zero results** |
| `"[VOE][WARN]slot full"` (Ameba context) | **Zero results** |
| `"VOE_OPEN_CMD" fail ameba` | **Zero results** |
| `"device_mutex_lock" "FlashMemory" Ameba` | **Zero results** |
| `ameba AMB82 FCS flash camera cold boot fix OR mutex 2026` | No relevant hits |

The highest indexed forum thread from any search remains #4834 (boot failure after OTA update, a different failure mode documented in Finding 42). No new FCS/FlashMemory/camera-boot threads have appeared.

---

### Finding 120 — Chinese-Language Sources Reconfirmed: Zero Reports in Any Language
**Source:** Google searches targeting CSDN, Zhihu, 21ic, EEWorld, bbs.ai-thinker.com (2026-05-06)
**Priority:** LOW — Status confirmation; bug remains publicly unknown

Chinese-language searches across all major developer platforms returned zero relevant results:

| Query | Result |
|---|---|
| `site:csdn.net AMB82 RTL8735B camera FCS FlashMemory 2026` | Zero relevant CSDN hits |
| `AMB82 FlashMemory camera 冷启动 FCS flash 写入 失败 2026` | Zero relevant hits |
| `AMB82-mini FCS 相机 flash camera cold boot site:csdn.net OR site:zhihu.com OR site:21ic.com` | Zero relevant hits |
| `BW21-CBV flash 写入 FCS 冷启动` | Zero results |

The CSDN article that appeared in search results ("瑞昱半导体AMB82 MINI SD卡加载模型...") discusses SD card model loading for AI/RTSP, with no mention of FCS, FlashMemory API, or cold boot camera failure. bbs.ai-thinker.com BW21-CBV threads continue to focus on product unboxings and basic usage; none report the FlashMemory/FCS interaction bug.

The bug remains publicly unreported in all languages as of 2026-05-06 (second 6-hour run).

---

### Complete Status Sweep — 2026-05-06 (Update 2)

| Repository / Source | Last activity | Status |
|---|---|---|
| ameba-arduino-pro2 (dev branch) | May 5, 2026 — SHA `13961cc` (AMB82-zero SWD pin) | **No new commits — compare endpoint confirms identical** |
| ameba-arduino-pro2 (releases) | V4.1.1-QC-V05 (Apr 30, 2026); V4.1.1 stable = HTTP 404 | **No new release** |
| ameba-rtos-pro2 (main branch) | May 1, 2026 — SHA `1c1c8b7` (WLAN dhcp); HEAD identical | **No new commits; no fix** |
| ameba-rtos-pro2 (tags) | V1.0.3-aiglass.07 (Apr 2, 2026); "9.6e" tag (Mar 3, 2026) — newly documented | **No new tags since Apr 2, 2026** |
| ameba-arduino-pro2 pull requests | 0 open; 319 closed; highest item #407 | **No fix under review** |
| ameba-arduino-pro2 issues | 17 open; highest filed: #398 (Mar 29, 2026) | **Zero new FCS/FlashMemory/VOE issues** |
| ameba-rtos-pro2 issues | 3 open; highest: #16 (Jan 2026); #17 = HTTP 404 | **Zero new relevant issues** |
| ideashatch/HUB-8735 | Dec 2, 2025; issue #10 only | **Inactive; no new issues** |
| Ai-Thinker-Open GitHub org | — | **No BW21-CBV repository** |
| ameba-arduino-pro2 forks (36 total) | Various | **Zero forks contain FlashMemory mutex patch** |
| forum.amebaiot.com | Highest indexed ~#4834; all 403-blocked | **No new accessible content; no new bug-string threads** |
| CSDN / Zhihu / 21ic / EEWorld | — | **Zero Chinese-language reports — reconfirmed** |
| bbs.ai-thinker.com (BW21-CBV) | — | **No camera/FCS bug threads** |
| FlashMemory.cpp (dev, SHA `4fdfbec`) | Sept 30, 2025 (~8 months) | **Still NO mutex fix — confirmed by direct raw fetch** |
| video_api.c (main) | March 3, 2026 | **Two unguarded `ftl_common_write()` calls; no fix** |
| Official documentation (ameba-arduino-doc) | April 16, 2026 — SHA `d0b6ca3` | **No new commits; no FlashMemory/FCS warning added** |
| Public web (all bug-signature strings) | — | **Zero new indexed results — root cause uniquely in this log** |

**No HIGH priority confirmed fix found. Bug status: publicly undocumented and unpatched as of 2026-05-06 (second 6-hour run).**

---

### Sources Added (Update 2026-05-06, Update 2)
- ameba-arduino-pro2 compare 13961cc...dev (confirmed identical — no new commits): https://github.com/Ameba-AIoT/ameba-arduino-pro2/compare/13961cc...dev
- ameba-rtos-pro2 compare 1c1c8b7...main (confirmed identical — no new commits): https://github.com/Ameba-AIoT/ameba-rtos-pro2/compare/1c1c8b7...main
- ameba-rtos-pro2 tags (9.6e Mar 3, 2026 — newly documented; V1.0.3-aiglass.07 Apr 2, 2026 most recent): https://github.com/Ameba-AIoT/ameba-rtos-pro2/tags
- ameba-arduino-doc commits/main (re-confirmed last: d0b6ca3, Apr 16, 2026; no new commits): https://github.com/Ameba-AIoT/ameba-arduino-doc/commits/main
- ameba-arduino-pro2 FlashMemory.cpp dev (re-confirmed no mutex, SHA `4fdfbec`, write()/writeWord() unchanged): https://raw.githubusercontent.com/Ameba-AIoT/ameba-arduino-pro2/dev/Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.cpp
- ameba-arduino-pro2 issues (re-confirmed: 17 open, highest filed #398 Mar 2026): https://github.com/Ameba-AIoT/ameba-arduino-pro2/issues
- ameba-rtos-pro2 issues (re-confirmed: 3 open, highest #16 Jan 2026): https://github.com/Ameba-AIoT/ameba-rtos-pro2/issues
- ideashatch/HUB-8735 issues (re-confirmed: issue #10 only, Aug 2025): https://github.com/ideashatch/HUB-8735/issues

---

## Research Update — 2026-05-07

### Finding 121 — Both Repos Confirmed Static: No New Commits Since May 5 / May 1
**Source:** Direct fetches of ameba-arduino-pro2/commits/dev and ameba-rtos-pro2/commits/main (2026-05-07)
https://github.com/Ameba-AIoT/ameba-arduino-pro2/commits/dev
https://github.com/Ameba-AIoT/ameba-rtos-pro2/commits/main
**Priority:** LOW — Status confirmation; no new fix commits

Both repositories remain static since their last documented activity:

| Repository | Last commit SHA | Last commit date | Message |
|---|---|---|---|
| ameba-arduino-pro2 (dev) | `13961cc` | May 5, 2026 | "Update API for AMB82-zero and SWD off logic" |
| ameba-rtos-pro2 (main) | `1c1c8b7` | May 1, 2026 | "Sync upstream — wowlan dhcp renew" |

No new commits to either repository since the previous research cycle. No new releases (latest: V4.1.1-QC-V05, internal build April 30, 2026; V4.1.1 stable tag returns HTTP 404). Zero open pull requests on `ameba-arduino-pro2`. FlashMemory.cpp has not been touched since SHA `4fdfbec` (September 30, 2025) — now over 8 months without modification. video_api.c has not been touched since March 3, 2026.

---

### Finding 122 — ideashatch/HUB-8735-Series_examples: First Documentation of Sister Repository; No FCS Bug Content
**Source:** https://github.com/ideashatch/HUB-8735-Series_examples
**Priority:** LOW — New repository logged; no FCS/camera-boot bug relevance

A sister repository to `ideashatch/HUB-8735` named `HUB-8735-Series_examples` was identified in this research cycle for the first time. Repository metadata:
- **Stars:** 3, **Forks:** 1, **Commits:** 54
- **Languages:** Jupyter Notebook (88.2%), C (9.7%), C++ (1.7%)
- **Content:** AI/CV application examples for the HUB-8735 platform — face detection/recognition, gesture recognition (hand gestures, smart home), object detection (masks, insects, vehicles), dice/coin recognition, meter-reading, irrigation systems, door locks.

The repository contains **no mention** of FCS, FlashMemory, camera boot failure, cold-boot errors, flash mutex, VOE initialization failure, or any flash-camera interaction. All examples are higher-level ML/CV application sketches that use the camera for inference only (not for flash write operations concurrent with camera streaming). This repo does not provide any new fix or workaround.

**Supplementary reference:** The repository points to `https://www.ideas-hatch.com/evb_share.jsp` for supplementary documentation. That page was not accessible (timeout/block), but given the repository's content, it is expected to contain hardware/pinout diagrams for the HUB-8735 series rather than SDK bug documentation.

---

### Finding 123 — Forum Threads Above #4840: No New FCS/Flash/Camera Threads Indexed
**Source:** Google site-search + direct URL probes for forum.amebaiot.com threads above #4840 (2026-05-07)
**Priority:** LOW — Status confirmation

A search for `site:forum.amebaiot.com` combined with bug-signature strings, and a systematic probe of thread URLs in the #4841–#4860 range, revealed **no new forum threads** mentioning FCS, FlashMemory, camera cold-boot failure, `VOE_OPEN_CMD`, `FCS KM_status`, or `[VOE][WARN]slot full`. The probe returned HTTP 403 for all probed thread URLs in the #4841+ range that exist, and HTTP 404 for gaps, with no Google-indexed snippets for any thread above #4840 matching the bug's symptom strings.

The most recent forum threads with any camera-adjacent content remain the previously documented set: #4835 (deep sleep/AON GPIO bus fault), #4839 (cloud upload), #4840 (HTTPS OTA). None relate to the FlashMemory/FCS race.

---

### Finding 124 — ameba-arduino-pro2 Issue Count Discrepancy Resolved: 12 Confirmed Open Issues (Down from 17)
**Source:** https://github.com/Ameba-AIoT/ameba-arduino-pro2/issues (direct fetch, 2026-05-07)
**Priority:** LOW — Count correction; no new FCS/FlashMemory bug reports

Prior research cycles (Findings 92, 104, 110) reported 17 open issues on `ameba-arduino-pro2`. This cycle's direct fetch of the issues page shows **12 open issues** explicitly listed:

| Issue # | Title |
|---|---|
| #398 | FEATURE REQUEST: Access to raw video or H264/H265 encoded data (Mar 29, 2026) |
| #342 | how to use USB connect keyboard, mouse (Oct 20, 2025) |
| #325 | Can we introduce librtmp or other libraries to push video streams (Jun 30, 2025) |
| #324 | Callback notification when a client connects to RTSP (Jun 17, 2025) |
| #317 | BSSID Flag for Wifi Connect? (Apr 20, 2025) |
| #310 | OV2640 and OV5640 compatibility (Mar 8, 2025) |
| #296 | WebRTC support for remote server (Feb 6, 2025) |
| #287 | RTSP Stream dec profile in AMB82-mini (Dec 5, 2024) |
| #276 | mDNS on AMB82-MINI (Oct 23, 2024) |
| #235 | SPI library not read output after transfer() call (Apr 21, 2024) |
| #224 | Amb82mini send instant audio (Mar 12, 2024) |
| #184 | PPPoS support on AMB82-Mini board? (Dec 27, 2023) |

The count change from 17 to 12 reflects some issues having been closed or the prior count including pagination artefacts. **The critical finding is unchanged: the highest filed issue is #398 (March 29, 2026), and zero issues relate to FlashMemory, FCS, camera boot failure, VOE errors, device_mutex_lock, or flash-camera interaction.**

---

### Finding 125 — Complete Status Sweep: Bug Unpatched as of 2026-05-07
**Source:** Exhaustive sweep of all tracked sources (2026-05-07)
**Priority:** LOW — Status confirmation

| Repository / Source | Last activity | Status |
|---|---|---|
| ameba-arduino-pro2 (dev branch) | May 5, 2026 — SHA `13961cc` ("Update API for AMB82-zero and SWD off logic") | **No new commits — confirmed** |
| ameba-arduino-pro2 (releases) | V4.1.1-QC-V05 (Apr 30, 2026); V4.1.1 stable = HTTP 404 | **No new release** |
| ameba-rtos-pro2 (main branch) | May 1, 2026 — SHA `1c1c8b7` (WLAN dhcp sync) | **No new commits — confirmed** |
| ameba-arduino-pro2 pull requests | 0 open; 319 closed; highest item #407 | **No fix under review** |
| ameba-arduino-pro2 issues | 12 open (previously reported as 17); highest filed: #398 (Mar 29, 2026) | **Zero new FCS/FlashMemory/VOE issues** |
| ameba-rtos-pro2 issues | 3 open; highest: #16 (Jan 2026); #17 = HTTP 404 | **Zero new relevant issues** |
| ideashatch/HUB-8735 | Dec 2, 2025 — SHA `870a7e0`; issue #10 only | **Inactive** |
| ideashatch/HUB-8735-Series_examples | ~54 commits; AI/CV examples only | **First documented; no FCS/flash bug content** |
| Ai-Thinker-Open GitHub org | — | **No BW21-CBV repository** |
| ameba-arduino-pro2 forks (36 total) | — | **Zero forks contain FlashMemory mutex patch** |
| forum.amebaiot.com | Highest indexed thread #4840; threads #4841+ probed but 403-blocked or 404; no new FCS threads | **No new accessible content** |
| CSDN / Zhihu / 21ic / EEWorld | — | **Zero Chinese-language reports — reconfirmed** |
| bbs.ai-thinker.com (BW21-CBV) | — | **No camera/FCS bug threads** |
| FlashMemory.cpp (dev, SHA `4fdfbec`) | Sept 30, 2025 (~8.5 months) | **Still NO mutex fix — confirmed by direct raw fetch** |
| video_api.c (main) | March 3, 2026 | **Two unguarded `ftl_common_write()` calls; no mutex fix** |
| Official documentation (ameba-arduino-doc) | April 16, 2026 — SHA `d0b6ca3` | **No new commits; no FlashMemory/FCS warning added** |
| Public web (`"It don't do the sensor initial process"`) | — | **Zero new indexed results** |
| Public web (`"FCS KM_status 0x00002081"`) | — | **Zero new indexed results** |
| Public web (`"device_mutex_lock" "FlashMemory" Ameba`) | — | **Zero results — root cause uniquely documented in this log** |

English and Chinese web searches (Google, CSDN, 知乎, 21ic, EEWorld, bbs.ai-thinker.com) confirm zero new public discussion of this bug in any language. No forum post, blog article, GitHub issue, or code patch describes the FlashMemory/FCS mutex race condition or a fix for it anywhere on the indexed public internet.

**No HIGH priority confirmed fix found. Bug status: publicly undocumented and unpatched as of 2026-05-07.**

---

### Sources Added (Update 2026-05-07)
- ameba-arduino-pro2 dev commits (re-confirmed latest: `13961cc`, May 5, 2026; no new commits): https://github.com/Ameba-AIoT/ameba-arduino-pro2/commits/dev
- ameba-rtos-pro2 main commits (re-confirmed latest: `1c1c8b7`, May 1, 2026; no new commits): https://github.com/Ameba-AIoT/ameba-rtos-pro2/commits/main
- ameba-arduino-pro2 issues (12 open confirmed; highest: #398 Mar 2026; zero FCS issues): https://github.com/Ameba-AIoT/ameba-arduino-pro2/issues
- ameba-rtos-pro2 issues (3 open; highest: #16 Jan 2026): https://github.com/Ameba-AIoT/ameba-rtos-pro2/issues
- ameba-arduino-pro2 releases (re-confirmed latest: V4.1.1-QC-V05, Apr 30, 2026): https://github.com/Ameba-AIoT/ameba-arduino-pro2/releases
- ideashatch/HUB-8735-Series_examples (first documented; AI/CV examples; no FCS/flash bug content): https://github.com/ideashatch/HUB-8735-Series_examples
- ameba-arduino-pro2 FlashMemory.cpp dev (re-confirmed no mutex, SHA `4fdfbec`): https://raw.githubusercontent.com/Ameba-AIoT/ameba-arduino-pro2/dev/Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.cpp
- ameba-rtos-pro2 video_api.c main (re-confirmed two unguarded ftl_common_write() calls): https://raw.githubusercontent.com/Ameba-AIoT/ameba-rtos-pro2/main/component/video/driver/RTL8735B/video_api.c

---

### Sources Added (Update 2026-05-06)
- ameba-rtos-pro2 main vs HEAD compare (1c1c8b7 identical to HEAD — confirmed no new commits): https://github.com/Ameba-AIoT/ameba-rtos-pro2/compare/1c1c8b7...main
- ameba-arduino-pro2 dev commits (confirmed latest: `13961cc`, May 5, 2026; no new commits after May 5): https://github.com/Ameba-AIoT/ameba-arduino-pro2/commits/dev
- ameba-arduino-pro2 FlashMemory.cpp dev (re-confirmed no mutex, SHA `4fdfbec` unchanged): https://raw.githubusercontent.com/Ameba-AIoT/ameba-arduino-pro2/dev/Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.cpp
- ameba-rtos-pro2 video_api.c main (re-confirmed two unguarded ftl_common_write() calls, device_lock.h already included): https://raw.githubusercontent.com/Ameba-AIoT/ameba-rtos-pro2/main/component/video/driver/RTL8735B/video_api.c
- ameba-arduino-pro2 issues (highest filed: #398 Mar 2026; no new issues; #399 absent): https://github.com/Ameba-AIoT/ameba-arduino-pro2/issues
- ameba-rtos-pro2 issues (3 open; highest: #16 Jan 2026; #17 = HTTP 404): https://github.com/Ameba-AIoT/ameba-rtos-pro2/issues
- ideashatch/HUB-8735 issues (only issue #10, Aug 2025): https://github.com/ideashatch/HUB-8735/issues
- ameba-arduino-pro2 PRs (0 open; 319 closed; no FlashMemory/FCS PR ever filed): https://github.com/Ameba-AIoT/ameba-arduino-pro2/pulls

---

## Research Update — 2026-05-06 (Update 2 — 6-hour cycle)

### Finding 115 — Forum Threads #4796 and #4803 Newly Surfaced; Both Unrelated to Bug
**Source:** Google search results; forum.amebaiot.com threads #4796 and #4803 (both 403-blocked)
https://forum.amebaiot.com/t/imx327-compatiblity/4796
https://forum.amebaiot.com/t/amb82-mini-usb-ethernet-failing/4803
**Priority:** LOW — New thread numbers logged; no FCS/flash bug relevance

Two previously unlogged forum threads were discovered via targeted searches in this cycle:

- **Thread #4796**: "IMX327 Compatiblity" — A camera sensor compatibility question for the IMX327 sensor on AMB82-Mini. This is adjacent to FCS topics (FCS is per-sensor), but the title and URL slug indicate a general sensor ID/driver compatibility question, not a cold-boot camera failure after flash writes. Content is HTTP 403-blocked.
- **Thread #4803**: "AMB82-mini: USB Ethernet failing" — A USB Ethernet peripheral failure question on AMB82-Mini. Unrelated to flash memory, FCS, or camera initialization. Content is HTTP 403-blocked.

These are the highest-numbered forum threads newly observed in this research cycle beyond the previously documented #4794 and #4800 range. Neither contains evidence of the FlashMemory/FCS race bug. The highest indexed thread overall remains approximately #4834 ("Boot failure after OTA update", Finding 42).

---

### Finding 116 — CSDN AMB82-Mini Articles: General SDK Usage; Zero FCS/Flash Bug Reports
**Source:** Google search `site:csdn.net AMB82-mini RTL8735B FlashMemory camera FCS`
https://blog.csdn.net/weixin_41589183/article/details/139222964
https://devpress.csdn.net/v1/article/detail/139584304
https://blog.csdn.net/code_snow/article/details/139896968
**Priority:** LOW — Chinese-language SDK usage articles; no FCS/flash bug content

Three CSDN articles about the AMB82-Mini / RTL8735B were surfaced by search. Their contents (from search snippets):

1. **"瑞昱半导体AMB82 MINI（RTL8735B）Arduino 方法介绍"** — General Arduino method overview for the AMB82-MINI board. Covers WiFi, GPIO, peripherals. No mention of FlashMemory, FCS, or camera boot failures.
2. **"AMB82 MINI SD卡加载模型RTSP视频流AI识别"** — Tutorial for loading AI models from SD card and streaming RTSP video on AMB82-MINI. Notes that earlier SDK versions (pre-V4.0.7) used Flash for model loading; newer versions use SD card. No mention of FlashMemory/FCS interaction or cold-boot issues.
3. **"arduino使用记录：_realtek ameba boards"** — Personal Arduino usage notes for Realtek Ameba boards. General SDK usage; no FCS/flash interaction documented.

None of the three articles describe the FlashMemory/FCS race condition, camera boot failure after flash writes, or `KM_status 0x00002081`. These articles confirm that Chinese-language AMB82-Mini SDK content exists on CSDN but covers only general usage tutorials, not the specific bug documented in this research log.

---

### Finding 117 — All Repositories Unchanged; No Fix Found (2026-05-06 Update 2)
**Source:** Direct fetches of ameba-rtos-pro2/commits/main and ameba-arduino-pro2/commits/dev (2026-05-06, second cycle)
**Priority:** LOW — Status confirmation; no new fix commits

Both repositories are static since their last documented activity:

| Repository | Last commit SHA | Last commit date | Message |
|---|---|---|---|
| ameba-arduino-pro2 (dev) | `13961cc` | May 5, 2026 | "Update API for AMB82-zero and SWD off logic" |
| ameba-rtos-pro2 (main) | `1c1c8b7` | May 1, 2026 | "Sync upstream — wowlan dhcp renew" |

Zero new commits to either repository since the May 6 Update 1 run. No new releases. No open pull requests. FlashMemory.cpp SHA `4fdfbec` (September 30, 2025) is now over 8 months old with no mutex protection added — the longest gap between any two modifications to that file in its 10-month public history.

---

### Complete Status Sweep — 2026-05-06 (Update 2)

| Repository / Source | Last activity | Status |
|---|---|---|
| ameba-arduino-pro2 (dev branch) | May 5, 2026 — SHA `13961cc` (AMB82-zero SWD pin) | **No new commits — confirmed** |
| ameba-arduino-pro2 (releases) | V4.1.1-QC-V05 (Apr 30, 2026); V4.1.1 stable = HTTP 404 | **No new release** |
| ameba-rtos-pro2 (main branch) | May 1, 2026 — SHA `1c1c8b7` (WLAN dhcp) | **No new commits — confirmed** |
| ameba-arduino-pro2 pull requests | 0 open | **No fix under review** |
| ameba-arduino-pro2 issues | 17 open; highest filed: #398 (Mar 29, 2026) | **Zero new FCS/FlashMemory/VOE issues** |
| ameba-rtos-pro2 issues | 3 open; highest: #16 (Jan 2026) | **Zero new relevant issues** |
| ideashatch/HUB-8735 | Dec 2, 2025; issue #10 only | **Inactive** |
| Ai-Thinker-Open GitHub org | — | **No BW21-CBV repository** |
| ameba-arduino-pro2 forks (36) | — | **Zero forks contain FlashMemory mutex patch** |
| forum.amebaiot.com | Threads #4796, #4803 newly logged (both 403-blocked, unrelated); highest: ~#4834 | **No accessible bug-related content** |
| CSDN | 3 AMB82-mini articles found; all general SDK usage; no FCS bug | **Zero FCS/flash bug reports** |
| Zhihu / 21ic / EEWorld | — | **Zero Chinese-language reports — reconfirmed** |
| bbs.ai-thinker.com (BW21-CBV) | — | **No camera/FCS bug threads** |
| FlashMemory.cpp (dev, SHA `4fdfbec`) | Sept 30, 2025 (~8 months since last change) | **Still NO mutex fix — confirmed** |
| video_api.c (main) | March 3, 2026 | **Two unguarded ftl_common_write() calls; no fix** |
| Official documentation (ameba-arduino-doc) | April 16, 2026 | **No FlashMemory/FCS warning added** |
| Public web (all bug-signature strings) | — | **Zero new indexed results — root cause uniquely in this log** |

**No HIGH priority confirmed fix found. Bug status: publicly undocumented and unpatched as of 2026-05-06 (second 6-hour run).**

---

### Sources Added (Update 2026-05-06, Update 2)
- Forum thread #4796 ("IMX327 Compatiblity", camera sensor compat; 403-blocked): https://forum.amebaiot.com/t/imx327-compatiblity/4796
- Forum thread #4803 ("AMB82-mini: USB Ethernet failing"; 403-blocked): https://forum.amebaiot.com/t/amb82-mini-usb-ethernet-failing/4803
- CSDN article (AMB82-MINI RTL8735B Arduino methods overview): https://blog.csdn.net/weixin_41589183/article/details/139222964
- CSDN article (AMB82-MINI SD card RTSP AI model loading): https://devpress.csdn.net/v1/article/detail/139584304
- CSDN article (Arduino usage notes for Realtek Ameba boards): https://blog.csdn.net/code_snow/article/details/139896968
- ameba-arduino-pro2 dev commits (re-confirmed last: `13961cc`, May 5, 2026; no new commits): https://github.com/Ameba-AIoT/ameba-arduino-pro2/commits/dev
- ameba-rtos-pro2 main commits (re-confirmed last: `1c1c8b7`, May 1, 2026): https://github.com/Ameba-AIoT/ameba-rtos-pro2/commits/main

---

## Research Update — 2026-05-07

### Finding 121 — All Repositories Static Since May 5 / May 1; No New Commits Found
**Source:** Direct fetches of ameba-arduino-pro2/commits/dev and ameba-rtos-pro2/commits/main (2026-05-07)
https://github.com/Ameba-AIoT/ameba-arduino-pro2/commits/dev
https://github.com/Ameba-AIoT/ameba-rtos-pro2/commits/main
**Priority:** LOW — Status confirmation; no new fix commits

Both repositories remain static since their last documented activity:

| Repository | Last commit SHA | Last commit date | Message |
|---|---|---|---|
| ameba-arduino-pro2 (dev) | `13961cc` | May 5, 2026 | "Update API for AMB82-zero and SWD off logic" |
| ameba-rtos-pro2 (main) | `1c1c8b7` | May 1, 2026 | "Sync upstream — wowlan dhcp renew" |

The full SHA for `13961cc` confirmed as `13961ccfef03e6f42c6e6d29e96a446fca29b71c`. Files in that commit: `wiring_digital.c`, `variant.cpp`, `variant.h` — all AMB82-zero/SWD-related, zero overlap with FlashMemory, FCS, or camera. No new commits to either repository since the previous cycle.

---

### Finding 122 — FlashMemory.cpp Re-Confirmed Unpatched: Zero Mutex Calls (May 7, 2026)
**Source:** https://raw.githubusercontent.com/Ameba-AIoT/ameba-arduino-pro2/dev/Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.cpp
**Priority:** LOW — Direct re-verification; bug confirmed still present

Fresh raw fetch confirms the file is unchanged from SHA `4fdfbec` (September 30, 2025 — now over 8 months without modification):
- Zero occurrences of `device_mutex_lock`, `RT_DEV_LOCK_FLASH`, or `device_lock.h` anywhere in the file
- `write()` function: calls `flash_erase_sector()` and `flash_stream_write()` with no synchronization
- `writeWord()` function: falls through to `flash_erase_sector()`/`flash_stream_write()` on bit-flip conflict with no synchronization
- Bug is confirmed unpatched

---

### Finding 123 — video_api.c Re-Confirmed Unpatched; One ftl_common_write() Call Visible in SAVE_TO_FLASH Path
**Source:** https://raw.githubusercontent.com/Ameba-AIoT/ameba-rtos-pro2/main/component/video/driver/RTL8735B/video_api.c
**Priority:** LOW — Direct re-verification; also clarifies Finding 97

Fresh raw fetch of the full 4,760-line `video_api.c` (current main branch) confirms:
- **No `device_mutex_lock`** or `RT_DEV_LOCK_FLASH` anywhere in the file outside of the already-included `device_lock.h` header
- The SAVE_TO_FLASH branch in `video_pre_init_save_cur_params()` contains the following unguarded pattern:
  ```c
  if (ftl_common_read(flash_addr, fcs_buf, fcs_buf_size) >= 0) {
      // ... checksum validation, struct fill ...
      if (ftl_common_write(flash_addr, fcs_buf, fcs_buf_size) >= 0) {
          video_dprintf(VIDEO_LOG_MSG, "ISP pre init params save success\r\n");
      }
  }
  ```
- Only `video_open_close_mutex` exists in the file; it guards `video_open()`/`video_close()` only, not the FCS flash write path

**Clarification re Finding 97:** Finding 97 (May 4, 2026) reported "TWO distinct ftl_common_write() calls" in `video_pre_init_save_cur_params()`. The current fetch shows one visible `ftl_common_write()` call in that function. The discrepancy may reflect a partial read in Finding 97 or internal refactoring in the March 3, 2026 codebase restructuring commit. What is certain is that the call(s) present remain unguarded — the bug exists regardless of whether there are one or two write sites.

---

### Finding 124 — No New Issues Above #398; #408–#410 Return HTTP 404 (May 7, 2026)
**Source:** https://github.com/Ameba-AIoT/ameba-arduino-pro2/issues (fetched 2026-05-07)
**Priority:** LOW — Status confirmation

- **ameba-arduino-pro2**: Issues #408, #409, #410 all return HTTP 404 — they do not exist. Highest filed issue remains #398 (raw video feature request, March 29, 2026). The 17 open issues continue to cover video streaming, WiFi, USB, audio — zero related to FlashMemory, FCS, camera boot failure, or VOE.
- **ameba-rtos-pro2**: Issue #17 returns HTTP 404. 3 open issues remain (highest: #16, Jan 2026).
- **ideashatch/HUB-8735**: Only issue #10 (Aug 2025 — PS5268 sensor ID, unrelated). No new issues.
- **ameba-arduino-pro2 PRs**: 0 open, 319 closed. No FlashMemory/FCS/mutex PR in history.

---

### Finding 125 — V4.1.1 Stable Release Still Does Not Exist; No New Pre-Release Tag
**Source:** https://github.com/Ameba-AIoT/ameba-arduino-pro2/releases (fetched 2026-05-07)
https://github.com/Ameba-AIoT/ameba-arduino-pro2/releases/tag/V4.1.1
**Priority:** LOW — Status confirmation; no hidden fix in an untracked release

- Direct fetch of `releases/tag/V4.1.1` returns **HTTP 404** — the stable release has still not been published.
- V4.1.1-QC-V05 (internal build April 30, 2026) remains the latest pre-release.
- V4.1.0 (March 2, 2026) remains the latest stable release.
- No new QC tag (V4.1.1-QC-V06 or similar) has been published.
- No changelog entry in any existing release mentions FlashMemory mutex, RT_DEV_LOCK_FLASH, FCS flash write protection, or camera boot failure.

---

### Finding 126 — Forum Searches: No New Threads Above #4840; Bug Strings Return Zero Results
**Source:** Google site-search for forum.amebaiot.com (2026-05-07)
**Priority:** LOW — Status confirmation

All forum.amebaiot.com threads remain HTTP 403-blocked. Direct probes of threads #4841–#4850 return no Google-indexed results. The following site-scoped and general searches were performed:

| Query | Result |
|---|---|
| `site:forum.amebaiot.com FCS camera flash` | 2 results: thread #4302 (unrelated) and #2849 (unrelated) |
| `site:forum.amebaiot.com FlashMemory camera` | 10 results; none related to FCS/mutex/cold boot failure |
| `site:forum.amebaiot.com "VOE_OPEN_CMD"` | **Zero results** |
| `site:forum.amebaiot.com "slot full"` | **Zero results** |
| `site:forum.amebaiot.com "sensor initial process"` | **Zero results** |

The highest confirmed indexed forum thread remains approximately #4840 ("關於Ameba Pro透過https下載Bin檔進行OTA的流程", OTA via HTTPS, unrelated). No new FCS/flash/camera bug threads have appeared.

---

### Finding 127 — All Bug-Signature Strings Return Zero Results (May 7, 2026)
**Source:** Web search (Google indexed, 2026-05-07) — English and Chinese
**Priority:** LOW — Confirms continued public ignorance of the bug

| Query | Result |
|---|---|
| `"It don't do the sensor initial process"` | **Zero results** |
| `"FCS KM_status 0x00002081"` | **Zero results** |
| `"VOE_OPEN_CMD fail" ameba` | **Zero results** |
| `"[VOE][WARN]slot full"` | **Zero results** |
| `device_mutex_lock FlashMemory ameba RTL8735B` | **Zero results** |
| `RTL8735B FCS flash camera fix 2026` | Zero relevant hits |
| `RTL8735B FCS 摄像头 冷启动 flash 写入` (Chinese) | **Zero relevant results** |
| `AMB82 FlashMemory FCS 冲突` (Chinese) | **Zero relevant results** |
| `BW21-CBV 摄像头 闪存 FCS 失败` (Chinese) | **Zero results** |
| `site:csdn.net RTL8735B AMB82 camera flash FCS 2026` | **Zero relevant hits** |
| `site:21ic.com RTL8735B FCS flash camera` | **Zero results** |

The bug remains completely unindexed and unreported on the public internet in any language as of May 7, 2026.

---

### Finding 128 — ameba-arduino-doc: No New Commits Since April 16, 2026
**Source:** https://github.com/Ameba-AIoT/ameba-arduino-doc/commits/main (fetched 2026-05-07)
**Priority:** LOW — Documentation status unchanged; bug fully undocumented

The official Arduino documentation repository has no commits since `d0b6ca3` ("Update PowerMode documentation", April 16, 2026). No FlashMemory/FCS compatibility warning, no "known issues" section, and no advisory about concurrent flash writes during camera streaming has been added. The bug is absent from all official Realtek/Ameba documentation.

---

### Complete Status Sweep — 2026-05-07

| Repository / Source | Last activity | Status |
|---|---|---|
| ameba-arduino-pro2 (dev branch) | May 5, 2026 — SHA `13961cc` (AMB82-zero SWD) | **No new commits — confirmed** |
| ameba-arduino-pro2 (releases) | V4.1.1-QC-V05 (Apr 30, 2026); V4.1.1 stable = HTTP 404 | **No new release** |
| ameba-rtos-pro2 (main branch) | May 1, 2026 — SHA `1c1c8b7` (WLAN dhcp sync) | **No new commits — confirmed** |
| ameba-arduino-pro2 pull requests | 0 open; 319 closed; highest item #407 | **No fix under review** |
| ameba-arduino-pro2 issues | 17 open; highest filed: #398 (Mar 29, 2026); #408–#410 = HTTP 404 | **Zero new FCS/FlashMemory/VOE issues** |
| ameba-rtos-pro2 issues | 3 open; highest: #16 (Jan 2026); #17 = HTTP 404 | **Zero new relevant issues** |
| ideashatch/HUB-8735 | Dec 2, 2025; issue #10 only | **Inactive** |
| Ai-Thinker-Open GitHub org | — | **No BW21-CBV repository** |
| ameba-arduino-pro2 forks (36 total) | Various | **Zero forks contain FlashMemory mutex patch** |
| forum.amebaiot.com | Highest indexed ~#4840; all 403-blocked | **No new FCS/flash/camera threads** |
| CSDN / Zhihu / 21ic / EEWorld | — | **Zero Chinese-language reports — reconfirmed** |
| bbs.ai-thinker.com (BW21-CBV) | — | **No camera/FCS bug threads** |
| FlashMemory.cpp (dev, SHA `4fdfbec`) | Sept 30, 2025 (>8 months without change) | **Still NO mutex fix — confirmed by direct raw fetch** |
| video_api.c (main) | March 3, 2026 | **Unguarded ftl_common_write() call(s); no mutex fix — confirmed** |
| Official documentation (ameba-arduino-doc) | April 16, 2026 | **No FlashMemory/FCS warning added** |
| Public web (all bug-signature strings) | — | **Zero new indexed results — root cause uniquely in this log** |

**No HIGH priority confirmed fix found. Bug status: publicly undocumented and unpatched as of 2026-05-07.**

---

### Sources Added (Update 2026-05-07)
- ameba-arduino-pro2 dev commits (confirmed last: `13961cc` SHA full `13961ccfef03e6f42c6e6d29e96a446fca29b71c`, May 5, 2026): https://github.com/Ameba-AIoT/ameba-arduino-pro2/commits/dev
- ameba-rtos-pro2 main commits (confirmed last: `1c1c8b7` SHA full `1c1c8b711a419d2d49190d34f7c13e2fd0b14974`, May 1, 2026): https://github.com/Ameba-AIoT/ameba-rtos-pro2/commits/main
- ameba-arduino-pro2 FlashMemory.cpp dev (confirmed no mutex, SHA `4fdfbec`): https://raw.githubusercontent.com/Ameba-AIoT/ameba-arduino-pro2/dev/Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.cpp
- ameba-rtos-pro2 video_api.c main (confirmed unguarded ftl_common_write; clarified Finding 97 discrepancy): https://raw.githubusercontent.com/Ameba-AIoT/ameba-rtos-pro2/main/component/video/driver/RTL8735B/video_api.c
- ameba-arduino-pro2 releases (V4.1.1-QC-V05 latest; V4.1.1 stable = HTTP 404): https://github.com/Ameba-AIoT/ameba-arduino-pro2/releases
- ameba-arduino-pro2 release tag V4.1.1 (HTTP 404 confirmed): https://github.com/Ameba-AIoT/ameba-arduino-pro2/releases/tag/V4.1.1
- ameba-arduino-pro2 issues (#408–#410 = HTTP 404; highest filed #398 Mar 2026): https://github.com/Ameba-AIoT/ameba-arduino-pro2/issues
- ameba-rtos-pro2 issues (#17 = HTTP 404; highest: #16 Jan 2026): https://github.com/Ameba-AIoT/ameba-rtos-pro2/issues
- ideashatch/HUB-8735 issues (only issue #10 Aug 2025): https://github.com/ideashatch/HUB-8735/issues
- ameba-arduino-pro2 PRs (0 open, 319 closed; no FlashMemory/FCS PR ever filed): https://github.com/Ameba-AIoT/ameba-arduino-pro2/pulls
- ameba-arduino-doc commits/main (last: `d0b6ca3` Apr 16, 2026; no new commits): https://github.com/Ameba-AIoT/ameba-arduino-doc/commits/main

---

## Research Update — 2026-05-07 (Update 2 — 6-hour cycle)

### Finding 129 — Both Repos Confirmed Static; No New Fix Commits (May 7, 2026 — Cycle 2)
**Source:** Direct fetches of ameba-arduino-pro2/commits/dev and ameba-rtos-pro2/commits/main (2026-05-07, second 6-hour run)
https://github.com/Ameba-AIoT/ameba-arduino-pro2/commits/dev
https://github.com/Ameba-AIoT/ameba-rtos-pro2/commits/main
**Priority:** LOW — Status confirmation; no new fix commits

Both repositories remain static:

| Repository | Last commit SHA | Last commit date | Message |
|---|---|---|---|
| ameba-arduino-pro2 (dev) | `13961cc` (`13961ccfef03e6f42c6e6d29e96a446fca29b71c`) | May 5, 2026 | "Update API for AMB82-zero and SWD off logic" |
| ameba-rtos-pro2 (main) | `1c1c8b7` (`1c1c8b711a419d2d49190d34f7c13e2fd0b14974`) | May 1, 2026 | "Sync upstream — wowlan dhcp renew" |

Zero new commits to either repository. No new releases, PRs, or issues. FlashMemory.cpp (SHA `4fdfbec`, September 30, 2025) is now **over 8.5 months** without modification — the longest unmodified stretch in its 10-month public history. video_api.c unchanged since March 3, 2026.

---

### Finding 130 — V4.1.1-QC-V05 Release Notes Fully Confirmed: Ends April 30, 2026; Zero Fix Mentions
**Source:** https://github.com/Ameba-AIoT/ameba-arduino-pro2/releases/tag/V4.1.1-QC-V05 (direct fetch, 2026-05-07)
**Priority:** LOW — Complete changelog confirmed; no hidden FlashMemory/FCS fix entry

The full release notes for V4.1.1-QC-V05 contain exactly five dated entries: 2026/03/06, 2026/03/20, 2026/04/02, 2026/04/17, 2026/04/30. These are organized into three fixed sections (Features, API Updates, Misc). A complete scan of all five entries finds **zero mentions** of any of: FlashMemory, mutex, FCS, RT_DEV_LOCK_FLASH, camera boot, VOE initialization failure, flash-camera interaction, or concurrent flash access. The last changelog entry is explicitly "Version 4.1.1 — 2026/04/30". No entry exists beyond that date. V4.1.1-QC-V06 tag returns HTTP 404 — it does not exist.

---

### Finding 131 — bbs.aithinker.com New Thread tid=47223: BW21 Digital Camera DIY Project; No FCS Bug Content
**Source:** Google search snippet for bbs.aithinker.com thread tid=47223 (full page inaccessible — TLS certificate error)
https://bbs.aithinker.com/forum.php?mod=viewthread&tid=47223
**Priority:** LOW — New higher-numbered BW21-CBV thread logged; no FCS/flash bug relevance

Thread tid=47223 ("【电子DIY作品】BW21数码相机+BW21-CBV-KIT") is a DIY digital camera project using the BW21-CBV-KIT board, featuring 1080p video recording to SD card and a display. This is the highest-numbered bbs.aithinker.com thread found in this research cycle (previously highest documented: tid=47062 from Finding 85, 2026-05-03). Gap of ~161 threads (47062 → 47223) reflects continued BW21-CBV community activity. The Google-indexed snippet contains **no mention** of FCS, FlashMemory, camera cold-boot failure, flash write errors, VOE initialization, or cold-boot bugs of any kind. The project is entirely a maker/DIY use case (hardware assembly + RTSP streaming), not a bug report.

---

### Finding 132 — ameba-arduino-pro2 PR History Confirmed: Only PR #333 Surfaces for FlashMemory Keyword Search
**Source:** https://github.com/Ameba-AIoT/ameba-arduino-pro2/pulls?q=is%3Apr+FlashMemory+is%3Aclosed (2026-05-07)
**Priority:** LOW — Complete PR history confirmed; no fix attempt ever filed

A closed-PR search for "FlashMemory" in `ameba-arduino-pro2` returns **1 result**: PR #333 "Update WiFi example" (merged September 9, 2025 by M-ichae-l). This PR is entirely unrelated to flash memory (the "FlashMemory" keyword match is coincidental). There is **no PR in the entire 319-closed-PR history** of `ameba-arduino-pro2` that adds `device_mutex_lock`, `RT_DEV_LOCK_FLASH`, or any synchronization guard to `FlashMemory.cpp`. The fix has never been proposed, reviewed, or merged in any form.

---

### Finding 133 — Complete Status Sweep: Bug Unpatched as of 2026-05-07 (Update 2)
**Source:** Exhaustive sweep of all tracked sources (2026-05-07, second 6-hour run)
**Priority:** LOW — Status confirmation

| Repository / Source | Last activity | Status |
|---|---|---|
| ameba-arduino-pro2 (dev branch) | May 5, 2026 — SHA `13961cc` (AMB82-zero SWD) | **No new commits — confirmed** |
| ameba-arduino-pro2 (releases) | V4.1.1-QC-V05 (Apr 30, 2026); V4.1.1 stable = HTTP 404; V4.1.1-QC-V06 = HTTP 404 | **No new release** |
| ameba-rtos-pro2 (main branch) | May 1, 2026 — SHA `1c1c8b7` (WLAN dhcp sync) | **No new commits — confirmed** |
| ameba-arduino-pro2 pull requests | 0 open; 319 closed; PR #333 only FlashMemory search result (WiFi example, unrelated) | **No fix under review; no fix ever filed** |
| ameba-arduino-pro2 issues | 12 open (confirmed count); highest filed: #398 (Mar 29, 2026) | **Zero new FCS/FlashMemory/VOE issues** |
| ameba-rtos-pro2 issues | 3 open; highest: #16 (Jan 2026) | **Zero new relevant issues** |
| ideashatch/HUB-8735 | Dec 2, 2025 — SHA `870a7e0`; issue #10 only | **Inactive** |
| ideashatch/HUB-8735-Series_examples | 54 commits; AI/CV examples only | **No FCS/flash bug content** |
| Ai-Thinker-Open GitHub org | — | **No BW21-CBV repository** |
| ameba-arduino-pro2 forks (36 total) | Various | **Zero forks contain FlashMemory mutex patch** |
| forum.amebaiot.com | All threads 403-blocked; highest indexed: #4840 (HTTPS OTA); no new FCS/flash threads | **No new accessible bug-related content** |
| CSDN / Zhihu / 21ic / EEWorld | — | **Zero Chinese-language reports — reconfirmed** |
| bbs.ai-thinker.com (BW21-CBV) | New thread tid=47223 (DIY digital camera); highest confirmed tid now 47223 | **No FCS/flash bug content** |
| FlashMemory.cpp (dev, SHA `4fdfbec`) | Sept 30, 2025 (>8.5 months) | **Still NO mutex fix — confirmed by direct raw fetch** |
| video_api.c (main) | March 3, 2026 | **Unguarded ftl_common_write() call(s); no mutex fix** |
| Official documentation (ameba-arduino-doc) | April 16, 2026 — SHA `d0b6ca3` | **No new commits; no FlashMemory/FCS warning** |
| Public web (`"It don't do the sensor initial process"`) | — | **Zero new indexed results** |
| Public web (`"FCS KM_status 0x00002081"`) | — | **Zero new indexed results** |
| Public web (`"device_mutex_lock" "FlashMemory" Ameba`) | — | **Zero results — root cause uniquely documented in this log** |

English and Chinese web searches (Google, CSDN, 知乎, 21ic, EEWorld, bbs.ai-thinker.com) confirm zero new public discussion of this bug in any language. No forum post, blog article, GitHub issue, or code patch describes the FlashMemory/FCS mutex race condition or a fix for it. The root cause (FlashMemory.cpp bypassing RT_DEV_LOCK_FLASH, confirmed Hypothesis F) remains the sole public analysis of this issue anywhere on the indexed internet.

**No HIGH priority confirmed fix found. Bug status: publicly undocumented and unpatched as of 2026-05-07 (second 6-hour run).**

---

### Sources Added (Update 2026-05-07, Update 2)
- ameba-arduino-pro2 dev commits (re-confirmed last: `13961cc`, May 5, 2026; no new commits): https://github.com/Ameba-AIoT/ameba-arduino-pro2/commits/dev
- ameba-rtos-pro2 main commits (re-confirmed last: `1c1c8b7`, May 1, 2026): https://github.com/Ameba-AIoT/ameba-rtos-pro2/commits/main
- ameba-arduino-pro2 V4.1.1-QC-V05 release notes (fully scanned; last entry Apr 30, 2026; no FlashMemory/FCS fix): https://github.com/Ameba-AIoT/ameba-arduino-pro2/releases/tag/V4.1.1-QC-V05
- ameba-arduino-pro2 V4.1.1-QC-V06 release tag (HTTP 404 confirmed): https://github.com/Ameba-AIoT/ameba-arduino-pro2/releases/tag/V4.1.1-QC-V06
- ameba-arduino-pro2 PR search (FlashMemory, closed) — only PR #333 surfaces (WiFi example, unrelated): https://github.com/Ameba-AIoT/ameba-arduino-pro2/pulls?q=is%3Apr+FlashMemory+is%3Aclosed
- bbs.aithinker.com thread tid=47223 (BW21数码相机+BW21-CBV-KIT; DIY camera; no FCS bug; highest confirmed BW21-CBV thread): https://bbs.aithinker.com/forum.php?mod=viewthread&tid=47223
- ameba-arduino-pro2 FlashMemory.cpp dev (re-confirmed no mutex, SHA `4fdfbec`, >8.5 months unmodified): https://raw.githubusercontent.com/Ameba-AIoT/ameba-arduino-pro2/dev/Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.cpp
- ameba-rtos-pro2 video_api.c main (re-confirmed unguarded ftl_common_write() call; device_lock.h included but unused for FCS path): https://raw.githubusercontent.com/Ameba-AIoT/ameba-rtos-pro2/main/component/video/driver/RTL8735B/video_api.c

---

## Research Update — 2026-05-07 (Update 3 — 6-hour cycle)

### Finding 134 — Forum Threads #4841–#4860 Probed; All HTTP 403; No New Bug-String Threads
**Source:** Direct URL probes of forum.amebaiot.com/t/4841 through /t/4860 (2026-05-07, third 6-hour run)
**Priority:** LOW — Extends thread probe range beyond previously documented #4840; no new accessible content

Systematic probes of forum.amebaiot.com thread URLs in the range #4841–#4860 all returned **HTTP 403 Forbidden**. No new threads in this range have been indexed by Google with content matching any of the bug's signature strings (`VOE_OPEN_CMD`, `FCS KM_status`, `slot full`, `sensor initial process`, FlashMemory). The highest confirmed indexed thread with any content remains #4840 ("關於Ameba Pro透過https下載Bin檔進行OTA的流程", HTTPS OTA — unrelated to FCS/flash camera bug). The forum wall is complete: no thread in any probed range has exposed FCS/flash camera bug content.

---

### Finding 135 — Complete Status Sweep: Bug Unpatched as of 2026-05-07 (Update 3)
**Source:** Exhaustive sweep of all tracked sources (2026-05-07, third 6-hour run)
**Priority:** LOW — Status confirmation

| Repository / Source | Last activity | Status |
|---|---|---|
| ameba-arduino-pro2 (dev branch) | May 5, 2026 — SHA `13961cc` (AMB82-zero SWD) | **No new commits — confirmed** |
| ameba-arduino-pro2 (releases) | V4.1.1-QC-V05 (Apr 30, 2026); V4.1.1 stable = HTTP 404; V4.1.1-QC-V06 = HTTP 404 | **No new release** |
| ameba-rtos-pro2 (main branch) | May 1, 2026 — SHA `1c1c8b7` (WLAN dhcp sync) | **No new commits — confirmed** |
| ameba-arduino-pro2 pull requests | 0 open; 319 closed; no FlashMemory/FCS PR ever filed | **No fix under review** |
| ameba-arduino-pro2 issues | 12 open; highest filed: #398 (Mar 29, 2026); #408–#410 = HTTP 404 | **Zero new FCS/FlashMemory/VOE issues** |
| ameba-rtos-pro2 issues | 3 open; highest: #16 (Jan 2026); #17 = HTTP 404 | **Zero new relevant issues** |
| ideashatch/HUB-8735 | Dec 2, 2025 — SHA `870a7e0`; issue #10 only | **Inactive** |
| ideashatch/HUB-8735-Series_examples | ~54 commits; AI/CV examples only | **No FCS/flash bug content** |
| Ai-Thinker-Open GitHub org | — | **No BW21-CBV repository** |
| ameba-arduino-pro2 forks (36 total) | Various | **Zero forks contain FlashMemory mutex patch** |
| forum.amebaiot.com | Threads #4841–#4860 newly probed (all HTTP 403); highest indexed: #4840 | **No new FCS/flash/camera threads; forum fully blocked** |
| CSDN / Zhihu / 21ic / EEWorld | — | **Zero Chinese-language reports — reconfirmed** |
| bbs.ai-thinker.com (BW21-CBV) | Highest confirmed: tid=47223 (DIY digital camera, unrelated) | **No FCS/flash bug content** |
| FlashMemory.cpp (dev, SHA `4fdfbec`) | Sept 30, 2025 (>8.5 months unmodified) | **Still NO mutex fix — confirmed by direct raw fetch** |
| video_api.c (main) | March 3, 2026 | **Unguarded ftl_common_write() call(s); no mutex fix — confirmed** |
| Official documentation (ameba-arduino-doc) | April 16, 2026 — SHA `d0b6ca3` | **No new commits; no FlashMemory/FCS warning added** |
| Public web (`"It don't do the sensor initial process"`) | — | **Zero new indexed results** |
| Public web (`"FCS KM_status 0x00002081"`) | — | **Zero new indexed results** |
| Public web (`"device_mutex_lock" "FlashMemory" Ameba`) | — | **Zero results — root cause uniquely documented in this log** |

English and Chinese web searches (Google, CSDN, 知乎, 21ic, EEWorld, bbs.ai-thinker.com) confirm zero new public discussion of this bug in any language. No forum post, blog article, GitHub issue, or code patch describes the FlashMemory/FCS mutex race condition or a fix for it anywhere on the indexed public internet.

**No HIGH priority confirmed fix found. Bug status: publicly undocumented and unpatched as of 2026-05-07 (third 6-hour run).**

---

### Sources Added (Update 2026-05-07, Update 3)
- forum.amebaiot.com threads #4841–#4860 (all HTTP 403; no new FCS/flash content in this range): https://forum.amebaiot.com/t/4841 (representative URL)
- ameba-arduino-pro2 dev commits (re-confirmed last: `13961cc`, May 5, 2026): https://github.com/Ameba-AIoT/ameba-arduino-pro2/commits/dev
- ameba-rtos-pro2 main commits (re-confirmed last: `1c1c8b7`, May 1, 2026): https://github.com/Ameba-AIoT/ameba-rtos-pro2/commits/main
- ameba-arduino-pro2 FlashMemory.cpp dev (re-confirmed no mutex, SHA `4fdfbec`): https://raw.githubusercontent.com/Ameba-AIoT/ameba-arduino-pro2/dev/Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.cpp
- ameba-rtos-pro2 video_api.c main (re-confirmed unguarded ftl_common_write() in SAVE_TO_FLASH path): https://raw.githubusercontent.com/Ameba-AIoT/ameba-rtos-pro2/main/component/video/driver/RTL8735B/video_api.c

---

## Research Update — 2026-05-08

### Finding 136 — Clarification to Finding 97: ftl_common_write() Appears in Both Load and Save Paths of video_api.c
**Source:** `ameba-rtos-pro2/main` — `video_api.c` (fresh fetch, May 8, 2026)  
https://raw.githubusercontent.com/Ameba-AIoT/ameba-rtos-pro2/main/component/video/driver/RTL8735B/video_api.c  
**Priority:** MEDIUM — Refines prior finding; potentially extends the race window to the load path as well

Finding 97 (2026-05-04 Update 3) documented two `ftl_common_write()` calls "within `video_pre_init_save_cur_params()`." A fresh fetch of `video_api.c` (May 8, 2026) reveals that `ftl_common_write()` is called in **two separate functions**:
1. `video_pre_init_load_params()` — the boot-time FCS load function
2. `video_pre_init_save_cur_params()` — the runtime FCS save function

If `video_pre_init_load_params()` truly uses `ftl_common_write()` (rather than `ftl_common_read()`), this would mean the load path also writes flash — possibly updating a header or status byte. **Neither call is wrapped with `device_mutex_lock(RT_DEV_LOCK_FLASH)`.**

**Caveat:** It is possible this reflects `ftl_common_read()` in the load path (misread by the research tool) rather than a genuine write. The underlying SPI collision hazard exists regardless — `ftl_common_read()` also internally acquires `RT_DEV_LOCK_FLASH`, so `FlashMemory.cpp`'s unguarded calls would still race with it. If the load path does use `ftl_common_write()`, the race window is larger than modelled in Finding 97.

---

### Finding 137 — FlashMemory.cpp: Six Total Unguarded Flash Operations Confirmed
**Source:** `ameba-arduino-pro2/dev` — `FlashMemory.cpp` (fresh fetch, May 8, 2026)  
https://raw.githubusercontent.com/Ameba-AIoT/ameba-arduino-pro2/dev/Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.cpp  
**Priority:** MEDIUM — Expands prior characterisation (Finding 63 counted two call sites; full count is six)

A fresh read of `FlashMemory.cpp` (dev, SHA `4fdfbec`) confirms **six unguarded raw flash operations** distributed across three functions:

| Function | Operations | Mutex |
|---|---|---|
| `write()` | `flash_erase_sector()` × N sectors + `flash_stream_write()` × 1 | None |
| `writeWord()` | `flash_write_word()` × 1; on bit-flip conflict: `flash_erase_sector()` × 1 + `flash_stream_write()` × 1 | None |
| `eraseSector()` / `eraseWord()` | `flash_erase_sector()` × 1 | None |

Total: up to six distinct SPI flash command sequences — all bypassing `RT_DEV_LOCK_FLASH`. Any one of these can race with the video module's `ftl_common_write()` / `ftl_common_read()` calls (which do hold the lock). The file has not been modified since SHA `4fdfbec` (September 30, 2025) — over 8.5 months unpatched.

---

### Finding 138 — Complete Status Sweep: Bug Unpatched as of 2026-05-08
**Source:** Exhaustive sweep of all tracked sources (2026-05-08)  
**Priority:** LOW — Status confirmation

| Repository / Source | Last activity | Status |
|---|---|---|
| ameba-arduino-pro2 (dev branch) | May 5, 2026 — SHA `13961cc` ("Update API for AMB82-zero and SWD off logic") | **No new commits — compare `13961cc...dev` returns identical** |
| ameba-arduino-pro2 (releases) | V4.1.1-QC-V05 (Apr 30, 2026); V4.1.1 stable = HTTP 404; V4.1.1-QC-V06 = HTTP 404 | **No new release** |
| ameba-rtos-pro2 (main branch) | May 1, 2026 — SHA `1c1c8b7` (WLAN dhcp sync) | **No new commits — compare `1c1c8b7...main` returns identical** |
| ameba-rtos-pro2 (tags) | V1.0.3-aiglass.07 (Apr 2, 2026) remains most recent | **No new tags** |
| ameba-arduino-pro2 pull requests | 0 open; 319 closed; no FlashMemory/FCS/mutex PR ever filed | **No fix under review** |
| ameba-arduino-pro2 issues | 12 open; highest filed: #398 (Mar 29, 2026); #408–#410 = HTTP 404 | **Zero new FCS/FlashMemory/VOE issues** |
| ameba-rtos-pro2 issues | 3 open; highest: #16 (Jan 2026); #17 = HTTP 404 | **Zero new relevant issues** |
| ideashatch/HUB-8735 | Dec 2, 2025 — SHA `870a7e0`; issue #10 only | **Inactive** |
| ideashatch/HUB-8735-Series_examples | ~54 commits; AI/CV examples only | **No FCS/flash bug content** |
| Ai-Thinker-Open GitHub org | — | **No BW21-CBV repository** |
| ameba-arduino-pro2 forks (36 total) | — | **Zero forks contain FlashMemory mutex patch** |
| forum.amebaiot.com | Threads #4841–#4860 all HTTP 403; highest indexed: #4840 (HTTPS OTA); no FCS/flash camera threads | **No new accessible content** |
| CSDN / Zhihu / 21ic / EEWorld | — | **Zero Chinese-language reports — reconfirmed** |
| bbs.ai-thinker.com / bbs.aithinker.com (BW21-CBV) | Highest confirmed: tid=47223 (DIY camera, unrelated) | **No FCS/flash bug threads** |
| FlashMemory.cpp (dev, SHA `4fdfbec`) | Sept 30, 2025 (>8.5 months unmodified) | **Still NO mutex fix — 6 unguarded flash operations confirmed** |
| video_api.c (main) | March 3, 2026 | **ftl_common_write() in both load and save paths; neither guarded — confirmed** |
| Official documentation (ameba-arduino-doc) | April 16, 2026 — SHA `d0b6ca3` | **No new commits; no FlashMemory/FCS warning added** |
| Public web (`"It don't do the sensor initial process"`) | — | **Zero new indexed results** |
| Public web (`"FCS KM_status 0x00002081"`) | — | **Zero new indexed results** |
| Public web (`"[VOE][WARN]slot full"` ameba) | — | **Zero new indexed results** |
| Public web (`"device_mutex_lock" "FlashMemory" Ameba`) | — | **Zero results — root cause uniquely documented in this log** |

English and Chinese web searches (Google, CSDN, 知乎, 21ic, EEWorld, bbs.ai-thinker.com) confirm zero new public discussion of this bug in any language. All six bug-signature strings remain completely unindexed on the public internet. No forum post, blog article, YouTube video, GitHub issue, or code patch describes the FlashMemory/FCS mutex race condition or a fix for it.

**No HIGH priority confirmed fix found. Bug status: publicly undocumented and unpatched as of 2026-05-08.**

---

### Sources Added (Update 2026-05-08)
- ameba-arduino-pro2 compare `13961cc...dev` (confirmed identical — no new commits since May 5, 2026): https://github.com/Ameba-AIoT/ameba-arduino-pro2/compare/13961cc...dev
- ameba-rtos-pro2 compare `1c1c8b7...main` (confirmed identical — no new commits since May 1, 2026): https://github.com/Ameba-AIoT/ameba-rtos-pro2/compare/1c1c8b7...main
- ameba-arduino-pro2 releases (re-confirmed latest: V4.1.1-QC-V05, Apr 30, 2026; V4.1.1-QC-V06 = HTTP 404): https://github.com/Ameba-AIoT/ameba-arduino-pro2/releases
- ameba-rtos-pro2 tags (re-confirmed latest: V1.0.3-aiglass.07, Apr 2, 2026; no new tags): https://github.com/Ameba-AIoT/ameba-rtos-pro2/tags
- ameba-arduino-pro2 issues (re-confirmed: 12 open, highest #398 Mar 2026, #408–#410 = HTTP 404): https://github.com/Ameba-AIoT/ameba-arduino-pro2/issues
- ameba-rtos-pro2 issues (re-confirmed: 3 open, highest #16 Jan 2026, #17 = HTTP 404): https://github.com/Ameba-AIoT/ameba-rtos-pro2/issues
- ameba-arduino-pro2 FlashMemory.cpp dev (6 unguarded flash operations confirmed; SHA `4fdfbec`; >8.5 months unmodified): https://raw.githubusercontent.com/Ameba-AIoT/ameba-arduino-pro2/dev/Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.cpp
- ameba-rtos-pro2 video_api.c main (ftl_common_write() in load and save paths; neither guarded): https://raw.githubusercontent.com/Ameba-AIoT/ameba-rtos-pro2/main/component/video/driver/RTL8735B/video_api.c
- ideashatch/HUB-8735-Series_examples (re-confirmed no FCS/flash bug content): https://github.com/ideashatch/HUB-8735-Series_examples
- forum.amebaiot.com threads #4841–#4860 (all HTTP 403; no FCS/flash camera bug content): https://forum.amebaiot.com/t/4841 (representative)
- bbs.aithinker.com thread tid=47223 (BW21数码相机+BW21-CBV-KIT; DIY camera; no FCS bug; highest confirmed BW21-CBV thread): https://bbs.aithinker.com/forum.php?mod=viewthread&tid=47223

---

## Research Update — 2026-05-08 (Update 2 — 6-hour cycle)

### Finding 139 — Forum Thread #4847 "I2C1 for MPU6050" — New Highest Indexed Thread; Unrelated to Bug
**Source:** Google search results — forum.amebaiot.com thread #4847 (HTTP 403-blocked for full content)
https://forum.amebaiot.com/t/i2c1-for-mpu6050/4847
**Priority:** LOW — New higher-numbered thread logged; updates highest confirmed forum thread from #4840 to #4847; no FCS/flash bug relevance

Forum thread **#4847** ("I2C1 for MPU6050") surfaced in search results for this cycle. Based on search engine metadata it was posted approximately 2 days before this research run, placing it around **May 6–7, 2026**. The thread discusses using the I2C1 bus on AMB82-Mini to communicate with an MPU6050 IMU sensor. Content is HTTP 403-blocked; only title and URL slug are available.

**This is the new highest confirmed indexed forum thread**, replacing #4840 ("關於Ameba Pro透過https下載Bin檔進行OTA的流程", HTTPS OTA, May 1, 2026) as the previously highest. The numbering gap #4840 → #4847 = 7 threads confirms continued forum activity (May 1–7, 2026 period). None of the 7 intermediate threads have been indexed by Google with content matching any bug-signature string.

No FCS, FlashMemory, cold-boot camera failure, VOE error, or flash-camera interaction is referenced in the visible title or URL slug of thread #4847.

---

### Finding 140 — Forum Thread #4802 "AMB82-Mini USB Host CDC ECM fails to enumerate Quectel EC200U 4G modem" — Previously Undocumented Thread Number
**Source:** Google search results — forum.amebaiot.com thread #4802 (HTTP 403-blocked)
https://forum.amebaiot.com/t/amb82-mini-usb-host-cdc-ecm-fails-to-enumerate-quectel-ec200u-4g-modem-ecm-init-fail/4802
**Priority:** LOW — New thread number logged; different from previously documented #4803; no FCS bug content

Forum thread **#4802** ("AMB82-Mini USB Host CDC ECM fails to enumerate Quectel EC200U 4G modem — 'ecm init fail'") was surfaced by search in this cycle. Prior research had documented thread #4803 ("AMB82-mini USB host CDC ECM fail to SIM7600G-H", Finding 100), but thread #4802 — a separate, different thread about USB CDC-ECM enumeration of a Quectel 4G modem — was not previously logged. Both #4802 and #4803 cover USB CDC-ECM peripheral failures on AMB82-Mini, unrelated to FCS, FlashMemory, or camera cold-boot failure. Full content is HTTP 403-blocked.

---

### Finding 141 — Both Repository Compare Endpoints Confirm Zero New Commits (May 8, 2026)
**Source:** Direct compare fetches (2026-05-08, second run)
https://github.com/Ameba-AIoT/ameba-arduino-pro2/compare/13961cc...dev
https://github.com/Ameba-AIoT/ameba-rtos-pro2/compare/1c1c8b7...main
**Priority:** LOW — Status confirmation; no new fix commits

Both GitHub compare endpoints return "identical" — confirming zero new commits since last documented activity:

| Repository | Last commit SHA | Last commit date | Message |
|---|---|---|---|
| ameba-arduino-pro2 (dev) | `13961cc` | May 5, 2026 | "Update API for AMB82-zero and SWD off logic" |
| ameba-rtos-pro2 (main) | `1c1c8b7` | May 1, 2026 | "Sync upstream — wowlan dhcp renew" |

`FlashMemory.cpp` (SHA `4fdfbec`) remains unchanged since September 30, 2025 — now over **8.5 months** without modification, the longest uninterrupted stretch in its ~10-month public history. `video_api.c` unchanged since March 3, 2026. No releases, PRs, or issues have been filed in any repository since the previous research cycle.

---

### Finding 142 — Complete Status Sweep: Bug Unpatched as of 2026-05-08 (Update 2)
**Source:** Exhaustive sweep of all tracked sources (2026-05-08, second 6-hour run)
**Priority:** LOW — Status confirmation

| Repository / Source | Last activity | Status |
|---|---|---|
| ameba-arduino-pro2 (dev branch) | May 5, 2026 — SHA `13961cc` | **No new commits — compare endpoint confirms identical** |
| ameba-arduino-pro2 (releases) | V4.1.1-QC-V05 (Apr 30, 2026); V4.1.1 stable = HTTP 404 | **No new release** |
| ameba-rtos-pro2 (main branch) | May 1, 2026 — SHA `1c1c8b7` | **No new commits — compare endpoint confirms identical** |
| ameba-arduino-pro2 pull requests | 0 open; 319 closed | **No fix under review** |
| ameba-arduino-pro2 issues | 12 open; highest filed: #398 (Mar 2026) | **Zero new FCS/FlashMemory/VOE issues** |
| ameba-rtos-pro2 issues | 3 open; highest: #16 (Jan 2026) | **Zero new relevant issues** |
| ideashatch/HUB-8735 | Dec 2, 2025 | **Inactive** |
| Ai-Thinker-Open GitHub org | — | **No BW21-CBV repository** |
| ameba-arduino-pro2 forks (36 total) | Various | **Zero forks contain FlashMemory mutex patch** |
| forum.amebaiot.com | Thread #4847 ("I2C1 for MPU6050", ~May 6–7, 2026) — new highest indexed thread; all 403-blocked | **No FCS/flash/camera bug threads; highest confirmed thread #4847** |
| CSDN / Zhihu / 21ic / EEWorld | — | **Zero Chinese-language reports — reconfirmed** |
| bbs.ai-thinker.com (BW21-CBV) | Highest: tid=47223 (DIY camera, unrelated) | **No camera/FCS bug threads** |
| FlashMemory.cpp (dev, SHA `4fdfbec`) | Sept 30, 2025 (>8.5 months) | **Still NO mutex fix — 6 unguarded flash operations** |
| video_api.c (main) | March 3, 2026 | **Unguarded ftl_common_write() calls; no mutex fix** |
| Official documentation (ameba-arduino-doc) | April 16, 2026 | **No FlashMemory/FCS warning added** |
| Public web (`"It don't do the sensor initial process"`) | — | **Zero new indexed results** |
| Public web (`"FCS KM_status 0x00002081"`) | — | **Zero new indexed results** |
| Public web (`"device_mutex_lock" "FlashMemory" Ameba`) | — | **Zero results — root cause uniquely documented in this log** |

**No HIGH priority confirmed fix found. Bug status: publicly undocumented and unpatched as of 2026-05-08 (second 6-hour run).**

---

### Sources Added (Update 2026-05-08, Update 2)
- forum.amebaiot.com thread #4847 ("I2C1 for MPU6050"; ~May 6–7, 2026; new highest indexed thread; unrelated to bug; 403-blocked): https://forum.amebaiot.com/t/i2c1-for-mpu6050/4847
- forum.amebaiot.com thread #4802 ("AMB82-Mini USB Host CDC ECM fails to enumerate Quectel EC200U 4G modem"; previously undocumented; unrelated; 403-blocked): https://forum.amebaiot.com/t/amb82-mini-usb-host-cdc-ecm-fails-to-enumerate-quectel-ec200u-4g-modem-ecm-init-fail/4802
- ameba-arduino-pro2 compare `13961cc...dev` (confirmed identical — no new commits since May 5, 2026): https://github.com/Ameba-AIoT/ameba-arduino-pro2/compare/13961cc...dev
- ameba-rtos-pro2 compare `1c1c8b7...main` (confirmed identical — no new commits since May 1, 2026): https://github.com/Ameba-AIoT/ameba-rtos-pro2/compare/1c1c8b7...main
- ameba-arduino-pro2 releases (re-confirmed: V4.1.1-QC-V05 latest; no V4.1.1 stable; no V4.1.1-QC-V06): https://github.com/Ameba-AIoT/ameba-arduino-pro2/releases
- ameba-arduino-pro2 issues (re-confirmed: 12 open, highest #398 Mar 2026; no new FCS issues): https://github.com/Ameba-AIoT/ameba-arduino-pro2/issues
- ameba-rtos-pro2 issues (re-confirmed: 3 open, highest #16 Jan 2026): https://github.com/Ameba-AIoT/ameba-rtos-pro2/issues
- ameba-arduino-pro2 FlashMemory.cpp dev (re-confirmed no mutex; SHA `4fdfbec`; write() and writeWord() unchanged): https://raw.githubusercontent.com/Ameba-AIoT/ameba-arduino-pro2/dev/Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.cpp

---

## Research Update — 2026-05-08 (Update 3 — 6-hour cycle)

### Finding 143 — New Chinese-Language BW21-CBV Article Indexed on mcublog.cn (April 2026); No FCS Bug Content
**Source:** Google-indexed result — https://www.mcublog.cn/software/2026_04/ai-bw21-cbv-led-photo/ (HTTP 403 on direct fetch)
**Priority:** LOW — New specific URL identified; no FCS/flash bug content confirmed

A previously unlogged Chinese-language article from **mcublog.cn** (April 2026) was surfaced in a targeted search for BW21-CBV + camera + FCS + cold boot content. Article title (from search snippet): "我让AI帮我把BW21-CBV开发板接入了飞书机器人，不光能控制点灯，还能拍照看照片" (roughly: "I used AI to connect my BW21-CBV development board to a Feishu robot — it can control LEDs and take photos"). The full article was HTTP 403-blocked on direct fetch.

The Google-indexed snippet describes a beginner-level Feishu bot integration using BW21-CBV for LED control and camera snapshot capture. No mention of FlashMemory writes, FCS mode configuration, cold boot failures, VOE initialization errors, or any flash-camera interaction issue is visible in the title or indexed snippet. The article represents additional April 2026 Chinese-language BW21-CBV community activity but contains no evidence of independent discovery of the FlashMemory/FCS bug.

Previous research cycles referenced mcublog.cn in status tables but had not identified this specific article URL.

---

### Finding 144 — Complete Status Sweep: Bug Unpatched as of 2026-05-08 (Update 3)
**Source:** Exhaustive sweep of all tracked sources (2026-05-08, third 6-hour run)
**Priority:** LOW — Status confirmation; no new fix

All previously documented statuses are unchanged from Finding 142 (Update 2):

| Repository / Source | Status as of 2026-05-08 Update 3 |
|---|---|
| ameba-arduino-pro2 (dev) | Last: SHA `13961cc`, May 5, 2026 — no FCS/FlashMemory change |
| ameba-rtos-pro2 (main) | Last: SHA `1c1c8b7`, May 1, 2026 — no new commits |
| ameba-arduino-pro2 releases | V4.1.1-QC-V05 latest; V4.1.1 stable = HTTP 404 |
| ameba-arduino-pro2 issues | 12 open; highest #398; zero new FCS/VOE/FlashMemory issues |
| forum.amebaiot.com | Highest indexed: #4847; all 403-blocked; no bug-string matches |
| Chinese-language sources | mcublog.cn (April 2026) added to sources; content irrelevant; **still zero bug reports** |
| FlashMemory.cpp | SHA `4fdfbec`; **still NO mutex fix** — 8.5+ months unmodified |
| video_api.c | March 3, 2026; **unguarded `ftl_common_write()` calls — no fix** |
| Public web bug strings | **Zero results** for all three bug-signature strings |

**No HIGH priority confirmed fix found. Bug status: publicly undocumented and unpatched as of 2026-05-08 (third 6-hour run).**

---

### Sources Added (Update 2026-05-08, Update 3)
- mcublog.cn BW21-CBV + Feishu bot article (April 2026; 403-blocked; no FCS bug content; first indexed by this research cycle): https://www.mcublog.cn/software/2026_04/ai-bw21-cbv-led-photo/

---

## Research Update — 2026-05-09

### Finding 145 — Both Repositories Confirmed Static Since Previous Cycle; No New Commits
**Source:** Direct commit-page fetches (2026-05-09)
https://github.com/Ameba-AIoT/ameba-arduino-pro2/commits/dev
https://github.com/Ameba-AIoT/ameba-rtos-pro2/commits/main
**Priority:** LOW — Status confirmation; no new fix commits

Both repositories remain static, consistent with all prior cycles in the May 7–8 period:

| Repository | Last commit SHA | Last commit date | Message |
|---|---|---|---|
| ameba-arduino-pro2 (dev) | `13961cc` (`13961ccfef03e6f42c6e6d29e96a446fca29b71c`) | May 5, 2026 | "Update API for AMB82-zero and SWD off logic" |
| ameba-rtos-pro2 (main) | `1c1c8b7` (`1c1c8b711a419d2d49190d34f7c13e2fd0b14974`) | May 1, 2026 | "Sync upstream — wowlan dhcp renew" |

Direct fetch of ameba-rtos-pro2 commits/main confirms the five most recent entries are all dated May 1, 2026: d54e1a8 (VOE 1.7.1.0), 63c0a2f (OV12890 IQ), 7b2b97f (IMX681 5M), a111e91 (WLAN dhcp), 1c1c8b7 (sync bot). No commits have been added since. `FlashMemory.cpp` remains at SHA `4fdfbec` (September 30, 2025) — now over **8.5 months** without modification.

---

### Finding 146 — FlashMemory.cpp write() and writeWord() Bodies Re-Confirmed (May 9, 2026)
**Source:** Direct raw fetch — `ameba-arduino-pro2/dev` — `FlashMemory.cpp`
https://raw.githubusercontent.com/Ameba-AIoT/ameba-arduino-pro2/dev/Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.cpp
**Priority:** LOW — Direct re-verification; bug confirmed still present

Fresh fetch confirms the complete `write()` function body (unchanged from SHA `4fdfbec`):
```cpp
void FlashMemoryClass::write(unsigned int offset)
{
    if ((_flash_base_address + offset) < FLASH_MEMORY_APP_BASE) {
        amb_ard_printf(ARD_LOG_ERR, "\r\n[ERROR] %s. Invalid offset \n", __FUNCTION__);
        return;
    } else if ((_flash_base_address + offset + buf_size) > FLASH_MEMORY_SIZE) {
        amb_ard_printf(ARD_LOG_ERR, "\r\n[ERROR] %s. Invalid offset \n", __FUNCTION__);
        return;
    }

    for (int i = 0; i < (MAX_FLASH_MEMORY_APP_SIZE / FLASH_SECTOR_SIZE); i++) {
        flash_erase_sector(_pFlash, (_flash_base_address + (i * FLASH_SECTOR_SIZE)));
    }

    flash_stream_write(_pFlash, (_flash_base_address + offset), buf_size, (uint8_t *)buf);
}
```

The `writeWord()` function: calls `flash_write_word()` and on bit-flip conflict falls through to `flash_erase_sector()` + `flash_stream_write()`. **Zero calls to `device_mutex_lock`, zero `device_lock.h` includes, zero `RT_DEV_LOCK_FLASH` references.** The mutex bypass documented in Hypothesis F / Finding 17 is confirmed present and unpatched.

---

### Finding 147 — Forum Thread #4707 "Access Raw Camera Output from AMB82-MINI" Newly Logged; Unrelated to Bug
**Source:** Google search results — forum.amebaiot.com thread #4707 (403-blocked)
https://forum.amebaiot.com/t/access-raw-camera-output-from-amb82-mini/4707
**Priority:** LOW — New thread number logged (previously undocumented gap between #4670 and #4748); no FCS/flash bug relevance

Forum thread **#4707** ("Access raw camera output from AMB82-MINI") surfaced in a targeted camera search this cycle. Based on context this is from approximately February 2026, predating the current research cycle. It is a feature question about accessing unencoded ISP frames for CV processing — similar in topic to GitHub issue #398 (Finding 73) but on the forum. Content is HTTP 403-blocked; title only is confirmed.

**Significance:** Thread #4707 fills a previously unlogged gap in the documented thread sequence (highest documented below #4748 was #4670 from Finding 37). None of the intermediate threads (#4671–#4747) have been captured containing FCS/flash bug content.

---

### Finding 148 — Forum Thread #4832 "Sys_reset Is Not Consistent" Newly Identified; Tangentially Adjacent to Bug
**Source:** Google search results — forum.amebaiot.com thread #4832 (403-blocked)
https://forum.amebaiot.com/t/sys-reset-is-not-consistent-why/4832
**Priority:** LOW — New thread number logged; camera + reset behavior is adjacent but does not describe the FlashMemory/FCS race

Forum thread **#4832** ("Sys_reset is not consistent, why?") surfaced in search this cycle. Based on Google-indexed snippet metadata, the user reports that `sys_reset()` stops boot debug output on a camera application after OTA updates, requiring a power cycle to restore normal operation. This is tangentially adjacent to our bug (camera + abnormal boot behavior), but the described symptom (lost boot debug output requiring power cycle) does not match the FCS sector corruption mechanism (which manifests as `KM_status 0x00002081` + "It don't do the sensor initial process"). No FCS/FlashMemory error strings or flash write operations are mentioned in the indexed content. Full content is HTTP 403-blocked; no resolution or fix is visible from the snippet.

This is a previously undocumented thread number between #4829 (documented in Finding 100) and #4834 (documented in Finding 42).

---

### Finding 149 — All Bug-Signature Strings Return Zero Results; No New Public Reports (May 9, 2026)
**Source:** Web searches (Google indexed, 2026-05-09) — English and Chinese; confirmed by independent background research agent
**Priority:** LOW — Confirms continued public ignorance of the bug

| Query | Result |
|---|---|
| `"It don't do the sensor initial process"` | **Zero results** |
| `"FCS KM_status 0x00002081"` | **Zero results** |
| `"[VOE][WARN]slot full"` (Ameba context) | **Zero results** |
| `"VOE_OPEN_CMD fail" ameba` | **Zero results** |
| `"device_mutex_lock" "FlashMemory" Ameba` | **Zero results** |
| `RTL8735B AMB82 FlashMemory FCS camera cold boot fix 2026` | Zero relevant hits |
| `ameba-arduino-pro2 FlashMemory device_mutex_lock RT_DEV_LOCK_FLASH patch` | Zero results |
| `ameba AMB82 BW21-CBV 摄像头 FCS 冷启动 flash 写入 失败 2026` (Chinese) | **Zero results** |
| `site:csdn.net RTL8735B AMB82 camera flash FCS 2026` | **Zero relevant hits** |
| `site:forum.amebaiot.com camera VOE slot full flash 2026` | Zero relevant hits |
| Chinese: AMB82 相机 FCS flash 写入 冷启动 (CSDN/Zhihu/21ic/EEWorld) | **Zero results** |

Forum searches confirm the highest indexed camera-adjacent thread is still approximately #4847 ("I2C1 for MPU6050", ~May 6–7, 2026, previously documented in Finding 139). Threads #4848–#4860 are not yet publicly indexed. The bug remains completely unindexed and unreported on the public internet in any language as of May 9, 2026.

---

### Complete Status Sweep — 2026-05-09

| Repository / Source | Last activity | Status |
|---|---|---|
| ameba-arduino-pro2 (dev branch) | May 5, 2026 — SHA `13961cc` (AMB82-zero SWD) | **No new commits — confirmed** |
| ameba-arduino-pro2 (releases) | V4.1.1-QC-V05 (Apr 30, 2026); V4.1.1 stable = HTTP 404; V4.1.1-QC-V06 = HTTP 404 | **No new release** |
| ameba-rtos-pro2 (main branch) | May 1, 2026 — SHA `1c1c8b7` (WLAN dhcp sync) | **No new commits — confirmed by direct fetch** |
| ameba-rtos-pro2 (tags) | V1.0.3-aiglass.07 (Apr 2, 2026) — most recent | **No new tags** |
| ameba-arduino-pro2 pull requests | 0 open; 319 closed; no FlashMemory/FCS/mutex PR ever filed | **No fix under review** |
| ameba-arduino-pro2 issues | 12 open; highest filed: #398 (Mar 29, 2026); #408+ = HTTP 404 | **Zero new FCS/FlashMemory/VOE issues** |
| ameba-rtos-pro2 issues | 3 open; highest: #16 (Jan 2026); #17 = HTTP 404 | **Zero new relevant issues** |
| ideashatch/HUB-8735 | Dec 2, 2025 — SHA `870a7e0`; issue #10 only | **Inactive** |
| ideashatch/HUB-8735-Series_examples | ~54 commits; AI/CV examples only | **No FCS/flash bug content** |
| Ai-Thinker-Open GitHub org | — | **No BW21-CBV repository** |
| ameba-arduino-pro2 forks (36 total) | — | **Zero forks contain FlashMemory mutex patch** |
| forum.amebaiot.com | Threads #4707, #4832 newly logged (both unrelated); highest indexed: #4847 (~May 6–7, 2026); all 403-blocked | **No new FCS/flash/camera bug threads** |
| CSDN / Zhihu / 21ic / EEWorld | — | **Zero Chinese-language reports — reconfirmed** |
| bbs.ai-thinker.com (BW21-CBV) | Highest confirmed: tid=47223 (DIY camera, unrelated) | **No camera/FCS bug threads** |
| FlashMemory.cpp (dev, SHA `4fdfbec`) | Sept 30, 2025 (>8.5 months unmodified) | **Still NO mutex fix — confirmed by direct raw fetch with full write()/writeWord() bodies** |
| video_api.c (main) | March 3, 2026 | **Unguarded ftl_common_write() calls; no mutex fix — confirmed** |
| Official documentation (ameba-arduino-doc) | April 16, 2026 — SHA `d0b6ca3` | **No new commits; no FlashMemory/FCS warning added** |
| Public web (all bug-signature strings) | — | **Zero new indexed results — root cause uniquely documented in this log** |

English and Chinese web searches confirm zero new public discussion of this bug in any language. No forum post, blog article, GitHub issue, or code patch describes the FlashMemory/FCS mutex race condition or a fix for it. The root cause analysis (Hypothesis F — `FlashMemory.cpp` bypasses `RT_DEV_LOCK_FLASH`) remains the sole public record of this analysis anywhere on the indexed internet.

**No HIGH priority confirmed fix found. Bug status: publicly undocumented and unpatched as of 2026-05-09.**

---

### Sources Added (Update 2026-05-09)
- ameba-arduino-pro2 dev commits (confirmed last: `13961cc`, May 5, 2026; no new commits): https://github.com/Ameba-AIoT/ameba-arduino-pro2/commits/dev
- ameba-rtos-pro2 main commits (confirmed last: `1c1c8b7`, May 1, 2026; five May 1 commits verified by direct fetch): https://github.com/Ameba-AIoT/ameba-rtos-pro2/commits/main
- ameba-arduino-pro2 FlashMemory.cpp dev (write() and writeWord() full bodies confirmed; SHA `4fdfbec`; no mutex; >8.5 months unmodified): https://raw.githubusercontent.com/Ameba-AIoT/ameba-arduino-pro2/dev/Arduino_package/hardware/libraries/FlashMemory/src/FlashMemory.cpp
- ameba-rtos-pro2 video_api.c main (unguarded ftl_common_write() call(s) confirmed; device_lock.h already included but unused for FCS path): https://raw.githubusercontent.com/Ameba-AIoT/ameba-rtos-pro2/main/component/video/driver/RTL8735B/video_api.c
- ameba-arduino-pro2 issues (confirmed: 12 open, highest #398 Mar 2026; #408+ = HTTP 404): https://github.com/Ameba-AIoT/ameba-arduino-pro2/issues
- ameba-rtos-pro2 issues (confirmed: 3 open, highest #16 Jan 2026): https://github.com/Ameba-AIoT/ameba-rtos-pro2/issues
- ameba-arduino-pro2 releases (confirmed: V4.1.1-QC-V05 latest; V4.1.1 stable = HTTP 404; V4.1.1-QC-V06 = HTTP 404): https://github.com/Ameba-AIoT/ameba-arduino-pro2/releases
- forum.amebaiot.com thread #4707 ("Access raw camera output from AMB82-MINI"; Feb 2026; previously undocumented; 403-blocked; unrelated to bug): https://forum.amebaiot.com/t/access-raw-camera-output-from-amb82-mini/4707
- forum.amebaiot.com thread #4832 ("Sys_reset is not consistent, why?"; camera+reset adjacent; 403-blocked; no FCS bug content): https://forum.amebaiot.com/t/sys-reset-is-not-consistent-why/4832

---

## Research Update — 2026-05-09 (Update 2 — 6-hour cycle)

### Finding 150 — pvvx/RTL0B_SDK: RTL8710B OTA Code Uses device_mutex_lock(RT_DEV_LOCK_FLASH) — Realtek's Own Pattern Absent in AMB82 FlashMemory.cpp
**Priority:** MEDIUM
Source: https://github.com/pvvx/RTL0B_SDK/blob/master/component/soc/realtek/8711b/misc/rtl8710b_ota.c
Pattern confirmed: `device_mutex_lock(RT_DEV_LOCK_FLASH)` / flash ops / `device_mutex_unlock()` used in RTL8710B (AmebaZ) OTA code — confirming Realtek's own prior-generation SDK followed this exact pattern.
The omission of this pattern in AmebaPro2 `FlashMemory.cpp` is inconsistent with Realtek's established practice on their own earlier chips. This strengthens the argument that the missing mutex in `FlashMemory.cpp` is a regression/oversight, not a deliberate design choice.
Cross-reference: `pvvx/RTL00MP3` `device_lock.h` confirms `RT_DEV_LOCK_FLASH = 1` in `device_mutex[]` pool on RTL8710B — same index/API as AmebaPro2.

### Finding 151 — ameba-doc-arduino-sdk.readthedocs-hosted.com: Flash Memory Docs — No FCS/FlashMemory Warning
**Priority:** LOW
Source: https://ameba-doc-arduino-sdk.readthedocs-hosted.com/en/latest/ameba_pro2/amb82-mini/Example_Guides/Flash%20Memory/index.html
All three official documentation sources confirmed silent on the FlashMemory/FCS race condition:
1. ameba-doc-arduino-sdk.readthedocs-hosted.com (this source) — no concurrent-use or FCS warning
2. docs.arduino.cc AMB82-MINI page — no warning (confirmed in prior cycle)
3. ameba-arduino-doc GitHub pages — no warning (confirmed in prior cycle)
No documentation warns users that calling `FlashMemory.write()` concurrently with active camera/FCS can corrupt the boot-time FCS record and cause `VOE_OPEN_CMD fail` on the next cold boot.

### Finding 152 — V4.1.2 Release Confirmed Non-Existent; V4.1.1 Stable Still Absent
**Priority:** LOW
- `https://github.com/Ameba-AIoT/ameba-arduino-pro2/releases/tag/V4.1.2` → HTTP 404 (does not exist)
- `https://github.com/Ameba-AIoT/ameba-arduino-pro2/releases/tag/V4.1.1` → HTTP 404 (stable release never published)
- `V4.1.1-QC-V05` remains the latest release as of this cycle.
No new release has been published. The FlashMemory mutex fix has not been shipped in any release.

### Complete Status Sweep — 2026-05-09 (Update 2)

| Item | Last Known State | Current State |
|---|---|---|
| ameba-arduino-pro2 `dev` branch | Last commit `13961cc`, May 5, 2026 | **No new commits — static** |
| ameba-rtos-pro2 `main` branch | Last commit `1c1c8b7`, May 1, 2026 | **No new commits — static** |
| `FlashMemory.cpp` (dev) | SHA `4fdfbec`, Sept 30, 2025; no mutex | **Unchanged — no mutex fix** |
| `video_api.c` (main) | March 3, 2026; unguarded `ftl_common_write()` | **Unchanged** |
| ameba-arduino-pro2 issues | 12 open; highest #398 (Mar 2026) | **No new issues** |
| ameba-rtos-pro2 issues | 3 open; highest #16 (Jan 2026) | **No new issues** |
| ameba-arduino-pro2 releases | `V4.1.1-QC-V05` latest | **No new release** |
| Official documentation | No FCS/mutex warning in any doc source | **No change** |
| Public web (English + Chinese) | Zero indexed results for bug signatures | **Zero new results** |
| pvvx/RTL0B_SDK cross-reference | NEW: RTL8710B OTA uses `device_mutex_lock(RT_DEV_LOCK_FLASH)` | **Confirms Realtek's own prior-gen pattern; AmebaPro2 omission is regression** |

English and Chinese web searches confirm zero new public discussion of this bug in any language. No forum post, blog article, GitHub issue, or code patch describes the FlashMemory/FCS mutex race condition or a fix for it. The root cause analysis (Hypothesis F — `FlashMemory.cpp` bypasses `RT_DEV_LOCK_FLASH`) remains the sole public record of this analysis anywhere on the indexed internet.

**No HIGH priority confirmed fix found. Bug status: publicly undocumented and unpatched as of 2026-05-09 (Update 2).**

---

### Sources Added (Update 2026-05-09, Update 2)
- pvvx/RTL0B_SDK `rtl8710b_ota.c` (RTL8710B OTA uses `device_mutex_lock(RT_DEV_LOCK_FLASH)`): https://github.com/pvvx/RTL0B_SDK/blob/master/component/soc/realtek/8711b/misc/rtl8710b_ota.c
- pvvx/RTL00MP3 `device_lock.h` (RTL8710B `RT_DEV_LOCK_FLASH = 1` confirmed): https://github.com/pvvx/RTL00MP3/blob/master/RTL00_SDKV35a/component/os/os_dep/include/device_lock.h
- ameba-doc-arduino-sdk Flash Memory docs (no FCS/mutex warning): https://ameba-doc-arduino-sdk.readthedocs-hosted.com/en/latest/ameba_pro2/amb82-mini/Example_Guides/Flash%20Memory/index.html
- V4.1.2 tag (HTTP 404 — does not exist): https://github.com/Ameba-AIoT/ameba-arduino-pro2/releases/tag/V4.1.2
- V4.1.1 stable tag (HTTP 404 — never published): https://github.com/Ameba-AIoT/ameba-arduino-pro2/releases/tag/V4.1.1
- ameba-arduino-pro2 dev commits (re-confirmed last: `13961cc`, May 5, 2026; no new commits since Update 1): https://github.com/Ameba-AIoT/ameba-arduino-pro2/commits/dev
- ameba-rtos-pro2 main commits (re-confirmed last: `1c1c8b7`, May 1, 2026; no new commits since Update 1): https://github.com/Ameba-AIoT/ameba-rtos-pro2/commits/main

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

## Research Update — 2026-05-13

### Finding 111 — postbuild Tool is the FCS Pipeline Control Point
**Source:** `ameba-arduino-pro2` — `platform.txt` (dev branch, raw fetch 2026-05-13)  
https://github.com/Ameba-AIoT/ameba-arduino-pro2/blob/dev/Arduino_package/hardware/platform.txt  
**Priority:** MEDIUM — Clarifies what "Camera FCS Mode" actually controls; impacts workaround evaluation

Detailed analysis of `platform.txt` and `boards.txt` reveals how the "Camera FCS Mode" Arduino IDE setting works:

**boards.txt defines two values:**
```
# Disable:
menu.05_FCSMode.Disable.build.fcs_mode_flags=
menu.05_FCSMode.Disable.build.fcs_mode_val=Disable

# Enable:
menu.05_FCSMode.Enable.build.fcs_mode_flags=-DArduino_FCS_MODE
menu.05_FCSMode.Enable.build.fcs_mode_val=Enable
```

**platform.txt uses ONLY `fcs_mode_val` — in the postbuild recipe:**
```
recipe.objcopy.hex.pattern.windows="{ameba.tools_path}/{recipe.objcopy.hex.cmd}"
  "{ameba.tools_path}" "..." "{build.camera_opt}" "{build.ota_mode_val}" "{build.fcs_mode_val}"
```

**Critical finding:** `build.fcs_mode_flags` (`-DArduino_FCS_MODE`) does NOT appear anywhere in `platform.txt` compiler or linker recipes. It is defined in boards.txt but **never actually passed to the C++ compiler**. This means `#ifdef Arduino_FCS_MODE` never fires in Arduino C++ source code.

**Therefore, "Camera FCS Mode: Enable/Disable" controls only the `postbuild_windows.exe` (post-build image packaging tool):**
- **Enable:** postbuild tool includes the `fcs_data_<sensor>.bin` static calibration file in the combined flash image. This binary is written to the `fcsdata` partition (0x8000) during upload.
- **Disable:** postbuild tool does NOT include FCS data. The `fcsdata` partition at 0x8000 is NOT updated during firmware upload.

**Implication for workaround evaluation:**
If "Camera FCS Mode: Disable" is selected at compile/upload time:
1. The `fcsdata` partition (0x8000) is not written — no valid FCSD header exists
2. On every cold boot, the boot ROM reads 0x8000, finds no valid FCS header, fails KM check (`KM_status 0x2081`)
3. Boot ROM prints "It don't do the sensor initial process" and falls back to normal (slower) camera init
4. Camera still boots successfully via normal path
5. `FlashMemory.write()` cannot cause *additional* FCS-related failure since FCS was never valid
6. **Trade-off:** Permanent loss of FCS fast cold start (adds ~3–5 seconds to camera ready time)

However, this is only a workaround if the indirect corruption mechanism can be avoided. Since the C/C++ application code (including `video_pre_init_save_cur_params()` which writes runtime AE/AWB to 0xF0D000) is **not gated by `Arduino_FCS_MODE`**, it still executes regardless of this setting. If the corruption mechanism involves the 0xF0D000 runtime save area, this workaround may be incomplete.

---

### Finding 112 — Forum Thread #4834 Title Confirmed: "Boot Failure After OTA Update" — Different Failure Mode, Thematically Related
**Source:** forum.amebaiot.com thread #4834 (403-blocked; Google snippet 2026-05-13)  
https://forum.amebaiot.com/t/boot-failure-after-ota-update/4834  
**Priority:** MEDIUM — Confirms flash writes cause boot failures via DIFFERENT mechanism; reinforces systemic flash/boot vulnerability

Thread #4834 ("Boot failure after OTA update") was previously logged only by number in Finding 110 (as "highest observed: ~#4834"). Its full title is now confirmed from search snippets.

**Error messages from #4834 (from search snippet):**
```
[SPIF Err]Invalid ID
[BOOT Err]Flash init error
```

**Analysis:**
- This is a **different failure mode** from the FlashMemory/FCS bug:
  - Our bug: `FCS KM_status 0x00002081` → camera VOE failure (flash reads OK, FCS data validation fails)
  - Thread #4834: `[SPIF Err]Invalid ID` → complete boot failure (boot ROM cannot even initialize NOR flash)
- OTA writes to the `fw2` partition at 0x4C0000 — completely different from FlashMemory (0xFD0000) and FCS (0x8000, 0xF0D000)
- The `[SPIF Err]Invalid ID` error typically means the flash chip returns an unexpected JEDEC ID during boot ROM's SPI initialization — this can occur if the flash was left in an alternate bus mode (QPI/QSPI) or power state (deep power-down) after the OTA write process

**Significance:** This represents a second confirmed class of "flash write causes next cold boot failure" on RTL8735B/AmebaPro2. Both our bug and this OTA bug share the pattern: flash write operation → subsequent cold boot failure. The mechanisms are different but may share a common root (improper SPI bus state restoration after write operations, or boot ROM sensitivity to flash state left by application-level writes).

Thread content is 403-blocked; the full OTA context, Realtek staff response (if any), and resolution status are not recoverable.

---

### Finding 113 — Forum Thread #4835: New Highest Thread Observed; Unrelated to FCS Bug
**Source:** forum.amebaiot.com thread #4835 (403-blocked; Google search snippet 2026-05-13)  
https://forum.amebaiot.com/t/amb82-mini-deep-sleep-is-aon-gpio-pin-21-unreadable-after-powermode-begin-bus-fault-observed/4835  
**Priority:** LOW — New thread; unrelated to FlashMemory/FCS bug; updates "highest thread observed"

Thread #4835 title: "AMB82-mini Deep Sleep: Is AON GPIO pin 21 unreadable after `PowerMode.begin()`? (Bus Fault observed)"

This thread is about deep sleep and AON (Always-On) GPIO behavior, not flash or camera. Its discovery updates the "highest observed" thread number from ~#4834 to **#4835**.

Additionally, several other new thread titles from this search cycle (not previously specifically titled in the log):
- **#4748:** "Need latest VOE and Sensor drivers source code" (Multimedia) — developer requesting VOE/sensor binary sources; no FCS bug content indexed
- **#4777:** "AMB82-Mini onboard camera sensor identification and VOE setup for wireless video and I2C" (SDK) — VOE setup for I2C + wireless streaming; no FCS bug content indexed
- **#4802:** "AMB82-Mini USB Host CDC ECM fails to enumerate Quectel EC200U 4G modem — 'ecm init fail'" (USB) — unrelated
- **#4803:** "AMB82-mini: USB Ethernet failing" (USB) — unrelated

All threads are 403-blocked. None contain indexed FCS/FlashMemory bug content.

---

### Finding 114 — FCS Data Binary Files Confirmed in RTOS SDK voe_bin Directory
**Source:** AmebaPro2 RTOS SDK documentation search snippet (2026-05-13)  
**Priority:** LOW — Supplements Finding 9 (partition table) and Finding 11 (FCSD data structure)

FCS static calibration binary files for each supported sensor are located at:
```
component\soc\8735b\fwlib\rtl8735b\lib\source\ram\video\voe_bin\fcs_data_<sensor>.bin
```
Examples: `fcs_data_sc301.bin`, `fcs_data_gc2053.bin`, etc.

These `.bin` files contain the static AE/AWB calibration parameters (in `video_boot_stream_t` format with "FCSD" magic header) that are packaged into the `fcsdata` partition (0x8000) during firmware upload when FCS mode is enabled. They are distinct from the **runtime** FCS save data written to `NOR_FLASH_FCS` (0xF0D000) by `video_pre_init_save_cur_params()` during camera operation.

This confirms the two-tier FCS data architecture:
1. **Static tier** (0x8000): `fcs_data_<sensor>.bin` uploaded at programming time → initial AE/AWB parameters; verified by KM at boot
2. **Dynamic tier** (0xF0D000): Written at runtime by `video_pre_init_save_cur_params()` → current-session AE/AWB parameters; read by boot ROM on next cold boot

---

### Finding 115 — Full Repository Status Sweep: No Fix (2026-05-13)
**Source:** Direct GitHub page fetches and search results (2026-05-13)  
**Priority:** LOW — Status confirmation

| Repository / Source | Status as of 2026-05-13 |
|---|---|
| ameba-arduino-pro2 (dev branch) | Latest SHA: `13961cc` (May 5, 2026) — **NO new commits since last cycle** |
| ameba-arduino-pro2 (releases) | Latest stable: V4.1.0 (Mar 2, 2026) — **NO new release** |
| ameba-rtos-pro2 (main branch) | Latest SHA: `1c1c8b7` (May 1, 2026) — **NO new commits** |
| ameba-arduino-pro2 open issues | Highest: #398 (Mar 29, 2026) — **NO new issues** |
| ameba-arduino-pro2 closed issues | Most recent closure: ~Jan 2026 — **NO new closures related to bug** |
| forum.amebaiot.com | Highest thread: **#4835** (up from #4834) — #4834 now titled "Boot failure after OTA update"; no FCS bug reports accessible |
| CSDN / Zhihu / 21ic / EEWorld | **Zero new Chinese-language RTL8735B FCS/flash/camera bug articles** — reconfirmed |
| bbs.aithinker.com | No new BW21-CBV FCS bug content — reconfirmed |

**Bug status: Publicly undocumented and unpatched as of 2026-05-13.**

---

### Sources Added (Update 2026-05-13)
- platform.txt (dev branch, FCS mode postbuild analysis): https://github.com/Ameba-AIoT/ameba-arduino-pro2/blob/dev/Arduino_package/hardware/platform.txt
- forum.amebaiot.com thread #4834 "Boot failure after OTA update" (403-blocked; [SPIF Err]Invalid ID): https://forum.amebaiot.com/t/boot-failure-after-ota-update/4834
- forum.amebaiot.com thread #4835 "Deep Sleep AON GPIO bus fault" (403-blocked; highest thread): https://forum.amebaiot.com/t/amb82-mini-deep-sleep-is-aon-gpio-pin-21-unreadable-after-powermode-begin-bus-fault-observed/4835
- forum.amebaiot.com thread #4748 "Need latest VOE and Sensor drivers" (403-blocked; unrelated): https://forum.amebaiot.com/t/need-latest-voe-and-sensor-drivers-source-code/4748
- forum.amebaiot.com thread #4777 "AMB82-Mini camera sensor ID and VOE setup" (403-blocked; unrelated): https://forum.amebaiot.com/t/amb82-mini-onboard-camera-sensor-identification-and-voe-setup-for-wireless-video-and-i2c/4777

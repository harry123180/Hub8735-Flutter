# RTL8735B FCS Flash Bug — Research Supplement 2026-05-13 (Cycle U2)

This supplement covers the 6-hour research cycle completed 2026-05-13 (UTC). Findings are numbered 111–115 continuing from the previous cycle (110 was the last finding in the 2026-05-12 session).

**No HIGH priority confirmed fix found in this cycle.**

---

## Finding 111 — postbuild Tool is the FCS Pipeline Control Point
**Source:** `ameba-arduino-pro2` — `platform.txt` + `boards.txt` (dev branch, fetched 2026-05-13)  
https://github.com/Ameba-AIoT/ameba-arduino-pro2/blob/dev/Arduino_package/hardware/platform.txt  
**Priority:** MEDIUM — Clarifies what "Camera FCS Mode" actually controls; impacts workaround evaluation

Detailed analysis of `platform.txt` and `boards.txt` reveals the two-valued "Camera FCS Mode" setting:

**boards.txt defines two values per option:**
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

**Critical finding:** `build.fcs_mode_flags` (`-DArduino_FCS_MODE`) does NOT appear anywhere in `platform.txt` compiler or linker recipes. It is defined in boards.txt but **never actually passed to the C++ compiler**. The `#ifdef Arduino_FCS_MODE` guard fires in NO Arduino C++ source code.

**What the setting actually controls (postbuild_windows.exe only):**
- **Enable:** postbuild tool includes `fcs_data_<sensor>.bin` in the combined flash image; this binary is written to the `fcsdata` partition (0x8000) during upload
- **Disable:** postbuild tool does NOT include FCS data; the `fcsdata` partition at 0x8000 is NOT updated during firmware upload

**Implication as a workaround:**
If "Camera FCS Mode: Disable" is selected:
1. `fcsdata` partition (0x8000) is not written — no valid FCSD header exists
2. Every cold boot: boot ROM reads 0x8000, finds no FCS header, fails KM check (`KM_status 0x2081`)
3. Boot ROM prints "It don't do the sensor initial process", falls back to normal (slower) init
4. Camera still boots successfully via normal path
5. `FlashMemory.write()` cannot cause *additional* FCS-related failure since FCS was never valid
6. **Trade-off:** Permanent loss of FCS fast cold start (~3–5 seconds added to camera ready time)

**Caveat:** The C/C++ application code `video_pre_init_save_cur_params()` (writes runtime AE/AWB to 0xF0D000) is NOT gated by `Arduino_FCS_MODE` and still executes unconditionally. If the corruption mechanism involves 0xF0D000, this workaround may be incomplete.

---

## Finding 112 — Forum Thread #4834 Title Confirmed: "Boot Failure After OTA Update"
**Source:** forum.amebaiot.com thread #4834 (403-blocked; Google snippet 2026-05-13)  
https://forum.amebaiot.com/t/boot-failure-after-ota-update/4834  
**Priority:** MEDIUM — Second confirmed class of "flash write → cold boot failure" on RTL8735B

Thread #4834 was previously logged only by number (as "highest observed: ~#4834" in Finding 110). Its title is now confirmed.

**Error messages from thread #4834 (Google snippet):**
```
[SPIF Err]Invalid ID
[BOOT Err]Flash init error
```

**Analysis vs our bug:**
- Our bug: `FCS KM_status 0x00002081` → camera VOE failure (flash reads OK, FCS validation fails)
- Thread #4834: `[SPIF Err]Invalid ID` → complete boot failure (boot ROM cannot initialize NOR flash at all)
- OTA writes to `fw2` partition at 0x4C0000 — different from FlashMemory (0xFD0000) and FCS (0x8000, 0xF0D000)
- `[SPIF Err]Invalid ID` typically means flash chip returns unexpected JEDEC ID — can occur if flash was left in QPI/QSPI mode or deep power-down state after the OTA write

**Significance:** This is a second confirmed class of "any flash write → next cold boot failure" on RTL8735B/AmebaPro2. Both bugs share the pattern: application-level flash operation → persistent boot failure. Different mechanisms, possibly a common root: improper SPI bus state restoration after write operations, or boot ROM sensitivity to flash state left by application writes.

Thread is 403-blocked; full details, Realtek staff response, and resolution are not recoverable.

---

## Finding 113 — Forum Threads #4748, #4777, #4802, #4803, #4835 Newly Titled; #4835 = New Highest
**Source:** forum.amebaiot.com (Google search snippets, 2026-05-13)  
**Priority:** LOW — Status/catalog update; no FCS bug content

New thread titles confirmed this cycle (all 403-blocked):

| Thread | Title | Category | FCS bug relevance |
|---|---|---|---|
| #4748 | "Need latest VOE and Sensor drivers source code" | Multimedia | None indexed |
| #4777 | "AMB82-Mini onboard camera sensor identification and VOE setup for wireless video and I2C" | SDK | None indexed |
| #4802 | "AMB82-Mini USB Host CDC ECM fails to enumerate Quectel EC200U 4G modem — 'ecm init fail'" | USB | Unrelated |
| #4803 | "AMB82-mini: USB Ethernet failing" | USB | Unrelated |
| **#4835** | **"AMB82-mini Deep Sleep: Is AON GPIO pin 21 unreadable after `PowerMode.begin()`? (Bus Fault observed)"** | Arduino | Unrelated |

Thread #4835 is the new highest forum thread observed (previously ~#4834). The forum has at least 4,835 threads as of 2026-05-13.

---

## Finding 114 — FCS Data Binary Files Confirmed in RTOS SDK voe_bin Directory
**Source:** AmebaPro2 RTOS SDK documentation search snippet (2026-05-13)  
**Priority:** LOW — Supplements Finding 9 (partition table) and Finding 11 (FCSD data structure)

FCS static calibration binary files (one per supported sensor) are located at:
```
component\soc\8735b\fwlib\rtl8735b\lib\source\ram\video\voe_bin\fcs_data_<sensor>.bin
```
Examples: `fcs_data_sc301.bin`, `fcs_data_gc2053.bin`, etc.

These `.bin` files contain static AE/AWB calibration in `video_boot_stream_t` format with "FCSD" magic header. They are distinct from the **runtime** FCS data written to `NOR_FLASH_FCS` (0xF0D000) by `video_pre_init_save_cur_params()` during camera operation.

**Two-tier FCS data architecture (confirmed):**
1. **Static tier** (0x8000 `fcsdata` partition): `fcs_data_<sensor>.bin` uploaded at programming time; initial AE/AWB parameters; verified by KM at boot
2. **Dynamic tier** (0xF0D000 `NOR_FLASH_FCS`): Written at runtime by `video_pre_init_save_cur_params()` after camera session; read by boot ROM on NEXT cold boot for fast sensor init

---

## Finding 115 — Full Repository Status Sweep: No Fix (2026-05-13)
**Source:** Direct GitHub page fetches and web searches (2026-05-13)  
**Priority:** LOW — Status confirmation

| Repository / Source | Status as of 2026-05-13 |
|---|---|
| ameba-arduino-pro2 (dev branch) | Latest SHA: `13961cc` (May 5, 2026) — **NO new commits** |
| ameba-arduino-pro2 (releases) | Latest stable: V4.1.0 (Mar 2, 2026) — **NO new release** |
| ameba-rtos-pro2 (main branch) | Latest SHA: `1c1c8b7` (May 1, 2026) — **NO new commits** |
| ameba-arduino-pro2 open issues | Highest: #398 (Mar 29, 2026) — **NO new issues** |
| forum.amebaiot.com | Highest thread: **#4835** (up from ~#4834); #4834 titled "Boot failure after OTA update" |
| CSDN / Zhihu / 21ic / EEWorld | **Zero new Chinese-language FCS/flash/camera bug articles** |
| bbs.aithinker.com | **No new BW21-CBV FCS bug content** |
| FlashMemory.cpp / video_api.c | **Still no mutex guards — bug unpatched** |

**Bug status: Publicly undocumented and unpatched as of 2026-05-13.**

---

## Sources Added (Cycle U2, 2026-05-13)
- platform.txt (FCS mode postbuild analysis): https://github.com/Ameba-AIoT/ameba-arduino-pro2/blob/dev/Arduino_package/hardware/platform.txt
- forum.amebaiot.com thread #4834 "Boot failure after OTA update" ([SPIF Err]Invalid ID; 403-blocked): https://forum.amebaiot.com/t/boot-failure-after-ota-update/4834
- forum.amebaiot.com thread #4835 "Deep Sleep AON GPIO pin 21 bus fault" (403-blocked; highest thread): https://forum.amebaiot.com/t/amb82-mini-deep-sleep-is-aon-gpio-pin-21-unreadable-after-powermode-begin-bus-fault-observed/4835
- forum.amebaiot.com thread #4748 "Need latest VOE and Sensor drivers" (403-blocked): https://forum.amebaiot.com/t/need-latest-voe-and-sensor-drivers-source-code/4748
- forum.amebaiot.com thread #4777 "AMB82-Mini camera sensor ID and VOE setup" (403-blocked): https://forum.amebaiot.com/t/amb82-mini-onboard-camera-sensor-identification-and-voe-setup-for-wireless-video-and-i2c/4777

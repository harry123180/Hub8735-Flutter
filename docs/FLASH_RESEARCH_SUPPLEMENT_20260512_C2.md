## Research Update — 2026-05-12 (Cycle 2)

### Finding 111 — Forum Thread #4832: sys_reset Inconsistency After Camera+OTA App (NEW — Parallel Bug)
**Source:** https://forum.amebaiot.com/t/sys-reset-is-not-consistent-why/4832 (403-blocked; Google snippet only)
**Priority:** MEDIUM — Parallel manifestation of our core bug; supports peripheral-register root-cause hypothesis

Thread #4832 ("Sys_reset is not consistent, why?") was posted approximately 3 weeks before 2026-05-12 (~April 21, 2026). The poster reports:

- A **camera application** that performs an **OTA firmware update** (large flash write + erase) and then calls `sys_reset()` to reboot
- After `sys_reset()`, the device enters a stuck state: **no serial console output, no boot messages**
- Recovery requires **physical power disconnection and reconnection**
- The behavior is described as inconsistent ("sometimes works, sometimes not") — identical intermittency to our bug

The forum SDK description of `sys_reset()` is crucial: *"sys_reset() is software reset that only restarts the CPU, while the peripheral register setting is not reset."*

**Why this matters for our bug:** This is an independent report of the same root-cause pattern:
1. Flash write/erase operation (OTA uses `flash_erase_sector()` + `flash_stream_write()`)
2. Soft/warm reset (sys_reset ≈ warm reboot; our bug: cold power cycle needed but FCS runs at power-on)
3. Camera/boot initialization fails because **SPI peripheral registers or flash chip state** is not fully reset by a CPU-only restart

The explanation that peripheral registers are NOT cleared by `sys_reset()` maps directly onto our hypothesis: after `FlashMemory.write()` exercises the SPI flash controller (WREN + PAGE_PROGRAM), the **SPI controller's state machine or the flash chip's WEL/WIP status register** persists across a warm reset. Boot ROM then encounters unexpected SPI bus state when trying to read FCS parameters, causing `FCS KM_status 0x00002081 err 0x0000200a`. A full power cycle resets both the CPU peripheral registers AND the flash chip's power-on state, which is why cold boots from clean power always work.

No fix has been posted to this thread in available snippets.

---

### Finding 112 — Forum Thread #4834: Boot Failure After OTA — NOR Flash Init Error (NEW THREAD)
**Source:** https://forum.amebaiot.com/t/boot-failure-after-ota-update/4834 (403-blocked; Google snippet only)
**Priority:** LOW — Different failure mode (NOR flash completely undetected), but same trigger (OTA flash writes); adds to pattern

Thread #4834 ("Boot failure after OTA update") describes a developer who:
- Integrated OTA update functionality into their AMB82-Mini/RTL8735B firmware
- After OTA completes and device reboots, the boot ROM reports **"[SPIF Err]Invalid ID"** and **"Flash init error"**
- System falls back to NAND flash boot path and fails to start

This is a **distinct** failure mode from our FCS camera bug (in our bug, NOR flash is detected and read correctly; the FCS data region is the problem). However, the trigger is identical: OTA = large-scale flash sector erases and page programs, after which the boot ROM cannot initialize correctly.

The pattern confirms a broader class of RTL8735B bugs where **flash write operations leave the device in a state that causes the next boot's low-level initialization to fail**. In our bug, it is the FCS boot path that fails; in thread #4834, it is the NOR flash identification that fails.

No fix confirmed from available snippet.

---

### Finding 113 — New Forum Threads #4748 and #4777 Observed (VOE/Camera Focus)
**Source:** https://forum.amebaiot.com/t/need-latest-voe-and-sensor-drivers-source-code/4748 (403-blocked)
**Source:** https://forum.amebaiot.com/t/amb82-mini-onboard-camera-sensor-identification-and-voe-setup-for-wireless-video-and-i2c/4777 (403-blocked)
**Priority:** LOW — New threads logged; content inaccessible; no confirmed FCS bug relevance from Google snippets

Thread #4748 requests the latest VOE (Video Object Engine) and sensor driver source code. Thread #4777 discusses onboard camera sensor identification and VOE setup combined with I2C and wireless video. Neither thread's title or Google-indexed excerpt mentions flash write failures, FCS errors, or cold-boot camera failure. Content is 403-blocked; cannot assess in detail.

---

### Finding 114 — Forum Thread #4780: Matter OTA Issue (First Logged)
**Source:** https://forum.amebaiot.com/t/matter-ota-issue-with-rtl-amebazii-dev-2vo/4780 (403-blocked; Google snippet only)
**Priority:** LOW — Matter protocol OTA issue, unrelated to FCS camera race bug

Thread #4780 discusses a Matter OTA failure on `RTL_AMEBAZII_DEV_2VO`. This is unrelated to the FCS/FlashMemory camera race bug. Logged for completeness.

---

### Finding 115 — YELUFT BW21-CBV-Kit Listed on Amazon (New Retail Listing)
**Source:** https://www.amazon.com/YELUFT-BW21-CBV-Kit-Recognition-Transmission-Wide-Angle/dp/B0FY67YTFN (403-blocked; snippet only)
**Priority:** LOW — New third-party retail listing of BW21-CBV-Kit observed; no FCS bug user reviews accessible

A third-party seller (YELUFT) lists a BW21-CBV-Kit (ASIN B0FY67YTFN) on Amazon.com. The product listing is 403-blocked; no user Q&A or reviews mentioning flash write/camera boot failures are accessible. Logged to track commercial availability of the affected hardware platform.

---

### Finding 116 — Complete Status Sweep: Bug Unpatched as of 2026-05-12 (Cycle 2)
**Source:** Exhaustive sweep of all tracked sources (2026-05-12, Cycle 2)
**Priority:** LOW — Status confirmation

| Repository / Source | Last activity | Status |
|---|---|---|
| ameba-arduino-pro2 (dev branch) | May 5, 2026 — SHA `13961cc` | **No new commits since Cycle 1** |
| ameba-arduino-pro2 (releases) | V4.1.1-QC-V05 (March 6, 2026 pre-release) | **No new release** |
| ameba-rtos-pro2 (main branch) | May 1, 2026 — SHA `1c1c8b7` | **No new commits** |
| ameba-arduino-pro2 issues | Highest: #398 (Mar 29, 2026); 12 open | **No new FCS/FlashMemory/VOE issues** |
| forum.amebaiot.com | Highest observed: #4834; threads #4748, #4777, #4780, #4832, #4834 newly analyzed (all 403-blocked) | **No accessible FCS/flash bug content in any thread** |
| FlashMemory.cpp (dev) | SHA 4fdfbec (Sept 30, 2025) | **Still NO mutex fix — reconfirmed** |
| CSDN / Zhihu / 21ic / EEWorld | — | **Zero Chinese-language reports — reconfirmed** |
| Amazon BW21-CBV-Kit (YELUFT) | ASIN B0FY67YTFN | **New retail listing; no user bug reports accessible** |

**No HIGH priority confirmed fix found. Bug status: publicly undocumented and unpatched as of 2026-05-12 (Cycle 2).**

---

### Sources Added (Update 2026-05-12, Cycle 2)
- forum.amebaiot.com thread #4832 (sys_reset inconsistency, camera+OTA; ~Apr 21 2026; 403-blocked; **parallel bug, MEDIUM priority**): https://forum.amebaiot.com/t/sys-reset-is-not-consistent-why/4832
- forum.amebaiot.com thread #4834 (boot failure after OTA, NOR flash init error; 403-blocked): https://forum.amebaiot.com/t/boot-failure-after-ota-update/4834
- forum.amebaiot.com thread #4748 (VOE source code request; 403-blocked): https://forum.amebaiot.com/t/need-latest-voe-and-sensor-drivers-source-code/4748
- forum.amebaiot.com thread #4777 (camera sensor ID + VOE setup + I2C; 403-blocked): https://forum.amebaiot.com/t/amb82-mini-onboard-camera-sensor-identification-and-voe-setup-for-wireless-video-and-i2c/4777
- forum.amebaiot.com thread #4780 (Matter OTA issue; 403-blocked; unrelated): https://forum.amebaiot.com/t/matter-ota-issue-with-rtl-amebazii-dev-2vo/4780
- Amazon YELUFT BW21-CBV-Kit (ASIN B0FY67YTFN; new retail listing): https://www.amazon.com/YELUFT-BW21-CBV-Kit-Recognition-Transmission-Wide-Angle/dp/B0FY67YTFN

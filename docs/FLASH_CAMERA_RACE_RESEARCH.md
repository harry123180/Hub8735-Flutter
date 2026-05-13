# RTL8735B Flash → Camera Boot Race — Research Log

> **NOTE (2026-05-13):** This file was accidentally truncated during an automated push.
> **Full research history (Findings 1–110)** is preserved in:
> - `docs/FLASH_RESEARCH_SUPPLEMENT_20260505_20260509.md` — Findings 17–88 (comprehensive archive)
> - `docs/FLASH_RESEARCH_SUPPLEMENT_20260512_C2.md`, `_U2.md`, `_U3.md` — Findings 89–110
> - `docs/FLASH_RESEARCH_SUPPLEMENT_20260513.md` — earlier Findings 111–114 from today
> - `docs/FLASH_RESEARCH_SUPPLEMENT_20260513_U2.md` — Findings 111–115 from THIS cycle
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
| 111–115 | FLASH_RESEARCH_SUPPLEMENT_20260513_U2.md | May 13 THIS cycle: postbuild FCS analysis; thread #4835 |

## Key Confirmed Facts

- **FCS data address**: `fcsdata` partition = 0x8000 (boot ROM reads here); `NOR_FLASH_FCS` = 0xF0D000 (runtime AE/AWB)
- **FlashMemory address**: 0xFD0000–0xFFFFFF (no direct overlap with FCS)
- **Root cause mechanism**: INDIRECT — still unknown; address overlap disproved (Finding 13)
- **Postbuild tool**: `build.fcs_mode_val` controls whether `fcs_data_<sensor>.bin` is uploaded to fcsdata partition
- **`Arduino_FCS_MODE`**: Defined in boards.txt but NOT passed to C++ compiler (Finding 111)
- **No public fix**: Bug is undocumented and unpatched as of 2026-05-13

## Supplement Files Quick Reference

See `docs/FLASH_RESEARCH_SUPPLEMENT_20260513_U2.md` for the latest findings from this research cycle.

# BIOS 03.11.26 KEYB/SD

Fork of the BIOS `024 - ... msbasic-20261024` (version 24.10.26), made for the applications of `MiniVIC Apps`.
It fixes two problems: the keyboard gave no arrows, Delete, function keys, Ctrl and Alt, and the SD could only be read, and only up to 2 GB.
Everything that was there before works as before: menu, BASIC, WozMon, program loading and the jump table `$FD00-$FD15`.

## Build and EEPROM
- `sh make.sh` creates `tmp/boogs.bin` (32 KB, the whole CAT28C256P image from `$8000` to `$FFFF`).
- The main menu shows the version `03.11.26 KEYB/SD` (27.10.26 KEYB/SD before the SD submenus of 03-11-2026).

## New jump table entries (at the end, the old ones do not move)

| Address | Name | Use |
| :--- | :--- | :--- |
| `$FD18` | `JT_SD_READ_SECTOR` | reads sector `SD_LBA` into the buffer `X`/`Y` (lo/hi, 512 bytes). C=0 ok, C=1 error. Preserves A/X/Y and the I flag |
| `$FD1B` | `JT_SD_WRITE_SECTOR` | writes the buffer `X`/`Y` (512 bytes) to sector `SD_LBA`. C=0 ok, C=1 error |
| `$FD1E` | `JT_SD_INIT` | (re)initializes the SD. C=0 and A = type (1 SDSC v1, 2 SDSC v2, 3 SDHC/SDXC); C=1 and A=0 if there is no card |
| `$FD21` | `JT_KB_SET_MODE` | A=0 classic keyboard, A≠0 extended keyboard |

`SD_LBA` = `$0316-$0319`, 32-bit sector number (512 bytes), **little endian**. It is always a sector number, also on small SD cards: the BIOS does the conversion to bytes.
The sector routines initialize the card by themselves when needed (`sd_type = 0`).

## SD: all cards
- Init: CMD0, then CMD8. If the answer is "illegal command" the card is an SDSC v1, if the `$1AA` echo comes back it is a v2. ACMD41 follows (with HCS on v2). On v2 cards CMD58 reads the CCS bit: if it is 1 the card is SDHC/SDXC and is addressed in sectors. On SDSC cards CMD16 sets 512 byte blocks.
- Program loading (menu, `JT_LOAD_RUN_SLOT`, `JT_INIT_SDCARD`) now counts in **sectors**: slot N = sector N×64, data = sector N×64+8. The `make_sd.py` format does not change.
- Timeouts on everything. Before, without a card, the SD menu hung. Now, after about 5 s, "NO VALID SD DIRECTORY FOUND" appears, and the routines return C=1.
- Writing with CMD24: `$FE` token, 512 bytes, dummy CRC, check of the `xxx00101` response, wait for the end of busy.
- After a sector read or write, Shift, Ctrl, Alt and the keyboard CA1 flag are cleared, because scancodes are lost during the SD access. Caps Lock and the key buffer stay.

## Extended keyboard (`JT_KB_SET_MODE` with A≠0)

| Key | Code |
| :--- | :--- |
| ↑ ↓ ← → | `$80` `$81` `$82` `$83` |
| Home End PgUp PgDn | `$84` `$85` `$86` `$87` |
| Ins Delete | `$88` `$89` |
| F1…F12 | `$90`…`$9B` |
| Ctrl+letter | `$01`…`$1A` (Ctrl+S = `$13`) |
| Alt+letter | `$E1`…`$FA` (lowercase + `$80`) |
| Enter / Backspace / Tab / Esc | `$0D` / `$08` / `$09` / `$1B` |
| Shift | full US table (also `?`, which is lost in classic mode) |
| Caps Lock | swaps upper and lower case of letters only (the LED stays off: the board does not send to the keyboard) |
| Keypad | always digits; keypad Enter = `$0D` |

- Right Ctrl and Alt (`E0 14`, `E0 11`) work like the left ones. The fake Shifts that some keyboards send with the arrows (`E0 12`) are ignored.
- Classic mode stays identical to the old BIOS, with one fix: releasing Shift now **clears** the flag instead of toggling it, so a lost Shift no longer stays stuck.
- `SHOW_MENU` (so every return to the menu) sets classic mode again. BASIC and WozMon always use it.

## `[TYPE] Name` line on the serial port (30-10-2026)
When a program starts from the menu (entry with the "run" flag) or with `JT_LOAD_RUN_SLOT`, the BIOS sends **on the serial port only** a line like `[GAME] ASTEROIDS` + CR LF. The screen does not change, and the rest of the menu stays as it is.
- The type is in the SD directory, in byte +6 of the entry parameters (`+16 + i*8 + 6`): 0 unknown (no line), 1 GAME, 2 APP, 3 TOOL.
- Byte +7 is the length of the name to send (0 = whole name). `make_sd.py` puts there the length without the ` - GAME` suffix shown in the menu.
- Before, the two bytes were reserved and were 0. The 24.10.26 BIOS does not read them, so the new SD also works with it.
- `sd_get_params` copies type and name to `$031A-$033A`, before the load overwrites the directory at `$1000`. `SD_ANNOUNCE` sends the line like `CHROUT` does (byte in `ACIA_DATA` and fixed delay), but without writing to the screen. It never waits for the ACIA: without a serial board nothing happens.
- `JT_INIT_SDCARD` (load without running) does not send the line.

## SD submenus (03-11-2026)
Key 3 of the main menu reads directory page 0 (no card or no valid directory: the same error as before) and then asks:

```
 1. GAMES   2. APPS   3. SOUNDS   4. ALL PROGRAMS   ESC = MAIN MENU
```

- GAMES shows type 1, APPS types 2 and 3 (APP and TOOL), SOUNDS type 4. The type is the directory byte +6 of the entry parameters (see above). `make_sd.py` writes type 4 for `[SOUND]` or a ` - SOUND` / ` - SONG` suffix.
- ALL is the old list: the SD pages as they are, read one at a time. It is the only place where type 0 programs appear (SD cards made before the types, or images built by the emulator).
- For GAMES, APPS and SOUNDS, `sd_scan` reads every directory page once and keeps slot, flags and name of the matching programs in RAM. Each page of the submenu is then rebuilt at `$1000` in the directory layout, so the same drawing code, A/D paging and 1-9 keys work as before. The key gives the real SD slot, so loading and the `[TYPE] Name` serial line do not change.
- An empty submenu says `NO PROGRAMS OF THIS KIND ON THE SD`; a key goes back to the choice.
- ESC in a list goes back to the choice, ESC in the choice goes back to the main menu.
- `SD_ANNOUNCE` knows type 4 and sends `[SOUND] Name`.
- The SD format does not change: the 24.10.26 BIOS ignores the type byte, so it still reads the new SD.

## New RAM used by the BIOS
- `$0309` `kb_mode`
- `$030A` `sd_type`
- `$030B-$030E` R3/R7 response
- `$030F` retry counter
- `$0316-$0319` `SD_LBA`
- `$031A-$033A` type and name for the serial line (only needed during the load: afterwards the program can use them)
- zero page `$4D` (free before)
- SD menu only (free again once a program is loaded): `$1200-$1208` menu state, `$1300-$13FE` slots and `$1400-$14FE` flags of the submenu, `$2000-$3FDF` submenu names (32 bytes each)

## Code
- `keyboard_drv.s`: `kb_mode`, jump to the extended decoder, Shift fix. The `kbx_interrupt` decoder and `KB_SET_MODE` are at the end, in the `PROGRAM` segment.
- `sdcard_drv.s`: rewritten (init for all cards, sectors, writing, timeouts, public API); `sd_save_announce` and `SD_ANNOUNCE` for the serial line, also called by `LOAD_AND_RUN_SLOT`.
- `jumptable.s`: 4 new entries. `boot_menu_multi.s`: version, `stz sd_type` in `SHOW_MENU`, `SD_ANNOUNCE` in `sd_do_copy` before running the program.
- `boot_menu_multi.s` (03-11-2026): submenu choice `sd_cat_menu`, `sd_scan`, `sd_build_page`, titles per submenu.

## Tests (`test_keyb_sd/`)
`node test_keyb_sd/run.mjs` tests `tmp/boogs.bin` on the core of the `bo6502-emulator` emulator (which is not changed). The checks:
- BASIC and WozMon start;
- classic mode unchanged;
- 34 extended keys plus Caps, Ctrl and Alt;
- loading a game from the menu and writing/reading a sector in the document area (sector 16391), on the emulator SD, SDSC v1, SDSC v2 and SDHC;
- error beyond the end of the card and behaviour without a card;
- serial line: `[GAME] ASTEROIDS` from the menu (shortened name), no line for type 0, `[APP] ...` with a 31 character name from `JT_LOAD_RUN_SLOT` on entry 8 of the page;
- submenus on an SD without types: GAMES says it is empty and goes back to the choice.

`node test_system/run.mjs` (after `python test_system/make_test_sd.py`) checks the submenus on the real SD: GAMES, APPS and SOUNDS list exactly the programs of their types, in order and with paging; applications start from APPS, ASTEROIDS from GAMES and from ALL, a song from SOUNDS with `[SOUND] ...`; ESC goes back one level.

The SDHC/v2 model is in the test, because the emulator SD is v1 only.

## To be tried on the real hardware
- SD cards of different types (one of 2 GB or less and one SDHC) and writing a sector.
- BTC 5100: arrows, Fn+keys, F11/F12, Caps Lock.
- Problem that was already there: in BASIC, typing with Shift gives doubled characters (`ppRINT`). It happens the same way with the 24.10.26 BIOS in the emulator, so it was not introduced here.

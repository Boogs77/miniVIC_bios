# Emulator change request: BIOS selection, SD v2/SDHC, document area, browser keys

Target repository: `bo6502-emulator` (https://github.com/Boogs77/BO6502-miniVIC-emulator, local copy
`C:\Users\Marco\Documents\Claude\bo6502-emulator`). Follow that repository's `CLAUDE.md`: everything is in
English, no `enum`, no parameter properties, no runtime dependencies, run `npm test` and look at the
screenshots in `tests/out/`.

Requested by: MiniVIC Apps project (office applications for the miniVIC), 2026-10-27.

---

## 🎯 Goal

The emulator must run both miniVIC BIOS versions, and the user picks one:

| Id | Name in the UI | Source | Notes |
| :--- | :--- | :--- | :--- |
| `std` | `BIOS 24.10.26 (standard)` | `public/roms/minivic.bin` (the current one, unchanged) | **default** |
| `keybsd` | `BIOS 27.10.26 KEYB/SD` | `public/roms/minivic_keybsd.bin` (new) | for the MiniVIC Apps |

The KEYB/SD BIOS is a fork of the standard one. It keeps the old jump table `$FD00-$FD15` and adds:
- an extended keyboard mode: arrows, Home/End, PgUp/PgDn, Ins/Del, F1-F12, Ctrl, Alt, Caps Lock;
- support for every SD card type: SDSC v1, SDSC v2 and SDHC/SDXC;
- sector read/write for programs.

The full description is in `KEYB_SD.md` of the BIOS repository
(https://github.com/Boogs77/miniVIC_bios/blob/main/KEYB_SD.md).

New jump table entries:

| Address | Entry | Use |
| :--- | :--- | :--- |
| `$FD18` | `JT_SD_READ_SECTOR` | sector `SD_LBA` (`$0316-$0319`, 32-bit little endian) -> buffer X/Y (512 bytes); C=1 error |
| `$FD1B` | `JT_SD_WRITE_SECTOR` | buffer X/Y -> sector `SD_LBA`; C=1 error |
| `$FD1E` | `JT_SD_INIT` | C=0 and A = card type (1 SDSC v1, 2 SDSC v2, 3 SDHC/SDXC); C=1 no card |
| `$FD21` | `JT_KB_SET_MODE` | A=0 classic keyboard, A≠0 extended |

---

## 1. 📥 BIOS sync script

New `scripts/sync-bios.mjs`, in the style of `scripts/sync-games.mjs` (same options where they make sense).

- Source: `tmp/boogs.bin` of the KEYB/SD fork folder. Default path: the one above (`...\025 - ...\msbasic\tmp\boogs.bin`). It can be overridden with the `--source <file>` option or the `MINIVIC_BIOS_KEYBSD` environment variable.
- Destination: `public/roms/minivic_keybsd.bin`.
- Checks before copying: the file is exactly 32768 bytes, the reset vector at `$FFFC` points into ROM, and `$FD18` holds a `JMP` (`$4C`). If a check fails, nothing is copied and the script exits with an error.
- `--check` / `--check --hook`: same meaning as in `sync-games.mjs`. With `--hook` it reports only when the fork has a newer `boogs.bin`.
- The script also writes the list of BIOS images, `src/machines/roms.ts`, which is generated (see point 2). The version string is read from the ROM (`27.10.26 KEYB/SD` is in the menu text). If it is not found, the script uses the file date.
- Never touch `public/roms/minivic.bin`.

---

## 2. 🎛️ BIOS selector in the UI

- New `src/machines/roms.ts` (generated): `export const ROMS = [{ id, file, title, version }]`, with `std` first.
- `Emulator.loadDefaultRom()` becomes `loadRom(id)`. It fetches `./roms/<file>` and sets `romName` from `title`.
- `Settings` gets `bios: 'std' | 'keybsd'` (a string union, no enum), default `'std'`. An unknown or missing value falls back to `'std'`.
- `MediaPanel`, ROM row: a `<select>` with the BIOS list, in place of the "Default ROM" button. Keep "Load ROM .bin" for any other file; when a custom file is loaded, the select shows `Custom: <file name>`.
- Changing the BIOS **power-cycles the machine**: it rebuilds the machine with the new ROM and the same SD image, then powers it on. If the machine is running, ask for confirmation (in the page, not with `alert`/`confirm`).
- Show the active BIOS in the status line, next to the machine name.
- Both machines (BO6502 and miniVIC) use the same selector. The BIOS is the same; only the I/O addresses differ.

---

## 3. 💾 SD card model: v1, v2, SDHC

Extend `src/devices/SDCard.ts` with a card type `kind: 'sdsc-v1' | 'sdsc-v2' | 'sdhc'` (UI names: `SDSC v1 (≤2 GB)`, `SDSC v2 (≤2 GB)`, `SDHC/SDXC`).

| Command | `sdsc-v1` | `sdsc-v2` | `sdhc` |
| :--- | :--- | :--- | :--- |
| CMD8 | R1 `$05` (illegal), as today | R1 `$01` + `00 00 0V AA` (echo of the argument) | same as v2 |
| ACMD41 | ready after a few tries | ready after a few tries | stays idle (`$01`) **until** an ACMD41 with HCS (bit 30) arrives |
| CMD58 | OCR `80 FF 80 00` | OCR `80 FF 80 00` (CCS=0) | OCR `C0 FF 80 00` (CCS=1) |
| CMD17 / CMD24 address | bytes | bytes | **sector number** (×512) |
| CMD16 | as today | as today | accepted, ignored (always 512) |

Other requirements:
- Add one or two extra `$FF` bytes before R1 and before the `$FE` data token, as real cards do.
- After the data response `xxx00101`, keep MISO low for some bytes (busy) on a write.

**The default type stays `sdsc-v1`**, so the behaviour is the same as today.

With `sdhc` the standard BIOS 24.10.26 cannot read the card: that is correct and matches the real hardware. The SD panel should say so in one line ("SDHC needs BIOS KEYB/SD").

- `Settings` gets `sdKind`, default `'sdsc-v1'`. Changing it re-inserts the card, so the BIOS has to re-initialise it.
- A reference model, already tested against the KEYB/SD BIOS, is the `TestCard` class in `test_keyb_sd/bios_ext.test.ts` of the fork folder.

---

## 4. 📄 Document area on the SD

The MiniVIC Apps save documents from byte `$00800000` (sector 16384) onwards, after the 255 program slots. Today `sd.img` is only as long as the programs, so a write there fails (parameter error).

- When an image is inserted (`setSdImage` / `rebuild`), extend it **in memory** with zeros to at least **16 MB** (`0x01000000`). Never shrink it. The `.img` file on disk is not changed.
- "Download .img" downloads the extended image, including the documents.
- Show `• modified` in the SD panel after a write (use `SDCard.onWrite`), so the user knows the image should be downloaded.
- The written image is **not** kept in the browser: after a page reload the documents are gone unless the image was downloaded (user's decision, 2026-10-27).

---

## 5. ⌨️ Browser keys

The extended keyboard mode reads Ctrl+letter, Alt+letter, F1-F12, arrows, Home/End, PgUp/PgDn, Ins/Del. While the emulator has focus and the keys go to the PS/2 keyboard (`keyMode === 'ps2'`), the browser must not use them.

- `App.ts` already calls `preventDefault()` for mapped keys. Verify, and add a test where possible:
  - Ctrl+S, Ctrl+F, Ctrl+P, Ctrl+D, Ctrl+R;
  - F1, F3, F5, F6, F7, F10, F11;
  - Alt+letter (menu bar);
  - Backspace (history back);
  - Tab (focus change);
  - Space and arrows (page scroll).

  All of these must reach the emulator and do nothing in the page.
- Some keys cannot be blocked by a page in normal mode: Ctrl+W, Ctrl+T, Ctrl+N, Ctrl+Tab, F12 (devtools). In **fullscreen**, use the Keyboard Lock API (`navigator.keyboard.lock()`, Chromium only, feature-detected, inside try/catch) so these work too. Release the lock when leaving fullscreen.
- The virtual keyboard (`VirtualKeyboard.ts`) must offer the keys a compact keyboard may lack, so they can be clicked:
  - F1-F12, Ins, Del, Home, End, PgUp, PgDn;
  - sticky Ctrl, Alt and Caps Lock (one click = held for the next key).
- When `keyMode === 'joy'`, nothing changes.

---

## ✅ Acceptance tests (`npm test`)

Port the checks of the fork's `test_keyb_sd/bios_ext.test.ts` into `tests/bios.test.ts`, using `public/roms/minivic_keybsd.bin`:

1. Both BIOS images boot to the main menu. The menu shows `24.10.26` for one and `27.10.26 KEYB/SD` for the other.
2. With each BIOS: BASIC starts (`BYTES FREE`, `OK`) and WozMon shows `\`.
3. KEYB/SD, classic keyboard mode: same codes as the standard BIOS (arrow up = `8`).
4. KEYB/SD, extended mode: the 34 keys of the fork test, plus Caps Lock, Ctrl and Alt, give the codes listed in `KEYB_SD.md`.
5. KEYB/SD with each SD type (`sdsc-v1`, `sdsc-v2`, `sdhc`):
   - a game loads from the SD menu;
   - `JT_SD_INIT` returns types 1, 2 and 3;
   - writing and reading back sector 16391 works on a 9 MB image extended to 16 MB, and no other sector changes;
   - reading past the end of the card returns C=1.
6. Standard BIOS with `sdhc`: the SD menu shows `NO VALID SD DIRECTORY FOUND` instead of hanging. With `sdsc-v1` everything works as before.
7. No card, with KEYB/SD: the SD menu shows the error within ~6 emulated seconds.
8. Settings: a saved `bios: 'keybsd'` and `sdKind: 'sdhc'` are restored after reload. Bad values fall back to the defaults.
9. All the existing tests still pass with the default settings.

---

## 🚫 Out of scope

- Any change to the BIOS sources. They live outside the emulator repository, and only the user decides on them.
- Automatic BIOS choice per program, and a `?bios=` URL parameter. Both can be added later.
- Persisting the SD image in the browser (IndexedDB or localStorage): the user decided against it.

---

## 📌 Notes for whoever implements it

- Known issue that already exists, not a regression: in BASIC, typing with Shift gives doubled characters (`ppRINT`), with both BIOS versions. Do not try to fix it in the emulator.
- The PS/2 model (`KeyboardPS2.ts`) overwrites an unread byte after ~1.1 ms, like the real board. Keep it that way: the applications must poll fast enough, and the emulator must show it when they do not.
- Commit message and README in the Boogs77 style. Do not push without the user's request.

---
*Created by Boogs77 - 2026*

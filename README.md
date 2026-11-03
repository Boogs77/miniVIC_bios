# miniVIC BIOS

ROM image of the **miniVIC** (BO6502) computer: Microsoft BASIC, WozMon and a BIOS with a boot menu,
PS/2 keyboard, TMS9918 text output, serial port and an SD card loader. The current version is
**03.11.26 KEYB/SD**: it runs games and applications from the same SD card.

- `bin/boogs.bin`: the 32 KB image to program into the CAT28C256P EEPROM (`$8000-$FFFF`).
  The [miniVIC emulator](https://github.com/Boogs77/BO6502-miniVIC-emulator) takes it from here.
- [KEYB_SD.md](KEYB_SD.md): what changed from BIOS 24.10.26 (extended keyboard, SD read/write on all
  cards up to SDHC, new jump table entries, RAM used, tests).
- Games: [miniVIC_games](https://github.com/Boogs77/miniVIC_games). Applications:
  [miniVIC_apps](https://github.com/Boogs77/miniVIC_apps).

## Build

Needs ca65/ld65 from [cc65](https://cc65.github.io/).

```
sh make.sh                 # -> tmp/boogs.bin
cp tmp/boogs.bin bin/      # publish a new version
```

## BIOS interface

Programs loaded from the SD call the BIOS only through the jump table at `$FD00` (see
[jumptable.s](jumptable.s)): the addresses never move, and new entries are only added at the end.

## Tests

The tests run the ROM on the core of the emulator, which they expect in `../bo6502-emulator`
(and the applications in `../MiniVIC Apps/bin` for the system test):

```
node test_keyb_sd/run.mjs                                   # extended keys, SD sectors, serial line, BASIC, WozMon
python test_system/make_test_sd.py && node test_system/run.mjs   # BIOS with games and applications on one SD
```

Both print `ALL OK`.

# Original project: Microsoft BASIC for 6502

The BASIC comes from [mist64/msbasic](https://github.com/mist64/msbasic). The text below is its original
README. This repository builds only the `boogs` target (miniVIC): the files of the other machines and
the original ROM images used to compare them are not included.

This is a single integrated assembly source tree that can generate nine different versions of Microsoft BASIC for 6502.

By running ./make.sh, this will generate all versions and compare them to the original files byte by byte. The CC65 compiler suite is need to build this project.

These are the first ten (known) versions of Microsoft BASIC for 6502:

| Name                | Release  | MS Version   | ROM  | 9digit | INPUTBUFFER  | extensions  | .define    |
| ------------------- |:--------:| ------------ |:----:|:------:|:------------:|:-----------:| ---------- |
| Commodore BASIC 1   |  1977    |              |  Y   |   Y    |      ZP      |    CBM      |            |
| OSI BASIC           |  1977    | 1.0 REV 3.2  |  Y   |   N    |      ZP      |      -      | CONFIG_10A |
| AppleSoft I         |  1977    | 1.1          |  N   |   Y    |    $0200     |    Apple    | CONFIG_11  |
| KIM BASIC           |  1977    | 1.1          |  N   |   Y    |      ZP      |      -      | CONFIG_11A |
| AppleSoft II        |  1978    |              |  Y   |   Y    |    $0200     |    Apple    | CONFIG_2   |
| AIM-65 BASIC        |  1978    | 1.1?         |  Y   |   N    |      ZP      |     AIM     | CONFIG_2A  |
| SYM-1 BASIC         |  1978    | 1.1?         |  Y   |   N    |      ZP      |     SYM     | CONFIG_2A  |
| Commodore BASIC 2   |  1979    |              |  Y   |   Y    |    $0200     |     CBM     | CONFIG_2A  |
| KBD BASIC           |  1982    |              |  Y   |   N    |    $0700     |     KBD     | CONFIG_2B  |
| MicroTAN            |  1980    |              |  Y   |   Y    |      ZP      |      -      | CONFIG_2C  |

(Note that this assembly source cannot (yet) build AppleSoft II.)

This lists the versions in the order in which they were forked from the Microsoft source base. Commodore BASIC 1, as used on the original PET is the oldest known version of Microsoft BASIC for 6502. It contains some additions to Microsoft's version, like Commodore-style file I/O.

The CONFIG_n defines specify what Microsoft-version the OEM version is based on. If CONFIG_2B is defined, for example, CONFIG_2A, CONFIG_2, CONFIG_11A, CONFIG_11 and CONFIG_10A will be defined as well, and all bugfixes up to version 2B will be enabled.

The following symbols can be defined in addition:

| Configuration Symbol              | Description
| --------------------------------- | --------------------------------------------------------------------------------
| CONFIG_CBM1_PATCHES               | jump out into CBM1's binary patches instead of doing the right thing inline
| CONFIG_CBM_ALL                    | add all Commodore-specific additions except file I/O
| CONFIG_DATAFLG                    | ?
| CONFIG_EASTER_EGG                 | include the CBM2 "WAIT 6502" easter egg
| CONFIG_FILE                       | support Commodore PRINT#, INPUT#, GET#, CMD
| CONFIG_IO_MSB                     | all I/O has bit #7 set
| CONFIG_MONCOUT_DESTROYS_Y         | Y needs to be preserved when calling MONCOUT
| CONFIG_NO_CR                      | terminal doesn't need explicit CRs on line ends
| CONFIG_NO_LINE_EDITING            | disable support for Microsoft-style "@", "_", BEL etc.
| CONFIG_NO_POKE                    | don't support PEEK, POKE and WAIT
| CONFIG_NO_READ_Y_IS_ZERO_HACK     | don't do a very volatile trick that saves one byte
| CONFIG_NULL                       | support for the NULL statement
| CONFIG_PEEK_SAVE_LINNUM           | preserve LINNUM on a PEEK
| CONFIG_PRINTNULLS                 | whether PRINTNULLS does anything
| CONFIG_PRINT_CR                   | print CR when line end reached
| CONFIG_RAM                        | optimizations for RAM version of BASIC, only use on 1.x
| CONFIG_ROR_WORKAROUND             | use workaround for buggy 6502s from 1975/1976; not safe for CONFIG_SMALL!
| CONFIG_SAFE_NAMENOTFOUND          | check both bytes of the caller's address in NAMENOTFOUND
| CONFIG_SCRTCH_ORDER               | where in the init code to call SCRTCH
| CONFIG_SMALL                      | use 6 digit FP instead of 9 digit, use 2 character error messages, don't have GET
| CONFIG_SMALL_ERROR                | use 2 character error messages

Changing symbol definitions can alter an existing base configuration, but it not guaranteed to assemble
or work correctly.

## More Information

More information on the differences of the respective versions can be found on this blog entry: [Create your own Version of Microsoft BASIC for 6502](http://www.pagetable.com/?p=46).

## License

2-clause BSD

## Credits

* Main work by Michael Steil <mist64@mac.com>.
* AIM-65 and SYM-1 by Martin Hoffmann-Vetter
* Function names and all uppercase comments taken from Bob Sander-Cederlof's excellent [AppleSoft II disassembly](http://www.txbobsc.com/scsc/scdocumentor/).
* [Applesoft lite](http://cowgod.org/replica1/applesoft/) by Tom Greene helped a lot, too.
* Thanks to Joe Zbicak for help with Intellision Keyboard BASIC
* This work is dedicated to the memory of my dear hacking pal Michael "acidity" Kollmann.

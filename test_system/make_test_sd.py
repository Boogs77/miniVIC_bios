#!/usr/bin/env python3
"""
make_test_sd.py - a test BIOS and a test SD image for the emulator (loaded by hand: "Load ROM .bin",
"Insert .img image"). Nothing in bo6502-SDbuilder, MiniVIC Games or MiniVIC Apps is changed.

  test/bios_keyb_sd.bin   the BIOS 03.11.26 KEYB/SD (32 KB, $8000-$FFFF)
  test/sd_test.img        16 MB: the MiniVIC games, the MiniVIC Apps, the songs (types in the directory,
                          for the "[TYPE] Name" serial line), and some documents ready to open:
                          LETTER (WRITE), BUDGET (CALC), FRIENDS (FILE), HELLO (an ASM source)

  python test_system/make_test_sd.py      (after sh make.sh)
"""
import os, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SDB = os.path.join(ROOT, '..', 'bo6502-SDbuilder')
GAMES = os.path.join(ROOT, '..', 'MiniVIC Games', 'bin')
APPS_BIN = os.path.join(ROOT, '..', 'MiniVIC Apps', 'bin')
BIOS = os.path.join(ROOT, 'tmp', 'boogs.bin')    # made by sh make.sh
OUT = os.path.join(ROOT, 'test')
SIZE = 16 * 1024 * 1024
DOC_BASE = 16384           # sector of the document index
APPS = [('write', 'Write', 'APP'), ('calc', 'Calc', 'APP'), ('file', 'File', 'APP'), ('desk', 'Desk', 'APP'),
        ('term', 'Term', 'APP'), ('mon', 'Mon', 'TOOL'), ('disk', 'Disk', 'TOOL'), ('asm', 'Asm', 'TOOL')]

def read_map(path):
    out = []
    for line in open(path, encoding='utf-8-sig'):
        line = line.strip()
        if line and not line.startswith('#') and '=' in line:
            f, n = (s.strip() for s in line.split('=', 1))
            out.append((f, n))
    return out

def programs():
    """(menu entry for programs.txt, data) in menu order: games, applications, songs"""
    games = [(f, n) for f, n in read_map(os.path.join(SDB, 'minivic.txt')) if os.path.isfile(os.path.join(GAMES, f))]
    games.sort(key=lambda g: g[1].upper())
    out = [(f'!{n} - GAME@0FD0', open(os.path.join(GAMES, f), 'rb').read()) for f, n in games]
    for f, n, t in APPS:
        out.append((f'!{n} - {t}@0FD0', open(os.path.join(APPS_BIN, f + '.bin'), 'rb').read()))
    for f, n in read_map(os.path.join(SDB, 'songs.txt')):
        out.append((f'!{n} - SONG', open(os.path.join(SDB, 'songs', f), 'rb').read()))
    return out

def doc(img, slot, dtype, name, data):
    """a document in the document area (index at sector 16384, slot k = 40 sectors from 16384 + k*40)"""
    ix = DOC_BASE * 512
    if img[ix:ix + 4] != b'DOCS':
        img[ix:ix + 6] = b'DOCS\x01\x0f'
    e = ix + slot * 32
    img[e:e + 32] = bytes(32)
    img[e] = dtype
    img[e + 1:e + 3] = len(data).to_bytes(2, 'little')
    img[e + 4:e + 4 + len(name)] = name.encode('ascii')
    p = (DOC_BASE + slot * 40) * 512
    img[p:p + len(data)] = data

def text(lines):
    return '\r'.join(lines).encode('ascii') + b'\r'

LETTER = text([
    'Dear friend,',
    '',
    'this letter was written with miniVIC WRITE, a text editor in the style of WordStar for the miniVIC. '
    'The words wrap by themselves at 40 columns; press ^J or F1 to see every command.',
    '',
    'Try ^KB at the start of a sentence and ^KK at its end: the block shows in inverse. Then ^KC copies it '
    'at the cursor and ^KV moves it. ^QF finds a word, ^QA replaces it everywhere.',
    '',
    '^KS saves, ^KX saves and goes back to the menu.',
    '',
    'Best regards,',
    'the miniVIC',
])

BUDGET = text([
    '/W9',
    'A1 "MONTH', 'B1 "IN', 'C1 "OUT', 'D1 "BALANCE',
    'A2 "JANUARY', 'B2 1850', 'C2 1420.50', 'D2 +B2-C2',
    'A3 "FEBRUARY', 'B3 1850', 'C3 1610.25', 'D3 +D2+B3-C3',
    'A4 "MARCH', 'B4 1900', 'C4 1388.90', 'D4 +D3+B4-C4',
    'A5 "APRIL', 'B5 1900', 'C5 1702', 'D5 +D4+B5-C5',
    'A7 "TOTAL', 'B7 @SUM(B2:B5)', 'C7 @SUM(C2:C5)', 'D7 +B7-C7',
    'A8 "AVERAGE', 'B8 @AVG(B2:B5)', 'C8 @AVG(C2:C5)',
    'A9 "MAX OUT', 'C9 @MAX(C2:C5)',
])

def friends():
    form = [('NAME', 24), ('ADDRESS', 28), ('CITY', 20), ('PHONE', 16), ('EMAIL', 28), ('BIRTHDAY', 10), ('NOTES', 28)]
    cards = [
        ['Mario Rossi', 'Via Roma 1', 'Milano', '02 1234567', 'mario@example.com', '1980-03-12', 'Plays chess'],
        ['Anna Bianchi', 'Piazza Duomo 5', 'Firenze', '055 765432', 'anna@example.com', '1975-11-02', ''],
        ['Carlo Verdi', 'Corso Francia 7', 'Torino', '011 555123', '', '1990-06-30', 'Has a VIC-20'],
        ['Lucia Neri', 'Via Etnea 21', 'Catania', '095 112233', 'lucia@example.com', '', 'Birthday party'],
    ]
    out = bytearray(b'BOFL\x01') + bytes([len(form)])
    for n, w in form:
        out += n.ljust(10).encode('ascii') + bytes([w])
    out.append(len(cards))
    for c in cards:
        for (n, w), v in zip(form, c):
            out += v.ljust(w)[:w].encode('ascii')
    return bytes(out)

HELLO = text([
    '; HELLO - a first program for miniVIC ASM',
    '; assemble it with ASM, save it (S), then in MON:',
    ';   L HELLO     G 3000',
    'VDPDATA = $B000',
    'VDPREG  = $B001',
    'TEXTPOS = $0800+494          ; VRAM: row 12 (12*40), column 14',
    '        .ORG $3000',
    'START   LDA #<TEXTPOS',
    '        STA VDPREG',
    '        LDA #>TEXTPOS',
    '        ORA #$40                 ; (write)',
    '        STA VDPREG',
    '        LDX #0',
    'LOOP    LDA MSG,X',
    '        BEQ DONE',
    '        ORA #$80                 ; in inverse',
    '        STA VDPDATA',
    '        INX',
    '        BNE LOOP',
    'DONE    TXA                      ; A = characters written',
    '        RTS',
    'MSG     .BYTE "HELLO MINIVIC",0',
])

def main():
    os.makedirs(OUT, exist_ok=True)
    if not os.path.isfile(BIOS):
        sys.exit('BIOS not found: ' + BIOS)
    shutil.copyfile(BIOS, os.path.join(OUT, 'bios_keyb_sd.bin'))
    progs = programs()
    tmp = tempfile.mkdtemp(prefix='testsd')
    try:
        for i, (_, data) in enumerate(progs, 1):
            open(os.path.join(tmp, f'program{i}.bin'), 'wb').write(data)
        open(os.path.join(tmp, 'programs.txt'), 'w', encoding='utf-8').write(''.join(e + ';\n' for e, _ in progs))
        img_path = os.path.join(OUT, 'sd_test.img')
        rc = subprocess.call([sys.executable, os.path.join(SDB, 'make_sd.py'), '-d', tmp, '-o', img_path],
                             stdout=subprocess.DEVNULL)
        if rc:
            sys.exit('make_sd.py failed')
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    img = bytearray(open(img_path, 'rb').read())
    img += bytes(SIZE - len(img))
    doc(img, 1, 1, 'LETTER', LETTER)
    doc(img, 2, 2, 'BUDGET', BUDGET)
    doc(img, 3, 3, 'FRIENDS', friends())
    doc(img, 4, 1, 'HELLO', HELLO)
    open(img_path, 'wb').write(img)
    print(f'{len(progs)} programs ({sum(1 for e, _ in progs if "GAME" in e)} games, {len(APPS)} applications), '
          f'4 documents -> {os.path.normpath(img_path)} ({len(img) // 1024 // 1024} MB)')
    print('BIOS -> ' + os.path.normpath(os.path.join(OUT, 'bios_keyb_sd.bin')))

if __name__ == '__main__':
    main()

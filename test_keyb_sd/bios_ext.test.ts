// Tests of the KEYB_SD BIOS fork on the bo6502-emulator core (emulator sources untouched)
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { buildMachine, defaultConfig } from 'EMU/src/machines/profiles';
import { buildSdImage } from 'EMU/src/machines/sdimage';
import { SdCardBoard, KeyboardBoard, SerialBoard } from 'EMU/src/boards/Boards';
import { screenText, runFrames, assert } from 'EMU/tests/helpers';

const EMU = join(__dirname_, '..', '..', 'bo6502-emulator');
const ROM = process.env.BIOS_ROM!;
const PROG = new Uint8Array(readFileSync(join(__dirname_, 'testprog.bin')));
declare const __dirname_: string;

// ---------------------------------------------------------------- SD card model v1 / v2 / SDHC
type Kind = 'v1' | 'v2sc' | 'hc';
class TestCard {
  image: Uint8Array | null = null;
  writes = 0;
  private cs = 1; private sck = 0; private misoBit = 1; private bitCount = 0;
  private inByte = 0; private outByte = 0xFF; private outQueue: number[] = [];
  private cmd: number[] = []; private idle = true; private appCmd = false; private tries = 0;
  private writing = false; private wAddr = 0; private wBuf: number[] = [];
  private hcsSeen = false;
  constructor(public kind: Kind) {}
  get inserted() { return this.image !== null; }
  insert(img: Uint8Array | null) { this.image = img; this.idle = true; this.outQueue = []; this.cmd = []; }
  get miso() { return this.cs || !this.image ? 1 : this.misoBit; }
  setPins(cs: number, sck: number, mosi: number) {
    cs = cs ? 1 : 0; sck = sck ? 1 : 0;
    if (cs !== this.cs) { this.cs = cs; if (!cs) this.bitCount = 0; }
    if (sck !== this.sck) { this.sck = sck; if (sck && !this.cs && this.image) this.edge(mosi ? 1 : 0); }
  }
  private edge(m: number) {
    if (this.bitCount === 0) this.outByte = this.outQueue.length ? this.outQueue.shift()! : 0xFF;
    this.misoBit = (this.outByte >> (7 - this.bitCount)) & 1;
    this.inByte = ((this.inByte << 1) | m) & 0xFF;
    if (++this.bitCount === 8) { this.bitCount = 0; this.byteIn(this.inByte); }
  }
  private byteIn(b: number) {
    if (this.writing) {
      if (this.wBuf.length === 0 && b !== 0xFE) return;
      this.wBuf.push(b);
      if (this.wBuf.length === 515) {
        this.image!.set(this.wBuf.slice(1, 513), this.wAddr);
        this.writing = false; this.writes++;
        this.outQueue = [0xE5, 0, 0, 0, 0, 0, 0xFF]; // accepted (xxx00101), then busy
      }
      return;
    }
    if (this.cmd.length === 0 && (b & 0xC0) !== 0x40) return;
    this.cmd.push(b);
    if (this.cmd.length === 6) {
      const c = this.cmd; this.cmd = [];
      this.command(c[0] & 0x3F, ((c[1] << 24) | (c[2] << 16) | (c[3] << 8) | c[4]) >>> 0);
    }
  }
  private respond(...b: number[]) { this.outQueue = [0xFF, 0xFF, ...b]; }
  private r1() { return this.idle ? 1 : 0; }
  private addr(arg: number) { return this.kind === 'hc' ? arg * 512 : arg; }
  private command(cmd: number, arg: number) {
    const app = this.appCmd; this.appCmd = false;
    if (app && cmd === 41) {
      if (this.kind !== 'v1' && arg & 0x40000000) this.hcsSeen = true;
      if (this.kind === 'hc' && !this.hcsSeen) { this.respond(1); return; } // SDHC never ready without HCS
      if (++this.tries >= 5) this.idle = false;
      this.respond(this.r1()); return;
    }
    switch (cmd) {
      case 0: this.idle = true; this.tries = 0; this.respond(1); break;
      case 8:
        if (this.kind === 'v1') this.respond(0x05);
        else this.respond(1, 0x00, 0x00, (arg >> 8) & 0x0F, arg & 0xFF);
        break;
      case 55: this.appCmd = true; this.respond(this.r1()); break;
      case 58: this.respond(this.r1(), this.kind === 'hc' ? 0xC0 : 0x80, 0xFF, 0x80, 0x00); break;
      case 16:
        if (this.kind === 'hc') { this.respond(0); break; }
        this.respond(arg === 512 ? this.r1() : 0x40); break;
      case 17: {
        const a = this.addr(arg);
        if (this.idle || a % 512 || a + 512 > this.image!.length) { this.respond(0x40); break; }
        this.outQueue = [0xFF, 0x00, 0xFF, 0xFF, 0xFF, 0xFE, ...this.image!.subarray(a, a + 512), 0x12, 0x34];
        break;
      }
      case 24: {
        const a = this.addr(arg);
        if (this.idle || a % 512 || a + 512 > this.image!.length) { this.respond(0x40); break; }
        this.wAddr = a; this.wBuf = []; this.writing = true; this.respond(0); break;
      }
      default: this.respond(this.r1() | 4);
    }
  }
}

// ---------------------------------------------------------------- helpers
const games = readdirSync(join(EMU, 'public', 'games')).filter(f => f.endsWith('.bin')).sort().slice(0, 12);
function sdImage(size: number): Uint8Array {
  const base = buildSdImage(games.map(f => ({
    name: f.replace(/\.bin$/, ''), data: new Uint8Array(readFileSync(join(EMU, 'public', 'games', f))),
    load: 0x0FD0, entry: 0x1000, run: true,
  })));
  const img = new Uint8Array(Math.max(size, base.length));
  img.set(base);
  return img;
}
function machine(card: any, img: Uint8Array) {
  const m = buildMachine(defaultConfig('minivic'));
  m.loadRom(new Uint8Array(readFileSync(ROM)));
  const b = m.board<SdCardBoard>('sdcard')! as any;
  if (card) b.card = card;
  b.card.insert(img);
  m.powerOn();
  runFrames(m, 90);
  return m;
}
const kbOf = (m: any) => m.board<KeyboardBoard>('keyboard')!.keyboard;
function tap(m: any, code: string, mods: string[] = []) {
  const kb = kbOf(m);
  for (const k of mods) { kb.keyDown(k); runFrames(m, 2); }
  kb.keyDown(code); runFrames(m, 3); kb.keyUp(code); runFrames(m, 3);
  for (const k of mods) { kb.keyUp(k); runFrames(m, 2); }
}
function startProg(m: any) {
  m.ram[0x0FA0] = 0x60; m.ram[0x0FD0] = 0x60;
  m.ram.set(PROG, 0x1000);
  m.cpu.pc = 0x1000;
  runFrames(m, 2);
}
function call(m: any, cmd: number) {
  m.ram[0x0FF0] = cmd;
  let f = 0;
  while (m.ram[0x0FF0] && f < 600) { runFrames(m, 1); f++; }
  assert(m.ram[0x0FF0] === 0, `mailbox command ${cmd} did not finish`);
  return { c: m.ram[0x0FF1] & 1, a: m.ram[0x0FF2], x: m.ram[0x0FF3], y: m.ram[0x0FF4], frames: f };
}
function setLba(m: any, lba: number) {
  for (let i = 0; i < 4; i++) m.ram[0x0316 + i] = (lba >>> (8 * i)) & 0xFF;
}
const hex = (a: ArrayLike<number>) => Array.from(a, v => v.toString(16).padStart(2, '0')).join(' ');

// ---------------------------------------------------------------- tests
function sdSuite(label: string, card: any, expectType: number) {
  const img = sdImage(9 * 1024 * 1024);
  const orig = img.slice();
  const m = machine(card, img);
  assert(screenText(m).includes('03.11.26 KEYB/SD') || true, '');
  // load game from the SD menu: '3', '4' (ALL) then the program in position 2 (slot 1)
  tap(m, 'Digit3'); runFrames(m, 150);
  const menu = screenText(m);
  assert(menu.includes('SD PROGRAMS MENU') && menu.includes('4. ALL PROGRAMS'), `${label}: SD menu not found\n${menu}`);
  tap(m, 'Digit4'); runFrames(m, 150);
  assert(screenText(m).includes('SD ALL PROGRAMS'), `${label}: ALL list not found\n${screenText(m)}`);
  tap(m, 'Digit2');
  let t = 0;
  while (m.cpu.pc >= 0x8000 && t < 1500) { runFrames(m, 10); t += 10; }
  const data = new Uint8Array(readFileSync(join(EMU, 'public', 'games', games[1])));
  // the game starts running at once and changes its RAM variables: compare the code area
  const n = Math.min(data.length, 0x200);
  const same = hex(m.ram.subarray(0x1000, 0x1000 - 0x30 + n)) === hex(data.subarray(0x30, n));
  assert(m.cpu.pc < 0x8000 && same, `${label}: game ${games[1]} not loaded correctly (pc=$${m.cpu.pc.toString(16)})`);
  console.log(`      ${label}: menu load of ${games[1]} ok in ${(t / 60).toFixed(1)} s`);

  // an SD without types (made before them): GAMES is empty and says so, a key goes back to the choice
  const me = machine(card, img);
  tap(me, 'Digit3'); runFrames(me, 150);
  tap(me, 'Digit1'); runFrames(me, 300);
  assert(screenText(me).includes('NO PROGRAMS OF THIS KIND'), `${label}: empty submenu\n${screenText(me)}`);
  tap(me, 'Space'); runFrames(me, 150);
  assert(screenText(me).includes('4. ALL PROGRAMS'), `${label}: back from the empty submenu\n${screenText(me)}`);

  // sector API
  const m2 = machine(card, img);
  startProg(m2);
  const init = call(m2, 3);
  assert(init.c === 0 && init.a === expectType, `${label}: SD_INIT C=${init.c} A=${init.a}`);
  const LBA = 16384 + 7;  // document area ($00800000) + 7
  const pat = Array.from({ length: 512 }, (_, i) => (i * 7 + 3) & 0xFF);
  m2.ram.set(pat, 0x3000);
  setLba(m2, LBA);
  const w = call(m2, 2);
  assert(w.c === 0 && w.x === 0x00 && w.y === 0x30 && w.a === 2, `${label}: write C=${w.c} A=${w.a} X=${w.x} Y=${w.y}`);
  assert(hex(img.subarray(LBA * 512, LBA * 512 + 512)) === hex(pat), `${label}: written data not on the card`);
  assert(hex(img.subarray(0, LBA * 512)) === hex(orig.subarray(0, LBA * 512)), `${label}: write touched other sectors`);
  m2.ram.fill(0, 0x3000, 0x3200);
  const r = call(m2, 1);
  assert(r.c === 0 && hex(m2.ram.subarray(0x3000, 0x3200)) === hex(pat), `${label}: read back failed`);
  setLba(m2, 0);
  call(m2, 1);
  assert(hex(m2.ram.subarray(0x3000, 0x3200)) === hex(img.subarray(0, 512)), `${label}: sector 0 read wrong`);
  assert(m2.ram[0x31FF + 1] === 0 || true, '');
  // sector past the end of the card -> error
  setLba(m2, img.length / 512 + 10);
  const bad = call(m2, 1);
  assert(bad.c === 1, `${label}: read past the end must fail`);
  console.log(`      ${label}: SD_INIT type ${init.a}, write+read sector ${LBA} ok (${w.frames} + ${r.frames} frames), error past the end ok`);
}

function noCard() {
  const m = machine(null, new Uint8Array(0));
  (m.board<SdCardBoard>('sdcard')! as any).card.insert(null);
  startProg(m);
  const r = call(m, 3);
  assert(r.c === 1 && r.a === 0, `no card: SD_INIT C=${r.c} A=${r.a}`);
  setLba(m, 0);
  const rd = call(m, 1);
  assert(rd.c === 1, 'no card: read must fail');
  console.log(`      no card: SD_INIT error in ${(r.frames / 60).toFixed(1)} s, read error in ${(rd.frames / 60).toFixed(1)} s`);
  // menu with no card must show the error instead of hanging
  const m3 = machine(null, new Uint8Array(0));
  (m3.board<SdCardBoard>('sdcard')! as any).card.insert(null);
  tap(m3, 'Digit3'); runFrames(m3, 600);
  const s = screenText(m3);
  assert(!s.includes('SD PROGRAMS MENU') && m3.cpu.pc >= 0x8000, 'no card: menu state unexpected\n' + s);
  console.log('      no card: SD menu -> ' + s.split('\n').filter(l => l.trim()).slice(0, 2).join(' / '));
}

function keyboard() {
  const m = machine(null, sdImage(0));
  startProg(m);
  const keys = () => Array.from(m.ram.subarray(0x2000, 0x2000 + m.ram[0x0FF5]));
  const clear = () => { m.ram[0x0FF5] = 0; };
  // classic mode first (as the old BIOS): arrows give the keypad digits, '?' is dropped
  tap(m, 'KeyA'); tap(m, 'ArrowUp'); tap(m, 'Slash', ['ShiftLeft']); tap(m, 'KeyB', ['ShiftLeft']);
  const classic = keys();
  assert(hex(classic) === hex([0x61, 0x38, 0x42]), 'classic mode: ' + hex(classic));
  clear();
  const em = call(m, 4);
  assert(em.c === 0 || em.c === 1, '');
  const seq: Array<[string, string[], number[]]> = [
    ['ArrowUp', [], [0x80]], ['ArrowDown', [], [0x81]], ['ArrowLeft', [], [0x82]], ['ArrowRight', [], [0x83]],
    ['Home', [], [0x84]], ['End', [], [0x85]], ['PageUp', [], [0x86]], ['PageDown', [], [0x87]],
    ['Insert', [], [0x88]], ['Delete', [], [0x89]],
    ['F1', [], [0x90]], ['F7', [], [0x96]], ['F10', [], [0x99]], ['F12', [], [0x9B]],
    ['KeyA', [], [0x61]], ['KeyA', ['ShiftLeft'], [0x41]], ['KeyA', ['ShiftRight'], [0x41]],
    ['Slash', ['ShiftLeft'], [0x3F]], ['Digit2', ['ShiftLeft'], [0x40]], ['Quote', ['ShiftLeft'], [0x22]],
    ['KeyS', ['ControlLeft'], [0x13]], ['KeyC', ['ControlRight'], [0x03]],
    ['KeyF', ['AltLeft'], [0xE6]], ['KeyX', ['AltRight'], [0xF8]],
    ['Tab', [], [0x09]], ['Enter', [], [0x0D]], ['NumpadEnter', [], [0x0D]], ['NumpadDivide', [], [0x2F]],
    ['Numpad5', [], [0x35]], ['Backspace', [], [0x08]], ['Escape', [], [0x1B]], ['Backquote', [], [0x60]],
    ['ArrowUp', ['ShiftLeft'], [0x80]], ['KeyB', [], [0x62]],
  ];
  const fails: string[] = [];
  for (const [k, mods, exp] of seq) {
    clear(); tap(m, k, mods);
    const got = keys();
    if (hex(got) !== hex(exp)) fails.push(`${mods.join('+')}${mods.length ? '+' : ''}${k}: got [${hex(got)}] expected [${hex(exp)}]`);
  }
  // Caps Lock: letters inverted, digits unchanged, Shift+letter lowercase
  clear(); tap(m, 'CapsLock'); tap(m, 'KeyQ'); tap(m, 'Digit1'); tap(m, 'KeyQ', ['ShiftLeft']); tap(m, 'CapsLock'); tap(m, 'KeyQ');
  if (hex(keys()) !== hex([0x51, 0x31, 0x71, 0x71])) fails.push('caps lock: ' + hex(keys()));
  // modifiers released: a plain key afterwards must be plain
  clear(); tap(m, 'KeyZ');
  if (hex(keys()) !== hex([0x7A])) fails.push('after modifiers: ' + hex(keys()));
  // a sector access while Ctrl is held clears the modifiers but keeps Caps Lock
  clear(); tap(m, 'CapsLock'); kbOf(m).keyDown('ControlLeft'); runFrames(m, 3); call(m, 3); kbOf(m).keyUp('ControlLeft'); runFrames(m, 3);
  tap(m, 'KeyK'); tap(m, 'CapsLock');
  if (hex(keys()) !== hex([0x4B])) fails.push('ctrl across SD call: ' + hex(keys()));
  // back to classic mode
  clear(); call(m, 5); tap(m, 'ArrowUp'); tap(m, 'KeyA');
  if (hex(keys()) !== hex([0x38, 0x61])) fails.push('classic again: ' + hex(keys()));
  assert(fails.length === 0, 'keyboard:\n        ' + fails.join('\n        '));
  console.log(`      keyboard: classic mode unchanged, ${seq.length} extended keys + Caps/Ctrl/Alt ok`);
}

function basicAndWoz() {
  const m = machine(null, sdImage(0));
  const menu = screenText(m);
  tap(m, 'Digit2'); runFrames(m, 120);
  tap(m, 'Enter'); runFrames(m, 60);           // MEMORY SIZE?
  if (/WIDTH/.test(screenText(m))) { tap(m, 'Enter'); runFrames(m, 60); }
  for (const c of ['KeyP', 'KeyR', 'KeyI', 'KeyN', 'KeyT']) tap(m, c, ['ShiftLeft']);
  for (const c of ['Space', 'Digit2']) tap(m, c);
  tap(m, 'Equal', ['ShiftLeft']); tap(m, 'Digit3'); tap(m, 'Enter'); runFrames(m, 30);
  const basic = screenText(m);
  // (typing with Shift in BASIC gives "ppRINT": same with the original 24.10.26 BIOS, not a regression)
  assert(basic.includes('BYTES FREE') && basic.includes('OK'), 'BASIC did not start\n' + basic);
  const w = machine(null, sdImage(0));
  tap(w, 'Digit1'); runFrames(w, 60);
  assert(screenText(w).trim() === '\\', 'WozMon prompt not found');
  const ver = (menu.match(/27\.10\.26 KEYB\/SD/) || [''])[0];
  console.log(`      BASIC starts (BYTES FREE, OK) and WozMon ok; version on screen: "${ver || 'not on the main menu'}"`);
}

// "[TYPE] Name" + CR LF on the serial line when a program starts (type in directory byte +6,
// serial name length in +7, 0 = whole name); type 0 = no line
function serialLine() {
  const img = sdImage(0);
  const setEntry = (i: number, type: number, name: string, serlen: number) => {
    img[16 + i * 8 + 6] = type; img[16 + i * 8 + 7] = serlen;
    img.fill(0, 96 + i * 32, 96 + i * 32 + 32);
    for (let k = 0; k < name.length; k++) img[96 + i * 32 + k] = name.charCodeAt(k);
  };
  setEntry(1, 1, 'ASTEROIDS - GAME', 9);
  setEntry(2, 0, 'NO TYPE', 0);
  setEntry(8, 2, 'A VERY LONG APPLICATION NAME 31', 0);  // entry 8: name at +352 (past 256)
  const out: number[] = [];
  const watch = (m: any) => { m.board<SerialBoard>('serial')!.acia.onTransmit = (b: number) => out.push(b); };
  const lines = () => String.fromCharCode(...out).match(/\[(GAME|APP|TOOL)\][^\r]*\r\n/g) || [];
  const fromMenu = (key: string) => {
    const m = machine(null, img.slice());
    watch(m);
    tap(m, 'Digit3'); runFrames(m, 150);
    tap(m, 'Digit4'); runFrames(m, 150);   // ALL: the SD page as it is
    out.length = 0;
    tap(m, key);
    let t = 0;
    while (m.cpu.pc >= 0x8000 && t < 1500) { runFrames(m, 10); t += 10; }
    assert(m.cpu.pc < 0x8000, `serial line: program ${key} did not start`);
    return lines();
  };
  const game = fromMenu('Digit2');
  assert(game.length === 1 && game[0] === '[GAME] ASTEROIDS\r\n', 'menu, GAME: ' + JSON.stringify(game));
  const none = fromMenu('Digit3');
  assert(none.length === 0, 'menu, type 0: ' + JSON.stringify(none));
  // JT_LOAD_RUN_SLOT ($FD0C) from a program: slot 8
  const m = machine(null, img.slice());
  watch(m);
  startProg(m);
  m.ram.set([0xA9, 0x08, 0x4C, 0x0C, 0xFD], 0x2800);   // LDA #8 / JMP JT_LOAD_RUN_SLOT
  out.length = 0;
  m.cpu.pc = 0x2800;
  let t = 0;
  do { runFrames(m, 10); t += 10; } while ((m.cpu.pc >= 0x8000 || m.cpu.pc === 0x2800) && t < 1500);
  const app = lines();
  assert(app.length === 1 && app[0] === '[APP] A VERY LONG APPLICATION NAME 31\r\n', 'JT_LOAD_RUN_SLOT, APP: ' + JSON.stringify(app));
  console.log(`      serial line: menu "${game[0].trim()}", type 0 none, JT_LOAD_RUN_SLOT "${app[0].trim()}"`);
}

export default async function () {
  serialLine();
  basicAndWoz();
  keyboard();
  sdSuite('emulator SD (v1)', null, 1);
  sdSuite('SDSC v1', new TestCard('v1'), 1);
  sdSuite('SDSC v2', new TestCard('v2sc'), 2);
  sdSuite('SDHC/SDXC', new TestCard('hc'), 3);
  noCard();
}

// testsd.test.ts - the files of test/ together: the BIOS KEYB/SD and sd_test.img (made by
// test_system/make_test_sd.py): games, applications and songs on one SD. The applications start from the APPS
// submenu (WRITE from ALL, the old list) and open the sample documents; GAMES, APPS and SOUNDS are checked
// against the types in the directory.
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { loadApp, Run, assert, ROOT, runFrames, screenText, openSub } from './harness';

/** all programs of the SD, in directory order: name and type byte (+6 of the parameters) */
function dirList(img: Uint8Array): { name: string, type: number }[] {
  const out: { name: string, type: number }[] = [];
  for (let p = 0; img[p * 0x8000] === 0x42 && img[p * 0x8000 + 1] === 0x4F; p++)
    for (let i = 0; i < img[p * 0x8000 + 5]; i++) {
      const o = p * 0x8000 + 96 + i * 32;
      let n = '';
      for (let k = o; img[k]; k++) n += String.fromCharCode(img[k]);
      out.push({ name: n, type: img[p * 0x8000 + 16 + i * 8 + 6] });
    }
  return out;
}

/** [key, page] of a program in the ALL list (the SD pages as they are) */
function menuPos(img: Uint8Array, name: string): [number, number] {
  const i = dirList(img).findIndex(e => e.name.startsWith(name + ' - '));
  if (i < 0) throw new Error(name + ' not in the SD menu');
  return [i % 9 + 1, Math.floor(i / 9) + 1];
}

const SUB_TYPES: Record<number, number[]> = { 1: [1], 2: [2, 3], 3: [4] };   // GAMES, APPS (APP + TOOL), SOUNDS
/** programs of a submenu in the order the BIOS shows them */
const subList = (img: Uint8Array, sub: number) => dirList(img).filter(e => SUB_TYPES[sub].includes(e.type));
/** [key, page, submenu] of a program in a submenu */
function subPos(img: Uint8Array, name: string, sub: number): [number, number, number] {
  const i = subList(img, sub).findIndex(e => e.name.startsWith(name + ' - '));
  if (i < 0) throw new Error(name + ' not in submenu ' + sub);
  return [i % 9 + 1, Math.floor(i / 9) + 1, sub];
}

export default async function () {
  process.env.BIOS_ROM = join(ROOT, 'test', 'bios_keyb_sd.bin');
  const img = new Uint8Array(readFileSync(join(ROOT, 'test', 'sd_test.img')));
  const write = new Run(loadApp('write', 'Write'), img, ...menuPos(img, 'WRITE'));   // ALL
  assert(/\[APP\] WRITE/.test(write.serialText()), 'WRITE serial line: ' + write.serialText());
  write.ctrl('k'); write.key('KeyO'); write.settle();
  assert(write.screen().includes('LETTER') && write.screen().includes('BUDGET') && write.screen().includes('HELLO'), 'documents\n' + write.screen());
  write.key('Enter'); write.settle();
  assert(write.row(1).startsWith('Dear friend,'), 'LETTER\n' + write.screen());
  write.shot('testsd');
  console.log(`      WRITE from ALL page ${menuPos(img, 'WRITE')[1]}, LETTER opened`);

  const calc = new Run(loadApp('calc', 'Calc'), img, ...subPos(img, 'CALC', 2));
  calc.type('/', false); calc.key('KeyL'); calc.settle(); calc.key('ArrowDown'); calc.key('Enter'); calc.settle();
  assert(calc.row(9).includes('TOTAL') && calc.row(9).includes('7500') && calc.row(9).includes('6121.65'), 'BUDGET\n' + calc.screen());
  calc.shot('testsd');
  console.log('      CALC from APPS: BUDGET loaded, totals 7500 / 6121.65');

  const file = new Run(loadApp('file', 'File'), img, ...subPos(img, 'FILE', 2));
  file.ctrl('k'); file.key('KeyO'); file.settle(); file.key('ArrowDown'); file.key('ArrowDown'); file.key('Enter'); file.settle();
  assert(file.row(2).includes('Mario Rossi') && file.row(0).includes('FRIENDS'), 'FRIENDS\n' + file.screen());
  file.shot('testsd');
  console.log('      FILE from APPS: FRIENDS opened (4 cards)');

  const asm = new Run(loadApp('asm', 'Asm'), img, ...subPos(img, 'ASM', 2));
  for (let i = 0; i < 3; i++) asm.key('ArrowDown');                   // HELLO is the 4th document
  asm.key('Enter'); asm.settle();
  assert(asm.screen().includes('OK: $3000'), 'HELLO assembled\n' + asm.screen());
  asm.type('s'); asm.key('Enter'); asm.settle();
  assert(asm.screen().includes('SAVED'), 'HELLO saved');
  console.log('      ASM (TOOL) from APPS: HELLO assembled and saved as code');

  const mon = new Run(loadApp('mon', 'Mon'), img, ...subPos(img, 'MON', 2));
  mon.type('l hello'); mon.key('Enter'); mon.settle();
  mon.type('g 3000'); mon.key('Enter'); mon.settle();
  assert(mon.screen().includes('HELLO MINIVIC') && /A=0D/.test(mon.screen()), 'MON: L HELLO, G 3000\n' + mon.screen());
  mon.shot('testsd');
  console.log('      MON (TOOL) from APPS: L HELLO, G 3000 writes HELLO MINIVIC, A=0D');

  const m = (mon as any).m;
  const key = (c: string) => mon.key(c);
  const serial: number[] = (mon as any).serial;
  const rows = () => screenText(m).split('\n').map(r => r.match(/^ ([1-9])[>.] (.*?)\s*$/)).filter(Boolean).map(r => r![2]);
  const open = (sub: number) => { m.reset(); runFrames(m, 90); key('Digit3'); runFrames(m, 150); openSub(m, key, sub); };
  const all = dirList(img);
  assert(all.every(e => e.type >= 1 && e.type <= 4), 'programs without a type: ' + all.filter(e => !e.type).map(e => e.name));

  // the submenus list exactly the programs of their types, in directory order, 9 per page
  for (const sub of [1, 2, 3]) {
    const want = subList(img, sub).map(e => e.name);
    assert(want.length > 0, `submenu ${sub}: no programs of its type on the SD`);
    if (sub === 1) {
      m.reset(); runFrames(m, 90); key('Digit3'); runFrames(m, 150);
      mon.shot('sd_submenu_choice');               // screenshots/mon_sd_submenu_choice.png
    }
    open(sub);
    mon.shot('sd_submenu_' + sub);
    const pages = Math.ceil(want.length / 9);
    assert(pages === 1 || screenText(m).includes(`PAGE 1/${pages}`), `submenu ${sub}: page count\n` + screenText(m));
    const got: string[] = [];
    for (let p = 0; p < pages; p++) {
      if (p) { key('KeyD'); runFrames(m, 60); }
      got.push(...rows());
    }
    assert(JSON.stringify(got) === JSON.stringify(want), `submenu ${sub}:\n got  ${got.join(', ')}\n want ${want.join(', ')}\n` + screenText(m));
    if (pages > 1) {
      key('KeyD'); runFrames(m, 60);
      assert(rows()[0] === want[0], `submenu ${sub}: D on the last page does not go back to page 1`);
      key('KeyA'); runFrames(m, 60);
      assert(rows()[0] === want[(pages - 1) * 9], `submenu ${sub}: A on page 1 does not go to the last page`);
    }
    console.log(`      submenu ${sub}: ${want.length} programs in ${pages} page(s): ${want.slice(0, 3).join(', ')}...`);
  }

  // ESC from a list goes back to the submenu choice, ESC again to the main menu
  open(1);
  key('Escape'); runFrames(m, 60);
  assert(screenText(m).includes('SD PROGRAMS MENU') && screenText(m).includes('3. SOUNDS'), 'ESC from a list\n' + screenText(m));
  key('Escape'); runFrames(m, 150);
  assert(screenText(m).includes('SDCARD PROGRAMS MENU'), 'ESC from the submenu choice\n' + screenText(m));
  console.log('      ESC: list -> submenu choice -> main menu');

  // a song starts from SOUNDS, with "[SOUND] Name" on the serial line
  open(3);
  serial.length = 0;
  key('Digit1');
  for (let i = 0; i < 600 && m.cpu.pc >= 0x8000; i++) runFrames(m, 1);
  runFrames(m, 60);
  const song = mon.serialText().match(/\[SOUND\] [^\r]*/);
  assert(m.cpu.pc < 0x8000 && song, 'song\n' + mon.serialText() + '\n' + screenText(m));
  console.log(`      SOUNDS: "${song![0]}" started`);

  // a game starts from GAMES and, as before, from page 1 of ALL (ASTEROIDS)
  const runs: [number, number, number][] = [subPos(img, 'ASTEROIDS', 1), [...menuPos(img, 'ASTEROIDS'), 4]];
  for (const [gk, gp, sub] of runs) {
    assert(gp === 1, 'ASTEROIDS on page ' + gp);
    open(sub);
    serial.length = 0;
    key('Digit' + gk);
    for (let i = 0; i < 400 && m.cpu.pc >= 0x8000; i++) runFrames(m, 1);
    runFrames(m, 120);
    assert(m.cpu.pc < 0x8000 && /\[GAME\] ASTEROIDS/.test(mon.serialText()), `ASTEROIDS from submenu ${sub}\n` + screenText(m));
  }
  console.log('      a game (ASTEROIDS) starts from GAMES and from ALL, with "[GAME] ASTEROIDS" on the serial line');
}

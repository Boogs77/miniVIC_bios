// testsd.test.ts - the files of test/ together: the BIOS KEYB/SD and sd_test.img (made by
// test_system/make_test_sd.py): games and applications on one SD. The applications start from page 3 of the menu and open the sample documents.
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { loadApp, Run, assert, ROOT, runFrames, screenText } from './harness';

/** [key, page] of a program in the SD menu, from the directory pages (page P in the first sector of block P) */
function menuPos(img: Uint8Array, name: string): [number, number] {
  for (let p = 0; img[p * 0x8000] === 0x42 && img[p * 0x8000 + 1] === 0x4F; p++)
    for (let i = 0; i < img[p * 0x8000 + 5]; i++) {
      const o = p * 0x8000 + 96 + i * 32;
      let n = '';
      for (let k = o; img[k]; k++) n += String.fromCharCode(img[k]);
      if (n.startsWith(name + ' - ')) return [i + 1, p + 1];
    }
  throw new Error(name + ' not in the SD menu');
}

export default async function () {
  process.env.BIOS_ROM = join(ROOT, 'test', 'bios_keyb_sd.bin');
  const img = new Uint8Array(readFileSync(join(ROOT, 'test', 'sd_test.img')));
  const write = new Run(loadApp('write', 'Write'), img, ...menuPos(img, 'WRITE'));
  assert(/\[APP\] WRITE/.test(write.serialText()), 'WRITE serial line: ' + write.serialText());
  write.ctrl('k'); write.key('KeyO'); write.settle();
  assert(write.screen().includes('LETTER') && write.screen().includes('BUDGET') && write.screen().includes('HELLO'), 'documents\n' + write.screen());
  write.key('Enter'); write.settle();
  assert(write.row(1).startsWith('Dear friend,'), 'LETTER\n' + write.screen());
  write.shot('testsd');
  console.log(`      WRITE from menu page ${menuPos(img, 'WRITE')[1]}, LETTER opened`);

  const calc = new Run(loadApp('calc', 'Calc'), img, ...menuPos(img, 'CALC'));
  calc.type('/', false); calc.key('KeyL'); calc.settle(); calc.key('ArrowDown'); calc.key('Enter'); calc.settle();
  assert(calc.row(9).includes('TOTAL') && calc.row(9).includes('7500') && calc.row(9).includes('6121.65'), 'BUDGET\n' + calc.screen());
  calc.shot('testsd');
  console.log('      CALC: BUDGET loaded, totals 7500 / 6121.65');

  const file = new Run(loadApp('file', 'File'), img, ...menuPos(img, 'FILE'));
  file.ctrl('k'); file.key('KeyO'); file.settle(); file.key('ArrowDown'); file.key('ArrowDown'); file.key('Enter'); file.settle();
  assert(file.row(2).includes('Mario Rossi') && file.row(0).includes('FRIENDS'), 'FRIENDS\n' + file.screen());
  file.shot('testsd');
  console.log('      FILE: FRIENDS opened (4 cards)');

  const asm = new Run(loadApp('asm', 'Asm'), img, ...menuPos(img, 'ASM'));
  for (let i = 0; i < 3; i++) asm.key('ArrowDown');                   // HELLO is the 4th document
  asm.key('Enter'); asm.settle();
  assert(asm.screen().includes('OK: $3000'), 'HELLO assembled\n' + asm.screen());
  asm.type('s'); asm.key('Enter'); asm.settle();
  assert(asm.screen().includes('SAVED'), 'HELLO saved');
  console.log('      ASM: HELLO assembled and saved as code');

  const mon = new Run(loadApp('mon', 'Mon'), img, ...menuPos(img, 'MON'));
  mon.type('l hello'); mon.key('Enter'); mon.settle();
  mon.type('g 3000'); mon.key('Enter'); mon.settle();
  assert(mon.screen().includes('HELLO MINIVIC') && /A=0D/.test(mon.screen()), 'MON: L HELLO, G 3000\n' + mon.screen());
  mon.shot('testsd');
  console.log('      MON: L HELLO, G 3000 writes HELLO MINIVIC, A=0D');

  // a game still starts from page 1 (ASTEROIDS)
  const m = (mon as any).m;
  m.reset(); runFrames(m, 90);
  const [gk, gp] = menuPos(img, 'ASTEROIDS');
  assert(gp === 1, 'ASTEROIDS on page ' + gp);
  mon.key('Digit3'); runFrames(m, 150); mon.key('Digit' + gk);
  for (let i = 0; i < 400 && m.cpu.pc >= 0x8000; i++) runFrames(m, 1);
  runFrames(m, 120);
  assert(m.cpu.pc < 0x8000 && /\[GAME\] ASTEROIDS/.test(mon.serialText()), 'ASTEROIDS\n' + screenText(m));
  console.log('      a game (ASTEROIDS) starts as before, with "[GAME] ASTEROIDS" on the serial line');
}

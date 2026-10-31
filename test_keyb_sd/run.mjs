// Bundles bios_ext.test.ts against the emulator sources and runs it
//   node test_keyb_sd/run.mjs            tests ../tmp/boogs.bin
//   BIOS_ROM=<file.bin> node run.mjs     tests another ROM image
//   the emulator sources are expected in ../../bo6502-emulator (next to this project)
import { createRequire } from 'node:module';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
const here = dirname(fileURLToPath(import.meta.url));
const EMU = join(here, '..', '..', 'bo6502-emulator').split(String.fromCharCode(92)).join('/');
const { build } = createRequire(join(EMU, 'package.json'))('esbuild');
const out = join(here, 'out.mjs');
process.env.BIOS_ROM ||= join(here, '..', 'tmp', 'boogs.bin');
await build({
  entryPoints: [join(here, 'bios_ext.test.ts')], outfile: out, bundle: true, platform: 'node', format: 'esm',
  logLevel: 'error', alias: { EMU }, define: { __dirname_: JSON.stringify(here.split(String.fromCharCode(92)).join('/')) },
});
const mod = await import(pathToFileURL(out).href);
try { await mod.default(); console.log('ALL OK'); } catch (e) { console.error('FAIL ' + (e.stack || e)); process.exit(1); }

// run.mjs - the whole system: the BIOS of tmp/boogs.bin, the MiniVIC games and the MiniVIC Apps on one SD
//   sh make.sh && python test_system/make_test_sd.py && node test_system/run.mjs
// The emulator sources are expected in ../../bo6502-emulator and the applications in ../../MiniVIC Apps/bin.
import { createRequire } from 'node:module';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { existsSync } from 'node:fs';

const slash = (p) => p.split(String.fromCharCode(92)).join('/');
const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..');
const EMU = slash(join(root, '..', 'bo6502-emulator'));
const APPS = slash(join(root, '..', 'MiniVIC Apps'));
for (const f of [join(EMU, 'package.json'), join(APPS, 'bin'), join(root, 'test', 'sd_test.img')])
  if (!existsSync(f)) { console.error('not found: ' + f); process.exit(1); }
const { build } = createRequire(join(EMU, 'package.json'))('esbuild');
const out = join(here, 'out.mjs');
await build({
  entryPoints: [join(here, 'testsd.test.ts')], outfile: out, bundle: true, platform: 'node', format: 'esm',
  logLevel: 'error', alias: { EMU }, define: { __ROOT__: JSON.stringify(slash(root)), __APPS__: JSON.stringify(APPS) },
});
const mod = await import(pathToFileURL(out).href);
try { await mod.default(); console.log('ALL OK'); } catch (e) { console.error('FAIL ' + (e.stack || e)); process.exit(1); }

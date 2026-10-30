import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
const root = path.resolve(import.meta.dirname, '..');
const studio = process.env.DEVECO_HOME || '/Applications/DevEco-Studio.app/Contents';
if (!fs.existsSync(path.join(root, 'build-profile.json5'))) {
  fs.copyFileSync(path.join(root, 'build-profile.example.json5'), path.join(root, 'build-profile.json5'));
}
const tooling = path.join(root, '.tooling');
fs.mkdirSync(path.join(root, 'node_modules/@ohos'), { recursive: true });
for (const [name, source] of [['hvigor', 'hvigor'], ['hvigor-ohos-plugin', 'hvigor-ohos-plugin']]) {
  const target = path.join(root, 'node_modules/@ohos', name);
  if (!fs.existsSync(target)) fs.symlinkSync(path.join(studio, 'tools/hvigor', source), target);
}
const result = spawnSync(path.join(studio, 'tools/node/bin/node'), [
  path.join(studio, 'tools/hvigor/hvigor/bin/hvigor.js'),
  '--mode', 'module', '-p', 'product=default', '-p', 'module=entry@default',
  '-p', 'buildMode=debug', 'assembleHap', '--no-daemon', ...process.argv.slice(2)
], {
  cwd: root, stdio: 'inherit', env: {
    ...process.env,
    JAVA_HOME: path.join(studio, 'jbr/Contents/Home'),
    DEVECO_SDK_HOME: path.join(studio, 'sdk'),
    HVIGOR_USER_HOME: path.join(tooling, 'hvigor'),
    NODE_PATH: path.join(root, 'node_modules'),
    PATH: `${studio}/tools/node/bin:${studio}/tools/ohpm/bin:${process.env.PATH}`
  }
});
process.exit(result.status ?? 1);

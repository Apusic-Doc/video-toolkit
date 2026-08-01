import fs from 'fs';
import path from 'path';
import { execFile } from 'child_process';
import { promisify } from 'util';
import { TOOLKIT_DIR } from './paths.js';

const execFileAsync = promisify(execFile);

// 读某个 feature 自己的 meta.json（编辑器要改的就是这份，不是合并后的结果）
export function readFeatureMeta(featureDir) {
  const p = path.join(featureDir, 'meta.json');
  if (!fs.existsSync(p)) return {};
  try { return JSON.parse(fs.readFileSync(p, 'utf8')); }
  catch { return {}; }
}

export function writeFeatureMeta(featureDir, data) {
  const p = path.join(featureDir, 'meta.json');
  fs.writeFileSync(p, JSON.stringify(data, null, 2) + '\n', 'utf8');
}

export function readProjectMeta(projectDir) {
  const p = path.join(projectDir, 'meta.json');
  if (!fs.existsSync(p)) return {};
  try { return JSON.parse(fs.readFileSync(p, 'utf8')); }
  catch { return {}; }
}

export function writeProjectMeta(projectDir, data) {
  const p = path.join(projectDir, 'meta.json');
  fs.writeFileSync(p, JSON.stringify(data, null, 2) + '\n', 'utf8');
}

// 三级合并后的"最终生效值"，直接复用真实的 lib/meta.sh:load_meta，
// 不在 JS 里重新实现一遍合并逻辑（避免跟 bash 那边的行为长出两套不一样的结果）
export async function readMergedMeta(featureDir) {
  const script = `source "${TOOLKIT_DIR}/lib/meta.sh"; load_meta "$1"`;
  try {
    const { stdout } = await execFileAsync('bash', ['-c', script, '--', featureDir], { timeout: 10000 });
    return JSON.parse(stdout.trim());
  } catch (e) {
    return {};
  }
}

// 项目设置页面用："项目不设置这个字段的话，实际会生效的值"——内置默认 + 本机
// vt config 全局设置，不含任何 project/feature meta.json（那正是这个页面要编辑的东西）
export async function readProjectDefaults() {
  const script = `source "${TOOLKIT_DIR}/lib/meta.sh"; project_defaults`;
  try {
    const { stdout } = await execFileAsync('bash', ['-c', script], { timeout: 10000 });
    return JSON.parse(stdout.trim());
  } catch (e) {
    return {};
  }
}

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export const TOOLKIT_DIR = path.resolve(__dirname, '..', '..');
// "toolkit 自己装在哪" 跟 "视频项目目录在哪" 是两回事——装到 ~/.local/share/video-toolkit
// 之后，它的上一级目录（~/.local/share）跟用户的 Videos/ 项目目录完全没关系，
// 只有直接跑仓库源码副本（Videos/toolkit/）时两者才恰好重合。
// 真正可靠的来源是 vt ui 启动时传进来的 VT_UI_VIDEOS_ROOT（cmd_ui 用当时的
// 工作目录算出来的），退回到 dirname(TOOLKIT_DIR) 只是本地开发时的兜底。
export const VIDEOS_ROOT = process.env.VT_UI_VIDEOS_ROOT || path.dirname(TOOLKIT_DIR);
export const VT_BIN = path.join(process.env.HOME || '', '.local', 'bin', 'vt');

// 一个"project"就是 VIDEOS_ROOT 下任意一个直接子目录，
// 判定标准：里面至少有一个 feature-* 子目录（不要求叫 projects/xxx，跟实际用法一致——
// 项目目录就是直接挂在 Videos/ 下面，不是套在 projects/ 里）
function isFeatureDir(p) {
  try { return fs.statSync(p).isDirectory(); } catch { return false; }
}

// 判定"是不是项目"：要么已经有至少一个 feature-* 子目录（老项目，一直以来的判定标准），
// 要么带着 .video-toolkit-project 标记文件（新建但还没加 feature 的空项目，见 createProject）——
// 后者是为了让 vt-ui 的"新建项目"按钮建出来的空项目也能立刻出现在下拉框里
export function listProjects() {
  const names = fs.readdirSync(VIDEOS_ROOT, { withFileTypes: true })
    .filter(d => d.isDirectory() && !d.name.startsWith('.') && d.name !== 'toolkit')
    .map(d => d.name);
  const projects = [];
  for (const name of names) {
    const dir = path.join(VIDEOS_ROOT, name);
    const entries = fs.readdirSync(dir, { withFileTypes: true });
    const hasFeature = entries.some(d => d.isDirectory() && d.name.startsWith('feature-'));
    const isMarked = entries.some(d => d.isFile() && d.name === '.video-toolkit-project');
    if (hasFeature || isMarked) projects.push(name);
  }
  return projects.sort();
}

const PROJECT_NAME_RE = /^[a-z0-9][a-z0-9-]{0,63}$/;
const FEATURE_SLUG_RE = /^[a-z0-9][a-z0-9-]{0,63}$/;

// 新建一个空项目目录：标记文件 + 最小 meta.json，供 listProjects() 立刻识别
export function createProject(name) {
  if (!PROJECT_NAME_RE.test(name)) throw new Error('项目名只能是小写字母/数字/短横线，且以字母数字开头');
  const dir = path.join(VIDEOS_ROOT, name);
  if (fs.existsSync(dir)) throw new Error('目录已存在');
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, '.video-toolkit-project'), '');
  fs.writeFileSync(path.join(dir, 'meta.json'), '{}\n');
  return dir;
}

// 新建一个 feature 目录：feature-<NNN>-<slug>，NNN 是现有最大编号+1，零填充到
// 项目 meta.json 的 feature_seq_digits（默认 3 位）——只建目录，不生成 record.spec.js/
// meta.json，那些交给 AI 按一句话意图去写（17章的工作流），这里只负责"这个功能点存在"
export function createFeature(project, slug) {
  if (!FEATURE_SLUG_RE.test(slug)) throw new Error('feature 名只能是小写字母/数字/短横线，且以字母数字开头');
  const projectDir = resolveProjectDir(project);
  if (!projectDir) throw new Error('project not found');

  const existing = listFeatures(project);
  let maxN = 0;
  let existingWidth = 0;
  for (const name of existing) {
    const m = name.match(/^feature-(\d+)-/);
    if (m) {
      maxN = Math.max(maxN, parseInt(m[1], 10));
      existingWidth = Math.max(existingWidth, m[1].length);
    }
  }

  // 位数优先级：项目 meta.json 显式配置 > 沿用这个项目已有编号的位数（老项目大多是 2 位，
  // 不能因为新建一个 feature 就悄悄跳到 3 位，导致同一个项目里编号风格不一致）> 全新项目默认 3 位
  let digits = existingWidth || 3;
  try {
    const meta = JSON.parse(fs.readFileSync(path.join(projectDir, 'meta.json'), 'utf8'));
    if (Number.isInteger(meta.feature_seq_digits) && meta.feature_seq_digits > 0) digits = meta.feature_seq_digits;
  } catch {}

  const seq = String(maxN + 1).padStart(digits, '0');
  const featureName = `feature-${seq}-${slug}`;
  const dir = path.join(projectDir, featureName);
  if (fs.existsSync(dir)) throw new Error(`目录已存在: ${featureName}`);
  fs.mkdirSync(dir, { recursive: true });
  return featureName;
}

// 软删除：挪进项目根目录的 _trash/，带时间戳避免重名冲突——绝不用 rm -rf，
// 里面可能有已经花时间录好的 recording.mov
export function softDeleteFeature(project, feature) {
  const featureDir = resolveFeatureDir(project, feature);
  if (!featureDir) throw new Error('feature not found');
  const projectDir = resolveProjectDir(project);
  const trashDir = path.join(projectDir, '_trash');
  fs.mkdirSync(trashDir, { recursive: true });
  const ts = new Date().toISOString().replace(/[:.]/g, '-');
  const dest = path.join(trashDir, `${feature}-${ts}`);
  fs.renameSync(featureDir, dest);
  return dest;
}

// 校验 project 名字合法（必须是 listProjects() 里真实存在的一个），返回绝对路径或 null
export function resolveProjectDir(project) {
  if (!project || typeof project !== 'string') return null;
  if (!listProjects().includes(project)) return null;
  return path.join(VIDEOS_ROOT, project);
}

// 校验 feature 名字合法（必须是该 project 下真实存在的 feature-* 目录），返回绝对路径或 null
export function resolveFeatureDir(project, feature) {
  const projectDir = resolveProjectDir(project);
  if (!projectDir) return null;
  if (!feature || typeof feature !== 'string' || !feature.startsWith('feature-')) return null;
  const dir = path.join(projectDir, feature);
  if (!isFeatureDir(dir)) return null;
  // 防越界：resolve 后必须仍然是 projectDir 的直接子目录
  if (path.dirname(dir) !== projectDir) return null;
  return dir;
}

export function listFeatures(project) {
  const projectDir = resolveProjectDir(project);
  if (!projectDir) return [];
  return fs.readdirSync(projectDir, { withFileTypes: true })
    .filter(d => d.isDirectory() && d.name.startsWith('feature-'))
    .map(d => d.name)
    .sort();
}

export function featureStatus(featureDir) {
  const has = (name) => fs.existsSync(path.join(featureDir, name));
  const base = path.basename(featureDir);
  return {
    name: base,
    recording: has('recording.mov'),
    subtitles: has('subtitles.srt'),
    dub: has('ai_dub.wav'),
    mp4: has(`${base}.mp4`),
    noCoverMp4: has(`${base}-no-cover.mp4`),
    subMp4: has(`${base}-sub.mp4`),
    // 英文流水线（trans → dub-en → mix-en），默认不生产，高级面板里按需露出
    dubEn: has('ai_dub_en.wav'),
    mp4En: has(`${base}_en.mp4`),
  };
}

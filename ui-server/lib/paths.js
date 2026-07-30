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

export function listProjects() {
  const names = fs.readdirSync(VIDEOS_ROOT, { withFileTypes: true })
    .filter(d => d.isDirectory() && !d.name.startsWith('.') && d.name !== 'toolkit')
    .map(d => d.name);
  const projects = [];
  for (const name of names) {
    const dir = path.join(VIDEOS_ROOT, name);
    const hasFeature = fs.readdirSync(dir, { withFileTypes: true })
      .some(d => d.isDirectory() && d.name.startsWith('feature-'));
    if (hasFeature) projects.push(name);
  }
  return projects.sort();
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

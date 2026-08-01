import express from 'express';
import fs from 'fs';
import path from 'path';
import {
  listProjects, listFeatures, resolveProjectDir, resolveFeatureDir, featureStatus,
  createProject, createFeature, softDeleteFeature,
} from '../lib/paths.js';
import { readFeatureMeta, writeFeatureMeta, readMergedMeta, readProjectMeta, writeProjectMeta, readProjectDefaults } from '../lib/meta.js';
import { parseSrt, serializeSrt } from '../lib/srt.js';
import { runTask, getHistory, ALLOWED_COMMANDS } from '../lib/taskRunner.js';
import { guardScreenCommand } from '../lib/localGuard.js';
import { FONTS, VOICES, ensureFontPreview, ensureVoiceSample, findFont, findVoice } from '../lib/fontsVoices.js';

const router = express.Router();

// ── projects / features ──
// name 是目录名（slug，稳定不变，API 路径靠它定位），displayName 是给人看的
// 项目名称（project meta.json 里的 name 字段，纯 UI 展示用，不参与 3 级配置合并、
// 不会被任何 feature 继承——跟 title 字段的用途完全分开，title 是视频内容里的标题）
router.get('/projects', (req, res) => {
  res.json(listProjects().map(name => {
    const meta = readProjectMeta(resolveProjectDir(name));
    return { name, displayName: meta.name || null, company: meta.company || null, featureCount: listFeatures(name).length };
  }));
});

// ── 项目级 meta.json（字体/字号/语音/封面配色这些"整个项目该统一"的设置放这里，
// 单个 feature 的 meta.json 留空就会继承这里的值，覆盖了才是这个 feature 自己特殊）──
router.get('/projects/:project/meta', async (req, res) => {
  const projectDir = resolveProjectDir(req.params.project);
  if (!projectDir) return res.status(404).json({ error: 'project not found' });
  const merged = await readProjectDefaults();
  res.json({ raw: readProjectMeta(projectDir), merged });
});

router.put('/projects/:project/meta', (req, res) => {
  const projectDir = resolveProjectDir(req.params.project);
  if (!projectDir) return res.status(404).json({ error: 'project not found' });
  const data = req.body;
  if (typeof data !== 'object' || data === null || Array.isArray(data)) {
    return res.status(400).json({ error: 'meta 必须是一个 JSON 对象' });
  }
  writeProjectMeta(projectDir, data);
  res.json({ ok: true });
});

// 项目级封面预览：用项目 meta 里的默认值（没有 title 时用项目名占位）渲染一张示例封面
router.post('/projects/:project/preview-cover', async (req, res) => {
  const projectDir = resolveProjectDir(req.params.project);
  if (!projectDir) return res.status(404).json({ error: 'project not found' });
  const { execFile } = await import('child_process');
  const { promisify } = await import('util');
  const execFileAsync = promisify(execFile);
  const { TOOLKIT_DIR } = await import('../lib/paths.js');
  const data = req.body || {};
  const tmpPng = path.join(projectDir, '.ui_preview_cover.png');

  let logoPath = '';
  if (data.logo && typeof data.logo === 'string') {
    const candidate = path.join(projectDir, data.logo);
    if (fs.existsSync(candidate)) logoPath = candidate;
  } else {
    const auto = path.join(projectDir, 'resources', 'logo.png');
    if (fs.existsSync(auto)) logoPath = auto;
  }
  const script = `source "${TOOLKIT_DIR}/lib/compose.sh"; gen_title_card_png "$1" "$2" "$3" "$4" "$5" "$6"`;
  try {
    await execFileAsync('bash', ['-c', script, '--',
      data.title || '示例标题 Sample Title', data.subtitle || '示例副标题', tmpPng, logoPath,
      data.company || '', data.cover_accent_color || '#222222']);
    if (!fs.existsSync(tmpPng)) return res.status(400).json({ error: '生成失败' });
    res.setHeader('Content-Type', 'image/png');
    res.setHeader('Cache-Control', 'no-store');
    fs.createReadStream(tmpPng).pipe(res).on('close', () => fs.unlink(tmpPng, () => {}));
  } catch (e) {
    res.status(500).json({ error: String(e) });
  }
});

router.post('/projects', (req, res) => {
  const { slug, displayName } = req.body || {};
  if (!slug) return res.status(400).json({ error: '缺少 slug' });
  try {
    createProject(slug, displayName);
    res.json({ ok: true, project: slug });
  } catch (e) {
    res.status(400).json({ error: e.message });
  }
});

router.post('/projects/:project/features', (req, res) => {
  const { slug } = req.body || {};
  if (!slug) return res.status(400).json({ error: '缺少 slug' });
  if (!resolveProjectDir(req.params.project)) return res.status(404).json({ error: 'project not found' });
  try {
    const featureName = createFeature(req.params.project, slug);
    res.json({ ok: true, feature: featureName });
  } catch (e) {
    res.status(400).json({ error: e.message });
  }
});

router.delete('/projects/:project/features/:feature', requireFeature, (req, res) => {
  try {
    softDeleteFeature(req.params.project, req.params.feature);
    res.json({ ok: true });
  } catch (e) {
    res.status(400).json({ error: e.message });
  }
});

router.get('/projects/:project/features', (req, res) => {
  const projectDir = resolveProjectDir(req.params.project);
  if (!projectDir) return res.status(404).json({ error: 'project not found' });
  const features = listFeatures(req.params.project).map((name) => {
    const dir = path.join(projectDir, name);
    const meta = readFeatureMeta(dir);
    return { ...featureStatus(dir), title: meta.title || null };
  });
  res.json(features);
});

function requireFeature(req, res, next) {
  const projectDir = resolveProjectDir(req.params.project);
  const featureDir = resolveFeatureDir(req.params.project, req.params.feature);
  if (!projectDir || !featureDir) return res.status(404).json({ error: 'feature not found' });
  req.projectDir = projectDir;
  req.featureDir = featureDir;
  next();
}

router.get('/projects/:project/features/:feature', requireFeature, (req, res) => {
  res.json(featureStatus(req.featureDir));
});

// ── meta.json ──
router.get('/projects/:project/features/:feature/meta', requireFeature, async (req, res) => {
  const raw = readFeatureMeta(req.featureDir);
  const merged = await readMergedMeta(req.featureDir);
  res.json({ raw, merged });
});

router.put('/projects/:project/features/:feature/meta', requireFeature, (req, res) => {
  const data = req.body;
  if (typeof data !== 'object' || data === null || Array.isArray(data)) {
    return res.status(400).json({ error: 'meta 必须是一个 JSON 对象' });
  }
  writeFeatureMeta(req.featureDir, data);
  res.json({ ok: true });
});

// ── 封面预览（用当前表单里的值现改现渲染，不落地成正式 cover 素材）──
// 直接调真实的 gen_title_card_png（跟 compose_final 生产时用的是同一个函数），
// 不在这里另外重写一遍 magick 拼图逻辑，避免以后两边改漂了
router.post('/projects/:project/features/:feature/preview-cover', requireFeature, async (req, res) => {
  const { execFile } = await import('child_process');
  const { promisify } = await import('util');
  const execFileAsync = promisify(execFile);
  const { TOOLKIT_DIR } = await import('../lib/paths.js');
  const data = req.body || {};
  const tmpPng = path.join(req.featureDir, '.ui_preview_cover.png');

  let logoPath = '';
  if (data.logo && typeof data.logo === 'string') {
    const candidate = path.join(req.projectDir, data.logo);
    if (fs.existsSync(candidate)) logoPath = candidate;
  } else {
    const auto = path.join(req.projectDir, 'resources', 'logo.png');
    if (fs.existsSync(auto)) logoPath = auto;
  }
  const script = `source "${TOOLKIT_DIR}/lib/compose.sh"; gen_title_card_png "$1" "$2" "$3" "$4" "$5" "$6"`;
  try {
    await execFileAsync('bash', ['-c', script, '--',
      data.title || '', data.subtitle || '', tmpPng, logoPath,
      data.company || '', data.cover_accent_color || '#222222']);
    if (!fs.existsSync(tmpPng)) return res.status(400).json({ error: '标题不能为空' });
    res.setHeader('Content-Type', 'image/png');
    res.setHeader('Cache-Control', 'no-store');
    fs.createReadStream(tmpPng).pipe(res).on('close', () => fs.unlink(tmpPng, () => {}));
  } catch (e) {
    res.status(500).json({ error: String(e) });
  }
});

// ── subtitles.srt ──
router.get('/projects/:project/features/:feature/subtitles', requireFeature, (req, res) => {
  const p = path.join(req.featureDir, 'subtitles.srt');
  if (!fs.existsSync(p)) return res.json({ cues: [] });
  res.json({ cues: parseSrt(fs.readFileSync(p, 'utf8')) });
});

router.put('/projects/:project/features/:feature/subtitles', requireFeature, (req, res) => {
  const { cues } = req.body || {};
  if (!Array.isArray(cues)) return res.status(400).json({ error: 'cues 必须是数组' });
  const p = path.join(req.featureDir, 'subtitles.srt');
  fs.writeFileSync(p, serializeSrt(cues), 'utf8');
  res.json({ ok: true });
});

// ── cuts.json（成片剪辑：要从最终视频里去掉的时间区间，vt recut 读这个文件）──
router.get('/projects/:project/features/:feature/cuts', requireFeature, (req, res) => {
  const p = path.join(req.featureDir, 'cuts.json');
  if (!fs.existsSync(p)) return res.json({ cuts: [] });
  try {
    res.json({ cuts: JSON.parse(fs.readFileSync(p, 'utf8')) });
  } catch {
    res.status(500).json({ error: 'cuts.json 解析失败' });
  }
});

// ── groups（多个 feature 的成片按顺序合并成一个对外发布的大视频，定义存在项目级
// meta.json 的 groups 数组里；只读取各 feature 现有成片来拼接，从不改动/删除
// 任何 feature-*/ 目录下的文件，合并结果落在项目根目录的 groups/<id>.mp4）──
function readGroups(projectDir) {
  return readProjectMeta(projectDir).groups || [];
}
function writeGroups(projectDir, groups) {
  writeProjectMeta(projectDir, { ...readProjectMeta(projectDir), groups });
}

router.get('/projects/:project/groups', (req, res) => {
  const projectDir = resolveProjectDir(req.params.project);
  if (!projectDir) return res.status(404).json({ error: 'project not found' });
  res.json(readGroups(projectDir));
});

router.post('/projects/:project/groups', (req, res) => {
  const projectDir = resolveProjectDir(req.params.project);
  if (!projectDir) return res.status(404).json({ error: 'project not found' });
  const { id, title } = req.body || {};
  if (!id || !/^[a-z0-9-]+$/.test(id)) return res.status(400).json({ error: 'id 只能是小写字母/数字/短横线' });
  const groups = readGroups(projectDir);
  if (groups.some((g) => g.id === id)) return res.status(400).json({ error: '分组 id 已存在' });
  groups.push({ id, title: title || id, features: [] });
  writeGroups(projectDir, groups);
  res.json({ ok: true });
});

router.put('/projects/:project/groups/:id', (req, res) => {
  const projectDir = resolveProjectDir(req.params.project);
  if (!projectDir) return res.status(404).json({ error: 'project not found' });
  const { title, features } = req.body || {};
  if (!Array.isArray(features)) return res.status(400).json({ error: 'features 必须是数组' });
  const valid = new Set(listFeatures(req.params.project));
  for (const f of features) {
    if (!valid.has(f)) return res.status(400).json({ error: `feature 不存在: ${f}` });
  }
  const groups = readGroups(projectDir);
  const g = groups.find((g) => g.id === req.params.id);
  if (!g) return res.status(404).json({ error: 'group not found' });
  if (title !== undefined) g.title = title;
  g.features = features;
  writeGroups(projectDir, groups);
  res.json({ ok: true });
});

// 只删分组这条定义，不碰任何视频文件——分组本来就是"元数据"，原 feature 视频完全不受影响
router.delete('/projects/:project/groups/:id', (req, res) => {
  const projectDir = resolveProjectDir(req.params.project);
  if (!projectDir) return res.status(404).json({ error: 'project not found' });
  writeGroups(projectDir, readGroups(projectDir).filter((g) => g.id !== req.params.id));
  res.json({ ok: true });
});

router.post('/projects/:project/groups/:id/merge', (req, res) => {
  const projectDir = resolveProjectDir(req.params.project);
  if (!projectDir) return res.status(404).json({ error: 'project not found' });
  if (!readGroups(projectDir).some((g) => g.id === req.params.id)) {
    return res.status(404).json({ error: 'group not found' });
  }
  const id = runTask(req.params.project, `group:${req.params.id}`, projectDir, req.params.id, 'group-merge');
  res.json({ id });
});

router.get('/projects/:project/groups/:id/tasks', (req, res) => {
  res.json(getHistory(req.params.project, `group:${req.params.id}`));
});

// 合并结果 groups/<id>.mp4 的播放地址——id 本身已经在创建时校验过是 [a-z0-9-]+，
// 这里再核实一遍避免路径穿越
router.get('/projects/:project/groups/:id/file', (req, res) => {
  const projectDir = resolveProjectDir(req.params.project);
  if (!projectDir || !/^[a-z0-9-]+$/.test(req.params.id)) return res.status(404).end();
  const fp = path.join(projectDir, 'groups', `${req.params.id}.mp4`);
  if (!fs.existsSync(fp)) return res.status(404).end();
  res.setHeader('Cache-Control', 'no-cache');
  res.sendFile(fp);
});

router.put('/projects/:project/features/:feature/cuts', requireFeature, (req, res) => {
  const { cuts } = req.body || {};
  if (!Array.isArray(cuts)) return res.status(400).json({ error: 'cuts 必须是数组' });
  for (const c of cuts) {
    if (!c || typeof c.start !== 'string' || typeof c.end !== 'string') {
      return res.status(400).json({ error: '每条区间必须是 { start, end } 字符串' });
    }
  }
  const p = path.join(req.featureDir, 'cuts.json');
  fs.writeFileSync(p, JSON.stringify(cuts, null, 2), 'utf8');
  res.json({ ok: true });
});

// ── 说明文档（README.md，纯展示，不可编辑——改文档去改 README.md 本身）──
router.get('/projects/:project/features/:feature/readme', requireFeature, (req, res) => {
  const p = path.join(req.featureDir, 'README.md');
  if (!fs.existsSync(p)) return res.json({ content: '' });
  res.json({ content: fs.readFileSync(p, 'utf8') });
});

// ── tasks ──
router.get('/projects/:project/features/:feature/tasks', requireFeature, (req, res) => {
  res.json(getHistory(req.params.project, req.params.feature));
});

router.post('/projects/:project/features/:feature/tasks', requireFeature, guardScreenCommand, (req, res) => {
  const { cmd } = req.body || {};
  if (!ALLOWED_COMMANDS.has(cmd)) return res.status(400).json({ error: `不支持的命令: ${cmd}` });
  const id = runTask(req.params.project, req.params.feature, req.projectDir, req.params.feature, cmd);
  res.json({ id });
});

// ── media 文件（recording.mov / *.mp4 / ai_dub.wav / subtitles.srt 等，range 请求走 sendFile）──
router.get('/projects/:project/features/:feature/files/:filename', requireFeature, (req, res) => {
  const { filename } = req.params;
  if (filename.includes('/') || filename.includes('..')) return res.status(400).end();
  const fp = path.join(req.featureDir, filename);
  if (!fs.existsSync(fp) || !fs.statSync(fp).isFile()) return res.status(404).end();
  // 录制/字幕/成片这些文件经常在原地被重新生成（文件名不变，内容变了），
  // 不能让浏览器无条件信任本地缓存，每次都强制回源校验（有 ETag 命中还是走 304，不是整个重下）
  res.setHeader('Cache-Control', 'no-cache');
  res.sendFile(fp);
});

// ── fonts / voices ──
router.get('/fonts', async (req, res) => {
  res.json(FONTS.map(f => ({ ...f, previewUrl: `/api/fonts/${f.id}/preview.png` })));
});
router.get('/fonts/:id/preview.png', async (req, res) => {
  const font = findFont(req.params.id);
  if (!font) return res.status(404).end();
  try {
    const p = await ensureFontPreview(font);
    res.setHeader('Content-Type', 'image/png');
    res.setHeader('Cache-Control', 'public, max-age=86400');
    fs.createReadStream(p).pipe(res);
  } catch (e) { res.status(500).json({ error: String(e) }); }
});

router.get('/voices', async (req, res) => {
  res.json(VOICES.map(v => ({ ...v, sampleUrl: `/api/voices/${v.id}/sample.mp3` })));
});
router.get('/voices/:id/sample.mp3', async (req, res) => {
  const voice = findVoice(req.params.id);
  if (!voice) return res.status(404).end();
  try {
    const p = await ensureVoiceSample(voice);
    res.setHeader('Content-Type', 'audio/mpeg');
    res.setHeader('Cache-Control', 'public, max-age=86400');
    fs.createReadStream(p).pipe(res);
  } catch (e) { res.status(500).json({ error: String(e) }); }
});

export default router;

import express from 'express';
import fs from 'fs';
import path from 'path';
import {
  listProjects, listFeatures, resolveProjectDir, resolveFeatureDir, featureStatus,
} from '../lib/paths.js';
import { readFeatureMeta, writeFeatureMeta, readMergedMeta, readProjectMeta, writeProjectMeta } from '../lib/meta.js';
import { parseSrt, serializeSrt } from '../lib/srt.js';
import { runTask, getHistory, ALLOWED_COMMANDS } from '../lib/taskRunner.js';
import { guardScreenCommand } from '../lib/localGuard.js';
import { FONTS, VOICES, ensureFontPreview, ensureVoiceSample, findFont, findVoice } from '../lib/fontsVoices.js';

const router = express.Router();

// ── projects / features ──
router.get('/projects', (req, res) => {
  res.json(listProjects().map(name => ({
    name,
    company: readProjectMeta(resolveProjectDir(name)).company || null,
  })));
});

// ── 项目级 meta.json（字体/字号/语音/封面配色这些"整个项目该统一"的设置放这里，
// 单个 feature 的 meta.json 留空就会继承这里的值，覆盖了才是这个 feature 自己特殊）──
router.get('/projects/:project/meta', (req, res) => {
  const projectDir = resolveProjectDir(req.params.project);
  if (!projectDir) return res.status(404).json({ error: 'project not found' });
  res.json({ raw: readProjectMeta(projectDir) });
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

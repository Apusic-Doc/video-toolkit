import fs from 'fs';
import path from 'path';
import { execFile } from 'child_process';
import { promisify } from 'util';
import { TOOLKIT_DIR } from './paths.js';

const execFileAsync = promisify(execFile);
const FF = '/usr/local/opt/ffmpeg-full/bin/ffmpeg';
const EDGE_TTS = path.join(TOOLKIT_DIR, '.venv', 'bin', 'edge-tts');
const CACHE_DIR = path.join(path.dirname(new URL(import.meta.url).pathname), '..', 'cache');
const FONT_CACHE = path.join(CACHE_DIR, 'fonts');
const VOICE_CACHE = path.join(CACHE_DIR, 'voices');
fs.mkdirSync(FONT_CACHE, { recursive: true });
fs.mkdirSync(VOICE_CACHE, { recursive: true });

// 跟烧字幕用的是同一套 libass 渲染路径（force_style FontName=家族名），
// 预览图就是真实渲染效果，不是随便找张示意图糊弄
export const FONTS = [
  { id: 'pingfang', name: 'PingFang SC', label: '苹方（现代无衬线）' },
  { id: 'heiti', name: 'Heiti SC', label: '黑体（经典无衬线）' },
  { id: 'songti', name: 'Songti SC', label: '宋体（衬线，正式）' },
  { id: 'kaiti', name: 'Kaiti SC', label: '楷体（手写风格）' },
  { id: 'yuanti', name: 'Yuanti SC', label: '圆体（圆润活泼）' },
];

export const VOICES = [
  { id: 'zh-CN-XiaoxiaoNeural', lang: 'zh', label: 'Xiaoxiao · 温暖清晰' },
  { id: 'zh-CN-YunyangNeural', lang: 'zh', label: 'Yunyang · 专业播报' },
  { id: 'zh-CN-YunjianNeural', lang: 'zh', label: 'Yunjian · 激昂有力' },
  { id: 'zh-CN-YunxiNeural', lang: 'zh', label: 'Yunxi · 活泼自然' },
  { id: 'zh-CN-XiaoyiNeural', lang: 'zh', label: 'Xiaoyi · 亲切可爱' },
  { id: 'en-US-AvaNeural', lang: 'en', label: 'Ava · Clear & friendly' },
  { id: 'en-US-AriaNeural', lang: 'en', label: 'Aria · Confident' },
  { id: 'en-US-ChristopherNeural', lang: 'en', label: 'Christopher · Authoritative' },
  { id: 'en-GB-SoniaNeural', lang: 'en', label: 'Sonia · British female' },
  { id: 'en-GB-RyanNeural', lang: 'en', label: 'Ryan · British male' },
];

const SAMPLE_TEXT = { zh: '欢迎使用金蝶天燕产品', en: 'Welcome to Apusic products' };

function fontPreviewPath(id) { return path.join(FONT_CACHE, `${id}.png`); }
function voiceSamplePath(id) { return path.join(VOICE_CACHE, `${id}.mp3`); }

// 画布/字号都调大过——之前 640x140/FontSize=40 缩在小格子里看着够用，
// 点开放大之后就糊了，现在按点开后的展示尺寸生成，缩小当缩略图用反而更清晰
export async function ensureFontPreview(font) {
  const out = fontPreviewPath(font.id);
  if (fs.existsSync(out)) return out;
  const srt = path.join(FONT_CACHE, `${font.id}.srt`);
  fs.writeFileSync(srt, `1\n00:00:00,000 --> 00:00:05,000\n字幕预览 欢迎使用金蝶天燕产品 ABC 123\n`);
  await execFileAsync(FF, [
    '-f', 'lavfi', '-i', 'color=c=white:s=1200x260',
    '-vf', `subtitles=${srt}:force_style='FontName=${font.name},FontSize=60,PrimaryColour=&H00222222,Outline=0,MarginV=15'`,
    '-frames:v', '1', '-y', out, '-loglevel', 'error',
  ]);
  fs.unlinkSync(srt);
  return out;
}

export async function ensureVoiceSample(voice) {
  const out = voiceSamplePath(voice.id);
  if (fs.existsSync(out)) return out;
  const text = SAMPLE_TEXT[voice.lang] || SAMPLE_TEXT.zh;
  await execFileAsync(EDGE_TTS, ['--voice', voice.id, '--text', text, '--write-media', out], { timeout: 30000 });
  return out;
}

export function findFont(id) { return FONTS.find(f => f.id === id) || null; }
export function findVoice(id) { return VOICES.find(v => v.id === id) || null; }

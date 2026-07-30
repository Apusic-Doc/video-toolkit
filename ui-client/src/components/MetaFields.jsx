import FontPicker from './FontPicker.jsx';
import VoicePicker from './VoicePicker.jsx';
import { assToRgbHex, rgbHexToAss } from '../colorUtils.js';

const EMPTY_STYLE = { font_name: 'PingFang SC', font_size: 44, color: '&H00FFFFFF', outline: '&H00000000', margin_v: 45 };

// meta_defaults() 里 subtitle 的内置默认值其实是个 {mode,burn} 对象（字幕生成模式配置），
// 跟"封面副标题文案"这个字符串用途的 subtitle 撞了同一个 key——只有当某 feature 自己
// 没设置字符串副标题时，merged 出来的 subtitle 才会是这个对象，直接当 placeholder 用
// 会在输入框里显示 "[object Object]"，这里做个防御性过滤。
function asPlaceholder(v) {
  return typeof v === 'string' ? v : '';
}

// feature 页面和项目设置页面共用同一套字段——按 RULE.md 的想法，字体/字号/语音/
// 封面配色这些"设计"层面的东西整个项目该统一，只有 title/subtitle 这种"内容"
// 是每个 feature 自己的，所以用 showContent 控制要不要露出内容字段。
// advanced=false 时只露标题/副标题/配音偏移——正常 feature 该走项目级默认，
// 不需要每次都盯着一屏字体字号语音选项；advanced=true（点开"高级设置"）才露全部。
export default function MetaFields({ raw, merged, set, showContent, advanced = true }) {
  const style = { ...EMPTY_STYLE, ...(merged?.subtitle_style || {}), ...(raw.subtitle_style || {}) };
  const effectiveVoice = raw.voice || merged?.voice || 'zh-CN-XiaoxiaoNeural';
  const effectiveVoiceEn = raw.voice_en || merged?.voice_en || 'en-US-AvaNeural';
  const effectiveAccent = raw.cover_accent_color || merged?.cover_accent_color || '#222222';

  return (
    <div>
      {showContent && (
        <div className="form-grid">
          <div className="form-field">
            <label>标题 title</label>
            <input type="text" value={raw.title || ''} onChange={(e) => set('title', e.target.value)} placeholder={asPlaceholder(merged?.title)} />
          </div>
          <div className="form-field">
            <label>副标题 subtitle</label>
            <input type="text" value={raw.subtitle || ''} onChange={(e) => set('subtitle', e.target.value)} placeholder={asPlaceholder(merged?.subtitle)} />
          </div>
          <div className="form-field">
            <label>配音时间偏移 dub_offset（秒，感觉配音比画面快就填负数，比画面慢就填正数）</label>
            <input
              type="number" step="0.1" value={raw.dub_offset ?? ''}
              onChange={(e) => set('dub_offset', e.target.value === '' ? '' : +e.target.value)}
              placeholder="0"
            />
          </div>
        </div>
      )}

      {advanced && (
      <div className="form-grid" style={{ marginTop: showContent ? 16 : 0 }}>
        <div className="form-field">
          <label>公司名 company{showContent ? '（留空用项目级默认）' : ''}</label>
          <input type="text" value={raw.company || ''} onChange={(e) => set('company', e.target.value)} placeholder={asPlaceholder(merged?.company)} />
        </div>
        <div className="form-field">
          <label>封面强调色 cover_accent_color（跟管控台配色统一时用）</label>
          <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
            <input type="color" style={{ width: 44, padding: 2, height: 36 }} value={effectiveAccent} onChange={(e) => set('cover_accent_color', e.target.value)} />
            <input type="text" value={raw.cover_accent_color || ''} onChange={(e) => set('cover_accent_color', e.target.value)} placeholder={asPlaceholder(merged?.cover_accent_color) || '#222222'} style={{ flex: 1 }} />
          </div>
        </div>
        <div className="form-field">
          <label>封面停留秒数 cover_duration</label>
          <input type="number" value={raw.cover_duration ?? ''} onChange={(e) => set('cover_duration', +e.target.value)} placeholder={String(merged?.cover_duration ?? 3)} />
        </div>
        <div className="form-field">
          <label>Logo 路径（相对项目根目录，留空自动探测 resources/logo.png）</label>
          <input type="text" value={raw.logo || ''} onChange={(e) => set('logo', e.target.value)} placeholder="resources/logo.png" />
        </div>

        <div className="form-field full"><hr style={{ border: 'none', borderTop: '1px solid var(--border)', margin: '4px 0' }} /></div>

        <div className="form-field">
          <label>背景音乐 BGM（默认关闭，勾选并给路径才生效）</label>
          <label style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: '0.85rem', color: 'var(--text)' }}>
            <input type="checkbox" style={{ width: 'auto' }} checked={!!raw.bgm} onChange={(e) => set('bgm', e.target.checked ? (raw.bgm || 'resources/bgm.mp3') : false)} />
            启用 BGM
          </label>
        </div>
        {raw.bgm ? (
          <>
            <div className="form-field">
              <label>BGM 路径</label>
              <input type="text" value={typeof raw.bgm === 'string' ? raw.bgm : ''} onChange={(e) => set('bgm', e.target.value)} placeholder="resources/bgm.mp3" />
            </div>
            <div className="form-field">
              <label>BGM 音量 (0-1)</label>
              <input type="number" step="0.05" min="0" max="1" value={raw.bgm_volume ?? ''} onChange={(e) => set('bgm_volume', +e.target.value)} placeholder="0.15" />
            </div>
          </>
        ) : null}

        <div className="form-field full"><hr style={{ border: 'none', borderTop: '1px solid var(--border)', margin: '4px 0' }} /></div>

        <div className="form-field">
          <label>字幕字号 font_size</label>
          <input type="number" value={style.font_size} onChange={(e) => set('subtitle_style.font_size', +e.target.value)} />
        </div>
        <div className="form-field">
          <label>字幕下边距 margin_v</label>
          <input type="number" value={style.margin_v} onChange={(e) => set('subtitle_style.margin_v', +e.target.value)} />
        </div>
        <div className="form-field">
          <label>字幕颜色</label>
          <input
            type="color"
            value={assToRgbHex(style.color, '#FFFFFF')}
            onChange={(e) => set('subtitle_style.color', rgbHexToAss(e.target.value))}
          />
        </div>
        <div className="form-field">
          <label>描边颜色</label>
          <input
            type="color"
            value={assToRgbHex(style.outline, '#000000')}
            onChange={(e) => set('subtitle_style.outline', rgbHexToAss(e.target.value))}
          />
        </div>
        <div className="form-field full">
          <label>字幕实时预览（跟实际烧录效果的字体/字号/颜色/描边是同一套参数，比例仅供参考）</label>
          <div className="subtitle-live-preview">
            <span
              style={{
                fontFamily: `"${style.font_name}"`,
                fontSize: Math.min(style.font_size, 64),
                fontWeight: 700,
                color: assToRgbHex(style.color, '#FFFFFF'),
                WebkitTextStroke: `1px ${assToRgbHex(style.outline, '#000000')}`,
                paintOrder: 'stroke fill',
              }}
            >
              字幕预览 Preview ABC
            </span>
          </div>
        </div>
      </div>
      )}
    </div>
  );
}

// 字体/语音选择器单独拆出来，因为它俩是横向铺满的大网格，跟上面紧凑的两列表单
// 不适合挤在同一个 flex 行里（放一起会被封面预览挤成一条窄栏，卡片全挤在一起）。
// 两个页面（feature 表单、项目设置）都是"紧凑表单 + 封面预览"并排在上面，
// 这个大网格铺满宽度放在最下面。
export function MetaPickers({ raw, merged, set }) {
  const style = { ...EMPTY_STYLE, ...(merged?.subtitle_style || {}), ...(raw.subtitle_style || {}) };
  const effectiveVoice = raw.voice || merged?.voice || 'zh-CN-XiaoxiaoNeural';
  const effectiveVoiceEn = raw.voice_en || merged?.voice_en || 'en-US-AvaNeural';

  return (
    <div>
      <div className="form-field full">
        <label>字幕字体 subtitle_style.font_name（点小图放大看真实渲染效果，点卡片选择）</label>
        <FontPicker value={style.font_name} onChange={(name) => set('subtitle_style.font_name', name)} />
      </div>

      <div className="form-field full" style={{ marginTop: 24 }}>
        <label>中文配音 voice（点击试听）</label>
        <VoicePicker lang="zh" value={effectiveVoice} onChange={(id) => set('voice', id)} />
      </div>
      <div className="form-field full" style={{ marginTop: 16 }}>
        <label>英文配音 voice_en（点击试听，仅英文版视频用得到）</label>
        <VoicePicker lang="en" value={effectiveVoiceEn} onChange={(id) => set('voice_en', id)} />
      </div>
    </div>
  );
}

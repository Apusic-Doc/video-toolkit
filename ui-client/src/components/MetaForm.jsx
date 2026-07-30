import { useEffect, useRef, useState } from 'react';
import { api } from '../api.js';
import FontPicker from './FontPicker.jsx';
import VoicePicker from './VoicePicker.jsx';

const EMPTY_STYLE = { font_name: '', font_size: 44, color: '&H00FFFFFF', outline: '&H00000000', margin_v: 45 };

// meta_defaults() 里 subtitle 的内置默认值其实是个 {mode,burn} 对象（字幕生成模式配置），
// 跟"封面副标题文案"这个字符串用途的 subtitle 撞了同一个 key——只有当某 feature 自己
// 没设置字符串副标题时，merged 出来的 subtitle 才会是这个对象，直接当 placeholder 用
// 会在输入框里显示 "[object Object]"，这里做个防御性过滤。
function asPlaceholder(v) {
  return typeof v === 'string' ? v : '';
}

export default function MetaForm({ project, feature, onToast }) {
  const [raw, setRaw] = useState(null);
  const [merged, setMerged] = useState(null);
  const [saving, setSaving] = useState(false);
  const [coverUrl, setCoverUrl] = useState(null);
  const previewTimer = useRef(null);

  useEffect(() => {
    let cancelled = false;
    setRaw(null);
    api.meta(project, feature).then(({ raw, merged }) => {
      if (cancelled) return;
      setRaw({ subtitle_style: {}, ...raw });
      setMerged(merged);
    }).catch(() => {
      // project/feature 切换太快时，上一个组合的请求可能落在新 project 已经
      // 不存在这个 feature 的窗口期里，属于正常竞态，不用报错打扰用户
    });
    return () => { cancelled = true; };
  }, [project, feature]);

  useEffect(() => {
    if (!raw) return;
    clearTimeout(previewTimer.current);
    previewTimer.current = setTimeout(() => refreshCover(), 400);
    return () => clearTimeout(previewTimer.current);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [raw?.title, raw?.subtitle, raw?.company, raw?.cover_accent_color, raw?.logo]);

  async function refreshCover() {
    if (!raw?.title && !merged?.title) return;
    try {
      const res = await fetch(api.previewCoverUrl(project, feature), {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(raw),
      });
      if (!res.ok) return;
      const blob = await res.blob();
      setCoverUrl((old) => { if (old) URL.revokeObjectURL(old); return URL.createObjectURL(blob); });
    } catch {}
  }

  function set(path, value) {
    setRaw((prev) => {
      const next = { ...prev };
      if (path.includes('.')) {
        const [a, b] = path.split('.');
        next[a] = { ...(prev[a] || {}), [b]: value };
      } else {
        next[path] = value;
      }
      return next;
    });
  }

  async function save() {
    setSaving(true);
    try {
      // 空字符串/空 style 不落盘成噪音字段
      const clean = { ...raw };
      if (clean.subtitle_style && Object.values(clean.subtitle_style).every((v) => v === '' || v == null)) {
        delete clean.subtitle_style;
      }
      for (const k of Object.keys(clean)) if (clean[k] === '') delete clean[k];
      await api.saveMeta(project, feature, clean);
      onToast('已保存', 'ok');
    } catch (e) {
      onToast(`保存失败: ${e.message}`, 'err');
    } finally {
      setSaving(false);
    }
  }

  if (!raw) return <div className="empty-state">加载中…</div>;
  const style = { ...EMPTY_STYLE, ...(raw.subtitle_style || {}) };

  return (
    <div>
      <div style={{ display: 'flex', gap: 32, flexWrap: 'wrap' }}>
        <div className="form-grid" style={{ flex: 1, minWidth: 320 }}>
          <div className="form-field">
            <label>标题 title</label>
            <input type="text" value={raw.title || ''} onChange={(e) => set('title', e.target.value)} placeholder={asPlaceholder(merged?.title)} />
          </div>
          <div className="form-field">
            <label>副标题 subtitle</label>
            <input type="text" value={raw.subtitle || ''} onChange={(e) => set('subtitle', e.target.value)} placeholder={asPlaceholder(merged?.subtitle)} />
          </div>
          <div className="form-field">
            <label>公司名 company（留空用项目级默认）</label>
            <input type="text" value={raw.company || ''} onChange={(e) => set('company', e.target.value)} placeholder={asPlaceholder(merged?.company)} />
          </div>
          <div className="form-field">
            <label>封面强调色 cover_accent_color（跟管控台配色统一时用）</label>
            <input type="text" value={raw.cover_accent_color || ''} onChange={(e) => set('cover_accent_color', e.target.value)} placeholder="#222222" />
          </div>
          <div className="form-field">
            <label>封面停留秒数 cover_duration</label>
            <input type="number" value={raw.cover_duration ?? ''} onChange={(e) => set('cover_duration', +e.target.value)} placeholder="3" />
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
            <label>字幕颜色 (ASS &amp;HAABBGGRR 格式)</label>
            <input type="text" value={style.color} onChange={(e) => set('subtitle_style.color', e.target.value)} />
          </div>
          <div className="form-field">
            <label>描边颜色 (ASS &amp;HAABBGGRR 格式)</label>
            <input type="text" value={style.outline} onChange={(e) => set('subtitle_style.outline', e.target.value)} />
          </div>
        </div>

        <div>
          <label style={{ fontSize: '0.8rem', color: 'var(--text2)', display: 'block', marginBottom: 8 }}>封面实时预览</label>
          <div className="cover-preview">
            {coverUrl ? <img src={coverUrl} alt="cover preview" /> : <span style={{ color: '#999' }}>填写标题后自动预览</span>}
          </div>
        </div>
      </div>

      <div className="form-field full" style={{ marginTop: 24 }}>
        <label>字幕字体 subtitle_style.font_name（点击选择，图片是真实渲染效果）</label>
        <FontPicker value={style.font_name} onChange={(name) => set('subtitle_style.font_name', name)} />
      </div>

      <div className="form-field full" style={{ marginTop: 24 }}>
        <label>中文配音 voice（点击试听）</label>
        <VoicePicker lang="zh" value={raw.voice} onChange={(id) => set('voice', id)} />
      </div>
      <div className="form-field full" style={{ marginTop: 16 }}>
        <label>英文配音 voice_en（点击试听，仅英文版视频用得到）</label>
        <VoicePicker lang="en" value={raw.voice_en} onChange={(id) => set('voice_en', id)} />
      </div>

      <div className="form-actions">
        <button className="btn btn-pri" onClick={save} disabled={saving}>{saving ? '保存中…' : '保存 meta.json'}</button>
      </div>
    </div>
  );
}

import { useEffect, useRef, useState } from 'react';
import { api } from '../api.js';
import MetaFields, { MetaPickers } from './MetaFields.jsx';

// 项目级 meta.json——字体/字号/语音/封面配色这些"整个项目该统一"的设置放这里，
// 单个 feature 没覆盖就会继承这里的值（三级合并：内置默认 → 这里 → feature 自己的 meta.json）。
export default function ProjectSettings({ project, onClose, onToast }) {
  const [raw, setRaw] = useState(null);
  const [coverUrl, setCoverUrl] = useState(null);
  const [saving, setSaving] = useState(false);
  const previewTimer = useRef(null);

  useEffect(() => {
    setRaw(null);
    api.projectMeta(project).then(({ raw }) => setRaw({ subtitle_style: {}, ...raw }));
  }, [project]);

  useEffect(() => {
    if (!raw) return;
    clearTimeout(previewTimer.current);
    previewTimer.current = setTimeout(() => refreshCover(), 400);
    return () => clearTimeout(previewTimer.current);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [raw?.company, raw?.cover_accent_color, raw?.logo]);

  async function refreshCover() {
    try {
      const res = await fetch(api.projectPreviewCoverUrl(project), {
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
      const clean = { ...raw };
      if (clean.subtitle_style && Object.values(clean.subtitle_style).every((v) => v === '' || v == null)) {
        delete clean.subtitle_style;
      }
      for (const k of Object.keys(clean)) if (clean[k] === '') delete clean[k];
      await api.saveProjectMeta(project, clean);
      onToast('项目设置已保存', 'ok');
    } catch (e) {
      onToast(`保存失败: ${e.message}`, 'err');
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-box" style={{ width: 880, maxHeight: '85vh', overflowY: 'auto', textAlign: 'left' }} onClick={(e) => e.stopPropagation()}>
        <h1 style={{ fontSize: '1.1rem', margin: '0 0 4px' }}>项目设置 · {project}</h1>
        <p style={{ color: 'var(--text2)', fontSize: '0.82rem', margin: '0 0 20px' }}>
          这里改的是整个项目统一的默认值（字体/字号/语音/封面配色等），单个 feature 没有单独设置时就会用这里的。
        </p>

        {!raw ? <div className="empty-state">加载中…</div> : (
          <>
            <MetaFields raw={raw} merged={null} set={set} showContent={false} />

            <div style={{ marginTop: 20 }}>
              <label style={{ fontSize: '0.8rem', color: 'var(--text2)', display: 'block', marginBottom: 8 }}>封面样式预览（示例文案）</label>
              <div className="cover-preview" style={{ maxWidth: 640 }}>
                {coverUrl ? <img src={coverUrl} alt="cover preview" /> : <span style={{ color: '#999' }}>加载中…</span>}
              </div>
            </div>

            <div style={{ marginTop: 24 }}>
              <MetaPickers raw={raw} merged={null} set={set} />
            </div>

            <div className="form-actions" style={{ justifyContent: 'space-between' }}>
              <button className="btn" onClick={onClose}>关闭</button>
              <button className="btn btn-pri" onClick={save} disabled={saving}>{saving ? '保存中…' : '保存项目设置'}</button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}

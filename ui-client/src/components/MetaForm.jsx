import { useEffect, useRef, useState } from 'react';
import { api } from '../api.js';
import MetaFields, { MetaPickers } from './MetaFields.jsx';

export default function MetaForm({ project, feature, onToast }) {
  const [raw, setRaw] = useState(null);
  const [merged, setMerged] = useState(null);
  const [saving, setSaving] = useState(false);
  const [coverUrl, setCoverUrl] = useState(null);
  const [advanced, setAdvanced] = useState(false);
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

  return (
    <div>
      <div style={{ display: 'flex', gap: 32, flexWrap: 'wrap', alignItems: 'flex-start' }}>
        <div style={{ flex: 1, minWidth: 320 }}>
          <MetaFields raw={raw} merged={merged} set={set} showContent advanced={advanced} />
        </div>
        <div>
          <label style={{ fontSize: '0.8rem', color: 'var(--text2)', display: 'block', marginBottom: 8 }}>封面实时预览</label>
          <div className="cover-preview">
            {coverUrl ? <img src={coverUrl} alt="cover preview" /> : <span style={{ color: '#999' }}>填写标题后自动预览</span>}
          </div>
        </div>
      </div>

      <button className="btn btn-sm" style={{ marginTop: 16 }} onClick={() => setAdvanced((v) => !v)}>
        {advanced ? '▾ 收起高级设置' : '▸ 高级设置（字体/语音/配色/BGM，正常项目该在"项目设置"里统一配）'}
      </button>

      {advanced && (
        <div style={{ marginTop: 16 }}>
          <MetaPickers raw={raw} merged={merged} set={set} />
        </div>
      )}

      <div className="form-actions">
        <button className="btn btn-pri" onClick={save} disabled={saving}>{saving ? '保存中…' : '保存 meta.json'}</button>
      </div>
    </div>
  );
}

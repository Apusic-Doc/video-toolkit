import { useEffect, useState } from 'react';
import { api } from '../api.js';

function emptyCue() {
  return { start: '00:00:00,000', end: '00:00:03,000', text: '' };
}

export default function SubtitleEditor({ project, feature, onToast, onRunTask }) {
  const [cues, setCues] = useState(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    setCues(null);
    api.subtitles(project, feature).then((d) => setCues(d.cues)).catch(() => setCues([]));
  }, [project, feature]);

  function update(i, key, value) {
    setCues((prev) => prev.map((c, idx) => (idx === i ? { ...c, [key]: value } : c)));
  }
  function removeRow(i) {
    setCues((prev) => prev.filter((_, idx) => idx !== i));
  }
  function addRow() {
    setCues((prev) => [...prev, emptyCue()]);
  }

  async function save(andRedub) {
    setSaving(true);
    try {
      await api.saveSubtitles(project, feature, cues);
      onToast('字幕已保存', 'ok');
      if (andRedub) onRunTask('redub');
    } catch (e) {
      onToast(`保存失败: ${e.message}`, 'err');
    } finally {
      setSaving(false);
    }
  }

  if (!cues) return <div className="empty-state">加载中…</div>;

  return (
    <div>
      <table className="srt-table">
        <thead>
          <tr>
            <th className="idx-col">#</th>
            <th className="ts-col">开始</th>
            <th className="ts-col">结束</th>
            <th>文案</th>
            <th className="del-col"></th>
          </tr>
        </thead>
        <tbody>
          {cues.map((c, i) => (
            <tr key={i}>
              <td className="idx-col">{i + 1}</td>
              <td><input value={c.start} onChange={(e) => update(i, 'start', e.target.value)} /></td>
              <td><input value={c.end} onChange={(e) => update(i, 'end', e.target.value)} /></td>
              <td><textarea rows={1} value={c.text} onChange={(e) => update(i, 'text', e.target.value)} /></td>
              <td><button className="btn btn-sm" onClick={() => removeRow(i)} title="删除">✕</button></td>
            </tr>
          ))}
        </tbody>
      </table>

      <div className="form-actions">
        <button className="btn" onClick={addRow}>+ 新增一行</button>
        <button className="btn btn-pri" onClick={() => save(false)} disabled={saving}>{saving ? '保存中…' : '保存字幕'}</button>
        <button className="btn" onClick={() => save(true)} disabled={saving}>保存并重新配音合成（vt redub）</button>
      </div>
    </div>
  );
}

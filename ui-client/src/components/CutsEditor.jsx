import { useEffect, useRef, useState } from 'react';
import { api } from '../api.js';

function emptyCut() {
  return { start: '00:00:00', end: '00:00:03' };
}

function formatTimestamp(seconds) {
  const total = Math.max(0, seconds);
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}:${s.toFixed(3).padStart(6, '0')}`;
}

// 剪辑对象是最终成片（.mp4 / -sub.mp4 / -no-cover.mp4...），不是原始录屏——
// 预览优先选跟 vt recut 实际会处理的是同一份文件，方便对着时间轴找区间
function previewFile(feature, status) {
  if (status?.subMp4) return `${feature}-sub.mp4`;
  if (status?.mp4) return `${feature}.mp4`;
  return null;
}

export default function CutsEditor({ project, feature, status, onToast, onRunTask }) {
  const [cuts, setCuts] = useState(null);
  const [saving, setSaving] = useState(false);
  const videoRef = useRef(null);

  useEffect(() => {
    setCuts(null);
    api.cuts(project, feature).then((d) => setCuts(d.cuts)).catch(() => setCuts([]));
  }, [project, feature]);

  function update(i, key, value) {
    setCuts((prev) => prev.map((c, idx) => (idx === i ? { ...c, [key]: value } : c)));
  }
  function removeRow(i) {
    setCuts((prev) => prev.filter((_, idx) => idx !== i));
  }
  function addRow() {
    setCuts((prev) => [...prev, emptyCut()]);
  }
  function fillFromPlayhead(i, key) {
    if (!videoRef.current) return;
    update(i, key, formatTimestamp(videoRef.current.currentTime));
  }

  async function save(run) {
    setSaving(true);
    try {
      await api.saveCuts(project, feature, cuts);
      onToast('剪辑区间已保存', 'ok');
      if (run) onRunTask('recut');
    } catch (e) {
      onToast(`保存失败: ${e.message}`, 'err');
    } finally {
      setSaving(false);
    }
  }

  if (!cuts) return <div className="empty-state">加载中…</div>;

  const file = previewFile(feature, status);

  return (
    <div>
      <p style={{ color: 'var(--text2)', fontSize: '0.85rem', marginBottom: 14 }}>
        列出要从最终成片里去掉的时间区间（比如念白之间的长停顿）。提交后会先把当前成片备份到{' '}
        <code>backups/</code>，再生成剪掉这些区间的新版本——原文件名不变，随时可以从备份找回。
      </p>

      {file ? (
        <video
          ref={videoRef}
          key={file}
          controls
          style={{ marginBottom: 16, maxWidth: '100%' }}
          src={api.fileUrl(project, feature, file)}
        />
      ) : (
        <div className="empty-state" style={{ marginBottom: 16 }}>还没有成片，先跑一次合成再来剪辑</div>
      )}

      <table className="srt-table">
        <thead>
          <tr>
            <th className="idx-col">#</th>
            <th className="ts-col">开始</th>
            <th className="ts-col">结束</th>
            <th className="del-col"></th>
          </tr>
        </thead>
        <tbody>
          {cuts.map((c, i) => (
            <tr key={i}>
              <td className="idx-col">{i + 1}</td>
              <td>
                <input value={c.start} onChange={(e) => update(i, 'start', e.target.value)} />
                {file && <button className="btn btn-sm" title="用当前播放位置填入" onClick={() => fillFromPlayhead(i, 'start')}>⏱</button>}
              </td>
              <td>
                <input value={c.end} onChange={(e) => update(i, 'end', e.target.value)} />
                {file && <button className="btn btn-sm" title="用当前播放位置填入" onClick={() => fillFromPlayhead(i, 'end')}>⏱</button>}
              </td>
              <td><button className="btn btn-sm" onClick={() => removeRow(i)} title="删除">✕</button></td>
            </tr>
          ))}
          {cuts.length === 0 && (
            <tr><td colSpan={4} style={{ color: 'var(--text3)', textAlign: 'center', padding: '12px 0' }}>还没有要剪的区间</td></tr>
          )}
        </tbody>
      </table>

      <div className="form-actions">
        <button className="btn" onClick={addRow}>+ 新增区间</button>
        <button className="btn" onClick={() => save(false)} disabled={saving}>{saving ? '保存中…' : '仅保存区间'}</button>
        <button className="btn btn-pri" onClick={() => save(true)} disabled={saving || cuts.length === 0}>
          保存并剪辑（先备份再生成新成片）
        </button>
      </div>
    </div>
  );
}

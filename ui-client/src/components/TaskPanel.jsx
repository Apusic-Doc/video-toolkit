import { useEffect, useRef, useState } from 'react';
import { api, openTaskSocket } from '../api.js';

const COMMANDS = [
  { cmd: 'record', label: '录制（本机专用）', desc: '真实操控本机屏幕，只允许本机/内网触发' },
  { cmd: 'redub', label: '重新配音+合成', desc: '改完字幕/meta 后最常用，复用已有录屏' },
  { cmd: 'dub', label: '仅生成配音' },
  { cmd: 'mix', label: '仅合成视频' },
  { cmd: 'burn', label: '烧录字幕' },
  { cmd: 'srt', label: '提取字幕' },
  { cmd: 'all', label: '全流程 (srt→dub→合成)' },
  { cmd: 'status', label: '检查文件状态' },
];

export default function TaskPanel({ project, feature, status, onToast, runSignal }) {
  const [lines, setLines] = useState([]);
  const [running, setRunning] = useState(false);
  const [history, setHistory] = useState([]);
  const wsRef = useRef(null);
  const logRef = useRef(null);

  useEffect(() => {
    api.tasks(project, feature).then(setHistory).catch(() => {});
    const ws = openTaskSocket(project, feature, (msg) => {
      if (msg.type === 'log') {
        setLines((prev) => [...prev, msg.line]);
      } else if (msg.type === 'status') {
        setRunning(msg.status === 'running');
        if (msg.status !== 'running') api.tasks(project, feature).then(setHistory).catch(() => {});
      }
    });
    wsRef.current = ws;
    return () => ws.close();
  }, [project, feature]);

  useEffect(() => {
    if (logRef.current) logRef.current.scrollTop = logRef.current.scrollHeight;
  }, [lines]);

  async function run(cmd) {
    setLines([]);
    setRunning(true);
    try {
      await api.runTask(project, feature, cmd);
    } catch (e) {
      onToast(`启动失败: ${e.message}`, 'err');
      setRunning(false);
    }
  }

  // 供外部（字幕页的"保存并重新合成"按钮）触发任务
  useEffect(() => {
    if (runSignal) run(runSignal.cmd);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [runSignal]);

  const previewFile = status?.subMp4 ? `${feature}-sub.mp4` : (status?.mp4 ? `${feature}.mp4` : (status?.recording ? 'recording.mov' : null));

  function lineClass(l) {
    if (l.includes('✅') || l.includes('passed')) return 'ok';
    if (l.includes('❌') || l.includes('Error') || l.includes('失败')) return 'err';
    if (l.includes('⚠')) return 'warn';
    return '';
  }

  return (
    <div>
      <div className="task-buttons">
        {COMMANDS.map((c) => (
          <button key={c.cmd} className="btn" title={c.desc} disabled={running} onClick={() => run(c.cmd)}>
            {running ? '运行中…' : c.label}
          </button>
        ))}
      </div>

      <div className="log-panel" ref={logRef}>
        {lines.length === 0 && !running && <span style={{ color: 'var(--text3)' }}>还没有运行任务，点上面的按钮开始</span>}
        {lines.map((l, i) => <div key={i} className={`log-line ${lineClass(l)}`}>{l}</div>)}
      </div>

      {previewFile && (
        <div style={{ marginTop: 20 }}>
          <label style={{ fontSize: '0.8rem', color: 'var(--text2)', display: 'block', marginBottom: 8 }}>
            成片预览（{previewFile}）
          </label>
          <video key={previewFile} controls src={api.fileUrl(project, feature, previewFile)} />
        </div>
      )}

      {history.length > 0 && (
        <div style={{ marginTop: 20 }}>
          <label style={{ fontSize: '0.8rem', color: 'var(--text2)', display: 'block', marginBottom: 8 }}>历史任务</label>
          <table className="srt-table">
            <thead><tr><th>命令</th><th>状态</th><th>时间</th></tr></thead>
            <tbody>
              {history.map((h) => (
                <tr key={h.id}>
                  <td>{h.cmd}</td>
                  <td className={lineClass(h.status === 'done' ? '✅' : h.status === 'failed' ? '❌' : '')}>{h.status}</td>
                  <td>{h.startedAt ? new Date(h.startedAt).toLocaleTimeString() : '-'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

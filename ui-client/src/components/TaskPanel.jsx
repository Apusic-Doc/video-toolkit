import { useEffect, useRef, useState } from 'react';
import { api, openTaskSocket } from '../api.js';
import { useLang } from '../i18n.jsx';

// 常用：录制两步 + "一键生效"（重新配音+合成+烧字幕，串起来跑，改完字幕/meta 后最常用的就是它）+ 状态检查。
// 其余 srt/dub/mix/burn 单独跑、全流程、英文版流水线都是排查问题或者特殊场景才需要，
// 默认收进"高级"，减少正常操作时的选择负担。
const PRIMARY_COMMANDS = [
  { cmd: 'codegen', label: '录制路径（本机专用）', desc: '弹出真实浏览器，手动走一遍管控台操作路径，选择器存到 nav-draft.spec.js，只允许本机/内网触发' },
  { cmd: 'record', label: '录制视频（本机专用）', desc: '真实操控本机屏幕，只允许本机/内网触发' },
  { cmd: ['redub', 'burn'], key: 'redub+burn', label: '一键生效（配音+合成+烧字幕）', desc: '改完字幕/meta 后最常用，复用已有录屏，跑完直接是最终成片' },
  { cmd: 'status', label: '检查文件状态' },
];

const ADVANCED_COMMANDS = [
  { cmd: 'dub', label: '仅生成配音' },
  { cmd: 'mix', label: '仅合成视频（不烧字幕）' },
  { cmd: 'burn', label: '仅烧录字幕' },
  { cmd: 'srt', label: '仅提取字幕' },
  { cmd: 'recut', label: '重新应用剪辑区间', desc: '按"剪辑"tab 里保存的 cuts.json 重新处理一遍最新成片（比如重新 mix/burn 之后要再剪一次）' },
];

const ADVANCED_EN_COMMANDS = [
  { cmd: 'trans', label: '翻译字幕（DeepSeek）' },
  { cmd: 'dub-en', label: '生成英文配音' },
  { cmd: 'mix-en', label: '合成英文视频' },
];

export default function TaskPanel({ project, feature, status, onToast, runSignal, onDeleteFeature }) {
  const { t } = useLang();
  const [lines, setLines] = useState([]);
  const [running, setRunning] = useState(false);
  const [history, setHistory] = useState([]);
  const [previewNonce, setPreviewNonce] = useState(0);
  const [showAdvanced, setShowAdvanced] = useState(false);
  const [confirmingDelete, setConfirmingDelete] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const wsRef = useRef(null);
  const logRef = useRef(null);
  const pendingIds = useRef(new Set());

  useEffect(() => {
    api.tasks(project, feature).then(setHistory).catch(() => {});
    const ws = openTaskSocket(project, feature, (msg) => {
      if (msg.type === 'log') {
        setLines((prev) => [...prev, msg.line]);
      } else if (msg.type === 'status' && msg.status !== 'running') {
        pendingIds.current.delete(msg.id);
        api.tasks(project, feature).then(setHistory).catch(() => {});
        // 任务跑完文件内容可能变了（比如重新烧字幕），视频/音频这些浏览器会按文件名缓存，
        // 文件名没变浏览器不一定会重新拉——用一个递增的 query 参数强制换新
        setPreviewNonce((n) => n + 1);
        if (pendingIds.current.size === 0) setRunning(false);
      }
    });
    wsRef.current = ws;
    setConfirmingDelete(false);
    return () => ws.close();
  }, [project, feature]);

  async function confirmDelete() {
    setDeleting(true);
    try {
      await onDeleteFeature();
    } catch (e) {
      onToast(`${e.message}`, 'err');
      setDeleting(false);
    }
  }

  useEffect(() => {
    if (logRef.current) logRef.current.scrollTop = logRef.current.scrollHeight;
  }, [lines]);

  // cmds 可以是单个命令，也可以是一串按顺序执行的命令（比如"重新配音→重新烧字幕"）——
  // 后端本来就按 feature 串行排队，这里依次提交就行，不用等上一个真的跑完再交下一个
  async function run(cmds) {
    const list = Array.isArray(cmds) ? cmds : [cmds];
    setLines([]);
    setRunning(true);
    pendingIds.current = new Set();
    try {
      for (const cmd of list) {
        const { id } = await api.runTask(project, feature, cmd);
        pendingIds.current.add(id);
      }
    } catch (e) {
      onToast(`启动失败: ${e.message}`, 'err');
      setRunning(false);
    }
  }

  // 供外部（字幕页的"保存并生效"按钮）触发任务
  useEffect(() => {
    if (runSignal) run(runSignal.cmd);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [runSignal]);

  const videoPreviewFile = status?.subMp4 ? `${feature}-sub.mp4` : (status?.mp4 ? `${feature}.mp4` : (status?.recording ? 'recording.mov' : null));
  const enVideoPreviewFile = status?.mp4En ? `${feature}_en.mp4` : null;

  function lineClass(l) {
    if (l.includes('✅') || l.includes('passed')) return 'ok';
    if (l.includes('❌') || l.includes('Error') || l.includes('失败')) return 'err';
    if (l.includes('⚠')) return 'warn';
    return '';
  }

  function renderButtons(list) {
    return list.map((c) => (
      <button key={c.key || c.cmd} className="btn" title={c.desc} disabled={running} onClick={() => run(c.cmd)}>
        {running ? '运行中…' : c.label}
      </button>
    ));
  }

  return (
    <div>
      <div className="task-buttons">{renderButtons(PRIMARY_COMMANDS)}</div>

      <button className="btn btn-sm" style={{ marginTop: 4, marginBottom: 12 }} onClick={() => setShowAdvanced((v) => !v)}>
        {showAdvanced ? '▾ 收起高级操作' : '▸ 高级操作（单步命令 / 英文版流水线）'}
      </button>

      {showAdvanced && (
        <div style={{ marginBottom: 16 }}>
          <div className="task-buttons">{renderButtons(ADVANCED_COMMANDS)}</div>
          <label style={{ fontSize: '0.78rem', color: 'var(--text3)', display: 'block', margin: '10px 0 6px' }}>英文版</label>
          <div className="task-buttons">{renderButtons(ADVANCED_EN_COMMANDS)}</div>

          <div style={{ marginTop: 20, padding: 14, border: '1px solid var(--red)', borderRadius: 'var(--radius-sm)' }}>
            <label style={{ fontSize: '0.78rem', color: 'var(--red)', display: 'block', marginBottom: 6, fontWeight: 700 }}>
              {t('danger_zone')}
            </label>
            <p style={{ fontSize: '0.8rem', color: 'var(--text2)', margin: '0 0 10px' }}>{t('danger_zone_desc')}</p>
            {!confirmingDelete ? (
              <button className="btn btn-sm" style={{ borderColor: 'var(--red)', color: 'var(--red)' }} onClick={() => setConfirmingDelete(true)}>
                {t('btn_delete_feature')}
              </button>
            ) : (
              <div style={{ display: 'flex', gap: 8 }}>
                <button className="btn btn-sm" onClick={() => setConfirmingDelete(false)} disabled={deleting}>{t('btn_cancel')}</button>
                <button
                  className="btn btn-sm" style={{ background: 'var(--red)', color: '#fff', borderColor: 'var(--red)' }}
                  onClick={confirmDelete} disabled={deleting}
                >
                  {deleting ? t('saving') : t('btn_confirm_delete')}
                </button>
              </div>
            )}
          </div>
        </div>
      )}

      <div className="log-panel" ref={logRef}>
        {lines.length === 0 && !running && <span style={{ color: 'var(--text3)' }}>还没有运行任务，点上面的按钮开始</span>}
        {lines.map((l, i) => <div key={i} className={`log-line ${lineClass(l)}`}>{l}</div>)}
      </div>

      {status?.dub && (
        <div style={{ marginTop: 20 }}>
          <label style={{ fontSize: '0.8rem', color: 'var(--text2)', display: 'block', marginBottom: 8 }}>
            配音预览（ai_dub.wav，只做了配音这一步也能直接听，不用等合成视频）
          </label>
          <audio controls src={`${api.fileUrl(project, feature, 'ai_dub.wav')}?v=${previewNonce}`} />
        </div>
      )}

      {videoPreviewFile && (
        <div style={{ marginTop: 20 }}>
          <label style={{ fontSize: '0.8rem', color: 'var(--text2)', display: 'block', marginBottom: 8 }}>
            成片预览（{videoPreviewFile}）
          </label>
          <video key={videoPreviewFile} controls src={`${api.fileUrl(project, feature, videoPreviewFile)}?v=${previewNonce}`} />
        </div>
      )}

      {showAdvanced && (status?.dubEn || enVideoPreviewFile) && (
        <div style={{ marginTop: 20 }}>
          <label style={{ fontSize: '0.8rem', color: 'var(--text2)', display: 'block', marginBottom: 8 }}>英文版预览</label>
          {status?.dubEn && (
            <div style={{ marginBottom: 10 }}>
              <div style={{ fontSize: '0.78rem', color: 'var(--text3)', marginBottom: 4 }}>ai_dub_en.wav</div>
              <audio controls src={`${api.fileUrl(project, feature, 'ai_dub_en.wav')}?v=${previewNonce}`} />
            </div>
          )}
          {enVideoPreviewFile && (
            <div>
              <div style={{ fontSize: '0.78rem', color: 'var(--text3)', marginBottom: 4 }}>{enVideoPreviewFile}</div>
              <video key={enVideoPreviewFile} controls src={`${api.fileUrl(project, feature, enVideoPreviewFile)}?v=${previewNonce}`} />
            </div>
          )}
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

function statusGroup(f) {
  if (f.subMp4) return '已完成';
  if (f.mp4) return '已合成';
  if (f.recording) return '已录制';
  return '未开始';
}
const GROUP_ORDER = ['已完成', '已合成', '已录制', '未开始'];

export default function Sidebar({ projects, project, onProject, features, selected, onSelect, onOpenProjectSettings }) {
  const groups = {};
  for (const f of features) {
    const g = statusGroup(f);
    (groups[g] ||= []).push(f);
  }

  return (
    <div className="sidebar">
      <div className="sidebar-header">
        <h1>video-toolkit</h1>
        <select value={project} onChange={(e) => onProject(e.target.value)}>
          {projects.map((p) => <option key={p.name} value={p.name}>{p.name}</option>)}
        </select>
        <button className="btn btn-sm" style={{ width: '100%', justifyContent: 'center', marginTop: 8 }} onClick={onOpenProjectSettings}>
          ⚙ 项目设置（字体/语音/封面统一样式）
        </button>
      </div>
      <div className="feature-list">
        {GROUP_ORDER.filter((g) => groups[g]?.length).map((g) => (
          <div key={g}>
            <div className="feature-group-label">{g}（{groups[g].length}）</div>
            {groups[g].map((f) => (
              <div
                key={f.name}
                className={`feature-item${selected === f.name ? ' active' : ''}`}
                onClick={() => onSelect(f.name)}
              >
                <div className="title">{f.title || f.name}</div>
                <div className="name">{f.name}</div>
                <div className="status-dots" title="录制 / 字幕 / 配音 / 成片">
                  <span className={`status-dot${f.recording ? ' on' : ''}`} />
                  <span className={`status-dot${f.subtitles ? ' on' : ''}`} />
                  <span className={`status-dot${f.dub ? ' on' : ''}`} />
                  <span className={`status-dot${f.subMp4 ? ' on' : ''}`} />
                </div>
              </div>
            ))}
          </div>
        ))}
        {features.length === 0 && <div className="feature-group-label">这个项目下还没有 feature</div>}
      </div>
    </div>
  );
}

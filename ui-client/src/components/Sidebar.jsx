import { useLang } from '../i18n.jsx';

function statusGroup(f) {
  if (f.subMp4) return 'status_done';
  if (f.mp4) return 'status_mixed';
  if (f.recording) return 'status_recorded';
  return 'status_none';
}
const GROUP_ORDER = ['status_done', 'status_mixed', 'status_recorded', 'status_none'];

export default function Sidebar({ features, selected, onSelect, onNewFeature }) {
  const { t } = useLang();
  const groups = {};
  for (const f of features) {
    const g = statusGroup(f);
    (groups[g] ||= []).push(f);
  }

  return (
    <div className="sidebar">
      <div className="sidebar-header">
        <button className="btn btn-sm btn-pri" style={{ width: '100%', justifyContent: 'center' }} onClick={onNewFeature}>
          {t('sidebar_new_feature')}
        </button>
      </div>
      <div className="feature-list">
        {GROUP_ORDER.filter((g) => groups[g]?.length).map((g) => (
          <div key={g}>
            <div className="feature-group-label">{t(g)}（{groups[g].length}）</div>
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
        {features.length === 0 && <div className="feature-group-label">{t('sidebar_empty')}</div>}
      </div>
    </div>
  );
}

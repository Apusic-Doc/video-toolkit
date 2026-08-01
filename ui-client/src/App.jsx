import { useEffect, useState } from 'react';
import { api, AuthError } from './api.js';
import Login from './components/Login.jsx';
import Sidebar from './components/Sidebar.jsx';
import MetaForm from './components/MetaForm.jsx';
import SubtitleEditor from './components/SubtitleEditor.jsx';
import CutsEditor from './components/CutsEditor.jsx';
import TaskPanel from './components/TaskPanel.jsx';
import ReadmeView from './components/ReadmeView.jsx';
import ProjectSettings from './components/ProjectSettings.jsx';

const TABS = [
  { id: 'meta', label: '封面 / 配置' },
  { id: 'subtitles', label: '字幕' },
  { id: 'cuts', label: '剪辑' },
  { id: 'tasks', label: '任务 / 预览' },
  { id: 'readme', label: '说明' },
];

function useQueryParam(name) {
  const p = new URLSearchParams(location.search);
  return p.get(name);
}

export default function App() {
  const [authState, setAuthState] = useState('checking'); // checking | need-login | denied | ok
  const [projects, setProjects] = useState([]);
  const [project, setProject] = useState('');
  const [features, setFeatures] = useState([]);
  const [selected, setSelected] = useState(useQueryParam('feature') || '');
  const [tab, setTab] = useState('meta');
  const [toast, setToast] = useState(null);
  const [runSignal, setRunSignal] = useState(null);
  const [showProjectSettings, setShowProjectSettings] = useState(false);

  useEffect(() => {
    api.session().then((s) => {
      if (s.status === 'ok') setAuthState('ok');
      else if (s.status === 'no-password-remote-denied') setAuthState('denied');
      else setAuthState('need-login');
    });
  }, []);

  useEffect(() => {
    if (authState !== 'ok') return;
    api.projects().then((ps) => {
      setProjects(ps);
      const initial = useQueryParam('project');
      setProject(initial && ps.some((p) => p.name === initial) ? initial : ps[0]?.name || '');
    });
  }, [authState]);

  useEffect(() => {
    if (!project) return;
    api.features(project).then((fs) => {
      setFeatures(fs);
      setSelected((prev) => (prev && fs.some((f) => f.name === prev) ? prev : fs[0]?.name || ''));
    }).catch((e) => { if (e instanceof AuthError) setAuthState('need-login'); });
  }, [project]);

  function showToast(text, kind) {
    setToast({ text, kind });
    setTimeout(() => setToast(null), 3000);
  }

  if (authState === 'checking') return null;
  if (authState === 'need-login') return <Login onLoggedIn={() => setAuthState('ok')} />;
  if (authState === 'denied') {
    return (
      <div className="login-screen">
        <div className="login-box">
          <h1>访问受限</h1>
          <p style={{ color: 'var(--text2)', fontSize: '0.85rem' }}>
            服务端未配置密码，仅允许本机访问。如需远程/公网访问，请先设置 VT_UI_PASSWORD 环境变量。
          </p>
        </div>
      </div>
    );
  }

  const selectedFeature = features.find((f) => f.name === selected);

  return (
    <div className="app">
      <Sidebar
        projects={projects} project={project} onProject={setProject}
        features={features} selected={selected} onSelect={setSelected}
        onOpenProjectSettings={() => setShowProjectSettings(true)}
      />
      <div className="main">
        {selectedFeature ? (
          <>
            <div className="main-header">
              <div>
                <h2>{selectedFeature.title || selectedFeature.name}</h2>
                <div className="sub">{project} / {selectedFeature.name}</div>
              </div>
            </div>
            <div className="tabs">
              {TABS.map((t) => (
                <div key={t.id} className={`tab${tab === t.id ? ' active' : ''}`} onClick={() => setTab(t.id)}>
                  {t.label}
                </div>
              ))}
            </div>
            <div className="tab-content">
              {tab === 'meta' && <MetaForm project={project} feature={selected} onToast={showToast} />}
              {tab === 'subtitles' && (
                <SubtitleEditor
                  project={project} feature={selected} onToast={showToast}
                  onRunTask={(cmd) => { setTab('tasks'); setRunSignal({ cmd, ts: Date.now() }); }}
                />
              )}
              {tab === 'cuts' && (
                <CutsEditor
                  project={project} feature={selected} status={selectedFeature} onToast={showToast}
                  onRunTask={(cmd) => { setTab('tasks'); setRunSignal({ cmd, ts: Date.now() }); }}
                />
              )}
              {tab === 'tasks' && (
                <TaskPanel
                  project={project} feature={selected} status={selectedFeature}
                  onToast={showToast} runSignal={runSignal}
                />
              )}
              {tab === 'readme' && <ReadmeView project={project} feature={selected} />}
            </div>
          </>
        ) : (
          <div className="empty-state">左边选一个 feature 开始</div>
        )}
      </div>
      {toast && <div className={`toast ${toast.kind}`}>{toast.text}</div>}
      {showProjectSettings && (
        <ProjectSettings project={project} onClose={() => setShowProjectSettings(false)} onToast={showToast} />
      )}
    </div>
  );
}

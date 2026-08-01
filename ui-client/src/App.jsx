import { useEffect, useState } from 'react';
import { api, AuthError } from './api.js';
import { LangProvider, useLang } from './i18n.jsx';
import Login from './components/Login.jsx';
import NavBar from './components/NavBar.jsx';
import Sidebar from './components/Sidebar.jsx';
import CreateModal from './components/CreateModal.jsx';
import MetaForm from './components/MetaForm.jsx';
import SubtitleEditor from './components/SubtitleEditor.jsx';
import CutsEditor from './components/CutsEditor.jsx';
import TaskPanel from './components/TaskPanel.jsx';
import ReadmeView from './components/ReadmeView.jsx';
import ProjectSettings from './components/ProjectSettings.jsx';
import GroupManager from './components/GroupManager.jsx';

const TAB_KEYS = ['tab_meta', 'tab_subtitles', 'tab_cuts', 'tab_tasks', 'tab_readme'];
const TAB_IDS = ['meta', 'subtitles', 'cuts', 'tasks', 'readme'];

function useQueryParam(name) {
  const p = new URLSearchParams(location.search);
  return p.get(name);
}

const THEME_KEY = 'vt-ui-theme';

export default function App() {
  return (
    <LangProvider>
      <AppInner />
    </LangProvider>
  );
}

function AppInner() {
  const { t } = useLang();
  const [authState, setAuthState] = useState('checking'); // checking | need-login | denied | ok
  const [projects, setProjects] = useState([]);
  const [project, setProject] = useState('');
  const [features, setFeatures] = useState([]);
  const [selected, setSelected] = useState(useQueryParam('feature') || '');
  const [tab, setTab] = useState('meta');
  const [toast, setToast] = useState(null);
  const [runSignal, setRunSignal] = useState(null);
  const [showProjectSettings, setShowProjectSettings] = useState(false);
  const [showGroups, setShowGroups] = useState(false);
  const [showNewProject, setShowNewProject] = useState(false);
  const [showNewFeature, setShowNewFeature] = useState(false);
  const [theme, setTheme] = useState(() => localStorage.getItem(THEME_KEY) || 'light');

  useEffect(() => {
    document.documentElement.setAttribute('data-theme', theme);
    localStorage.setItem(THEME_KEY, theme);
  }, [theme]);

  useEffect(() => {
    api.session().then((s) => {
      if (s.status === 'ok') setAuthState('ok');
      else if (s.status === 'no-password-remote-denied') setAuthState('denied');
      else setAuthState('need-login');
    });
  }, []);

  useEffect(() => {
    if (authState !== 'ok') return;
    refreshProjects();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [authState]);

  useEffect(() => {
    if (!project) return;
    refreshFeatures();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [project]);

  function refreshProjects(preferName) {
    return api.projects().then((ps) => {
      setProjects(ps);
      const initial = preferName || useQueryParam('project');
      setProject((prev) => (initial && ps.some((p) => p.name === initial)) ? initial : (ps.some((p) => p.name === prev) ? prev : ps[0]?.name || ''));
    });
  }

  function refreshFeatures(preferName) {
    return api.features(project).then((fs) => {
      setFeatures(fs);
      setSelected((prev) => {
        const want = preferName ?? prev;
        return fs.some((f) => f.name === want) ? want : fs[0]?.name || '';
      });
    }).catch((e) => { if (e instanceof AuthError) setAuthState('need-login'); });
  }

  function showToast(text, kind) {
    setToast({ text, kind });
    setTimeout(() => setToast(null), 3000);
  }

  async function handleNewProject(name) {
    await api.createProject(name);
    showToast(t('toast_created'), 'ok');
    await refreshProjects(name);
  }

  async function handleNewFeature(slug) {
    const { feature } = await api.createFeature(project, slug);
    showToast(t('toast_created'), 'ok');
    await refreshFeatures(feature);
  }

  async function handleDeleteFeature(name) {
    if (!confirm(t('confirm_delete_feature', name))) return;
    try {
      await api.deleteFeature(project, name);
      showToast(t('toast_deleted'), 'ok');
      await refreshFeatures();
    } catch (e) {
      showToast(`${e.message}`, 'err');
    }
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
  const activePage = showGroups ? 'groups' : showProjectSettings ? 'settings' : 'features';

  function onPage(id) {
    setShowGroups(id === 'groups');
    setShowProjectSettings(id === 'settings');
  }

  return (
    <div className="app">
      <NavBar
        projects={projects} project={project} onProject={setProject}
        onNewProject={() => setShowNewProject(true)}
        page={activePage} onPage={onPage}
        theme={theme} onToggleTheme={() => setTheme((t) => (t === 'dark' ? 'light' : 'dark'))}
      />
      <div className="app-body">
        <Sidebar
          features={features} selected={selected} onSelect={setSelected}
          onNewFeature={() => setShowNewFeature(true)}
          onDeleteFeature={handleDeleteFeature}
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
                {TAB_IDS.map((id, i) => (
                  <div key={id} className={`tab${tab === id ? ' active' : ''}`} onClick={() => setTab(id)}>
                    {t(TAB_KEYS[i])}
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
            <div className="empty-state">{t('empty_pick_feature')}</div>
          )}
        </div>
      </div>

      {toast && <div className={`toast ${toast.kind}`}>{toast.text}</div>}

      {showProjectSettings && (
        <ProjectSettings project={project} onClose={() => setShowProjectSettings(false)} onToast={showToast} />
      )}
      {showGroups && (
        <GroupManager project={project} features={features} onClose={() => setShowGroups(false)} onToast={showToast} />
      )}
      {showNewProject && (
        <CreateModal
          title={t('new_project_title')} placeholder={t('new_project_placeholder')}
          onSubmit={handleNewProject} onClose={() => setShowNewProject(false)}
        />
      )}
      {showNewFeature && (
        <CreateModal
          title={t('new_feature_title')} placeholder={t('new_feature_placeholder')} hint={t('new_feature_hint')}
          onSubmit={handleNewFeature} onClose={() => setShowNewFeature(false)}
        />
      )}
    </div>
  );
}

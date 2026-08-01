import { useEffect, useState } from 'react';
import { api, AuthError } from './api.js';
import { LangProvider, useLang } from './i18n.jsx';
import Login from './components/Login.jsx';
import NavBar from './components/NavBar.jsx';
import Sidebar from './components/Sidebar.jsx';
import NewFeatureModal from './components/NewFeatureModal.jsx';
import NewProjectModal from './components/NewProjectModal.jsx';
import MetaForm from './components/MetaForm.jsx';
import SubtitleEditor from './components/SubtitleEditor.jsx';
import CutsEditor from './components/CutsEditor.jsx';
import TaskPanel from './components/TaskPanel.jsx';
import ReadmeView from './components/ReadmeView.jsx';
import ProjectSettings from './components/ProjectSettings.jsx';
import GroupManager from './components/GroupManager.jsx';
import Dashboard from './components/Dashboard.jsx';
import { applyPalette, clearPaletteOverrides, DEFAULT_PALETTE } from './palettes.js';

const TAB_KEYS = ['tab_meta', 'tab_subtitles', 'tab_cuts', 'tab_tasks', 'tab_readme'];
const TAB_IDS = ['meta', 'subtitles', 'cuts', 'tasks', 'readme'];

function useQueryParam(name) {
  const p = new URLSearchParams(location.search);
  return p.get(name);
}

const THEME_KEY = 'vt-ui-theme';
const PALETTE_KEY = 'vt-ui-palette';
const PROJECT_KEY = 'vt-ui-project';
const FEATURE_KEY = 'vt-ui-feature';
const PAGE_KEY = 'vt-ui-page';

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
  const [project, setProject] = useState(() => useQueryParam('project') || localStorage.getItem(PROJECT_KEY) || '');
  const [features, setFeatures] = useState([]);
  const [selected, setSelected] = useState(useQueryParam('feature') || localStorage.getItem(FEATURE_KEY) || '');
  const [tab, setTab] = useState(() => useQueryParam('tab') || 'meta');
  const [toast, setToast] = useState(null);
  const [runSignal, setRunSignal] = useState(null);
  const [page, setPage] = useState(() => useQueryParam('page') || localStorage.getItem(PAGE_KEY) || 'dashboard');
  const [showProjectSettings, setShowProjectSettings] = useState(false);
  const [showNewProject, setShowNewProject] = useState(false);
  const [showNewFeature, setShowNewFeature] = useState(false);
  const [theme, setTheme] = useState(() => localStorage.getItem(THEME_KEY) || 'light');
  const [palette, setPalette] = useState(() => localStorage.getItem(PALETTE_KEY) || DEFAULT_PALETTE);

  useEffect(() => {
    document.documentElement.setAttribute('data-theme', theme);
    localStorage.setItem(THEME_KEY, theme);
  }, [theme]);

  // 配色方案只覆盖 light 主题的变量——dark 主题没人抱怨过，维持 index.css 里
  // [data-theme="dark"] 原本定义的值，切到 dark 时把 light 方案的内联覆盖清掉
  useEffect(() => {
    if (theme === 'light') applyPalette(palette);
    else clearPaletteOverrides();
    localStorage.setItem(PALETTE_KEY, palette);
  }, [theme, palette]);

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
      const initial = preferName || useQueryParam('project') || localStorage.getItem(PROJECT_KEY);
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

  async function handleNewProject({ slug, displayName }) {
    await api.createProject(slug, displayName);
    showToast(t('toast_created'), 'ok');
    await refreshProjects(slug);
    // 名字/slug 之外的属性（字体/语音/封面统一样式）复用现成的项目设置表单，
    // 建完项目直接接上去，不用另外重复造一份表单
    setShowProjectSettings(true);
    showToast(t('new_project_next_hint'), 'ok');
  }

  async function handleNewFeature({ slug, title, subtitle }) {
    const { feature } = await api.createFeature(project, slug);
    if (title || subtitle) {
      await api.saveMeta(project, feature, { ...(title ? { title } : {}), ...(subtitle ? { subtitle } : {}) });
    }
    showToast(t('toast_created'), 'ok');
    await refreshFeatures(feature);
  }

  // 二次确认是 TaskPanel 里"危险操作"区域自己的两步点击 UI 负责的，这里拿到调用
  // 就是已经确认过了，直接执行
  async function handleDeleteFeature(name) {
    await api.deleteFeature(project, name);
    showToast(t('toast_deleted'), 'ok');
    await refreshFeatures();
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
  // 设置是单个实体的编辑表单，走弹层（跟新建 feature/project 一样的交互）；
  // 分组是一个列表，跟 Dashboard/Features 一样走真正的页面，不是弹层
  const activePage = showProjectSettings ? 'settings' : page;

  function onPage(id) {
    setShowProjectSettings(id === 'settings');
    if (id !== 'settings') setPage(id);
  }

  function openFeatureFromDashboard(name) {
    setSelected(name);
    setPage('features');
  }

  // 记住当前选择的项目/feature/页面，刷新后恢复
  useEffect(() => { if (project) localStorage.setItem(PROJECT_KEY, project); }, [project]);
  useEffect(() => { if (selected) localStorage.setItem(FEATURE_KEY, selected); }, [selected]);
  useEffect(() => { localStorage.setItem(PAGE_KEY, page); }, [page]);

  // 同步状态到 URL（replaceState 不刷新页面），每个项目/feature/页面/标签都有独立 URL
  useEffect(() => {
    const params = new URLSearchParams();
    if (project) params.set('project', project);
    if (selected) params.set('feature', selected);
    if (page !== 'dashboard') params.set('page', page);
    if (tab !== 'meta') params.set('tab', tab);
    const qs = params.toString();
    const url = qs ? `${location.pathname}?${qs}` : location.pathname;
    history.replaceState(null, '', url);
  }, [project, selected, page, tab]);

  // 列表/标题这些"给人看"的地方统一显示项目显示名称，没设置才退回目录名——
  // project 变量本身（slug）继续原样传给各组件当 API 参数，两者不要混用
  const projectLabel = projects.find((p) => p.name === project)?.displayName || project;

  return (
    <div className="app">
      <NavBar
        projects={projects} project={project} onProject={setProject}
        onNewProject={() => setShowNewProject(true)}
        page={activePage} onPage={onPage}
        theme={theme} onToggleTheme={() => setTheme((t) => (t === 'dark' ? 'light' : 'dark'))}
        palette={palette} onPalette={setPalette}
      />
      {page === 'dashboard' ? (
        <div className="page-content">
          <Dashboard
            projects={projects} project={project} onSelectProject={setProject}
            features={features} onOpenFeature={openFeatureFromDashboard}
            onNewProject={() => setShowNewProject(true)} onNewFeature={() => setShowNewFeature(true)}
          />
        </div>
      ) : page === 'groups' ? (
        <div className="page-content">
          <GroupManager project={project} projectLabel={projectLabel} features={features} onToast={showToast} />
        </div>
      ) : (
        <div className="app-body">
          <Sidebar
            features={features} selected={selected} onSelect={setSelected}
            onNewFeature={() => setShowNewFeature(true)}
          />
          <div className="main">
            {selectedFeature ? (
              <>
                <div className="main-header">
                  <div>
                    <h2>{selectedFeature.title || selectedFeature.name}</h2>
                    <div className="sub">{projectLabel} / {selectedFeature.name}</div>
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
                      onDeleteFeature={() => handleDeleteFeature(selected)}
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
      )}

      {toast && <div className={`toast ${toast.kind}`}>{toast.text}</div>}

      {showProjectSettings && (
        <ProjectSettings project={project} onClose={() => setShowProjectSettings(false)} onToast={showToast} />
      )}
      {showNewProject && (
        <NewProjectModal onSubmit={handleNewProject} onClose={() => setShowNewProject(false)} />
      )}
      {showNewFeature && (
        <NewFeatureModal onSubmit={handleNewFeature} onClose={() => setShowNewFeature(false)} />
      )}
    </div>
  );
}

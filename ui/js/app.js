const api = {
  async get(url) {
    try { const r = await fetch(url); if (!r.ok) throw new Error(r.status); return r.json(); }
    catch(e) { console.warn(`API GET ${url} failed:`, e.message); return []; }
  },
  async post(url, data) {
    try { const r = await fetch(url, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(data) }); return r.json(); }
    catch(e) { console.warn(`API POST ${url} failed:`, e.message); return {}; }
  },
  async upload(url, file) { const r = await fetch(`/api/upload/${url}`, { method: "POST", body: file }); return { ok: r.ok }; },
  async del(url) {
    try { await fetch(`/api/features/${encodeURIComponent(url)}/delete`, { method: "POST" }); }
    catch(e) { console.warn(`Delete ${url} failed:`, e.message); }
  }
};

function streamTask(taskId, onLine, onDone) {
  const es = new EventSource(`/api/task/${taskId}`);
  es.onmessage = (e) => { if (e.data.startsWith(":")) return; const m = JSON.parse(e.data); if (m.type === "output") onLine(m.text); if (m.type === "done" || m.type === "error") { es.close(); onDone(m.status); } };
  es.onerror = () => { es.close(); onDone("error"); };
}

const voiceOptions = {
  cn: [{id:"zh-CN-XiaoxiaoNeural",label:"Xiaoxiao ★ Warm & clear"},{id:"zh-CN-YunyangNeural",label:"Yunyang · Professional"},{id:"zh-CN-YunjianNeural",label:"Yunjian · Passionate"},{id:"zh-CN-YunxiNeural",label:"Yunxi · Lively"},{id:"zh-CN-XiaoyiNeural",label:"Xiaoyi · Cute"}],
  en: [{id:"en-US-AvaNeural",label:"Ava ★ Clear & friendly"},{id:"en-US-AriaNeural",label:"Aria · Confident"},{id:"en-US-ChristopherNeural",label:"Christopher · Authoritative"},{id:"en-GB-SoniaNeural",label:"Sonia · British female"},{id:"en-GB-RyanNeural",label:"Ryan · British male"}]
};

const defaultMeta = { type:"auto",voice:"zh-CN-XiaoxiaoNeural",voice_en:"en-US-AvaNeural",cover:null,outro:null,cover_duration:3,outro_duration:3,bgm:null,bgm_volume:0.15,bgm_loop:true,resolution:"1920x1080",fps:30,subtitle:{mode:"auto",burn:false},slides:{mode:"auto",page_duration:3,page_padding:1.5,transition:"fade",pages:[]} };

const cmdList = [
  {cmd:"all",desc:"Full pipeline: srt→dub→compose"},
  {cmd:"srt",desc:"Extract subtitles from recording"},
  {cmd:"dub",desc:"AI dubbing with edge-tts"},
  {cmd:"mix",desc:"Compose final video"},
  {cmd:"slide",desc:"Generate slideshow video"},
  {cmd:"trans",desc:"Translate subtitles to English"},
  {cmd:"en",desc:"English version (trans+dub+compose)"},
  {cmd:"config KEY=val",desc:"Set global config"},
  {cmd:"config list voice",desc:"List available voices"},
];

const { createApp, ref, computed, watch, onMounted } = Vue;
createApp({
  setup() {
    const page = ref("projects");
    const projects = ref([]);
    const selectedProject = ref("");
    const selectedFeature = ref("");
    const tab = ref("files");
    const lines = ref([]);
    const taskStatus = ref("");
    const running = ref(false);
    const themeBtn = ref("🌙");
    const showCreateProj = ref(false);
    const showCreateFeat = ref(false);
    const newName = ref("");
    const newMode = ref("video");
    const gCfg = ref({});
    const mCfg = ref({...defaultMeta});
    const cfgView = ref("visual");
    const metaText = ref("{}");
    const narrationText = ref("");
    const slideFiles = ref([]);
    const confirmCmd = ref(null);
    const confirmLabel = ref("");

    const projFeatures = computed(() => projects.value.find(p => p.name === selectedProject.value)?.features || []);
    const featureType = computed(() => projFeatures.value.find(f => f.name === selectedFeature.value)?.type || "video");
    const hasRecording = computed(() => projFeatures.value.find(f => f.name === selectedFeature.value)?.has_recording || false);
    const hasFinal = computed(() => projFeatures.value.find(f => f.name === selectedFeature.value)?.has_final || false);
    const outputFeatures = computed(() => {
      const r = [];
      for (const p of projects.value) for (const f of (p.features||[])) if (f.has_final) r.push({project:p.name,name:f.name});
      return r;
    });

    async function refreshProjects() { projects.value = await api.get("/api/projects"); }
    async function loadGlobalConfig() { gCfg.value = await api.get("/api/config"); }

    function selectProject(name) { selectedProject.value = name; selectedFeature.value = ""; }

    async function selectFeature(name) {
      selectedFeature.value = name; tab.value = "files";
      const pfx = encodeURIComponent(selectedProject.value)+"/"+encodeURIComponent(name);
      metaText.value = "{}"; narrationText.value = ""; slideFiles.value = [];
      try { const r = await fetch(`/api/files/${pfx}/meta.json`); if (r.ok) { const d = await r.json(); metaText.value = JSON.stringify(d,null,2); mCfg.value = {...defaultMeta,...d,slides:{...defaultMeta.slides,...(d.slides||{})}}; } } catch { metaText.value = "{}"; mCfg.value = {...defaultMeta}; }
      try { const r = await fetch(`/api/files/${pfx}/slides/narration.txt`); if (r.ok) narrationText.value = await r.text(); } catch { narrationText.value = ""; }
      try { const r = await fetch(`/api/files/${pfx}/slides`); if (r.ok) slideFiles.value = (await r.json())||[]; } catch { slideFiles.value = []; }
    }

    async function createProject() { if (!newName.value) return; await api.post("/api/projects", {name:newName.value}); showCreateProj.value = false; newName.value = ""; await refreshProjects(); selectProject(newName.value); }
    async function createFeature() { if (!newName.value) return; await api.post(`/api/projects/${encodeURIComponent(selectedProject.value)}/features`, {name:newName.value,mode:newMode.value}); showCreateFeat.value = false; newName.value = ""; newMode.value = "video"; await refreshProjects(); selectFeature(newName.value); }

    async function uploadFile(event, fname) { const f = event.target.files[0]; if (!f) return; await api.upload(`${encodeURIComponent(selectedProject.value)}/${encodeURIComponent(selectedFeature.value)}/${fname}`, f); await refreshProjects(); }
    async function uploadSlide(event) { for (const f of event.target.files) await api.upload(`${encodeURIComponent(selectedProject.value)}/${encodeURIComponent(selectedFeature.value)}/slides/${f.name}`, f); await refreshProjects(); try { const r = await fetch(`/api/files/${encodeURIComponent(selectedProject.value)}/${encodeURIComponent(selectedFeature.value)}/slides`); if (r.ok) slideFiles.value = (await r.json())||[]; } catch { slideFiles.value=[]; } }
    async function delFile(p) { await api.del(`${selectedProject.value}/${selectedFeature.value}/${p}`); await refreshProjects(); selectFeature(selectedFeature.value); }
    async function saveNarration() { await api.upload(`${encodeURIComponent(selectedProject.value)}/${encodeURIComponent(selectedFeature.value)}/slides/narration.txt`, new Blob([narrationText.value],{type:"text/plain"})); }
    async function saveMeta() { const d = cfgView.value==="visual"?mCfg.value:JSON.parse(metaText.value); await api.upload(`${encodeURIComponent(selectedProject.value)}/${encodeURIComponent(selectedFeature.value)}/meta.json`, new Blob([JSON.stringify(d,null,2)],{type:"application/json"})); await refreshProjects(); }
    async function saveGlobalConfig() { await api.post("/api/config", gCfg.value); }

    function confirmRun(cmd, label) { confirmCmd.value = cmd; confirmLabel.value = label; tab.value = "run"; }
    function executeConfirm() { const c = confirmCmd.value; confirmCmd.value = null; runTask(c); }
    function runSingle(cmd) { runTask(cmd); }

    async function runTask(cmd) {
      if (running.value) return;
      running.value = true; taskStatus.value = "running"; lines.value = [];
      const add = (t) => { let c=""; if (t.includes("✅")) c="ok"; else if (t.includes("❌")||t.includes("Error")) c="err"; else if (t.includes("⚠")) c="warn"; else if (t.includes("➜")) c="info"; lines.value.push({text:t,class:c}); };
      const {task_id} = await api.post("/api/run", {cmd, project:selectedProject.value, feature:selectedFeature.value});
      streamTask(task_id, add, (s) => { taskStatus.value = s; running.value = false; refreshProjects(); });
    }

    function toggleTheme() {
      const cur = document.documentElement.getAttribute("data-theme");
      const next = cur === "dark" ? "light" : "dark";
      document.documentElement.setAttribute("data-theme", next);
      themeBtn.value = next === "dark" ? "🌙" : "☀";
      localStorage.setItem("vt-theme", next);
    }

    watch(cfgView, (v) => { if (v==="json") metaText.value = JSON.stringify(mCfg.value,null,2); });
    watch(mCfg, () => { if (cfgView.value==="json") metaText.value = JSON.stringify(mCfg.value,null,2); }, {deep:true});

    const saved = localStorage.getItem("vt-theme")||"dark";
    document.documentElement.setAttribute("data-theme", saved);
    themeBtn.value = saved==="dark"?"🌙":"☀";
    refreshProjects(); loadGlobalConfig();

    return { page,projects,selectedProject,selectedFeature,tab,lines,taskStatus,running,themeBtn,
      showCreateProj,showCreateFeat,newName,newMode,gCfg,mCfg,cfgView,metaText,narrationText,slideFiles,
      confirmCmd,confirmLabel,voiceOptions,cmdList,
      projFeatures,featureType,hasRecording,hasFinal,outputFeatures,
      refreshProjects,selectProject,selectFeature,createProject,createFeature,
      uploadFile,uploadSlide,delFile,saveNarration,saveMeta,saveGlobalConfig,
      confirmRun,executeConfirm,runSingle,toggleTheme };
  }
}).mount("#app");

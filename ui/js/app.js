const api = {
  async get(url) { const r = await fetch(url); return r.json(); },
  async post(url, data) {
    const r = await fetch(url, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(data) });
    return r.json();
  },
  async upload(url, file) {
    const r = await fetch(`/api/upload/${url}`, { method: "POST", body: file });
    return r.ok ? { ok: true } : { ok: false };
  },
  async del(url) { await fetch(`/api/features/${url}/delete`, { method: "POST" }); }
};

function streamTask(taskId, onLine, onDone) {
  const es = new EventSource(`/api/task/${taskId}`);
  es.onmessage = (e) => {
    if (e.data.startsWith(":")) return;
    const msg = JSON.parse(e.data);
    if (msg.type === "output") onLine(msg.text);
    if (msg.type === "done" || msg.type === "error") { es.close(); onDone(msg.status); }
  };
  es.onerror = () => { es.close(); onDone("error"); };
}

const voiceOptions = {
  cn: [
    { id: "zh-CN-XiaoxiaoNeural", label: "Xiaoxiao ★ Warm & clear" },
    { id: "zh-CN-YunyangNeural", label: "Yunyang · Professional" },
    { id: "zh-CN-YunjianNeural", label: "Yunjian · Passionate" },
    { id: "zh-CN-YunxiNeural", label: "Yunxi · Lively" },
    { id: "zh-CN-XiaoyiNeural", label: "Xiaoyi · Cute" }
  ],
  en: [
    { id: "en-US-AvaNeural", label: "Ava ★ Clear & friendly" },
    { id: "en-US-AriaNeural", label: "Aria · Confident" },
    { id: "en-US-ChristopherNeural", label: "Christopher · Authoritative" },
    { id: "en-GB-SoniaNeural", label: "Sonia · British female" },
    { id: "en-GB-RyanNeural", label: "Ryan · British male" }
  ]
};

const defaultMeta = {
  type: "auto", voice: "zh-CN-XiaoxiaoNeural", voice_en: "en-US-AvaNeural",
  cover: null, outro: null, cover_duration: 3, outro_duration: 3,
  bgm: null, bgm_volume: 0.15, bgm_loop: true,
  resolution: "1920x1080", fps: 30,
  subtitle: { mode: "auto", burn: false },
  slides: { mode: "auto", page_duration: 3, page_padding: 1.5, transition: "fade", pages: [] }
};

const { createApp, ref, computed, watch } = Vue;
createApp({
  setup() {
    const page = ref("projects");
    const features = ref([]);
    const selectedFeature = ref("");
    const tab = ref("files");
    const lines = ref([]);
    const taskStatus = ref("");
    const running = ref(false);
    const themeBtn = ref("🌙");
    const showCreate = ref(false);
    const newProject = ref({ name: "", mode: "video" });
    const gCfg = ref({});
    const mCfg = ref({ ...defaultMeta });
    const cfgView = ref("visual");
    const metaText = ref("{}");
    const narrationText = ref("");
    const slideFiles = ref([]);
    const confirmCmd = ref(null);
    const confirmLabel = ref("");

    const featureType = computed(() => features.value.find(x => x.name === selectedFeature.value)?.type || "video");
    const hasRecording = computed(() => features.value.find(x => x.name === selectedFeature.value)?.has_recording || false);
    const hasFinal = computed(() => features.value.find(x => x.name === selectedFeature.value)?.has_final || false);

    async function refreshFeatures() { features.value = await api.get("/api/features"); }
    async function loadGlobalConfig() { gCfg.value = await api.get("/api/config"); }

    async function selectFeature(name) {
      selectedFeature.value = name; tab.value = "files"; page.value = "projects";
      metaText.value = "{}"; narrationText.value = ""; slideFiles.value = [];
      try { const r = await fetch(`/api/files/${name}/meta.json`); if (r.ok) { const d = await r.json(); metaText.value = JSON.stringify(d, null, 2); mCfg.value = { ...defaultMeta, ...d, slides: { ...defaultMeta.slides, ...(d.slides || {}) } }; } }
      catch { metaText.value = "{}"; mCfg.value = { ...defaultMeta }; }
      try { const r = await fetch(`/api/files/${name}/slides/narration.txt`); if (r.ok) narrationText.value = await r.text(); }
      catch { narrationText.value = ""; }
      try { const r = await fetch(`/api/files/${name}/slides`); if (r.ok) slideFiles.value = (await r.json()) || []; }
      catch { slideFiles.value = []; }
    }

    async function createProject() {
      if (!newProject.value.name) return;
      await api.post("/api/features", newProject.value);
      showCreate.value = false;
      const nm = newProject.value.name.startsWith("feature-") ? newProject.value.name : `feature-${newProject.value.name}`;
      newProject.value = { name: "", mode: "video" };
      await refreshFeatures();
      selectFeature(nm);
    }

    async function uploadFile(event, filename) {
      const file = event.target.files[0]; if (!file) return;
      await api.upload(`${selectedFeature.value}/${filename}`, file);
      await refreshFeatures();
    }

    async function uploadSlide(event) {
      for (const file of event.target.files) await api.upload(`${selectedFeature.value}/slides/${file.name}`, file);
      await refreshFeatures();
      try { const r = await fetch(`/api/files/${selectedFeature.value}/slides`); if (r.ok) slideFiles.value = (await r.json()) || []; }
      catch { slideFiles.value = []; }
    }

    async function delFile(path) { await api.del(`${selectedFeature.value}/${path}`.replace("//","/")); await refreshFeatures(); }

    async function saveNarration() {
      await api.upload(`${selectedFeature.value}/slides/narration.txt`, new Blob([narrationText.value], { type: "text/plain" }));
    }

    async function saveMeta() {
      const data = cfgView.value === "visual" ? mCfg.value : JSON.parse(metaText.value);
      await api.upload(`${selectedFeature.value}/meta.json`, new Blob([JSON.stringify(data, null, 2)], { type: "application/json" }));
      await refreshFeatures();
    }

    async function saveGlobalConfig() {
      await api.post("/api/config", gCfg.value);
      alert("Saved");
    }

    function confirmRun(cmd, label) { confirmCmd.value = cmd; confirmLabel.value = label; tab.value = "run"; }
    function executeConfirm() { const c = confirmCmd.value; confirmCmd.value = null; runTask(c); }
    function runSingle(cmd) { runTask(cmd); }

    async function runTask(cmd) {
      if (running.value) return;
      running.value = true; taskStatus.value = "running"; lines.value = [];
      function addLine(text) {
        let cls = "";
        if (text.includes("✅")) cls = "ok";
        else if (text.includes("❌") || text.includes("Error")) cls = "err";
        else if (text.includes("⚠")) cls = "warn";
        else if (text.includes("➜")) cls = "info";
        lines.value.push({ text, class: cls });
      }
      const { task_id } = await api.post("/api/run", { cmd, feature: selectedFeature.value });
      streamTask(task_id, addLine, (status) => { taskStatus.value = status; running.value = false; refreshFeatures(); });
    }

    function toggleTheme() {
      const cur = document.documentElement.getAttribute("data-theme");
      const next = cur === "dark" ? "light" : "dark";
      document.documentElement.setAttribute("data-theme", next);
      themeBtn.value = next === "dark" ? "🌙" : "☀";
      localStorage.setItem("vt-theme", next);
    }

    watch(cfgView, (v) => { if (v === "json") metaText.value = JSON.stringify(mCfg.value, null, 2); });
    watch(mCfg, () => { if (cfgView.value === "json") metaText.value = JSON.stringify(mCfg.value, null, 2); }, { deep: true });

    const saved = localStorage.getItem("vt-theme") || "dark";
    document.documentElement.setAttribute("data-theme", saved);
    themeBtn.value = saved === "dark" ? "🌙" : "☀";
    refreshFeatures(); loadGlobalConfig();

    return {
      page, features, selectedFeature, tab, lines, taskStatus, running, themeBtn,
      showCreate, newProject, gCfg, mCfg, cfgView, metaText, narrationText, slideFiles,
      confirmCmd, confirmLabel, voiceOptions,
      featureType, hasRecording, hasFinal,
      refreshFeatures, selectFeature, createProject, uploadFile, uploadSlide, delFile,
      saveNarration, saveMeta, saveGlobalConfig,
      confirmRun, executeConfirm, runSingle, toggleTheme
    };
  }
}).mount("#app");

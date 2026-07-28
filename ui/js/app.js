const api = {
  async get(url) { const r = await fetch(url); return r.json(); },
  async post(url, data) {
    const r = await fetch(url, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(data) });
    return r.json();
  },
  async upload(url, file, filename) {
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

const { createApp, ref, computed, watch, nextTick } = Vue;
createApp({
  setup() {
    const features = ref([]);
    const selectedFeature = ref("");
    const tab = ref("files");
    const lines = ref([]);
    const taskStatus = ref("");
    const running = ref(false);
    const themeBtn = ref("🌙");
    const showCreate = ref(false);
    const newProject = ref({ name: "", mode: "video" });
    const globalConfig = ref({});
    const metaText = ref("{}");
    const narrationText = ref("");
    const slideFiles = ref([]);

    const featureType = computed(() => {
      const f = features.value.find(x => x.name === selectedFeature.value);
      return f ? f.type : "video";
    });
    const hasRecording = computed(() => {
      const f = features.value.find(x => x.name === selectedFeature.value);
      return f ? f.has_recording : false;
    });
    const hasFinal = computed(() => {
      const f = features.value.find(x => x.name === selectedFeature.value);
      return f ? f.has_final : false;
    });

    async function refreshFeatures() {
      features.value = await api.get("/api/features");
    }

    async function selectFeature(name) {
      selectedFeature.value = name;
      tab.value = "files";
      await loadFeatureData();
    }

    async function loadFeatureData() {
      if (!selectedFeature.value) return;
      // load meta.json
      try {
        const r = await fetch(`/api/files/${selectedFeature.value}/meta.json`);
        if (r.ok) metaText.value = JSON.stringify(await r.json(), null, 2);
      } catch { metaText.value = "{}"; }
      // load narration
      try {
        const r = await fetch(`/api/files/${selectedFeature.value}/slides/narration.txt`);
        if (r.ok) narrationText.value = await r.text();
      } catch { narrationText.value = ""; }
      // list slide files
      const f = features.value.find(x => x.name === selectedFeature.value);
      if (f && f.has_slides) {
        try {
          // simple: check if slides/ dir exists (we'll just show from features list)
          slideFiles.value = [];
        } catch { slideFiles.value = []; }
      }
      // load global config
      globalConfig.value = await api.get("/api/config");
    }

    async function createProject() {
      if (!newProject.value.name) return;
      await api.post("/api/features", newProject.value);
      showCreate.value = false;
      newProject.value = { name: "", mode: "video" };
      await refreshFeatures();
      selectFeature(newProject.value.name.startsWith("feature-") ? newProject.value.name : `feature-${newProject.value.name}`);
    }

    async function uploadFile(event, filename) {
      const file = event.target.files[0];
      if (!file) return;
      await api.upload(`${selectedFeature.value}/${filename}`, file);
      await refreshFeatures();
    }

    async function uploadSlide(event) {
      for (const file of event.target.files) {
        await api.upload(`${selectedFeature.value}/slides/${file.name}`, file);
      }
      await refreshFeatures();
    }

    async function delFile(path) {
      await api.del(`${selectedFeature.value}/${path}`.replace("//", "/"));
      await refreshFeatures();
    }

    async function saveNarration() {
      const blob = new Blob([narrationText.value], { type: "text/plain" });
      await api.upload(`${selectedFeature.value}/slides/narration.txt`, blob);
      await refreshFeatures();
    }

    async function saveMeta() {
      try {
        JSON.parse(metaText.value); // validate
      } catch { alert("Invalid JSON"); return; }
      const blob = new Blob([metaText.value], { type: "application/json" });
      await api.upload(`${selectedFeature.value}/meta.json`, blob);
      await refreshFeatures();
    }

    async function saveGlobalConfig() {
      await api.post("/api/config", globalConfig.value);
      alert("Saved");
    }

    function editMeta(e) { metaText.value = e.target.innerText; }

    async function run(cmd) {
      if (running.value) return;
      running.value = true; taskStatus.value = "running"; lines.value = [];
      tab.value = "run";

      function addLine(text) {
        let cls = "";
        if (text.includes("✅")) cls = "ok";
        else if (text.includes("❌") || text.includes("Error")) cls = "err";
        else if (text.includes("⚠")) cls = "warn";
        else if (text.includes("➜")) cls = "info";
        lines.value.push({ text, class: cls });
      }

      const { task_id } = await api.post("/api/run", { cmd, feature: selectedFeature.value });
      streamTask(task_id, addLine, (status) => {
        taskStatus.value = status;
        running.value = false;
        refreshFeatures();
      });
    }

    function toggleTheme() {
      const cur = document.documentElement.getAttribute("data-theme");
      const next = cur === "dark" ? "light" : "dark";
      document.documentElement.setAttribute("data-theme", next);
      themeBtn.value = next === "dark" ? "🌙" : "☀";
      localStorage.setItem("vt-theme", next);
    }

    watch(selectedFeature, async () => { if (selectedFeature.value) await loadFeatureData(); });

    // Init
    const saved = localStorage.getItem("vt-theme") || "dark";
    document.documentElement.setAttribute("data-theme", saved);
    themeBtn.value = saved === "dark" ? "🌙" : "☀";
    refreshFeatures();

    return {
      features, selectedFeature, tab, lines, taskStatus, running,
      themeBtn, showCreate, newProject, globalConfig, metaText, narrationText, slideFiles,
      featureType, hasRecording, hasFinal,
      refreshFeatures, selectFeature, createProject,
      uploadFile, uploadSlide, delFile, saveNarration, saveMeta, saveGlobalConfig, editMeta,
      run, toggleTheme
    };
  }
}).mount("#app");

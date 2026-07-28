// ── API Client ──
const api = {
  async get(url) { const r = await fetch(url); return r.json(); },
  async post(url, data) {
    const r = await fetch(url, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(data) });
    return r.json();
  }
};

// ── SSE Stream ──
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

// ── Feature List Component ──
const FeatureList = {
  props: ["features", "selected"],
  emits: ["select", "refresh"],
  template: `
    <div class="card">
      <h3>📂 Features</h3>
      <div v-if="features.length===0" style="color:var(--text3);font-size:0.85rem">无 feature 目录</div>
      <div v-for="f in features" :key="f.name"
        :class="['feature-item', { active: selected===f.name }]"
        @click="$emit('select', f.name)">
        <span>{{ f.name }}</span>
        <span>
          <span class="badge" :class="f.type==='video'?'g':'b'">{{ f.type }}</span>
          <span v-if="f.has_final" class="badge g" style="margin-left:4px">✅</span>
        </span>
      </div>
    </div>
  `
};

// ── Command Panel Component ──
const CommandPanel = {
  props: ["feature", "running"],
  emits: ["run"],
  template: `
    <div class="card">
      <h3>⚡ Commands</h3>
      <div v-if="!feature" style="color:var(--text3);font-size:0.85rem">← 请先选择 feature</div>
      <div v-else>
        <div class="cmd-btns">
          <button class="btn btn-pri" @click="$emit('run','all')" :disabled="running">🚀 all</button>
          <button class="btn" @click="$emit('run','srt')" :disabled="running">🎙️ srt</button>
          <button class="btn" @click="$emit('run','dub')" :disabled="running">🤖 dub</button>
          <button class="btn" @click="$emit('run','mix')" :disabled="running">🎬 mix</button>
          <button class="btn" @click="$emit('run','slide')" :disabled="running">📸 slide</button>
          <button class="btn" @click="$emit('run','en')" :disabled="running">🌐 en</button>
        </div>
        <div class="cmd-btns">
          <button class="btn btn-sm" @click="$emit('run','trans')" :disabled="running">🌐 trans</button>
          <button class="btn btn-sm" @click="$emit('run','dub-en')" :disabled="running">en-dub</button>
          <button class="btn btn-sm" @click="$emit('run','mix-en')" :disabled="running">en-mix</button>
        </div>
      </div>
    </div>
  `
};

// ── Live Terminal Component ──
const LiveTerminal = {
  props: ["lines", "status"],
  template: `
    <div class="card">
      <h3>🖥️ Terminal {{ status ? '· '+status : '' }}</h3>
      <div class="terminal" ref="term">
        <div v-if="lines.length===0" style="color:var(--text3)">等待命令...</div>
        <div v-for="(l,i) in lines" :key="i" :class="l.class || ''">{{ l.text }}</div>
      </div>
    </div>
  `,
  updated() {
    const t = this.$refs.term;
    if (t) t.scrollTop = t.scrollHeight;
  }
};

// ── Config Panel Component ──
const ConfigPanel = {
  props: ["config"],
  emits: ["update"],
  data() { return { editing: false, form: {} }; },
  template: `
    <div class="card">
      <h3>⚙️ Config <button class="btn btn-sm" @click="editing=!editing" style="float:right">{{ editing?'Done':'Edit' }}</button></h3>
      <div v-if="!editing">
        <div class="card-row" v-for="(v,k) in config" :key="k">
          <span class="label">{{ k }}</span><span style="font-family:var(--mono);font-size:0.8rem">{{ v || '(empty)' }}</span>
        </div>
      </div>
      <div v-else>
        <div class="config-row" v-for="(v,k) in config" :key="k">
          <span class="key">{{ k }}</span>
          <input v-model="form[k]" :placeholder="v" />
        </div>
        <button class="btn btn-pri btn-sm" @click="save">Save</button>
      </div>
    </div>
  `,
  methods: {
    async save() {
      await api.post("/api/config", this.form);
      this.editing = false;
      this.$emit("update");
    }
  },
  watch: {
    config: {
      immediate: true,
      handler(c) { if (!this.editing) this.form = { ...c }; }
    }
  }
};

// ── App ──
const { createApp, ref, computed } = Vue;
createApp({
  components: { FeatureList, CommandPanel, LiveTerminal, ConfigPanel },
  setup() {
    const features = ref([]);
    const selectedFeature = ref("");
    const config = ref({});
    const terminalLines = ref([]);
    const taskStatus = ref("");
    const isRunning = ref(false);
    const themeBtn = ref("🌙");

    async function refreshFeatures() { features.value = await api.get("/api/features"); }
    async function loadConfig() { config.value = await api.get("/api/config"); }

    function selectFeature(name) { selectedFeature.value = name; }

    async function runCommand(cmd) {
      if (isRunning.value) return;
      isRunning.value = true; taskStatus.value = "running";
      terminalLines.value = [];

      function addLine(text) {
        let cls = "";
        if (text.includes("✅")) cls = "ok";
        else if (text.includes("❌") || text.includes("Error")) cls = "err";
        else if (text.includes("⚠")) cls = "warn";
        else if (text.includes("➜")) cls = "info";
        terminalLines.value.push({ text, class: cls });
      }

      const { task_id } = await api.post("/api/run", {
        cmd, feature: selectedFeature.value
      });

      streamTask(task_id, addLine, (status) => {
        taskStatus.value = status;
        isRunning.value = false;
        refreshFeatures();
      });
    }

    async function updateConfig() { await loadConfig(); }

    function toggleTheme() {
      const cur = document.documentElement.getAttribute("data-theme");
      const next = cur === "dark" ? "light" : "dark";
      document.documentElement.setAttribute("data-theme", next);
      themeBtn.value = next === "dark" ? "🌙" : "☀";
      localStorage.setItem("vt-theme", next);
    }

    // Init
    const saved = localStorage.getItem("vt-theme") || "dark";
    document.documentElement.setAttribute("data-theme", saved);
    themeBtn.value = saved === "dark" ? "🌙" : "☀";

    refreshFeatures(); loadConfig();

    return { features, selectedFeature, config, terminalLines, taskStatus, isRunning,
      themeBtn, refreshFeatures, selectFeature, runCommand, updateConfig, toggleTheme };
  }
}).mount("#app");

#!/usr/bin/env python3
"""Video Toolkit Web UI Server (Tier 1)"""
import http.server, json, os, subprocess, threading, queue, time, urllib.parse, sys

PORT = int(os.environ.get("VT_PORT", "9876"))
TOOLKIT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UI_DIR = os.path.join(TOOLKIT_DIR, "ui")
CONFIG_FILE = os.path.expanduser("~/.config/video-toolkit/config")

# ── SSE 任务管理 ──
class TaskManager:
    def __init__(self):
        self.tasks = {}
        self._lock = threading.Lock()

    def create(self, task_id):
        with self._lock:
            q = queue.Queue()
            self.tasks[task_id] = {"queue": q, "process": None, "status": "running"}
        return q

    def update(self, task_id, status):
        with self._lock:
            if task_id in self.tasks:
                self.tasks[task_id]["status"] = status

    def get(self, task_id):
        with self._lock:
            return self.tasks.get(task_id)

tasks = TaskManager()

# ── SSE 流式执行命令 ──
def run_command(cmd, task_id, feat_dir=None):
    q = tasks.create(task_id)
    env = os.environ.copy()
    if feat_dir:
        env["VIDEO_FEATURES_DIR"] = feat_dir

    def reader(pipe, prefix):
        for line in iter(pipe.readline, ""):
            q.put(json.dumps({"type": "output", "text": prefix + line.rstrip()}))
        pipe.close()

    try:
        proc = subprocess.Popen(
            ["bash", os.path.join(TOOLKIT_DIR, "video-toolkit.sh")] + cmd.split(),
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, bufsize=1, cwd=TOOLKIT_DIR, env=env
        )
        tasks.tasks[task_id]["process"] = proc
        reader(proc.stdout, "")
        proc.wait()
        status = "success" if proc.returncode == 0 else "failed"
        tasks.update(task_id, status)
        q.put(json.dumps({"type": "done", "status": status}))
    except Exception as e:
        tasks.update(task_id, "error")
        q.put(json.dumps({"type": "error", "text": str(e)}))

# ── API 路由 ──
class APIHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=UI_DIR, **kwargs)

    def log_message(self, format, *args):
        pass  # 静默

    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path

        if path == "/api/features":
            return self.json_response(self.list_features())
        if path == "/api/config":
            return self.json_response(self.read_config())
        if path == "/api/status":
            return self.json_response(self.get_status())
        if path.startswith("/api/task/"):
            return self.handle_sse(path)
        return super().do_GET()

    def do_POST(self):
        path = urllib.parse.urlparse(self.path).path
        length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(length)) if length > 0 else {}

        if path == "/api/run":
            return self.run_task(body)
        if path == "/api/config":
            return self.json_response(self.write_config(body))
        self.send_error(404)

    # ── SSE ──
    def handle_sse(self, path):
        task_id = path.split("/")[-1]
        q = tasks.get(task_id)
        if not q:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        while True:
            try:
                msg = q["queue"].get(timeout=30)
                self.wfile.write(f"data: {msg}\n\n".encode())
                self.wfile.flush()
                parsed = json.loads(msg)
                if parsed.get("type") in ("done", "error"):
                    break
            except queue.Empty:
                self.wfile.write(": ping\n\n".encode())
                self.wfile.flush()

    def run_task(self, body):
        cmd = body.get("cmd", "")
        feat = body.get("feature", "")
        task_id = str(int(time.time() * 1000))
        feat_dir = None
        if feat:
            feat_dir = self.resolve_feature(feat)
        threading.Thread(target=run_command, args=(cmd, task_id, feat_dir), daemon=True).start()
        self.json_response({"task_id": task_id})

    # ── Helpers ──
    def json_response(self, data):
        body = json.dumps(data, ensure_ascii=False).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def list_features(self):
        base = os.environ.get("VIDEO_FEATURES_DIR", TOOLKIT_DIR)
        result = []
        if os.path.isdir(base):
            for d in sorted(os.listdir(base)):
                if d.startswith("feature-") and os.path.isdir(os.path.join(base, d)):
                    has_rec = os.path.exists(os.path.join(base, d, "recording.mov"))
                    has_slides = os.path.isdir(os.path.join(base, d, "slides"))
                    has_final = os.path.exists(os.path.join(base, d, "final.mp4"))
                    result.append({
                        "name": d, "type": "slide" if has_slides and not has_rec else "video",
                        "has_recording": has_rec, "has_slides": has_slides, "has_final": has_final
                    })
        return result

    def resolve_feature(self, name):
        base = os.environ.get("VIDEO_FEATURES_DIR", TOOLKIT_DIR)
        if os.path.isdir(name): return name
        path = os.path.join(base, name)
        if os.path.isdir(path): return path
        import glob
        matches = glob.glob(os.path.join(base, f"feature-{name.replace('feature-', '')}*"))
        return matches[0] if matches else base

    def read_config(self):
        cfg = {}
        if os.path.exists(CONFIG_FILE):
            with open(CONFIG_FILE) as f:
                for line in f:
                    line = line.strip()
                    if "=" in line and not line.startswith("#"):
                        k, v = line.split("=", 1)
                        cfg[k] = v
        return cfg

    def write_config(self, body):
        existing = self.read_config()
        existing.update(body)
        os.makedirs(os.path.dirname(CONFIG_FILE), exist_ok=True)
        with open(CONFIG_FILE, "w") as f:
            for k, v in existing.items():
                f.write(f"{k}={v}\n")
        return {"ok": True}

    def get_status(self):
        base = os.environ.get("VIDEO_FEATURES_DIR", TOOLKIT_DIR)
        features = self.list_features()
        total = len(features)
        done = sum(1 for f in features if f["has_final"])
        return {"total": total, "done": done, "features": features}

if __name__ == "__main__":
    server = http.server.HTTPServer(("0.0.0.0", PORT), APIHandler)
    print(f"  🎬 Video Toolkit UI → http://localhost:{PORT}")
    print(f"  📁 静态文件: {UI_DIR}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n  👋 bye")

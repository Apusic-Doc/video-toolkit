#!/usr/bin/env python3
"""Video Toolkit Web UI Server (Tier 1 — Project > Feature hierarchy)"""
import http.server, json, os, subprocess as sp, threading, queue, time, urllib.parse, sys, shutil

PORT = int(os.environ.get("VT_PORT", "9876"))
TOOLKIT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UI_DIR = os.path.join(TOOLKIT_DIR, "ui")
PROJECTS_DIR = os.environ.get("VIDEO_PROJECTS_DIR",
    os.path.join(os.path.dirname(TOOLKIT_DIR), "projects"))
CONFIG_FILE = os.path.expanduser("~/.config/video-toolkit/config")

os.makedirs(PROJECTS_DIR, exist_ok=True)

# ── SSE Task Manager ──
class TaskManager:
    def __init__(self): self.tasks = {}; self._lock = threading.Lock()
    def create(self, tid):
        with self._lock: q = queue.Queue(); self.tasks[tid] = {"queue": q, "process": None, "status": "running"}; return q
    def update(self, tid, status):
        with self._lock:
            if tid in self.tasks: self.tasks[tid]["status"] = status
    def get(self, tid):
        with self._lock: return self.tasks.get(tid)
    def cleanup(self, tid):
        with self._lock:
            if tid in self.tasks: del self.tasks[tid]

TASKS = TaskManager()

class APIHandler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a): pass

    def ok(self, data=None):
        self.send_response(200); self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*"); self.end_headers()
        self.wfile.write(json.dumps(data or {}).encode())

    def error(self, code, msg=""):
        self.send_response(code); self.send_header("Access-Control-Allow-Origin", "*"); self.end_headers()
        self.wfile.write(json.dumps({"error": msg}).encode())

    # ── Routing ──
    def do_GET(self):
        p = urllib.parse.urlparse(self.path)
        if p.path == "/api/projects": return self.list_projects()
        if p.path == "/api/config": return self.get_global_config()
        if p.path == "/api/task/": return self.handle_404()
        if p.path.startswith("/api/task/"): return self.sse_task(p.path.split("/")[-1])
        if p.path.startswith("/api/files/"): return self.serve_file("GET", p.path)
        if p.path == "/" or "." not in p.path.rsplit("/", 1)[-1]: return self.serve_static(p.path)
            return self.serve_static(p.path)
        return self.handle_404()

    def do_POST(self):
        p = urllib.parse.urlparse(self.path)
        body = self._read_body()
        if p.path == "/api/projects": return self.create_project(body)
        if p.path == "/api/config": return self.set_global_config(body)
        if p.path == "/api/run": return self.run_task(body)
        if p.path.startswith("/api/upload/"): return self.upload_file(p.path, body)
        m = self._match_proj_feat(p.path, "POST")
        if m: return self.dispatch(m[0], m[1], m[2], m[3], "POST", body)
        return self.handle_404()

    def do_OPTIONS(self):
        self.send_response(200); self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET,POST,OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type"); self.end_headers()

    def _read_body(self):
        length = int(self.headers.get("Content-Length", 0))
        return json.loads(self.rfile.read(length)) if length > 0 else {}

    def _match_proj_feat(self, path, method):
        """Parse /api/projects/{pname}/features/{fname}[/{action}]"""
        parts = path.strip("/").split("/")
        if len(parts) < 4 or parts[:2] != ["api", "projects"]: return None
        pname = parts[2]
        if len(parts) == 3: return ("project", pname, None, None)
        if len(parts) >= 5 and parts[3] == "features":
            fname = parts[4]
            action = parts[5] if len(parts) > 5 else ""
            return ("feature", pname, fname, action)
        return None

    def dispatch(self, kind, pname, fname, action, method, body=None):
        if kind == "project":
            if method == "GET": return self.get_project(pname)
            if method == "POST": return self.create_feature(pname, body)
        if kind == "feature":
            if action == "delete":
                return self.delete_file(pname, fname)
            return self.error(400, "unknown action")
        return self.error(400)

    # ── Projects ──
    def list_projects(self):
        projects = []
        for name in sorted(os.listdir(PROJECTS_DIR)):
            d = os.path.join(PROJECTS_DIR, name)
            if not os.path.isdir(d) or name.startswith("."): continue
            features = self._list_features_in(d)
            projects.append({"name": name, "features": features})
        self.ok(projects)

    def get_project(self, pname):
        d = os.path.join(PROJECTS_DIR, pname)
        if not os.path.isdir(d): return self.error(404, "project not found")
        features = self._list_features_in(d)
        self.ok({"name": pname, "features": features})

    def create_project(self, body):
        name = body.get("name", "").strip()
        if not name: return self.error(400, "name required")
        d = os.path.join(PROJECTS_DIR, name)
        if os.path.exists(d): return self.error(409, "exists")
        os.makedirs(d, exist_ok=True)
        self.ok({"created": name})

    def create_feature(self, pname, body):
        d = os.path.join(PROJECTS_DIR, pname)
        if not os.path.isdir(d): return self.error(404, "project not found")
        fname = body.get("name", "").strip()
        mode = body.get("mode", "video")
        if not fname: return self.error(400, "name required")
        fd = os.path.join(d, fname)
        if os.path.exists(fd): return self.error(409, "exists")
        os.makedirs(fd, exist_ok=True)
        if mode == "slide": os.makedirs(os.path.join(fd, "slides"), exist_ok=True)
        self.ok({"created": fname})

    def _list_features_in(self, proj_dir):
        features = []
        for name in sorted(os.listdir(proj_dir)):
            d = os.path.join(proj_dir, name)
            if not os.path.isdir(d) or name.startswith("."): continue
            features.append({
                "name": name,
                "type": "slide" if os.path.isdir(os.path.join(d, "slides")) else "video",
                "has_recording": any(f for f in os.listdir(d) if f.startswith("recording") and os.path.isfile(os.path.join(d, f))),
                "has_slides": os.path.isdir(os.path.join(d, "slides")) and len(os.listdir(os.path.join(d, "slides"))) > 0,
                "has_final": os.path.isfile(os.path.join(d, "final.mp4"))
            })
        return features

    # ── Files ──
    def serve_file(self, method, path):
        base = PROJECTS_DIR
        rel = path.replace("/api/files/", "").lstrip("/")
        fp = os.path.join(base, os.path.normpath(rel))
        # Security: stay inside PROJECTS_DIR
        if not fp.startswith(base + os.sep) and fp != base:
            return self.error(403)
        if os.path.isdir(fp):
            files = [f for f in os.listdir(fp) if not f.startswith('.') and os.path.isfile(os.path.join(fp, f))]
            return self.ok(files)
        if not os.path.exists(fp): return self.error(404)
        if method == "POST": return self.handle_404()
        ext = os.path.splitext(fp)[1]
        ct = {"mp4": "video/mp4", "wav": "audio/wav", "png": "image/png", "jpg": "image/jpeg",
              "mov": "video/quicktime", "mp3": "audio/mpeg", "json": "application/json",
              "txt": "text/plain", "srt": "text/plain"}.get(ext[1:], "application/octet-stream")
        self.send_response(200); self.send_header("Content-Type", ct)
        self.send_header("Content-Length", os.path.getsize(fp)); self.end_headers()
        with open(fp, "rb") as f: self.wfile.write(f.read())

    def delete_file(self, pname, fname):
        body = urllib.parse.parse_qs(self.path.split("?")[1]) if "?" in self.path else {}
        path = body.get("path", [""])[0]
        fp = os.path.join(PROJECTS_DIR, pname, fname, os.path.normpath(path))
        if not fp.startswith(os.path.join(PROJECTS_DIR, pname, fname)):
            return self.error(403)
        if os.path.isfile(fp): os.remove(fp)
        elif os.path.isdir(fp):
            import shutil; shutil.rmtree(fp)
        self.ok({"deleted": path})

    def upload_file(self, path, body):
        pname = path.split("/")[3] if len(path.split("/")) > 3 else None
        fname = path.split("/")[4] if len(path.split("/")) > 4 else None
        fpath = path.split("/", 5)[5] if len(path.split("/")) > 5 else ""
        if not pname or not fname: return self.error(400)
        dest = os.path.join(PROJECTS_DIR, pname, fname, fpath)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        if isinstance(body, str):
            with open(dest, "w", encoding="utf-8") as f: f.write(body)
        elif isinstance(body, bytes):
            with open(dest, "wb") as f: f.write(body)
        else:
            # multipart or raw? Read from raw request
            cl = int(self.headers.get("Content-Length", 0))
            data = self.rfile.read(cl)
            with open(dest, "wb") as f: f.write(data)
        self.ok({"uploaded": fpath})

    # ── Config ──
    def get_global_config(self):
        cfg = {}
        if os.path.exists(CONFIG_FILE):
            with open(CONFIG_FILE) as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith("#") and "=" in line:
                        k, v = line.split("=", 1)
                        cfg[k.strip()] = v.strip()
        self.ok(cfg)

    def set_global_config(self, body):
        existing = {}
        if os.path.exists(CONFIG_FILE):
            with open(CONFIG_FILE) as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith("#") and "=" in line:
                        k, v = line.split("=", 1)
                        existing[k.strip()] = v.strip()
        existing.update(body)
        with open(CONFIG_FILE, "w") as f:
            f.write("# Video Toolkit 配置文件\n")
            for k, v in existing.items():
                f.write(f"{k}={v}\n")
        self.ok({"saved": True})

    # ── Run ──
    def run_task(self, body):
        cmd = body.get("cmd", "")
        pname = body.get("project", "")
        fname = body.get("feature", "")
        if not pname or not fname: return self.error(400, "project + feature required")
        fd = os.path.join(PROJECTS_DIR, pname, fname)
        if not os.path.isdir(fd): return self.error(404, "feature not found")

        task_id = f"{int(time.time())}-{os.urandom(3).hex()}"
        q = TASKS.create(task_id)
        self.ok({"task_id": task_id})

        t = threading.Thread(target=self._exec, args=(task_id, cmd, fd))
        t.daemon = True; t.start()

    def _exec(self, task_id, cmd, feature_dir):
        script = os.path.join(TOOLKIT_DIR, "video-toolkit.sh")
        p = subprocess.Popen(
            ["bash", script, cmd, feature_dir],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, bufsize=1, cwd=TOOLKIT_DIR
        )
        TASKS.tasks[task_id]["process"] = p
        for line in p.stdout:
            TASKS.tasks[task_id]["queue"].put({"type": "output", "text": line.rstrip()})
        p.wait()
        status = "done" if p.returncode == 0 else f"error ({p.returncode})"
        TASKS.update(task_id, status)
        TASKS.tasks[task_id]["queue"].put({"type": "done", "status": status})

    def sse_task(self, task_id):
        ti = TASKS.get(task_id)
        if not ti: return self.error(404)
        self.send_response(200); self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache"); self.end_headers()
        q = ti["queue"]
        try:
            while True:
                msg = q.get(timeout=30)
                self.wfile.write(f"data: {json.dumps(msg)}\n\n".encode())
                self.wfile.flush()
                if msg["type"] in ("done", "error"): break
        except queue.Empty:
            self.wfile.write('data: {"type":"error","status":"timeout"}\n\n'.encode())
            self.wfile.flush()
        TASKS.cleanup(task_id)

    # ── Static ──
    def serve_static(self, path):
        fp = os.path.join(UI_DIR, path.lstrip("/") or "index.html")
        if not os.path.exists(fp) or not fp.startswith(UI_DIR):
            fp = os.path.join(UI_DIR, "index.html")
        ext = os.path.splitext(fp)[1]
        ct = {".html": "text/html", ".css": "text/css", ".js": "application/javascript",
              ".svg": "image/svg+xml", ".png": "image/png"}.get(ext, "text/plain")
        self.send_response(200); self.send_header("Content-Type", ct)
        self.send_header("Content-Length", os.path.getsize(fp)); self.end_headers()
        with open(fp, "rb") as f: self.wfile.write(f.read())

    def handle_404(self):
        self.error(404, "not found")

if __name__ == "__main__":
    # Auto-create demo project from old 'samples' dir
    old_samples = os.path.join(TOOLKIT_DIR, "samples")
    demo_proj = os.path.join(PROJECTS_DIR, "demo")
    if os.path.isdir(old_samples) and not os.path.exists(demo_proj):
        import shutil
        for item in os.listdir(old_samples):
            if item.startswith("feature-") and os.path.isdir(os.path.join(old_samples, item)):
                dest = os.path.join(demo_proj, item)
                if not os.path.exists(dest):
                    shutil.copytree(os.path.join(old_samples, item), dest)
        if os.listdir(PROJECTS_DIR): os.makedirs(demo_proj, exist_ok=True)

    # 端口占用自动杀旧进程
    try:
        httpd = http.server.HTTPServer(("0.0.0.0", PORT), APIHandler)
    except OSError:
        sp.run(f"lsof -ti :{PORT} | xargs kill -9 2>/dev/null", shell=True, capture_output=True)
        time.sleep(1)
        httpd = http.server.HTTPServer(("0.0.0.0", PORT), APIHandler)
    print(f"✅ Video Toolkit UI → http://localhost:{PORT}")
    httpd.serve_forever()

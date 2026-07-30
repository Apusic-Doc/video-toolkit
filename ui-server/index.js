import express from 'express';
import http from 'http';
import path from 'path';
import fs from 'fs';
import { WebSocketServer } from 'ws';
import { fileURLToPath } from 'url';
import { sessionMiddleware, requireAuth, authStatus, loginHandler, logoutHandler } from './lib/auth.js';
import apiRouter from './routes/api.js';
import { bus } from './lib/taskRunner.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PORT = process.env.VT_UI_PORT || 5175;

const app = express();
app.use(express.json({ limit: '2mb' }));
app.use(sessionMiddleware);

app.get('/api/session', (req, res) => res.json({ status: authStatus(req) }));
app.post('/api/login', loginHandler);
app.post('/api/logout', logoutHandler);

app.use('/api', requireAuth, apiRouter);

// 生产模式：serve 前端构建产物；开发模式下前端另起 Vite dev server 走代理，不需要这段
const clientDist = path.join(__dirname, '..', 'ui-client', 'dist');
if (fs.existsSync(clientDist)) {
  app.use(express.static(clientDist));
  app.get('*', (req, res) => {
    if (req.path.startsWith('/api')) return res.status(404).end();
    res.sendFile(path.join(clientDist, 'index.html'));
  });
}

const server = http.createServer(app);

// ── WebSocket: 任务实时日志，按 project/feature 订阅 ──
const wss = new WebSocketServer({ server, path: '/ws' });
wss.on('connection', (ws, req) => {
  const url = new URL(req.url, 'http://localhost');
  const project = url.searchParams.get('project');
  const feature = url.searchParams.get('feature');
  if (!project || !feature) { ws.close(); return; }
  const key = `${project}/${feature}`;
  const onEvent = (msg) => { if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(msg)); };
  bus.on(key, onEvent);
  ws.on('close', () => bus.off(key, onEvent));
});

server.listen(PORT, () => {
  console.log(`✅ vt-ui-server → http://localhost:${PORT}`);
});

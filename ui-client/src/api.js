async function req(method, url, body) {
  const opts = { method, headers: {} };
  if (body !== undefined) {
    opts.headers['Content-Type'] = 'application/json';
    opts.body = JSON.stringify(body);
  }
  const res = await fetch(url, opts);
  if (res.status === 401) throw new AuthError();
  const ct = res.headers.get('content-type') || '';
  const data = ct.includes('application/json') ? await res.json() : null;
  if (!res.ok) throw new Error(data?.error || `HTTP ${res.status}`);
  return data;
}

export class AuthError extends Error {
  constructor() { super('need-login'); this.name = 'AuthError'; }
}

export const api = {
  session: () => req('GET', '/api/session'),
  login: (password) => req('POST', '/api/login', { password }),
  logout: () => req('POST', '/api/logout'),

  projects: () => req('GET', '/api/projects'),
  features: (project) => req('GET', `/api/projects/${encodeURIComponent(project)}/features`),
  feature: (project, feature) => req('GET', `/api/projects/${encodeURIComponent(project)}/features/${encodeURIComponent(feature)}`),

  meta: (project, feature) => req('GET', `/api/projects/${encodeURIComponent(project)}/features/${encodeURIComponent(feature)}/meta`),
  saveMeta: (project, feature, data) => req('PUT', `/api/projects/${encodeURIComponent(project)}/features/${encodeURIComponent(feature)}/meta`, data),
  previewCoverUrl: (project, feature) => `/api/projects/${encodeURIComponent(project)}/features/${encodeURIComponent(feature)}/preview-cover`,
  readme: (project, feature) => req('GET', `/api/projects/${encodeURIComponent(project)}/features/${encodeURIComponent(feature)}/readme`),

  projectMeta: (project) => req('GET', `/api/projects/${encodeURIComponent(project)}/meta`),
  saveProjectMeta: (project, data) => req('PUT', `/api/projects/${encodeURIComponent(project)}/meta`, data),
  projectPreviewCoverUrl: (project) => `/api/projects/${encodeURIComponent(project)}/preview-cover`,

  subtitles: (project, feature) => req('GET', `/api/projects/${encodeURIComponent(project)}/features/${encodeURIComponent(feature)}/subtitles`),
  saveSubtitles: (project, feature, cues) => req('PUT', `/api/projects/${encodeURIComponent(project)}/features/${encodeURIComponent(feature)}/subtitles`, { cues }),

  fonts: () => req('GET', '/api/fonts'),
  voices: () => req('GET', '/api/voices'),

  tasks: (project, feature) => req('GET', `/api/projects/${encodeURIComponent(project)}/features/${encodeURIComponent(feature)}/tasks`),
  runTask: (project, feature, cmd) => req('POST', `/api/projects/${encodeURIComponent(project)}/features/${encodeURIComponent(feature)}/tasks`, { cmd }),

  fileUrl: (project, feature, filename) => `/api/projects/${encodeURIComponent(project)}/features/${encodeURIComponent(feature)}/files/${encodeURIComponent(filename)}`,
};

export function openTaskSocket(project, feature, onMessage) {
  const proto = location.protocol === 'https:' ? 'wss' : 'ws';
  const ws = new WebSocket(`${proto}://${location.host}/ws?project=${encodeURIComponent(project)}&feature=${encodeURIComponent(feature)}`);
  ws.onmessage = (e) => { try { onMessage(JSON.parse(e.data)); } catch {} };
  return ws;
}

import { spawn } from 'child_process';
import { EventEmitter } from 'events';
import { VT_BIN } from './paths.js';

// 只允许这些子命令通过 UI 触发——跟 video-toolkit.sh 里真实存在的 case 分支比对过，
// 排除了 config/sync（参数形状不一样，是全局命令不是"对某个 feature 操作"）。
// cmd 只能是这个集合里的字面量，不会拼接任意字符串。
// codegen 会真的弹出一个浏览器窗口等人工点击操作路径，跟 record 一样要走 guardScreenCommand。
export const ALLOWED_COMMANDS = new Set([
  'record', 'codegen', 'redub', 'dub', 'dub-en', 'mix', 'mix-en',
  'burn', 'srt', 'trans', 'en', 'all', 'status', 'cover', 'recut',
]);

// group-merge 走单独的 /groups/:id/merge 接口触发（不是"对某个 feature 操作"，
// 参数形状不一样：第二个参数是 group id 不是 feature 名），不放进上面这个集合。

export const bus = new EventEmitter();
bus.setMaxListeners(200);

// 每个 project/feature 一条串行队列，避免同一个 feature 被并发跑两个任务撞车
// （比如一边在 vt record 一边又点了 vt redub，两个进程抢同一批文件）
const queues = new Map(); // key: `${project}/${feature}` -> Promise chain
const history = new Map(); // key -> [{id, cmd, status, startedAt, finishedAt}]

function channel(project, feature) { return `${project}/${feature}`; }

export function getHistory(project, feature) {
  return history.get(channel(project, feature)) || [];
}

export function runTask(project, feature, projectDir, featureName, cmd) {
  const key = channel(project, feature);
  const id = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
  const record = { id, cmd, status: 'queued', startedAt: null, finishedAt: null };
  if (!history.has(key)) history.set(key, []);
  history.get(key).unshift(record);
  history.set(key, history.get(key).slice(0, 30));

  const prev = queues.get(key) || Promise.resolve();
  const next = prev.then(() => execOne(key, projectDir, featureName, cmd, record)).catch(() => {});
  queues.set(key, next);

  return id;
}

function execOne(key, projectDir, featureName, cmd, record) {
  return new Promise((resolve) => {
    record.status = 'running';
    record.startedAt = Date.now();
    bus.emit(key, { type: 'status', id: record.id, status: 'running' });

    const child = spawn(VT_BIN, [cmd, featureName], { cwd: projectDir });

    const onData = (chunk) => {
      const text = chunk.toString('utf8');
      for (const line of text.split(/\r?\n/)) {
        // video-toolkit.sh 输出里的颜色控制码（\x1b[0;32m 之类）是给真实终端看的，
        // 网页日志面板照单全收会变成一串乱码前后缀，这里剥掉只留文字
        const clean = line.replace(/\x1b\[[0-9;]*m/g, '').trim();
        if (clean.length === 0) continue;
        bus.emit(key, { type: 'log', id: record.id, line: clean });
      }
    };
    child.stdout.on('data', onData);
    child.stderr.on('data', onData);

    child.on('close', (code) => {
      record.status = code === 0 ? 'done' : 'failed';
      record.finishedAt = Date.now();
      bus.emit(key, { type: 'status', id: record.id, status: record.status, code });
      resolve();
    });
    child.on('error', (err) => {
      record.status = 'failed';
      record.finishedAt = Date.now();
      bus.emit(key, { type: 'log', id: record.id, line: `[启动失败] ${err.message}` });
      bus.emit(key, { type: 'status', id: record.id, status: 'failed' });
      resolve();
    });
  });
}

export { channel };

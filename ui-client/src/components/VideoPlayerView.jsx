import { api } from '../api.js';
import { useLang } from '../i18n.jsx';

// 挑成片优先级：烧了字幕的版本 > 普通合成版 > 原始录屏——跟 TaskPanel 预览用的是同一套逻辑
function pickVideoFile(f) {
  if (f.subMp4) return `${f.name}-sub.mp4`;
  if (f.mp4) return `${f.name}.mp4`;
  if (f.recording) return 'recording.mov';
  return null;
}
function statusLabel(f, t) {
  if (f.subMp4) return t('status_done');
  if (f.mp4) return t('status_mixed');
  if (f.recording) return t('status_recorded');
  return t('status_none');
}

// 视频播放模式：专门用于最后验收——大播放器 + 右侧播放列表（类似 YouTube）。
// 播放列表是"一个项目一个 PlayList"，列出项目下全部 feature（不管有没有视频），
// 还没产出视频的点开显示提示，不从列表里拿掉——不然列表数量对不上项目实际的 feature 数
export default function VideoPlayerView({ project, features, selected, onSelect }) {
  const { t } = useLang();
  const current = features.find((f) => f.name === selected) || features[0] || null;
  const file = current ? pickVideoFile(current) : null;
  const src = current && file ? api.fileUrl(project, current.name, file) : null;

  function playNext() {
    if (!current) return;
    const idx = features.findIndex((f) => f.name === current.name);
    // 自动往后找下一个真的有视频的 feature，不在没产出的空 feature 上卡住播放链
    for (let i = idx + 1; i < features.length; i++) {
      if (pickVideoFile(features[i])) { onSelect(features[i].name); return; }
    }
  }

  return (
    <div className="video-player-view">
      <div className="video-player-main">
        <div className="video-player-stage">
          {src ? (
            <video key={src} controls autoPlay src={src} onEnded={playNext} />
          ) : (
            <div className="empty-state">{current ? t('video_no_source') : t('sidebar_empty')}</div>
          )}
        </div>
      </div>
      <div className="video-playlist">
        <div className="video-playlist-head">{t('nav_features')} · {features.length}</div>
        {features.map((f) => (
          <div
            key={f.name}
            className={`video-playlist-item${current?.name === f.name ? ' active' : ''}${pickVideoFile(f) ? '' : ' disabled'}`}
            onClick={() => onSelect(f.name)}
          >
            <div className="thumb">▶</div>
            <div className="info">
              <div className="title">{f.title || f.name}</div>
              <div className="meta">{f.name} · {statusLabel(f, t)}</div>
            </div>
          </div>
        ))}
        {features.length === 0 && <div className="empty-state">{t('sidebar_empty')}</div>}
      </div>
    </div>
  );
}

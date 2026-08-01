import DataGrid from './DataGrid.jsx';
import { useLang } from '../i18n.jsx';

function featureStatusLabel(f, t) {
  if (f.subMp4) return t('status_done');
  if (f.mp4) return t('status_mixed');
  if (f.recording) return t('status_recorded');
  return t('status_none');
}

// "视图模式"里的 DataGrid 模式——跟左侧卡片列表（Sidebar）二选一，占同一个位置，
// 右边的 tabs 详情面板完全不变，只是换一种方式浏览/筛选左边的 feature 列表
export default function FeatureGridSidebar({ features, selected, onSelect }) {
  const { t } = useLang();
  const columns = [
    { key: 'title', label: t('field_title'), sortable: true, sortValue: (f) => f.title || f.name, render: (f) => <strong>{f.title || f.name}</strong> },
    { key: 'status', label: '状态', sortable: true, sortValue: (f) => featureStatusLabel(f, t), render: (f) => featureStatusLabel(f, t) },
  ];

  return (
    <div className="sidebar sidebar-grid">
      <DataGrid
        columns={columns}
        rows={features}
        rowKey={(f) => f.name}
        onRowClick={(f) => onSelect(f.name)}
        isSelected={(f) => f.name === selected}
        emptyText={t('sidebar_empty')}
      />
    </div>
  );
}

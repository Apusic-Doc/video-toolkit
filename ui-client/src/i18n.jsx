import { createContext, useContext, useState, useCallback } from 'react';

// 内部工具，默认中文（团队日常使用），可切到英文——跟 video-toolkit.bitey.ai 官网
// 默认英文正好相反，两边默认语言是各自受众决定的，不需要一致。
// 覆盖范围：导航栏/侧边栏/页面骨架/通用按钮文案；MetaFields 等表单里逐字段的
// 说明文字暂时只有中文，量太大，先保证"壳"是双语的，字段级翻译后续再补。
export const STRINGS = {
  zh: {
    nav_dashboard: '概览', nav_dashboard_projects: '项目', nav_features: '功能点', nav_groups: '分组', nav_settings: '设置',
    sidebar_project_settings: '⚙ 项目设置（字体/语音/封面统一样式）',
    sidebar_groups: '📦 分组管理',
    sidebar_new_feature: '+ 新建 Feature',
    sidebar_new_project: '+ 新建项目',
    sidebar_empty: '这个项目下还没有 feature',
    status_done: '已完成', status_mixed: '已合成', status_recorded: '已录制', status_none: '未开始',
    tab_meta: '封面 / 配置', tab_subtitles: '字幕', tab_cuts: '剪辑', tab_tasks: '任务 / 预览', tab_readme: '说明',
    empty_pick_feature: '左边选一个 feature 开始',
    loading: '加载中…',
    saving: '保存中…',
    btn_save: '保存', btn_cancel: '取消', btn_close: '关闭', btn_delete: '删除',
    btn_create: '创建', btn_add_row: '+ 新增一行',
    toast_created: '创建成功', toast_deleted: '已删除',
    new_feature_title: '新建 Feature',
    new_feature_hint: '目录名会自动生成为 feature-编号-你输入的内容',
    new_feature_placeholder: '比如 export-report',
    new_project_title: '新建项目',
    new_project_placeholder: '项目目录名，比如 demo-project',
    settings_title: '项目设置',
    settings_desc: '这里改的是整个项目统一的默认值（字体/字号/语音/封面配色等），单个 feature 没有单独设置时就会用这里的。',
    groups_title: '分组管理',
    groups_desc: '把多个 feature 的成片按顺序合并成一个对外发布的大视频。只读取各 feature 现有成片来拼接，不会修改或删除任何原始 feature 视频。',
    project_display_name: '项目显示名称（留空则显示目录名）',
    field_title: '标题', field_subtitle: '副标题',
    field_slug_feature: '目录 slug（自动根据标题生成，可手动修改）',
    field_slug_project: '目录 slug（自动根据名称生成，可手动修改）',
    field_project_name: '项目名称',
    danger_zone: '危险操作',
    danger_zone_desc: '删除这个 feature 会把整个目录挪进项目的 _trash/ 子目录，不是真的抹掉，可以手动找回，但不会再出现在列表里。',
    btn_delete_feature: '删除此 Feature',
    btn_confirm_delete: '确认删除，不再犹豫',
    new_project_next_hint: '项目已创建，接下来设置字体/语音/封面等统一样式',
    new_group_title: '新建分组', field_slug_group: '分组 id（自动根据标题生成，可手动修改）',
    groups_empty: '还没有分组',
  },
  en: {
    nav_dashboard: 'Dashboard', nav_dashboard_projects: 'Projects', nav_features: 'Features', nav_groups: 'Groups', nav_settings: 'Settings',
    sidebar_project_settings: '⚙ Project Settings (font/voice/cover)',
    sidebar_groups: '📦 Groups',
    sidebar_new_feature: '+ New Feature',
    sidebar_new_project: '+ New Project',
    sidebar_empty: 'No features in this project yet',
    status_done: 'Done', status_mixed: 'Composed', status_recorded: 'Recorded', status_none: 'Not started',
    tab_meta: 'Cover / Config', tab_subtitles: 'Subtitles', tab_cuts: 'Trim', tab_tasks: 'Tasks / Preview', tab_readme: 'Readme',
    empty_pick_feature: 'Pick a feature on the left to get started',
    loading: 'Loading…',
    saving: 'Saving…',
    btn_save: 'Save', btn_cancel: 'Cancel', btn_close: 'Close', btn_delete: 'Delete',
    btn_create: 'Create', btn_add_row: '+ Add row',
    toast_created: 'Created', toast_deleted: 'Deleted',
    new_feature_title: 'New Feature',
    new_feature_hint: 'The directory name is auto-generated as feature-NNN-<what you type>',
    new_feature_placeholder: 'e.g. export-report',
    new_project_title: 'New Project',
    new_project_placeholder: 'project directory name, e.g. demo-project',
    settings_title: 'Project Settings',
    settings_desc: "Defaults shared across the whole project (font/voice/cover color). A feature without its own override inherits these.",
    groups_title: 'Groups',
    groups_desc: "Merge several features' final videos, in order, into one video for external release. Only reads each feature's existing output — never modifies or deletes any original feature video.",
    project_display_name: 'Display name (falls back to the directory name if empty)',
    field_title: 'Title', field_subtitle: 'Subtitle',
    field_slug_feature: 'Directory slug (auto from title, editable)',
    field_slug_project: 'Directory slug (auto from name, editable)',
    field_project_name: 'Project name',
    danger_zone: 'Danger zone',
    danger_zone_desc: 'Deleting a feature moves the whole directory into the project\'s _trash/ — not permanently erased, restorable by hand, but it disappears from the list.',
    btn_delete_feature: 'Delete this feature',
    btn_confirm_delete: 'Yes, delete it',
    new_project_next_hint: 'Project created — now set up shared font/voice/cover style',
    new_group_title: 'New Group', field_slug_group: 'Group id (auto from title, editable)',
    groups_empty: 'No groups yet',
  },
};

const LangContext = createContext(null);
const LANG_KEY = 'vt-ui-lang';

export function LangProvider({ children }) {
  const [lang, setLangState] = useState(() => localStorage.getItem(LANG_KEY) || 'zh');
  const setLang = useCallback((l) => {
    localStorage.setItem(LANG_KEY, l);
    setLangState(l);
  }, []);
  const t = useCallback((key, ...args) => {
    const entry = STRINGS[lang]?.[key] ?? STRINGS.zh[key] ?? key;
    return typeof entry === 'function' ? entry(...args) : entry;
  }, [lang]);
  return <LangContext.Provider value={{ lang, setLang, t }}>{children}</LangContext.Provider>;
}

export function useLang() {
  const ctx = useContext(LangContext);
  if (!ctx) throw new Error('useLang must be used inside LangProvider');
  return ctx;
}

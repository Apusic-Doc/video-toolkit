import { useEffect, useState } from 'react';
import { renderMarkdown } from '../markdown.js';
import { api } from '../api.js';

export default function ReadmeView({ project, feature }) {
  const [html, setHtml] = useState(null);

  useEffect(() => {
    let cancelled = false;
    setHtml(null);
    api.readme(project, feature).then(({ content }) => {
      if (cancelled) return;
      setHtml(content ? renderMarkdown(content) : '');
    }).catch(() => setHtml(''));
    return () => { cancelled = true; };
  }, [project, feature]);

  if (html === null) return <div className="empty-state">加载中…</div>;
  if (html === '') return <div className="empty-state">这个 feature 还没有 README.md</div>;

  return <div className="markdown-body" dangerouslySetInnerHTML={{ __html: html }} />;
}

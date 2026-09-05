import type { ReactNode } from 'react';

export function Avatar({
  label,
  tone,
  size = 'md',
}: {
  label: string;
  tone: number;
  size?: 'sm' | 'md' | 'lg';
}) {
  return <span className={`avatar avatar-${size} avatar-tone-${tone}`}>{label}</span>;
}

export function Badge({
  children,
  tone = 'neutral',
}: {
  children: ReactNode;
  tone?: 'neutral' | 'success' | 'warning' | 'danger' | 'info';
}) {
  return <span className={`badge badge-${tone}`}>{children}</span>;
}

export function EmptyState({ title, body }: { title: string; body?: string }) {
  return (
    <div className="empty-state">
      <p className="empty-state-title">{title}</p>
      {body !== undefined ? <p className="muted">{body}</p> : null}
    </div>
  );
}

export function KpiCard({
  label,
  value,
  hint,
  tone = 'blue',
  current,
  total,
}: {
  label: string;
  value: string;
  hint?: string;
  tone?: 'blue' | 'green' | 'purple' | 'amber';
  current?: number;
  total?: number;
}) {
  const ratio =
    current !== undefined && total !== undefined && total > 0
      ? Math.min(100, Math.round((current / total) * 100))
      : null;

  return (
    <article className={`kpi-card kpi-${tone}`}>
      <p className="kpi-label">{label}</p>
      <p className="kpi-value">{value}</p>
      {ratio !== null ? (
        <div className="progress-track" aria-hidden="true">
          <div className="progress-fill" style={{ width: `${ratio}%` }} />
        </div>
      ) : null}
      {hint !== undefined ? <p className="kpi-hint">{hint}</p> : null}
    </article>
  );
}

export function Field({
  label,
  children,
}: {
  label: string;
  children: ReactNode;
}) {
  return (
    <label className="field">
      <span className="field-label">{label}</span>
      {children}
    </label>
  );
}

export function PageNotice({
  children,
  tone = 'info',
}: {
  children: ReactNode;
  tone?: 'info' | 'error';
}) {
  return <p className={`banner banner-${tone}`}>{children}</p>;
}

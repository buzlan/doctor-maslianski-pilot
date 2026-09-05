import type { ReactNode } from 'react';

export type TabItem<T extends string> = {
  id: T;
  label: string;
};

export function Tabs<T extends string>({
  items,
  value,
  onChange,
}: {
  items: readonly TabItem<T>[];
  value: T;
  onChange: (id: T) => void;
}) {
  return (
    <div className="tabs" role="tablist">
      {items.map((item) => (
        <button
          key={item.id}
          type="button"
          role="tab"
          aria-selected={item.id === value}
          className={item.id === value ? 'tab is-active' : 'tab'}
          onClick={() => onChange(item.id)}
        >
          {item.label}
        </button>
      ))}
    </div>
  );
}

export function TabPanel({
  active,
  children,
}: {
  active: boolean;
  children: ReactNode;
}) {
  if (!active) {
    return null;
  }
  return <div className="tab-panel">{children}</div>;
}

import { NavLink, Outlet } from 'react-router-dom';

import { useStaffAuth } from '../auth/StaffAuth';
import { avatarTone, initialsFromLabel } from '../lib/display';
import { Avatar } from '../ui/primitives';

function PatientsIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <path
        d="M8 14a4 4 0 1 1 0-8 4 4 0 0 1 0 8Zm8.5-1a3.5 3.5 0 1 1 0-7 3.5 3.5 0 0 1 0 7ZM3 19.2C3 16.6 6.1 15 8 15s5 1.6 5 4.2V20H3v-.8Zm11.2.8v-.6c0-1.5.7-2.8 1.8-3.6 1 .4 2.1.6 3.3.6 1 0 1.8-.1 2.7-.4V20h-7.8Z"
        fill="currentColor"
      />
    </svg>
  );
}

function CatalogIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <path
        d="M7 4h10a2 2 0 0 1 2 2v13l-4-2-3 2-3-2-4 2V6a2 2 0 0 1 2-2Z"
        stroke="currentColor"
        strokeWidth="1.7"
      />
    </svg>
  );
}

function CrossIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <path d="M10.5 4.5h3v15h-3v-15Zm-6 6h15v3h-15v-3Z" fill="currentColor" />
    </svg>
  );
}

export function AppShell() {
  const { session, signOut } = useStaffAuth();
  const name = session?.displayName ?? 'Персонал';

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="brand">
          <span className="brand-mark">
            <CrossIcon />
          </span>
          <div>
            <div className="brand-title">{session?.clinicName ?? 'Клиника'}</div>
            <div className="brand-sub">Pilot Review</div>
          </div>
        </div>
        <nav className="side-nav">
          <NavLink
            to="/patients"
            className={({ isActive }) => (isActive ? 'side-link is-active' : 'side-link')}
          >
            <PatientsIcon />
            Пациенты
          </NavLink>
          <NavLink
            to="/catalog"
            className={({ isActive }) => (isActive ? 'side-link is-active' : 'side-link')}
          >
            <CatalogIcon />
            Каталог
          </NavLink>
        </nav>
        <div className="side-card">
          Закрытый пилот: доступ только у персонала клиники. Данные пациента не попадают в
          приглашение и QR.
        </div>
      </aside>
      <div className="app-main">
        <header className="topbar">
          <div className="topbar-user">
            <Avatar label={initialsFromLabel(name)} tone={avatarTone(name)} size="sm" />
            <span className="topbar-name">{name}</span>
            <button type="button" className="ghost" onClick={() => void signOut()}>
              Выйти
            </button>
          </div>
        </header>
        <div className="app-content">
          <Outlet />
        </div>
      </div>
    </div>
  );
}

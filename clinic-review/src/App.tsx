import type { ReactNode } from 'react';
import { Link, Navigate, Route, Routes } from 'react-router-dom';

import { RequireStaff, useStaffAuth } from './auth/StaffAuth';
import { CatalogPage } from './pages/CatalogPage';
import { LoginPage } from './pages/LoginPage';
import { PatientDetailPage } from './pages/PatientDetailPage';
import { PatientNewPage } from './pages/PatientNewPage';
import { PatientsPage } from './pages/PatientsPage';

function Shell({ children }: { children: ReactNode }) {
  const auth = useStaffAuth();
  const session = auth.session;

  return (
    <>
      <header className="app-header">
        <strong>{session?.clinicName ?? 'Клиника'}</strong>
        <nav>
          <Link to="/patients">Пациенты</Link>
          <Link to="/catalog">Каталог действий</Link>
        </nav>
        <div className="row">
          <span className="muted">{session?.displayName}</span>
          <button type="button" className="secondary" onClick={() => void auth.signOut()}>
            Выйти
          </button>
        </div>
      </header>
      <main>{children}</main>
    </>
  );
}

export function App() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      <Route
        path="/patients"
        element={
          <RequireStaff>
            <Shell>
              <PatientsPage />
            </Shell>
          </RequireStaff>
        }
      />
      <Route
        path="/patients/new"
        element={
          <RequireStaff>
            <Shell>
              <PatientNewPage />
            </Shell>
          </RequireStaff>
        }
      />
      <Route
        path="/patients/:patientId"
        element={
          <RequireStaff>
            <Shell>
              <PatientDetailPage />
            </Shell>
          </RequireStaff>
        }
      />
      <Route
        path="/catalog"
        element={
          <RequireStaff>
            <Shell>
              <CatalogPage />
            </Shell>
          </RequireStaff>
        }
      />
      <Route path="/" element={<Navigate to="/patients" replace />} />
      <Route path="*" element={<Navigate to="/patients" replace />} />
    </Routes>
  );
}

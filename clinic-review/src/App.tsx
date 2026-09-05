import { Navigate, Route, Routes } from 'react-router-dom';

import { RequireStaff } from './auth/StaffAuth';
import { AppShell } from './layout/AppShell';
import { PatientsLayout } from './layout/PatientsLayout';
import { CatalogPage } from './pages/CatalogPage';
import { LoginPage } from './pages/LoginPage';
import { PatientDetailPage } from './pages/PatientDetailPage';
import { PatientNewPage } from './pages/PatientNewPage';
import { PatientsPage } from './pages/PatientsPage';

export function App() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      <Route
        element={
          <RequireStaff>
            <AppShell />
          </RequireStaff>
        }
      >
        <Route path="/patients" element={<PatientsLayout />}>
          <Route index element={<PatientsPage />} />
          <Route path="new" element={<PatientNewPage />} />
          <Route path=":patientId" element={<PatientDetailPage />} />
        </Route>
        <Route path="/catalog" element={<CatalogPage />} />
      </Route>
      <Route path="/" element={<Navigate to="/patients" replace />} />
      <Route path="*" element={<Navigate to="/patients" replace />} />
    </Routes>
  );
}

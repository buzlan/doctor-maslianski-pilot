import { Outlet } from 'react-router-dom';

import { PatientListPanel } from '../features/PatientListPanel';

export function PatientsLayout() {
  return (
    <div className="patients-split">
      <PatientListPanel />
      <Outlet />
    </div>
  );
}

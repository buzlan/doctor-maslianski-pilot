import { EmptyState } from '../ui/primitives';

export function PatientsPage() {
  return (
    <section className="workspace workspace-empty">
      <EmptyState
        title="Выберите пациента"
        body="Список слева показывает метку клиники, активацию и день текущего периода. Создайте пациента, чтобы выдать приглашение."
      />
    </section>
  );
}

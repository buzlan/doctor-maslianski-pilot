import { EmptyState } from '../ui/primitives';

export type DiaryRow = {
  id: string;
  submitted_on: string;
  pain: number;
  swelling: number;
  wellbeing: 'better' | 'unchanged' | 'worse';
};

const WELLBEING: Record<DiaryRow['wellbeing'], string> = {
  better: 'Лучше',
  unchanged: 'Без изменений',
  worse: 'Хуже',
};

export function DiaryPanel({ entries }: { entries: DiaryRow[] }) {
  return (
    <section className="card">
      <h2 className="card-title">Дневник</h2>
      {entries.length === 0 ? (
        <EmptyState title="Записей дневника нет" />
      ) : (
        <table className="data-table">
          <thead>
            <tr>
              <th>Дата</th>
              <th>Боль</th>
              <th>Отёк</th>
              <th>Самочувствие</th>
            </tr>
          </thead>
          <tbody>
            {entries.map((entry) => (
              <tr key={entry.id}>
                <td>{entry.submitted_on}</td>
                <td>{entry.pain}</td>
                <td>{entry.swelling}</td>
                <td>{WELLBEING[entry.wellbeing]}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </section>
  );
}

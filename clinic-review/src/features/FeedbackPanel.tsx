import { EmptyState } from '../ui/primitives';

export type FeedbackRow = {
  usefulness_score: number;
  clarity_score: number;
  submitted_at: string;
};

export function FeedbackPanel({ feedback }: { feedback: FeedbackRow | null }) {
  return (
    <section className="card">
      <h2 className="card-title">Обратная связь</h2>
      {feedback === null ? (
        <EmptyState title="Опрос ещё не отправлен" />
      ) : (
        <div className="kv">
          <div className="kv-row">
            <span className="kv-label">Польза</span>
            <strong>{feedback.usefulness_score} / 5</strong>
          </div>
          <div className="kv-row">
            <span className="kv-label">Понятность</span>
            <strong>{feedback.clarity_score} / 5</strong>
          </div>
          <div className="kv-row">
            <span className="kv-label">Дата</span>
            <span>{feedback.submitted_at.slice(0, 10)}</span>
          </div>
        </div>
      )}
    </section>
  );
}

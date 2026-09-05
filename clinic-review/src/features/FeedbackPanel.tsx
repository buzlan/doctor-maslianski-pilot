export type FeedbackRow = {
  usefulness_score: number;
  clarity_score: number;
  submitted_at: string;
};

export function FeedbackPanel({ feedback }: { feedback: FeedbackRow | null }) {
  return (
    <section>
      <h2>Обратная связь</h2>
      {feedback === null ? (
        <p className="muted">Опрос ещё не отправлен.</p>
      ) : (
        <p>
          Польза: {feedback.usefulness_score} / 5 · Понятность: {feedback.clarity_score} / 5 ·{' '}
          {feedback.submitted_at.slice(0, 10)}
        </p>
      )}
    </section>
  );
}

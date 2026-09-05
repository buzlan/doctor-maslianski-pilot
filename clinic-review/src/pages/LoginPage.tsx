import { FormEvent, useState } from 'react';
import { Navigate } from 'react-router-dom';

import { useStaffAuth } from '../auth/StaffAuth';

export function LoginPage() {
  const auth = useStaffAuth();
  const [email, setEmail] = useState('staff.synthetic@local.test');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (auth.status === 'ready') {
    return <Navigate to="/patients" replace />;
  }

  async function onSubmit(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    const message = await auth.signIn(email.trim(), password);
    setError(message);
    setBusy(false);
  }

  return (
    <main>
      <section className="login-card">
        <h1>Вход для персонала</h1>
        <p className="muted">Публичная регистрация отключена. Используйте выданную учётную запись.</p>
        {(error ?? auth.error) !== null ? (
          <p className="banner error">{error ?? auth.error}</p>
        ) : null}
        <form className="row" onSubmit={(event) => void onSubmit(event)}>
          <label>
            Email
            <input
              type="email"
              autoComplete="username"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              required
            />
          </label>
          <label>
            Пароль
            <input
              type="password"
              autoComplete="current-password"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              required
            />
          </label>
          <button type="submit" disabled={busy}>
            {busy ? 'Вход…' : 'Войти'}
          </button>
        </form>
      </section>
    </main>
  );
}

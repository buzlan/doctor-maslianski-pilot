import { FormEvent, useEffect, useState } from 'react';

import { useStaffAuth } from '../auth/StaffAuth';
import { publicErrorMessage } from '../lib/errors';
import { supabase } from '../lib/supabase';
import { Badge, EmptyState, Field, PageNotice } from '../ui/primitives';

type CatalogItem = {
  id: string;
  title: string;
  instruction: string | null;
  status: 'draft' | 'approved';
};

export function CatalogPage() {
  const { session } = useStaffAuth();
  const [items, setItems] = useState<CatalogItem[]>([]);
  const [title, setTitle] = useState('');
  const [instruction, setInstruction] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function load() {
    const { data, error: loadError } = await supabase
      .from('action_catalog_items')
      .select('id, title, instruction, status, sort_order')
      .order('sort_order')
      .order('created_at');

    if (loadError) {
      setError(publicErrorMessage(loadError, 'Не удалось загрузить каталог.'));
      return;
    }

    setItems(data ?? []);
    setError(null);
  }

  useEffect(() => {
    void load();
  }, []);

  async function onCreate(event: FormEvent) {
    event.preventDefault();
    if (session === null) {
      return;
    }
    setBusy(true);
    const { error: insertError } = await supabase.from('action_catalog_items').insert({
      clinic_id: session.clinicId,
      title: title.trim(),
      instruction: instruction.trim().length === 0 ? null : instruction.trim(),
      status: 'draft',
    });
    setBusy(false);
    if (insertError) {
      setError(publicErrorMessage(insertError, 'Не удалось создать пункт каталога.'));
      return;
    }
    setTitle('');
    setInstruction('');
    await load();
  }

  async function saveItem(item: CatalogItem) {
    setBusy(true);
    const { error: updateError } = await supabase
      .from('action_catalog_items')
      .update({
        title: item.title.trim(),
        instruction:
          item.instruction === null || item.instruction.trim().length === 0
            ? null
            : item.instruction.trim(),
      })
      .eq('id', item.id);
    setBusy(false);
    if (updateError) {
      setError(publicErrorMessage(updateError, 'Не удалось сохранить формулировку.'));
      return;
    }
    await load();
  }

  async function approve(id: string) {
    setBusy(true);
    const { error: updateError } = await supabase
      .from('action_catalog_items')
      .update({ status: 'approved' })
      .eq('id', id);
    setBusy(false);
    if (updateError) {
      setError(publicErrorMessage(updateError, 'Не удалось утвердить пункт.'));
      return;
    }
    await load();
  }

  return (
    <div className="catalog-page">
      <h1>Каталог действий</h1>
      <p className="muted">
        Title обязателен, инструкция необязательна. Утверждённый текст копируется в назначение.
        Изменение формулировки снова делает пункт черновиком.
      </p>
      {error !== null ? <PageNotice tone="error">{error}</PageNotice> : null}

      <section className="card">
        <h2 className="card-title">Новый пункт</h2>
        <form className="form-grid" onSubmit={(event) => void onCreate(event)}>
          <Field label="Название">
            <input value={title} onChange={(event) => setTitle(event.target.value)} required />
          </Field>
          <Field label="Инструкция">
            <input value={instruction} onChange={(event) => setInstruction(event.target.value)} />
          </Field>
          <button type="submit" disabled={busy}>
            Добавить черновик
          </button>
        </form>
      </section>

      <section className="card" style={{ marginTop: '0.9rem' }}>
        <h2 className="card-title">Пункты клиники</h2>
        {items.length === 0 ? (
          <EmptyState
            title="Каталог пуст"
            body="Добавьте и утвердите формулировку клиники."
          />
        ) : (
          items.map((item) => (
            <div key={item.id} className="catalog-item">
              <div className="form-grid">
                <Field label="Название">
                  <input
                    value={item.title}
                    onChange={(event) =>
                      setItems((current) =>
                        current.map((row) =>
                          row.id === item.id ? { ...row, title: event.target.value } : row,
                        ),
                      )
                    }
                  />
                </Field>
                <Field label="Инструкция">
                  <input
                    value={item.instruction ?? ''}
                    onChange={(event) =>
                      setItems((current) =>
                        current.map((row) =>
                          row.id === item.id ? { ...row, instruction: event.target.value } : row,
                        ),
                      )
                    }
                  />
                </Field>
                <Badge tone={item.status === 'approved' ? 'success' : 'warning'}>
                  {item.status === 'approved' ? 'утверждено' : 'черновик'}
                </Badge>
                <button
                  type="button"
                  className="secondary"
                  disabled={busy}
                  onClick={() => void saveItem(item)}
                >
                  Сохранить
                </button>
                {item.status === 'draft' ? (
                  <button type="button" disabled={busy} onClick={() => void approve(item.id)}>
                    Утвердить
                  </button>
                ) : null}
              </div>
            </div>
          ))
        )}
      </section>
    </div>
  );
}

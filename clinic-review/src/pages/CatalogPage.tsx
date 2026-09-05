import { FormEvent, useEffect, useState } from 'react';

import { useStaffAuth } from '../auth/StaffAuth';
import { publicErrorMessage } from '../lib/errors';
import { supabase } from '../lib/supabase';

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
        instruction: item.instruction === null || item.instruction.trim().length === 0
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
    <>
      <h1>Каталог действий</h1>
      <p className="muted">
        Title обязателен, инструкция необязательна. Утверждённый текст копируется в назначение.
        Изменение формулировки снова делает пункт черновиком.
      </p>
      {error !== null ? <p className="banner error">{error}</p> : null}

      <section>
        <h2>Новый пункт</h2>
        <form className="row" onSubmit={(event) => void onCreate(event)}>
          <label>
            Название
            <input value={title} onChange={(event) => setTitle(event.target.value)} required />
          </label>
          <label>
            Инструкция
            <input
              value={instruction}
              onChange={(event) => setInstruction(event.target.value)}
            />
          </label>
          <button type="submit" disabled={busy}>
            Добавить черновик
          </button>
        </form>
      </section>

      <section>
        <h2>Пункты клиники</h2>
        {items.length === 0 ? (
          <p className="muted">Каталог пуст. Добавьте и утвердите формулировку клиники.</p>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Название</th>
                <th>Инструкция</th>
                <th>Статус</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {items.map((item) => (
                <tr key={item.id}>
                  <td>
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
                  </td>
                  <td>
                    <input
                      value={item.instruction ?? ''}
                      onChange={(event) =>
                        setItems((current) =>
                          current.map((row) =>
                            row.id === item.id
                              ? { ...row, instruction: event.target.value }
                              : row,
                          ),
                        )
                      }
                    />
                  </td>
                  <td>{item.status === 'approved' ? 'утверждено' : 'черновик'}</td>
                  <td className="row">
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
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>
    </>
  );
}

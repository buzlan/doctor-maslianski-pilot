import { describe, expect, it } from 'vitest';

import { patientDetailTabs } from '../lib/patient-tabs';

function labels(input: { activated: boolean; isTest: boolean }): string[] {
  return patientDetailTabs(input).map((item) => item.label);
}

describe('patient detail tabs', () => {
  it('keeps access until the patient is activated', () => {
    expect(labels({ activated: false, isTest: false })).toContain('Доступ');
    expect(labels({ activated: false, isTest: true })).toContain('Доступ');
    expect(labels({ activated: false, isTest: true })).not.toContain('Уведомления');
  });

  it('hides access after activation and keeps notifications for test patients', () => {
    expect(labels({ activated: true, isTest: false })).not.toContain('Доступ');
    expect(labels({ activated: true, isTest: false })).not.toContain('Уведомления');
    expect(labels({ activated: true, isTest: true })).toEqual([
      'Ближайший приём',
      'Назначения',
      'Дневник',
      'Фото',
      'Визиты',
      'Уведомления',
      'Отзыв',
    ]);
  });
});

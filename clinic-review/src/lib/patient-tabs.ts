export type DetailTab =
  | 'overview'
  | 'assignments'
  | 'diary'
  | 'photos'
  | 'visits'
  | 'access'
  | 'notifications'
  | 'feedback';

export type PatientTabItem = {
  id: DetailTab;
  label: string;
};

const LEADING_TABS: PatientTabItem[] = [
  { id: 'overview', label: 'Обзор' },
  { id: 'assignments', label: 'Назначения' },
  { id: 'diary', label: 'Дневник' },
  { id: 'photos', label: 'Фото' },
  { id: 'visits', label: 'Визиты' },
];

export function patientDetailTabs(input: { activated: boolean; isTest: boolean }): PatientTabItem[] {
  const tabs = [...LEADING_TABS];
  if (!input.activated) {
    tabs.push({ id: 'access', label: 'Доступ' });
  } else if (input.isTest) {
    tabs.push({ id: 'notifications', label: 'Уведомления' });
  }
  tabs.push({ id: 'feedback', label: 'Отзыв' });
  return tabs;
}

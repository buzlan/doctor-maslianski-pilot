export type TreatmentStatus = 'active' | 'completed' | 'cancelled' | null;

export function initialsFromLabel(label: string): string {
  const parts = label
    .trim()
    .split(/\s+/)
    .filter((part) => part.length > 0);
  if (parts.length === 0) {
    return '—';
  }
  if (parts.length === 1) {
    return parts[0].slice(0, 2).toUpperCase();
  }
  return `${parts[0][0] ?? ''}${parts[1][0] ?? ''}`.toUpperCase();
}

export function avatarTone(label: string): number {
  let hash = 0;
  for (const char of label) {
    hash = (hash + char.charCodeAt(0)) % 5;
  }
  return hash;
}

export function shortId(id: string): string {
  return id.slice(0, 8);
}

export function treatmentStatusLabel(status: TreatmentStatus): string {
  if (status === 'active') {
    return 'активно';
  }
  if (status === 'completed') {
    return 'завершено';
  }
  if (status === 'cancelled') {
    return 'отменено';
  }
  return 'нет лечения';
}

export function treatmentStatusTone(
  status: TreatmentStatus,
): 'success' | 'neutral' | 'warning' | 'danger' {
  if (status === 'active') {
    return 'success';
  }
  if (status === 'completed') {
    return 'neutral';
  }
  if (status === 'cancelled') {
    return 'danger';
  }
  return 'warning';
}

export function publicErrorMessage(error: unknown, fallback: string): string {
  if (error !== null && typeof error === 'object' && 'message' in error) {
    const message = error.message;
    if (typeof message === 'string' && message.length > 0) {
      if (/token|invite\/|clinic_label|service_role/i.test(message)) {
        return fallback;
      }
      return message;
    }
  }
  return fallback;
}

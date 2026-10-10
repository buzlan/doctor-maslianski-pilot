import type { PushSendResult, PushSubscriptionTarget } from './notification-delivery.ts';

type WebPushModule = {
  setVapidDetails(subject: string, publicKey: string, privateKey: string): void;
  sendNotification(
    subscription: { endpoint: string; keys: { p256dh: string; auth: string } },
    payload: string,
  ): Promise<{ statusCode?: number }>;
};

export function readVapidConfig(): {
  subject: string;
  publicKey: string;
  privateKey: string;
} | null {
  const subject = Deno.env.get('VAPID_SUBJECT') ?? '';
  const publicKey = Deno.env.get('VAPID_PUBLIC_KEY') ?? '';
  const privateKey = Deno.env.get('VAPID_PRIVATE_KEY') ?? '';
  if (subject.length === 0 || publicKey.length === 0 || privateKey.length === 0) {
    return null;
  }
  if (publicKey === privateKey) {
    return null;
  }
  return { subject, publicKey, privateKey };
}

export async function sendWebPush(
  subscription: PushSubscriptionTarget,
  payload: string,
): Promise<PushSendResult> {
  const vapid = readVapidConfig();
  if (vapid === null) {
    return { status: null };
  }

  try {
    const imported = await import('npm:web-push@3.6.7');
    const webpush = (imported.default ?? imported) as WebPushModule;
    webpush.setVapidDetails(vapid.subject, vapid.publicKey, vapid.privateKey);
    const result = await webpush.sendNotification(
      {
        endpoint: subscription.endpoint,
        keys: { p256dh: subscription.p256dh, auth: subscription.auth },
      },
      payload,
    );
    return { status: result.statusCode ?? 201 };
  } catch (error) {
    const statusCode = error !== null && typeof error === 'object' && 'statusCode' in error
      ? Number((error as { statusCode: unknown }).statusCode)
      : Number.NaN;
    return { status: Number.isFinite(statusCode) ? statusCode : null };
  }
}

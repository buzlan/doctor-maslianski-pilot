import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react';
import { Navigate, useLocation } from 'react-router-dom';

import { publicErrorMessage } from '../lib/errors';
import { supabase } from '../lib/supabase';

export type StaffSession = {
  userId: string;
  staffId: string;
  clinicId: string;
  displayName: string;
  clinicName: string;
  timeZone: string;
};

type StaffAuthState = {
  status: 'loading' | 'unauthenticated' | 'ready' | 'forbidden';
  session: StaffSession | null;
  error: string | null;
  signIn: (email: string, password: string) => Promise<string | null>;
  signOut: () => Promise<void>;
};

const StaffAuthContext = createContext<StaffAuthState | null>(null);

async function loadStaffSession(userId: string): Promise<StaffSession | null> {
  const { data: staff, error: staffError } = await supabase
    .from('clinic_staff')
    .select('id, clinic_id, display_name')
    .maybeSingle();

  if (staffError || staff === null) {
    return null;
  }

  const { data: clinic, error: clinicError } = await supabase
    .from('clinics')
    .select('id, name, time_zone')
    .eq('id', staff.clinic_id)
    .maybeSingle();

  if (clinicError || clinic === null) {
    return null;
  }

  return {
    userId,
    staffId: staff.id,
    clinicId: staff.clinic_id,
    displayName: staff.display_name,
    clinicName: clinic.name,
    timeZone: clinic.time_zone,
  };
}

export function StaffAuthProvider({ children }: { children: ReactNode }) {
  const [status, setStatus] = useState<StaffAuthState['status']>('loading');
  const [session, setSession] = useState<StaffSession | null>(null);
  const [error, setError] = useState<string | null>(null);

  const applyUser = useCallback(async (userId: string | undefined) => {
    if (userId === undefined) {
      setSession(null);
      setStatus('unauthenticated');
      return;
    }

    const loaded = await loadStaffSession(userId);
    if (loaded === null) {
      await supabase.auth.signOut();
      setSession(null);
      setStatus('forbidden');
      setError('Этот вход не относится к персоналу клиники.');
      return;
    }

    setSession(loaded);
    setError(null);
    setStatus('ready');
  }, []);

  useEffect(() => {
    let cancelled = false;

    supabase.auth.getSession().then(({ data }) => {
      if (cancelled) {
        return;
      }
      void applyUser(data.session?.user.id);
    });

    const { data } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      void applyUser(nextSession?.user.id);
    });

    return () => {
      cancelled = true;
      data.subscription.unsubscribe();
    };
  }, [applyUser]);

  const signIn = useCallback(async (email: string, password: string) => {
    setError(null);
    const { data, error: signInError } = await supabase.auth.signInWithPassword({
      email,
      password,
    });

    if (signInError || data.user === null) {
      const message = publicErrorMessage(signInError, 'Неверный email или пароль.');
      setError(message);
      setStatus('unauthenticated');
      return message;
    }

    await applyUser(data.user.id);
    return null;
  }, [applyUser]);

  const signOut = useCallback(async () => {
    await supabase.auth.signOut();
    setSession(null);
    setStatus('unauthenticated');
    setError(null);
  }, []);

  const value = useMemo(
    () => ({ status, session, error, signIn, signOut }),
    [status, session, error, signIn, signOut],
  );

  return <StaffAuthContext.Provider value={value}>{children}</StaffAuthContext.Provider>;
}

export function useStaffAuth(): StaffAuthState {
  const value = useContext(StaffAuthContext);
  if (value === null) {
    throw new Error('useStaffAuth must be used within StaffAuthProvider');
  }
  return value;
}

export function RequireStaff({ children }: { children: ReactNode }) {
  const auth = useStaffAuth();
  const location = useLocation();

  if (auth.status === 'loading') {
    return <p className="session-loading">Загрузка сессии…</p>;
  }

  if (auth.status !== 'ready' || auth.session === null) {
    return <Navigate to="/login" replace state={{ from: location.pathname }} />;
  }

  return children;
}

import { useEffect, useState } from "react";

import { ACTION_ICON_BUCKET } from "../lib/action-icons";
import { supabase } from "../lib/supabase";

export function AssignmentIcon({ path }: { path: string | null }) {
  const [image, setImage] = useState<{ path: string; url: string } | null>(
    null,
  );

  useEffect(() => {
    let cancelled = false;
    async function resolve() {
      if (!path) return;
      const { data, error } = await supabase.storage
        .from(ACTION_ICON_BUCKET)
        .createSignedUrl(path, 300);
      if (!cancelled)
        setImage(error || !data ? null : { path, url: data.signedUrl });
    }
    void resolve();
    const timer = window.setInterval(() => void resolve(), 240000);
    return () => {
      cancelled = true;
      window.clearInterval(timer);
    };
  }, [path]);

  if (!path || image?.path !== path) return null;
  return (
    <img
      className="action-icon-preview"
      src={image.url}
      alt="Иконка назначения"
      onError={() => setImage(null)}
    />
  );
}

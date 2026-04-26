const url = import.meta.env.VITE_SUPABASE_URL as string | undefined;
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined;
const serviceKey = import.meta.env.VITE_SUPABASE_SERVICE_KEY as
  | string
  | undefined;

const placeholder = (v: string | undefined) =>
  !v || v.startsWith("PASTE_") || v.length < 40;

if (placeholder(url) || placeholder(anonKey) || placeholder(serviceKey)) {
  // eslint-disable-next-line no-console
  console.warn(
    "[refine] .env 미완성. Supabase Dashboard → Settings → API 에서 " +
      "anon key + service_role key 두 개 모두 복사해 넣어라."
  );
}

export const SUPABASE_URL = url ?? "https://jicaenyzunjdlcxcdbfb.supabase.co";
export const SUPABASE_ANON_KEY = anonKey ?? "";
export const SUPABASE_SERVICE_KEY = serviceKey ?? "";

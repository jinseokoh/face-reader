import { createClient } from "@refinedev/supabase";
import {
  SUPABASE_ANON_KEY,
  SUPABASE_SERVICE_KEY,
  SUPABASE_URL,
} from "./constants";

// 로그인 / 세션 발급 — anon key 만 사용. service_role 로는 signInWithPassword 가 거부된다.
export const supabaseAuthClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  db: { schema: "public" },
  auth: { persistSession: true },
});

// 데이터 조회 — service_role 로 RLS 우회. 모든 사용자 row SELECT 가능.
// 브라우저에 노출되므로 admin 본인만 띄우는 로컬 도구 전제.
export const supabaseAdminClient = createClient(
  SUPABASE_URL,
  SUPABASE_SERVICE_KEY,
  {
    db: { schema: "public" },
    auth: { persistSession: false, autoRefreshToken: false },
  }
);

// authProvider 가 import 하는 default client — auth 흐름은 anon 으로.
export const supabaseClient = supabaseAuthClient;

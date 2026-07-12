import { createClient, type SupabaseClient } from "@supabase/supabase-js";

/**
 * 브라우저 전용 Supabase 클라이언트 — 앱과 같은 프로젝트·같은 auth.users.
 * PKCE flow: 카카오 → 같은 /g/{id} 로 복귀, detectSessionInUrl 이 ?code= 교환.
 * anon key 는 공개키 (loader 가 내려줌).
 */
let client: SupabaseClient | null = null;

export function getSupabase(url: string, anonKey: string): SupabaseClient {
  if (!client) {
    client = createClient(url, anonKey, {
      auth: { flowType: "pkce", detectSessionInUrl: true, persistSession: true },
    });
  }
  return client;
}

/** 카카오 OAuth 시작 — 현재 페이지(쿼리 제거)로 복귀하도록 redirect. */
export async function loginWithKakao(sb: SupabaseClient): Promise<void> {
  const url = new URL(window.location.href);
  await sb.auth.signInWithOAuth({
    provider: "kakao",
    options: { redirectTo: `${url.origin}${url.pathname}` },
  });
}

/** users.nickname (self-read RLS) → 없으면 kakao user_metadata fallback. */
export async function fetchNickname(
  sb: SupabaseClient,
  uid: string,
): Promise<string> {
  const { data } = await sb
    .from("users")
    .select("nickname")
    .eq("id", uid)
    .maybeSingle();
  if (data?.nickname) return data.nickname as string;
  const { data: u } = await sb.auth.getUser();
  const meta = (u.user?.user_metadata ?? {}) as Record<string, unknown>;
  return (meta.name as string) ?? (meta.nickname as string) ?? "";
}

/** OAuth 복귀 흔적(?code=) 을 주소창에서 제거. 있었으면 true (로그인 복귀 판별용). */
export function cleanAuthParams(): boolean {
  const url = new URL(window.location.href);
  if (!url.searchParams.has("code")) return false;
  url.searchParams.delete("code");
  window.history.replaceState(null, "", url.pathname + url.search);
  return true;
}

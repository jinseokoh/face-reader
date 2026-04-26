import { dataProvider as supabaseDataProvider } from "@refinedev/supabase";
import { supabaseAdminClient } from "./supabase-client";

// data/live 둘 다 service_role client 사용 — RLS 우회로 모든 사용자 row 조회.
export const dataProvider = supabaseDataProvider(supabaseAdminClient);
export const adminClient = supabaseAdminClient;

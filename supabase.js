// The Candy Bowl — Supabase client configuration
// Replace these with the Project URL and publishable (or legacy anon) key from Supabase.
// Never put a service_role/secret key in browser code.
const SUPABASE_URL = "https://azdkajwthrdrkibuhtcg.supabase.co";
const SUPABASE_ANON_KEY = "sb_publishable_3hJPGPgN38pZyUvpIbPRDA_uKq4cjHn";

if (!window.supabase) {
  console.error("Supabase JS library did not load. Check your internet connection.");
}
const candySupabase = window.supabase?.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
window.candySupabase = candySupabase;

// The Candy Bowl — Supabase client configuration
// Replace these with the Project URL and publishable (or legacy anon) key from Supabase.
// Never put a service_role/secret key in browser code.
const SUPABASE_URL = "YOUR_SUPABASE_PROJECT_URL";
const SUPABASE_ANON_KEY = "YOUR_SUPABASE_PUBLISHABLE_OR_ANON_KEY";

if (!window.supabase) {
  console.error("Supabase JS library did not load. Check your internet connection.");
}
const candySupabase = window.supabase?.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
window.candySupabase = candySupabase;

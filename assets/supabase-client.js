(function () {
  'use strict';

  const SUPABASE_URL = "https://qqefegpievdlaprwzktx.supabase.co";
  const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFxZWZlZ3BpZXZkbGFwcnd6a3R4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI0ODQxNzAsImV4cCI6MjA5ODA2MDE3MH0.1h_585aBtTnXtA0FLtbNvhkYpVokgfHbUpKcAIBImKY";

  window.SirFisherSupabase = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
})();

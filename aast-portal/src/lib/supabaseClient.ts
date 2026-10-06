import { createClient } from "@supabase/supabase-js";

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL as string;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string;

// Each portal tab keeps its own identity. A student login in another tab must
// not replace the staff token while the staff page still shows that user.
export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: { storage: window.sessionStorage },
});

/**
 * Students and staff log in with their ID, not an email. Supabase Auth still
 * requires an email internally, so every account uses a hidden, generated one
 * -- the person never sees or types it.
 */
export function idToHiddenEmail(role: "student" | "staff", id: string): string {
  const domain =
    role === "student" ? "students.aegisos.local" : "staff.aegisos.local";
  return `${id}@${domain}`;
}

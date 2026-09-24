import { createContext, useContext, useState, type ReactNode } from "react";
import {
  validateStaffId,
  validateStudentId,
  type ValidatedStudent,
} from "@/lib/portalGrades";
import { supabase, idToHiddenEmail } from "@/lib/supabaseClient";

export type PortalRole = "student" | "staff";

export interface StudentProfile {
  student_id: string;
  name: string;
  major: string;
  year: number;
  gpa: number | null;
  courses: string[];
}

interface AuthContextValue {
  isAuthenticated: boolean;
  role: PortalRole | null;
  portalId: string | null;
  academicStudentId: string | null;
  student: StudentProfile | null;
  login: (
    role: PortalRole,
    id: string,
    password: string,
  ) => Promise<{ success: boolean; error?: string }>;
  logout: () => void;
}

const AuthContext = createContext<AuthContextValue | undefined>(undefined);

interface StoredSession {
  role: PortalRole | null;
  portalId: string | null;
  academicStudentId: string | null;
  student: StudentProfile | null;
}

const STORAGE_KEY = "aast-portal-auth";

function readStoredSession(): StoredSession {
  const stored = sessionStorage.getItem(STORAGE_KEY);
  if (!stored) {
    return {
      role: null,
      portalId: null,
      academicStudentId: null,
      student: null,
    };
  }
  if (stored === "student" || stored === "staff") {
    return {
      role: stored,
      portalId: null,
      academicStudentId: null,
      student: null,
    };
  }
  try {
    const parsed = JSON.parse(stored) as Partial<StoredSession>;
    if (parsed.role === "student" || parsed.role === "staff") {
      return {
        role: parsed.role,
        portalId: parsed.portalId ?? null,
        academicStudentId: parsed.academicStudentId ?? null,
        student: parsed.student ?? null,
      };
    }
  } catch {
    // Ignore invalid persisted state and fall back to a signed-out session.
  }
  return { role: null, portalId: null, academicStudentId: null, student: null };
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState(readStoredSession);

  const login = async (
    selectedRole: PortalRole,
    id: string,
    password: string,
  ) => {
    const normalizedId = id.trim();
    if (!normalizedId) {
      return { success: false, error: "Please enter your ID." };
    }
    if (!password) {
      return { success: false, error: "Please enter your password." };
    }

    const email = idToHiddenEmail(selectedRole, normalizedId);
    const { error: authError } = await supabase.auth.signInWithPassword({
      email,
      password,
    });
    if (authError) {
      return { success: false, error: "Incorrect ID or password." };
    }

    try {
      if (selectedRole === "student") {
        const student = await validateStudentId(normalizedId);
        if (student === null) {
          return {
            success: false,
            error:
              "Student ID not found. Please check your registration number.",
          };
        }
        const profile: StudentProfile = {
          student_id: student.student_id,
          name: student.name,
          major: student.major,
          year: student.year,
          gpa: student.gpa,
          courses: student.courses,
        };
        const nextSession: StoredSession = {
          role: "student",
          portalId: normalizedId,
          academicStudentId: student.student_id,
          student: profile,
        };
        sessionStorage.setItem(STORAGE_KEY, JSON.stringify(nextSession));
        setSession(nextSession);
        return { success: true };
      }

      const valid = await validateStaffId(normalizedId);
      if (!valid) {
        return {
          success: false,
          error:
            "Staff ID not recognized. Please contact IT if this is a new account.",
        };
      }
      const nextSession: StoredSession = {
        role: "staff",
        portalId: normalizedId,
        academicStudentId: null,
        student: null,
      };
      sessionStorage.setItem(STORAGE_KEY, JSON.stringify(nextSession));
      setSession(nextSession);
      return { success: true };
    } catch (err) {
      return {
        success: false,
        error:
          err instanceof Error
            ? err.message
            : "Could not reach the academic server. Make sure the AegisOS backend is running.",
      };
    }
  };

  const logout = () => {
    sessionStorage.removeItem(STORAGE_KEY);
    setSession({
      role: null,
      portalId: null,
      academicStudentId: null,
      student: null,
    });
  };

  const isAuthenticated = session.role !== null;

  return (
    <AuthContext.Provider
      value={{
        isAuthenticated,
        role: session.role,
        portalId: session.portalId,
        academicStudentId: session.academicStudentId,
        student: session.student,
        login,
        logout,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used within AuthProvider");
  return ctx;
}

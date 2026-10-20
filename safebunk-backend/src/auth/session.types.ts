/**
 * Session shapes are intentionally discriminated by `role`.
 *
 * The role is assigned by the backend when the session is created:
 * - Linways student login -> STUDENT
 * - Local staff login -> STAFF or ADMIN, read from the StaffUser row
 *
 * A client never supplies a role when authenticating.
 */
export const STAFF_ROLES = ['STAFF', 'ADMIN'] as const;

export type StaffRole = (typeof STAFF_ROLES)[number];

export function isStaffRole(value: unknown): value is StaffRole {
  return value === 'STAFF' || value === 'ADMIN';
}

export interface StudentSession {
  token: string;
  role: 'STUDENT';
  studentId: string;
  username: string;
  cookies: string;
  authToken: string;
  createdAt: number;
}

export interface StaffSession {
  token: string;
  role: StaffRole;
  staffId: string;
  username: string;
  createdAt: number;
}

export type Session = StudentSession | StaffSession;

export function isStudentSession(session: Session): session is StudentSession {
  return session.role === 'STUDENT';
}

export function isStaffSession(session: Session): session is StaffSession {
  return session.role === 'STAFF' || session.role === 'ADMIN';
}

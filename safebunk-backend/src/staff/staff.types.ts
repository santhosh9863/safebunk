import { StaffRole } from '../auth/session.types';

export interface StaffIdentity {
  id: string;
  username: string;
  displayName: string | null;
  role: StaffRole;
}

export interface StaffAccountSummary extends StaffIdentity {
  active: boolean;
  createdAt: Date;
}

/** Staff usernames are case-insensitive; store and look them up normalized. */
export function normalizeStaffUsername(username: string): string {
  return username.trim().toLowerCase();
}

export const STAFF_PASSWORD_MIN_LENGTH = 12;
export const STAFF_PASSWORD_MAX_LENGTH = 256;
export const STAFF_USERNAME_MIN_LENGTH = 3;
export const STAFF_USERNAME_MAX_LENGTH = 64;

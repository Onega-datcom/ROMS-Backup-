export const STAFF_ROLES = [
  "Administrator",
  "Manager",
  "Receptionist",
  "Inventory Clerk",
  "Chef / Kitchen Staff",
] as const;

export type StaffRole = typeof STAFF_ROLES[number];
export const INVITABLE_ROLES = STAFF_ROLES.filter(
  (role): role is Exclude<StaffRole, "Administrator"> =>
    role !== "Administrator",
);
export type InvitableRole = typeof INVITABLE_ROLES[number];

export class InviteValidationError extends Error {}

const EMAIL_PATTERN =
  /^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$/;
const INVITE_FIELDS = new Set(["email", "full_name", "role"]);

export interface InvitePayload {
  email: string;
  full_name: string;
  role: InvitableRole;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isInvitableRole(value: unknown): value is InvitableRole {
  return typeof value === "string" &&
    INVITABLE_ROLES.some((role) => role === value);
}

export function normalizeAndValidateEmail(value: unknown): string {
  if (typeof value !== "string") {
    throw new InviteValidationError("A valid email address is required.");
  }

  const email = value.trim().toLowerCase();
  const [localPart] = email.split("@");
  if (
    email.length < 3 ||
    email.length > 254 ||
    !localPart ||
    localPart.length > 64 ||
    !EMAIL_PATTERN.test(email)
  ) {
    throw new InviteValidationError("A valid email address is required.");
  }

  return email;
}

export function parseInvitePayload(value: unknown): InvitePayload {
  if (!isRecord(value)) {
    throw new InviteValidationError("A JSON invitation object is required.");
  }

  if (Object.keys(value).some((key) => !INVITE_FIELDS.has(key))) {
    throw new InviteValidationError(
      "The invitation contains unsupported fields.",
    );
  }

  const email = normalizeAndValidateEmail(value.email);
  if (typeof value.full_name !== "string") {
    throw new InviteValidationError("A full name is required.");
  }

  const fullName = value.full_name.trim();
  const fullNameLength = Array.from(fullName).length;
  if (fullNameLength < 1 || fullNameLength > 160) {
    throw new InviteValidationError(
      "Full name must be between 1 and 160 characters.",
    );
  }

  if (!isInvitableRole(value.role)) {
    throw new InviteValidationError("A valid staff role is required.");
  }

  return { email, full_name: fullName, role: value.role };
}

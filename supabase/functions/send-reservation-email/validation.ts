export interface ReservationEmailRequest {
  reference: string;
  email: string;
}

export class ReservationEmailValidationError extends Error {}

const REFERENCE_PATTERN = /^RSV-[A-F0-9]{32}$/;
const EMAIL_PATTERN = /^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$/i;
const ALLOWED_FIELDS = new Set(["reference", "email"]);

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function parseReservationEmailRequest(
  value: unknown,
): ReservationEmailRequest {
  if (!isRecord(value)) {
    throw new ReservationEmailValidationError(
      "A JSON request object is required.",
    );
  }
  if (Object.keys(value).some((key) => !ALLOWED_FIELDS.has(key))) {
    throw new ReservationEmailValidationError(
      "The request contains unsupported fields.",
    );
  }

  if (
    typeof value.reference !== "string" ||
    !REFERENCE_PATTERN.test(value.reference.trim().toUpperCase())
  ) {
    throw new ReservationEmailValidationError(
      "A valid reservation reference is required.",
    );
  }

  if (typeof value.email !== "string") {
    throw new ReservationEmailValidationError(
      "A valid email address is required.",
    );
  }
  const email = value.email.trim();
  if (email.length > 254 || !EMAIL_PATTERN.test(email)) {
    throw new ReservationEmailValidationError(
      "A valid email address is required.",
    );
  }

  return { reference: value.reference.trim().toUpperCase(), email };
}

export function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, (character) => {
    switch (character) {
      case "&":
        return "&amp;";
      case "<":
        return "&lt;";
      case ">":
        return "&gt;";
      case '"':
        return "&quot;";
      case "'":
        return "&#39;";
      default:
        return character;
    }
  });
}

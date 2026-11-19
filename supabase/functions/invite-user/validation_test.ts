import {
  InviteValidationError,
  normalizeAndValidateEmail,
  parseInvitePayload,
} from "./validation.ts";

function assertEquals<T>(actual: T, expected: T, message: string): void {
  if (actual !== expected) {
    throw new Error(
      `${message}; expected ${String(expected)}, received ${String(actual)}`,
    );
  }
}

function assertValidationError(action: () => unknown, message: string): void {
  try {
    action();
  } catch (error) {
    if (error instanceof InviteValidationError) return;
    throw error;
  }
  throw new Error(message);
}

Deno.test("normalizes valid email and invitation fields", () => {
  const invite = parseInvitePayload({
    email: "  Staff.Member@Example.COM ",
    full_name: "  Staff Member  ",
    role: "Receptionist",
  });

  assertEquals(
    invite.email,
    "staff.member@example.com",
    "email should be normalized",
  );
  assertEquals(invite.full_name, "Staff Member", "full name should be trimmed");
  assertEquals(invite.role, "Receptionist", "staff role should be retained");
});

Deno.test("accepts each supported staff role", () => {
  const roles = [
    "Administrator",
    "Manager",
    "Receptionist",
    "Inventory Clerk",
    "Chef / Kitchen Staff",
  ];

  for (const role of roles) {
    assertEquals(
      parseInvitePayload({
        email: "staff@example.com",
        full_name: "Staff Member",
        role,
      }).role,
      role,
      `role ${role} should be accepted`,
    );
  }
});

Deno.test("rejects invalid email addresses", () => {
  for (
    const email of [
      "not-an-email",
      "staff@localhost",
      "staff@example..com",
      "x".repeat(65) + "@example.com",
    ]
  ) {
    assertValidationError(
      () => normalizeAndValidateEmail(email),
      `email ${email} should be rejected`,
    );
  }
});

Deno.test("rejects invalid roles, blank names, and caller-supplied fields", () => {
  const valid = {
    email: "staff@example.com",
    full_name: "Staff Member",
    role: "Manager",
  };

  assertValidationError(
    () => parseInvitePayload({ ...valid, role: "Customer" }),
    "Customer should not be an invitation role",
  );
  assertValidationError(
    () => parseInvitePayload({ ...valid, full_name: "  " }),
    "blank names should be rejected",
  );
  assertValidationError(
    () => parseInvitePayload({ ...valid, invited_by: "attacker-id" }),
    "caller-supplied inviter identity should be rejected",
  );
});

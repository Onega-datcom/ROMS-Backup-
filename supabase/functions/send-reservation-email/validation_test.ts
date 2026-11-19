import {
  escapeHtml,
  parseReservationEmailRequest,
  ReservationEmailValidationError,
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
    if (error instanceof ReservationEmailValidationError) return;
    throw error;
  }
  throw new Error(message);
}

Deno.test("normalizes a valid reservation email request", () => {
  const request = parseReservationEmailRequest({
    reference: "rsv-0123456789abcdef0123456789abcdef",
    email: "  guest@example.com  ",
  });

  assertEquals(
    request.reference,
    "RSV-0123456789ABCDEF0123456789ABCDEF",
    "reservation reference should be normalized",
  );
  assertEquals(request.email, "guest@example.com", "email should be trimmed");
});

Deno.test("rejects malformed or caller-extended email requests", () => {
  for (
    const request of [
      null,
      { reference: "not-a-reservation", email: "guest@example.com" },
      { reference: "RSV-0123456789ABCDEF0123456789ABCDEF", email: "bad-email" },
      {
        reference: "RSV-0123456789ABCDEF0123456789ABCDEF",
        email: "guest@example.com",
        guests: 500,
      },
    ]
  ) {
    assertValidationError(
      () => parseReservationEmailRequest(request),
      "invalid reservation email request should be rejected",
    );
  }
});

Deno.test("escapes customer-provided content before inserting it in HTML", () => {
  assertEquals(
    escapeHtml(`<img src="x" onerror='alert(1)'>&`),
    "&lt;img src=&quot;x&quot; onerror=&#39;alert(1)&#39;&gt;&amp;",
    "HTML special characters should be escaped",
  );
});

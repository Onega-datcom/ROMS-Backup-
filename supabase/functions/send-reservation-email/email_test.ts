import {
  createReservationEmailContent,
  type ReservationEmailRow,
} from "./email.ts";

function assert(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

Deno.test("creates an escaped Pending-request email with the stored details", () => {
  const reservation: ReservationEmailRow = {
    id: "RSV-0123456789ABCDEF0123456789ABCDEF",
    name: "<Guest>",
    email: "guest@example.com",
    reservation_date: "2026-11-25",
    reservation_time: "11:00 AM",
    guests: 5,
    status: "Pending",
  };
  const content = createReservationEmailContent(reservation);

  assert(
    content.subject === `Reservation request received - ${reservation.id}`,
    "subject should identify the reservation request",
  );
  assert(
    content.html.includes("&lt;Guest&gt;"),
    "customer name should be HTML escaped",
  );
  assert(
    content.html.includes("not confirmed until the restaurant approves it"),
    "message should preserve Pending semantics",
  );
  assert(
    content.html.includes("2026-11-25") && content.html.includes("11:00 AM"),
    "date and time should be included",
  );
  assert(
    content.text.includes("Guests: 5"),
    "total guest count should be included",
  );
});

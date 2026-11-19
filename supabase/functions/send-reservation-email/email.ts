import { escapeHtml } from "./validation.ts";

export interface ReservationEmailRow {
  id: string;
  name: string;
  email: string;
  reservation_date: string;
  reservation_time: string;
  guests: number;
  status: string;
}

export interface ReservationEmailContent {
  subject: string;
  html: string;
  text: string;
}

export function createReservationEmailContent(
  reservation: ReservationEmailRow,
): ReservationEmailContent {
  const heading = reservation.status === "Confirmed"
    ? "Reservation confirmed"
    : reservation.status === "Pending"
    ? "Reservation request received"
    : "Reservation status update";
  const statusMessage = reservation.status === "Pending"
    ? "Our team will review it; this request is not confirmed until the restaurant approves it."
    : reservation.status === "Confirmed"
    ? "The restaurant has confirmed your reservation."
    : `Current reservation status: ${reservation.status}.`;
  const safeStatusMessage = escapeHtml(statusMessage);
  const safeName = escapeHtml(reservation.name);
  const safeReference = escapeHtml(reservation.id);
  const safeDate = escapeHtml(reservation.reservation_date);
  const safeTime = escapeHtml(reservation.reservation_time);
  const html = `
    <div style="font-family:Arial,sans-serif;max-width:500px;margin:auto;padding:20px;border:1px solid #eee;border-radius:8px">
      <h2>${heading}</h2>
      <p>Hi <strong>${safeName}</strong>,</p>
      <p>Thank you for requesting a reservation. ${safeStatusMessage}</p>
      <p>Your reservation reference:</p>
      <div style="background:#f4f4f4;padding:15px;text-align:center;font-size:24px;font-weight:bold;letter-spacing:2px;border-radius:6px;margin:20px 0">${safeReference}</div>
      <p><strong>Date:</strong> ${safeDate}<br>
      <strong>Time:</strong> ${safeTime}<br>
      <strong>Guests:</strong> ${reservation.guests}</p>
      <p>Keep this reference to check your reservation status.</p>
    </div>`;
  const text = [
    heading,
    "",
    `Hi ${reservation.name},`,
    `Thank you for requesting a reservation. ${statusMessage}`,
    "",
    `Reference: ${reservation.id}`,
    `Date: ${reservation.reservation_date}`,
    `Time: ${reservation.reservation_time}`,
    `Guests: ${reservation.guests}`,
    "",
    "Keep this reference to check your reservation status.",
  ].join("\n");

  return {
    subject: `${heading} - ${reservation.id}`,
    html,
    text,
  };
}

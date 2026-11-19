import { createClient } from "npm:@supabase/supabase-js@2";
import nodemailer from "npm:nodemailer@6.9.13";
import {
  createReservationEmailContent,
  type ReservationEmailRow,
} from "./email.ts";
import {
  parseReservationEmailRequest,
  ReservationEmailValidationError,
} from "./validation.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Max-Age": "86400",
  "Content-Type": "application/json",
};
const MAX_BODY_BYTES = 4096;
const SMTP_TIMEOUT_MS = 10000;

class HttpError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
  }
}

function jsonResponse(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: CORS_HEADERS });
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new HttpError(
      500,
      "The reservation email service is not configured.",
    );
  }
  return value;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function logFailure(
  requestId: string,
  operation: string,
  error?: unknown,
): void {
  const code = typeof error === "object" && error !== null && "code" in error &&
      typeof error.code === "string"
    ? error.code.slice(0, 64)
    : error instanceof Error
    ? error.name
    : "unknown_error";
  console.error(JSON.stringify({
    event: "reservation_reference_email_failed",
    request_id: requestId,
    operation,
    error_code: code,
  }));
}

function isReservationEmailRow(value: unknown): value is ReservationEmailRow {
  if (!isRecord(value)) {
    return false;
  }
  return typeof value.id === "string" &&
    typeof value.name === "string" &&
    typeof value.email === "string" &&
    typeof value.reservation_date === "string" &&
    typeof value.reservation_time === "string" &&
    typeof value.guests === "number" &&
    Number.isInteger(value.guests) &&
    value.guests > 0 &&
    typeof value.status === "string";
}

async function sendGmailMessage(
  requestId: string,
  reservation: ReservationEmailRow,
): Promise<void> {
  const sender = requiredEnv("GMAIL_USER");
  const appPassword = requiredEnv("GMAIL_APP_PASSWORD").replace(/\s/g, "");
  if (!/^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$/i.test(sender)) {
    throw new HttpError(500, "GMAIL_USER must be a valid email address.");
  }
  if (!/^[A-Z0-9]{16}$/i.test(appPassword)) {
    throw new HttpError(
      500,
      "GMAIL_APP_PASSWORD must be a valid 16-character Gmail App Password.",
    );
  }

  const transporter = nodemailer.createTransport({
    service: "gmail",
    auth: { user: sender, pass: appPassword },
    connectionTimeout: SMTP_TIMEOUT_MS,
    greetingTimeout: SMTP_TIMEOUT_MS,
    socketTimeout: SMTP_TIMEOUT_MS,
  });
  try {
    await transporter.sendMail({
      from: `"Restaurant Reservations" <${sender}>`,
      to: reservation.email,
      ...createReservationEmailContent(reservation),
    });
  } catch (error) {
    logFailure(requestId, "gmail_smtp_send", error);
    throw new HttpError(
      502,
      "The reservation reference email could not be sent.",
    );
  } finally {
    transporter.close();
  }
}

async function handleRequest(request: Request): Promise<Response> {
  const requestId = crypto.randomUUID();
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (request.method !== "POST") {
    return jsonResponse(405, { error: "Only POST requests are supported." });
  }

  try {
    const bodyText = await request.text();
    if (new TextEncoder().encode(bodyText).byteLength > MAX_BODY_BYTES) {
      throw new HttpError(413, "Request body is too large.");
    }
    let parsedBody: unknown;
    try {
      parsedBody = JSON.parse(bodyText);
    } catch {
      throw new HttpError(400, "Request body must contain valid JSON.");
    }

    let input: ReturnType<typeof parseReservationEmailRequest>;
    try {
      input = parseReservationEmailRequest(parsedBody);
    } catch (error) {
      if (error instanceof ReservationEmailValidationError) {
        throw new HttpError(400, error.message);
      }
      throw error;
    }

    const serviceClient = createClient(
      requiredEnv("SUPABASE_URL"),
      requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
      { auth: { autoRefreshToken: false, persistSession: false } },
    );
    const { data, error } = await serviceClient
      .from("reservations")
      .select("id,name,email,reservation_date,reservation_time,guests,status")
      .eq("id", input.reference)
      .eq("email", input.email)
      .eq("source", "Website")
      .eq("type", "Reservation")
      .maybeSingle();
    if (error) {
      logFailure(requestId, "reservation_lookup", error);
      throw new HttpError(500, "Could not verify the reservation.");
    }
    if (!isReservationEmailRow(data)) {
      throw new HttpError(
        404,
        "No website reservation matched that reference and email address.",
      );
    }

    await sendGmailMessage(requestId, data);
    return jsonResponse(200, { sent: true });
  } catch (error) {
    if (error instanceof HttpError) {
      return jsonResponse(error.status, {
        error: error.message,
        request_id: requestId,
      });
    }
    logFailure(requestId, "unhandled_request", error);
    return jsonResponse(500, {
      error: "The reservation reference email could not be sent.",
      request_id: requestId,
    });
  }
}

Deno.serve(handleRequest);

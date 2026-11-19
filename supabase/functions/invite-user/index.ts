import { createClient } from "npm:@supabase/supabase-js@2";
import {
  InviteValidationError,
  normalizeAndValidateEmail,
  parseInvitePayload,
} from "./validation.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Max-Age": "86400",
  "Content-Type": "application/json",
};
const MAX_BODY_BYTES = 16_384;
const INVITE_VALIDITY_DAYS = 7;

type JsonRecord = Record<string, unknown>;

class HttpError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
  }
}

function jsonResponse(status: number, body: JsonRecord): Response {
  return new Response(JSON.stringify(body), { status, headers: CORS_HEADERS });
}

function readErrorCode(error: unknown): string {
  if (typeof error === "object" && error !== null && "code" in error) {
    const code = error.code;
    if (typeof code === "string" && /^[a-z0-9_-]{1,64}$/i.test(code)) {
      return code;
    }
  }
  return error instanceof Error ? error.name : "unknown_error";
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new HttpError(500, `Server configuration is missing ${name}.`);
  }
  return value;
}

function getRedirectUrl(): string {
  const value = requiredEnv("INVITE_REDIRECT_URL");
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    throw new HttpError(500, "Server invitation redirect URL is invalid.");
  }
  const isLocalHttp = url.protocol === "http:" &&
    ["localhost", "127.0.0.1"].includes(url.hostname);
  if (url.protocol !== "https:" && !isLocalHttp) {
    throw new HttpError(500, "Server invitation redirect URL must use HTTPS.");
  }
  return url.toString();
}

function getBearerToken(request: Request): string {
  const header = request.headers.get("authorization") ?? "";
  const match = /^Bearer\s+([^\s]+)$/i.exec(header);
  if (!match) {
    throw new HttpError(401, "A valid signed-in session is required.");
  }
  return match[1];
}

function getObject(value: unknown): JsonRecord {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new HttpError(400, "A JSON request object is required.");
  }
  return value as JsonRecord;
}

function createServiceClient(url: string, serviceRoleKey: string) {
  return createClient(url, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

async function cancelPendingInvitation(
  serviceClient: ReturnType<typeof createServiceClient>,
  invitationId: string,
): Promise<{ succeeded: boolean; error?: unknown }> {
  const { data, error } = await serviceClient
    .from("user_invites")
    .update({ status: "Cancelled" })
    .eq("id", invitationId)
    .eq("status", "Pending")
    .select("id")
    .maybeSingle();
  if (error) return { succeeded: false, error };
  if (!data) {
    return {
      succeeded: false,
      error: new Error("Pending invitation was not found during cancellation."),
    };
  }
  return { succeeded: true };
}

function logFailure(
  requestId: string,
  operation: string,
  error: unknown,
): void {
  console.error(JSON.stringify({
    event: "invite_user_operation_failed",
    request_id: requestId,
    operation,
    error_code: readErrorCode(error),
  }));
}

async function createInvitation(
  requestId: string,
  body: JsonRecord,
  userId: string,
  serviceClient: ReturnType<typeof createServiceClient>,
  redirectUrl: string,
): Promise<Response> {
  if (body.action !== "invite") {
    throw new HttpError(400, "A supported invitation action is required.");
  }

  const allowedFields = new Set(["action", "email", "full_name", "role"]);
  if (Object.keys(body).some((key) => !allowedFields.has(key))) {
    throw new HttpError(400, "The invitation contains unsupported fields.");
  }

  let invite: ReturnType<typeof parseInvitePayload>;
  try {
    invite = parseInvitePayload({
      email: body.email,
      full_name: body.full_name,
      role: body.role,
    });
  } catch (error) {
    if (error instanceof InviteValidationError) {
      throw new HttpError(400, error.message);
    }
    throw error;
  }

  const escapedEmail = invite.email.replace(/[%_\\]/g, "\\$&");
  const { data: existingProfile, error: profileLookupError } =
    await serviceClient
      .from("profiles")
      .select("id")
      .ilike("email", escapedEmail)
      .limit(1)
      .maybeSingle();
  if (profileLookupError) {
    logFailure(requestId, "profile_lookup", profileLookupError);
    throw new HttpError(
      500,
      "Could not verify whether the email already has a profile.",
    );
  }
  if (existingProfile) {
    throw new HttpError(
      409,
      "An account already exists for this email address.",
    );
  }

  const { data: existingInvitation, error: invitationLookupError } =
    await serviceClient
      .from("user_invites")
      .select("id")
      .eq("email", invite.email)
      .eq("status", "Pending")
      .maybeSingle();
  if (invitationLookupError) {
    logFailure(requestId, "invitation_lookup", invitationLookupError);
    throw new HttpError(500, "Could not verify existing invitations.");
  }
  if (existingInvitation) {
    throw new HttpError(
      409,
      "A pending invitation already exists for this email address.",
    );
  }

  const expiresAt = new Date(
    Date.now() + INVITE_VALIDITY_DAYS * 24 * 60 * 60 * 1000,
  ).toISOString();
  const { data: invitation, error: invitationInsertError } = await serviceClient
    .from("user_invites")
    .insert({
      email: invite.email,
      full_name: invite.full_name,
      role: invite.role,
      invited_by: userId,
      expires_at: expiresAt,
    })
    .select("id, expires_at")
    .single();
  if (invitationInsertError || !invitation) {
    if (invitationInsertError?.code === "23505") {
      throw new HttpError(
        409,
        "A pending invitation already exists for this email address.",
      );
    }
    logFailure(
      requestId,
      "invitation_insert",
      invitationInsertError ?? new Error("No invitation returned."),
    );
    throw new HttpError(500, "The invitation record could not be created.");
  }

  const { data: authInvitation, error: authInviteError } = await serviceClient
    .auth.admin
    .inviteUserByEmail(invite.email, {
      data: { full_name: invite.full_name, role: invite.role },
      redirectTo: redirectUrl,
    });
  if (authInviteError || !authInvitation.user) {
    const cleanup = await cancelPendingInvitation(
      serviceClient,
      invitation.id,
    );
    if (!cleanup.succeeded) {
      logFailure(
        requestId,
        "cancel_failed_auth_invite",
        cleanup.error,
      );
      throw new HttpError(
        500,
        "The email invitation failed and its database record needs administrator review.",
      );
    }
    logFailure(
      requestId,
      "auth_invite",
      authInviteError ?? new Error("No Auth user returned."),
    );
    if (authInviteError?.status === 422) {
      throw new HttpError(
        409,
        "An Auth account already exists for this email address.",
      );
    }
    if (authInviteError?.status === 429) {
      throw new HttpError(
        429,
        "Supabase Auth email rate limit reached. Try again later.",
      );
    }
    throw new HttpError(
      502,
      "Supabase Auth could not send the invitation. Check email and redirect configuration.",
    );
  }

  const { error: profileInsertError } = await serviceClient
    .from("profiles")
    .insert({
      id: authInvitation.user.id,
      email: invite.email,
      full_name: invite.full_name,
      role: invite.role,
    });
  if (profileInsertError) {
    logFailure(requestId, "profile_insert", profileInsertError);
    const { error: deleteUserError } = await serviceClient.auth.admin
      .deleteUser(authInvitation.user.id);
    if (deleteUserError) {
      logFailure(requestId, "auth_user_compensation", deleteUserError);
      throw new HttpError(
        500,
        "Account setup failed after sending the email; administrator reconciliation is required.",
      );
    }

    const cleanup = await cancelPendingInvitation(
      serviceClient,
      invitation.id,
    );
    if (!cleanup.succeeded) {
      logFailure(requestId, "cancel_failed_profile_insert", cleanup.error);
      throw new HttpError(
        500,
        "Account setup failed and invitation cleanup needs administrator review.",
      );
    }
    throw new HttpError(
      profileInsertError.code === "23505" ? 409 : 500,
      profileInsertError.code === "23505"
        ? "An account already exists for this email address."
        : "The invitation email was sent, but profile setup failed. The invite was rolled back; please retry.",
    );
  }

  return jsonResponse(201, {
    invitation_id: invitation.id,
    email: invite.email,
    status: "Pending",
    expires_at: invitation.expires_at,
    request_id: requestId,
  });
}

async function acceptInvitation(
  requestId: string,
  body: JsonRecord,
  user: { id: string; email?: string; email_confirmed_at?: string },
  serviceClient: ReturnType<typeof createServiceClient>,
): Promise<Response> {
  if (
    body.action !== "accept" ||
    Object.keys(body).some((key) => key !== "action")
  ) {
    throw new HttpError(
      400,
      "A valid invitation acceptance action is required.",
    );
  }
  if (!user.email || !user.email_confirmed_at) {
    throw new HttpError(403, "A confirmed invitation email is required.");
  }

  let email: string;
  try {
    email = normalizeAndValidateEmail(user.email);
  } catch {
    throw new HttpError(
      403,
      "The signed-in account does not have a valid confirmed email.",
    );
  }

  const { data: profile, error: profileError } = await serviceClient
    .from("profiles")
    .select("email")
    .eq("id", user.id)
    .maybeSingle();
  if (profileError) {
    logFailure(requestId, "accept_profile_lookup", profileError);
    throw new HttpError(500, "Could not verify the invited account profile.");
  }
  if (!profile || profile.email.trim().toLowerCase() !== email) {
    throw new HttpError(
      403,
      "The signed-in account does not match an invitation profile.",
    );
  }

  const { data: invitation, error: invitationError } = await serviceClient
    .from("user_invites")
    .select("id, status, expires_at")
    .eq("email", email)
    .in("status", ["Pending", "Accepted"])
    .order("invited_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (invitationError) {
    logFailure(requestId, "accept_invitation_lookup", invitationError);
    throw new HttpError(500, "Could not verify the invitation record.");
  }
  if (!invitation) {
    throw new HttpError(
      403,
      "No matching invitation was found for this account.",
    );
  }
  if (invitation.status === "Accepted") {
    return jsonResponse(200, {
      invitation_id: invitation.id,
      status: "Accepted",
      already_accepted: true,
      request_id: requestId,
    });
  }

  if (new Date(invitation.expires_at).getTime() <= Date.now()) {
    const { error: expireError } = await serviceClient
      .from("user_invites")
      .update({ status: "Expired" })
      .eq("id", invitation.id)
      .eq("status", "Pending");
    if (expireError) {
      logFailure(requestId, "mark_expired", expireError);
      throw new HttpError(
        500,
        "The expired invitation status could not be recorded.",
      );
    }
    throw new HttpError(
      410,
      "This invitation has expired. Ask an Administrator for a new invitation.",
    );
  }

  const { data: acceptedInvitation, error: acceptanceError } =
    await serviceClient
      .from("user_invites")
      .update({ status: "Accepted" })
      .eq("id", invitation.id)
      .eq("status", "Pending")
      .gt("expires_at", new Date().toISOString())
      .select("id, status")
      .maybeSingle();
  if (acceptanceError) {
    logFailure(requestId, "accept_invitation_update", acceptanceError);
    throw new HttpError(500, "Invitation acceptance could not be recorded.");
  }
  if (!acceptedInvitation) {
    throw new HttpError(
      409,
      "The invitation is no longer pending or has expired.",
    );
  }

  return jsonResponse(200, {
    invitation_id: acceptedInvitation.id,
    status: acceptedInvitation.status,
    request_id: requestId,
  });
}

async function handleRequest(request: Request): Promise<Response> {
  const requestId = crypto.randomUUID();
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  if (request.method !== "POST") {
    return jsonResponse(405, {
      error: "Method not allowed.",
      request_id: requestId,
    });
  }
  if (
    !request.headers.get("content-type")?.toLowerCase().includes(
      "application/json",
    )
  ) {
    return jsonResponse(415, {
      error: "Content-Type must be application/json.",
      request_id: requestId,
    });
  }

  try {
    const contentLength = Number(request.headers.get("content-length") ?? "0");
    if (Number.isFinite(contentLength) && contentLength > MAX_BODY_BYTES) {
      throw new HttpError(413, "Request body is too large.");
    }

    const authorization = request.headers.get("authorization") ?? "";
    const token = getBearerToken(request);
    const supabaseUrl = requiredEnv("SUPABASE_URL");
    const anonKey = requiredEnv("SUPABASE_ANON_KEY");
    const userClient = createClient(supabaseUrl, anonKey, {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUrl: false,
      },
      global: { headers: { Authorization: authorization } },
    });

    const { data: userData, error: userError } = await userClient.auth.getUser(
      token,
    );
    if (userError || !userData.user) {
      throw new HttpError(401, "The signed-in session is invalid or expired.");
    }

    const { data: callerProfile, error: callerProfileError } = await userClient
      .from("profiles")
      .select("role")
      .eq("id", userData.user.id)
      .maybeSingle();
    if (callerProfileError) {
      logFailure(requestId, "caller_profile_lookup", callerProfileError);
      throw new HttpError(500, "Could not verify the signed-in user role.");
    }

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
    const body = getObject(parsedBody);

    if (body.action === "invite" && callerProfile?.role !== "Administrator") {
      throw new HttpError(
        403,
        "Only Administrators can send staff invitations.",
      );
    }
    if (body.action !== "invite" && body.action !== "accept") {
      throw new HttpError(400, "Action must be invite or accept.");
    }

    const serviceClient = createServiceClient(
      supabaseUrl,
      requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
    );

    if (body.action === "invite") {
      return await createInvitation(
        requestId,
        body,
        userData.user.id,
        serviceClient,
        getRedirectUrl(),
      );
    }

    if (body.action === "accept") {
      return await acceptInvitation(
        requestId,
        body,
        userData.user,
        serviceClient,
      );
    }
    throw new HttpError(400, "Action must be invite or accept.");
  } catch (error) {
    if (error instanceof HttpError) {
      return jsonResponse(error.status, {
        error: error.message,
        request_id: requestId,
      });
    }
    logFailure(requestId, "unhandled_request", error);
    return jsonResponse(500, {
      error: "The invitation request could not be completed.",
      request_id: requestId,
    });
  }
}

Deno.serve(handleRequest);

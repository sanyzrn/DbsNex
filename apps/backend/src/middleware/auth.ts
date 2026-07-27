import { createHash, timingSafeEqual } from "node:crypto";
import type { NextFunction, Request, Response } from "express";

import { getPool } from "../db/index.ts";
import { Forbidden, Unauthorized } from "../http/errors.ts";

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Express {
    interface Request {
      auth?: AuthContext;
    }
  }
}

export interface AuthContext {
  deviceId: string;
  userId: string;
}

/** SHA-256 hex. Tokens are high-entropy, so a plain digest is sufficient. */
export function hashToken(token: string): string {
  return createHash("sha256").update(token, "utf8").digest("hex");
}

/** Constant-time comparison of two hex digests of equal length. */
export function safeEqualHex(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  return timingSafeEqual(Buffer.from(a, "hex"), Buffer.from(b, "hex"));
}

function bearerFrom(req: Request): string | null {
  const header = req.get("authorization");
  if (!header) return null;
  const match = /^Bearer\s+(.+)$/i.exec(header.trim());
  return match?.[1]?.trim() || null;
}

/**
 * Authenticates a device bearer token and attaches { deviceId, userId }.
 *
 * Every data route sits behind this. Before, `device_id` was a self-asserted
 * string in the request body and the schema had no owner column at all, so any
 * caller could read or overwrite any note.
 */
export async function requireDevice(
  req: Request,
  _res: Response,
  next: NextFunction,
): Promise<void> {
  const token = bearerFrom(req);
  if (!token) throw new Unauthorized("missing bearer token");

  const { rows } = await getPool().query<{
    device_id: string;
    user_id: string;
  }>(
    `SELECT device_id, user_id
       FROM devices
      WHERE token_hash = $1
        AND revoked_at IS NULL`,
    [hashToken(token)],
  );

  const row = rows[0];
  if (!row) throw new Unauthorized("invalid or revoked token");

  req.auth = { deviceId: row.device_id, userId: row.user_id };

  // Best-effort liveness bookkeeping; never blocks the request.
  void getPool()
    .query("UPDATE devices SET last_seen_at = NOW() WHERE device_id = $1", [
      row.device_id,
    ])
    .catch(() => undefined);

  next();
}

/** Narrowing helper — throws rather than returning undefined. */
export function auth(req: Request): AuthContext {
  if (!req.auth) throw new Unauthorized();
  return req.auth;
}

/**
 * Rejects a payload whose declared device_id does not match the authenticated
 * device. A device may only speak for itself.
 */
export function assertOwnDevice(req: Request, claimed: string): void {
  if (claimed !== auth(req).deviceId) {
    throw new Forbidden("device_id does not match the authenticated device");
  }
}

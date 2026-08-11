import { randomBytes, randomUUID } from "node:crypto";
import type { Request, Response, Router } from "express";
import { Router as createRouter } from "express";
import { z } from "zod";

import { getPool, withTransaction } from "../db/index.ts";
import { env } from "../env.ts";
import { BadRequest, Unauthorized } from "../http/errors.ts";
import { auth, hashToken, requireDevice } from "../middleware/auth.ts";

export const authRouter: Router = createRouter();

/** 256 bits, base64url — opaque, no PII, revocable, clock-independent. */
function mintSecret(): string {
  return randomBytes(32).toString("base64url");
}

const pairSchema = z.object({
  code: z.string().min(8).max(128),
  label: z.string().max(120).optional(),
});

/**
 * Mint a pairing code from an already-paired device.
 *
 * Bootstrapping the very first device for a user is an operator action: insert
 * a row into pairing_codes directly, or run the seed script. This deliberately
 * does not implement signup — see the decision note on tenancy.
 */
authRouter.post(
  "/pairing-code",
  requireDevice,
  async (req: Request, res: Response) => {
    const { userId } = auth(req);
    const code = mintSecret();
    const expiresAt = new Date(
      Date.now() + env.PAIRING_CODE_TTL_SECONDS * 1000,
    ).toISOString();

    await getPool().query(
      `INSERT INTO pairing_codes (code_hash, user_id, expires_at)
       VALUES ($1, $2, $3)`,
      [hashToken(code), userId, expiresAt],
    );

    // Shown exactly once.
    res.status(201).json({ code, expires_at: expiresAt });
  },
);

/** Redeem a pairing code for a device bearer token. */
authRouter.post("/pair", async (req: Request, res: Response) => {
  const parsed = pairSchema.safeParse(req.body);
  if (!parsed.success) {
    throw new BadRequest("invalid pairing payload", parsed.error.flatten().fieldErrors);
  }

  const result = await withTransaction(async (client) => {
    const { rows } = await client.query<{ user_id: string }>(
      `UPDATE pairing_codes
          SET consumed_at = NOW()
        WHERE code_hash = $1
          AND consumed_at IS NULL
          AND expires_at > NOW()
        RETURNING user_id`,
      [hashToken(parsed.data.code)],
    );

    const row = rows[0];
    if (!row) throw new Unauthorized("pairing code is invalid, used, or expired");

    const deviceId = randomUUID();
    const token = mintSecret();
    const expiresAt = new Date(
      Date.now() + env.DEVICE_TOKEN_TTL_DAYS * 86_400_000,
    ).toISOString();

    await client.query(
      `INSERT INTO devices (device_id, user_id, label, token_hash, expires_at)
       VALUES ($1, $2, $3, $4, $5)`,
      [
        deviceId,
        row.user_id,
        parsed.data.label ?? null,
        hashToken(token),
        expiresAt,
      ],
    );

    await client.query(
      `INSERT INTO device_acks (device_id, user_id, last_pull_at, last_pull_seq)
       VALUES ($1, $2, NOW(), 0)
       ON CONFLICT (device_id) DO NOTHING`,
      [deviceId, row.user_id],
    );

    return { deviceId, token };
  });

  res.status(201).json({
    device_id: result.deviceId,
    token: result.token,
    token_type: "Bearer",
  });
});

/** Revoke this device. Idempotent. */
authRouter.post("/revoke", requireDevice, async (req: Request, res: Response) => {
  const { deviceId } = auth(req);
  await getPool().query(
    "UPDATE devices SET revoked_at = NOW() WHERE device_id = $1 AND revoked_at IS NULL",
    [deviceId],
  );
  res.json({ status: "ok" });
});

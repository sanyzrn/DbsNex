import { randomUUID } from "node:crypto";
import type { NextFunction, Request, Response } from "express";

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Express {
    interface Request {
      id: string;
    }
  }
}

/**
 * Assigns a correlation id to every request. The id is echoed in the response
 * header and in every structured log line, so a 500 can be traced without
 * leaking the underlying error message to the caller.
 */
export function requestId(req: Request, res: Response, next: NextFunction): void {
  const incoming = req.get("x-request-id");
  req.id = incoming && incoming.length <= 64 ? incoming : randomUUID();
  res.setHeader("x-request-id", req.id);
  next();
}

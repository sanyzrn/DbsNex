/**
 * Typed error hierarchy. Handlers throw these; the terminal error middleware in
 * src/index.ts maps them to a status code and a safe JSON body.
 *
 * Raw `e.message` is never returned to a client — `pg` messages contain SQL
 * fragments, constraint names and column names.
 */
export class AppError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
    readonly context?: Record<string, unknown>,
  ) {
    super(message);
    this.name = code;
  }
}

export class BadRequest extends AppError {
  constructor(message: string, context?: Record<string, unknown>) {
    super(400, "BadRequest", message, context);
  }
}

export class Unauthorized extends AppError {
  constructor(message = "authentication required") {
    super(401, "Unauthorized", message);
  }
}

export class Forbidden extends AppError {
  constructor(message = "not permitted") {
    super(403, "Forbidden", message);
  }
}

export class NotFound extends AppError {
  constructor(message = "not found") {
    super(404, "NotFound", message);
  }
}

export class Conflict extends AppError {
  constructor(message: string, context?: Record<string, unknown>) {
    super(409, "Conflict", message, context);
  }
}

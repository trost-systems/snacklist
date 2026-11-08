// The API's error answers (docs/API.md "Errors"): `{ error: { code, message, details? } }`.

export type ErrorCode =
  | 'invalid_json'
  | 'validation_failed'
  | 'invalid_cursor'
  | 'invalid_id'
  | 'invalid_idempotency_key'
  | 'missing_token'
  | 'invalid_token'
  | 'premium_required'
  | 'insufficient_scope'
  | 'not_found'
  | 'item_not_found'
  | 'method_not_allowed'
  | 'conflict'
  | 'payload_too_large'
  | 'unsupported_media_type'
  | 'store_not_found'
  | 'category_not_found'
  | 'ambiguous_store'
  | 'ambiguous_category'
  | 'list_not_found'
  | 'ambiguous_list'
  | 'idempotency_key_reused'
  | 'rate_limited'
  | 'auth_throttled'
  | 'internal_error'
  | 'unavailable';

/** A request the API answers with an error; thrown anywhere, answered by the handler. */
export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: ErrorCode,
    message: string,
    readonly details?: Record<string, unknown>,
    readonly headers: Record<string, string> = {},
  ) {
    super(message);
  }

  get body(): { error: { code: ErrorCode; message: string; details?: Record<string, unknown> } } {
    return {
      error: {
        code: this.code,
        message: this.message,
        ...(this.details ? { details: this.details } : {}),
      },
    };
  }
}

export const noSuchEndpoint = (): ApiError => new ApiError(404, 'not_found', 'No such endpoint.');

export const unavailable = (): ApiError =>
  new ApiError(
    503,
    'unavailable',
    'The service is not answering right now. Retry later.',
    undefined,
    { 'retry-after': '5' },
  );

export const internalError = (): ApiError =>
  new ApiError(500, 'internal_error', 'Something went wrong on our side. Retry later.');

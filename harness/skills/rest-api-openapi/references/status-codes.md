# Status-code matrix

## Contents

- Matrix
- Semantics
- Idempotency outcomes (POST), stored outcomes
- System and Admin
- Adding an error example

## Matrix

Every cell marked `x` is a required `responses:` entry. `o` is opt-in (see note). Use the shared `$ref` shown in the last column.
The POST and PUT/PATCH rows are enforced by `rule/post-declares-create-outcomes` and `rule/put-patch-declare-precondition-outcomes` in the ruleset.
`400` is on every operation: each one takes a path, query, or header input that can be malformed.

| Code | POST /r | GET /r | HEAD /r | OPTIONS | GET /r/{id} | PUT /r/{id} | PATCH /r/{id} | DELETE /r/{id} | HEAD /r/{id} | `$ref` |
|---|---|---|---|---|---|---|---|---|---|---|
| 200 | | x | x | | x | x | x | | x | `schemas/<r>/responses/<r>-list.yaml`, `<r>-head.yaml`, `<r>-retrieved.yaml`, `<r>-updated.yaml` |
| 201 | x | | | | | | | | | `schemas/<r>/responses/<r>-created.yaml` |
| 204 | | | | x | | | | x | | `<r>s-options.yaml`, `<r>-options.yaml`, `<r>-deleted.yaml` |
| 304 | | x | x | | x | | | | x | `schemas/<r>/responses/not-modified.yaml` |
| 400 | x | x | x | x | x | x | x | x | x | `schemas/common/responses/errors/bad-request.yaml` |
| 401 | x | x | x | | x | x | x | x | x | `.../errors/unauthorized.yaml` |
| 403 | o | o | o | | o | o | o | o | o | `.../errors/forbidden.yaml`; declared when access depends on more than a valid token: scope, role, or ownership |
| 404 | | | | | x | x | x | x | x | `.../errors/not-found.yaml` |
| 406 | x | x | | | x | x | x | | | `.../errors/not-acceptable.yaml` |
| 409 | x | | | | | x | x | x | | `.../errors/conflict.yaml` |
| 412 | | | | | | x | x | x | | `.../errors/precondition-failed.yaml` |
| 413 | x | | | | | x | x | | | `.../errors/content-too-large.yaml` |
| 415 | x | | | | | x | x | | | `.../errors/unsupported-media-type.yaml` |
| 422 | x | | | | | x | x | | | `.../errors/unprocessable-entity.yaml` |
| 428 | | | | | | o | o | | | `.../errors/precondition-required.yaml`; required when `IfMatchHeader` is `required: true` for the resource |
| 429 | x | x | x | | x | x | x | x | x | `.../errors/rate-limit.yaml` |
| 500 | x | x | x | | x | x | x | x | x | `.../errors/server-error.yaml` |
| 503 | x | x | x | | x | x | x | x | x | `.../errors/service-unavailable.yaml` |

Not in the matrix on purpose:
- `405` applies to methods the path does not define, which OpenAPI cannot list. It is documented once in `info.description` with its mandatory `Allow` header; the server emits it. Same for `414` and `431`.

Response keys are quoted strings in YAML: `"201":`, not `201:`.

## Semantics

Error bodies are `Problem` documents (`application/problem+json`). `type` is `<problem_type_base><slug>` (base from the profile);
violation codes come from the closed vocabulary in [errors.md](errors.md).

| Code | Use when | Body / headers |
|---|---|---|
| 200 | Read or update succeeded | envelope `{data, meta[, pagination]}`; PUT/PATCH add `Content-Location` |
| 201 | Create succeeded; `Location` set | envelope `{data, meta}`; `Idempotent-Replayed: true` when replayed |
| 204 | Delete or OPTIONS succeeded | none |
| 304 | `If-None-Match` matched current ETag (weak comparison) | none; carries `ETag`, `Cache-Control`, `Cache-Status`, `RateLimit-*`, `Vary`; no `Last-Modified` |
| 400 | Malformed JSON, non-UUID path id, unparseable query, missing or malformed `Idempotency-Key`, undecodable `cursor`, unknown `fields` name, `API-Version` that differs from the URL version, unparseable `Signature-Input` or `Signature` (`signature-malformed`) | `bad-request`; violations such as `""` `invalid_format`, `/path/widgetId` `invalid_format`, `/headers/Idempotency-Key` `required`, `/query/cursor` `invalid_cursor`, `/query/fields` `unknown_field`, `/headers/API-Version` `invalid_enum_value` |
| 401 | Missing or invalid PASETO or Basic credentials; failed request signature | `unauthorized` or a `signature-*` / `content-digest-mismatch` slug; `WWW-Authenticate` always, as the bare challenge when no credentials were sent |
| 403 | Valid credentials that may not perform this operation on this resource (scope, role, ownership). A resource whose existence must stay hidden answers `404` instead | `forbidden`; no violations; `WWW-Authenticate: Bearer realm="<auth_realm>", error="insufficient_scope"` when a scope is missing (RFC 6750 §3.1) |
| 404 | Resource id does not exist | `not-found` |
| 405 | Method not defined on the path | `method-not-allowed`; `Allow` always |
| 406 | `Accept` not satisfiable; `Accept-Encoding` not satisfiable and `identity` refused too (otherwise the response goes out unencoded, RFC 9110 §12.5.3) | `not-acceptable`; violation on `/headers/Accept` or `/headers/Accept-Encoding` |
| 409 | Business-rule violation against current state (delete or rename an in-use widget) | `conflict`; violations `/status` or `/name` `immutable` |
| 409 | `POST` replay while the original request with the same `Idempotency-Key` is in flight | `request-in-progress`; violation `/headers/Idempotency-Key` `in_progress`; `Retry-After` |
| 412 | `If-Match` present and does not match the current strong ETag (PUT, PATCH, DELETE) | `precondition-failed`; violation `/headers/If-Match` `etag_mismatch`; response carries the current `ETag` |
| 413 | Request body exceeds the configured size limit | `content-too-large`; violation `""` `too_big` |
| 415 | Request `Content-Type` not declared for the operation (e.g. `application/json` on PATCH, `text/plain` on POST) | `unsupported-media-type`; violation `/headers/Content-Type` `invalid_enum_value`; PATCH adds `Accept-Patch` |
| 422 | Parsed body that fails schema or domain validation (required field, length, enum, `null` on a required merge-patch field, unknown property) | `validation-error`; violations `required`, `too_small`, `too_big`, `invalid_enum_value`, `invalid_type`, `unknown_field` |
| 422 | `Idempotency-Key` reused with a different fingerprint | `idempotency-key-reused`; violation `/headers/Idempotency-Key` `payload_mismatch` |
| 428 | Resource requires `If-Match` and the request omitted it | `precondition-required`; violation `/headers/If-Match` `required` |
| 429 | Rate limit exceeded | `rate-limit-exceeded`; `Retry-After`, `RateLimit-*` |
| 500 | Unexpected failure: a defect, never a dependency outage | `internal-error`; generic `detail`, never internals |
| 503 | Dependency down, overload, or maintenance; signing keys unavailable or policy in reject-all mode; a probe that reports down | `service-unavailable` / `signature-service-unavailable`, or the probe entity (`Liveness`/`Readiness`/`Health`) with `status: down`; `Retry-After` always. Clients retry `503`, not `500` |

## Idempotency outcomes (POST)

Status codes and field typing follow draft-ietf-httpapi-idempotency-key-header (quoted Structured Field String canonical, bare UUID accepted).

| Situation | Status | `type` slug and violation | Example key |
|---|---|---|---|
| Header missing | 400 | `bad-request`; `/headers/Idempotency-Key` `required` | `bad-request.yaml#/idempotency_key_missing` |
| Header not a UUID | 400 | `bad-request`; `/headers/Idempotency-Key` `invalid_format` | `bad-request.yaml#/idempotency_key_invalid` |
| Same key, same fingerprint, original succeeded | 201 | stored body + headers, plus `Idempotent-Replayed: true` | `widget.yaml#/widget_created` |
| Same key, original failed with `4xx` or `5xx` | as a first request | nothing was stored; the request is evaluated again | |
| Same key, same fingerprint, original in flight | 409 | `request-in-progress`; `/headers/Idempotency-Key` `in_progress`; `Retry-After` | `conflict.yaml#/idempotency_key_in_progress` |
| Same key, different fingerprint | 422 | `idempotency-key-reused`; `/headers/Idempotency-Key` `payload_mismatch` | `unprocessable-entity.yaml#/idempotency_key_reused` |

Fingerprint = method + path + body. Scope = authenticated client + path. Retention 24h.

### Stored outcomes

- Only a `2xx` outcome is stored and replayed. For a create that is the `201`, with its headers and body.
- A `4xx` is never stored, whether the handler produced it (`409` business conflict, `422` validation) or a check before it did (`400`, `401`, `429`, the in-flight `409`): it created nothing. A retry with the same key is evaluated again, so an input error repeats and a business conflict clears once the state allows the create.
- A `5xx` is never stored. The key record commits in the same transaction as the resource, so a retry with the same key either runs the create again (nothing was committed) or replays the stored `201` (the failure came after the commit).
- A key whose request failed stays free: the client may correct the body and reuse it. `422` `idempotency-key-reused` applies only against a stored or in-flight request.
- This narrows draft-ietf-httpapi-idempotency-key-header on purpose. The draft says a retry SHOULD get the previous result, "success or an error"; here a key guards the side effect, and only a success has one.

## System and Admin

| Path | Codes | Security |
|---|---|---|
| `GET /liveness`, `GET /readiness` | 200, 429, 503 (entity body + `Retry-After`) | `[]` |
| `GET /health` | 200, 401, 503 | `BasicAuth` |
| `GET /admin/...` | 200, 401, 503 | `BasicAuth` |
| `DELETE /admin/...` | 200, 400 (when it has params), 401, 500, 503 | `BasicAuth` |

Admin success bodies use `schemas/admin/responses/*.yaml`; admin errors reference the shared problem files
(`bad-request.yaml`, `unauthorized.yaml`, `server-error.yaml`, `service-unavailable.yaml`). Every admin operation with `BasicAuth` declares `401`.

## Adding an error example

Add a new key under `examples:` in the shared error file. Include every required member of `Problem`:
`requestId`, `timestamp`, `type`, `title`, `status`, `detail`; add `traceId` and, when an input is at fault, `violations`.
Keys are snake_case and unique API-wide. Reuse the canonical fixture values
`requestId: "019234a5-6b7c-7d9e-8f12-34567890abcd"`, `traceId: "0af7651916cd43dd8448eb211c80319c"`,
`timestamp: "2024-01-15T10:30:00Z"`.

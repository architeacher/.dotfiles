# Errors: RFC 9457 Problem Details

Every 4xx and 5xx body is `application/problem+json` with the `Problem` schema below, admin and system
endpoints included. One schema for every operation. Clients switch on `type`.

Files: `schemas/common/responses/errors/entities/problem.yaml` (schema) and one shared response file per
status in `schemas/common/responses/errors/`. The rule `operation-4xx-problem-details-rfc7807` in
the ruleset rejects any 4xx response that is not `application/problem+json`.
`<problem_type_base>` and `<auth_realm>` come from the profile; the examples use `https://docs.example.com/problems/`.

## Contents

- Canonical example
- `Problem` schema
- `field` pointer convention
- Violation code vocabulary (closed set)
- Problem type catalogue
- Rules

## Canonical example

```http
HTTP/1.1 422 Unprocessable Content
Content-Type: application/problem+json
Cache-Control: no-store

{
  "requestId": "019234a5-6b7c-7d9e-8f12-34567890abcd",
  "traceId": "0af7651916cd43dd8448eb211c80319c",
  "timestamp": "2024-01-15T10:30:00Z",
  "type": "https://docs.example.com/problems/validation-error",
  "title": "Validation Error",
  "status": 422,
  "detail": "Request failed validation.",
  "violations": [
    {
      "field": "/name",
      "code": "too_small",
      "message": "String must contain at least 1 character(s)"
    }
  ]
}
```

## `Problem` schema (`schemas/common/responses/errors/entities/problem.yaml`)

| Member | Type | Required | Rule |
|---|---|---|---|
| `requestId` | uuid | yes | equals the `Request-Id` header |
| `traceId` | string | no | W3C trace id when tracing is on |
| `timestamp` | date-time | yes | when the problem occurred |
| `type` | uri | yes | `<problem_type_base>{slug}`, constant per type, resolves to docs |
| `title` | string | yes | constant per type |
| `status` | integer 400..599 | yes | equals the HTTP status |
| `detail` | string | yes | one occurrence-specific sentence, ends with a period, no internals |
| `violations[]` | `Violation` | no | present only when a specific input is at fault; never an empty array |

`Violation`: `field` (JSON Pointer, pattern `^(/.*)?$`), `code` (pattern `^[a-z][a-z0-9_]*$`), `message`. All three required.

Response file shape:

```yaml
description: <Status reason> - <when> (RFC 9457 problem)
headers:
  API-Version: ...        # TRACE set
  Request-Id: ...
  Correlation-Id: ...
  Cache-Control:
    $ref: "../headers/headers.yaml#/CacheControlNoStoreHeader"
  # status-specific: WWW-Authenticate (401, 403), Retry-After (409, 429, 503), ETag (412), Accept-Patch (415), RateLimit-* (429)
  traceparent: ...
  tracestate: ...
content:
  application/problem+json:
    schema:
      $ref: "entities/problem.yaml#/Problem"
    examples:
      <snake_case_case_name>: ...
```

## `field` pointer convention

- RFC 6901 JSON Pointer. Escape `~` as `~0` and `/` as `~1`.
- `""` (empty) is the whole request body: unparseable JSON, body not an object, body too large.
- The request body is the root: `/name`, `/state`, `/items/0/sku`.
- Non-body inputs use reserved roots: `/headers/<Header-Name>` (canonical casing), `/query/<param>`, `/path/<param>`.
- Consequence: body top-level properties must never be named `headers`, `query`, or `path`.

## Violation code vocabulary (closed set)

| `code` | Meaning | Typical `field` |
|---|---|---|
| `required` | Required input missing | `/name`, `/headers/Idempotency-Key`, `/headers/If-Match` (428), `/query/pattern` |
| `invalid_type` | Wrong JSON type, including `null` on a non-nullable field in a merge patch | `/state`, `/name` |
| `invalid_format` | Fails `format` or `pattern` (uuid, date-time, unparseable JSON body, unbalanced quotes on a Structured Field String) | `/path/widgetId`, `/headers/Idempotency-Key`, `""` |
| `invalid_enum_value` | Not one of the allowed values, including unsupported media types and encodings | `/state`, `/query/sort`, `/headers/Accept`, `/headers/Content-Type`, `/headers/API-Version` |
| `too_small` | Below `minLength`, `minimum`, `minItems`, or `minProperties` | `/name`, `/query/page` |
| `too_big` | Above `maxLength`, `maximum`, `maxItems`, or the body size limit | `/brand`, `/query/size`, `""` (413) |
| `unknown_field` | Property or projection name not in the schema | `/foo`, `/query/fields` |
| `immutable` | Field cannot change in the resource's current state | `/name`, `/state` (409) |
| `etag_mismatch` | `If-Match` does not match the current strong ETag | `/headers/If-Match` (412) |
| `in_progress` | A request with this idempotency key is still executing | `/headers/Idempotency-Key` (409) |
| `payload_mismatch` | Idempotency key reused with a different request fingerprint | `/headers/Idempotency-Key` (422) |
| `invalid_cursor` | Cursor cannot be decoded or no longer matches the query | `/query/cursor` (400) |

Every code has at least one example in a shared error file. This table is the baseline for every project. A code only one project needs is a contract change there: record it under `additions.violation_codes` in the profile and add the example.

## Problem type catalogue

`type` = `<problem_type_base><slug>`. Every slug needs a documentation page at that URL. The rows below are the baseline; a project-specific slug goes under `additions.problem_types` in the profile.

| Status | Slug | `title` | When | Extra headers | File |
|---|---|---|---|---|---|
| 400 | `bad-request` | Bad Request | Malformed JSON, bad path or query value, missing or malformed header. Violations name the input. | | `bad-request.yaml` |
| 401 | `unauthorized` | Unauthorized | Missing or invalid PASETO or Basic credentials | `WWW-Authenticate` | `unauthorized.yaml` |
| 400 | `signature-malformed` | Signature Malformed | `Signature-Input` or `Signature` cannot be parsed as RFC 9421 Dictionary fields | | `bad-request.yaml` |
| 401 | `signature-required`, `signature-invalid`, `signature-expired`, `signature-future-created`, `signature-unknown-key`, `signature-missing-components`, `signature-replay`, `signature-key-mismatch`, `content-digest-mismatch` | per slug ("Signature Required", …) | Request signature failed verification (RFC 9421; profile in headers.md). Examples exist for required, invalid, expired, and content-digest-mismatch; add one when another slug is first emitted. | `WWW-Authenticate` | `unauthorized.yaml` |
| 403 | `forbidden` | Forbidden | Valid credentials that may not perform the operation (scope, role, ownership). No violations. Opt-in per operation. | `WWW-Authenticate` with `error="insufficient_scope"` when a scope is missing | `forbidden.yaml` |
| 404 | `not-found` | Not Found | Resource id does not exist, or its existence must stay hidden from the caller | | `not-found.yaml` |
| 405 | `method-not-allowed` | Method Not Allowed | Method not defined on the path (documented in `info.description`) | `Allow` | none (not per operation) |
| 406 | `not-acceptable` | Not Acceptable | `Accept` or `Accept-Encoding` cannot be satisfied | | `not-acceptable.yaml` |
| 409 | `conflict` | Conflict | Business rule against current state. Violations use `immutable`. | | `conflict.yaml` |
| 409 | `request-in-progress` | Request In Progress | Idempotent duplicate still executing. Violation `in_progress`. | `Retry-After` | `conflict.yaml` |
| 412 | `precondition-failed` | Precondition Failed | `If-Match` mismatch. Violation `etag_mismatch`. | `ETag` | `precondition-failed.yaml` |
| 413 | `content-too-large` | Content Too Large | Body over the configured limit. Violation `""` `too_big`. | | `content-too-large.yaml` |
| 415 | `unsupported-media-type` | Unsupported Media Type | Request `Content-Type` not declared for the operation | `Accept-Patch` on PATCH | `unsupported-media-type.yaml` |
| 422 | `validation-error` | Validation Error | Parsed body that fails schema or domain validation. Violations required. | | `unprocessable-entity.yaml` |
| 422 | `idempotency-key-reused` | Idempotency Key Reused | Same key, different fingerprint. Violation `payload_mismatch`. | | `unprocessable-entity.yaml` |
| 428 | `precondition-required` | Precondition Required | Resource requires `If-Match` and it is absent. Violation `required`. Opt-in per resource. | | `precondition-required.yaml` |
| 429 | `rate-limit-exceeded` | Too Many Requests | Rate limit exceeded | `Retry-After`, `RateLimit-*` | `rate-limit.yaml` |
| 500 | `internal-error` | Internal Server Error | Unexpected failure: a defect, never a dependency outage. Generic `detail`. | | `server-error.yaml` |
| 503 | `service-unavailable`, `signature-service-unavailable` | Service Unavailable, Signature Service Unavailable | Dependency down, overload, or maintenance; signing keys unavailable or policy in reject-all mode. Declared on every operation. | `Retry-After` | `service-unavailable.yaml` |

400 versus 422: the request is 400 when the server could not interpret an input (syntax, header shape,
query or path parse, including a non-UUID `widgetId`). It is 422 when every input parsed and the body still
breaks a schema or business rule.

## Rules

- Clients switch on `type`. `title` and `detail` are for humans and may change wording without a version bump.
- `detail` is one sentence, specific to the occurrence, ending with a period. 5xx `detail` is generic: no stack traces, SQL, hostnames, or upstream error strings.
- `violations[]` is present whenever a specific input is at fault, and absent otherwise.
- `Cache-Control: no-store` on every problem response.
- 401 carries `WWW-Authenticate`. No credentials sent: the bare challenge `Bearer realm="<auth_realm>"`, without `error` (RFC 6750 §3). Credentials rejected: `Bearer realm="<auth_realm>", error="invalid_token", error_description="…"`. Admin uses `Basic realm="<auth_realm>"`. The challenge names the authentication scheme in use, also for signature failures; RFC 9421 defines no scheme of its own.
- Problem bodies are never wrapped in the `data` / `meta` envelope.
- Example keys in shared files are snake_case, name the case, and are unique API-wide: `idempotency_key_missing`, `widget_in_use_delete`.
- Fixture values: `requestId: "019234a5-6b7c-7d9e-8f12-34567890abcd"`, `traceId: "0af7651916cd43dd8448eb211c80319c"`, `timestamp: "2024-01-15T10:30:00Z"`.

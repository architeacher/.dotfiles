# Header sets

All names are RFC 6648 compliant (no `X-` prefix): `Request-Id`, `Correlation-Id`, `RateLimit-*`, not `X-Request-Id`.
Pre-existing standardized `X-` headers (`X-Content-Type-Options`, `X-Frame-Options`) keep their names; RFC 6648 covers
new names only and takes no position on existing ones (§1). OpenAPI `x-` extensions (`x-internal`, `x-enumDescriptions`)
are a different namespace that the OpenAPI specification itself requires.
Casing follows the spec exactly: `API-Version`, `Request-Id`, `Correlation-Id`, `traceparent`, `tracestate` (lowercase per W3C).
Every header below exists in the spec. Adding one follows "Adding a new header" at the end.
`<auth_realm>` and `<cache_name>` come from the profile.

## Contents

- Request headers
- Response headers
- Required header set per response type
- ETag rules
- Signature profile (RFC 9421 §1.4)
- Deprecation
- Security headers
- Adding a new header

## Request headers (defined in `specs.yaml` `components/parameters`)

| Parameter key | Header | Required | Where |
|---|---|---|---|
| `ApiVersionHeader` | `API-Version` | no (enum `[v1]`, default `v1`); an assertion, not a selector: when sent it must equal the URL version, else `400` | path-level, every resource path |
| `RequestIdHeader` | `Request-Id` | no (uuid) | path-level |
| `CorrelationIdHeader` | `Correlation-Id` | no (uuid), echoed or generated | path-level |
| `TraceparentHeader` | `traceparent` | no, regex `^00-[a-f0-9]{32}-[a-f0-9]{16}-[0-9a-f]{2}$` | path-level |
| `TracestateHeader` | `tracestate` | no | path-level |
| `SignatureInputHeader` | `Signature-Input` | no; the signing policy makes it mandatory per path (RFC 9421) | path-level |
| `SignatureHeader` | `Signature` | same as above | path-level |
| `AcceptSignatureHeader` | `Accept-Signature` | no; asks for a signed response (RFC 9421 §5.1) | path-level |
| `WantContentDigestHeader` | `Want-Content-Digest` | no; asks for a response digest (RFC 9530) | path-level |
| `IdempotencyKeyHeader` | `Idempotency-Key` | **yes**; uuid v7 as a quoted Structured Field String (canonical) or bare | POST only |
| `ContentDigestHeader` | `Content-Digest` | no; required when a signed request has a body (`sha-256=:…:`) | POST, PUT, PATCH |
| `IfMatchHeader` | `If-Match` | no by default; `required: true` on resources that declare 428 | PUT, PATCH, DELETE |
| `IfNoneMatchHeader` | `If-None-Match` | no | GET, HEAD |
| `AcceptEncodingHeader` | `Accept-Encoding` | no | GET (list and item) |

`Authorization`, `Accept`, and `Content-Type` are not parameters: OpenAPI 3.0.3 ignores header parameters with those names (`rule/no-ignored-header-parameters`).
- `Authorization`: the operation's `security` plus `securitySchemes`. `PasetoAuth` documents the token format `Bearer v4.(public|local).…` in `bearerFormat` and `description`; `BasicAuth` covers admin. Missing or rejected credentials are `401`.
- `Accept`: implied by the response `content` keys. Default `application/json`; unsatisfiable is `406`.
- `Content-Type`: implied by `requestBody.content`. Wrong value is `415`.

Order inside an operation's `parameters:`: op-specific (`Idempotency-Key` / `If-Match` / `Content-Digest` / query params), then `If-None-Match`, `Accept-Encoding`.

## Response headers (defined in `schemas/common/responses/headers/headers.yaml`)

| Key in `headers.yaml` | Header | Notes |
|---|---|---|
| `ApiVersionHeader` | `API-Version` | enum `[v1]` |
| `RequestIdHeader` | `Request-Id` | always server-generated |
| `CorrelationIdHeader` | `Correlation-Id` | echoed or generated |
| `TraceparentResponseHeader`, `TracestateResponseHeader` | `traceparent`, `tracestate` | |
| `LocationHeader` | `Location` | 201 only, `format: uri-reference`, base path included |
| `ContentLocationHeader` | `Content-Location` | PUT/PATCH 200; equals the request path, base path included; marks the body as the new representation (RFC 9110 §8.7) |
| `IdempotentReplayedHeader` | `Idempotent-Replayed` | 201 only; present on replayed responses, enum `["true"]` |
| `ETagHeader` | `ETag` | strong `"..."` on single resources, weak `W/"..."` allowed on collections |
| `CacheControlHeader` | `Cache-Control` | `private, max-age=…, stale-while-revalidate=…, stale-if-error=…` (RFC 5861) on 2xx |
| `CacheControlNoStoreHeader` | `Cache-Control` | `no-store`, every 4xx/5xx |
| `CacheStatusHeader` | `Cache-Status` | RFC 9211: `<cache_name>; hit`, `<cache_name>; hit; ttl=-15`, `<cache_name>; fwd=miss; stored`, `<cache_name>; fwd=bypass` |
| `LastModifiedHeader` | `Last-Modified` | HTTP-date, plain string, single resource only, never on `304` |
| `TotalCountHeader` | `Total-Count` | HEAD on collections |
| `ContentLengthHeader` | `Content-Length` | HEAD 200: the length the GET body would have |
| `RateLimitLimitHeader`, `RateLimitRemainingHeader` | `RateLimit-Limit`, `RateLimit-Remaining` | integers |
| `RateLimitResetHeader` | `RateLimit-Reset` | delta-seconds until the window resets, never a Unix timestamp |
| `RateLimitPolicyHeader` | `RateLimit-Policy` | `100;w=60` |
| `RetryAfterHeader` | `Retry-After` | 429, 503, and 409 `request-in-progress` |
| `ContentEncodingHeader` | `Content-Encoding` | enum `gzip, deflate, br, zstd`; omitted when unencoded (`identity` is not a content coding) |
| `VaryHeader` | `Vary` | `Accept, Accept-Encoding, Authorization, Origin` |
| `DeprecationHeader` | `Deprecation` | RFC 9745 structured Date `@1767225599`, pattern `^@[0-9]+$` |
| `SunsetHeader` | `Sunset` | RFC 8594 HTTP-date, plain string |
| `LinkHeader` | `Link` | RFC 8288; rels `successor-version` (RFC 5829), `deprecation` (RFC 9745), `sunset` (RFC 8594) |
| `WWWAuthenticateHeader` | `WWW-Authenticate` | every 401; `Bearer realm="<auth_realm>"` alone when no credentials were sent, plus `error="invalid_token", error_description="…"` when they were rejected (RFC 6750 §3); Basic for admin |
| `ContentDigestResponseHeader` | `Content-Digest` | RFC 9530, on signed responses |
| `SignatureInputResponseHeader`, `SignatureResponseHeader` | `Signature-Input`, `Signature` | RFC 9421, on signed responses |
| `AllowHeader` | `Allow` | OPTIONS 204 and 405 (inline per path in the options files because the method list differs) |
| `AcceptPatchHeader` | `Accept-Patch` | `application/merge-patch+json`; item-path OPTIONS and 415 on PATCH (RFC 5789) |
| `AccessControlAllowOriginHeader` | `Access-Control-Allow-Origin` | echoed allowed origin, never `*` with credentials; pair with `Vary: Origin` |
| `AccessControlAllowMethodsHeader` | `Access-Control-Allow-Methods` | inline per path in the options files |
| `AccessControlAllowHeadersHeader` | `Access-Control-Allow-Headers` | header parameters in `components/parameters` plus `Authorization` and `Content-Type`; canonical list is this header's example |
| `AccessControlExposeHeadersHeader` | `Access-Control-Expose-Headers` | every non-safelisted response header a browser must read; canonical list is this header's example |
| `AccessControlMaxAgeHeader` | `Access-Control-Max-Age` | 86400; Chromium caps at 7200 |

Not adopted: `Prefer` / `Preference-Applied` (RFC 7240). Mutations always return the representation.

## Required header set per response type

**TRACE** = `API-Version`, `Request-Id`, `Correlation-Id`, `traceparent`, `tracestate`
**RATE** = `RateLimit-Limit`, `RateLimit-Remaining`, `RateLimit-Reset`, `RateLimit-Policy`
**ENC** = `Content-Encoding`, `Vary`
**CACHE** = `ETag`, `Cache-Control`, `Cache-Status` (+ `Last-Modified` for single resource)
**SIGN** = `Content-Digest`, `Signature-Input`, `Signature` (present only when response signing is enabled for the path)
**CORS** = `Access-Control-Allow-Origin`, `Access-Control-Expose-Headers`, `Vary: Origin` (only when the request carried `Origin`)

RATE belongs to authenticated operations: every `2xx` and `304` declares it, `429` declares it and adds `Retry-After`,
other error responses do not. It is the three-field form of draft-ietf-httpapi-ratelimit-headers-06; later revisions
changed the fields and the `RateLimit-Policy` syntax. Migrate only when the RFC publishes.

| Response | Headers |
|---|---|
| `201 Created` | TRACE + `Location` + `Idempotent-Replayed` + RATE + ENC + SIGN |
| `200 OK` single GET | TRACE + CACHE(+Last-Modified) + RATE + ENC + SIGN |
| `200 OK` list GET | TRACE + CACHE + RATE + ENC + SIGN |
| `200 OK` PUT/PATCH | TRACE + `ETag` + `Content-Location` + RATE + ENC + SIGN |
| `200 OK` HEAD single | TRACE + CACHE(+Last-Modified) + RATE + `Content-Length` |
| `200 OK` HEAD list | TRACE + CACHE + RATE + `Total-Count` + `Content-Length` |
| `204 No Content` DELETE | TRACE + RATE |
| `204 No Content` OPTIONS | `Allow`, `Accept-Patch` (item path), `Access-Control-Allow-Origin`, `Access-Control-Allow-Methods`, `Access-Control-Allow-Headers`, `Access-Control-Expose-Headers`, `Access-Control-Max-Age`, `Vary` (no TRACE) |
| `304 Not Modified` | TRACE + CACHE (never `Last-Modified`) + RATE + `Vary` (RFC 9110 §15.4.5) |
| `4xx` / `5xx` generic | TRACE + `Cache-Control: no-store` |
| `401 Unauthorized` | + `WWW-Authenticate` |
| `403 Forbidden` (opt-in) | + `WWW-Authenticate` with `error="insufficient_scope"`, only when a scope is missing |
| `405 Method Not Allowed` | + `Allow` |
| `409 Conflict` | + `Retry-After` (set only for `request-in-progress`) |
| `412 Precondition Failed` | + `ETag` |
| `415 Unsupported Media Type` | + `Accept-Patch` (PATCH only) |
| `429 Too Many Requests` | + `Retry-After` + RATE |
| `503 Service Unavailable` | + `Retry-After` (also on probe 503s, which keep their entity bodies) |
| Admin success responses | none declared (internal port); admin errors use the shared problem files above |

Every response the browser may read carries the CORS set when the request had `Origin`. Only the OPTIONS files declare it; for every other response it is stated once in `info.description`.

## ETag rules

- Single resource: strong, `"<hash of id + updatedAt>"`. Identifies the resource version, so it stays identical across `Content-Encoding` values and compression must not weaken or suffix it. This is the Express / Spring convention. The strict RFC 9110 §8.8.3 reading (one strong tag per encoding) is intentionally not followed because `If-Match` needs a stable strong tag; the compliant alternative (Apache-style `-gzip` suffix, stripped before `If-Match` comparison) was judged not worth the complexity.
- Collection: weak `W/"<hash of data + pagination>"`. Weak comparison is enough for `If-None-Match` → `304`.
- `meta` is never part of an ETag: it changes with every request. After a `304` the client keeps the `meta` of the response it cached; the current ids travel in the `Request-Id` and `traceparent` headers.
- `If-Match` uses strong comparison (RFC 9110 §13.1.1). Never compare it against a weak tag.
- `If-Match: *` means "resource exists". `If-None-Match: *` on `PUT` means "create only" (this API answers 404 because PUT never creates).
- PUT/PATCH 200 responses carry `Content-Location` equal to the request path, so the body is the new representation (RFC 9110 §8.7) and the `ETag` describes it. For `PUT` this is a deliberate deviation from the letter of RFC 9110 §9.3.4, which allows a validator only when the server stored the request body without transformation; here it adds `updatedAt` and the envelope. It is safe because the response carries the stored representation, so a client never pairs the `ETag` with the body it sent.

## Signature profile (RFC 9421 §1.4)

RFC 9421 leaves these choices to each application and requires them to be fixed. This API's profile:

| Item | Requests (client to API) | Responses (API to client) |
|---|---|---|
| Fields | `Signature-Input`, `Signature`; `Content-Digest` whenever a body is present | `Signature-Input`, `Signature`, `Content-Digest` |
| Covered components, minimum | `@method`, `@target-uri`, `content-digest` (when a body is present), `authorization` (when present) | `@status`, `content-digest`, `content-type`; plus `"@method";req` and `"@target-uri";req` when the request was signed (§2.4 request-response binding) |
| Required parameters | `created`, `expires`, `nonce`, `keyid` | `created`, `keyid` |
| Optional parameters | `alg` (must agree with the key; verifiers never trust it alone, §3.2 step 6.5), `tag` | `alg`, `tag` |
| Algorithms (registry names) | `ecdsa-p256-sha256` (default), `ed25519`, `hmac-sha256` | same |
| Validity | reject `created` in the future beyond the tolerated clock skew, and anything past `expires` | same |
| Replay | `nonce` unique per key within the validity window; reuse is 401 `signature-replay` | n/a |
| Key resolution | `keyid` names a key registered for the client; unknown key is 401 `signature-unknown-key`, algorithm mismatch 401 `signature-key-mismatch` | clients resolve `keyid` against the published API keys (candidate `application/jwk-set+json`, see media-types.md) |
| Digest | RFC 9530 `Content-Digest: sha-256=:…:`; mismatch is 401 `content-digest-mismatch`; `Want-Content-Digest` asks for one on the response | same algorithm family |
| Opt-in response signing | `Accept-Signature: sig1=("@status" "content-digest");keyid="…"` (§5.1) | signature label echoes the requested label |
| Failures | unparseable `Signature-Input` or `Signature` is 400 `signature-malformed`; every other verification failure is 401 with its `signature-*` slug and `WWW-Authenticate` naming the authentication scheme in use (`Bearer`; RFC 9421 defines no scheme of its own); keys unavailable is 503 `signature-service-unavailable` | n/a |

Which paths require a signature is a policy choice; state it in the operation description.

## Deprecation

RFC 9745 and RFC 8594. A deprecated operation sets `deprecated: true` in the spec, and each of its responses carries
`Deprecation: @<unix-seconds>` (structured Date, RFC 9651), `Sunset: <HTTP-date>`, and a `Link` header with
`rel="successor-version"`, `rel="deprecation"`, and `rel="sunset"`. `Deprecation: true` is the expired draft syntax; do
not use it. A version that a new `v<N+1>` replaces is deprecated this way.

## Security headers

Set by the server on every response and documented in `info.description` only, not per-response:
`X-Content-Type-Options: nosniff`, `Content-Security-Policy` with `frame-ancestors 'none'` (the standard successor to
`X-Frame-Options`, which stays only for legacy browsers), `X-Frame-Options: DENY`, `X-XSS-Protection: 0` (never
`1; mode=block`, per OWASP), `Strict-Transport-Security`, `Referrer-Policy`, `Permissions-Policy`.
Do not add them to response files.

## Adding a new header

1. Request header: add to `components/parameters` in `specs.yaml` with `in: header`, `required`, `description`, `schema`, `example`. Path-level if every operation may receive it.
2. Response header: add to `headers.yaml` as `<Name>Header` with `description`, `schema`, `example`. HTTP-dates (`Last-Modified`, `Sunset`) are plain `type: string`, never `format: date-time`; URIs that may be relative (`Location`, `Content-Location`) are `format: uri-reference`.
3. Reference it from every response file that must carry it. Grep for an analogous header to find the full list:

```bash
rg -l "RateLimitLimitHeader" docs/contracts/openapi
```

4. If it varies the cached representation, add it to the `Vary` example.
5. If a browser must send it, add it to the `AccessControlAllowHeadersHeader` example. If a browser must read it, add it to the `AccessControlExposeHeadersHeader` example.
6. If a status must always carry it, add it to `response-contains-header`: in the skill's ruleset when every project needs it, otherwise by repeating the rule with the longer `names` map in the project's `.redocly.yaml`.
7. Record it. A header every project should have gets a row above (a change to the skill); a project-specific one goes under `additions.headers` in the profile.

---
name: rest-api-openapi
description: 'Designs and extends REST API endpoints spec-first with the modular OpenAPI 3.0.3 layout under docs/contracts/openapi. Use when adding a resource, endpoint, query parameter, header, error response, media type, or example to an API kept in that layout, or when reviewing an OpenAPI change for consistency. Covers directory structure, $ref conventions, the project profile, request/response header sets, status-code matrix per HTTP method, RFC 9457 Problem Details errors with violations, idempotency, ETags and preconditions, pagination (page + cursor), filtering, sorting, field projection, deprecation, rate-limit and CORS headers, media types (JSON, merge-patch, problem+json), the redocly ruleset, and the lint/bundle workflow.'
license: MIT
metadata:
  tags: "API Design, OpenAPI, Productivity"
  category: "productivity"
---

# REST API design with OpenAPI (spec-first)

The OpenAPI spec is the contract and the only source of truth. Never derive spec content from
an implementation; when they disagree, the spec wins and the implementation changes. Never hand-edit
a bundle (`public/swagger-pact.json`, `internal/swagger.json`); both are the bundler's output.

Project values come from `docs/contracts/openapi/profile.yaml` (template: [assets/profile.yaml](assets/profile.yaml)); read it first.
`<api>`, `<version>`, `<base_path>`, `<reference_resource>`, `<problem_type_base>`, `<auth_realm>`, and `<cache_name>` below are its values; `widget` is the resource being added.
Root: `docs/contracts/openapi/<api>/<version>/specs.yaml`. Everything else is `$ref`'d from it.
No profile: offer to create it before editing the spec. An API that does not follow this layout keeps its own conventions.

## Workflow

1. Read `profile.yaml`, `specs.yaml`, and the reference resource (`schemas/<reference_resource>/**`) before writing anything.
2. Add or edit YAML following [references/directory-layout.md](references/directory-layout.md).
3. Copy the operation skeleton from [references/endpoint-template.md](references/endpoint-template.md). Do not invent new header sets; reuse `components/parameters` and `schemas/common/responses/headers/headers.yaml`.
4. Pick status codes from [references/status-codes.md](references/status-codes.md). Every listed code for the method is required, not optional.
5. New tag? Add it to `tags:` in `specs.yaml` with a description. Internal-only tags get `x-internal: true`, and so does every path item that uses them.
6. Lint and bundle with the redocly CLI from `docs/contracts/openapi`:

```bash
redocly lint main --config .redocly.yaml
redocly bundle --config .redocly.yaml --component-renaming-conflicts-severity error
```

   `bundle` takes no file: it writes each `output` in `.redocly.yaml`, the public `<api>/<version>/public/swagger-pact.json` (api `main`, `x-internal` content removed) and the full `<api>/<version>/internal/swagger.json` (api `internal`). Paths in the config are relative to it, so both commands run unchanged on a host and in the container of [references/toolchain-integration.md](references/toolchain-integration.md).

7. Check for breaking changes against the last released public bundle: `oasdiff breaking <released swagger-pact.json> <api>/<version>/public/swagger-pact.json`. A finding means the change does not fit this version: make it additive, or start `<api>/v<N+1>/` (see **Versioning**).
8. Update `docs/CHANGELOG.md`, bump `info.version` (minor on additive), and record contract decisions as ADRs in `docs/architecture.md`.
9. If the project has no lint/bundle automation for the spec, or generates code from the bundle without a target for it, propose the snippets in [references/toolchain-integration.md](references/toolchain-integration.md). Suggest only; add them when the user confirms.

## Non-negotiable rules

**Spec format**
- `openapi: 3.0.3`. Use `nullable: true` (3.0 syntax), not `type: [string, "null"]` (3.1 syntax).
- No siblings next to `$ref` (3.0 ignores them; `spec-ref-siblings` is an error). Put the text in the parent schema's `description`, or wrap the reference in `allOf: [{ $ref }]` when a `default` must stay machine-readable.
- Every operation has `summary`, `description`, `operationId`, `tags`, explicit `security`.
- `operationId` is camelCase `verbNoun`: `createWidget`, `listWidgets`, `updateWidget` (PUT), `patchWidget`, `headWidgets`; the template has all ten.
- Business rules go in the operation `description` under a `**Business Rules:**` heading, and also in the field `description` they constrain.
- Every schema property has `description` and `example`. Strings get `minLength`/`maxLength`; integers get `minimum`/`maximum`; enums live in their own file under `schemas/common/entities/` with `x-enumDescriptions` (a value-to-description map, the form Redocly renders).
- Request body schemas set `additionalProperties: false`; unknown fields are `422` `unknown_field`, never silently dropped.
- Example keys are unique across the whole API and start with the resource (`widget_created`, `liveness_ok`; never bare `created` or `ok`): the bundler hoists them into `components/examples`, and the bundle command fails on a collision.

**URL and resources**
- Plural nouns, kebab-case path segments, camelCase path params: `/widgets/{widgetId}`.
- Version is in the server URL template (`/{version}`), never repeated in paths; rules under **Versioning**.
- Emitted links (`Location`, `Content-Location`, `links.*`, pagination links) are path-absolute and include the base path: `<base_path>/widgets/{id}`, e.g. `/v1/widgets/{id}`. A reference starting with `/` resolves against the host alone (RFC 3986 §5.2.2).
- Path-level `parameters:` block holds what every operation shares: the id param plus `API-Version`, `Request-Id`, `Correlation-Id`, `traceparent`, `tracestate`, and the optional signature headers.
- Collection path supports `POST GET HEAD OPTIONS`. Item path supports `GET PUT PATCH DELETE HEAD OPTIONS`. Omit a method only with a stated reason in the plan.
- `OPTIONS` has `security: []` and returns `204` with `Allow`, `Accept-Patch` (item path), and the CORS headers.
- Any other method on a known path is `405` with `Allow`. OpenAPI cannot express absent methods, so 405, 414, and 431 are documented once in `info.description`, not per operation.
- `PUT` never creates (no upsert): unknown id is `404`.

**Versioning**
- The URL selects the version. `API-Version` is an optional assertion: when sent it must equal the URL version, else `400` (`/headers/API-Version` `invalid_enum_value`).
- The `info.version` major equals the URL version (`v1` is `1.x.y`). A version takes additive changes only, each a minor bump.
- A breaking change starts `<api>/v<N+1>/`: its own tree, its own pair of `apis` entries, its own server path, `info.version: <N+1>.0.0`, and a "Breaking" line in the CHANGELOG. The version it replaces gets `deprecated: true` and the deprecation headers.

**Identifiers and time**
- IDs are UUID v7 (RFC 9562), `format: uuid`. Timestamps are RFC 3339 `format: date-time`, UTC `Z`. `createdAt` is immutable; `updatedAt` is always present on responses and `required` in the entity schema.

**Media types** (decision table in [references/media-types.md](references/media-types.md))
- Requests and 2xx bodies: `application/json`. Errors: `application/problem+json`. PATCH bodies: `application/merge-patch+json` (RFC 7396).
- Declare `content:` media types per operation. Unlisted request `Content-Type` is `415`; unsatisfiable `Accept` is `406`. An unsatisfiable `Accept-Encoding` gets an unencoded response, and `406` only when the client also refuses `identity` (RFC 9110 §12.5.3).
- No `charset` parameter on JSON. No `application/json-patch+json`, HAL, JSON:API, or `health+json` (rejected, reasons recorded).

**Request headers** (via `components/parameters`; tables in [references/headers.md](references/headers.md))
- Never declare `Authorization`, `Accept`, or `Content-Type` as header parameters; OpenAPI 3.0.3 ignores such definitions. Authentication is the operation's `security`; the token format (`Bearer v4.(public|local).…`, both kinds opaque to the client, `v4.local` legitimate for tokens issued and verified by the same party) is documented in `securitySchemes.PasetoAuth`. `Accept` follows from response `content`, `Content-Type` from `requestBody.content`.
- `Idempotency-Key` on `POST` (required), `If-Match` on `PUT`/`PATCH`/`DELETE`, `If-None-Match` on `GET`/`HEAD`, `Accept-Encoding` on `GET`. `Idempotency-Key` is a Structured Field String (RFC 9651): the UUID in double quotes is canonical, and a bare UUID is accepted too.
- Request signing (RFC 9421: `Signature-Input`, `Signature`, `Content-Digest`) is optional in the spec; the operation description states which paths require it. The signature profile in headers.md fixes components, parameters, algorithms, and failure mapping, as RFC 9421 §1.4 requires of every application.
- Never create `X-` prefixed headers (RFC 6648): `Request-Id`, not `X-Request-Id`.
- Every header the API reads or writes must exist in the spec, in `headers.yaml` or `components/parameters`; the three in the first rule are covered by `security` and `content`.

**Response envelope**
- Single resource: `{ data: <Entity>, meta: Meta }`. Collection: `{ data: [<Entity>], meta: Meta, pagination: Pagination }`.
- `Meta` (`requestId`, `traceId`, `apiVersion`) is required on every 2xx body. Error bodies use the `Problem` schema directly, no envelope.
- Entities carry a `required` `links.self` (HATEOAS, `uri-reference`).
- Envelope, entity, and links schemas live together in `responses/entities/<resource>.yaml` as `<Resource>Envelope`, `<Resource>`, `<Resource>Links`.

**Errors** (RFC 9457 Problem Details; schema, catalogue, and vocabulary in [references/errors.md](references/errors.md))
- One schema `Problem`: `requestId`, `traceId`, `timestamp`, then RFC members `type`, `title`, `status`, `detail`, then `violations[]`. One media type `application/problem+json`, returned regardless of `Accept`, for every operation including admin and system. No `instance`, no top-level `code`.
- `type` is the machine-readable discriminator: `<problem_type_base><kebab-slug>`, constant per problem type, resolving to a docs page. `title` is constant per type; `detail` is one occurrence-specific sentence.
- `violations[]` items are `{ field, code, message }`. `field` is an RFC 6901 JSON Pointer: body root (`/name`), `""` for the whole body, or reserved roots `/headers/<Name>`, `/query/<param>`, `/path/<param>`. `code` comes from the closed snake_case vocabulary.
- Always `$ref` the shared files in `schemas/common/responses/errors/`. Add a new example key to the shared file instead of creating a resource-specific error response. A `type` slug or violation code outside the baseline in [references/errors.md](references/errors.md) is a project addition: record it under `additions` in the profile, with an example in the shared file.
- `400` = input could not be interpreted (syntax, header shape, query or path parse). `413` = body over the limit. `415` = unsupported request media type. `422` = parsed but breaks schema or business validation. `409` = conflict with current server state (business rule, or in-flight idempotent request as `request-in-progress`). `412` = ETag mismatch. `428` = precondition header required but absent. `500` = a defect. `503` = dependency outage, overload, or unavailable signing keys; clients retry it, so every operation declares it.
- `403` is opt-in: an operation whose access depends on more than a valid token (scope, role, ownership) declares it (`forbidden.yaml`). A resource whose existence must stay hidden answers `404`.
- `401` always carries `WWW-Authenticate`: the bare `Bearer realm="<auth_realm>"` challenge when no credentials were sent, RFC 6750 `error`/`error_description` only for rejected credentials (RFC 6750 §3). `405` always carries `Allow`. `429` and `503` carry `Retry-After`. Error responses carry `Cache-Control: no-store`. 5xx `detail` is generic.

**Idempotency** (draft-ietf-httpapi-idempotency-key-header; outcomes table and stored-outcomes rule in [references/status-codes.md](references/status-codes.md))
- `POST` requires `Idempotency-Key` (UUID v7, quoted or bare). Key scope is client + path. Fingerprint is method + path + body. Retention 24h.
- Missing or malformed key is `400`. A replay while the original is in flight is `409` `request-in-progress` with `Retry-After`. The same key with a different fingerprint is `422` `idempotency-key-reused`. So every `POST` declares `400`, `409`, and `422`.
- Only a successful outcome is stored. A replay of a completed create returns the stored `201`, headers, and body, and adds `Idempotent-Replayed: true`; `POST` 201 responses declare that header. A failed request (`4xx`, `5xx`) stores nothing and runs again on retry.
- Reuse the existing example keys `idempotency_key_*` in the shared error files; do not add resource-specific copies.

**Lists** (details in [references/pagination-filtering.md](references/pagination-filtering.md))
- `size` default 20, max 100. Filters are `array` with `style: form, explode: false` (comma-separated OR). `sort` uses `-` prefix for DESC and a regex `pattern` whitelist. `id` is always the final tiebreaker so cursors are stable.
- Both page-based and opaque-cursor pagination; `cursor` overrides `page`. Cursor mode omits `currentPage`, `totalItems`, and `totalPages`, so no page pays for a count; `HEAD` returns the total as `Total-Count`.
- `fields` narrows optional and nested properties only; `required` properties are always returned, so a projected response still validates.
- `HEAD` on a collection takes the same query parameters as `GET` (`fields` too: the list ETag depends on it) and therefore declares the same `400`. It adds `Total-Count`.

**Caching and concurrency** (header sets in [references/headers.md](references/headers.md))
- Single-resource ETags are strong (`"..."`), derived from the resource version (`id` + `updatedAt`), not from encoded bytes, so they stay identical across `Content-Encoding` values. Reason: RFC 9110 §13.1.1 requires strong comparison for `If-Match`; a weak ETag can never satisfy it.
- Collection ETags may be weak (`W/"..."`), hashed over `data` and `pagination`, never `meta` (it changes per request). `If-None-Match` uses weak comparison, so `304` works for both kinds.
- Cacheable `GET`/`HEAD` responses declare the CACHE set (`ETag`, `Cache-Control`, `Cache-Status`, and `Last-Modified` on a single resource) plus a `304` response ref `responses/not-modified.yaml`.
- `304` carries the CACHE set without `Last-Modified`, plus `Vary` and the rate-limit headers (RFC 9110 §15.4.5).
- `PUT`/`PATCH` honour `If-Match` with strong comparison and declare `412` (response carries the current `ETag`). Their `200` carries `ETag` and `Content-Location` equal to the request path, so the body counts as the new representation (RFC 9110 §8.7); the `ETag` on `PUT` deviates deliberately from §9.3.4 (reason in headers.md). `DELETE` honours `If-Match` when present and declares `412`.
- `If-Match` is optional by default. For a resource with concurrent writers, make `IfMatchHeader` `required: true` on its `PUT`/`PATCH` and declare `428` (`precondition-required.yaml`). State the choice in the operation description.
- `PUT` requires all fields; `PATCH` is a merge-patch document: `minProperties: 1`, no `required`, `null` on a required field is `422` `invalid_type`.

**Cross-cutting response headers** (sets, syntax, and reasons in [references/headers.md](references/headers.md))
- Rate limit: every `2xx` and `304` response of an authenticated operation declares `RateLimit-Limit`, `RateLimit-Remaining`, `RateLimit-Reset`, and `RateLimit-Policy`. `429` declares them too and adds `Retry-After`; other errors do not.
- Deprecation (RFC 9745, RFC 8594): a deprecated operation sets `deprecated: true` and emits `Deprecation`, `Sunset`, and a `Link` to its successor.
- CORS (Fetch standard): OPTIONS `204` declares the full CORS set. Other responses carry `Access-Control-Allow-Origin` and `Access-Control-Expose-Headers` when the request has `Origin`; this is stated once in `info.description`, not per response file.
- Security headers (`X-Content-Type-Options`, `Content-Security-Policy`, `Strict-Transport-Security`, and the rest of the list) are set on every response and documented once in `info.description`. Do not add them to response files.

**Admin / internal**
- Internal endpoints live under `/admin/...`, are tagged `Admin`, and use `BasicAuth`. The path item and the tag both carry `x-internal: true`; the path-item flag is what keeps the endpoints out of the public bundle. Success bodies use their own slim schemas under `schemas/admin/`; error bodies use the shared problem files like everyone else.
- Every operation with a non-empty `security` requirement declares `401`, admin included.
- System probes (`/liveness`, `/readiness`, `/health`) use tag `System` and no envelope. Their `503` responses carry `Retry-After`.

**Enforcement**
- The generic ruleset is [assets/rest-api-ruleset.yaml](assets/rest-api-ruleset.yaml), installed verbatim as `docs/contracts/openapi/rest-api-ruleset.yaml` (a `diff` of the two prints nothing). The project's `.redocly.yaml` beside it (template: [assets/redocly.yaml](assets/redocly.yaml)) extends it and owns the `apis` block and rule overrides. A new convention gets a rule in the skill's ruleset first, then the installed copy, then a row in the rule map in [references/directory-layout.md](references/directory-layout.md).
- Pin the redocly CLI version wherever lint and bundle run; never `latest`. The `REDOCLY_VERSION` variable in [references/toolchain-integration.md](references/toolchain-integration.md) shows the pattern.

## Review checklist

Before declaring an OpenAPI change done, check what lint and bundle cannot. They already cover refs, media types, example validity, example-key collisions, and the status lists of `POST`, `PUT`, and `PATCH`.
- [ ] `redocly lint main` passes with zero errors and zero warnings you introduced.
- [ ] `redocly bundle` wrote both bundles; the public one has no `/admin` path.
- [ ] Each `GET`, `HEAD`, `DELETE`, and `OPTIONS` operation lists every status code of the matrix in [references/status-codes.md](references/status-codes.md); an operation restricted by scope, role, or ownership declares `403`.
- [ ] Each success response declares the full header set in [references/headers.md](references/headers.md).
- [ ] Emitted links include the base path.
- [ ] Error responses use the shared files only; any problem `type` slug or violation `code` outside the baseline in [references/errors.md](references/errors.md) is under `additions` in the profile and has an example in the shared file.
- [ ] PATCH bodies are `application/merge-patch+json`.
- [ ] Request bodies, responses, and examples each have their own file; no inline schemas in `specs.yaml` except `components/parameters` and `securitySchemes`.
- [ ] Examples exist for the request body, the 2xx response, and at least one error.
- [ ] Every new header exists in `headers.yaml` or `components/parameters`, and browser-facing ones are in the `Access-Control-Expose-Headers` / `Access-Control-Allow-Headers` examples.
- [ ] `oasdiff breaking` is clean, or the change went into a new `v<N+1>` tree.
- [ ] `docs/CHANGELOG.md` updated; contract decisions recorded as an ADR.

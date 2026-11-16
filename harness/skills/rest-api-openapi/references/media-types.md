# Media types

Baseline decision record for every JSON media type considered; a project departs from a row only with an ADR. Status values:
**Adopted** (in the spec), **Candidate** (use when the named feature arrives),
**Rejected** (considered, reason given), **N/A** (no matching use case).

| Media type | Spec | Status | Decision |
|---|---|---|---|
| `application/json` | RFC 8259 | Adopted | All request bodies and all 2xx bodies. No `charset` parameter: RFC 8259 defines none and says adding one has no effect. |
| `application/problem+json` | RFC 9457 | Adopted | Every 4xx/5xx body. Schema and catalogue in [errors.md](errors.md). Returned even when the client sent `Accept: application/json`. |
| `application/merge-patch+json` | RFC 7396 | Adopted | PATCH request body. `Patch<Resource>` is the merge-patch document. `null` on a required field is a 422, not a clear. Advertised with `Accept-Patch` on item-path OPTIONS and on 415 (RFC 5789). |
| `application/health+json` | draft-inadarei-api-health-check | Rejected | Expired draft, never registered. Probes keep the project's `Liveness` / `Readiness` / `Health` entities, which already carry `status`, dependency checks, and uptime. |
| `application/json-patch+json` | RFC 6902 | Rejected | Operation lists (`add`, `remove`, `move`, `test`) pay off on deep documents. Resources in this layout are flat. Revisit only if clients need atomic `test` + `replace` across fields. |
| `application/json-seq` | RFC 7464 | Candidate | Bulk export or event-stream endpoints. RS-delimited, registered. Declare per operation; never for paginated lists. |
| `application/x-ndjson`, `application/jsonl` | unregistered | Rejected | Unregistered. Use `application/json-seq` for the same job. |
| `application/hal+json` | draft-kelly-json-hal | Rejected | Envelope is `data` / `meta` / `pagination` with plain `links`. HAL's `_links` / `_embedded` would break every client for no new capability. HATEOAS stays as `links.self` plus pagination links, optionally mirrored in a `Link` header (RFC 8288). |
| `application/vnd.api+json` | JSON:API | Rejected | Same envelope conflict, plus mandated `attributes` / `relationships` structure and query syntax (`page[size]`, `filter[...]`) that differs from the adopted `page`, `size`, `sort`, `fields` parameters. |
| `application/ld+json` | W3C JSON-LD | N/A | No linked-data or SEO consumers. |
| `application/linkset+json` | RFC 9264 | N/A | Link relations are few and travel in the body. Revisit if a resource grows more than a handful of relations. |
| `application/schema+json` | JSON Schema | Rejected | The OpenAPI document is the contract. Do not serve JSON Schema separately; clients can read `schemas/` from the bundled spec. |
| `application/jwt`, `application/at+jwt`, `application/secevent+jwt`, `application/oauth-authz-req+jwt`, `application/jose+json` | RFC 7519, 9068, 8417, 9101, 7515 | N/A | Authentication is PASETO v4 bearer tokens (ADR in the profile, `decisions.authentication`). No JWT, no OAuth flows, no SETs. |
| `application/jwk+json`, `application/jwk-set+json` | RFC 7517 | Candidate | If clients must verify response signatures (RFC 9421 `keyid`), publish the public keys at `/.well-known/jwks.json` as `application/jwk-set+json`. Not in the spec yet. |
| `application/jrd+json` | RFC 7033 | N/A | No WebFinger discovery. |
| `application/scim+json` | RFC 7644 | N/A | No user or group provisioning endpoints. |
| `application/yang-data+json` | RFC 8040 | N/A | Not a RESTCONF network-management API. |
| `application/senml+json` | RFC 8428 | N/A | No sensor measurements. Revisit if telemetry ingestion is added. |
| `application/geo+json` | RFC 7946 | N/A | No geometry. If a location field is added, type that field as a GeoJSON `Point`; do not switch the whole body. |
| `application/cloudevents+json` | CNCF CloudEvents 1.0 | Candidate | Webhooks or outbound events, if added, use the CloudEvents envelope with `type` like `<reverse-domain>.<resource>.created.v1`. Not in the spec. |

## Rules

- Declare media types per operation under `content:`. Never rely on a default.
- Request `Content-Type` not listed for the operation: `415`. `Accept` that cannot be satisfied: `406`.
- Any `+json` structured-syntax suffix type (RFC 6839) is still JSON; `application/merge-patch+json` is parsed with the ordinary JSON parser.
- OPTIONS responses list patch formats in `Accept-Patch` (RFC 5789): `application/merge-patch+json`.
- Do not add `charset` to JSON media types.
- Adopting a media type is a contract decision: record it in `docs/architecture.md` as an ADR, bump `info.version`, and list it under `additions.media_types` in the profile. A Rejected or N/A row changes no contract.

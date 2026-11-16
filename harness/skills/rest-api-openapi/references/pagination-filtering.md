# Pagination, filtering, sorting, search, projection

All list endpoints (`GET` and `HEAD` on a collection) accept the same parameter family, in this order.

## Contents

- Query parameters, filter template, parameter examples
- Response: `Pagination`, page mode and cursor mode
- Cursor rules
- Field projection
- Caching interaction

## Query parameters

| Param | Type | Constraints | Default | Notes |
|---|---|---|---|---|
| `page` | integer | `minimum: 1` | 1 | 1-indexed; ignored when `cursor` present |
| `size` | integer | `minimum: 1`, `maximum: 100` | 20 | |
| `<field>` filter | array of string/enum | `style: form`, `explode: false`, `maxItems` (10 for free text, enum size for enums), item `minLength`/`maxLength` | | comma-separated = OR; repeat for several fields |
| `sort` | array of string | item `pattern: "^-?(fieldA\|fieldB\|...)$"`, `maxItems: 5`, `style: form`, `explode: false` | `["-createdAt"]` | `-` prefix = DESC; whitelist every sortable field in the regex; the server always appends `id` as the final tiebreaker so equal keys (same `createdAt`) never reorder between pages |
| `q` | string | `minLength: 2`, `maxLength: 255` | | full-text search; document which fields it covers and how it matches (stemming, language) |
| `cursor` | string | `maxLength: 500` | | opaque, base64url; overrides `page` |
| `fields` | string | `pattern: "^[a-zA-Z,:()]+$"`, `minLength: 1`, `maxLength: 500` | | projection of optional and nested properties; `required` properties always included; nested via `parent:(child)` |

`components/parameters` keys: `PageParam`, `SizeParam`, `<Field>FilterParam`, `SortParam`, `SearchParam`, `CursorParam`, `FieldsParam`.

HEAD on a collection takes the same query parameters as GET, `fields` included, so its ETag matches the GET. It takes no `Accept-Encoding`.

### Filter parameter template

```yaml
BrandFilterParam:
  name: brand
  in: query
  required: false
  description: |
    Filter by brand(s). Comma-separated for OR matching.
    Example: ?brand=Apple,Samsung
  schema:
    type: array
    items:
      type: string
      minLength: 1
      maxLength: 100
    maxItems: 10
  style: form
  explode: false
  example: ["Apple"]
```

Enum filters reference the shared enum: `items: { $ref: "schemas/common/entities/widget-status.yaml#/WidgetStatus" }`.

### Multiple examples on a parameter

Use `examples:` (plural) with keyed entries carrying `value` and `summary`, as `FieldsParam` does. Use `example:` (singular) when one value suffices. Never both.

## Response: `Pagination` (`schemas/common/entities/pagination.yaml`)

```yaml
pagination:
  size: 20           # required
  hasNext: true      # required
  hasPrevious: false
  page: 1            # page mode only
  totalItems: 150    # page mode only, minimum 0
  totalPages: 8      # page mode only, minimum 0
  nextCursor: "..."      # only when hasNext
  previousCursor: null   # only when hasPrevious
  links:                 # PaginationLinks: self, first, last (page mode only), next (nullable), previous (nullable); base path included
    self: "/v1/widgets?page=1&size=20"
```

- Page mode (no `cursor`): `page`, `totalItems`, and `totalPages` are present. `totalPages` is `0` for an empty result, `page` stays `1`.
- Cursor mode (`cursor` sent): the three are omitted, and so is `links.last`, so no page pays for a count. A client that needs the total calls `HEAD`, which returns `Total-Count`.
- `Pagination` therefore requires only `size` and `hasNext`.

Reuse this schema for every collection; put it on the list envelope as a required `pagination` property:

```yaml
WidgetsListEnvelope:
  type: object
  required: [data, meta, pagination]
  properties:
    data:
      type: array
      items:
        $ref: "widget.yaml#/Widget"
    meta:
      $ref: "../../../common/responses/entities/meta.yaml#/Meta"
    pagination:
      $ref: "../../../common/entities/pagination.yaml#/Pagination"
```

## Cursor rules

- Cursor encodes sort field, boundary value, boundary id, and direction. Clients must treat it as opaque; the description says so explicitly.
- When `cursor` is sent, ignore `page`, but still honour `size`, filters, `sort`, and `q`. Changing filters or sort invalidates a cursor; return `400` (type `bad-request`, violation `/query/cursor` `invalid_cursor`) if it cannot be decoded.
- Always provide the list examples `list`, `empty`, `withCursor`, plus one filtered example.

## Field projection

- `fields` narrows optional and nested properties only. Properties the entity schema marks `required` are always returned, so a projected response still validates against the schema.
- Default (no `fields`): every `required` property plus the optional ones the parameter description names as default.
- Unknown field names: `400`.
- Nested syntax: `parent:(child1,child2)`.

## Caching interaction

List responses carry `ETag`, `Cache-Control`, and `Cache-Status`, and support `If-None-Match` -> `304`. List ETags may be weak (`W/"..."`), hashed over `data` and `pagination`, never `meta`; single-resource ETags are strong (see headers.md, ETag rules). Pagination links may additionally be mirrored in a `Link` header (RFC 8288, `rel="next"`, `rel="prev"`, `rel="first"`, `rel="last"`); the body `pagination.links` remains authoritative. The ETag must incorporate every query parameter that changes the representation (`page`, `size`, filters, `sort`, `q`, `cursor`, `fields`). `Vary` must list request headers that affect it (`Accept-Encoding`, `Authorization`).

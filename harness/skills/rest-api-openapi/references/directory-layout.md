# Directory layout and `$ref` conventions

## Contents

- Tree
- Project profile
- Adding a new resource `widgets`
- File-type contracts
- Naming
- Where the redocly files live
- Rule map
- `$ref` rules

## Tree

`<api>` and `<version>` come from `profile.yaml`; `widgets` stands for any public resource.

```
docs/contracts/openapi/
├── .redocly.yaml                       # project config: extends the ruleset, owns the `apis` block
├── rest-api-ruleset.yaml               # generic rules; verbatim copy of the skill's assets/rest-api-ruleset.yaml
├── profile.yaml                        # project values the skill reads first
└── <api>/<version>/
    ├── specs.yaml                      # root: info, servers, security, paths, components.parameters, securitySchemes, tags
    ├── public/
    │   └── swagger-pact.json           # bundle of api `main`, x-internal content removed; never edit
    ├── internal/
    │   └── swagger.json                # bundle of api `internal`, everything; never edit
    └── schemas/
        ├── common/
        │   ├── entities/               # shared value objects: widget-status.yaml, pagination.yaml
        │   └── responses/
        │       ├── entities/meta.yaml  # Meta envelope block
        │       ├── headers/headers.yaml# every reusable RESPONSE header
        │       ├── errors/             # one RFC 9457 problem response per status, shared by every operation
        │       │   ├── bad-request.yaml, unauthorized.yaml, forbidden.yaml (403, opt-in per operation),
        │       │   │   not-found.yaml, not-acceptable.yaml,
        │       │   │   conflict.yaml, precondition-failed.yaml, content-too-large.yaml,
        │       │   │   unsupported-media-type.yaml, unprocessable-entity.yaml,
        │       │   │   precondition-required.yaml (428, opt-in per resource), rate-limit.yaml,
        │       │   │   server-error.yaml, service-unavailable.yaml
        │       │   └── entities/problem.yaml   # Problem, Violation
        │       └── system/             # liveness/readiness/health responses
        │           ├── entities/       # Liveness, Readiness, Health, DependencyCheck
        │           └── examples/
        ├── widgets/                    # one directory per public resource
        │   ├── requests/
        │   │   ├── create-widget.yaml  # requestBody object (description, required, content)
        │   │   ├── update-widget.yaml
        │   │   ├── patch-widget.yaml
        │   │   └── entities/widget.yaml      # CreateWidget, UpdateWidget, PatchWidget schemas
        │   ├── responses/
        │   │   ├── widget-created.yaml       # one file per (operation, status) response object
        │   │   ├── widget-retrieved.yaml
        │   │   ├── widget-updated.yaml
        │   │   ├── widget-deleted.yaml
        │   │   ├── widget-head.yaml
        │   │   ├── widget-options.yaml
        │   │   ├── widgets-list.yaml
        │   │   ├── widgets-head.yaml
        │   │   ├── widgets-options.yaml
        │   │   ├── not-modified.yaml
        │   │   └── entities/
        │   │       ├── widget.yaml           # WidgetEnvelope, Widget, WidgetLinks
        │   │       └── widgets-list.yaml     # WidgetsListEnvelope
        │   └── examples/
        │       ├── create-request.yaml       # keyed examples: widget_basic, widget_with_status
        │       ├── update-request.yaml       # widget_full, widget_patch_status, widget_patch_name
        │       ├── widget.yaml               # widget_created, widget, widget_updated, widget_patched
        │       └── widgets-list.yaml         # widgets_list, widgets_filtered_by_kind, widgets_empty, widgets_with_cursor
        └── admin/                      # internal resources; their path items carry x-internal: true
            ├── responses/
            │   └── entities/
            └── examples/
```

## Project profile

`docs/contracts/openapi/profile.yaml`, created from the skill's `assets/profile.yaml`:

| Key | Used for |
|---|---|
| `api`, `version` | the `<api>/<version>/` directory, the server path segment, the `API-Version` value |
| `base_path` | prefix of every emitted link: `Location`, `Content-Location`, `links.*`, pagination links |
| `reference_resource` | `schemas/<reference_resource>/`: the resource whose files new ones are copied from |
| `problem_type_base` | Problem `type` = base + kebab-case slug |
| `auth_realm`, `cache_name` | `WWW-Authenticate` realm, `Cache-Status` cache identifier |
| `decisions` | ADR ids for spec-first and authentication |
| `implementation_status` | optional plan file that tracks spec versus implementation |
| `additions` | project problem types, violation codes, media types, and headers beyond the skill's baseline tables, each with its ADR |

The skill's reference tables are the baseline for every project and change only through a change to the
skill. What a single project adds goes under `additions`, so each vocabulary stays closed per project:
baseline plus additions.

## Adding a new resource `widgets`

Create exactly this tree, swapping the noun:

```
schemas/widgets/
├── requests/{create-widget,update-widget,patch-widget}.yaml
├── requests/entities/widget.yaml           # CreateWidget, UpdateWidget, PatchWidget
├── responses/{widget-created,widget-retrieved,widget-updated,widget-deleted,
│              widget-head,widget-options,widgets-list,widgets-head,widgets-options,
│              not-modified}.yaml
├── responses/entities/widget.yaml          # WidgetEnvelope, Widget, WidgetLinks
├── responses/entities/widgets-list.yaml    # WidgetsListEnvelope
└── examples/{create-request,update-request,widget,widgets-list}.yaml
```

Shared enums for the resource go in `schemas/common/entities/<name>.yaml` (e.g. `widget-status.yaml`), never inline.

## File-type contracts

| File kind | Top level is | Referenced from | Example |
|---|---|---|---|
| requestBody | `description`, `required`, `content` | `paths.*.requestBody.$ref` | `requests/create-widget.yaml` |
| response | `description`, `headers`, `content` | `paths.*.responses.<code>.$ref` | `responses/widget-created.yaml` |
| entity bag | map of PascalCase schema names | `schema.$ref: "file.yaml#/Name"` | `responses/entities/widget.yaml#/Widget` |
| examples bag | map of example keys, each `summary` + `value` | `examples.<key>.$ref: "file.yaml#/key"` | `examples/widget.yaml#/widget_created` |
| headers bag | map of PascalCase header names ending `Header` | `headers.<Http-Name>.$ref` | `headers.yaml#/ETagHeader` |

## Naming

| Thing | Style | Example |
|---|---|---|
| File names | kebab-case | `precondition-failed.yaml` |
| Response file | `<resource>-<past-tense-outcome>` or `<resources>-<method>` | `widget-created.yaml`, `widgets-head.yaml` |
| Schema keys | PascalCase | `WidgetsListEnvelope` |
| Header keys in bag | PascalCase + `Header` suffix; request/response variants suffixed `ResponseHeader` when both exist | `TraceparentResponseHeader` |
| Example keys | snake_case, starting with the resource, unique across the whole API (the bundler hoists them into `components/examples`, and the bundle fails on a collision) | `widget_patch_status`, `liveness_ok` |
| JSON properties | camelCase | `createdAt`, `totalItems` |
| Query params | camelCase or single word | `page`, `size`, `q`, `fields` |
| Path params | camelCase + `Id` | `widgetId` |
| `components/parameters` keys | PascalCase + `Param` or `Header` | `SizeParam`, `IfMatchHeader` |
| Problem `type` slug | kebab-case | `precondition-failed` |
| Violation `code` | lowercase snake_case | `too_small` |
| Violation `field` | RFC 6901 JSON Pointer | `/name`, `/headers/If-Match` |

## Where the redocly files live

Both at the root of the contracts directory, beside the `<api>/` tree and above every API version:
`docs/contracts/openapi/.redocly.yaml` and `docs/contracts/openapi/rest-api-ruleset.yaml`. Reasons:
- `root`, `output`, and `extends` resolve relative to `.redocly.yaml`. The lint and bundle commands run from this directory, on a host or with this directory mounted in a container.
- One ruleset governs every API and version under it (`<api>/v1`, a future `<api>/v2`, any second API). Each gets its own pair of `apis` entries: a public one with `remove-x-internal`, a full internal one.
- `rest-api-ruleset.yaml` is the installed copy of the skill's `assets/rest-api-ruleset.yaml`; keep both identical. `.redocly.yaml` starts from `assets/redocly.yaml` and holds only what differs per project: the `apis` block and rule overrides.
Do not place per-version or per-API copies deeper in the tree.

## Rule map

| Rule | Convention it enforces |
|---|---|
| `operation-4xx-problem-details-rfc7807` | Problem Details on every 4xx |
| `response-contains-header` | header sets per status: `API-Version`, `Request-Id`, `Cache-Control` on 4xx; `WWW-Authenticate` on 401; `Retry-After` on 429 and 503 |
| `rule/post-declares-create-outcomes`, `rule/put-patch-declare-precondition-outcomes` | status matrix for `POST` and `PUT`/`PATCH` |
| `rule/operation-id-camel-case` | `operationId` style |
| `rule/operation-security-explicit` | explicit `security` on every operation; `security-defined` alone accepts a root-level default |
| `rule/no-ignored-header-parameters` | no `Authorization`, `Accept`, or `Content-Type` header parameter |
| `rule/no-version-in-paths`, `paths-kebab-case`, `path-segment-plural`, `no-http-verbs-in-paths` | URL rules |
| `operation-tag-defined`, `tag-description` | every tag is declared, with a description |
| `request-mime-type`, `response-mime-type` | media-type table |
| `spec-ref-siblings`, `no-unused-components`, `no-invalid-schema-examples`, `no-invalid-media-type-examples` | spec format, as errors |
| `scalar-property-missing-example` | property examples, as warning |

Limits to know:
- `rule/post-declares-create-outcomes` treats every `POST` as a create. A project with an action-style or internal `POST` overrides the rule in its `.redocly.yaml`.
- `path-segment-plural` ships with the exceptions `admin`, `cache`, `health`, `liveness`, `readiness`. A project that needs more repeats the rule in its `.redocly.yaml` with the longer list.
- `no-http-verbs-in-paths` runs with `splitIntoWords: true`; the default substring match rejects `/widgets` ("get") and `/outputs` ("put").

## `$ref` rules

- Paths are relative to the file that contains the `$ref`, not to `specs.yaml`.
  - From `specs.yaml`: `schemas/widgets/responses/widget-created.yaml`
  - From `schemas/widgets/responses/*.yaml`: `../../common/responses/headers/headers.yaml#/ETagHeader`
  - From `schemas/common/responses/errors/*.yaml`: `../headers/headers.yaml#/ETagHeader`
  - From `schemas/widgets/requests/entities/widget.yaml`: `../../../common/entities/widget-status.yaml#/WidgetStatus`
- Intra-file refs use `#/Name` (e.g. `$ref: "#/Widget"`).
- Request parameters live in `specs.yaml` `components/parameters` and are referenced as `#/components/parameters/Name`. Response headers live in `headers.yaml`. Do not mix the two.
- `security` on an operation references `securitySchemes` keys: `PasetoAuth`, `BasicAuth`, or `[]` for none.
- The decorator `remove-x-internal` (api `main`) removes exactly the nodes that carry `x-internal: true`. Flag the internal path items, or their operations stay in the public bundle. Flag the tag too, or the public bundle keeps its entry.

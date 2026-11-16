# Endpoint template

Replace `widget`/`Widget`/`widgets` with the resource noun. Keep the structure, order, and refs.
`/v1` in the examples is the profile's `base_path`.

## Contents

1. `specs.yaml` paths, `components/parameters`, `tags`
2. Request bodies: `create-widget.yaml`, `update-widget.yaml`, `patch-widget.yaml`
3. Request entities: `CreateWidget`, `UpdateWidget`, `PatchWidget`
4. Responses: `widget-created.yaml` and the files derived from it
5. Response entities: `WidgetEnvelope`, `Widget`, `WidgetLinks`
6. Examples
7. Shared enum

## 1. `specs.yaml` paths

```yaml
  /widgets:
    # Common parameters for all operations on this path
    parameters:
      - $ref: "#/components/parameters/ApiVersionHeader"
      - $ref: "#/components/parameters/RequestIdHeader"
      - $ref: "#/components/parameters/TraceparentHeader"
      - $ref: "#/components/parameters/TracestateHeader"
      - $ref: "#/components/parameters/CorrelationIdHeader"
      - $ref: "#/components/parameters/SignatureInputHeader"
      - $ref: "#/components/parameters/SignatureHeader"
      - $ref: "#/components/parameters/AcceptSignatureHeader"
      - $ref: "#/components/parameters/WantContentDigestHeader"

    post:
      summary: Create a new widget
      description: |
        Creates a new widget resource. The widget will be assigned a unique UUID v7 identifier
        and the creation time will be automatically set to the current timestamp.
      operationId: createWidget
      tags:
        - Widgets
      security:
        - PasetoAuth: []
      parameters:
        - $ref: "#/components/parameters/IdempotencyKeyHeader"
        - $ref: "#/components/parameters/ContentDigestHeader"
      requestBody:
        $ref: "schemas/widgets/requests/create-widget.yaml"
      responses:
        "201":
          $ref: "schemas/widgets/responses/widget-created.yaml"
        "400":
          $ref: "schemas/common/responses/errors/bad-request.yaml"
        "401":
          $ref: "schemas/common/responses/errors/unauthorized.yaml"
        "406":
          $ref: "schemas/common/responses/errors/not-acceptable.yaml"
        "409":
          $ref: "schemas/common/responses/errors/conflict.yaml"
        "413":
          $ref: "schemas/common/responses/errors/content-too-large.yaml"
        "415":
          $ref: "schemas/common/responses/errors/unsupported-media-type.yaml"
        "422":
          $ref: "schemas/common/responses/errors/unprocessable-entity.yaml"
        "429":
          $ref: "schemas/common/responses/errors/rate-limit.yaml"
        "500":
          $ref: "schemas/common/responses/errors/server-error.yaml"
        "503":
          $ref: "schemas/common/responses/errors/service-unavailable.yaml"

    get:
      summary: List all widgets
      description: |
        Retrieves a paginated list of all widgets. Supports filtering by <fields>,
        and full-text search across <fields> using the `q` parameter.
      operationId: listWidgets
      tags:
        - Widgets
      security:
        - PasetoAuth: []
      parameters:
        - $ref: "#/components/parameters/PageParam"
        - $ref: "#/components/parameters/SizeParam"
        # resource-specific filters here, e.g. WidgetKindFilterParam
        - $ref: "#/components/parameters/SortParam"      # define WidgetSortParam if sortable fields differ
        - $ref: "#/components/parameters/SearchParam"
        - $ref: "#/components/parameters/CursorParam"
        - $ref: "#/components/parameters/FieldsParam"    # define WidgetFieldsParam if fields differ
        - $ref: "#/components/parameters/IfNoneMatchHeader"
        - $ref: "#/components/parameters/AcceptEncodingHeader"
      responses:
        "200":
          $ref: "schemas/widgets/responses/widgets-list.yaml"
        "304":
          $ref: "schemas/widgets/responses/not-modified.yaml"
        "400":
          $ref: "schemas/common/responses/errors/bad-request.yaml"
        "401":
          $ref: "schemas/common/responses/errors/unauthorized.yaml"
        "406":
          $ref: "schemas/common/responses/errors/not-acceptable.yaml"
        "429":
          $ref: "schemas/common/responses/errors/rate-limit.yaml"
        "500":
          $ref: "schemas/common/responses/errors/server-error.yaml"
        "503":
          $ref: "schemas/common/responses/errors/service-unavailable.yaml"

    head:
      summary: Get widgets collection metadata
      description: |
        Returns headers only for the widgets collection (no response body).
        Useful for checking collection size or validating cached data via ETag.
      operationId: headWidgets
      tags:
        - Widgets
      security:
        - PasetoAuth: []
      parameters:
        - $ref: "#/components/parameters/PageParam"
        - $ref: "#/components/parameters/SizeParam"
        # same filters as GET
        - $ref: "#/components/parameters/SortParam"
        - $ref: "#/components/parameters/SearchParam"
        - $ref: "#/components/parameters/CursorParam"
        - $ref: "#/components/parameters/FieldsParam"
        - $ref: "#/components/parameters/IfNoneMatchHeader"
      responses:
        "200":
          $ref: "schemas/widgets/responses/widgets-head.yaml"
        "304":
          $ref: "schemas/widgets/responses/not-modified.yaml"
        "400":
          $ref: "schemas/common/responses/errors/bad-request.yaml"
        "401":
          $ref: "schemas/common/responses/errors/unauthorized.yaml"
        "429":
          $ref: "schemas/common/responses/errors/rate-limit.yaml"
        "500":
          $ref: "schemas/common/responses/errors/server-error.yaml"
        "503":
          $ref: "schemas/common/responses/errors/service-unavailable.yaml"

    options:
      summary: Get allowed methods for widgets collection
      description: |
        Returns the HTTP methods allowed for the widgets collection.
        Used for CORS preflight requests and capability discovery.
      operationId: optionsWidgets
      tags:
        - Widgets
      security: []
      responses:
        "204":
          $ref: "schemas/widgets/responses/widgets-options.yaml"
        "400":
          $ref: "schemas/common/responses/errors/bad-request.yaml"

  /widgets/{widgetId}:
    parameters:
      - $ref: "#/components/parameters/WidgetIdParam"
      - $ref: "#/components/parameters/ApiVersionHeader"
      - $ref: "#/components/parameters/RequestIdHeader"
      - $ref: "#/components/parameters/TraceparentHeader"
      - $ref: "#/components/parameters/TracestateHeader"
      - $ref: "#/components/parameters/CorrelationIdHeader"
      - $ref: "#/components/parameters/SignatureInputHeader"
      - $ref: "#/components/parameters/SignatureHeader"
      - $ref: "#/components/parameters/AcceptSignatureHeader"
      - $ref: "#/components/parameters/WantContentDigestHeader"

    get:
      summary: Get a widget by ID
      description: Retrieves a single widget by its unique identifier.
      operationId: getWidget
      tags:
        - Widgets
      security:
        - PasetoAuth: []
      parameters:
        - $ref: "#/components/parameters/FieldsParam"
        - $ref: "#/components/parameters/IfNoneMatchHeader"
        - $ref: "#/components/parameters/AcceptEncodingHeader"
      responses:
        "200":
          $ref: "schemas/widgets/responses/widget-retrieved.yaml"
        "304":
          $ref: "schemas/widgets/responses/not-modified.yaml"
        "400":
          $ref: "schemas/common/responses/errors/bad-request.yaml"
        "401":
          $ref: "schemas/common/responses/errors/unauthorized.yaml"
        "404":
          $ref: "schemas/common/responses/errors/not-found.yaml"
        "406":
          $ref: "schemas/common/responses/errors/not-acceptable.yaml"
        "429":
          $ref: "schemas/common/responses/errors/rate-limit.yaml"
        "500":
          $ref: "schemas/common/responses/errors/server-error.yaml"
        "503":
          $ref: "schemas/common/responses/errors/service-unavailable.yaml"

    put:
      summary: Fully update a widget
      description: |
        Fully updates an existing widget. All fields must be provided.

        **Business Rules:**
        - Creation time cannot be updated (will be ignored if provided)
        - <resource-specific immutability rules>
      operationId: updateWidget
      tags:
        - Widgets
      security:
        - PasetoAuth: []
      parameters:
        - $ref: "#/components/parameters/IfMatchHeader"
        - $ref: "#/components/parameters/ContentDigestHeader"
      requestBody:
        $ref: "schemas/widgets/requests/update-widget.yaml"
      responses:
        "200":
          $ref: "schemas/widgets/responses/widget-updated.yaml"
        "400":
          $ref: "schemas/common/responses/errors/bad-request.yaml"
        "401":
          $ref: "schemas/common/responses/errors/unauthorized.yaml"
        "404":
          $ref: "schemas/common/responses/errors/not-found.yaml"
        "406":
          $ref: "schemas/common/responses/errors/not-acceptable.yaml"
        "409":
          $ref: "schemas/common/responses/errors/conflict.yaml"
        "412":
          $ref: "schemas/common/responses/errors/precondition-failed.yaml"
        "413":
          $ref: "schemas/common/responses/errors/content-too-large.yaml"
        "415":
          $ref: "schemas/common/responses/errors/unsupported-media-type.yaml"
        "422":
          $ref: "schemas/common/responses/errors/unprocessable-entity.yaml"
        "429":
          $ref: "schemas/common/responses/errors/rate-limit.yaml"
        "500":
          $ref: "schemas/common/responses/errors/server-error.yaml"
        "503":
          $ref: "schemas/common/responses/errors/service-unavailable.yaml"
        # Resources with concurrent writers: set IfMatchHeader required: true on this op and add
        # "428": { $ref: "schemas/common/responses/errors/precondition-required.yaml" }

    patch:
      summary: Partially update a widget
      description: |
        Partially updates an existing widget. Only provided fields will be updated.

        **Business Rules:**
        - <resource-specific immutability rules>
      operationId: patchWidget
      tags:
        - Widgets
      security:
        - PasetoAuth: []
      parameters:
        - $ref: "#/components/parameters/IfMatchHeader"
        - $ref: "#/components/parameters/ContentDigestHeader"
      requestBody:
        $ref: "schemas/widgets/requests/patch-widget.yaml"
      responses:
        "200":
          $ref: "schemas/widgets/responses/widget-updated.yaml"
        "400":
          $ref: "schemas/common/responses/errors/bad-request.yaml"
        "401":
          $ref: "schemas/common/responses/errors/unauthorized.yaml"
        "404":
          $ref: "schemas/common/responses/errors/not-found.yaml"
        "406":
          $ref: "schemas/common/responses/errors/not-acceptable.yaml"
        "409":
          $ref: "schemas/common/responses/errors/conflict.yaml"
        "412":
          $ref: "schemas/common/responses/errors/precondition-failed.yaml"
        "413":
          $ref: "schemas/common/responses/errors/content-too-large.yaml"
        "415":
          $ref: "schemas/common/responses/errors/unsupported-media-type.yaml"
        "422":
          $ref: "schemas/common/responses/errors/unprocessable-entity.yaml"
        "429":
          $ref: "schemas/common/responses/errors/rate-limit.yaml"
        "500":
          $ref: "schemas/common/responses/errors/server-error.yaml"
        "503":
          $ref: "schemas/common/responses/errors/service-unavailable.yaml"
        # Same opt-in as put: required IfMatchHeader plus "428".

    delete:
      summary: Delete a widget
      description: |
        Deletes a widget by its unique identifier.

        **Business Rules:**
        - <state that blocks deletion, if any>
      operationId: deleteWidget
      tags:
        - Widgets
      security:
        - PasetoAuth: []
      parameters:
        - $ref: "#/components/parameters/IfMatchHeader"
      responses:
        "204":
          $ref: "schemas/widgets/responses/widget-deleted.yaml"
        "400":
          $ref: "schemas/common/responses/errors/bad-request.yaml"
        "401":
          $ref: "schemas/common/responses/errors/unauthorized.yaml"
        "404":
          $ref: "schemas/common/responses/errors/not-found.yaml"
        "409":
          $ref: "schemas/common/responses/errors/conflict.yaml"
        "412":
          $ref: "schemas/common/responses/errors/precondition-failed.yaml"
        "429":
          $ref: "schemas/common/responses/errors/rate-limit.yaml"
        "500":
          $ref: "schemas/common/responses/errors/server-error.yaml"
        "503":
          $ref: "schemas/common/responses/errors/service-unavailable.yaml"

    head:
      summary: Get widget metadata
      description: |
        Returns headers only for a single widget (no response body).
        Useful for checking if a widget exists or validating cached data via ETag.
      operationId: headWidget
      tags:
        - Widgets
      security:
        - PasetoAuth: []
      parameters:
        - $ref: "#/components/parameters/IfNoneMatchHeader"
      responses:
        "200":
          $ref: "schemas/widgets/responses/widget-head.yaml"
        "304":
          $ref: "schemas/widgets/responses/not-modified.yaml"
        "400":
          $ref: "schemas/common/responses/errors/bad-request.yaml"
        "401":
          $ref: "schemas/common/responses/errors/unauthorized.yaml"
        "404":
          $ref: "schemas/common/responses/errors/not-found.yaml"
        "429":
          $ref: "schemas/common/responses/errors/rate-limit.yaml"
        "500":
          $ref: "schemas/common/responses/errors/server-error.yaml"
        "503":
          $ref: "schemas/common/responses/errors/service-unavailable.yaml"

    options:
      summary: Get allowed methods for widget resource
      description: |
        Returns the HTTP methods allowed for this widget resource.
        Used for CORS preflight requests and capability discovery.
      operationId: optionsWidget
      tags:
        - Widgets
      security: []
      responses:
        "204":
          $ref: "schemas/widgets/responses/widget-options.yaml"
        "400":
          $ref: "schemas/common/responses/errors/bad-request.yaml"
```

Opt-in responses, not in the skeleton: `"403"` (`schemas/common/responses/errors/forbidden.yaml`) on an operation restricted by scope, role, or ownership; `"428"` on `put` and `patch` of a resource with concurrent writers.

Add to `components/parameters`:

```yaml
    WidgetIdParam:
      name: widgetId
      in: path
      required: true
      description: The unique identifier of the widget (UUID v7)
      schema:
        type: string
        format: uuid
      example: "019234a5-6b7c-7d9e-8f12-34567890abcd"
```

Add to `tags:` (internal-only tags also get `x-internal: true`, and so do the path items that use them):

```yaml
  - name: Widgets
    description: Widget management operations
```

## 2. `schemas/widgets/requests/create-widget.yaml`

```yaml
description: Request body for creating a new widget
required: true
content:
  application/json:
    schema:
      $ref: "entities/widget.yaml#/CreateWidget"
    examples:
      widget_basic:
        $ref: "../examples/create-request.yaml#/widget_basic"
```

`update-widget.yaml` is identical apart from `description`, schema name `UpdateWidget`, and the example `widget_full` from `../examples/update-request.yaml`.

`patch-widget.yaml` is a JSON Merge Patch document (RFC 7396), so its only media type differs:

```yaml
description: Request body for partially updating a widget (PATCH, RFC 7396 JSON Merge Patch)
required: true
content:
  application/merge-patch+json:
    schema:
      $ref: "entities/widget.yaml#/PatchWidget"
    examples:
      widget_patch_status:
        $ref: "../examples/update-request.yaml#/widget_patch_status"
```

## 3. `schemas/widgets/requests/entities/widget.yaml`

```yaml
CreateWidget:
  type: object
  description: |
    Request body for creating a new widget.
    `status` defaults to "active" when omitted. Unknown properties are rejected with 422.
  additionalProperties: false
  required:
    - name
  properties:
    name:
      type: string
      description: The name of the widget
      minLength: 1
      maxLength: 255
      example: "Widget A"
    status:
      $ref: "../../../common/entities/widget-status.yaml#/WidgetStatus"   # no siblings next to $ref; defaults live in the parent description

UpdateWidget:
  type: object
  description: Request body for fully updating a widget (PUT). All fields are required; unknown properties are rejected with 422.
  additionalProperties: false
  required:
    - name
    - status
  properties:
    name:
      type: string
      description: The name of the widget
      minLength: 1
      maxLength: 255
      example: "Widget A"
    status:
      $ref: "../../../common/entities/widget-status.yaml#/WidgetStatus"

PatchWidget:
  type: object
  description: |
    JSON Merge Patch document (RFC 7396). Only provided fields change.
    `null` on a required field is rejected with 422 (`invalid_type`). Unknown properties are rejected with 422.
  additionalProperties: false
  minProperties: 1
  properties:
    name:
      type: string
      description: The name of the widget
      minLength: 1
      maxLength: 255
      example: "Widget A"
    status:
      $ref: "../../../common/entities/widget-status.yaml#/WidgetStatus"
```

The three schemas carry the same properties; only `required` differs. A field with an immutability rule gets a `**Note:**` line in its `description`.

## 4. `schemas/widgets/responses/widget-created.yaml`

```yaml
description: Widget created successfully
headers:
  API-Version:
    $ref: "../../common/responses/headers/headers.yaml#/ApiVersionHeader"
  Location:
    $ref: "../../common/responses/headers/headers.yaml#/LocationHeader"
  Idempotent-Replayed:
    $ref: "../../common/responses/headers/headers.yaml#/IdempotentReplayedHeader"
  Request-Id:
    $ref: "../../common/responses/headers/headers.yaml#/RequestIdHeader"
  Correlation-Id:
    $ref: "../../common/responses/headers/headers.yaml#/CorrelationIdHeader"
  RateLimit-Limit:
    $ref: "../../common/responses/headers/headers.yaml#/RateLimitLimitHeader"
  RateLimit-Remaining:
    $ref: "../../common/responses/headers/headers.yaml#/RateLimitRemainingHeader"
  RateLimit-Reset:
    $ref: "../../common/responses/headers/headers.yaml#/RateLimitResetHeader"
  RateLimit-Policy:
    $ref: "../../common/responses/headers/headers.yaml#/RateLimitPolicyHeader"
  Content-Encoding:
    $ref: "../../common/responses/headers/headers.yaml#/ContentEncodingHeader"
  Vary:
    $ref: "../../common/responses/headers/headers.yaml#/VaryHeader"
  Content-Digest:
    $ref: "../../common/responses/headers/headers.yaml#/ContentDigestResponseHeader"
  Signature-Input:
    $ref: "../../common/responses/headers/headers.yaml#/SignatureInputResponseHeader"
  Signature:
    $ref: "../../common/responses/headers/headers.yaml#/SignatureResponseHeader"
  traceparent:
    $ref: "../../common/responses/headers/headers.yaml#/TraceparentResponseHeader"
  tracestate:
    $ref: "../../common/responses/headers/headers.yaml#/TracestateResponseHeader"
content:
  application/json:
    schema:
      $ref: "entities/widget.yaml#/WidgetEnvelope"
    examples:
      widget_created:
        $ref: "../examples/widget.yaml#/widget_created"
```

The other response files follow their rows in the header-set table in headers.md. Starting from the file above:
For `widget-retrieved.yaml` drop `Location` and `Idempotent-Replayed`, add `ETag`, `Cache-Control`, `Cache-Status`, `Last-Modified`.
For `widget-updated.yaml` (PUT and PATCH 200) drop `Location` and `Idempotent-Replayed`, add `ETag` and `Content-Location`.
For `widgets-list.yaml` drop `Location` and `Idempotent-Replayed`, add `ETag`, `Cache-Control`, `Cache-Status`, schema `entities/widgets-list.yaml#/WidgetsListEnvelope`, example `../examples/widgets-list.yaml#/widgets_list`.
For `widget-deleted.yaml` keep the TRACE and RATE sets only, no `content`.
`not-modified.yaml`, `*-head.yaml`, and `*-options.yaml` have no body: declare exactly the headers of their rows (OPTIONS: `Allow`, `Accept-Patch` on the item path only, the CORS set, `Vary`). When the project has a reference resource, copy them from `schemas/<reference_resource>/responses/` and rename.

## 5. `schemas/widgets/responses/entities/widget.yaml`

```yaml
WidgetEnvelope:
  type: object
  description: Response envelope containing a single widget with metadata
  required:
    - data
    - meta
  properties:
    data:
      $ref: "#/Widget"
    meta:
      $ref: "../../../common/responses/entities/meta.yaml#/Meta"

Widget:
  type: object
  description: A widget resource
  required:
    - id
    - name
    - status
    - createdAt
    - updatedAt
    - links
  properties:
    id:
      type: string
      format: uuid
      description: Unique identifier for the widget (UUID v7)
      example: "019234a5-6b7c-7d9e-8f12-34567890abcd"
    name:
      type: string
      description: The name of the widget
      minLength: 1
      maxLength: 255
      example: "Widget A"
    status:
      $ref: "../../../common/entities/widget-status.yaml#/WidgetStatus"
    createdAt:
      type: string
      format: date-time
      description: Timestamp when the widget was created (immutable)
      example: "2024-01-15T10:30:00Z"
    updatedAt:
      type: string
      format: date-time
      description: Timestamp when the widget was last updated
      example: "2024-01-15T14:45:00Z"
    links:
      $ref: "#/WidgetLinks"

WidgetLinks:
  type: object
  description: HATEOAS links for widget navigation
  required:
    - self
  properties:
    self:
      type: string
      format: uri-reference
      description: Link to this widget resource, base path included
      example: "/v1/widgets/019234a5-6b7c-7d9e-8f12-34567890abcd"
```

## 6. `schemas/widgets/examples/widget.yaml`

Keys `widget_created`, `widget`, `widget_updated`, `widget_patched`. Each is `summary` + `value` with the full envelope:

```yaml
widget_created:
  summary: Newly created widget
  value:
    data:
      id: "019234a5-6b7c-7d9e-8f12-34567890abcd"
      name: "Widget A"
      status: "active"
      createdAt: "2024-01-15T10:30:00Z"
      updatedAt: "2024-01-15T10:30:00Z"
      links:
        self: "/v1/widgets/019234a5-6b7c-7d9e-8f12-34567890abcd"
    meta:
      requestId: "550e8400-e29b-41d4-a716-446655440000"
      traceId: "0af7651916cd43dd8448eb211c80319c"
      apiVersion: "v1"
```

Examples must satisfy `required` and enum constraints or `redocly lint` fails (`no-invalid-schema-examples`, `no-invalid-media-type-examples`).

## 7. Shared enum `schemas/common/entities/widget-status.yaml`

```yaml
WidgetStatus:
  type: string
  description: The current status of the widget
  enum:
    - active
    - retired
  example: "active"
  x-enumDescriptions:
    active: Widget is in service
    retired: Widget is retired and read-only
```

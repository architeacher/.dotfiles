# Toolchain integration (suggest after a spec change; apply only when the user confirms)

## Contents

- Any project: lint and bundle (Make + Docker)
- Go projects: regenerate server stubs from the bundles
- Other stacks

After the OpenAPI files are done, check whether the project automates lint, bundle, and (if it generates
code from the bundle) stub generation. If it does not, propose the snippets below to the user. Do not
add them unasked. Adjust the service path, the module path, and the logging helpers to the project;
`<api>` and `<version>` come from the profile.

Suggested wording: "The spec is updated and lint-clean. The project has no lint/bundle targets for it.
Want me to add `lint-api` and `bundle-api` (pinned redocly CLI in Docker), and for the Go service a
`generate-api` target with oapi-codegen configs?"

## Any project: lint and bundle (Make + Docker)

Recipes are tab-indented. `printMessage` and `INFO_CLR` are the project's Makefile logging helpers; use
`echo` when they do not exist. Both targets address the spec through the api aliases in `.redocly.yaml`.
Its `root` and `output` paths are relative to the config file, so the mount point is free to choose and
the same commands run on a host.

```makefile
# build/mk/app.mk
REDOCLY_VERSION ?= 2.78.0

.PHONY: lint-api
lint-api: ## 🔍 Lint and validate OpenAPI specification.
	$(call printMessage,"🔍  Linting OpenAPI specification",${INFO_CLR})
	docker run --rm \
		-v "${CURDIR}/docs/contracts/openapi":/spec \
		-w "/spec" \
		"redocly/cli:${REDOCLY_VERSION}" lint main \
		--config .redocly.yaml

.PHONY: bundle-api
bundle-api: lint-api ## Bundle modular OpenAPI specs into the public and the internal file.
	$(call printMessage,"🤖  Generating API specs",${INFO_CLR})
	docker run --rm \
		-v "${CURDIR}/docs/contracts/openapi":/spec \
		-w "/spec" \
		"redocly/cli:${REDOCLY_VERSION}" bundle \
		--config .redocly.yaml \
		--component-renaming-conflicts-severity error
```

Notes:
- Pin `REDOCLY_VERSION`; never `latest`. Bump it deliberately and re-run lint, because new rule versions can add findings.
- `bundle-api` depends on `lint-api`, so a bundle is never produced from an invalid spec.
- `bundle` without a file argument writes every `output` in `.redocly.yaml`: `public/swagger-pact.json` (api `main`, `x-internal` content removed) and `internal/swagger.json` (api `internal`, everything).
- `--component-renaming-conflicts-severity error` fails the bundle on a duplicate example key instead of renaming it to `created-2`.
- Commit both bundles; downstream generators and contract tests read the bundles, not the modular files.

## Go projects: regenerate server stubs from the bundles

```makefile
# build/mk/app.mk
# The service's tools module; adjust the path.
API_TOOLS_DIR ?= services/svc-api-gateway/internal/tools

.PHONY: generate-api
generate-api: bundle-api ## 🤖 Regenerate HTTP server stubs from bundled OpenAPI spec.
	cd "${API_TOOLS_DIR}" && go generate .
```

The generator lives in a dedicated tools module, following the Go tools-module pattern
(https://www.jvt.me/posts/2024/09/30/go-tools-module/): its own `go.mod` declares build tools with the
Go 1.24+ `tool` directive, so generator dependencies never enter the service module's graph. The
`//go:generate go tool …` lines run exactly the version pinned there, and `vendor/` makes generation
reproducible offline. The `tool` directive replaces the older `tools.go` pattern, so no build tag is
needed, neither in the files nor on the `go generate` call.

```
services/<service>/internal/tools/
├── generate.go
├── go.mod
├── go.sum
└── vendor
```

```go.mod
// tools/go.mod
module <module>/services/<service>/internal/tools

go 1.27

toolchain go1.27.4

require (
    ... // indirect
)

tool github.com/oapi-codegen/oapi-codegen/v2/cmd/oapi-codegen
```

Maintain it from inside the tools directory: `go get -tool github.com/oapi-codegen/oapi-codegen/v2/cmd/oapi-codegen@<version>`,
then `go mod tidy` and `go mod vendor`. Bumping the generator is a reviewed change, because its output lands in the service.

```go
// Package tools pins the code generators this service runs through go generate.
package tools

//go:generate go tool github.com/oapi-codegen/oapi-codegen/v2/cmd/oapi-codegen --config=../../../../build/oapi/codegen-public.yaml ../../../../docs/contracts/openapi/<api>/<version>/public/swagger-pact.json
//go:generate go tool github.com/oapi-codegen/oapi-codegen/v2/cmd/oapi-codegen --config=../../../../build/oapi/codegen-admin.yaml ../../../../docs/contracts/openapi/<api>/<version>/internal/swagger.json
```

Generator configs, one per server:

```
build/oapi/
├── codegen-admin.yaml
└── codegen-public.yaml
```

```yaml
# build/oapi/codegen-public.yaml
package: public
generate:
  chi-server: true
  strict-server: true
  models: true
  embedded-spec: true
output: ../../internal/adapters/inbound/http/handlers/public/http_server_gen.go
output-options:
  skip-prune: true
  nullable-type: true
  include-tags:
    - Widgets
    - System
```

```yaml
# build/oapi/codegen-admin.yaml
package: admin
generate:
  chi-server: true
  strict-server: true
  models: true
  embedded-spec: true
output: ../../internal/adapters/inbound/http/handlers/admin/http_server_gen.go
output-options:
  skip-prune: true
  nullable-type: true
  include-tags:
    - Admin
    - System
```

Notes for the user when proposing this:
- The public generator reads `public/swagger-pact.json`, so nothing internal reaches the public server or its embedded spec. The admin generator reads `internal/swagger.json`: `Admin` operations exist only there.
- `include-tags` is what splits the public and admin servers. A new tag in `specs.yaml` must also be added here, or its operations are silently absent from the generated server.
- `nullable-type: true` pairs with OpenAPI 3.0 `nullable: true`; do not switch the spec to 3.1 null unions.
- `strict-server: true` turns every declared response into a typed return value. Spec changes that add status codes, rename schemas, or change a request media type make the handlers fail to compile until they are updated. Regenerate together with the handler change, never alone.
- `embedded-spec: true` compiles the spec into the service. It validates requests only when a validator middleware is wired to it; either way a spec edit reaches the running service only after regeneration and redeploy.

## Other stacks

Add the equivalent generator target depending on `bundle-api` (for example `openapi-generator-cli`, `orval`,
`openapi-typescript`), and keep the same rule: regenerate together with the code that consumes the output.

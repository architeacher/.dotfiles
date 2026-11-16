#!/usr/bin/env bats
# Run: bats tests/rest_api_openapi.bats
# Needs: bats-core, rg. The lint and bundle tests also need a redocly CLI (`redocly` on PATH, or
# REDOCLY_BIN); without one they are skipped. Checked with @redocly/cli 2.78.0.
#
# The contract under test is built from the skill itself: the YAML blocks of its endpoint template
# are laid over the scaffold in fixtures/rest-api-openapi, so template and ruleset cannot drift apart.

setup() {
    SKILL="${BATS_TEST_DIRNAME}/../harness/skills/rest-api-openapi"
    TEMPLATE="${SKILL}/references/endpoint-template.md"
    FIXTURE="${BATS_TEST_DIRNAME}/fixtures/rest-api-openapi"
    CONTRACTS="${BATS_TEST_TMPDIR}/contracts"
    SPEC_DIR="${CONTRACTS}/acme/v1"
    SPEC="${SPEC_DIR}/specs.yaml"

    DESCRIPTION_LIMIT=1024
    BODY_LINE_LIMIT=500
    CONTENTS_THRESHOLD=100
}

# usage: yaml_block <markdown file> <prefix of the block's first line>
# Prints the fenced yaml block that starts with the prefix; fails when there is none.
yaml_block() {
    awk -v prefix="${2}" '
        /^```yaml$/ { inside = 1; first = 1; keep = 0; next }
        /^```$/ {
            if (inside && keep) { found = 1; exit }
            inside = 0
            next
        }
        inside && first { first = 0; keep = (index($0, prefix) == 1) }
        inside && keep { print }
        END { exit found ? 0 : 1 }
    ' "${1}"
}

# usage: replace_first <file> <old> <new>
# Literal replacement of the first occurrence; fails when the text is absent.
replace_first() {
    local file="${1}"

    awk -v old="${2}" -v new="${3}" '
        !done && (at = index($0, old)) {
            $0 = substr($0, 1, at - 1) new substr($0, at + length(old))
            done = 1
        }
        { print }
        END { exit done ? 0 : 1 }
    ' "${file}" > "${file}.new"
    mv "${file}.new" "${file}"
}

# Prints "<matrix column>|<code>" for every required cell of the status matrix.
matrix_codes() {
    awk -F'|' '
        /^## Matrix$/ { inside = 1 }
        /^## Semantics$/ { inside = 0 }
        !inside { next }
        /^\| Code \|/ {
            for (column = 3; column <= 11; column++) {
                name[column] = $column
                gsub(/^ +| +$/, "", name[column])
            }
            next
        }
        /^\| [0-9][0-9][0-9] \|/ {
            code = $2
            gsub(/ /, "", code)
            for (column = 3; column <= 11; column++) {
                cell = $column
                gsub(/ /, "", cell)
                if (cell == "x") print name[column] "|" code
            }
        }
    ' "${SKILL}/references/status-codes.md"
}

# Prints "<matrix column>|<code>" for every response the template skeleton declares.
template_codes() {
    yaml_block "${TEMPLATE}" "  /widgets:" | awk '
        /^  \/widgets:$/ { kind = "/r" }
        /^  \/widgets\/[{]widgetId[}]:$/ { kind = "/r/{id}" }
        /^    (get|post|put|patch|delete|head|options):$/ {
            method = toupper($1)
            sub(/:$/, "", method)
        }
        /^        "[0-9][0-9][0-9]":$/ {
            code = $1
            gsub(/[":]/, "", code)
            print (method == "OPTIONS" ? "OPTIONS" : method " " kind) "|" code
        }
    '
}

# One shared problem response per status. The skill fixes the file names and the status-specific
# headers; the rest is filler.
write_error_files() {
    local errors_dir="${SPEC_DIR}/schemas/common/responses/errors" \
          cases=(
              "bad-request|"
              "unauthorized|WWW-Authenticate:WWWAuthenticateHeader"
              "not-found|"
              "not-acceptable|"
              "conflict|Retry-After:RetryAfterHeader"
              "precondition-failed|ETag:ETagHeader"
              "content-too-large|"
              "unsupported-media-type|"
              "unprocessable-entity|"
              "rate-limit|Retry-After:RetryAfterHeader"
              "server-error|"
              "service-unavailable|Retry-After:RetryAfterHeader"
          ) \
          entry \
          name \
          extra \
          header

    for entry in "${cases[@]}"; do
        IFS='|' read -r name extra <<< "${entry}"

        {
            printf 'description: %s (RFC 9457 problem)\nheaders:\n' "${name}"
            for header in "API-Version:ApiVersionHeader" "Request-Id:RequestIdHeader" \
                "Cache-Control:CacheControlNoStoreHeader" "${extra}"; do
                [[ -n "${header}" ]] || continue
                printf "  %s:\n    \$ref: \"../headers/headers.yaml#/%s\"\n" "${header%%:*}" "${header##*:}"
            done
            cat <<EOF
content:
  application/problem+json:
    schema:
      \$ref: "entities/problem.yaml#/Problem"
    examples:
      ${name//-/_}_generic:
        summary: ${name}
        value:
          requestId: "550e8400-e29b-41d4-a716-446655440000"
          timestamp: "2024-01-15T10:30:00Z"
          type: "https://docs.example.com/problems/${name}"
          title: "${name}"
          status: 400
          detail: "Request failed."
EOF
        } > "${errors_dir}/${name}.yaml"
    done
}

# The responses the template derives in prose. A body response needs its schema and example here,
# the others only a description.
write_response_stubs() {
    local responses_dir="${SPEC_DIR}/schemas/widgets/responses" \
          cases=(
              "widget-retrieved|Widget retrieved|widget.yaml#/WidgetEnvelope|widget.yaml#/widget_created"
              "widget-updated|Widget updated|widget.yaml#/WidgetEnvelope|widget.yaml#/widget_created"
              "widgets-list|Widgets listed|widgets-list.yaml#/WidgetsListEnvelope|widgets-list.yaml#/widgets_list"
              "widget-deleted|Widget deleted||"
              "widget-head|Widget metadata||"
              "widgets-head|Widgets metadata||"
              "widget-options|Allowed methods||"
              "widgets-options|Allowed methods||"
              "not-modified|Not modified||"
          ) \
          entry \
          name \
          description \
          schema \
          example

    for entry in "${cases[@]}"; do
        IFS='|' read -r name description schema example <<< "${entry}"

        {
            printf 'description: %s\n' "${description}"
            [[ -z "${schema}" ]] || printf \
                "content:\n  application/json:\n    schema:\n      \$ref: \"entities/%s\"\n    examples:\n      %s:\n        \$ref: \"../examples/%s\"\n" \
                "${schema}" "${example##*#/}" "${example}"
        } > "${responses_dir}/${name}.yaml"
    done
}

# Stubs every response header the laid-out files reference: the skill names them, a project defines them.
write_header_stubs() {
    local headers_dir="${SPEC_DIR}/schemas/common/responses/headers" \
          key

    mkdir -p "${headers_dir}"
    rg --no-filename --only-matching 'headers\.yaml#/[A-Za-z]+' "${SPEC_DIR}/schemas" \
        | sed 's|.*#/||' \
        | sort -u \
        | while read -r key; do
            printf '%s:\n  description: %s\n  schema:\n    type: string\n  example: value\n' "${key}" "${key}"
        done > "${headers_dir}/headers.yaml"
}

# Stubs every parameter the template references and leaves to the project.
parameter_stubs() {
    local key \
          name \
          location

    rg --only-matching '#/components/parameters/[A-Za-z]+' "${TEMPLATE}" \
        | sed 's|.*/||' \
        | sort -u \
        | while read -r key; do
            [[ "${key}" != "WidgetIdParam" ]] || continue

            if [[ "${key}" == *Header ]]; then
                location="header"
                name="$(sed -E 's/Header$//; s/([a-z])([A-Z])/\1-\2/g' <<< "${key}")"
            else
                location="query"
                name="$(sed -E 's/Param$//' <<< "${key}" | tr '[:upper:]' '[:lower:]')"
            fi

            printf '    %s:\n      name: %s\n      in: %s\n      required: false\n      description: %s\n      schema:\n        type: string\n      example: value\n' \
                "${key}" "${name}" "${location}" "${key}"
        done
}

# Copies the scaffold root, replacing each marker line with the matching template block.
fill_spec() {
    local line

    while IFS= read -r line; do
        case "${line}" in
            "# <template: tags>") yaml_block "${TEMPLATE}" "  - name: Widgets" ;;
            "# <template: paths>") yaml_block "${TEMPLATE}" "  /widgets:" ;;
            "# <template: parameters>")
                yaml_block "${TEMPLATE}" "    WidgetIdParam:"
                parameter_stubs
                ;;
            *) printf '%s\n' "${line}" ;;
        esac
    done < "${FIXTURE}/specs.yaml" > "${SPEC}"
}

# Builds docs/contracts/openapi the way a project would: scaffold, template blocks, skill assets.
lay_out_contracts() {
    local schemas="${SPEC_DIR}/schemas" \
          cases=(
              "description: Request body for creating|widgets/requests/create-widget.yaml"
              "description: Request body for partially|widgets/requests/patch-widget.yaml"
              "CreateWidget:|widgets/requests/entities/widget.yaml"
              "description: Widget created|widgets/responses/widget-created.yaml"
              "WidgetEnvelope:|widgets/responses/entities/widget.yaml"
              "widget_created:|widgets/examples/widget.yaml"
              "WidgetStatus:|common/entities/widget-status.yaml"
          ) \
          entry \
          prefix \
          target

    rm -rf "${CONTRACTS}"
    mkdir -p "${SPEC_DIR}"
    cp -R "${FIXTURE}/schemas" "${schemas}"

    for entry in "${cases[@]}"; do
        IFS='|' read -r prefix target <<< "${entry}"

        mkdir -p "${schemas}/${target%/*}"
        yaml_block "${TEMPLATE}" "${prefix}" > "${schemas}/${target}"
    done

    yaml_block "${SKILL}/references/pagination-filtering.md" "WidgetsListEnvelope:" \
        > "${schemas}/widgets/responses/entities/widgets-list.yaml"

    # The template: "identical apart from description, schema name, and the example".
    sed -e 's/creating a new widget/fully updating a widget/' \
        -e 's/CreateWidget/UpdateWidget/' \
        -e 's/widget_basic/widget_full/g' \
        -e 's/create-request/update-request/' \
        "${schemas}/widgets/requests/create-widget.yaml" > "${schemas}/widgets/requests/update-widget.yaml"

    write_response_stubs
    write_error_files
    write_header_stubs
    fill_spec

    cp "${SKILL}/assets/rest-api-ruleset.yaml" "${CONTRACTS}/rest-api-ruleset.yaml"
    sed -e 's|<api>|acme|g' -e 's|<version>|v1|g' "${SKILL}/assets/redocly.yaml" > "${CONTRACTS}/.redocly.yaml"
}

# Finds the redocly CLI, or skips the test: the structural tests do not need it.
need_redocly() {
    REDOCLY="${REDOCLY_BIN:-}"
    [[ -n "${REDOCLY}" ]] || REDOCLY="$(command -v redocly || true)"
    [[ -n "${REDOCLY}" ]] || skip "no redocly CLI: install @redocly/cli or set REDOCLY_BIN"
}

# usage: run redocly_contracts <redocly arguments>
# Runs redocly from the contracts directory, as the skill's workflow does. Call it through `run`: its
# subshell keeps the cd away from the test, which removes that directory between layouts.
redocly_contracts() {
    cd "${CONTRACTS}" || return 1
    env REDOCLY_TELEMETRY=off REDOCLY_SUPPRESS_UPDATE_NOTICE=true NO_COLOR=1 "${REDOCLY}" "$@"
}

@test "frontmatter: name matches the directory, license and metadata are set" {
    local cases=(
        "^name: rest-api-openapi$"
        "^license: MIT$"
        "^  tags: \".+\"$"
        "^  category: \".+\"$"
    ) \
        pattern

    for pattern in "${cases[@]}"; do
        rg --quiet "${pattern}" "${SKILL}/SKILL.md" || { echo "missing: ${pattern}"; return 1; }
    done
}

@test "frontmatter: description fits the limit and is written in the third person" {
    local description

    description="$(sed -n "s/^description: '\(.*\)'$/\1/p" "${SKILL}/SKILL.md")"

    [ -n "${description}" ]
    [ "${#description}" -le "${DESCRIPTION_LIMIT}" ]
    [[ "${description}" == Designs* ]]
}

@test "body: stays under the line limit" {
    local lines

    lines="$(wc -l < "${SKILL}/SKILL.md" | tr -d ' ')"

    [ "${lines}" -lt "${BODY_LINE_LIMIT}" ]
}

@test "references: every link in SKILL.md resolves, and every reference file is linked" {
    local link \
          reference

    while read -r link; do
        [ -f "${SKILL}/${link}" ] || { echo "dead link: ${link}"; return 1; }
    done < <(rg --only-matching '\]\((references|assets)/[^)]+\)' "${SKILL}/SKILL.md" | sed 's/^](//; s/)$//' | sort -u)

    for reference in "${SKILL}"/references/*.md; do
        rg --quiet --fixed-strings "(references/${reference##*/})" "${SKILL}/SKILL.md" \
            || { echo "not linked: ${reference##*/}"; return 1; }
    done
}

@test "references: a file over the threshold carries a contents list" {
    local reference \
          lines

    for reference in "${SKILL}"/references/*.md; do
        lines="$(wc -l < "${reference}" | tr -d ' ')"
        [ "${lines}" -gt "${CONTENTS_THRESHOLD}" ] || continue

        rg --quiet '^## Contents$' "${reference}" \
            || { echo "no contents list: ${reference##*/} (${lines} lines)"; return 1; }
    done
}

@test "skill: names no single project and leaves no open marker" {
    local cases=(
        "devices/v1"
        "docs.devices.dev"
        ".claude/skills/rest-api-openapi"
        "feature-rest-standards-alignment"
        "TODO(human)"
    ) \
        token

    for token in "${cases[@]}"; do
        run rg --hidden --files-with-matches --fixed-strings "${token}" "${SKILL}"
        [ "${status}" -eq 1 ] || { printf 'found %s in:\n%s\n' "${token}" "${output}"; return 1; }
    done
}

@test "assets: the ruleset holds rules only, the project config extends it and names both apis" {
    run rg --quiet '^apis:' "${SKILL}/assets/rest-api-ruleset.yaml"
    [ "${status}" -eq 1 ]

    rg --quiet --fixed-strings '"./rest-api-ruleset.yaml"' "${SKILL}/assets/redocly.yaml"
    rg --quiet '^  main:$' "${SKILL}/assets/redocly.yaml"
    rg --quiet '^  internal:$' "${SKILL}/assets/redocly.yaml"
}

@test "assets: the profile template carries every key the skill reads" {
    local cases=(
        api
        version
        base_path
        reference_resource
        problem_type_base
        auth_realm
        cache_name
        decisions
        implementation_status
        additions
    ) \
        key

    for key in "${cases[@]}"; do
        rg --quiet "^${key}:" "${SKILL}/assets/profile.yaml" || { echo "missing key: ${key}"; return 1; }
    done
}

@test "template: declares no header parameter OpenAPI ignores, and every example key starts with the resource" {
    run rg --quiet 'parameters/(Authorization|Accept|ContentType)Header"' "${TEMPLATE}"
    [ "${status}" -eq 1 ]

    run rg --no-line-number --after-context 1 '^ +examples:$' "${TEMPLATE}"
    [ "${status}" -eq 0 ]

    run rg --invert-match '^ +(examples|widgets?_[a-z_]+):$|^--$' <<< "${output}"
    [ "${status}" -eq 1 ] || { printf 'bare example key:\n%s\n' "${output}"; return 1; }
}

@test "template: every operation declares exactly the required codes of the status matrix" {
    run diff <(matrix_codes | sort -u) <(template_codes | sort -u)

    [ "${status}" -eq 0 ] || { printf 'matrix (<) versus template (>):\n%s\n' "${output}"; return 1; }
}

@test "ruleset: the endpoint template lints clean" {
    need_redocly
    lay_out_contracts

    run redocly_contracts lint main --config .redocly.yaml --format stylish

    [ "${status}" -eq 0 ] || { echo "${output}"; return 1; }
}

@test "ruleset: each seeded violation fails on its rule" {
    need_redocly

    local cases=(
        'operationId: createWidget|operationId: CreateWidget|rule/operation-id-camel-case'
        '  /liveness:|  /v2/liveness:|rule/no-version-in-paths'
        '  - name: System|  - name: Probes|operation-tag-defined'
        '      security:|      x-security:|rule/operation-security-explicit'
        'name: Idempotency-Key|name: Authorization|rule/no-ignored-header-parameters'
        '"406":|"407":|rule/post-declares-create-outcomes'
        '"503":|"504":|rule/post-declares-create-outcomes'
    ) \
        entry \
        old \
        new \
        rule

    for entry in "${cases[@]}"; do
        IFS='|' read -r old new rule <<< "${entry}"

        lay_out_contracts
        replace_first "${SPEC}" "${old}" "${new}"
        run redocly_contracts lint main --config .redocly.yaml --format stylish

        [ "${status}" -ne 0 ] || { echo "passed with: ${old} -> ${new}"; return 1; }
        [[ "${output}" == *"${rule}"* ]] || { printf 'expected %s, got:\n%s\n' "${rule}" "${output}"; return 1; }
    done
}

@test "bundle: one call writes the public and the internal file; only the internal one holds the admin endpoint" {
    need_redocly
    lay_out_contracts

    run redocly_contracts bundle --config .redocly.yaml --component-renaming-conflicts-severity error
    [ "${status}" -eq 0 ] || { echo "${output}"; return 1; }

    run rg --quiet --fixed-strings '"/admin/cache"' "${SPEC_DIR}/public/swagger-pact.json"
    [ "${status}" -eq 1 ]
    run rg --quiet --fixed-strings '"Admin"' "${SPEC_DIR}/public/swagger-pact.json"
    [ "${status}" -eq 1 ]

    rg --quiet --fixed-strings '"/widgets/{widgetId}"' "${SPEC_DIR}/public/swagger-pact.json"
    rg --quiet --fixed-strings '"/admin/cache"' "${SPEC_DIR}/internal/swagger.json"
}

@test "bundle: a duplicate example key fails instead of being renamed" {
    need_redocly
    lay_out_contracts

    local file

    for file in "${SPEC_DIR}/schemas/widgets/requests/update-widget.yaml" \
        "${SPEC_DIR}/schemas/widgets/examples/update-request.yaml"; do
        sed 's/widget_full/widget_basic/g' "${file}" > "${file}.new"
        mv "${file}.new" "${file}"
    done

    run redocly_contracts bundle --config .redocly.yaml --component-renaming-conflicts-severity error

    [ "${status}" -ne 0 ]
    [ ! -e "${SPEC_DIR}/public/swagger-pact.json" ]
}

@test "config: a project can switch a generic rule off" {
    need_redocly
    lay_out_contracts

    replace_first "${SPEC}" '"406":' '"407":'
    printf '\nrules:\n  rule/post-declares-create-outcomes: off\n' >> "${CONTRACTS}/.redocly.yaml"

    run redocly_contracts lint main --config .redocly.yaml --format stylish

    [ "${status}" -eq 0 ] || { echo "${output}"; return 1; }
}

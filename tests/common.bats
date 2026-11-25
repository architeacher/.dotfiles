#!/usr/bin/env bats
# Run: bats tests/common.bats

setup() {
    # The path is built at run time.
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../scripts/common.sh"

    SAID="${BATS_TEST_TMPDIR}/said"
    NOTIFIED="${BATS_TEST_TMPDIR}/notified"
}

# Stands in for the say command: keeps what it is given to read.
say() {
    cat > "${SAID}"
}

# Stands in for osascript: keeps its arguments, one per line.
osascript() {
    printf '%s\n' "$@" > "${NOTIFIED}"
}

# --- notify -----------------------------------------------------------------

@test "notify: hands the texts to the script as arguments, never as its source" {
    local message='-3 "quoted" & $(id)' \
          script \
          texts

    notify "${message}" "install.sh" "at_exit callback"

    # After the end of the options: the texts as they are. Before it: the script.
    texts="$(sed '1,/^--$/d' "${NOTIFIED}")"
    script="$(sed '/^--$/,$d' "${NOTIFIED}")"

    [ "${texts}" == "${message}${LOG_NEWLINE}install.sh${LOG_NEWLINE}at_exit callback" ]
    [[ "${script}" == *"item 1 of argv"*"item 2 of argv"*"item 3 of argv"* ]]
    [[ "${script}" != *"quoted"* ]]
    [[ "${script}" != *"install.sh"* ]]
}

@test "notify: title and subtitle can be left out" {
    notify "Done"

    # Three texts follow the end of the options, the last two are empty.
    [ "$(sed '1,/^--$/d' "${NOTIFIED}" | wc -l | tr -d ' ')" -eq 3 ]
    [ "$(sed '1,/^--$/d' "${NOTIFIED}")" == "Done" ]
}

# --- speak ------------------------------------------------------------------

@test "speak: says the words of a log message: escapes are read, emoji are left out" {
    speak "\n✨ Congratulations, you can now chillax!\n😎 May the odds be in your favour."

    [ "$(< "${SAID}")" == "$(printf '\n Congratulations, you can now chillax!\n May the odds be in your favour.')" ]
}

@test "speak: silent where there is no say command" {
    is_command() { return 1; }

    run speak "hello"
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
    [ ! -e "${SAID}" ]
}

@test "speak: a say that fails does not fail the caller" {
    say() { return 1; }

    run speak "hello"
    [ "${status}" -eq 0 ]
}

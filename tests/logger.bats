#!/usr/bin/env bats
# Run: bats tests/logger.bats
# Needs: bats-core 1.5+ (run --separate-stderr).

bats_require_minimum_version 1.5.0

setup() {
    LOGGER="${BATS_TEST_DIRNAME}/../scripts/logger.sh"

    # The logger reads these when it is sourced, so every test starts from the same state.
    unset LOG_COLOR NO_COLOR LOG_PALETTE
    export COLORTERM="truecolor" TERM="xterm-256color"

    # The path is built at run time.
    # shellcheck disable=SC1090
    source "${LOGGER}"

    ESC=$'\033'
    RESET="${ESC}[0m"
}

# Recompile the styles, as sourcing the logger with this LOG_COLOR would.
# usage: color_mode <LOG_COLOR> [palette]
color_mode() {
    LOG_COLOR="${1}"
    log_set_palette "${2:-rose_pine_moon}"
}

# The line a level prints in truecolor.
# usage: colored <prefix rgb> <tag> <tag rgb> <message rgb> <message>
colored() {
    printf '%s  %s %s' \
        "${ESC}[38;2;${1}m==>${RESET}" \
        "${ESC}[1;38;2;${3}m[${2}]:${RESET}" \
        "${ESC}[38;2;${4}m${5}${RESET}"
}

# --- plain output -------------------------------------------------------------

@test "log: every level prints its tag to stderr and nothing to stdout" {
    local cases=(
        "log_emergency|EMERGENCY"
        "log_alert|ALERT"
        "log_critical|CRITICAL"
        "log_error|ERROR"
        "log_warning|WARNING"
        "log_notice|NOTICE"
        "log_info|INFO"
        "log_debug|DEBUG"
    ) \
        entry

    log_set_level "${LOG_LEVEL_DEBUG}"

    for entry in "${cases[@]}"; do
        run --separate-stderr "${entry%%|*}" "a message"
        [ "${status}" -eq 0 ]
        [ -z "${output}" ]
        [ "${stderr}" == "==>  [${entry#*|}]: a message" ]
    done
}

@test "log: drops messages less severe than the level" {
    log_set_level "${LOG_LEVEL_WARN}"

    run log_info "hidden"
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]

    run log_warning "shown"
    [ "${output}" == "==>  [WARNING]: shown" ]
}

@test "log: expands backslash escapes in the message" {
    run log_info 'first\nsecond'
    [ "${output}" == "==>  [INFO]: first"$'\n'"second" ]
}

@test "log: joins its arguments with a space" {
    run log_info "one" "two"
    [ "${output}" == "==>  [INFO]: one two" ]
}

@test "log: an unknown level prints the bare message to stdout" {
    log_set_level 99

    run --separate-stderr log 50 "raw"
    [ "${status}" -eq 0 ]
    [ "${output}" == "==> raw" ]
    [ -z "${stderr}" ]
}

@test "abort: logs the error and exits 1" {
    run abort "boom"
    [ "${status}" -eq 1 ]
    [ "${output}" == "==>  [ERROR]: boom" ]
}

# --- parse_log_level ------------------------------------------------------------

@test "parse_log_level: maps every level name to its number" {
    local cases=(
        "emergency|0"
        "alert|1"
        "critical|2"
        "error|3"
        "warning|4"
        "notice|5"
        "info|6"
        "debug|7"
    ) \
        entry

    for entry in "${cases[@]}"; do
        run parse_log_level "${entry%%|*}"
        [ "${status}" -eq 0 ]
        [ "${output}" == "${entry#*|}" ]
    done
}

@test "parse_log_level: aborts on an unknown name" {
    run parse_log_level "loud"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"Invalid log level: loud"* ]]
}

# --- color switch ---------------------------------------------------------------

@test "log_color_enabled: LOG_COLOR wins, NO_COLOR turns auto off, auto needs a terminal" {
    local cases=(
        # LOG_COLOR|NO_COLOR|stderr is a terminal|expected status ("-" is unset)
        "never|-|true|1"
        "always|-|false|0"
        "always|1|false|0"
        "auto|-|true|0"
        "auto|-|false|1"
        "auto|1|true|1"
        "auto||true|0"
        "|-|true|0"
        "-|-|true|0"
        "-|-|false|1"
        "-|1|true|1"
    ) \
        entry \
        mode \
        no_color \
        terminal \
        expected

    # Stands in for the terminal check, so the test needs no pty.
    log_stderr_is_terminal() { "${terminal}"; }

    for entry in "${cases[@]}"; do
        IFS='|' read -r mode no_color terminal expected <<< "${entry}"

        unset LOG_COLOR NO_COLOR
        [ "${mode}" == "-" ] || LOG_COLOR="${mode}"
        [ "${no_color}" == "-" ] || NO_COLOR="${no_color}"

        run log_color_enabled
        [ "${status}" -eq "${expected}" ] || {
            printf 'case: %s\n got: %s\n' "${entry}" "${status}"

            return 1
        }
    done
}

@test "log_color_enabled: auto stays off on a dumb terminal, always still colors" {
    local cases=(
        # LOG_COLOR|expected status
        "auto|1"
        "always|0"
    ) \
        entry

    log_stderr_is_terminal() { return 0; }
    TERM="dumb"

    for entry in "${cases[@]}"; do
        LOG_COLOR="${entry%%|*}"

        run log_color_enabled
        [ "${status}" -eq "${entry#*|}" ]
    done
}

@test "log_set_palette: an invalid LOG_COLOR aborts and keeps the compiled styles" {
    color_mode "always"
    LOG_COLOR="yes"

    run log_set_palette "rose_pine_moon"
    [ "${status}" -eq 1 ]
    [ "${output}" == "$(colored "224;175;255" "ERROR" "255;0;255" "230;230;250" "Invalid LOG_COLOR: yes")" ]
}

@test "logger: an invalid LOG_COLOR aborts with its value when it is sourced" {
    run env LOG_COLOR="yes" "${BASH}" -c "source '${LOGGER}'"
    [ "${status}" -eq 1 ]
    [ "${output}" == "==>  [ERROR]: Invalid LOG_COLOR: yes" ]
}

@test "log: LOG_COLOR=never prints no escape sequence on a terminal" {
    log_stderr_is_terminal() { return 0; }
    color_mode "never"

    run log_info "dir 'x' # note"
    [ "${output}" == "==>  [INFO]: dir 'x' # note" ]
}

@test "log: NO_COLOR prints no escape sequence on a terminal" {
    log_stderr_is_terminal() { return 0; }
    NO_COLOR="1"
    log_set_palette "rose_pine_moon"

    run log_info "plain"
    [ "${output}" == "==>  [INFO]: plain" ]
}

# --- theme ------------------------------------------------------------------------

@test "log: colors the prefix, the tag in bold and the message per level" {
    local cases=(
        # function|tag|prefix rgb|tag rgb|message rgb
        "log_emergency|EMERGENCY|255;0;128|128;0;0|224;222;244"
        "log_alert|ALERT|234;154;151|235;111;146|224;222;244"
        "log_critical|CRITICAL|189;147;249|196;167;231|128;152;228"
        "log_error|ERROR|224;175;255|255;0;255|230;230;250"
        "log_warning|WARNING|254;100;11|223;142;29|238;195;130"
        "log_notice|NOTICE|128;128;0|138;255;14|110;106;134"
        "log_info|INFO|64;160;43|156;207;216|62;143;176"
        "log_debug|DEBUG|59;134;193|120;203;250|62;143;176"
    ) \
        entry \
        name \
        tag \
        prefix_rgb \
        tag_rgb \
        message_rgb

    log_set_level "${LOG_LEVEL_DEBUG}"
    color_mode "always"

    for entry in "${cases[@]}"; do
        IFS='|' read -r name tag prefix_rgb tag_rgb message_rgb <<< "${entry}"

        run "${name}" "hello"
        [ "${output}" == "$(colored "${prefix_rgb}" "${tag}" "${tag_rgb}" "${message_rgb}" "hello")" ]
    done
}

@test "log: falls back to the nearest 256-color without truecolor" {
    COLORTERM=""
    color_mode "always"

    run log_info "hello"
    [ "${output}" == "${ESC}[38;5;70m==>${RESET}  ${ESC}[1;38;5;152m[INFO]:${RESET} ${ESC}[38;5;67mhello${RESET}" ]
}

@test "log_set_palette: a scheme overrides the roles it names, the default fills the rest" {
    local cases=(
        # function|tag|prefix rgb|tag rgb|message rgb
        "log_emergency|EMERGENCY|255;0;128|128;0;0|202;211;245"
        "log_info|INFO|64;160;43|139;213;202|62;143;176"
        "log_debug|DEBUG|59;134;193|120;203;250|166;218;149"
    ) \
        entry \
        name \
        tag \
        prefix_rgb \
        tag_rgb \
        message_rgb

    log_set_level "${LOG_LEVEL_DEBUG}"
    color_mode "always" "Catppuccin-Macchiato"

    for entry in "${cases[@]}"; do
        IFS='|' read -r name tag prefix_rgb tag_rgb message_rgb <<< "${entry}"

        run "${name}" "hello"
        [ "${output}" == "$(colored "${prefix_rgb}" "${tag}" "${tag_rgb}" "${message_rgb}" "hello")" ]
    done
}

@test "log_set_palette: aborts on an unknown palette" {
    run log_set_palette "solarized"
    [ "${status}" -eq 1 ]
    [ "${output}" == "==>  [ERROR]: Unknown palette: solarized" ]
}

@test "logger: reads LOG_COLOR and LOG_PALETTE when it is sourced" {
    run env LOG_COLOR="always" LOG_PALETTE="catppuccin_macchiato" COLORTERM="truecolor" \
        "${BASH}" -c "source '${LOGGER}'; log_info hello"
    [ "${output}" == "$(colored "64;160;43" "INFO" "139;213;202" "62;143;176" "hello")" ]
}

@test "logger: an unknown LOG_PALETTE aborts with its name when it is sourced" {
    run env LOG_PALETTE="bogus" "${BASH}" -c "source '${LOGGER}'"
    [ "${status}" -eq 1 ]
    [ "${output}" == "==>  [ERROR]: Unknown palette: bogus" ]
}

# --- syntax highlighting ----------------------------------------------------------

@test "log_highlight: colors strings, variables, assignments and comments, leaves prose alone" {
    local cases=(
        # text|highlighted: <s>tring, <v>ariable, <a>ssignment, <c>omment, <k> command, <f>lag,
        # back to the <m>essage style
        "input dir 'stow' not found|input dir <s>'stow'<m> not found"
        "say \"hello world\" twice|say <s>\"hello world\"<m> twice"
        "exit ('1') and ['2'] and x:'3'|exit (<s>'1'<m>) and [<s>'2'<m>] and x:<s>'3'<m>"
        "'first' 'second'|<s>'first'<m> <s>'second'<m>"
        "don't panic, it's fine|don't panic, it's fine"
        "an \"unclosed quote|an \"unclosed quote"
        "source \${HOME}/.zshenv|source <v>\${HOME}<m>/.zshenv"
        "as \$USER with \$1, status \$?|as <v>\$USER<m> with <v>\$1<m>, status <v>\$?<m>"
        "\$first\$second|<v>\$first<m><v>\$second<m>"
        "costs 5 \$ or \${unclosed|costs 5 \$ or \${unclosed"
        "  ENV_FILE=/tmp/.envrc|  <a>ENV_FILE=/tmp/.envrc<m>"
        "key='a b' other=\$HOME done|<a>key='a b'<m> <a>other=\$HOME<m> done"
        "name=\"two words\" empty= x|<a>name=\"two words\"<m> <a>empty=<m> x"
        "--flag=value a == b ?q=1|--flag=value a == b ?q=1"
        "run \`make hooks\` once|run \`make hooks\` once"
        "stow --restow # skipped|stow --restow <c># skipped<m>"
        "# says 'x' and \$y|<c># says 'x' and \$y<m>"
        "PR #16, sec# or ssb#, a#b|PR #16, sec# or ssb#, a#b"
        "\"a # b\" # c|<s>\"a # b\"<m> <c># c<m>"
        "🦇 'bat' luck|🦇 <s>'bat'<m> luck"
        $'first # note\nsecond \'x\'|first <c># note<m>\nsecond <s>\'x\'<m>'
        $'line one\n# line two|line one\n<c># line two<m>'
        $'open "quote\nclose" here|open "quote\nclose" here'
        $'a ${b\nc} d|a ${b\nc} d'
        $'ends with a newline\n|ends with a newline\n'
        $'\n\'x\' after an empty line|\n<s>\'x\'<m> after an empty line'
        "|"
    ) \
        entry

    LOG_SGR_SYNTAX=("<s>" "<v>" "<a>" "<c>" "<k>" "<f>")

    for entry in "${cases[@]}"; do
        log_highlight "${entry%%|*}" "<m>"
        [ "${REPLY}" == "${entry#*|}" ] || {
            printf 'case: %s\n got: %s\n' "${entry}" "${REPLY}"

            return 1
        }
    done
}

@test "log_highlight: the text between two LOG_CODE markers is a command line: command words and flags" {
    local cases=(
        # text => highlighted: <k> command, <f>lag, <s>tring, <v>ariable, <c>omment, back to the
        # <m>essage style. The separator is " => ", a command line may hold a "|".
        "DRY RUN: ${LOG_CODE}brew cleanup --prune=all${LOG_CODE} => DRY RUN: <k>brew<m> cleanup <f>--prune=all<m>"
        "run ${LOG_CODE}git clone --depth 1 -q url${LOG_CODE} now => run <k>git<m> clone <f>--depth<m> 1 <f>-q<m> url now"
        "${LOG_CODE}ls -la | grep x${LOG_CODE} => <k>ls<m> <f>-la<m> | <k>grep<m> x"
        "${LOG_CODE}a && echo \"done\"; exit${LOG_CODE} => <k>a<m> && <k>echo<m> <s>\"done\"<m>; <k>exit<m>"
        "${LOG_CODE}zsh -c source \${HOME}/.zshenv # note${LOG_CODE} => <k>zsh<m> <f>-c<m> source <v>\${HOME}<m>/.zshenv <c># note<m>"
        "${LOG_CODE}./scripts/install.sh -n${LOG_CODE} => <k>./scripts/install.sh<m> <f>-n<m>"
        "${LOG_CODE}a${LOG_CODE} then ${LOG_CODE}b -x${LOG_CODE} => <k>a<m> then <k>b<m> <f>-x<m>"
        "${LOG_CODE}cmd 2>&1${LOG_CODE} => <k>cmd<m> 2>&1"
        "${LOG_CODE}head -1 -- file${LOG_CODE} => <k>head<m> -1 -- file"
        "${LOG_CODE}git --filter=blob:none --name=\"a b\" -o='c d' x${LOG_CODE} => <k>git<m> <f>--filter=blob:none<m> <f>--name=\"a b\"<m> <f>-o='c d'<m> x"
        "${LOG_CODE}echo \`date\`${LOG_CODE} => <k>echo<m> \`date\`"
        "a - b, well-known, -1 and --x in prose => a - b, well-known, -1 and --x in prose"
        $'first\nthen \x1fls -l\x1f => first\nthen <k>ls<m> <f>-l<m>'
        $'a \x1fls\nx\x1f b => a \x1fls\nx\x1f b'
    ) \
        entry

    LOG_SGR_SYNTAX=("<s>" "<v>" "<a>" "<c>" "<k>" "<f>")

    for entry in "${cases[@]}"; do
        log_highlight "${entry%% => *}" "<m>"
        [ "${REPLY}" == "${entry#* => }" ] || {
            printf 'case: %s\n got: %s\n' "${entry}" "${REPLY}"

            return 1
        }
    done
}

@test "log_highlight: a long text takes linear time" {
    # In a fresh shell: bats traces every command, which would dominate the timing.
    # Line by line the text takes well under a second. Scanning it as a whole took more than 5 s.
    run env LOG_COLOR="always" "${BASH}" -s -- "${LOGGER}" <<'SCRIPT'
source "${1}"
text=""
for (( index = 0; index < 3000; index++ )); do
    text+="echo \"line ${index}\" # note"$'\n'
done

SECONDS=0
log_highlight "${text}" ""
printf '%s lines in %s s\n' "${index}" "${SECONDS}"
(( SECONDS < 3 ))
SCRIPT
    [ "${status}" -eq 0 ]
}

@test "log: highlights in the palette's syntax colors and returns to the message color" {
    local message="${ESC}[38;2;62;143;176m" \
          string="${ESC}[38;2;223;142;29m" \
          variable="${ESC}[38;2;196;167;231m" \
          comment="${ESC}[38;2;110;106;134m" \
          expected

    expected="run ${string}'x'${message} as ${variable}\$USER${message}"
    expected+=" with ${variable}HOME=/h${message} ${comment}# note${message}"
    color_mode "always"

    run log_info "run 'x' as \$USER with HOME=/h # note"
    [ "${output}" == "$(colored "64;160;43" "INFO" "156;207;216" "62;143;176" "${expected}")" ]
}

@test "log: colors the command and its flags between two LOG_CODE markers" {
    local message="${ESC}[38;2;110;106;134m" \
          command="${ESC}[38;2;64;160;43m" \
          flag="${ESC}[38;2;156;207;216m" \
          expected

    expected="DRY RUN: ${command}brew${message} cleanup ${flag}--prune=all${message}"
    color_mode "always"

    run log_notice "DRY RUN: ${LOG_CODE}brew cleanup --prune=all${LOG_CODE}"
    [ "${output}" == "$(colored "128;128;0" "NOTICE" "138;255;14" "110;106;134" "${expected}")" ]
}

@test "log: never prints a LOG_CODE marker, with or without colors" {
    run log_notice "DRY RUN: ${LOG_CODE}brew cleanup --prune=all${LOG_CODE} and one ${LOG_CODE}more"
    [ "${output}" == "==>  [NOTICE]: DRY RUN: brew cleanup --prune=all and one more" ]

    color_mode "always"

    run log_notice "one ${LOG_CODE}marker"
    [ "${output}" == "$(colored "128;128;0" "NOTICE" "138;255;14" "110;106;134" "one marker")" ]
}

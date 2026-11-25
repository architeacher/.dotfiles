#!/usr/bin/env bats
# Run: bats tests/progress.bats

setup() {
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../scripts/common.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../scripts/progress.sh"

    CAPTURE="${BATS_TEST_TMPDIR}/stderr"
    LOGO="${BATS_TEST_DIRNAME}/../assets/logo.txt"
    # Two rows, two pieces: the columns of A and B, a blank column, the column of C.
    PIECES="${BATS_TEST_TMPDIR}/pieces.txt"
    printf 'A  C\nAB C\n' > "${PIECES}"
    PROGRESS_LOGO_DELAY=0
    PROGRESS_LOGO_BLINK=0
    PROGRESS_HOLD=0
}

# Makes the module believe stderr is a 24x80 terminal.
fake_terminal() {
    TERM="xterm"
    log_stderr_is_terminal() { return 0; }
    progress_terminal_size() { printf '24 80\n'; }
}

# usage: count_cells <text> <cell>  (count in REPLY, independent of the locale's character width)
count_cells() {
    local rest="${1//${2}/}"

    REPLY=$(( (${#1} - ${#rest}) / ${#2} ))
}

# --- progress_frame ---------------------------------------------------------

@test "progress_frame: the trail enters, crosses and leaves the bar" {
    local cases=(
        "0|1"
        "5|6"
        "7|8"
        "27|8"
        "31|4"
        "35|0"
        "36|1"
    ) \
    entry step expected

    for entry in "${cases[@]}"; do
        IFS='|' read -r step expected <<< "${entry}"

        progress_frame "${step}" "Homebrew"
        count_cells "${REPLY}" "${PROGRESS_FULL}"

        [ "${REPLY}" -eq "${expected}" ] || { echo "step ${step}: ${REPLY} full cells, want ${expected}"; return 1; }
    done
}

@test "progress_frame: the bar keeps its width" {
    local step full

    for step in 0 9 35; do
        progress_frame "${step}" "Homebrew"
        count_cells "${REPLY}" "${PROGRESS_FULL}"
        full="${REPLY}"

        progress_frame "${step}" "Homebrew"
        count_cells "${REPLY}" "${PROGRESS_EMPTY}"

        [ "$(( full + REPLY ))" -eq "${PROGRESS_BAR_WIDTH}" ]
    done
}

@test "progress_frame: shows the spinner frame of the step and the label" {
    progress_frame 3 "Homebrew packages"
    [[ "${REPLY}" == *"${PROGRESS_SPINNER[3]}"*"Homebrew packages" ]]

    progress_frame "${#PROGRESS_SPINNER[@]}" "Homebrew packages"
    [[ "${REPLY}" == *"${PROGRESS_SPINNER[0]}"* ]]
}

@test "progress_frame: the bar fills up to the percentage, the trail adds no cell to it, the number follows" {
    # <step>|<percentage>|<full cells>|<what follows the bar>. Without a percentage the trail is
    # outside the bar at step 35. With one it stays inside the filled part at every step.
    local cases=(
        "35||0| Homebrew"
        "35|0|0|   0% Homebrew"
        "5|0|0|   0% Homebrew"
        "35|17|4|  17% Homebrew"
        "0|50|14|  50% Homebrew"
        "5|50|14|  50% Homebrew"
        "20|50|14|  50% Homebrew"
        "35|50|14|  50% Homebrew"
        "5|100|28| 100% Homebrew"
    ) \
    entry step percent expected rest

    for entry in "${cases[@]}"; do
        IFS='|' read -r step percent expected rest <<< "${entry}"

        progress_frame "${step}" "Homebrew" "${percent}"
        [[ "${REPLY}" == *"${rest}" ]] || { echo "${percent}%: ${REPLY}"; return 1; }
        [[ "${REPLY}" != *"%"* || -n "${percent}" ]] || { echo "a percentage without steps: ${REPLY}"; return 1; }

        count_cells "${REPLY}" "${PROGRESS_FULL}"
        [ "${REPLY}" -eq "${expected}" ] || { echo "${percent}% at step ${step}: ${REPLY} full cells, want ${expected}"; return 1; }
    done
}

@test "progress_frame: the trail runs inside the filled part and ends at its edge" {
    run env LOG_COLOR="always" "${BASH}" -c "
        source '${BATS_TEST_DIRNAME}/../scripts/common.sh'
        source '${BATS_TEST_DIRNAME}/../scripts/progress.sh'
        progress_frame 5 Homebrew 50
        printf '%s\n' \"\${REPLY}\"
        progress_frame 20 Homebrew 50
        printf '%s\n' \"\${REPLY}\"
        printf '%s\n' \"\${PROGRESS_SGR_TEXT}\${PROGRESS_FULL}\"
    "
    [ "${status}" -eq 0 ]

    # A cell of the filled part that the trail is not on.
    local filled="${lines[2]}"

    # 14 cells are filled. At step 5 the trail is on the first six, at step 20 it leaves over the last one.
    count_cells "${lines[0]}" "${filled}"
    [ "${REPLY}" -eq 8 ]
    count_cells "${lines[1]}" "${filled}"
    [ "${REPLY}" -eq 13 ]
}

@test "progress_percent: the share of the announced steps that are done, none without steps" {
    # <steps announced>|<steps done>|<percentage>
    local cases=(
        "0|3|"
        "6|0|0"
        "6|1|17"
        "6|2|33"
        "6|3|50"
        "6|4|67"
        "6|5|83"
        "6|6|100"
        "6|7|100"
    ) \
    entry total completed expected

    for entry in "${cases[@]}"; do
        IFS='|' read -r total completed expected <<< "${entry}"
        _progress_total="${total}"
        _progress_done="${completed}"

        progress_percent
        [ "${REPLY}" == "${expected}" ] || { echo "${completed} of ${total}: '${REPLY}', want '${expected}'"; return 1; }
    done
}

@test "progress_frame: no escape sequence when colors are off" {
    progress_frame 4 "Homebrew"
    [[ "${REPLY}" != *"${LOG_ESCAPE}"* ]]
}

@test "progress_frame: colored with the palette when colors are on" {
    run env LOG_COLOR="always" "${BASH}" -c "
        source '${BATS_TEST_DIRNAME}/../scripts/common.sh'
        source '${BATS_TEST_DIRNAME}/../scripts/progress.sh'
        progress_frame 4 Homebrew
        printf '%s' \"\${REPLY}\"
    "
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"${LOG_ESCAPE}[38;"* ]]
}

# --- progress_enabled -------------------------------------------------------

@test "progress_enabled: only on a terminal that is not dumb" {
    run progress_enabled
    [ "${status}" -ne 0 ]

    fake_terminal
    progress_enabled

    TERM="dumb"
    run progress_enabled
    [ "${status}" -ne 0 ]
}

# --- progress_room ----------------------------------------------------------

@test "progress_room: true when the terminal is at least that large, its rows in REPLY" {
    local cases=(
        "24|80|0"
        "2|60|0"
        "25|80|1"
        "24|81|1"
    ) \
    entry rows columns expected

    fake_terminal

    for entry in "${cases[@]}"; do
        IFS='|' read -r rows columns expected <<< "${entry}"

        run progress_room "${rows}" "${columns}"
        [ "${status}" -eq "${expected}" ] || { echo "${rows}x${columns}: status ${status}, want ${expected}"; return 1; }
    done

    progress_room 2 60
    [ "${REPLY}" -eq 24 ]
}

@test "progress_room: false without a terminal and for a size that is not a number" {
    run progress_room 1 1
    [ "${status}" -ne 0 ]

    fake_terminal
    progress_terminal_size() { printf 'unknown\n'; }

    run progress_room 1 1
    [ "${status}" -ne 0 ]
}

@test "progress_start: nothing when the terminal is too narrow for the line" {
    fake_terminal
    progress_terminal_size() { printf '24 30\n'; }

    progress_start "Homebrew" 2> "${CAPTURE}"

    [ -z "${_progress_pid}" ]
    [ ! -s "${CAPTURE}" ]
}

# --- progress_start / progress_stop ------------------------------------------

@test "progress_start: prints nothing and starts nothing without a terminal" {
    progress_start "Homebrew" 2> "${CAPTURE}"
    progress_stop 2>> "${CAPTURE}"

    [ -z "${_progress_pid}" ]
    [ ! -s "${CAPTURE}" ]
}

@test "progress_start: reserves the bottom row, draws there, progress_stop gives it back" {
    local pid drawn

    fake_terminal

    progress_start "Homebrew" 2>> "${CAPTURE}"
    pid="${_progress_pid}"
    sleep 0.3
    progress_stop 2>> "${CAPTURE}"

    drawn="$(< "${CAPTURE}")"

    [[ "${drawn}" == *"${LOG_ESCAPE}[1;23r"* ]]
    [[ "${drawn}" == *"${LOG_ESCAPE}[24;1H"*"Homebrew"* ]]
    [[ "${drawn}" == *"${LOG_ESCAPE}[r${LOG_ESCAPE}[24;1H${LOG_ESCAPE}[K"* ]]
    [ -z "${_progress_pid}" ]
    ! kill -0 "${pid}" 2> /dev/null
}

@test "progress_loop: starts at the given frame and leaves with the place of its trail" {
    local pid \
          status=0

    progress_loop "Homebrew" 24 "" 20 2> "${CAPTURE}" &
    pid="$!"
    sleep 0.3
    kill "${pid}"
    wait "${pid}" || status="$?"

    progress_frame 20 "Homebrew"
    [[ "$(< "${CAPTURE}")" == *"${REPLY}"* ]]
    # A few frames later: the place moved on from 20 and is still within one sweep of the trail.
    [ "${status}" -gt 20 ]
    [ "${status}" -lt "$(( PROGRESS_BAR_WIDTH + PROGRESS_TRAIL ))" ]
}

@test "progress_halt: keeps the place of the trail, so that the next line goes on from there" {
    # Stands in for the loop: it leaves with a place when it is ended.
    ( trap 'exit 7' TERM; while :; do sleep 0.05; done ) &
    _progress_pid="$!"
    sleep 0.2

    progress_halt

    [ "${_progress_step}" -eq 7 ]
    [ -z "${_progress_pid}" ]
}

@test "progress_halt: a loop that could not report leaves the place as it was" {
    sleep 5 &
    _progress_pid="$!"
    _progress_step=9

    progress_halt

    [ "${_progress_step}" -eq 9 ]
}

@test "progress_run: the trail goes on over the steps, it is not thrown back to the left" {
    fake_terminal
    PROGRESS_HOLD=0.2
    progress_steps 2

    # Stands in for the loop: notes the frame it starts at and leaves five frames further.
    progress_loop() {
        local first="${4}"

        echo "${first}" >> "${CAPTURE}"
        trap 'exit "$(( first + 5 ))"' TERM
        while :; do sleep 0.05; done
    }

    progress_run "First" sleep 0.2 2> /dev/null
    progress_run "Second" sleep 0.2 2> /dev/null

    # Two loops per step: one while it runs, one with the new percentage while it is held.
    [ "$(tr '\n' ' ' < "${CAPTURE}")" == "0 5 10 15 " ]
}

@test "progress_stop: safe to call twice and without a start" {
    progress_stop
    progress_stop
}

# --- progress_hold ----------------------------------------------------------

@test "progress_hold: waits only while a line is drawn" {
    # <pid of the line>|<what sleep is asked for>
    local cases=(
        "|"
        "4321|slept 0.6"
    ) \
    entry pid expected

    sleep() { echo "slept ${1}"; }
    PROGRESS_HOLD=0.6

    for entry in "${cases[@]}"; do
        IFS='|' read -r pid expected <<< "${entry}"
        _progress_pid="${pid}"

        run progress_hold
        [ "${status}" -eq 0 ]
        [ "${output}" == "${expected}" ] || { echo "pid '${pid}': ${output}"; return 1; }
    done
}

# --- progress_run -----------------------------------------------------------

@test "progress_steps: announces the steps and starts counting again" {
    _progress_done=4

    progress_steps 6

    [ "${_progress_total}" -eq 6 ]
    [ "${_progress_done}" -eq 0 ]
}

@test "progress_steps_of: announces one step for each progress_run call in the function" {
    three_steps() {
        progress_run "First" true
        # progress_run "a comment is no call" true
        echo "progress_run in a text is no call"
        progress_run "Second" true
        progress_run "Third" true
    }
    no_steps() { :; }

    progress_steps_of three_steps
    [ "${_progress_total}" -eq 3 ]

    _progress_done=2
    progress_steps_of no_steps
    [ "${_progress_total}" -eq 0 ]
    [ "${_progress_done}" -eq 0 ]
}

@test "progress_run: counts a step that succeeds, not one that fails" {
    progress_steps 2

    progress_run "First" true
    [ "${_progress_done}" -eq 1 ]

    progress_run "Second" false || true
    [ "${_progress_done}" -eq 1 ]
}

@test "progress_run: the line shows the percentage, and the new one while it is held" {
    local drawn

    fake_terminal
    PROGRESS_HOLD=0.3
    progress_steps 2

    progress_run "Homebrew" sleep 0.3 2>> "${CAPTURE}"
    drawn="$(< "${CAPTURE}")"

    [[ "${drawn}" == *"   0% Homebrew"*"  50% Homebrew"* ]]
    [[ "${drawn}" != *"  50% Homebrew"*"   0% Homebrew"* ]]
    [ -z "${_progress_pid}" ]
}

@test "progress_run: holds the line of a finished step before stopping it" {
    progress_start() { echo "start"; }
    progress_hold() { echo "hold"; }
    progress_stop() { echo "stop"; }

    run progress_run "Homebrew" echo "step"
    [ "${status}" -eq 0 ]
    [ "${output}" == "start${LOG_NEWLINE}step${LOG_NEWLINE}hold${LOG_NEWLINE}stop" ]
}

@test "progress_run: runs the command with its arguments, output unchanged" {
    run progress_run "Greeting" printf '%s-%s\n' "hello" "big world"
    [ "${status}" -eq 0 ]
    [ "${output}" == "hello-big world" ]
}

@test "progress_run: returns the status of the command" {
    fail_with() { return "${1}"; }

    run progress_run "Failing" fail_with 7
    [ "${status}" -eq 7 ]
}

@test "progress_run: the line is gone when the command is done" {
    fake_terminal

    progress_run "Homebrew" sleep 0.2 2>> "${CAPTURE}"

    [ -z "${_progress_pid}" ]
    [[ "$(< "${CAPTURE}")" == *"${LOG_ESCAPE}[r"* ]]
}

# --- progress_logo_load / progress_logo_frame --------------------------------

@test "progress_logo_load: reads the rows unchanged, and the longest length" {
    progress_logo_load "${LOGO}"

    [ "${#PROGRESS_LOGO[@]}" -eq 7 ]
    [ "${PROGRESS_LOGO_WIDTH}" -eq 58 ]
    [ "$(printf '%s\n' "${PROGRESS_LOGO[@]}")" == "$(< "${LOGO}")" ]
}

@test "progress_logo_load: no rows from what is not a readable file" {
    local cases=(
        "${BATS_TEST_TMPDIR}/missing.txt"
        "${BATS_TEST_TMPDIR}"
    ) \
    file

    for file in "${cases[@]}"; do
        PROGRESS_LOGO=("stale")
        PROGRESS_LOGO_WIDTH=5

        progress_logo_load "${file}"

        [ "${#PROGRESS_LOGO[@]}" -eq 0 ] || { echo "${file}: rows kept"; return 1; }
        [ "${PROGRESS_LOGO_WIDTH}" -eq 0 ]
        [ "${#PROGRESS_LOGO_STARTS[@]}" -eq 0 ]
    done
}

@test "progress_logo_load: cuts the logo into pieces at its blank columns" {
    progress_logo_load "${PIECES}"

    [ "${PROGRESS_LOGO_STARTS[*]}" == "0 3" ]
    [ "${PROGRESS_LOGO_LENGTHS[*]}" == "2 1" ]
}

@test "progress_logo_load: the block logo is one piece per letter" {
    (( ${#PROGRESS_FULL} == 1 )) || skip "the shell counts bytes, not characters, in this locale"

    progress_logo_load "${BATS_TEST_DIRNAME}/../assets/logo-blocks.txt"

    [ "${PROGRESS_LOGO_STARTS[*]}" == "0 2 7 12 16 20 22 25 30" ]
    [ "${PROGRESS_LOGO_LENGTHS[*]}" == "1 4 4 3 3 1 2 4 4" ]
}

@test "progress_logo_frame: the pieces come down onto the bar, the later ones complete it, then it goes" {
    # <frame>|<base>|<style>|<lines of the frame, joined by commas>
    # The bar is under the first of the two pieces from the start. The second one brings its part.
    local cases=(
        "0|bar||,,  ▀▀▀"
        "1|bar||  AB,,  ▀▀▀"
        "2|bar||  A,  AB,  ▀▀▀"
        "3|bar||  A  C,  AB,  ▀▀▀"
        "4|bar||  A  C,  AB C,  ▀▀▀▀"
        "4|flash||  A  C,  AB C,  ▀▀▀▀"
        "4|none||,  A  C,  AB C"
        "9|none||,  A  C,  AB C"
        "4|none|<W>|,  <W>A  <W>C,  <W>AB <W>C"
    ) \
    entry frame base style expected

    progress_logo_load "${PIECES}"

    for entry in "${cases[@]}"; do
        IFS='|' read -r frame base style expected <<< "${entry}"

        progress_logo_frame "${frame}" "${base}" "${style}"

        [ "${REPLY//${LOG_NEWLINE}/,}" == "${expected}," ] || { echo "frame ${frame}, ${base}: ${REPLY//${LOG_NEWLINE}/,}"; return 1; }
    done
}

@test "progress_logo_frame: a later piece brings its part of the bar in its own color, the flash is one color" {
    run env LOG_COLOR="always" "${BASH}" -c "
        source '${BATS_TEST_DIRNAME}/../scripts/common.sh'
        source '${BATS_TEST_DIRNAME}/../scripts/progress.sh'
        progress_logo_load '${PIECES}'
        progress_logo_frame 4 bar
        printf '%s' \"\${REPLY}\"
        progress_logo_frame 4 flash
        printf '%s' \"\${REPLY}\"
    "
    [ "${status}" -eq 0 ]

    local reset="${LOG_ESCAPE}[0m" \
          piece="${lines[0]##*  }" \
          bar="${lines[2]#  }" \
          flash="${lines[5]#  }"

    # The bar is two runs: the part from the start, then the part of piece C in the style of C.
    [ "${bar%%▀*}" != "${bar#*"${reset}"}" ]
    [[ "${bar#*"${reset}"}" == "${piece%%C*}▀${reset}" ]]

    # The flash: both runs in one style, which is not the style of the part from the start.
    local first="${flash%%▀*}" \
          second="${flash#*"${reset}"}"

    [ "${first}" == "${second%%▀*}" ]
    [ "${first}" != "${bar%%▀*}" ]
}

@test "progress_logo_frame: each piece has a color of its own" {
    run env LOG_COLOR="always" "${BASH}" -c "
        source '${BATS_TEST_DIRNAME}/../scripts/common.sh'
        source '${BATS_TEST_DIRNAME}/../scripts/progress.sh'
        progress_logo_load '${PIECES}'
        progress_logo_frame 4 bar
        printf '%s' \"\${REPLY}\"
    "
    [ "${status}" -eq 0 ]

    # First line: piece A, two blank columns, piece C. Each in its color, then reset.
    local first="${lines[0]#  }" \
          second="${lines[0]##*  }"

    [[ "${lines[0]}" == "  ${LOG_ESCAPE}[38;"*"mA${LOG_ESCAPE}[0m  ${LOG_ESCAPE}[38;"*"mC${LOG_ESCAPE}[0m" ]]
    [ "${first%%A*}" != "${second%%C*}" ]
}

# --- progress_banner --------------------------------------------------------

@test "progress_banner: plain logo, headline and subtitle without a terminal, set apart by blank lines" {
    progress_banner "${LOGO}" ".dotfiles Installer" "Install Mac software" 2> "${CAPTURE}"

    {
        sed 's/^/  /' "${LOGO}"
        printf '\n  .dotfiles Installer\n  Install Mac software\n\n'
    } > "${BATS_TEST_TMPDIR}/expected"

    cmp "${CAPTURE}" "${BATS_TEST_TMPDIR}/expected"
}

@test "progress_banner: headline and subtitle remain when the logo is missing" {
    progress_banner "${BATS_TEST_TMPDIR}/missing.txt" ".dotfiles Installer" "Install Mac software" 2> "${CAPTURE}"

    printf '\n  .dotfiles Installer\n  Install Mac software\n\n' > "${BATS_TEST_TMPDIR}/expected"

    cmp "${CAPTURE}" "${BATS_TEST_TMPDIR}/expected"
}

@test "progress_banner: the first piece enters at the top, the last frame is the plain text a row lower" {
    # The canvas is the two rows of the logo and the row of the bar.
    local plain animated redraw="${LOG_ESCAPE}[3A${LOG_ESCAPE}[J"

    plain="$(progress_banner "${PIECES}" ".dotfiles Installer" "Install Mac software" 2>&1)"
    fake_terminal
    animated="$(progress_banner "${PIECES}" ".dotfiles Installer" "Install Mac software" 2>&1)"

    # Before the first move back to the top: the empty canvas with the bar under the first piece.
    # After it: the first frame.
    [[ "${animated}" == "${LOG_NEWLINE}${LOG_NEWLINE}  ▀▀▀${LOG_NEWLINE}${redraw}"* ]]
    [[ "${animated#*"${redraw}"}" == "  AB${LOG_NEWLINE}${LOG_NEWLINE}  ▀▀▀${LOG_NEWLINE}"* ]]
    # After the last one: the logo in the row the bar left, so below a blank row.
    [ "${animated##*"${redraw}"}" == "${LOG_NEWLINE}${plain}" ]
}

@test "progress_banner: the pieces fall at one pace, the two flickers run at another" {
    local slept

    fake_terminal
    sleep() { printf 'slept %s\n' "${1}"; }
    PROGRESS_LOGO_DELAY=0.1
    PROGRESS_LOGO_BLINK=0.3

    slept="$(progress_banner "${PIECES}" ".dotfiles Installer" "Install Mac software" 2> /dev/null)"
    slept="${slept//slept 0.1/f}"
    slept="${slept//slept 0.3/S}"

    # Two pieces of two rows: three frames of falling. Then the bar flickers twice, colored and
    # text color, and so does the logo in its row: four frames each.
    [ "${slept//${LOG_NEWLINE}/}" == "fffSSSSSSSS" ]
}

@test "progress_logo_animate: the pieces fall, the complete bar flickers twice, then the logo does" {
    local drawn

    progress_logo_load "${PIECES}"
    PROGRESS_SGR_TEXT="<W>"
    # Stands in for the drawing: notes the frame, what the pieces rest on, and the style.
    progress_logo_draw() { shift; echo "$*"; }

    drawn="$(progress_logo_animate 2> /dev/null)"

    [ "${drawn}" == "$(printf '%s\n' \
        "1 bar" "2 bar" "3 bar" \
        "4 bar" "4 flash" "4 bar" "4 flash" \
        "4 none" "4 none <W>" "4 none" "4 none <W>")" ]
}

@test "progress_banner: the logo ends in the text color, the headline is bold" {
    local redraw="${LOG_ESCAPE}[3A${LOG_ESCAPE}[J" \
          logo_style \
          title_style

    run env LOG_COLOR="always" TERM="xterm" "${BASH}" -c "
        source '${BATS_TEST_DIRNAME}/../scripts/common.sh'
        source '${BATS_TEST_DIRNAME}/../scripts/progress.sh'
        log_stderr_is_terminal() { return 0; }
        progress_terminal_size() { printf '24 80\n'; }
        PROGRESS_LOGO_DELAY=0
        PROGRESS_LOGO_BLINK=0
        printf '%s\n%s\n' \"\${PROGRESS_SGR_TEXT}\" \"\${PROGRESS_SGR_TITLE}\"
        progress_banner '${PIECES}' '.dotfiles Installer' 'Install Mac software'
    "
    [ "${status}" -eq 0 ]
    logo_style="${lines[0]}"
    title_style="${lines[1]}"

    [[ "${title_style}" == "${LOG_ESCAPE}[${LOG_ATTRIBUTE_BOLD};"* ]]
    [[ "${output##*"${redraw}"}" == "${LOG_NEWLINE}  ${logo_style}A"* ]]
    [[ "${output}" == *"  ${title_style}.dotfiles Installer${LOG_ESCAPE}[0m"* ]]
}

@test "progress_banner: printed at once when the logo does not fit the terminal" {
    # The logo is 7 rows of up to 58 columns behind an indent of 2. Below it are the row of the bar
    # and the row the cursor rests in.
    local cases=(
        "9 60|yes"
        "8 60|no"
        "9 59|no"
    ) \
    entry size animated

    fake_terminal

    for entry in "${cases[@]}"; do
        IFS='|' read -r size animated <<< "${entry}"
        progress_terminal_size() { printf '%s\n' "${size}"; }

        run progress_banner "${LOGO}" ".dotfiles Installer" "Install Mac software"

        if [[ "${animated}" == "yes" ]]; then
            [[ "${output}" == *"${LOG_ESCAPE}["* ]] || { echo "${size}: not animated"; return 1; }
        else
            [[ "${output}" != *"${LOG_ESCAPE}"* ]] || { echo "${size}: animated"; return 1; }
        fi
    done
}

# --- progress_confirm -------------------------------------------------------

@test "progress_confirm: yes without a question when nobody can answer" {
    run progress_confirm "Choose an action:" "Install .dotfiles" "Do nothing" < /dev/null
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
}

@test "progress_confirm: shows the question and both choices, yes as the default" {
    progress_interactive() { return 0; }

    run progress_confirm "Choose an action:" "Install .dotfiles" "Do nothing" <<< "n"
    [ "${lines[0]}" == "Choose an action:" ]
    [ "${lines[1]}" == "  y    Install .dotfiles (default)" ]
    [ "${lines[2]}" == "  n    Do nothing" ]
    [[ "${output}" != *"${LOG_ESCAPE}"* ]]
}

@test "progress_confirm: Enter and y say yes, n says no, other keys are skipped" {
    # <keys typed, E is Enter>|<status>. No key at all is the end of the input.
    local cases=(
        "E|0"
        "y|0"
        "Y|0"
        "n|1"
        "N|1"
        "xy|0"
        "xn|1"
        "|1"
    ) \
    entry keys expected

    progress_interactive() { return 0; }

    for entry in "${cases[@]}"; do
        IFS='|' read -r keys expected <<< "${entry}"

        run progress_confirm "Choose an action:" "Install .dotfiles" "Do nothing" \
            < <(printf '%s' "${keys//E/${LOG_NEWLINE}}")
        [ "${status}" -eq "${expected}" ] || { echo "keys '${keys}': status ${status}, want ${expected}"; return 1; }
    done
}

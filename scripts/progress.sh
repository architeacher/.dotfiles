#!/usr/bin/env bash

# Terminal animation for long scripts: a banner with a logo whose rows drop into place, a yes or no
# question, and a progress line pinned to the bottom row while a step runs. The step's own output is
# never captured or changed: it scrolls above the line.
# Needs scripts/logger.sh (palette, LOG_ESCAPE). Everything is written to stderr, like the log lines.

readonly PROGRESS_BAR_WIDTH=28
readonly PROGRESS_TRAIL=8
readonly PROGRESS_INTERVAL=0.08
# Below this width the line would wrap on the reserved row.
readonly PROGRESS_MIN_COLUMNS=60
# The line takes the bottom row, the step needs a row above it.
readonly PROGRESS_MIN_ROWS=2
readonly PROGRESS_INDENT="  "
readonly PROGRESS_FULL="█"
readonly PROGRESS_EMPTY="░"
# The bar the pieces of the banner logo land on.
readonly PROGRESS_UPPER="▀"

# Arrays are assigned first, then made readonly, see scripts/logger.sh.
PROGRESS_SPINNER=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
readonly PROGRESS_SPINNER

# Palette roles of the trail, from its head to its tail. Also the row colors of the banner logo
# while it falls, from its top to its bottom.
PROGRESS_THEME_TRAIL=(yellow pink blue cyan)
readonly PROGRESS_THEME_TRAIL
readonly PROGRESS_THEME_SPINNER="cyan"
readonly PROGRESS_THEME_EMPTY="muted"
# The logo once it is in place, and the part of the bar that is done. In bold: the headline of the
# banner and a question.
readonly PROGRESS_THEME_TEXT="text"
# A question: the key of a choice, and the label of the yes choice.
readonly PROGRESS_THEME_KEY="cyan"
readonly PROGRESS_THEME_YES="green"

# Seconds between two frames of the banner logo while a piece falls a row.
PROGRESS_LOGO_DELAY=0.04
# Seconds a frame of the banner logo stays while the bar, and then the complete logo, flicker between
# their colors and the text color.
PROGRESS_LOGO_BLINK=0.12
# How often the bar, and then the logo, turn to the text color while they flicker.
readonly PROGRESS_LOGO_FLICKERS=2
# Seconds the line of a finished step stays on screen.
PROGRESS_HOLD=0.6

# The banner logo, set by progress_logo_load: its rows, the length of the longest one, a bar of that
# length, and its pieces. A piece is a run of columns between blank ones, a letter in a wordmark:
# the column it starts at and its length.
PROGRESS_LOGO=()
PROGRESS_LOGO_WIDTH=0
PROGRESS_LOGO_BAR=""
PROGRESS_LOGO_STARTS=()
PROGRESS_LOGO_LENGTHS=()

# Styles of the active palette, compiled by progress_set_styles. All are empty when colors are off.
PROGRESS_SGR_TRAIL=()
PROGRESS_SGR_SPINNER=""
PROGRESS_SGR_EMPTY=""
PROGRESS_SGR_TEXT=""
PROGRESS_SGR_TITLE=""
PROGRESS_SGR_KEY=""
PROGRESS_SGR_YES=""

_progress_pid=""
_progress_row=""
_progress_label=""
# The frame the next line starts at: the place of the trail of the line before it. So the trail goes
# on over the steps, and a step that returns at once does not throw it back to the left edge.
_progress_step=0
# Steps announced by progress_steps, and how many of them are done.
_progress_total=0
_progress_done=0

progress_set_styles() {
    local index

    for (( index = 0; index < ${#PROGRESS_THEME_TRAIL[@]}; index++ )); do
        log_style "${PROGRESS_THEME_TRAIL[index]}"
        PROGRESS_SGR_TRAIL[index]="${REPLY}"
    done

    log_style "${PROGRESS_THEME_SPINNER}"
    PROGRESS_SGR_SPINNER="${REPLY}"
    log_style "${PROGRESS_THEME_EMPTY}"
    PROGRESS_SGR_EMPTY="${REPLY}"
    log_style "${PROGRESS_THEME_TEXT}"
    PROGRESS_SGR_TEXT="${REPLY}"
    log_style "${PROGRESS_THEME_TEXT}" "${LOG_ATTRIBUTE_BOLD}"
    PROGRESS_SGR_TITLE="${REPLY}"
    log_style "${PROGRESS_THEME_KEY}"
    PROGRESS_SGR_KEY="${REPLY}"
    log_style "${PROGRESS_THEME_YES}"
    PROGRESS_SGR_YES="${REPLY}"
}

# True when animation is drawn: stderr is a terminal that understands cursor movement. Off under
# xtrace, where the trace of the drawing loop would flood the screen.
progress_enabled() {
    [[ "${TERM:-dumb}" != "dumb" && "$-" != *x* ]] && log_stderr_is_terminal
}

# Prints "<rows> <columns>" of the terminal on stderr.
progress_terminal_size() {
    stty size <&2 2> /dev/null
}

# usage: progress_room <rows> <columns>  (rows of the terminal in REPLY)
# True when animation is drawn and the terminal is at least that large.
progress_room() {
    local rows="" \
          columns=""

    progress_enabled || return 1

    IFS=' ' read -r rows columns <<< "$(progress_terminal_size)" || return 1
    [[ "${rows}" =~ ^[0-9]+$ && "${columns}" =~ ^[0-9]+$ ]] || return 1
    REPLY="${rows}"

    (( rows >= ${1} && columns >= ${2} ))
}

# usage: progress_steps <count>
# Announces how many steps progress_run will run: the line then shows the share that is done.
progress_steps() {
    _progress_total="${1:?count required}"
    _progress_done=0
}

# usage: progress_steps_of <function>
# Announces one step for each progress_run call in the definition of that function, so that the
# number is not kept by hand. A call in a loop or under a condition counts once.
progress_steps_of() {
    local name="${1:?function required}" \
          call='^[[:space:]]*progress_run[[:space:]]' \
          count=0 \
          line

    while IFS= read -r line; do
        [[ ! "${line}" =~ ${call} ]] || count=$(( count + 1 ))
    done < <(declare -f "${name}")

    progress_steps "${count}"
}

# usage: progress_percent  (REPLY: the share of the announced steps that are done, empty without steps)
progress_percent() {
    REPLY=""
    (( _progress_total > 0 )) || return 0

    REPLY=$(( (_progress_done * 100 + _progress_total / 2) / _progress_total ))
    (( REPLY <= 100 )) || REPLY=100
}

# usage: progress_sweep [percentage]  (REPLY: the cells the trail sweeps)
# The filled part of the bar, so that the trail ends where the progress is. The whole bar when no
# percentage is shown.
progress_sweep() {
    REPLY=$(( ${1:-100} * PROGRESS_BAR_WIDTH / 100 ))
}

# usage: progress_frame <step> <label> [percentage]  (line in REPLY)
# A trail of PROGRESS_TRAIL cells sweeps over the bar, one cell per step, then starts again: it shows
# that the script is alive, not how far the step is. With a percentage the bar is filled up to it,
# the trail sweeps that filled part only, and the number follows the bar: that shows how far the
# script is.
progress_frame() {
    local step="${1}" \
          label="${2}" \
          percent="${3:-}" \
          bar="" \
          number="" \
          filled=0 \
          sweep \
          head \
          age \
          index

    progress_sweep "${percent}"
    sweep="${REPLY}"
    [[ -z "${percent}" ]] || filled="${sweep}"
    head=$(( step % (sweep + PROGRESS_TRAIL) ))

    for (( index = 0; index < PROGRESS_BAR_WIDTH; index++ )); do
        age=$(( head - index ))

        (( index < sweep && age >= 0 && age < PROGRESS_TRAIL )) && {
            bar+="${PROGRESS_SGR_TRAIL[age * ${#PROGRESS_THEME_TRAIL[@]} / PROGRESS_TRAIL]}${PROGRESS_FULL}"

            continue
        }

        (( index < filled )) && {
            bar+="${PROGRESS_SGR_TEXT}${PROGRESS_FULL}"

            continue
        }

        bar+="${PROGRESS_SGR_EMPTY}${PROGRESS_EMPTY}"
    done

    [[ -z "${percent}" ]] || printf -v number ' %3d%%' "${percent}"

    REPLY="${PROGRESS_INDENT}${PROGRESS_SGR_SPINNER}${PROGRESS_SPINNER[step % ${#PROGRESS_SPINNER[@]}]}"
    REPLY+=" ${bar}${LOG_SGR_RESET}${number} ${label}"
}

# usage: progress_loop <label> <row> [percentage] [first frame]
# Redraws the line on the reserved row until it is ended or the script is gone. Ended, it leaves with
# the place of its trail as its status: a subshell has no other way to hand a number back, and a
# place is below 128, the status of a loop that was killed before it could report.
progress_loop() {
    local label="${1}" \
          row="${2}" \
          percent="${3:-}" \
          step="${4:-0}" \
          round

    # The frames of one round of the trail: over the cells it sweeps, then out of them.
    progress_sweep "${percent}"
    # The trap below reads it, in a string ShellCheck does not look into.
    # shellcheck disable=SC2034
    round=$(( REPLY + PROGRESS_TRAIL ))

    # The subshell inherits errexit and, under errtrace, the ERR trap: a failed draw must not log.
    set +eE
    trap - ERR
    trap 'exit "$(( step % round ))"' TERM

    while kill -0 "$$" 2> /dev/null; do
        progress_frame "${step}" "${label}" "${percent}"
        # One write per frame: save the cursor, draw on the row, clear the rest, restore the cursor.
        printf '%s7%s[%d;1H%s%s[K%s8' \
            "${LOG_ESCAPE}" "${LOG_ESCAPE}" "${row}" "${REPLY}" "${LOG_ESCAPE}" "${LOG_ESCAPE}" >&2

        step=$(( step + 1 ))
        sleep "${PROGRESS_INTERVAL}"
    done
}

# usage: progress_start <label>
# Reserves the bottom row with a scroll region and animates the line there in the background.
# shortcut: the size is read once per step, a resize leaves the line on the old row until the next step.
progress_start() {
    local label="${1:?label required}" \
          rows

    progress_stop
    progress_room "${PROGRESS_MIN_ROWS}" "${PROGRESS_MIN_COLUMNS}" || return 0
    rows="${REPLY}"

    # The newline scrolls once if the cursor is on the bottom row, so the row is free. The region
    # change moves the cursor home, hence save and restore around it.
    printf '\n%s7%s[1;%dr%s8%s[1A' \
        "${LOG_ESCAPE}" "${LOG_ESCAPE}" "$(( rows - 1 ))" "${LOG_ESCAPE}" "${LOG_ESCAPE}" >&2

    _progress_row="${rows}"
    _progress_label="${label}"
    progress_animate
}

# Ends the loop that draws the line, if there is one, and keeps the place of its trail. What the
# loop drew stays on the row.
progress_halt() {
    local place=0

    [[ -n "${_progress_pid}" ]] || return 0

    kill "${_progress_pid}" 2> /dev/null || true
    wait "${_progress_pid}" 2> /dev/null || place="$?"
    _progress_pid=""

    # 128 and more: the loop was killed before it could report, the place stays as it was.
    (( place >= 128 )) || _progress_step="${place}"
}

# Draws the line of the current step on the reserved row, in the background, with the percentage
# of now and from the place the trail was at. Takes the place of a loop that is already drawing.
progress_animate() {
    progress_halt
    progress_percent

    # Not holding stdout: a caller's command substitution would wait for the loop.
    progress_loop "${_progress_label}" "${_progress_row}" "${REPLY}" "${_progress_step}" > /dev/null &
    _progress_pid="$!"
}

# Counts a step as done. A line that is drawn shows the new percentage at once.
progress_advance() {
    _progress_done=$(( _progress_done + 1 ))

    [[ -n "${_progress_pid}" ]] || return 0
    (( _progress_total > 0 )) || return 0

    progress_animate
}

# Stops the line, clears its row and gives the whole screen back. Does nothing without a start.
progress_stop() {
    [[ -n "${_progress_pid}" ]] || return 0

    progress_halt
    printf '%s7%s[r%s[%d;1H%s[K%s8' \
        "${LOG_ESCAPE}" "${LOG_ESCAPE}" "${LOG_ESCAPE}" "${_progress_row}" "${LOG_ESCAPE}" "${LOG_ESCAPE}" >&2
}

# Keeps the line of a finished step on screen, so that a step that returns at once is still seen.
# Does nothing when no line is drawn: a pipe, a file and a small terminal never wait.
# shortcut: a long step waits as well, wait only for the missing time once Bash 3.2 is dropped (EPOCHREALTIME).
progress_hold() {
    [[ -n "${_progress_pid}" ]] || return 0

    sleep "${PROGRESS_HOLD}"
}

# usage: progress_run <label> <command> [argument...]
# Runs the command with the line below it and returns its status. A command that succeeds counts as
# a step that is done. The command is not run in a condition, so errexit and the ERR trap still apply
# inside it: the script's exit handler has to call progress_stop.
progress_run() {
    local label="${1:?label required}" \
          status

    shift

    progress_start "${label}"
    "$@"
    # Reached on failure only when errexit is off.
    status="$?"
    (( status != 0 )) || progress_advance
    progress_hold
    progress_stop

    return "${status}"
}

# usage: progress_logo_load <file>
# Reads the logo and cuts it into its pieces, see PROGRESS_LOGO. What is not a readable file leaves
# no rows: the logo is decoration and must not stop the script.
progress_logo_load() {
    local file="${1:?file required}" \
          start=-1 \
          column \
          filled \
          index \
          row

    PROGRESS_LOGO=()
    PROGRESS_LOGO_WIDTH=0
    PROGRESS_LOGO_BAR=""
    PROGRESS_LOGO_STARTS=()
    PROGRESS_LOGO_LENGTHS=()

    [[ -f "${file}" && -r "${file}" ]] || return 0

    while IFS= read -r row || [[ -n "${row}" ]]; do
        PROGRESS_LOGO+=("${row}")
        (( ${#row} <= PROGRESS_LOGO_WIDTH )) || PROGRESS_LOGO_WIDTH="${#row}"
    done < "${file}"

    printf -v PROGRESS_LOGO_BAR '%*s' "${PROGRESS_LOGO_WIDTH}" ""
    PROGRESS_LOGO_BAR="${PROGRESS_LOGO_BAR// /${PROGRESS_UPPER}}"

    # The column after the last one is blank in every row: it ends the last piece.
    for (( column = 0; column <= PROGRESS_LOGO_WIDTH; column++ )); do
        filled=""
        for (( index = 0; index < ${#PROGRESS_LOGO[@]}; index++ )); do
            filled+="${PROGRESS_LOGO[index]:column:1}"
        done

        if [[ "${filled}" == *[![:space:]]* ]]; then
            (( start >= 0 )) || start="${column}"
        elif (( start >= 0 )); then
            PROGRESS_LOGO_STARTS+=("${start}")
            PROGRESS_LOGO_LENGTHS+=("$(( column - start ))")
            start=-1
        fi
    done
}

# usage: progress_logo_bar <frame> <base>  (the bar as it is at that frame, in REPLY)
# The bar the pieces land on. Its first part, under the first half of the pieces, is there from the
# start. Each later piece brings the part under it when it lands, in its own color: the last piece
# completes the bar. "flash" shows what is there of the bar in the text color.
progress_logo_bar() {
    local frame="${1}" \
          base="${2}" \
          height="${#PROGRESS_LOGO[@]}" \
          pieces="${#PROGRESS_LOGO_STARTS[@]}" \
          color \
          end \
          first \
          piece \
          start

    first=$(( pieces / 2 ))
    REPLY=""

    # The part from the start is taken as the part of the piece before the first later one.
    for (( piece = first - 1; piece < pieces; piece++ )); do
        start=0
        color="${PROGRESS_SGR_SPINNER}"

        (( piece < first )) || {
            (( frame >= (piece + 1) * height )) || break

            start="${PROGRESS_LOGO_STARTS[piece]}"
            color="${PROGRESS_SGR_TRAIL[piece % ${#PROGRESS_THEME_TRAIL[@]}]}"
        }

        # A part ends where the piece after it starts, the last one at the end of the logo.
        end="${PROGRESS_LOGO_WIDTH}"
        (( piece + 1 >= pieces )) || end="${PROGRESS_LOGO_STARTS[piece + 1]}"
        [[ "${base}" != "flash" ]] || color="${PROGRESS_SGR_TEXT}"

        REPLY+="${color}${PROGRESS_LOGO_BAR:start:end - start}${LOG_SGR_RESET}"
    done
}

# usage: progress_logo_frame <frame> <base> [style]  (frame in REPLY)
# The pieces of the logo come down like falling blocks: one after the other, a row per frame, from
# the top of the canvas onto a bar below the logo. Piece p enters with frame p * rows + 1 and rests
# from frame (p + 1) * rows on, so the logo is complete at frame pieces * rows.
# <base> is what the pieces rest on: "bar", "flash" for the bar in the text color, or "none": the
# bar is gone and the logo sits a row lower, in the row of the bar, where it stays.
# A style replaces the colors of the pieces.
progress_logo_frame() {
    local frame="${1}" \
          base="${2}" \
          style="${3:-}" \
          height="${#PROGRESS_LOGO[@]}" \
          canvas="" \
          lowered=0 \
          above \
          color \
          cursor \
          line \
          piece \
          row \
          segment \
          start \
          text

    [[ "${base}" != "none" ]] || lowered=1

    for (( line = 0; line <= height; line++ )); do
        text=""
        cursor=0

        for (( piece = 0; piece < ${#PROGRESS_LOGO_STARTS[@]}; piece++ )); do
            # The rows the piece is still above its place. It is not on the canvas yet while that
            # is its whole height or more: then no row of it falls on a line.
            above=$(( (piece + 1) * height - frame ))
            (( above > 0 )) || above=0
            row=$(( line - lowered + above ))
            (( row >= 0 && row < height )) || continue

            start="${PROGRESS_LOGO_STARTS[piece]}"
            segment="${PROGRESS_LOGO[row]:start:PROGRESS_LOGO_LENGTHS[piece]}"
            # Without the blanks at its end: no line ends in blanks, and the piece after it is set
            # at its own column.
            segment="${segment%"${segment##*[![:space:]]}"}"
            [[ -n "${segment}" ]] || continue

            color="${style:-${PROGRESS_SGR_TRAIL[piece % ${#PROGRESS_THEME_TRAIL[@]}]}}"
            printf -v text '%s%*s%s%s%s' "${text}" "$(( start - cursor ))" "" "${color}" "${segment}" "${LOG_SGR_RESET}"
            cursor=$(( start + ${#segment} ))
        done

        [[ "${base}" == "none" ]] || (( line < height )) || {
            progress_logo_bar "${frame}" "${base}"
            text="${REPLY}"
        }

        [[ -z "${text}" ]] || canvas+="${PROGRESS_INDENT}${text}"
        canvas+="${LOG_NEWLINE}"
    done

    REPLY="${canvas}"
}

# usage: progress_logo_draw <seconds> <frame> <base> [style]
# Draws the frame over the one before it, then waits. The cursor rests below the canvas, so a script
# that is interrupted leaves a clean screen.
progress_logo_draw() {
    local seconds="${1}"

    shift
    progress_logo_frame "$@"
    # Back to the top of the canvas, the logo and the row of the bar, erase to the end of the screen, draw.
    printf '%s[%dA%s[J%s' "${LOG_ESCAPE}" "$(( ${#PROGRESS_LOGO[@]} + 1 ))" "${LOG_ESCAPE}" "${REPLY}" >&2

    sleep "${seconds}"
}

# Plays the logo like falling blocks. The pieces come down one after the other onto the bar, and the
# later ones complete it. The complete bar flickers between its colors and the text color and goes,
# and the logo drops into the row of the bar. There it flickers the same way and stays in the text
# color.
progress_logo_animate() {
    local landed="$(( ${#PROGRESS_LOGO_STARTS[@]} * ${#PROGRESS_LOGO[@]} ))" \
          frame \
          flicker

    # The empty canvas with its bar makes the room that every frame is drawn over.
    progress_logo_frame 0 bar
    printf '%s' "${REPLY}" >&2

    for (( frame = 1; frame < landed; frame++ )); do
        progress_logo_draw "${PROGRESS_LOGO_DELAY}" "${frame}" bar
    done

    for (( flicker = 0; flicker < PROGRESS_LOGO_FLICKERS; flicker++ )); do
        progress_logo_draw "${PROGRESS_LOGO_BLINK}" "${landed}" bar
        progress_logo_draw "${PROGRESS_LOGO_BLINK}" "${landed}" flash
    done

    for (( flicker = 0; flicker < PROGRESS_LOGO_FLICKERS; flicker++ )); do
        progress_logo_draw "${PROGRESS_LOGO_BLINK}" "${landed}" none
        progress_logo_draw "${PROGRESS_LOGO_BLINK}" "${landed}" none "${PROGRESS_SGR_TEXT}"
    done
}

# usage: progress_banner <logo file> <headline> <subtitle>
# Shows the logo, then a blank line, the headline in bold, the subtitle and a blank line. The logo
# is animated on a terminal with room for it and printed at once anywhere else: the text is the
# same, the animated logo ends a row lower.
progress_banner() {
    local file="${1:?logo file required}" \
          headline="${2:?headline required}" \
          subtitle="${3:?subtitle required}" \
          height \
          row

    progress_logo_load "${file}"
    height="${#PROGRESS_LOGO[@]}"

    # Two rows more than the logo: the bar, and the cursor below the canvas. A row that wraps would
    # break the redraw. The pieces are cut by column, which needs a shell that counts characters, not
    # bytes: in a locale without UTF-8 the logo is printed whole.
    if (( height > 0 && ${#PROGRESS_FULL} == 1 )) &&
        progress_room "$(( height + 2 ))" "$(( PROGRESS_LOGO_WIDTH + ${#PROGRESS_INDENT} ))"; then
        progress_logo_animate
    else
        for (( row = 0; row < height; row++ )); do
            printf '%s%s%s%s\n' "${PROGRESS_INDENT}" "${PROGRESS_SGR_TEXT}" "${PROGRESS_LOGO[row]}" "${LOG_SGR_RESET}" >&2
        done
    fi

    printf '\n%s%s%s%s\n%s%s%s%s\n\n' \
        "${PROGRESS_INDENT}" "${PROGRESS_SGR_TITLE}" "${headline}" "${LOG_SGR_RESET}" \
        "${PROGRESS_INDENT}" "${PROGRESS_SGR_EMPTY}" "${subtitle}" "${LOG_SGR_RESET}" >&2
}

# True when a question can be asked: the terminal shows it and the answer is typed there.
progress_interactive() {
    [[ -t 0 ]] && log_stderr_is_terminal
}

# usage: progress_confirm <question> <yes label> <no label>
# Shows both choices and reads one key. Enter, y and Y say yes, the default. n and N say no. Any
# other key is skipped. True for yes. Without a terminal nothing is asked and the answer is yes: a
# pipe or a job cannot type. No when the input ends before an answer.
progress_confirm() {
    local question="${1:?question required}" \
          yes="${2:?yes label required}" \
          no="${3:?no label required}" \
          answer=1 \
          key

    progress_interactive || return 0

    printf '%s%s%s\n\n' "${PROGRESS_SGR_TITLE}" "${question}" "${LOG_SGR_RESET}" >&2
    printf '%s%s%-4s%s %s%s%s %s(default)%s\n' \
        "${PROGRESS_INDENT}" "${PROGRESS_SGR_KEY}" "y" "${LOG_SGR_RESET}" \
        "${PROGRESS_SGR_YES}" "${yes}" "${LOG_SGR_RESET}" \
        "${PROGRESS_SGR_EMPTY}" "${LOG_SGR_RESET}" >&2
    printf '%s%s%-4s%s %s%s%s\n' \
        "${PROGRESS_INDENT}" "${PROGRESS_SGR_KEY}" "n" "${LOG_SGR_RESET}" \
        "${PROGRESS_SGR_EMPTY}" "${no}" "${LOG_SGR_RESET}" >&2

    while IFS= read -r -s -n 1 key; do
        case "${key}" in
            "" | y | Y)
                answer=0

                break
                ;;
            n | N) break ;;
        esac
    done

    # The key is not shown: a blank line sets what follows apart from the choices.
    printf '\n' >&2

    return "${answer}"
}

progress_set_styles

#!/usr/bin/env bash

set -uo pipefail

# Enhanced Claude Code Statusline
# Matches Starship prompt visual style with Catppuccin Mocha colors

# Catppuccin Mocha palette (ANSI true color)
reset=$'\033[0m'
blue=$'\033[38;2;137;180;250m'
green=$'\033[38;2;166;227;161m'
sky=$'\033[38;2;137;220;235m'
lavender=$'\033[38;2;180;190;254m'
mauve=$'\033[38;2;203;166;247m'
peach=$'\033[38;2;250;179;135m'
text=$'\033[38;2;205;214;244m'
yellow=$'\033[38;2;249;226;175m'

# Read input from Claude Code
input=$(cat)
cwd=$(printf '%s' "${input}" | jq -r '.workspace.current_dir // empty')

# Fallback if no cwd
if [[ -z "${cwd}" ]]; then
  cwd=$(pwd)
fi

# --- Functions ---

get_os_symbol() {
  case "$(uname -s)" in
    Darwin) printf '%s' "${blue} 󰀵${reset}" ;;
    Linux)  printf '%s' "${blue}󰌽${reset}" ;;
    *)      printf '%s' "${blue}󰍲${reset}" ;;
  esac
}

get_username() {
  printf '%s' "${lavender}${USER:-$(whoami)}${reset}"
}

get_directory() {
  local dir="${1}"
  local home_symbol="  ~"

  # Replace home with symbol
  if [[ "${dir}" == "${HOME}"* ]]; then
    dir="${home_symbol}${dir#${HOME}}"
  fi

  # Truncate to last 3 parts (Bash 3.2 compatible)
  local IFS='/'
  local parts
  read -ra parts <<< "${dir}"
  local len=${#parts[@]}

  if [[ ${len} -gt 4 ]]; then
    dir="…/${parts[$((len-3))]}/${parts[$((len-2))]}/${parts[$((len-1))]}"
  fi

  printf '%s' "${blue}  ${dir}${reset}"
}

get_git_info() {
  local cwd="${1}"
  local result=""

  # Check if in git repo
  if ! git -C "${cwd}" rev-parse --git-dir > /dev/null 2>&1; then
    return
  fi

  # Get branch or commit hash (detached HEAD)
  local branch
  branch=$(git -C "${cwd}" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
  if [[ -z "${branch}" ]]; then
    # Detached HEAD - show commit hash
    local commit
    commit=$(git -C "${cwd}" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
    if [[ -n "${commit}" ]]; then
      result="${green}  ${peach}${commit}${reset}"
    fi
  else
    result="${green}  ${branch}${reset}"
  fi

  # Git status indicators
  local status_output
  status_output=$(git -C "${cwd}" --no-optional-locks status --porcelain=v1 -b 2>/dev/null)

  local ahead=0 behind=0 modified=0 staged=0 untracked=0

  # Parse ahead/behind from first line
  local first_line
  first_line=$(printf '%s' "${status_output}" | head -n1)
  if [[ "${first_line}" =~ \[ahead\ ([0-9]+) ]]; then
    ahead=${BASH_REMATCH[1]}
  fi
  if [[ "${first_line}" =~ behind\ ([0-9]+) ]]; then
    behind=${BASH_REMATCH[1]}
  fi

  # Count file statuses
  while IFS= read -r line; do
    [[ -z "${line}" || "${line}" == \#\#* ]] && continue
    local index="${line:0:1}"
    local worktree="${line:1:1}"

    # Staged changes (index has changes)
    if [[ "${index}" =~ [MADRC] ]]; then
      ((staged++))
    fi
    # Modified in worktree
    if [[ "${worktree}" == "M" ]]; then
      ((modified++))
    fi
    # Untracked
    if [[ "${index}" == "?" ]]; then
      ((untracked++))
    fi
  done <<< "${status_output}"

  # Build status string
  local status_str=""
  if [[ ${ahead} -gt 0 ]]; then
    status_str+="${mauve}⇡${ahead}${reset}"
  fi
  if [[ ${behind} -gt 0 ]]; then
    status_str+="${mauve}⇣${behind}${reset}"
  fi
  if [[ ${staged} -gt 0 ]]; then
    status_str+="${green}++(${staged})${reset}"
  fi
  if [[ ${modified} -gt 0 ]]; then
    status_str+="${yellow} ${modified}${reset}"
  fi
  if [[ ${untracked} -gt 0 ]]; then
    status_str+="${peach} ${untracked}${reset}"
  fi

  if [[ -n "${status_str}" ]]; then
    result+=" ${status_str}"
  fi

  printf '%s' "${result}"
}

get_language() {
  local cwd="${1}"
  local result=""

  # Go
  if [[ -f "${cwd}/go.mod" ]]; then
    result+="${sky}  ${reset}"
  fi

  # Rust
  if [[ -f "${cwd}/Cargo.toml" ]]; then
    result+="${peach} ${reset}"
  fi

  # Zig
  if [[ -f "${cwd}/build.zig" ]]; then
    result+="${peach}  ${reset}"
  fi

  # Lua (check for lua files or config)
  if [[ -f "${cwd}/.luarc.json" ]] || ls "${cwd}"/*.lua > /dev/null 2>&1; then
    result+="${blue}  ${reset}"
  fi

  # PHP
  if [[ -f "${cwd}/composer.json" ]]; then
    result+="${lavender}🐘 ${reset}"
  fi

  # Node.js
  if [[ -f "${cwd}/package.json" ]]; then
    result+="${green}󰎙 ${reset}"
  fi

  # Python
  if [[ -f "${cwd}/pyproject.toml" ]] || [[ -f "${cwd}/setup.py" ]] || [[ -f "${cwd}/requirements.txt" ]]; then
    result+="${yellow} ${reset}"
  fi

  printf '%s' "${result}"
}

get_docker_k8s() {
  local cwd="${1}"
  local result=""

  # Docker
  if [[ -f "${cwd}/compose.yaml" ]] || [[ -f "${cwd}/docker-compose.yml" ]] || [[ -f "${cwd}/docker-compose.yaml" ]] || [[ -f "${cwd}/Dockerfile" ]]; then
    local docker_ctx
    docker_ctx=$(docker context show 2>/dev/null || echo "default")
    result+="${sky}  ${docker_ctx}${reset} "
  fi

  # Kubernetes (only if Docker files present)
  if [[ -f "${cwd}/Dockerfile" ]] && command -v kubectl > /dev/null 2>&1; then
    local k8s_ctx k8s_ns
    k8s_ctx=$(kubectl config current-context 2>/dev/null || true)
    if [[ -n "${k8s_ctx}" ]]; then
      k8s_ns=$(kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null || echo "default")
      result+="${blue}☸ ${k8s_ctx}${reset}"
      if [[ -n "${k8s_ns}" && "${k8s_ns}" != "default" ]]; then
        result+=" ${text}(${k8s_ns})${reset}"
      fi
    fi
  fi

  printf '%s' "${result}"
}

get_memory() {
  local mem_pct
  if [[ "$(uname -s)" == "Darwin" ]]; then
    # macOS: use vm_stat
    local page_size pages_active pages_wired total_mem used_mem
    page_size=$(pagesize)
    pages_active=$(vm_stat | awk '/Pages active/ {gsub(/\./,""); print $3}')
    pages_wired=$(vm_stat | awk '/Pages wired/ {gsub(/\./,""); print $4}')

    total_mem=$(sysctl -n hw.memsize)
    used_mem=$(( (pages_active + pages_wired) * page_size ))
    mem_pct=$(( used_mem * 100 / total_mem ))
  else
    # Linux: use /proc/meminfo
    mem_pct=$(awk '/MemTotal/ {total=$2} /MemAvailable/ {avail=$2} END {printf "%.0f", (1-avail/total)*100}' /proc/meminfo 2>/dev/null || echo "0")
  fi

  # Only show if above threshold (85%)
  if [[ ${mem_pct} -ge 85 ]]; then
    printf '%s' "${yellow}🐏 ${mem_pct}%%${reset}"
  fi
}

get_time() {
  printf '%s' "${text}  $(date +%R)${reset}"
}

# --- Build Status Line ---

os_symbol=$(get_os_symbol)
user_info=$(get_username)
dir_info=$(get_directory "${cwd}")
git_info=$(get_git_info "${cwd}")
lang_info=$(get_language "${cwd}")
docker_k8s=$(get_docker_k8s "${cwd}")
memory_info=$(get_memory)
time_info=$(get_time)

# Left side: OS | User | Dir | Lang | Docker/K8s | Git
left="${os_symbol} ${user_info}  ${dir_info}"

if [[ -n "${lang_info}" ]]; then
  left+=" ${lang_info}"
fi

if [[ -n "${docker_k8s}" ]]; then
  left+=" ${docker_k8s}"
fi

if [[ -n "${git_info}" ]]; then
  left+=" ${git_info}"
fi

# Right side: Memory | Time
right=""
if [[ -n "${memory_info}" ]]; then
  right+="${memory_info} "
fi
right+="${time_info}"

# Output with spacing
printf '%s   %s' "${left}" "${right}"

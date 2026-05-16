#!/bin/bash

# Claude Code Status Line
# Single line: directory | session | branch | git stats | context% | model | cost | time

# Read JSON input from stdin
input=$(cat)

# Extract values using jq
PROJECT_DIR=$(echo "$input" | jq -r '.workspace.project_dir // empty')
CURRENT_DIR=$(echo "$input" | jq -r '.workspace.current_dir // empty')
COST_USD=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
MODEL_NAME=$(echo "$input" | jq -r '.model.display_name // empty')
SESSION_NAME=$(echo "$input" | jq -r '.session_name // empty')
FIVE_HOUR_PCT=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
FIVE_HOUR_RESETS=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
SEVEN_DAY_PCT=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
SEVEN_DAY_RESETS=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

# Get directory names
PROJECT_NAME=$(basename "$PROJECT_DIR")

# Calculate relative path from project to current dir
RELATIVE_DIR=""
if [ -n "$PROJECT_DIR" ] && [ -n "$CURRENT_DIR" ] && [ "$PROJECT_DIR" != "$CURRENT_DIR" ]; then
    RELATIVE_DIR="${CURRENT_DIR#$PROJECT_DIR/}"
fi

# Git directory for all git operations
GIT_DIR="${PROJECT_DIR:-$CURRENT_DIR}"

# Get git branch
GIT_BRANCH=""
if [ -d "${GIT_DIR}/.git" ] || git -C "${GIT_DIR}" rev-parse --git-dir >/dev/null 2>&1; then
    GIT_BRANCH=$(git -C "${GIT_DIR}" rev-parse --abbrev-ref HEAD 2>/dev/null)
fi

# Get context percentage with color coding
CONTEXT_PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d'.' -f1)
[ -z "$CONTEXT_PCT" ] && CONTEXT_PCT=0

if [ "$CONTEXT_PCT" -ge 70 ]; then
    CTX_COLOR="\033[31m"  # Red
elif [ "$CONTEXT_PCT" -ge 50 ]; then
    CTX_COLOR="\033[33m"  # Yellow
else
    CTX_COLOR="\033[32m"  # Green
fi
RESET="\033[0m"
DIM="\033[2m"
CYAN="\033[36m"
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
BLUE="\033[1;34m"      # Bright blue for directory
MAGENTA="\033[1;35m"   # Bright magenta for branch
PURPLE="\033[35m"      # Softer purple for session name
BRIGHT_CYAN="\033[1;36m" # Bright cyan for new/untracked files

get_context_bar() {
    local PCT=$1
    local FILLED=$(( PCT * 10 / 100 ))
    [ $FILLED -gt 10 ] && FILLED=10
    local EMPTY=$(( 10 - FILLED ))
    local BAR="" i=0
    while [ $i -lt $FILLED ]; do BAR="${BAR}█"; i=$((i+1)); done
    i=0
    while [ $i -lt $EMPTY ]; do BAR="${BAR}░"; i=$((i+1)); done
    echo "$BAR"
}

# Get token counts for display
INPUT_TOKENS=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
OUTPUT_TOKENS=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')
CACHE_READ=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')

# Format cost or token count
COST_CENTS=$(awk "BEGIN {printf \"%.0f\", $COST_USD * 100}" 2>/dev/null)
[ -z "$COST_CENTS" ] && COST_CENTS=0

if [ "$COST_CENTS" -eq 0 ]; then
    TOTAL_TOKENS=$((INPUT_TOKENS + OUTPUT_TOKENS + CACHE_READ))
    if [ "$TOTAL_TOKENS" -ge 1000000 ]; then
        TOKEN_DISPLAY=$(awk "BEGIN {printf \"%.1fM\", $TOTAL_TOKENS / 1000000}")
    elif [ "$TOTAL_TOKENS" -ge 1000 ]; then
        TOKEN_DISPLAY=$(awk "BEGIN {printf \"%.1fK\", $TOTAL_TOKENS / 1000}")
    else
        TOKEN_DISPLAY="${TOTAL_TOKENS}"
    fi
    COST_DISPLAY="${TOKEN_DISPLAY} tok"
elif [ "$COST_CENTS" -ge 100 ]; then
    COST_DISPLAY=$(awk "BEGIN {printf \"\$%.2f\", $COST_CENTS / 100}")
else
    COST_DISPLAY="${COST_CENTS}c"
fi

# Git diff stats (inline, compact)
get_git_diff_stats() {
    if [ -z "$GIT_BRANCH" ]; then
        echo ""
        return
    fi

    STAGED=$(git -C "${GIT_DIR}" diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
    UNSTAGED=$(git -C "${GIT_DIR}" diff --numstat 2>/dev/null | wc -l | tr -d ' ')
    UNTRACKED=$(git -C "${GIT_DIR}" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')

    STAGED_STATS=$(git -C "${GIT_DIR}" diff --cached --shortstat 2>/dev/null)
    UNSTAGED_STATS=$(git -C "${GIT_DIR}" diff --shortstat 2>/dev/null)

    STAGED_ADD=$(echo "$STAGED_STATS" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || echo "0")
    STAGED_DEL=$(echo "$STAGED_STATS" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+' || echo "0")
    UNSTAGED_ADD=$(echo "$UNSTAGED_STATS" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || echo "0")
    UNSTAGED_DEL=$(echo "$UNSTAGED_STATS" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+' || echo "0")

    [ -z "$STAGED_ADD" ] && STAGED_ADD=0
    [ -z "$STAGED_DEL" ] && STAGED_DEL=0
    [ -z "$UNSTAGED_ADD" ] && UNSTAGED_ADD=0
    [ -z "$UNSTAGED_DEL" ] && UNSTAGED_DEL=0

    TOTAL_ADD=$((STAGED_ADD + UNSTAGED_ADD))
    TOTAL_DEL=$((STAGED_DEL + UNSTAGED_DEL))

    local OUTPUT=""

    if [ "$STAGED" -gt 0 ] 2>/dev/null; then
        OUTPUT="${GREEN}✓${STAGED}${RESET}"
    fi
    if [ "$UNSTAGED" -gt 0 ] 2>/dev/null; then
        OUTPUT="${OUTPUT:+$OUTPUT }${YELLOW}!${UNSTAGED}${RESET}"
    fi
    if [ "$UNTRACKED" -gt 0 ] 2>/dev/null; then
        OUTPUT="${OUTPUT:+$OUTPUT }${BRIGHT_CYAN}+${UNTRACKED}${RESET}"
    fi
    if [ "$TOTAL_ADD" -gt 0 ] || [ "$TOTAL_DEL" -gt 0 ]; then
        OUTPUT="${OUTPUT:+$OUTPUT }${GREEN}+${TOTAL_ADD}${RESET}${RED}-${TOTAL_DEL}${RESET}"
    fi

    echo "$OUTPUT"
}

CONTEXT_BAR=$(get_context_bar "$CONTEXT_PCT")
CURRENT_TIME=$(date +%H:%M)
GIT_STATS=$(get_git_diff_stats)

# ============ Single status line ============
LINE=""

# Directory - bright blue
if [ -n "$RELATIVE_DIR" ]; then
    LINE="${LINE}📁 ${BLUE}${PROJECT_NAME}/${RELATIVE_DIR}${RESET}"
else
    LINE="${LINE}📁 ${BLUE}${PROJECT_NAME}${RESET}"
fi

# Session name (optional)
if [ -n "$SESSION_NAME" ]; then
    LINE="${LINE} | 💬 ${PURPLE}\033[3m${SESSION_NAME}${RESET}"
fi

# Git branch + inline diff stats
if [ -n "$GIT_BRANCH" ]; then
    LINE="${LINE} | 🌿 ${MAGENTA}${GIT_BRANCH}${RESET}"
    if [ -n "$GIT_STATS" ]; then
        LINE="${LINE} ${GIT_STATS}"
    fi
fi

# Context percentage
LINE="${LINE} | ${CTX_COLOR}[${CONTEXT_BAR}] ${CONTEXT_PCT}%${RESET}"

# Model
LINE="${LINE} | 🤖 ${MODEL_NAME}"

# Cost/tokens
if [ "$COST_CENTS" -eq 0 ]; then
    LINE="${LINE} | 🔢 ${COST_DISPLAY}"
else
    LINE="${LINE} | 💰 ${COST_DISPLAY}"
fi

# Rate limits
format_reset_short() {
    local resets_at=$1
    local max_days=$2
    [ -z "$resets_at" ] && return
    local now secs_left
    now=$(date +%s)
    secs_left=$(( resets_at - now ))
    [ "$secs_left" -le 0 ] && echo "now" && return
    if [ "$max_days" -gt 1 ]; then
        local days=$(( secs_left / 86400 ))
        local hours=$(( (secs_left % 86400) / 3600 ))
        [ "$days" -gt 0 ] && echo "${days}d${hours}h" || echo "${hours}h"
    else
        local hours=$(( secs_left / 3600 ))
        local mins=$(( (secs_left % 3600) / 60 ))
        [ "$hours" -gt 0 ] && echo "${hours}h${mins}m" || echo "${mins}m"
    fi
}

if [ -n "$FIVE_HOUR_PCT" ] || [ -n "$SEVEN_DAY_PCT" ]; then
    RATE_PARTS=""
    if [ -n "$FIVE_HOUR_PCT" ]; then
        FIVE_RESET=$(format_reset_short "$FIVE_HOUR_RESETS" 1)
        RATE_PARTS="${FIVE_HOUR_PCT}%${FIVE_RESET:+ $FIVE_RESET}"
    fi
    if [ -n "$SEVEN_DAY_PCT" ]; then
        SEVEN_RESET=$(format_reset_short "$SEVEN_DAY_RESETS" 7)
        RATE_PARTS="${RATE_PARTS:+$RATE_PARTS / }${SEVEN_DAY_PCT}%${SEVEN_RESET:+ $SEVEN_RESET}"
    fi
    LINE="${LINE} | 📊 ${RATE_PARTS}"
fi

LINE="${LINE} | 🕐 ${CURRENT_TIME}"

printf "%b" "$LINE"


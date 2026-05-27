#!/bin/bash
# OpenRouter CLI Chat in BASH
# License: Apache-2.0
# Usage: ./ai.sh to start interactive terminal chatbot
# Optional: Run with DEBUG=true to enable detailed error debugging, e.g.:
# DEBUG=true ./ai.sh


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHAT_LOG_DIR="$SCRIPT_DIR/chat_sessions"
DATE_STR=$(date '+%Y-%m-%d_%H-%M-%S')
SESSION_FILE="$CHAT_LOG_DIR/session_$DATE_STR.txt"

# Option handling with case statement
case "$1" in
  -u|--update)
    echo "🔄 Updating ai.sh to the latest version..."
    cd "$SCRIPT_DIR" && git pull
    exit $?
    ;;
  -h|--help)
    echo -e "\nOpenRouter CLI Chat Usage:\n"
    echo "  ./ai.sh                Start interactive chat"
    echo "  ./ai.sh --update       Update repository (git pull)"
    echo "  ./ai.sh -h, --help     Show this help message"
    echo -e "\nEnvironment setup:"
    echo "  cp .env.example .env   # Create your .env file"
    echo "  Edit .env and add your OPENROUTER_API_KEY and optionally OPENROUTER_MODEL."
    echo "  See .models for available models."
    exit 0
    ;;
esac
check_dependency() {
  local cmd=$1
  local pkg=$2

  if ! command -v "$cmd" &> /dev/null; then
    echo "🚫 Missing dependency: $cmd"

    if [[ "$(uname)" == "Darwin" ]]; then
      echo "Try: brew install $pkg and come back!"
      exit 1
    elif command -v pacman &> /dev/null; then
      echo "Try: sudo pacman -S $pkg and come back!"
      exit 1
    elif command -v apt &> /dev/null; then
      echo "Try: sudo apt install $pkg and come back!"
      exit 1
    elif command -v dnf &> /dev/null; then
      echo "Try: sudo dnf install $pkg and come back!"
      exit 1
    elif command -v yum &> /dev/null; then
      echo "Try: sudo yum install $pkg and come back!"
      exit 1
    elif command -v zypper &> /dev/null; then
      echo "Try: sudo zypper install $pkg and come back!"
      exit 1
    else
      echo "Come back when you install $cmd!"
      exit 1
    fi

  fi
}

# Checking dependencies
check_dependency curl curl
check_dependency jq jq

# Load .env file
if [[ -f "$SCRIPT_DIR/.env" ]]; then
  source "$SCRIPT_DIR/.env"
else
  echo "❌ .env file not found in $SCRIPT_DIR"
  exit 1
fi

# Check API Key
if [[ -z "$OPENROUTER_API_KEY" ]]; then
  echo "❌ The OPENROUTER_API_KEY is missing from .env file."
  exit 1
fi

# Default AI Model
if [[ -z "$OPENROUTER_MODEL" ]]; then
  OPENROUTER_MODEL="meta-llama/llama-3.3-70b-instruct:free"
fi

mkdir -p "$CHAT_LOG_DIR"

# Initialize conversation history array
CHAT_HISTORY=()

echo -e "\n💬 Start a conversation! Type your message and press Enter (Ctrl+C for exit)\n"

# If DEBUG is true, print debug information
DEBUG=${DEBUG:-false}
if [[ "$DEBUG" == "true" ]]; then
  echo "🔍 Debugging is enabled"
fi

# Set default user name if not provided
USER=${USER:-user}

# Thinking spinner shown while waiting for API response
_spinner() {
  local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  while true; do
    for frame in "${frames[@]}"; do
      printf "\r\033[2m🤖 %s\033[0m" "$frame"
      sleep 0.08
    done
  done
}

while true; do
  # Interactive user input
  read -e -p "🧑 $USER: " USER_INPUT

  # Skip iteration if input is empty
  [[ -z "$USER_INPUT" ]] && continue

  # Append the user’s input to the chat history array
  CHAT_HISTORY+=("$USER_INPUT")

  # Build JSON array of messages alternating roles (user/assistant) from chat history, escaping quotes properly
  JSON_MESSAGES="["
  for ((i=0; i<${#CHAT_HISTORY[@]}; i++)); do
    if (( i % 2 == 0 )); then
      ROLE="user"
    else
      ROLE="assistant"
    fi
    ESCAPED=$(printf "%s" "${CHAT_HISTORY[i]}" | sed 's/"/\\"/g')
    JSON_MESSAGES+="{\"role\":\"$ROLE\",\"content\":[{\"type\":\"text\",\"text\":\"$ESCAPED\"}]},"
  done
  JSON_MESSAGES="${JSON_MESSAGES%,}]"

  # Show thinking spinner while waiting for API response
  _spinner &
  SPINNER_PID=$!

  # API request
  RESPONSE=$(curl -s https://openrouter.ai/api/v1/chat/completions \
    -H "Authorization: Bearer $OPENROUTER_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{
      \"model\": \"$OPENROUTER_MODEL\",
      \"messages\": $JSON_MESSAGES
    }")

  # Stop spinner and clear the line
  kill "$SPINNER_PID" 2>/dev/null
  wait "$SPINNER_PID" 2>/dev/null
  printf "\r\033[K"

  # Check for API errors; if found, show error message and, if DEBUG=true, display full JSON response for troubleshooting.
  # Skip saving error responses to chat history.
  ERROR_MSG=$(echo "$RESPONSE" | jq -r '.error.message // empty')
  if [[ -n "$ERROR_MSG" ]]; then
    ERROR_RAW=$(echo "$RESPONSE" | jq -r '.error.metadata.raw // empty')
    echo -e "\n❌ API Error: $ERROR_MSG"
    [[ -n "$ERROR_RAW" ]] && echo -e "   ↳ $ERROR_RAW"
    echo
    if [[ "$DEBUG" == "true" ]]; then
      echo "🔍 Full response for debugging:"
      echo "$RESPONSE" | jq .
    fi
    continue
  fi

  # Extract the AI's reply text from the JSON response
  BOT_REPLY=$(echo "$RESPONSE" | jq -r '.choices[0].message.content')

  # Extract AI Model name for display purposes

  BOT_NAME_RAW="$OPENROUTER_MODEL"
  BOT_NAME_WITH_DASHES="${BOT_NAME_RAW#*/}"
  BOT_NAME_WITH_DASHES="${BOT_NAME_WITH_DASHES%%:*}"
  BOT_NAME="${BOT_NAME_WITH_DASHES%%-*}"
  BOT_DISPLAY_NAME="$(tr '[:lower:]' '[:upper:]' <<< "${BOT_NAME:0:1}")${BOT_NAME:1} AI"

  # Print the AI response to the terminal with formatting
  echo -e "\n\033[1;32m🤖 $BOT_DISPLAY_NAME:\033[0m\n"
  TERM_WIDTH=$(tput cols 2>/dev/null || echo 100)
  echo "$BOT_REPLY" | fold -s -w "$TERM_WIDTH"
  echo


  # Append the current exchange to the session file (user + AI reply)
  {
    echo "🧑 $USER: $USER_INPUT"
    echo
    echo "🤖 $BOT_DISPLAY_NAME:"
    echo
    echo "$BOT_REPLY" | fold -s -w 100
    echo "------------------------------------------------------------"
  } >> "$SESSION_FILE"

  # Add the AI reply to the chat history array for context
  CHAT_HISTORY+=("$BOT_REPLY")
done

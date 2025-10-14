#!/usr/bin/env bash
set -euo pipefail

# Usage: ./bin/start.sh [path_to_env_file]
ENV_FILE=${1:-.env}

if [ -f "$ENV_FILE" ]; then
  echo "Loading environment from $ENV_FILE"
  # shellcheck disable=SC2162
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|\#*) continue ;;
    esac
    if [[ "$line" == *"="* ]]; then
      key="${line%%=*}"
      value="${line#*=}"
      key="$(echo "$key" | sed -e 's/^ *//' -e 's/ *$//')"
      value="$(echo "$value" | sed -e 's/^ *//' -e 's/ *$//')"
      if [[ "$value" =~ ^\".*\"$ ]]; then
        value="${value:1:${#value}-2}"
      elif [[ "$value" =~ ^\'.*\'$ ]]; then
        value="${value:1:${#value}-2}"
      fi
      export "$key=$value"
    fi
  done < "$ENV_FILE"
else
  echo "No $ENV_FILE found, continuing with existing environment"
fi

export MIX_ENV=${MIX_ENV:-prod}

: "${N2TG_TG_BOT_TOKEN:?Set N2TG_TG_BOT_TOKEN}"
: "${N2TG_TG_CHAT_ID:?Set N2TG_TG_CHAT_ID}"

if [ -x "/app/nostr2tg/bin/nostr2tg" ]; then
  exec /app/nostr2tg/bin/nostr2tg start
elif [ -x "./_build/prod/rel/nostr2tg/bin/nostr2tg" ]; then
  exec ./_build/prod/rel/nostr2tg/bin/nostr2tg start
else
  echo "Release not found, starting with mix (dev use)"
  exec mix run --no-halt
fi

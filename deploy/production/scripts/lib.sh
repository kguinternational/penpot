#!/usr/bin/env bash
# Shared shell helpers for Penpot 24/7 production scripts.

load_env_file() {
  local env_file="${1:-}"
  if [[ -z "${env_file}" || ! -f "${env_file}" ]]; then
    echo "ERROR: Environment file '${env_file}' not found." >&2
    return 1
  fi

  local line key val
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%$'\r'}"
    # Trim leading whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    # Skip empty lines and comments
    [[ -z "${line}" || "${line}" == \#* ]] && continue

    if [[ "${line}" != *=* ]]; then
      echo "ERROR: Invalid line in ${env_file}: ${line}" >&2
      return 1
    fi

    key="${line%%=*}"
    val="${line#*=}"

    # Trim trailing whitespace on key
    key="${key%"${key##*[![:space:]]}"}"

    if [[ ! "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      echo "ERROR: Invalid variable name '${key}' in ${env_file}" >&2
      return 1
    fi

    # Strip matching single or double surrounding quotes
    if [[ "${#val}" -ge 2 ]]; then
      if [[ "${val:0:1}" == '"' && "${val: -1}" == '"' ]]; then
        val="${val:1:${#val}-2}"
      elif [[ "${val:0:1}" == "'" && "${val: -1}" == "'" ]]; then
        val="${val:1:${#val}-2}"
      fi
    fi

    export "${key}=${val}"
  done < "${env_file}"
}

dc() {
  docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" "$@"
}

sha256_gen() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$@"
  else
    shasum -a 256 "$@"
  fi
}

sha256_check() {
  local sum_file="${1:?checksum file required}"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c "${sum_file}"
  else
    shasum -a 256 -c "${sum_file}"
  fi
}

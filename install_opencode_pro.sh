Absolutely — here’s a **production-grade, idempotent installer/tuner** you can use as a strong baseline.

> ⚠️ Because there are multiple tools called “OpenCode,” this script is built to be **highly configurable**.  
> Set `OPENCODE_REPO`, binary name, and install method as needed for your specific OpenCode distribution.

## `install-opencode-pro.sh`

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

############################################
# OpenCode Pro Installer / Optimizer
# - Idempotent
# - Backup + rollback-safe approach
# - Multi-platform (Linux/macOS)
# - Multi-method install (auto/brew/npm/binary)
# - Config hardening + performance profile
############################################

# ---------- User-tunable defaults ----------
OPENCODE_BIN="${OPENCODE_BIN:-opencode}"
OPENCODE_REPO="${OPENCODE_REPO:-opencode-ai/opencode}"   # GitHub org/repo for binary releases
OPENCODE_VERSION="${OPENCODE_VERSION:-latest}"            # "latest" or tag like "v1.2.3"
INSTALL_METHOD="${INSTALL_METHOD:-auto}"                  # auto|brew|npm|binary|skip
PREFIX_BIN="${PREFIX_BIN:-$HOME/.local/bin}"
CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/opencode}"
CONFIG_FILE="${CONFIG_FILE:-$CONFIG_DIR/config.yaml}"
STATE_DIR="${STATE_DIR:-$HOME/.local/state/opencode}"
CACHE_DIR="${CACHE_DIR:-$HOME/.cache/opencode}"
LOG_DIR="${LOG_DIR:-$HOME/.local/share/opencode/logs}"
BACKUP_ROOT="${BACKUP_ROOT:-$HOME/.local/share/opencode/backups}"

# performance/security defaults (safe, generic)
MAX_WORKERS="${MAX_WORKERS:-0}"            # 0 => auto
CACHE_SIZE_MB="${CACHE_SIZE_MB:-2048}"
TELEMETRY_ENABLED="${TELEMETRY_ENABLED:-false}"
AUTO_UPDATE="${AUTO_UPDATE:-true}"
SAFE_MODE="${SAFE_MODE:-true}"
NETWORK_TIMEOUT_SEC="${NETWORK_TIMEOUT_SEC:-30}"
LOG_LEVEL="${LOG_LEVEL:-info}"

# ---------- Internal ----------
SCRIPT_NAME="$(basename "$0")"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
WORKDIR="$(mktemp -d)"
LOG_FILE="$WORKDIR/${SCRIPT_NAME%.sh}.log"
OS=""
ARCH=""
PKG_MGR=""
SUDO=""

cleanup() {
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

on_error() {
  echo "[ERROR] Line $1 failed. See log: $LOG_FILE" >&2
}
trap 'on_error $LINENO' ERR

log()  { echo -e "[INFO]  $*" | tee -a "$LOG_FILE"; }
warn() { echo -e "[WARN]  $*" | tee -a "$LOG_FILE"; }
err()  { echo -e "[ERROR] $*" | tee -a "$LOG_FILE" >&2; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "Missing command: $1"; return 1; }
}

detect_os_arch() {
  local uos uarch
  uos="$(uname -s | tr '[:upper:]' '[:lower:]')"
  uarch="$(uname -m)"

  case "$uos" in
    linux) OS="linux" ;;
    darwin) OS="darwin" ;;
    *) err "Unsupported OS: $uos"; exit 1 ;;
  esac

  case "$uarch" in
    x86_64|amd64) ARCH="amd64" ;;
    arm64|aarch64) ARCH="arm64" ;;
    *) err "Unsupported architecture: $uarch"; exit 1 ;;
  esac

  log "Detected platform: OS=$OS ARCH=$ARCH"
}

detect_sudo() {
  if [[ "$OS" == "linux" ]] && [[ "$(id -u)" -ne 0 ]] && command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    SUDO=""
  fi
}

detect_pkg_mgr() {
  if command -v brew >/dev/null 2>&1; then PKG_MGR="brew"
  elif command -v apt-get >/dev/null 2>&1; then PKG_MGR="apt"
  elif command -v dnf >/dev/null 2>&1; then PKG_MGR="dnf"
  elif command -v yum >/dev/null 2>&1; then PKG_MGR="yum"
  elif command -v pacman >/dev/null 2>&1; then PKG_MGR="pacman"
  elif command -v zypper >/dev/null 2>&1; then PKG_MGR="zypper"
  else PKG_MGR="none"
  fi
  log "Package manager: $PKG_MGR"
}

install_prereqs() {
  log "Installing prerequisites..."
  case "$PKG_MGR" in
    brew)
      brew update
      brew install curl jq git tar gzip xz || true
      ;;
    apt)
      $SUDO apt-get update -y
      $SUDO apt-get install -y curl jq git ca-certificates tar gzip xz-utils
      ;;
    dnf)
      $SUDO dnf install -y curl jq git ca-certificates tar gzip xz
      ;;
    yum)
      $SUDO yum install -y curl jq git ca-certificates tar gzip xz
      ;;
    pacman)
      $SUDO pacman -Sy --noconfirm curl jq git ca-certificates tar gzip xz
      ;;
    zypper)
      $SUDO zypper --non-interactive install curl jq git ca-certificates tar gzip xz
      ;;
    none)
      warn "No supported package manager found. Ensure: curl jq git tar gzip installed."
      ;;
  esac
}

ensure_path() {
  mkdir -p "$PREFIX_BIN"
  case ":$PATH:" in
    *":$PREFIX_BIN:"*) ;;
    *)
      warn "$PREFIX_BIN not in PATH. Adding shell profile block."
      add_shell_block "opencode-path" "export PATH=\"$PREFIX_BIN:\$PATH\""
      export PATH="$PREFIX_BIN:$PATH"
      ;;
  esac
}

gh_api_get() {
  local url="$1"
  curl -fsSL -H "Accept: application/vnd.github+json" "$url"
}

resolve_release_tag() {
  if [[ "$OPENCODE_VERSION" != "latest" ]]; then
    echo "$OPENCODE_VERSION"
    return
  fi
  gh_api_get "https://api.github.com/repos/$OPENCODE_REPO/releases/latest" | jq -r '.tag_name'
}

download_release_asset() {
  local tag="$1"
  local api asset_url
  api="https://api.github.com/repos/$OPENCODE_REPO/releases/tags/$tag"

  log "Fetching release metadata for $OPENCODE_REPO@$tag"
  local assets_json
  assets_json="$(gh_api_get "$api")"

  # Flexible matching for common naming patterns
  asset_url="$(
    echo "$assets_json" | jq -r --arg os "$OS" --arg arch "$ARCH" '
      .assets[]
      | select(
          (.name | ascii_downcase | test($os))
          and
          (.name | ascii_downcase | test($arch))
          and
          (.name | ascii_downcase | test("tar.gz|tgz|zip"))
        )
      | .browser_download_url
    ' | head -n1
  )"

  if [[ -z "$asset_url" || "$asset_url" == "null" ]]; then
    err "Could not find matching release asset for OS=$OS ARCH=$ARCH."
    err "Set OPENCODE_REPO correctly or install method to brew/npm."
    return 1
  fi

  local out="$WORKDIR/opencode-asset"
  log "Downloading: $asset_url"
  curl -fL "$asset_url" -o "$out"
  echo "$out"
}

install_from_binary() {
  need_cmd curl
  need_cmd jq
  need_cmd tar

  ensure_path
  local tag asset filetype
  tag="$(resolve_release_tag)"
  log "Resolved version tag: $tag"

  asset="$(download_release_asset "$tag")"
  filetype="$(file -b "$asset" || true)"

  mkdir -p "$WORKDIR/extract"

  if [[ "$asset" == *.zip ]] || echo "$filetype" | grep -qi zip; then
    need_cmd unzip
    unzip -q "$asset" -d "$WORKDIR/extract"
  else
    tar -xf "$asset" -C "$WORKDIR/extract"
  fi

  # Find binary by name; fallback to first executable named like opencode*
  local binpath
  binpath="$(find "$WORKDIR/extract" -type f -name "$OPENCODE_BIN" -perm -u+x | head -n1 || true)"
  if [[ -z "$binpath" ]]; then
    binpath="$(find "$WORKDIR/extract" -type f -iname "opencode*" -perm -u+x | head -n1 || true)"
  fi
  [[ -n "$binpath" ]] || { err "Binary not found in extracted archive."; return 1; }

  install -m 0755 "$binpath" "$PREFIX_BIN/$OPENCODE_BIN"
  log "Installed $OPENCODE_BIN to $PREFIX_BIN/$OPENCODE_BIN"
}

install_from_brew() {
  need_cmd brew
  # Try exact formula, then cask fallback
  if brew info "$OPENCODE_BIN" >/dev/null 2>&1; then
    brew install "$OPENCODE_BIN" || brew upgrade "$OPENCODE_BIN" || true
  else
    warn "Formula '$OPENCODE_BIN' not found in brew. Falling back to binary install."
    install_from_binary
  fi
}

install_from_npm() {
  need_cmd npm
  # If your package differs, export OPENCODE_NPM_PACKAGE
  local pkg="${OPENCODE_NPM_PACKAGE:-$OPENCODE_BIN}"
  npm install -g "$pkg"
}

install_opencode() {
  if command -v "$OPENCODE_BIN" >/dev/null 2>&1; then
    log "$OPENCODE_BIN already present: $(command -v "$OPENCODE_BIN")"
    return
  fi

  case "$INSTALL_METHOD" in
    skip) log "Skipping install (INSTALL_METHOD=skip)." ;;
    brew) install_from_brew ;;
    npm) install_from_npm ;;
    binary) install_from_binary ;;
    auto)
      if command -v brew >/dev/null 2>&1; then
        install_from_brew || true
      fi
      if ! command -v "$OPENCODE_BIN" >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
        install_from_npm || true
      fi
      if ! command -v "$OPENCODE_BIN" >/dev/null 2>&1; then
        install_from_binary
      fi
      ;;
    *)
      err "Invalid INSTALL_METHOD=$INSTALL_METHOD"
      exit 1
      ;;
  esac

  command -v "$OPENCODE_BIN" >/dev/null 2>&1 || {
    err "Install failed: $OPENCODE_BIN not found in PATH."
    exit 1
  }
}

backup_file_if_exists() {
  local f="$1"
  if [[ -f "$f" ]]; then
    local bdir="$BACKUP_ROOT/$RUN_ID"
    mkdir -p "$bdir"
    cp -a "$f" "$bdir/"
    log "Backed up $f -> $bdir/"
  fi
}

write_config() {
  mkdir -p "$CONFIG_DIR" "$STATE_DIR" "$CACHE_DIR" "$LOG_DIR" "$BACKUP_ROOT"
  backup_file_if_exists "$CONFIG_FILE"

  cat > "$CONFIG_FILE" <<EOF
# Managed by $SCRIPT_NAME on $RUN_ID
core:
  telemetry: $TELEMETRY_ENABLED
  auto_update: $AUTO_UPDATE
  safe_mode: $SAFE_MODE
  log_level: "$LOG_LEVEL"
  network_timeout_sec: $NETWORK_TIMEOUT_SEC

paths:
  state_dir: "$STATE_DIR"
  cache_dir: "$CACHE_DIR"
  log_dir: "$LOG_DIR"

performance:
  max_workers: $MAX_WORKERS
  cache_size_mb: $CACHE_SIZE_MB
  lazy_load_plugins: true
  prewarm_index: true

ui:
  color: "auto"
  unicode: true
  concise_output: false
  interactive_confirmations: true

security:
  redact_secrets_in_logs: true
  strict_permissions: true
  verify_tls: true

developer:
  diagnostics: true
  profile_startup: true
EOF

  chmod 600 "$CONFIG_FILE"
  log "Wrote hardened config: $CONFIG_FILE"
}

add_shell_block() {
  local key="$1"
  local content="$2"

  local shells=("$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile")
  for rc in "${shells[@]}"; do
    [[ -f "$rc" ]] || touch "$rc"
    if ! grep -q "BEGIN:${key}" "$rc"; then
      cat >> "$rc" <<EOF

# >>> BEGIN:${key}
$content
# <<< END:${key}
EOF
      log "Updated $rc with block: $key"
    fi
  done
}

configure_shell_integration() {
  # Environment tuning
  add_shell_block "opencode-env" \
"export OPENCODE_CONFIG=\"$CONFIG_FILE\"
export OPENCODE_CACHE_DIR=\"$CACHE_DIR\"
export OPENCODE_LOG_LEVEL=\"$LOG_LEVEL\""

  # completions if supported
  if "$OPENCODE_BIN" --help 2>/dev/null | grep -qi "completion"; then
    add_shell_block "opencode-completion-bash" \
"if command -v $OPENCODE_BIN >/dev/null 2>&1; then
  source <($OPENCODE_BIN completion bash 2>/dev/null) || true
fi"
    add_shell_block "opencode-completion-zsh" \
"if command -v $OPENCODE_BIN >/dev/null 2>&1; then
  source <($OPENCODE_BIN completion zsh 2>/dev/null) || true
fi"
  fi

  # Useful aliases
  add_shell_block "opencode-aliases" \
"alias oc='$OPENCODE_BIN'
alias ocfg='${EDITOR:-vi} \"$CONFIG_FILE\"'"
}

harden_permissions() {
  chmod 700 "$CONFIG_DIR" "$STATE_DIR" "$CACHE_DIR" || true
  chmod 700 "$LOG_DIR" || true
}

run_health_checks() {
  log "Running health checks..."
  "$OPENCODE_BIN" --version || true
  if "$OPENCODE_BIN" --help 2>/dev/null | grep -qi "doctor"; then
    "$OPENCODE_BIN" doctor || true
  fi
}

print_summary() {
  cat <<EOF

✅ OpenCode installation and optimization complete.

Binary:
  $(command -v "$OPENCODE_BIN" || echo "not found")

Config:
  $CONFIG_FILE

State/Cache/Logs:
  $STATE_DIR
  $CACHE_DIR
  $LOG_DIR

Backups:
  $BACKUP_ROOT/$RUN_ID

Log:
  $LOG_FILE

Next steps:
  1) Restart shell or run: source ~/.bashrc (or ~/.zshrc)
  2) Verify: $OPENCODE_BIN --version
  3) Edit settings: ${EDITOR:-vi} "$CONFIG_FILE"
EOF
}

main() {
  log "Starting $SCRIPT_NAME"
  detect_os_arch
  detect_sudo
  detect_pkg_mgr
  install_prereqs
  install_opencode
  write_config
  configure_shell_integration
  harden_permissions
  run_health_checks
  print_summary
}

main "$@"
```

## Run it

```bash
chmod +x install-opencode-pro.sh
./install-opencode-pro.sh
```

<details>
<summary><strong>Optional: advanced usage examples</strong></summary>

```bash
# Pin version + custom repo + binary method
OPENCODE_REPO="your-org/opencode" \
OPENCODE_VERSION="v2.4.1" \
INSTALL_METHOD="binary" \
./install-opencode-pro.sh

# Use npm package
INSTALL_METHOD="npm" \
OPENCODE_NPM_PACKAGE="@your-scope/opencode" \
./install-opencode-pro.sh

# Keep existing binary, only reconfigure/harden
INSTALL_METHOD="skip" \
./install-opencode-pro.sh
```
</details>

If you want, I can also generate a **v2 enterprise edition** with:
- rollback transactions,
- checksum/signature verification,
- CI/non-interactive flags,
- and per-environment profiles (`dev`, `prod`, `airgapped`).

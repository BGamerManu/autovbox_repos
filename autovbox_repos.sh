#!/usr/bin/env bash
set -euo pipefail

# Note: this script does NOT install VirtualBox. It only prepares the repositories.

die() { echo "Error: $*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }

has_cmd() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<'EOF'
Usage:
  sudo ./autovbox_repos.sh [--latest-vbox] [--vbox-version-txt]

Options:
  --latest-vbox        after adding the repo, automatically installs the latest available VirtualBox version
  --vbox-version-txt   creates a .txt file in Downloads listing all installable VirtualBox versions/packages
  -h, --help      show this help
EOF
}

INSTALL_LATEST_VBOX=false
WRITE_VBOX_VERSION_TXT=false
for arg in "$@"; do
  case "$arg" in
    --latest-vbox) INSTALL_LATEST_VBOX=true ;;
    --vbox-version-txt) WRITE_VBOX_VERSION_TXT=true ;;
    -h|--help) usage; exit 0 ;;
    *) die "unrecognized argument: $arg (use --help)" ;;
  esac
done

require_sudo_launch() {
  # Check that the script is running as root (typically via sudo).
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "run this script with sudo: sudo $0"
  fi
  # If you're root without sudo, don't block: just inform.
  if [[ -z "${SUDO_USER:-}" ]]; then
    echo "Note: you are running as root without sudo (ok)."
  fi
}

target_user_home() {
  # Quando esegui con sudo, $HOME è spesso /root. Noi vogliamo la Downloads dell'utente chiamante.
  local user="${SUDO_USER:-}"
  if [[ -n "$user" ]]; then
    # Preferisci getent se disponibile; fallback su ~user.
    if has_cmd getent; then
      getent passwd "$user" | awk -F: '{print $6}' | head -n 1
      return 0
    fi
    eval "echo ~${user}"
    return 0
  fi
  # Se non c'è SUDO_USER (sei root "puro"), usa HOME corrente.
  echo "${HOME:-/root}"
}

wait_for_apt_locks() {
  # On Debian/Ubuntu, packagekitd/Software Center may hold dpkg/apt locks.
  # Wait for the main locks to be released before calling apt/dpkg.
  local timeout_s="${1:-300}"  # 5 minuti di default
  local step_s=3
  local waited=0

  # `flock` is typically available (util-linux). If not, we let apt handle errors.
  if ! has_cmd flock; then
    return 0
  fi

  local locks=(
    "/var/lib/dpkg/lock-frontend"
    "/var/lib/dpkg/lock"
    "/var/cache/apt/archives/lock"
  )

  while true; do
    local busy=false
    for lf in "${locks[@]}"; do
      # If the file doesn't exist, ok. If it exists but we can't lock it, it's busy.
      if [[ -e "$lf" ]] && ! flock -n "$lf" -c true 2>/dev/null; then
        busy=true
        break
      fi
    done

    if [[ "$busy" == "false" ]]; then
      return 0
    fi

    if (( waited == 0 )); then
      echo "apt/dpkg seems busy (e.g. packagekitd/Software Center). Waiting for the lock to be released (max ${timeout_s}s)..."
      echo "Tip: close any Software Center/update apps and wait a few seconds."
    fi

    if (( waited >= timeout_s )); then
      die "timeout: apt/dpkg is still busy after ${timeout_s}s. Retry once background updates have finished."
    fi

    sleep "$step_s"
    waited=$((waited + step_s))
  done
}

apt_get() {
  # Wrapper robusto: attende i lock e usa noninteractive.
  wait_for_apt_locks 300
  DEBIAN_FRONTEND=noninteractive apt-get "$@"
}

download_to_stdout() {
  local url="$1"
  if has_cmd curl; then
    curl -fsSL "$url"
  elif has_cmd wget; then
    wget -qO- "$url"
  else
    die "curl or wget is required to download: $url"
  fi
}

download_to_file() {
  local url="$1"
  local dest="$2"
  if has_cmd curl; then
    curl -fL --retry 3 --retry-delay 2 -o "$dest" "$url"
  elif has_cmd wget; then
    wget -q --tries=3 --waitretry=2 -O "$dest" "$url"
  else
    die "curl or wget is required to download: $url"
  fi
}

confirm() {
  local prompt="${1:-Procedere?}"
  local reply=""

  # Se non siamo in un terminale interattivo, assumiamo "sì" per non bloccare.
  if [[ ! -t 0 ]]; then
    return 0
  fi

  while true; do
    read -r -p "${prompt} [Y/n] " reply || return 1
    reply="${reply:-Y}"
    case "${reply}" in
      [Yy]|[Yy][Ee][Ss]|[Ss]) return 0 ;;
      [Nn]|[Nn][Oo]) return 1 ;;
      *) echo "Invalid answer. Use Y or n." ;;
    esac
  done
}

show_installable_versions_debian() {
  echo
  echo "Installable VirtualBox versions/packages via apt (from the repo just added):"
  if command -v apt-cache >/dev/null 2>&1; then
    # Mostra i pacchetti "virtualbox-*" con la versione disponibile.
    # (Oracle tipicamente pubblica virtualbox-6.1, virtualbox-7.0, virtualbox-7.1, ecc.)
    apt-cache search '^virtualbox-[0-9]' 2>/dev/null \
      | awk '{print $1}' \
      | sort -V \
      | while read -r pkg; do
          ver="$(apt-cache policy "$pkg" 2>/dev/null | awk '/Candidate:/ {print $2}' | head -n 1)"
          if [[ -n "$ver" && "$ver" != "(none)" ]]; then
            printf "  - %s (candidate: %s)\n" "$pkg" "$ver"
          else
            printf "  - %s\n" "$pkg"
          fi
        done
  else
    echo "  (apt-cache not available: cannot list packages.)"
  fi
}

show_installable_versions_fedora() {
  echo
  echo "Installable VirtualBox versions/packages via dnf (from the repo just added):"
  if command -v dnf >/dev/null 2>&1; then
    # Prova a mostrare duplicati; se la repo non espone duplicati, almeno elenca i pacchetti.
    if dnf -q list --showduplicates 'VirtualBox*' >/dev/null 2>&1; then
      dnf -q list --showduplicates 'VirtualBox*' 2>/dev/null \
        | awk 'NF>0 && $1 !~ /^Available/ && $1 !~ /^Installed/ {print "  - " $1 "  " $2}'
    else
      dnf -q list available 'VirtualBox*' 2>/dev/null \
        | awk 'NF>0 && $1 !~ /^Available/ {print "  - " $1 "  " $2}'
    fi
  else
    echo "  (dnf not available: cannot list packages.)"
  fi
}

write_versions_txt_debian() {
  local out_path="$1"
  need_cmd apt-cache

  {
    echo "VirtualBox - pacchetti/versioni installabili (Debian/Ubuntu)"
    echo "Generato: $(date -Is 2>/dev/null || date)"
    echo

    # Elenca i pacchetti virtualbox-* e per ciascuno stampa candidate + tutte le versioni note (madison).
    while read -r pkg; do
      [[ -z "$pkg" ]] && continue
      echo "[$pkg]"
      local cand=""
      cand="$(apt-cache policy "$pkg" 2>/dev/null | awk '/Candidate:/ {print $2}' | head -n 1)"
      echo "candidate: ${cand:-"(unknown)"}"

      # apt-cache madison non sempre è presente su sistemi minimal, ma di solito lo è.
      if apt-cache madison "$pkg" >/dev/null 2>&1; then
        echo "available:"
        apt-cache madison "$pkg" 2>/dev/null | awk '{print "  - " $3}' | sort -Vu
      else
        echo "available: (apt-cache madison non disponibile)"
      fi
      echo
    done < <(apt-cache search '^virtualbox-[0-9]' 2>/dev/null | awk '{print $1}' | sort -Vu)
  } >"$out_path"
}

write_versions_txt_fedora() {
  local out_path="$1"
  need_cmd dnf

  {
    echo "VirtualBox - pacchetti/versioni installabili (Fedora/derivate)"
    echo "Generato: $(date -Is 2>/dev/null || date)"
    echo
    echo "Output da: dnf list --showduplicates VirtualBox*"
    echo
    dnf -q list --showduplicates 'VirtualBox*' 2>/dev/null \
      | awk 'NF>0 && $1 !~ /^Available/ && $1 !~ /^Installed/ {print $0}' \
      || true
  } >"$out_path"
}

pick_latest_debian_pkg() {
  # Ritorna (stdout) il pacchetto virtualbox-* con Candidate più alta.
  need_cmd dpkg
  need_cmd apt-cache

  local best_pkg=""
  local best_ver=""
  local pkg=""
  local ver=""

  while read -r pkg; do
    [[ -z "$pkg" ]] && continue
    ver="$(apt-cache policy "$pkg" 2>/dev/null | awk '/Candidate:/ {print $2}' | head -n 1)"
    [[ -z "$ver" || "$ver" == "(none)" ]] && continue

    if [[ -z "$best_ver" ]]; then
      best_pkg="$pkg"
      best_ver="$ver"
      continue
    fi

    if dpkg --compare-versions "$ver" gt "$best_ver"; then
      best_pkg="$pkg"
      best_ver="$ver"
    fi
  done < <(apt-cache search '^virtualbox-[0-9]' 2>/dev/null | awk '{print $1}' | sort -u)

  if [[ -n "$best_pkg" ]]; then
    echo "$best_pkg"
    return 0
  fi

  return 1
}

pick_latest_fedora_pkg() {
  # Ritorna (stdout) il pacchetto VirtualBox* con versione più alta secondo dnf list --showduplicates.
  need_cmd dnf

  local line=""
  local namever=()
  local best_name=""
  local best_ver=""
  local name=""
  local ver=""

  # Output tipico:
  # VirtualBox-7.1.x86_64    7.1.4_165100_fedora40-1    virtualbox
  while read -r line; do
    [[ -z "$line" ]] && continue
    # Salta header
    [[ "$line" =~ ^(Available|Installed) ]] && continue
    # Prende: name.arch  version  repo
    name="$(awk '{print $1}' <<<"$line")"
    ver="$(awk '{print $2}' <<<"$line")"
    [[ -z "$name" || -z "$ver" ]] && continue

    # Normalizza name senza .arch
    name="${name%%.*}"

    if [[ -z "$best_ver" ]]; then
      best_name="$name"
      best_ver="$ver"
      continue
    fi

    # Confronto "grezzo" con sort -V: sufficiente per versioni dnf (es. 7.1.4_165100_fedora40-1)
    if [[ "$(printf "%s\n%s\n" "$best_ver" "$ver" | sort -V | tail -n 1)" == "$ver" ]]; then
      best_name="$name"
      best_ver="$ver"
    fi
  done < <(dnf -q list --showduplicates 'VirtualBox*' 2>/dev/null || true)

  if [[ -n "$best_name" ]]; then
    echo "$best_name"
    return 0
  fi

  return 1
}

install_deps_debian() {
  # Install everything needed to add the repo, manage keyrings, and download files.
  # Note: we do NOT install VirtualBox here.
  echo "Installing/updating dependencies (Debian/Ubuntu)..."
  apt_get update -y
  apt_get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    gnupg \
    lsb-release
}

install_deps_fedora() {
  echo "Installing/updating dependencies (Fedora-based)..."
  dnf -y install \
    ca-certificates \
    curl \
    wget \
    gnupg2
}

require_sudo_launch

if [[ ! -r /etc/os-release ]]; then
  die "impossibile leggere /etc/os-release (script pensato per Linux Debian/Ubuntu o Fedora/derivate)."
fi

# shellcheck disable=SC1091
source /etc/os-release

ID_LIKE_LOWER="$(echo "${ID_LIKE:-}" | tr '[:upper:]' '[:lower:]')"
ID_LOWER="$(echo "${ID:-}" | tr '[:upper:]' '[:lower:]')"

is_debian_like=false
if [[ "$ID_LOWER" == "debian" || "$ID_LOWER" == "ubuntu" ]]; then
  is_debian_like=true
elif [[ "$ID_LIKE_LOWER" == *"debian"* ]]; then
  is_debian_like=true
fi

is_fedora_like=false
if [[ "$ID_LOWER" == "fedora" ]]; then
  is_fedora_like=true
elif [[ "$ID_LIKE_LOWER" == *"fedora"* ]]; then
  is_fedora_like=true
fi

if [[ "$is_debian_like" != "true" && "$is_fedora_like" != "true" ]]; then
  die "distro non supportata: ID=${ID:-?} (supportate: Debian/Ubuntu e Fedora/derivate; niente Arch)."
fi
echo "Detected distro: ${PRETTY_NAME:-$ID_LOWER}"

VBOX_BASE_URL="https://download.virtualbox.org/virtualbox"
FINAL_REPO_PATH=""

echo
echo "This script will add the official VirtualBox repository and refresh the package metadata."
echo "It will NOT install VirtualBox unless you pass --latest-vbox."
echo
if ! confirm "Do you want to continue?"; then
  echo "Operation cancelled by user."
  exit 0
fi

if [[ "$is_debian_like" == "true" ]]; then
  install_deps_debian

  # Codename distro (es. jammy, noble, bookworm...)
  CODENAME="${VERSION_CODENAME:-}"
  if [[ -z "$CODENAME" ]] && command -v lsb_release >/dev/null 2>&1; then
    CODENAME="$(lsb_release -cs 2>/dev/null || true)"
  fi
  if [[ -z "$CODENAME" ]]; then
    die "impossibile determinare VERSION_CODENAME (installa lsb-release o usa una release con VERSION_CODENAME)."
  fi

  echo "Family: Debian/Ubuntu (codename: $CODENAME)"
  KEYRING_PATH="/usr/share/keyrings/oracle-virtualbox-2016.gpg"
  REPO_LIST_PATH="/etc/apt/sources.list.d/virtualbox.list"
  REPO_URL="$VBOX_BASE_URL/debian"

  echo "Importing Oracle GPG key (keyring: $KEYRING_PATH)..."
  download_to_stdout "https://www.virtualbox.org/download/oracle_vbox_2016.asc" \
    | gpg --dearmor -o "$KEYRING_PATH"
  chmod 0644 "$KEYRING_PATH"

  echo "Adding/updating VirtualBox repository in $REPO_LIST_PATH..."
  echo "deb [arch=amd64 signed-by=$KEYRING_PATH] $REPO_URL $CODENAME contrib" \
    | tee "$REPO_LIST_PATH" >/dev/null
  FINAL_REPO_PATH="$REPO_LIST_PATH"

  echo "Refreshing package index (apt update)..."
  apt_get update -y

  show_installable_versions_debian

  if [[ "$WRITE_VBOX_VERSION_TXT" == "true" ]]; then
    tgt_home="$(target_user_home)"
    versions_txt="$tgt_home/Downloads/VirtualBox-installable-versions.txt"
    mkdir -p "$(dirname "$versions_txt")"
    echo
    echo "Creating installable versions list file: $versions_txt"
    write_versions_txt_debian "$versions_txt"
  fi

  if [[ "$INSTALL_LATEST_VBOX" == "true" ]]; then
    echo
    echo "You requested --latest-vbox: installing the latest available version in 3 seconds..."
    sleep 3
    if latest_pkg="$(pick_latest_debian_pkg)"; then
      echo "Installing: $latest_pkg"
      apt_get install -y "$latest_pkg"
    else
      die "non sono riuscito a determinare quale pacchetto VirtualBox installare (nessun virtualbox-* con Candidate valida)."
    fi
  fi
else
  echo "Family: Fedora-based"
  need_cmd dnf
  need_cmd rpm
  install_deps_fedora

  REPO_FILE="/etc/yum.repos.d/virtualbox.repo"
  REPO_URL="$VBOX_BASE_URL/rpm/fedora/virtualbox.repo"

  echo "Adding/updating VirtualBox repository in $REPO_FILE..."
  # Scarichiamo prima localmente e poi copiamo, così funziona sia con curl che con wget.
  tmp_repo="$(mktemp)"
  trap 'rm -f "$tmp_repo"' EXIT
  download_to_file "$REPO_URL" "$tmp_repo"
  cp -f "$tmp_repo" "$REPO_FILE"
  chmod 0644 "$REPO_FILE"
  FINAL_REPO_PATH="$REPO_FILE"

  echo "Importing Oracle GPG key..."
  rpm --import "https://www.virtualbox.org/download/oracle_vbox_2016.asc"

  echo "Refreshing metadata cache (dnf makecache)..."
  dnf -y makecache

  show_installable_versions_fedora

  if [[ "$WRITE_VBOX_VERSION_TXT" == "true" ]]; then
    tgt_home="$(target_user_home)"
    versions_txt="$tgt_home/Downloads/VirtualBox-installable-versions.txt"
    mkdir -p "$(dirname "$versions_txt")"
    echo
    echo "Creating installable versions list file: $versions_txt"
    write_versions_txt_fedora "$versions_txt"
  fi

  if [[ "$INSTALL_LATEST_VBOX" == "true" ]]; then
    echo
    echo "You requested --latest-vbox: installing the latest available version in 3 seconds..."
    sleep 3
    if latest_pkg="$(pick_latest_fedora_pkg)"; then
      echo "Installing: $latest_pkg"
      dnf -y install "$latest_pkg"
    else
      die "non sono riuscito a determinare quale pacchetto VirtualBox installare (dnf list non ha restituito pacchetti VirtualBox*)."
    fi
  fi
fi

echo "Fetching the latest VirtualBox version to download the Extension Pack..."
LATEST_VER="$(download_to_stdout "$VBOX_BASE_URL/LATEST.TXT" | tr -d ' \t\r\n')"
if [[ -z "$LATEST_VER" ]]; then
  die "non sono riuscito a leggere LATEST.TXT da $VBOX_BASE_URL"
fi

EXT_FILENAME="Oracle_VirtualBox_Extension_Pack-${LATEST_VER}.vbox-extpack"
EXT_URL="$VBOX_BASE_URL/${LATEST_VER}/${EXT_FILENAME}"

TARGET_HOME="$(target_user_home)"
DEST_DIR="$TARGET_HOME/Downloads/Downloaded Extension Pack"
mkdir -p "$DEST_DIR"
DEST_PATH="$DEST_DIR/$EXT_FILENAME"

echo "Downloading Extension Pack: $EXT_URL"
download_to_file "$EXT_URL" "$DEST_PATH"

echo
echo "Done."
echo "- VirtualBox repo: ${FINAL_REPO_PATH:-"(repo path not determined)"}"
echo "- Extension Pack saved to: $DEST_PATH"
echo
echo "You can now install VirtualBox manually (or via --latest-vbox)."
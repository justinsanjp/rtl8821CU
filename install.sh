#!/usr/bin/env bash
set -euo pipefail

PACKAGE_NAME="rtl8821CU"
PACKAGE_VERSION="5.4.1-k6.17"
MODULE_NAME="8821cu"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DKMS_SRC_DIR="/usr/src/${PACKAGE_NAME}-${PACKAGE_VERSION}"
PATCH_CANDIDATES=(
  "${SCRIPT_DIR}/rtl8821cu-linux-6.17.patch"
  "${SCRIPT_DIR}/../rtl8821cu-linux-6.17.patch"
)

log() {
  printf '[*] %s\n' "$*"
}

warn() {
  printf '[!] %s\n' "$*" >&2
}

die() {
  printf '[x] %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Verwendung:
  ./install.sh         Installiert den Treiber per DKMS
  ./install.sh --undo  Entfernt die DKMS-Installation wieder

Hinweise:
  - Das Skript startet keinen NetworkManager neu.
  - Bereits laufende Verbindungen werden nicht aktiv getrennt.
  - Fuer Root-Rechte wird bei Bedarf sudo verwendet.
EOF
}

run_root() {
  if [[ ${EUID} -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Benoetigtes Kommando fehlt: $1"
}

dkms_version_tree_exists() {
  [[ -d "/var/lib/dkms/${PACKAGE_NAME}/${PACKAGE_VERSION}" ]]
}

dkms_version_status_exists() {
  dkms status -m "${PACKAGE_NAME}" -v "${PACKAGE_VERSION}" 2>/dev/null | \
    grep -Eq "^${PACKAGE_NAME}/${PACKAGE_VERSION}(,|:)"
}

dkms_version_exists() {
  dkms_version_tree_exists || dkms_version_status_exists
}

warn_about_other_versions() {
  local other_versions

  other_versions="$(dkms status -m "${PACKAGE_NAME}" 2>/dev/null | grep -v "^${PACKAGE_NAME}/${PACKAGE_VERSION}\\(,\\|:\\)" || true)"
  if [[ -n "${other_versions}" ]]; then
    warn "Es existieren weitere DKMS-Versionen fuer ${PACKAGE_NAME}:"
    printf '%s\n' "${other_versions}" >&2
  fi
}

find_patch_file() {
  local path
  for path in "${PATCH_CANDIDATES[@]}"; do
    if [[ -f "${path}" ]]; then
      printf '%s\n' "${path}"
      return 0
    fi
  done
  return 1
}

check_requirements() {
  need_cmd uname
  need_cmd make
  need_cmd patch
  need_cmd dkms
  need_cmd rsync
  need_cmd sed
  need_cmd grep

  [[ -d "/lib/modules/$(uname -r)/build" ]] || \
    die "Kernel-Header fuer $(uname -r) fehlen. Installiere linux-headers-$(uname -r)."
}

apply_patch_if_needed() {
  local patch_file

  if ! patch_file="$(find_patch_file)"; then
    warn "Keine Patchdatei gefunden. Verwende den aktuellen Quellbaum unveraendert."
    return 0
  fi

  if patch --dry-run -N -p1 -d "${SCRIPT_DIR}" < "${patch_file}" >/dev/null 2>&1; then
    log "Wende Patch an: ${patch_file}"
    patch -N -p1 -d "${SCRIPT_DIR}" < "${patch_file}"
    return 0
  fi

  if patch --dry-run -R -p1 -d "${SCRIPT_DIR}" < "${patch_file}" >/dev/null 2>&1; then
    log "Patch ist bereits angewendet."
    return 0
  fi

  die "Patchdatei passt nicht auf den aktuellen Quellbaum: ${patch_file}"
}

revert_patch_if_possible() {
  local patch_file

  if ! patch_file="$(find_patch_file)"; then
    warn "Keine Patchdatei gefunden. Quellbaum bleibt unveraendert."
    return 0
  fi

  if patch --dry-run -R -p1 -d "${SCRIPT_DIR}" < "${patch_file}" >/dev/null 2>&1; then
    log "Drehe Patch wieder zurueck."
    patch -R -p1 -d "${SCRIPT_DIR}" < "${patch_file}"
    return 0
  fi

  warn "Patch wird nicht zurueckgedreht, weil der Quellbaum nicht exakt zum Reverse-Patch passt."
}

build_test() {
  log "Pruefe Build lokal gegen Kernel $(uname -r)"
  make -C "${SCRIPT_DIR}" clean
  make -C "${SCRIPT_DIR}" -j"$(nproc)"
  [[ -f "${SCRIPT_DIR}/${MODULE_NAME}.ko" ]] || die "${MODULE_NAME}.ko wurde nicht erzeugt."
}

prepare_dkms_tree() {
  log "Aktualisiere DKMS-Quellbaum unter ${DKMS_SRC_DIR}"
  run_root mkdir -p "${DKMS_SRC_DIR}"
  run_root rsync -a --delete \
    --exclude '.git/' \
    --exclude '.tmp_versions/' \
    --exclude '*.o' \
    --exclude '*.ko' \
    --exclude '*.cmd' \
    --exclude '*.mod' \
    --exclude '*.mod.c' \
    --exclude 'Module.symvers' \
    --exclude 'modules.order' \
    --exclude '*.patch' \
    "${SCRIPT_DIR}/" "${DKMS_SRC_DIR}/"
  run_root sed -i "s/#MODULE_VERSION#/${PACKAGE_VERSION}/" "${DKMS_SRC_DIR}/dkms.conf"
}

remove_existing_dkms_version() {
  if dkms_version_exists; then
    log "Entferne vorhandene DKMS-Version ${PACKAGE_VERSION}"
    run_root dkms remove -m "${PACKAGE_NAME}" -v "${PACKAGE_VERSION}" --all
  fi
}

install_dkms() {
  remove_existing_dkms_version
  prepare_dkms_tree

  log "Fuege DKMS-Modul hinzu"
  run_root dkms add -m "${PACKAGE_NAME}" -v "${PACKAGE_VERSION}"

  log "Baue DKMS-Modul"
  run_root dkms build -m "${PACKAGE_NAME}" -v "${PACKAGE_VERSION}"

  log "Installiere DKMS-Modul"
  run_root dkms install -m "${PACKAGE_NAME}" -v "${PACKAGE_VERSION}"
}

undo_install() {
  if dkms_version_exists; then
    log "Entferne DKMS-Modul ${PACKAGE_NAME}/${PACKAGE_VERSION}"
    run_root dkms remove -m "${PACKAGE_NAME}" -v "${PACKAGE_VERSION}" --all
  else
    log "Keine installierte DKMS-Version ${PACKAGE_VERSION} gefunden."
  fi

  if [[ -d "${DKMS_SRC_DIR}" ]]; then
    log "Entferne DKMS-Quellverzeichnis ${DKMS_SRC_DIR}"
    run_root rm -rf "${DKMS_SRC_DIR}"
  fi

  log "Bereinige lokalen Buildbaum"
  make -C "${SCRIPT_DIR}" clean >/dev/null

  revert_patch_if_possible

  warn "Ein bereits geladenes Modul wird absichtlich nicht automatisch entladen."
  warn "Falls noetig, spaeter manuell pruefen: lsmod | grep ${MODULE_NAME}"
}

main() {
  local mode="install"

  if [[ $# -gt 1 ]]; then
    usage
    exit 1
  fi

  if [[ $# -eq 1 ]]; then
    case "$1" in
      --undo)
        mode="undo"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        usage
        exit 1
        ;;
    esac
  fi

  check_requirements
  warn_about_other_versions

  if [[ "${mode}" == "undo" ]]; then
    undo_install
    log "Rueckgaengig abgeschlossen."
    exit 0
  fi

  apply_patch_if_needed
  build_test
  install_dkms

  log "Installation abgeschlossen."
  log "Zum Laden ohne Neustart bei Bedarf manuell ausfuehren: sudo modprobe ${MODULE_NAME}"
  log "Zum Testen danach: iw dev ; nmcli device status"
  warn "NetworkManager wurde nicht neu gestartet."
}

main "$@"

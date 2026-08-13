#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
LOG_DIR="${ROOT_DIR}/logs"
mkdir -p "${LOG_DIR}"

OPENOCD=${OPENOCD:-openocd}
GDB=${GDB:-riscv32-unknown-elf-gdb}
GDB_PORT=${GDB_PORT:-3333}
TCL_PORT=${TCL_PORT:-6666}
TELNET_PORT=${TELNET_PORT:-4444}
ADAPTER_CFG=${ADAPTER_CFG:-}
FIRMWARE_ELF=${FIRMWARE_ELF:-}

if [[ -z "${ADAPTER_CFG}" ]]; then
  echo "ERROR: set ADAPTER_CFG=/path/to/adapter.cfg" >&2
  exit 2
fi

if [[ ! -f "${ADAPTER_CFG}" ]]; then
  echo "ERROR: ADAPTER_CFG does not exist: ${ADAPTER_CFG}" >&2
  exit 2
fi

if [[ -n "${FIRMWARE_ELF}" && ! -f "${FIRMWARE_ELF}" ]]; then
  echo "ERROR: FIRMWARE_ELF does not exist: ${FIRMWARE_ELF}" >&2
  exit 2
fi

GDB_SCRIPT="${LOG_DIR}/eriscv_m2_smoke.generated.gdb"
TRANSCRIPT="${LOG_DIR}/gdb-transcript.txt"
cp "${ROOT_DIR}/gdb/eriscv_m2_smoke.gdb" "${GDB_SCRIPT}"
python3 - "${GDB_SCRIPT}" "${TRANSCRIPT}" "${GDB_PORT}" "${FIRMWARE_ELF}" <<'PYEDIT'
from pathlib import Path
import sys
script = Path(sys.argv[1])
transcript = Path(sys.argv[2])
gdb_port = sys.argv[3]
firmware = sys.argv[4]
text = script.read_text()
text = text.replace('__TRANSCRIPT__', transcript.as_posix())
text = text.replace('__GDB_PORT__', str(gdb_port))
if firmware:
    text = text.replace('__HAS_ELF__', '1')
    text = text.replace('__FIRMWARE_ELF__', firmware)
else:
    text = text.replace('__HAS_ELF__', '0')
    text = text.replace('__FIRMWARE_ELF__', '')
script.write_text(text)
PYEDIT

"${OPENOCD}"   -f "${ADAPTER_CFG}"   -f "${ROOT_DIR}/openocd/eriscv_m2_riscv.cfg"   -c "gdb_port ${GDB_PORT}"   -c "tcl_port ${TCL_PORT}"   -c "telnet_port ${TELNET_PORT}"   -l "${LOG_DIR}/openocd.log" &
OPENOCD_PID=$!
trap 'kill ${OPENOCD_PID} >/dev/null 2>&1 || true' EXIT

sleep 2
"${GDB}" -q -x "${GDB_SCRIPT}" | tee "${LOG_DIR}/gdb.log"

grep -q "ERISCV_M2_OPENOCD_GDB PASS" "${LOG_DIR}/gdb.log"
echo "ERISCV_M2_OPENOCD_GDB PASS"

#!/usr/bin/env bash
set -euo pipefail

# Run the Poker.nvim simulator with default arguments:
# hands=10000, players=7, acpc_path=simulator default.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${REPO_ROOT}"

lua lua/poker/sim_cli.lua "$@"

echo "Simulation complete."

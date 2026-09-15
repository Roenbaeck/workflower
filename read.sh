#!/bin/bash
# Read-only reverse engineering of existing Snowflake task graphs.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/webapp/python_env.sh"
prepare_python
exec "$WORKFLOWER_PYTHON" "$SCRIPT_DIR/webapp/read.py" "$@"

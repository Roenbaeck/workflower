#!/bin/bash
# Run the local Workflower editor.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ $# -ne 1 ]; then
    echo "Usage: $0 <connection_name>"
    exit 1
fi
source "$SCRIPT_DIR/python_env.sh"
prepare_python
export SNOWFLAKE_CONNECTION="$1"
exec "$WORKFLOWER_PYTHON" "$SCRIPT_DIR/server.py"

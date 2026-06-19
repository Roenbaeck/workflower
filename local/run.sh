#!/bin/bash
# Run the Workflow Editor locally
# Usage: ./run.sh <connection_name>
#
# Reads connection details from ~/.snowflake/config.toml
# Automatically creates a virtual environment on first run.

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <connection_name>"
    echo "Example: $0 U2C"
    echo ""
    echo "Available connections:"
    python3 -c "
import tomllib, os
paths = [os.path.expanduser('~/.snowflake/config.toml'),
         os.path.expanduser('~/Library/Application Support/snowflake/config.toml')]
for p in paths:
    if os.path.exists(p):
        cfg = tomllib.load(open(p, 'rb'))
        for c in cfg.get('connections', {}):
            print(f'  {c}')
" 2>/dev/null || echo "  (no connections found)"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Workflow Editor (local) ==="
echo "Connection: $1"
echo ""

cd "$SCRIPT_DIR"

# Set up virtual environment
VENV_DIR="$SCRIPT_DIR/.venv"
if [ ! -f "$VENV_DIR/bin/python3" ]; then
    echo "Creating virtual environment..."
    python3 -m venv "$VENV_DIR"
    echo "Installing dependencies..."
    "$VENV_DIR/bin/pip" install -q -r requirements.txt
else
    # Verify dependencies are installed
    "$VENV_DIR/bin/pip" install -q -r requirements.txt 2>/dev/null || {
        echo "Installing missing dependencies..."
        "$VENV_DIR/bin/pip" install -r requirements.txt
    }
fi

SNOWFLAKE_CONNECTION="$1" "$VENV_DIR/bin/streamlit" run edit_workflow.py

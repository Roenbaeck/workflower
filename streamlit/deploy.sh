#!/bin/bash
# Deploy the Workflow Editor Streamlit app to Snowflake
# Usage: ./deploy.sh <connection_name>

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <connection_name>"
    echo "Example: $0 my_snowflake_conn"
    exit 1
fi

CONNECTION="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== deploy workflow editor ==="
echo "Connection: $CONNECTION"
echo ""

cd "$SCRIPT_DIR"

snow streamlit deploy -c "$CONNECTION" --replace --open

echo ""
echo "=== deploy complete ==="

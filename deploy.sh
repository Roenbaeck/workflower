#!/bin/bash
# Deploy sisula-snowflake to Snowflake
# Usage: ./deploy.sh <connection_name>

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <connection_name>"
    echo "Example: $0 my_snowflake_conn"
    exit 1
fi

CONNECTION="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SISULA_SOURCE="$SCRIPT_DIR/src/sisula.js"
DEPLOY_TEMPLATE="$SCRIPT_DIR/sql/deploy.sql"

render_deploy_sql() {
    local output_file="$1"

    if grep -q '\$\$' "$SISULA_SOURCE"; then
        echo "ERROR: $SISULA_SOURCE contains '$$', which would break the SQL UDF delimiter"
        exit 1
    fi

    if ! awk -v source_file="$SISULA_SOURCE" '
        BEGIN { inserted = 0 }
        index($0, "__SISULA_JS_SOURCE__") {
            while ((getline line < source_file) > 0) {
                if (line ~ /^[[:space:]]*module\.exports = sisulate;[[:space:]]*$/) continue;
                print line;
            }
            close(source_file);
            inserted = 1;
            next;
        }
        { print }
        END {
            if (!inserted) {
                print "Missing __SISULA_JS_SOURCE__ marker in deploy.sql" > "/dev/stderr";
                exit 2;
            }
        }
    ' "$DEPLOY_TEMPLATE" > "$output_file"; then
        echo "ERROR: failed to render deploy SQL from $DEPLOY_TEMPLATE"
        exit 1
    fi
}

echo "=== sisula-snowflake deploy ==="
echo "Connection: $CONNECTION"
echo ""

DEPLOY_SQL_RENDERED="$(mktemp)"
trap 'rm -f "$DEPLOY_SQL_RENDERED"' EXIT

render_deploy_sql "$DEPLOY_SQL_RENDERED"

snow sql -c "$CONNECTION" --enable-templating NONE -f "$DEPLOY_SQL_RENDERED"

echo ""
echo "=== Deploy complete ==="

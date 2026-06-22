#!/bin/bash
# Deploy metadata model and logging procedures to Snowflake
# Usage: ./deploy_metadata.sh <connection_name>

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <connection_name>"
    echo "Example: $0 my_snowflake_conn"
    exit 1
fi

CONNECTION="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== metadata deploy ==="
echo "Connection: $CONNECTION"
echo ""

run_step() {
    local step="$1"
    local file="$2"
    echo "--- $step ---"
    snow sql -c "$CONNECTION" --enable-templating NONE -f "$SCRIPT_DIR/$file" && echo "  OK" || { echo "  FAILED"; exit 1; }
    echo ""
}

seed_template() {
    local template_name="$1"
    local template_path="$2"
    local seed_file
    local template_sql

    echo "--- 6. Seed template: $template_name ---"
    seed_file="$(mktemp)"
    template_sql="$(perl -0pe "s/'/''/g" "$template_path")"
    printf "CALL metadata._TemplateUpsert('%s', '%s');\n" "$template_name" "$template_sql" > "$seed_file"
    snow sql -c "$CONNECTION" --enable-templating NONE -f "$seed_file" && echo "  OK" || { rm -f "$seed_file"; echo "  FAILED"; exit 1; }
    rm -f "$seed_file"
    echo ""
}

run_step "1. Schema"           metadata/Install_1_CreateMetadataSchema.sql
run_step "2. Model (DDL)"      metadata/Install_2_MetadataModel.sql
run_step "3. Knot values"      metadata/Install_3_InsertKnotValues.sql
run_step "4. Logging procs"    metadata/Install_4_CreateLoggingProcedures.sql
run_step "5. Config procs"     metadata/Install_5_ConfigurationProcedures.sql
seed_template "CreateTaskGraph" "$SCRIPT_DIR/templates/CreateTaskGraph.sql"

echo "=== deploy complete ==="

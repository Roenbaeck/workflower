#!/bin/bash
# Install task graphs from JSON bindings using sisula templates
# Usage: ./install.sh <connection_name> <directory> [--template <name>] [--dry-run]

set -euo pipefail

usage() {
    echo "Usage: $0 <connection_name> <directory> [--template <name>] [--dry-run]"
    echo ""
    echo "  connection_name   Snowflake connection (from snow config)"
    echo "  directory         Path containing .json workflow bindings"
    echo "  --template name   Template to use (default: CreateTaskGraph)"
    echo "  --dry-run         Render SQL files only, do not deploy"
    echo ""
    echo "Available templates:"
    ls "$SCRIPT_DIR/templates"/*.sql 2>/dev/null | while read f; do
        echo "  $(basename "$f" .sql)"
    done
    echo ""
    echo "Example: $0 my_conn ./examples --dry-run"
    exit 1
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATES_DIR="$SCRIPT_DIR/templates"
RENDERER="$SCRIPT_DIR/src/sisula.js"

CONNECTION=""
DIR=""
TEMPLATE_NAME="CreateTaskGraph"
DRY_RUN=false

while [ $# -gt 0 ]; do
    case "$1" in
        --template)
            TEMPLATE_NAME="$2"; shift 2 ;;
        -t)
            TEMPLATE_NAME="$2"; shift 2 ;;
        --dry-run|-n)
            DRY_RUN=true; shift ;;
        --help|-h)
            usage ;;
        -*)
            echo "Unknown option: $1"; usage ;;
        *)
            if [ -z "$CONNECTION" ]; then CONNECTION="$1";
            elif [ -z "$DIR" ]; then DIR="$1";
            else echo "Too many arguments: $1"; usage; fi
            shift ;;
    esac
done

if [ -z "$CONNECTION" ] || [ -z "$DIR" ]; then
    usage
fi

TEMPLATE="$TEMPLATES_DIR/${TEMPLATE_NAME}.sql"
OUTPUT_DIR="$DIR/rendered"

if [ ! -d "$DIR" ]; then
    echo "ERROR: directory '$DIR' not found"
    exit 1
fi

if [ ! -f "$TEMPLATE" ]; then
    echo "ERROR: template not found: $TEMPLATE"
    echo "Available templates:"
    ls "$TEMPLATES_DIR"/*.sql 2>/dev/null | while read f; do
        echo "  $(basename "$f" .sql)"
    done
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo "=== sisula task graph installer ==="
echo "Connection: $CONNECTION"
echo "Directory:  $DIR"
echo "Template:   $TEMPLATE_NAME"
echo "Dry run:    $DRY_RUN"
echo ""

shopt -s nullglob
JSON_FILES=("$DIR"/*.json)
shopt -u nullglob

if [ ${#JSON_FILES[@]} -eq 0 ]; then
    echo "No .json files found in $DIR"
    exit 0
fi

echo "Found ${#JSON_FILES[@]} workflow file(s)"
echo ""

for JSON_FILE in "${JSON_FILES[@]}"; do
    BASENAME="$(basename "$JSON_FILE" .json)"
    SQL_FILE="$OUTPUT_DIR/${TEMPLATE_NAME}_${BASENAME}.sql"

    echo "--- Rendering: $BASENAME ---"

    node -e "
        var sisulate = require('$RENDERER');
        var fs = require('fs');
        var tpl = fs.readFileSync('$TEMPLATE', 'utf8');
        var bind = fs.readFileSync('$JSON_FILE', 'utf8');
        var sql = sisulate(tpl, bind);
        fs.writeFileSync('$SQL_FILE', sql);
        console.log('  Rendered: ' + sql.split('\n').length + ' lines');
    "

    if [ "$DRY_RUN" = true ]; then
        echo "  Skipped deploy (dry-run)"
    else
        echo "  Deploying..."
        snow sql -c "$CONNECTION" --enable-templating NONE -f "$SQL_FILE" \
            && echo "  OK" \
            || { echo "  FAILED"; exit 1; }
    fi
    echo ""
done

echo "=== done ==="
if [ "$DRY_RUN" = true ]; then
    echo "Rendered SQL files saved to: $OUTPUT_DIR"
fi

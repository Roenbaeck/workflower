# Shared Python environment bootstrap. Source this file from launchers.
prepare_python() {
    local webapp_dir
    webapp_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    WORKFLOWER_PYTHON="$webapp_dir/.venv/bin/python3"
    if [ ! -x "$WORKFLOWER_PYTHON" ]; then
        python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else "Python 3.11 or later is required")'
        python3 -m venv "$webapp_dir/.venv"
    fi
    # Resolve dependencies on first run or after requirements change, not every start.
    local stamp="$webapp_dir/.venv/.workflower-requirements"
    if ! cmp -s "$webapp_dir/requirements.txt" "$stamp"; then
        "$WORKFLOWER_PYTHON" -m pip install -r "$webapp_dir/requirements.txt"
        cp "$webapp_dir/requirements.txt" "$stamp"
    fi
}

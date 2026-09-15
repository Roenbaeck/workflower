"""Export existing Snowflake tasks to native Workflower workflow JSON."""

import argparse
from getpass import getpass
import hashlib
import json
from pathlib import Path
import re
import sys

try:
    from .workflows import open_service
    from .reverse_engineer import export_graphs
except ImportError:
    from workflows import open_service
    from reverse_engineer import export_graphs


def main(argv=None):
    parser = argparse.ArgumentParser(description='Reverse engineer Snowflake task graphs into Workflower JSON (read-only).')
    parser.add_argument('connection', help='Named Snowflake connection')
    parser.add_argument('directory', type=Path, help='Output directory')
    parser.add_argument('--schema', required=True, help='DATABASE.SCHEMA; quote case-sensitive identifiers using SQL double quotes')
    parser.add_argument('--root', help='Root task name or fully qualified root; omit to export all visible graphs')
    parser.add_argument('--mfa-passcode', action='store_true', help='Prompt securely for a one-time MFA code')
    args = parser.parse_args(argv)
    try:
        options = {'passcode': getpass('Snowflake one-time MFA code: ')} if args.mfa_passcode else {}
        with open_service(args.connection, **options) as service:
            graphs = export_graphs(service.connection, args.schema, args.root)
        output = []
        for graph in graphs:
            name = graph['WORKFLOW']
            slug = re.sub(r'[^A-Za-z0-9_-]+', '_', name).strip('_')[:100] or 'workflow'
            suffix = hashlib.sha256(name.encode()).hexdigest()[:12]
            path = args.directory / f'{slug}_{suffix}.json'
            if path.exists():
                raise FileExistsError(f'Refusing to overwrite {path}; select another output directory')
            output.append((path, json.dumps(graph, indent=2, ensure_ascii=False, default=str) + '\n'))
        if not output:
            print('No visible tasks found.')
            return 0
        args.directory.mkdir(parents=True, exist_ok=True)
        for path, content in output:
            with path.open('x', encoding='utf-8') as handle:
                handle.write(content)
            print(f'Exported {path}')
        print(f'Exported {len(output)} graph(s). Native SQL is preserved; imported tasks install suspended.')
        print('Referenced objects and grants are not exported. Import the JSON into the editor to inspect it.')
        return 0
    except Exception as exc:
        print(f'Task import failed: {exc}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())

"""Command-line adapter for the same renderer and executor as the web API."""

import argparse
from getpass import getpass
from pathlib import Path
import sys

try:
    from .workflows import open_service, parse_bindings
except ImportError:  # python webapp/install.py
    from workflows import open_service, parse_bindings


def main(argv=None):
    parser = argparse.ArgumentParser(description="Render workflow JSON using Snowflake's deployed template, then optionally execute it.")
    parser.add_argument("connection", help="Named Snowflake connection")
    parser.add_argument("directory", type=Path, help="Directory containing JSON bindings")
    parser.add_argument("--template", "-t", default="CreateTaskGraph", help="Template name in Snowflake metadata storage")
    parser.add_argument("--dry-run", "-n", action="store_true", help="Render via Snowflake and write SQL without executing it (requires a connection)")
    parser.add_argument("--mfa-passcode", action="store_true", help="Prompt securely for a one-time MFA code before connecting")
    args = parser.parse_args(argv)
    if not args.directory.is_dir():
        parser.error(f"Directory does not exist: {args.directory}")
    # The template name is also part of an output filename.
    if not args.template or args.template in {".", ".."} or any(c in args.template for c in "/\\"):
        parser.error("Template name must not contain path separators")
    files = sorted(args.directory.glob("*.json"))
    if not files:
        print(f"No .json files found in {args.directory}")
        return 0
    try:
        # Validate all input JSON before executing any DDL.
        workflows = [(path, parse_bindings(path.read_text(encoding="utf-8"))) for path in files]
        output = args.directory / "rendered"
        output.mkdir(exist_ok=True)
        options = {"passcode": getpass("Snowflake one-time MFA code: ")} if args.mfa_passcode else {}
        with open_service(args.connection, **options) as service:
            for path, bindings in workflows:
                print(f"Rendering: {path.name}", flush=True)
                sql = service.render(bindings, args.template)
                sql_file = output / f"{args.template}_{path.stem}.sql"
                sql_file.write_text(sql, encoding="utf-8")
                print(f"Rendered: {sql_file}", flush=True)
                if args.dry_run:
                    continue
                for result in service.execute(sql):
                    print(f"Statement {result.number} executed | sfqid={result.query_id}", flush=True)
        return 0
    except Exception as exc:
        print(f"Install failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

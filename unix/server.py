#!/usr/bin/env python3
"""Workflower for macOS and Linux: the interactive interface.

A page on this machine only (127.0.0.1) that shows the task graphs of a schema, lets you edit one, shows the plan before anything is
changed, and runs, starts and stops graphs. It is the same page as the Windows version (../Workflower/ui) and the same API, served
by this script, which needs only Python 3.7 or later (no packages) and the Snowflake CLI (snow).

The logic is unix/engine.js, which runs inside Snowflake as an anonymous procedure that creates nothing (see PROTOCOL.md); this script
sends each request through `snow sql`, as the shell script `workflower` does, and turns the answers into the JSON that the page expects.
The connection stays in the snow connection profile and never reaches the browser; every call to the API carries a secret that this
process made up when it started, and a request for any other host is refused. Stop with Ctrl+C.

    python3 unix/server.py -c default
    unix/workflower ui -c default
"""

import argparse
import base64
import http.server
import json
import os
import re
import secrets
import shutil
import subprocess
import sys
import tempfile
import threading
import webbrowser
from urllib.parse import urlparse, parse_qs

if sys.version_info < (3, 7):
    sys.stderr.write("workflower: Python 3.7 or later is needed (this is %s)\n" % sys.version.split()[0])
    sys.exit(2)

HERE = os.path.dirname(os.path.abspath(__file__))

CONTENT_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".svg": "image/svg+xml",
    ".png": "image/png",
    ".ico": "image/x-icon",
    ".webmanifest": "application/manifest+json",
}

CSP = ("default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self'; connect-src 'self'; "
       "base-uri 'none'; form-action 'none'; frame-ancestors 'none'")

MAX_BODY = 20 * 1024 * 1024


class ApiError(Exception):
    """A request that cannot be answered; the message goes to the page."""


class Snow(object):
    """The Snowflake CLI: one statement at a time, and the engine."""

    def __init__(self, exe, connection, role, warehouse, engine_path):
        self.exe = exe
        self.connection = connection
        self.role = role
        self.warehouse = warehouse
        self.engine_path = engine_path

    def _run_file(self, sql):
        handle, path = tempfile.mkstemp(suffix=".sql", prefix="workflower-")
        try:
            with os.fdopen(handle, "w", encoding="utf-8", newline="\n") as f:
                f.write(sql)
            cmd = [self.exe, "sql", "--enable-templating", "NONE", "--format", "JSON", "-f", path]
            if self.connection:
                cmd += ["-c", self.connection]
            if self.role:
                cmd += ["--role", self.role]
            if self.warehouse:
                cmd += ["--warehouse", self.warehouse]
            try:
                done = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=600)
            except OSError as e:
                raise ApiError("Could not run the Snowflake CLI (%s): %s" % (self.exe, e))
            except subprocess.TimeoutExpired:
                raise ApiError("The Snowflake CLI did not answer within 10 minutes.")
            out = done.stdout.decode("utf-8", "replace")
            if done.returncode != 0:
                err = done.stderr.decode("utf-8", "replace").strip() or out.strip()
                raise ApiError("Snowflake CLI failed: " + err)
            return out
        finally:
            try:
                os.remove(path)
            except OSError:
                pass

    def query(self, sql):
        """Plain SQL: the rows as a list of dicts (column name to value)."""
        out = self._run_file(sql).strip()
        if not out:
            return []
        try:
            rows = json.loads(out)
        except ValueError:
            # the CLI may print a notice before the result: take the first JSON array in the text
            rows = None
            for match in re.finditer(r"^\[", out, re.M):
                try:
                    rows, _ = json.JSONDecoder().raw_decode(out[match.start():])
                    break
                except ValueError:
                    continue
            if rows is None:
                raise ApiError("The Snowflake CLI answered something that is not JSON: " + out[:300])
        return rows if isinstance(rows, list) else []

    def engine(self, op, args):
        """Runs the engine; returns an Answer."""
        try:
            with open(self.engine_path, "r", encoding="utf-8") as f:
                engine_text = f.read()
        except OSError as e:
            raise ApiError("engine.js is not there (%s): %s" % (self.engine_path, e))
        args_b64 = base64.b64encode(json.dumps(args).encode("utf-8")).decode("ascii")
        sql = ("WITH wf AS PROCEDURE (OP VARCHAR, ARGS VARCHAR) RETURNS VARCHAR LANGUAGE JAVASCRIPT AS\n$$\n" + engine_text +
               "\n$$\nCALL wf('" + op + "', BASE64_DECODE_STRING('" + args_b64 + "'))\n")
        rows = self.query(sql)
        token = None
        if rows and isinstance(rows[0], dict):
            for value in rows[0].values():
                if isinstance(value, str) and re.match(r"^[A-Za-z0-9+/=]{20,}$", value):
                    token = value
                    break
        if token is None:
            raise ApiError("The answer of Snowflake had no result.")
        return Answer(base64.b64decode(token).decode("utf-8"))


class Answer(object):
    """The answer of the engine (PROTOCOL.md): lines of STATUS, EXIT, STEPS, TEXT, JSON and FILE."""

    def __init__(self, text):
        self.status = "ok"
        self.exit = None
        self.steps = None
        self.texts = []
        self.json = None
        self.files = []
        for line in text.split("\n"):
            if not line:
                continue
            word, _, rest = line.partition(" ")
            if word == "STATUS":
                self.status = rest.strip()
            elif word == "EXIT":
                self.exit = int(rest) if rest.strip().isdigit() else None
            elif word == "STEPS":
                self.steps = int(rest) if rest.strip().isdigit() else None
            elif word == "TEXT":
                self.texts.append(base64.b64decode(rest).decode("utf-8"))
            elif word == "JSON":
                self.json = json.loads(base64.b64decode(rest).decode("utf-8"))
            elif word == "FILE":
                name, _, data = rest.partition(" ")
                self.files.append((name, base64.b64decode(data).decode("utf-8")))

    def message(self):
        return "\n".join(t.rstrip("\n") for t in self.texts).strip()

    def require_ok(self):
        if self.status != "ok":
            raise ApiError(self.message() or "The engine reported an error.")
        return self


def pick(row, name):
    """A value of a result row, the column name matched without regard to case."""
    for key, value in row.items():
        if key.lower() == name.lower():
            return value
    return None


def quote_identifier(name):
    return '"' + name.replace('"', '""') + '"'


# --- graphs as the page and the files see them ---------------------------------------------------------------------------------------

TASK_FIELDS = ["name", "after", "finalize", "schedule", "warehouse", "condition", "allowOverlappingExecution", "errorIntegration",
               "comment", "config", "parameters", "state"]


def graph_document(graph):
    """The text of a graph file for a graph from the page (what the engine reads as `doc`)."""
    tasks = []
    for task in graph.get("tasks") or []:
        entry = {}
        for key, value in task.items():
            if key == "info":
                continue
            entry[key] = value
        tasks.append(entry)
    doc = {"format": "workflower-graph", "version": 1, "database": graph.get("database") or "", "schema": graph.get("schema") or "",
           "tasks": tasks}
    return json.dumps(doc)


def engine_input(graph):
    if not isinstance(graph, dict):
        raise ApiError("The request has no graph.")
    doc = graph_document(graph)
    return {"doc": base64.b64encode(doc.encode("utf-8")).decode("ascii"), "files": {}}


def file_text(graph):
    """A graph file for download: the fields that are set, the SQL of each task last, as Export-TaskGraph writes it."""
    tasks = []
    for task in graph.get("tasks") or []:
        entry = {"name": task.get("name")}
        for key in TASK_FIELDS[1:]:
            value = task.get(key)
            if value is None or value == "" or value == [] or value == {}:
                continue
            entry[key] = value
        entry["definition"] = task.get("definition") or ""
        tasks.append(entry)
    doc = {"format": "workflower-graph", "version": 1, "database": graph.get("database") or "", "schema": graph.get("schema") or "",
           "tasks": tasks}
    return json.dumps(doc, indent=2) + "\n"


def graph_root(graph):
    root = graph.get("root")
    if root:
        return root
    for task in graph.get("tasks") or []:
        if not task.get("after") and not task.get("finalize"):
            return task.get("name")
    return None


# --- the routes of the API (the same as the Windows server) -------------------------------------------------------------------------------

class Api(object):
    def __init__(self, snow):
        self.snow = snow
        self.session = None

    def session_info(self):
        if self.session is None:
            rows = self.snow.query("SELECT CURRENT_ACCOUNT_NAME() AS ACCOUNT, CURRENT_ROLE() AS ROLE, CURRENT_WAREHOUSE() AS WAREHOUSE")
            row = rows[0] if rows else {}
            self.session = {"backend": "Cli", "account": pick(row, "account") or self.snow.connection or "",
                            "warehouse": pick(row, "warehouse") or "", "role": pick(row, "role") or ""}
        return self.session

    def check(self, graph):
        answer = self.snow.engine("check", engine_input(graph))
        if answer.status != "ok":
            raise ApiError(answer.message() or "The graph could not be checked.")
        return (answer.json or {}).get("problems") or []

    def read_graphs(self, database, schema, root=None, parameters=False):
        args = {"database": database, "schema": schema, "parameters": bool(parameters)}
        if root:
            args["root"] = root
        answer = self.snow.engine("graphs", args).require_ok()
        return (answer.json or {}).get("graphs") or []

    def route(self, method, path, query, body):
        q = lambda name: (query.get(name) or [""])[0]
        if path == "/api/session":
            return self.session_info()
        if path == "/api/databases":
            rows = self.snow.query("SHOW DATABASES")
            return {"databases": sorted(str(pick(r, "name")) for r in rows if pick(r, "name") is not None)}
        if path == "/api/schemas":
            database = q("database")
            if not database:
                raise ApiError("Say which database.")
            rows = self.snow.query("SHOW SCHEMAS IN DATABASE " + quote_identifier(database))
            names = [str(pick(r, "name")) for r in rows if pick(r, "name") is not None]
            return {"schemas": sorted(n for n in names if n != "INFORMATION_SCHEMA")}
        if path == "/api/graphs":
            database, schema = q("database"), q("schema")
            if not database or not schema:
                raise ApiError("Say which database and schema.")
            return {"graphs": self.read_graphs(database, schema)}
        if path == "/api/graph":
            database, schema, root = q("database"), q("schema"), q("root")
            found = self.read_graphs(database, schema, root, True)
            if not found:
                raise ApiError("There is no graph with the root '%s' in %s.%s (or the role cannot see it)." % (root, database, schema))
            return {"graph": found[0], "problems": self.check(found[0])}
        body = body or {}
        if path == "/api/validate":
            return {"problems": self.check(body.get("graph"))}
        if path == "/api/plan":
            graph = body.get("graph")
            problems = self.check(graph)
            plan = None
            if not any(p.get("severity") == "error" for p in problems):
                answer = self.snow.engine("plan", engine_input(graph)).require_ok()
                plan = (answer.json or {}).get("plan")
            return {"problems": problems, "plan": plan}
        if path == "/api/apply":
            graph = body.get("graph")
            answer = self.snow.engine("apply", engine_input(graph)).require_ok()
            plan = (answer.json or {}).get("plan")
            after = self.read_graphs(graph.get("database"), graph.get("schema"), graph_root(graph), True)
            view, problems = None, []
            if after:
                view = after[0]
                problems = self.check(view)
            return {"plan": plan, "graph": view, "problems": problems}
        if path == "/api/sql":
            answer = self.snow.engine("sql", engine_input(body.get("graph"))).require_ok()
            sql = (answer.json or {}).get("sql")
            if sql is None:
                sql = answer.message()
            return {"sql": sql}
        if path == "/api/export":
            graph = body.get("graph")
            if not isinstance(graph, dict):
                raise ApiError("The request has no graph.")
            parts = [graph.get("database"), graph.get("schema"), graph_root(graph)]
            name = re.sub(r"[^\w.\-]+", "_", ".".join(p for p in parts if p))
            return {"fileName": name + ".json", "text": file_text(graph)}
        if path == "/api/import":
            text = body.get("text")
            if not isinstance(text, str):
                raise ApiError("The request has no text.")
            try:
                json.loads(text)
            except ValueError:
                raise ApiError("The file is not valid JSON.")
            args = {"doc": base64.b64encode(text.encode("utf-8")).decode("ascii"), "files": {}}
            answer = self.snow.engine("import", args).require_ok()
            return {"graph": (answer.json or {}).get("graph"), "problems": (answer.json or {}).get("problems") or []}
        if path == "/api/operate":
            action = body.get("action")
            if action not in ("resume", "suspend", "run", "retry"):
                raise ApiError("Unknown action '%s' (resume, suspend, run or retry)." % action)
            args = {"database": body.get("database"), "schema": body.get("schema"), "root": body.get("root"), "action": action}
            self.snow.engine("operate", args).require_ok()
            found = self.read_graphs(body.get("database"), body.get("schema"), body.get("root"))
            return {"graph": found[0] if found else None}
        if path == "/api/runs":
            hours = int(q("hours")) if re.match(r"^\d+$", q("hours")) else 24
            args = {"database": q("database"), "schema": q("schema"), "root": q("root"), "hours": hours, "limit": 50}
            answer = self.snow.engine("runs", args).require_ok()
            return {"runs": (answer.json or {}).get("runs") or []}
        raise ApiError("Unknown route %s." % path)


# --- the web server --------------------------------------------------------------------------------------------------------------------

def make_handler(api, ui_root, secret, port):
    allowed_hosts = ("127.0.0.1:%d" % port, "localhost:%d" % port)

    class Handler(http.server.BaseHTTPRequestHandler):
        server_version = "Workflower"
        protocol_version = "HTTP/1.0"

        def log_message(self, fmt, *args):
            pass

        def send_bytes(self, status, content_type, data, extra=None):
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Referrer-Policy", "no-referrer")
            if extra:
                for key, value in extra.items():
                    self.send_header(key, value)
            self.end_headers()
            self.wfile.write(data)

        def send_json(self, status, obj):
            self.send_bytes(status, "application/json; charset=utf-8", json.dumps(obj).encode("utf-8"))

        def handle_any(self, method):
            if self.headers.get("Host", "") not in allowed_hosts:
                self.send_bytes(403, "text/plain; charset=utf-8", b"Forbidden")
                return
            parsed = urlparse(self.path)
            path = parsed.path
            if not path.startswith("/api/"):
                if method != "GET":
                    self.send_bytes(405, "text/plain; charset=utf-8", b"Method not allowed")
                    return
                self.serve_static(path)
                return
            given = self.headers.get("X-Workflower-Secret", "")
            if not secrets.compare_digest(given.encode("utf-8"), secret.encode("utf-8")):
                self.send_json(403, {"error": "Forbidden"})
                return
            body = None
            length = int(self.headers.get("Content-Length") or 0)
            if length > MAX_BODY:
                self.send_json(400, {"error": "The request is too large."})
                return
            if length > 0:
                raw = self.rfile.read(length)
                try:
                    body = json.loads(raw.decode("utf-8"))
                except ValueError:
                    self.send_json(400, {"error": "The request is not valid JSON."})
                    return
            try:
                result = api.route(method, path, parse_qs(parsed.query), body)
            except ApiError as e:
                self.send_json(400, {"error": str(e)})
                return
            except Exception as e:  # a bug must not close the connection without an answer
                self.send_json(500, {"error": "%s: %s" % (type(e).__name__, e)})
                return
            self.send_json(200, result)

        def serve_static(self, path):
            name = os.path.basename(path) or "index.html"
            full = os.path.join(ui_root, name)
            if not os.path.isfile(full):
                self.send_bytes(404, "text/plain; charset=utf-8", b"Not found")
                return
            with open(full, "rb") as f:
                data = f.read()
            content_type = CONTENT_TYPES.get(os.path.splitext(name)[1].lower(), "application/octet-stream")
            extra = None
            if name == "index.html":
                data = data.replace(b"__WORKFLOWER_SECRET__", secret.encode("ascii"))
                extra = {"Content-Security-Policy": CSP}
            self.send_bytes(200, content_type, data, extra)

        def do_GET(self):
            self.handle_any("GET")

        def do_POST(self):
            self.handle_any("POST")

    return Handler


def main(argv=None):
    parser = argparse.ArgumentParser(description="Workflower for macOS and Linux: the interface (needs the Snowflake CLI).")
    parser.add_argument("-c", "--connection", default=os.environ.get("WORKFLOWER_CONNECTION", ""), help="the connection of the Snowflake CLI")
    parser.add_argument("--role", default="", help="the role of the session")
    parser.add_argument("--session-warehouse", default="", help="the warehouse of the session")
    parser.add_argument("--port", type=int, default=8765, help="the port on 127.0.0.1 (default 8765)")
    parser.add_argument("--no-browser", action="store_true", help="do not open the page in a browser")
    parser.add_argument("--ui", default=os.environ.get("WORKFLOWER_UI") or os.path.join(HERE, "..", "Workflower", "ui"),
                        help="the folder of the page")
    parser.add_argument("--engine", default=os.environ.get("WORKFLOWER_ENGINE") or os.path.join(HERE, "engine.js"),
                        help="the engine (engine.js)")
    args = parser.parse_args(argv)

    exe = os.environ.get("WORKFLOWER_SNOW") or "snow"
    if shutil.which(exe) is None and not os.path.isfile(exe):
        sys.stderr.write("workflower: the Snowflake CLI (%s) was not found. Install it, or set WORKFLOWER_SNOW to its path.\n" % exe)
        return 2
    ui_root = os.path.abspath(args.ui)
    if not os.path.isfile(os.path.join(ui_root, "index.html")):
        sys.stderr.write("workflower: the interface files are not in %s (use --ui).\n" % ui_root)
        return 2

    snow = Snow(exe, args.connection, args.role, args.session_warehouse, os.path.abspath(args.engine))
    api = Api(snow)
    try:
        info = api.session_info()
    except ApiError as e:
        sys.stderr.write("workflower: cannot connect to Snowflake: %s\n" % e)
        return 2

    secret = secrets.token_hex(32)
    try:
        server = http.server.ThreadingHTTPServer(("127.0.0.1", args.port), make_handler(api, ui_root, secret, args.port))
    except OSError as e:
        sys.stderr.write("workflower: cannot listen on port %d: %s (use --port to choose another)\n" % (args.port, e))
        return 2
    url = "http://127.0.0.1:%d/" % args.port
    print("Workflower is at %s (Ctrl+C stops it)" % url)
    print("Connected to %s as role %s, warehouse %s" % (info.get("account"), info.get("role"), info.get("warehouse")))
    sys.stdout.flush()
    if not args.no_browser:
        threading.Timer(0.5, lambda: webbrowser.open(url)).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())

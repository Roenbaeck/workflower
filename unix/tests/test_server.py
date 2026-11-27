#!/usr/bin/env python3
"""Tests of unix/server.py, the interactive interface for macOS and Linux, over HTTP.

The server runs for real. Instead of the Snowflake CLI it calls tests/fake-snow/snow-mock, which runs the real engine.js on Node against the
fixtures of tests/mock-snow.js (the demo graphs of the Windows version), so the whole chain is exercised except Snowflake itself. Needs
Python 3.7 or later and Node; CI runs it on Linux and macOS.

    python3 unix/tests/test_server.py
"""

import http.client
import json
import os
import re
import socket
import subprocess
import sys
import tempfile
import time
import unittest
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
UNIX = os.path.dirname(HERE)


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


class ServerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix="wf-server-test-")
        env = dict(os.environ)
        env["WORKFLOWER_SNOW"] = os.path.join(HERE, "fake-snow", "snow-mock")
        env["MOCK_SNOW_STATE"] = os.path.join(cls.tmp, "state.json")
        cls.port = free_port()
        cls.base = "http://127.0.0.1:%d" % cls.port
        cls.proc = subprocess.Popen([sys.executable, os.path.join(UNIX, "server.py"), "--port", str(cls.port), "--no-browser"],
                                    env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        page = None
        for _ in range(60):
            if cls.proc.poll() is not None:
                break
            try:
                page = urllib.request.urlopen(cls.base + "/", timeout=5).read().decode("utf-8")
                break
            except (urllib.error.URLError, ConnectionError, OSError):
                time.sleep(0.5)
        if page is None:
            cls.stop()
            raise RuntimeError("the server did not start: " + cls.output())
        cls.page = page
        match = re.search(r'name="workflower-secret" content="([0-9a-f]{64})"', page)
        if not match:
            cls.stop()
            raise RuntimeError("the page carries no secret")
        cls.secret = match.group(1)

    @classmethod
    def output(cls):
        try:
            cls.proc.terminate()
            out, err = cls.proc.communicate(timeout=10)
            return (out + err).decode("utf-8", "replace")
        except Exception:
            return ""

    @classmethod
    def stop(cls):
        try:
            cls.proc.terminate()
            cls.proc.wait(timeout=10)
        except Exception:
            try:
                cls.proc.kill()
            except Exception:
                pass

    @classmethod
    def tearDownClass(cls):
        cls.stop()

    def request(self, method, path, body=None, secret=True):
        headers = {}
        if secret:
            headers["X-Workflower-Secret"] = self.secret
        data = None
        if body is not None:
            data = json.dumps(body).encode("utf-8")
            headers["Content-Type"] = "application/json"
        req = urllib.request.Request(self.base + path, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                return resp.status, json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            raw = e.read().decode("utf-8")
            try:
                return e.code, json.loads(raw)
            except ValueError:
                return e.code, raw

    def get(self, path):
        status, body = self.request("GET", path)
        self.assertEqual(status, 200, "GET %s: %s" % (path, body))
        return body

    def post(self, path, obj):
        status, body = self.request("POST", path, obj)
        self.assertEqual(status, 200, "POST %s: %s" % (path, body))
        return body

    # the tests are numbered because they share the state of the fixtures, as the checks of the Windows API test do

    def test_01_security(self):
        self.assertIn("script-src 'self'", self.csp())
        self.assertEqual(self.request("GET", "/api/session", secret=False)[0], 403)
        status, _ = self.request("GET", "/api/session")
        self.assertEqual(status, 200)
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=10)
        conn.request("GET", "/", headers={"Host": "evil.example"})
        self.assertEqual(conn.getresponse().status, 403, "a request for another host is refused")
        conn.close()
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=10)
        conn.request("GET", "/..%2f..%2fserver.py")
        self.assertNotEqual(conn.getresponse().status, 200, "a path outside the interface folder is not served")
        conn.close()
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=10)
        conn.request("GET", "/api/session", headers={"X-Workflower-Secret": "wrong"})
        self.assertEqual(conn.getresponse().status, 403)
        conn.close()

    def csp(self):
        with urllib.request.urlopen(self.base + "/", timeout=10) as resp:
            return resp.headers.get("Content-Security-Policy", "")

    def test_02_reading(self):
        self.assertEqual(self.get("/api/session")["backend"], "Cli")
        self.assertEqual(self.get("/api/databases")["databases"], ["FINANCE", "SALES"])
        self.assertEqual(self.get("/api/schemas?database=SALES")["schemas"], ["LOAD", "MAINTENANCE"])
        graphs = self.get("/api/graphs?database=SALES&schema=LOAD")["graphs"]
        self.assertEqual(len(graphs), 3)
        one = self.get("/api/graph?database=SALES&schema=LOAD&root=NIGHTLY_ROOT")
        self.assertEqual(len(one["graph"]["tasks"]), 7)
        self.assertEqual(one["graph"]["state"], "started")
        self.assertEqual(len([t for t in one["graph"]["tasks"] if t.get("finalize")]), 1)
        self.assertEqual(len(one["graph"]["tasks"][0]["parameters"]), 2)
        self.assertEqual(one["problems"], [])

    def test_03_checking_and_planning(self):
        graph = self.get("/api/graph?database=SALES&schema=LOAD&root=NIGHTLY_ROOT")["graph"]
        self.assertEqual(self.post("/api/validate", {"graph": graph})["problems"], [])
        broken = json.loads(json.dumps(graph))
        broken["tasks"][1]["after"] = ["NOPE"]
        problems = self.post("/api/validate", {"graph": broken})["problems"]
        self.assertEqual([p["code"] for p in problems if p["code"] == "missing-predecessor"], ["missing-predecessor"])
        planned = self.post("/api/plan", {"graph": broken})
        self.assertIsNone(planned["plan"], "a graph with errors has no plan")
        edited = json.loads(json.dumps(graph))
        edited["tasks"][1]["definition"] = "SELECT 42"
        planned = self.post("/api/plan", {"graph": edited})
        self.assertEqual([s["phase"] for s in planned["plan"]["steps"]], ["suspend", "alter", "resume"])
        self.assertEqual(planned["plan"]["changed"], ["LOAD_CUSTOMERS"])
        self.assertTrue(self.post("/api/plan", {"graph": graph})["plan"]["isEmpty"], "an untouched graph has an empty plan")
        applied = self.post("/api/apply", {"graph": edited})
        self.assertEqual(applied["plan"]["executed"], 3)
        sql = self.post("/api/sql", {"graph": graph})["sql"]
        self.assertIn('CREATE OR REPLACE TASK "SALES"."LOAD"."NIGHTLY_ROOT"', sql)

    def test_04_files(self):
        graph = self.get("/api/graph?database=SALES&schema=LOAD&root=NIGHTLY_ROOT")["graph"]
        exported = self.post("/api/export", {"graph": graph})
        self.assertEqual(exported["fileName"], "SALES.LOAD.NIGHTLY_ROOT.json")
        imported = self.post("/api/import", {"text": exported["text"]})
        self.assertEqual(len(imported["graph"]["tasks"]), 7)
        self.assertEqual(imported["graph"]["root"], "NIGHTLY_ROOT")
        status, body = self.request("POST", "/api/import", {"text": "this is not json"})
        self.assertEqual(status, 400)
        self.assertIn("not valid JSON", body["error"])
        status, body = self.request("POST", "/api/import", {"text": '{"tasks":[{"name":"X","definiton":"oops"}]}'})
        self.assertEqual(status, 400)
        self.assertIn("definiton", body["error"], "a misspelt field is refused and named")

    def test_05_runs_and_operations(self):
        runs = self.get("/api/runs?database=SALES&schema=LOAD&root=NIGHTLY_ROOT&hours=168")["runs"]
        self.assertGreaterEqual(len(runs), 2)
        self.assertTrue(any(r["state"] == "FAILED" for r in runs), "one of the runs failed")
        operated = self.post("/api/operate", {"database": "SALES", "schema": "LOAD", "root": "EVENT_ROOT", "action": "resume"})
        self.assertEqual(operated["graph"]["state"], "started")
        status, _ = self.request("POST", "/api/operate", {"database": "SALES", "schema": "LOAD", "root": "EVENT_ROOT", "action": "explode"})
        self.assertEqual(status, 400)


if __name__ == "__main__":
    unittest.main(verbosity=2)

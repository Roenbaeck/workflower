"""Regression coverage without credentials or a live Snowflake account."""

from contextlib import contextmanager
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient
from webapp import install, server, workflows


class ServiceTests(unittest.TestCase):
    def setUp(self):
        self.connection = MagicMock()
        self.cursor = self.connection.cursor.return_value.__enter__.return_value
        self.service = workflows.WorkflowService(self.connection)

    def test_render_binds_template_and_json(self):
        self.cursor.fetchone.return_value = ("SELECT 1;",)
        bindings = {"WORKFLOW": "O'Reilly", "CF_ID": 9}
        self.assertEqual(self.service.render(bindings, "custom' template"), "SELECT 1;")
        sql, params = self.cursor.execute.call_args.args
        self.assertEqual(sql, "CALL SP_SISULA_RENDER(?, ?)")
        self.assertEqual(params[0], "custom' template")
        self.assertEqual(json.loads(params[1]), bindings)

    def test_stored_id_overrides_untrusted_json_id(self):
        self.cursor.fetchone.return_value = ("SELECT 1;",)
        self.service.render_workflow({"cf_id": 42, "content": '{"CF_ID": 99}'})
        self.assertEqual(json.loads(self.cursor.execute.call_args.args[1][1])["CF_ID"], 42)

    def test_render_errors_never_execute(self):
        for rendered in (None, "", "  ", "ERROR: missing template", "\nERROR: bad syntax"):
            with self.subTest(rendered=rendered):
                self.cursor.fetchone.return_value = (rendered,)
                with self.assertRaises(workflows.RenderError):
                    self.service.render({})
        self.connection.execute_stream.assert_not_called()

    def test_invalid_json_never_reaches_snowflake(self):
        for content in ("{", "[]", "null", '"text"'):
            with self.assertRaises(workflows.InvalidWorkflow):
                self.service.render_workflow({"cf_id": 1, "content": content})
        self.cursor.execute.assert_not_called()

    def test_execution_is_lazy_and_stops_on_failure(self):
        cursor = MagicMock(sfqid="query-1", rowcount=1)
        reached = []

        def execute_stream(stream):
            self.assertEqual(stream.read(), "SELECT 1; SELECT broken;")
            reached.append(1)
            yield cursor
            reached.append(2)
            raise RuntimeError("SQL failed")

        self.connection.execute_stream.side_effect = execute_stream
        results = self.service.execute("SELECT 1; SELECT broken;")
        self.assertEqual(reached, [])
        self.assertEqual(next(results).query_id, "query-1")
        self.assertEqual(reached, [1])
        cursor.close.assert_called_once()
        with self.assertRaisesRegex(RuntimeError, "SQL failed"):
            next(results)
        self.assertEqual(reached, [1, 2])

    def test_connector_keeps_procedure_body_as_one_statement(self):
        from snowflake.connector.connection import SnowflakeConnection

        cursor = MagicMock(sfqid="qid", rowcount=0)
        self.connection.cursor.return_value = cursor
        self.connection.execute_stream.side_effect = lambda stream: SnowflakeConnection.execute_stream(self.connection, stream)
        sql = "CREATE PROCEDURE p() RETURNS VARCHAR LANGUAGE SQL AS $$ BEGIN RETURN 'a;b'; END; $$; SELECT 1;"
        self.assertEqual(len(list(self.service.execute(sql))), 2)
        statements = [call.args[0] for call in cursor.execute.call_args_list]
        self.assertIn("RETURN 'a;b'; END;", statements[0])
        self.assertEqual(statements[1].strip(), "SELECT 1;")

    def test_operation_connections_are_distinct_and_always_closed(self):
        first, second = MagicMock(), MagicMock()
        with patch("snowflake.connector.connect", side_effect=[first, second]), patch.object(workflows, "connection_settings", return_value={}):
            with workflows.open_service() as one:
                self.assertIs(one.connection, first)
            with self.assertRaises(RuntimeError):
                with workflows.open_service() as two:
                    self.assertIs(two.connection, second)
                    raise RuntimeError("failed")
        first.close.assert_called_once()
        second.close.assert_called_once()

    def test_mfa_cache_defaults_respect_explicit_opt_out(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "config.toml"
            with patch.dict(os.environ, {"SNOWFLAKE_CONFIG_FILE": str(config)}):
                for authenticator, option in (("username_password_mfa", "client_request_mfa_token"), ("externalbrowser", "client_store_temporary_credential")):
                    profile = f'[connections.test]\nauthenticator="{authenticator}"\n'
                    config.write_text(profile)
                    self.assertTrue(workflows.connection_settings("test")[option])
                    config.write_text(profile + f'{option}=false\n')
                    self.assertFalse(workflows.connection_settings("test")[option])

    def test_auth_settings_are_preserved_without_password(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "config.toml"
            config.write_text('[connections.test]\naccount="account"\nuser="user"\nauthenticator="externalbrowser"\nrole="editor"\nprivate_key_path="~/key.p8"\n')
            with patch.dict(os.environ, {"SNOWFLAKE_CONFIG_FILE": str(config)}):
                settings = workflows.connection_settings("test")
                self.assertEqual(settings["authenticator"], "externalbrowser")
                self.assertEqual(settings["role"], "editor")
                self.assertEqual(settings["paramstyle"], "qmark")
                self.assertEqual(settings["private_key_file"], str(Path.home() / "key.p8"))
                self.assertNotIn("password", settings)
                with self.assertRaisesRegex(ValueError, "missing"):
                    workflows.connection_settings("missing")


class AdapterTests(unittest.TestCase):
    def setUp(self):
        self.service = MagicMock()
        self.service.get_workflow.return_value = {"cf_id": 42, "name": "Test", "content": "{}"}
        self.service.render_workflow.return_value = "SELECT 1;"
        self.service.render.return_value = "SELECT 1;"
        self.service.execute.side_effect = lambda sql: iter([workflows.StatementResult(1, "qid", 1)])
        self.closed = 0
        self.opened = 0

        @contextmanager
        def factory(*args):
            self.opened += 1
            try:
                yield self.service
            finally:
                self.closed += 1

        self.factory = factory
        self.patch = patch.object(server, "open_service", factory)
        self.patch.start()
        self.addCleanup(self.patch.stop)
        self.client = TestClient(server.app, base_url="http://localhost")
        self.addCleanup(self.client.close)

    def test_static_assets_work_without_a_connection_and_backend_is_private(self):
        for path in ("/", "/editor.css", "/sisula.js", "/templates/CreateTaskGraph.sql"):
            self.assertEqual(self.client.get(path).status_code, 200, path)
        for path in ("/server.py", "/workflows.py", "/requirements.txt", "/.venv/pyvenv.cfg", "/config.toml"):
            self.assertEqual(self.client.get(path).status_code, 404, path)
        self.assertEqual(self.opened, 0)

    def test_foreign_hosts_and_cross_origin_writes_are_rejected(self):
        self.assertEqual(self.client.get("/", headers={"host": "attacker.example"}).status_code, 400)
        response = self.client.post("/api/workflows/42/install", headers={"origin": "https://attacker.example"})
        self.assertEqual(response.status_code, 403)
        self.assertEqual(self.opened, 0)

    def test_regular_and_streaming_install_share_service(self):
        response = self.client.post("/api/workflows/42/install", headers={"origin": "http://localhost"})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["statement_count"], 1)
        response = self.client.post("/api/workflows/42/install/stream")
        self.assertIn("[DONE]", response.text)
        self.assertIn("sfqid=qid", response.text)
        self.assertEqual(self.service.render_workflow.call_count, 2)
        self.assertEqual(self.service.execute.call_count, 2)
        self.assertEqual(self.closed, 2)

    def test_stream_render_failure_reports_error_and_closes_connection(self):
        self.service.render_workflow.side_effect = workflows.RenderError("template missing")
        response = self.client.post("/api/workflows/42/install/stream")
        self.assertIn("[ERROR]", response.text)
        self.assertNotIn("[DONE]", response.text)
        self.service.execute.assert_not_called()
        self.assertEqual(self.closed, 1)

    def test_stream_partial_execution_failure_is_not_success(self):
        def execute(sql):
            yield workflows.StatementResult(1, "qid", 0)
            raise RuntimeError("statement 2 failed")
        self.service.execute.side_effect = execute
        response = self.client.post("/api/workflows/42/install/stream")
        self.assertIn("Statement 1 executed", response.text)
        self.assertIn("[ERROR]", response.text)
        self.assertNotIn("[DONE]", response.text)
        self.assertEqual(self.closed, 1)

    def test_missing_workflow_returns_404_and_closes(self):
        self.service.get_workflow.side_effect = workflows.WorkflowNotFound("Workflow not found")
        self.assertEqual(self.client.get("/api/workflows/Unknown").status_code, 404)
        self.assertEqual(self.closed, 1)

    def test_workflow_names_can_contain_slashes(self):
        response = self.client.get("/api/workflows/Golf%20%2F%20workflow")
        self.assertEqual(response.status_code, 200)
        self.service.get_workflow.assert_called_once_with(name="Golf / workflow")

    def test_cli_dry_run_and_install_use_same_renderer(self):
        with tempfile.TemporaryDirectory(prefix="workflower ' ") as directory:
            path = Path(directory)
            (path / "example.json").write_text('{"WORKFLOW":"Example"}')
            with patch.object(install, "open_service", self.factory), patch("sys.stdout", new_callable=io.StringIO):
                self.assertEqual(install.main(["test", directory, "--dry-run"]), 0)
                self.service.execute.assert_not_called()
                self.assertEqual((path / "rendered/CreateTaskGraph_example.sql").read_text(), "SELECT 1;")
                self.assertEqual(install.main(["test", directory]), 0)
                self.service.execute.assert_called_once_with("SELECT 1;")
        self.assertEqual(self.closed, 2)

    def test_cli_invalid_later_file_prevents_any_execution(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path / "a.json").write_text("{}")
            (path / "b.json").write_text("[]")
            with patch.object(install, "open_service", self.factory), patch("sys.stderr", new_callable=io.StringIO):
                self.assertEqual(install.main(["test", directory]), 1)
        self.assertEqual(self.opened, 0)


if __name__ == "__main__":
    unittest.main()

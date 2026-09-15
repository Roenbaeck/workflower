"""Snowflake access and installation shared by the web API and command line."""

from contextlib import contextmanager
from dataclasses import dataclass
from io import StringIO
import json
import os
from pathlib import Path
import tomllib


class WorkflowNotFound(Exception):
    pass


class InvalidWorkflow(ValueError):
    pass


class RenderError(Exception):
    pass


def connection_settings(name=None):
    """Read the same named profile as the Snowflake CLI, without requiring a password."""
    name = name or os.environ.get("SNOWFLAKE_CONNECTION", "U2C")
    override = os.environ.get("SNOWFLAKE_CONFIG_FILE")
    paths = [Path(override).expanduser()] if override else [
        Path.home() / ".snowflake/config.toml",
        Path.home() / "Library/Application Support/snowflake/config.toml",
    ]
    for path in paths:
        if path.is_file():
            with path.open("rb") as handle:
                config = tomllib.load(handle)
            try:
                settings = dict(config["connections"][name])
            except KeyError as exc:
                raise ValueError(f"Connection {name!r} not found in {path}") from exc
            # CLI calls this private_key_path; the connector uses private_key_file.
            if "private_key_path" in settings:
                settings["private_key_file"] = settings.pop("private_key_path")
            if "private_key_file" in settings:
                settings["private_key_file"] = str(Path(settings["private_key_file"]).expanduser())
            authenticator = settings.get("authenticator", "").lower()
            if authenticator == "username_password_mfa":
                settings.setdefault("client_request_mfa_token", True)
            elif authenticator == "externalbrowser":
                settings.setdefault("client_store_temporary_credential", True)
            settings["paramstyle"] = "qmark"
            return settings
    raise FileNotFoundError(f"Snowflake config not found: {', '.join(map(str, paths))}")


@contextmanager
def open_service(name=None, *, passcode=None):
    # Import and connect lazily: importing the API needs neither credentials nor a session.
    import snowflake.connector

    settings = connection_settings(name)
    if passcode:
        settings["passcode"] = passcode
        settings["passcode_in_password"] = False
    connection = snowflake.connector.connect(**settings)
    try:
        yield WorkflowService(connection)
    finally:
        connection.close()


def parse_bindings(content):
    try:
        bindings = json.loads(content)
    except (json.JSONDecodeError, TypeError) as exc:
        raise InvalidWorkflow(f"Workflow JSON is invalid: {exc}") from exc
    if not isinstance(bindings, dict):
        raise InvalidWorkflow("Workflow JSON must be an object")
    return bindings


@dataclass(frozen=True)
class StatementResult:
    number: int
    query_id: str | None
    row_count: int | None


class WorkflowService:
    def __init__(self, connection):
        self.connection = connection

    def _one(self, sql, params=()):
        with self.connection.cursor() as cursor:
            cursor.execute(sql, params)
            return cursor.fetchone()

    def list_workflows(self):
        with self.connection.cursor() as cursor:
            cursor.execute("""
                SELECT CF_NAM_Configuration_Name, CF_TYP_CFT_ConfigurationType
                FROM metadata.lCF_Configuration
                WHERE CF_TYP_CFT_ConfigurationType = 'Workflow'
                ORDER BY CF_NAM_Configuration_Name
            """)
            return [{"name": row[0], "type": row[1]} for row in cursor.fetchall()]

    def get_workflow(self, *, name=None, cf_id=None):
        column, value = ("CF_ID", cf_id) if cf_id is not None else ("CF_NAM_Configuration_Name", name)
        row = self._one(f"""
            SELECT CF_ID, CF_NAM_Configuration_Name, CF_CNT_Configuration_Content
            FROM metadata.lCF_Configuration
            WHERE {column} = ? AND CF_TYP_CFT_ConfigurationType = 'Workflow'
        """, (value,))
        if row is None:
            raise WorkflowNotFound("Workflow not found")
        return {"cf_id": row[0], "name": row[1], "content": row[2]}

    def save_workflow(self, name, body):
        row = self._one("CALL metadata._ConfigurationUpsert(?, ?, ?)",
                        (name, json.dumps(body), "Workflow"))
        return {"name": name, "cf_id": row[0]}

    def delete_workflow(self, name):
        self.get_workflow(name=name)
        row = self._one("CALL metadata._ConfigurationDelete(?)", (name,))
        return {"status": row[0]}

    def render(self, bindings, template="CreateTaskGraph"):
        if not isinstance(bindings, dict):
            raise InvalidWorkflow("Workflow JSON must be an object")
        row = self._one("CALL SP_SISULA_RENDER(?, ?)", (template, json.dumps(bindings)))
        sql = row[0] if row else None
        if not isinstance(sql, str) or not sql.strip() or sql.lstrip().startswith("ERROR:"):
            raise RenderError(sql or "Template rendering failed")
        for task in bindings.get("TASKS", []):
            native = task.get("native")
            if native and (not native.get("header") or native["header"] not in sql):
                raise RenderError("The deployed template does not support native tasks. Deploy the updated CreateTaskGraph template before installing this import.")
        return sql

    def render_workflow(self, workflow):
        bindings = parse_bindings(workflow["content"])
        bindings["CF_ID"] = workflow["cf_id"]
        return self.render(bindings)

    def execute(self, sql):
        """Execute lazily, reporting each success before starting the next statement.

        DDL can commit independently. Failures propagate and must not be retried
        automatically, since earlier statements may already have taken effect.
        """
        for number, cursor in enumerate(self.connection.execute_stream(StringIO(sql)), 1):
            try:
                result = StatementResult(number, cursor.sfqid, cursor.rowcount)
            finally:
                cursor.close()
            yield result

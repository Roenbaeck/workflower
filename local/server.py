#!/usr/bin/env python3
"""FastAPI server for the Workflow Editor. Reads Snowflake config from env."""
import json
import os
import tomllib
from datetime import datetime
from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse, HTMLResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from snowflake.snowpark import Session

app = FastAPI(title="Workflow Editor")

# --- Snowflake session ---
def create_session():
    conn_name = os.environ.get("SNOWFLAKE_CONNECTION", "U2C")
    paths = [
        os.path.expanduser("~/.snowflake/config.toml"),
        os.path.expanduser("~/Library/Application Support/snowflake/config.toml"),
    ]
    config_path = None
    for p in paths:
        if os.path.exists(p):
            config_path = p
            break
    if not config_path:
        raise FileNotFoundError(f"Config not found at {paths}")
    with open(config_path, "rb") as f:
        cfg = tomllib.load(f)
    conn = cfg["connections"][conn_name]
    return Session.builder.configs({
        "account": conn["account"], "user": conn["user"], "password": conn["password"],
        "host": conn.get("host"), "port": conn.get("port", 443),
        "protocol": conn.get("protocol", "https"), "database": conn.get("database"),
        "schema": conn.get("schema"), "warehouse": conn.get("warehouse"), "role": conn.get("role"),
    }).create()


session = create_session()

# Get the directory containing this file
BASE_DIR = os.path.dirname(os.path.abspath(__file__))

def fetch_workflow_by_name(name: str):
    with session.connection.cursor() as cursor:
        cursor.execute(
            """
            SELECT
                CF_ID,
                CF_NAM_Configuration_Name,
                CF_CNT_Configuration_Content
            FROM metadata.lCF_Configuration
            WHERE CF_NAM_Configuration_Name = ?
            """,
            (name,),
        )
        row = cursor.fetchone()
    if not row:
        return None
    return {"cf_id": row[0], "name": row[1], "content": row[2]}

def fetch_workflow_by_id(cf_id: int):
    with session.connection.cursor() as cursor:
        cursor.execute(
            """
            SELECT
                CF_ID,
                CF_NAM_Configuration_Name,
                CF_CNT_Configuration_Content
            FROM metadata.lCF_Configuration
            WHERE CF_ID = ?
            """,
            (cf_id,),
        )
        row = cursor.fetchone()
    if not row:
        return None
    return {"cf_id": row[0], "name": row[1], "content": row[2]}


def render_install_sql(cf_id: int):
    workflow = fetch_workflow_by_id(cf_id)
    if not workflow:
        raise HTTPException(status_code=404, detail="Workflow not found")

    try:
        bindings = json.loads(workflow["content"])
    except json.JSONDecodeError as exc:
        raise HTTPException(status_code=400, detail=f"Stored workflow JSON is invalid: {exc}") from exc

    if not isinstance(bindings, dict):
        raise HTTPException(status_code=400, detail="Stored workflow JSON must be an object")

    bindings["CF_ID"] = cf_id
    rendered_sql = session.call("SP_SISULA_RENDER", "CreateTaskGraph", json.dumps(bindings))
    if not rendered_sql or (isinstance(rendered_sql, str) and rendered_sql.startswith("ERROR:")):
        raise HTTPException(status_code=500, detail=rendered_sql or "Template rendering failed")

    return workflow, rendered_sql


def install_log_line(level: str, message: str) -> str:
    timestamp = datetime.now().strftime("%H:%M:%S")
    return f"{timestamp} [{level.upper()}] {message}\n"


# --- API routes ---

@app.get("/api/workflows")
def list_workflows():
    rows = session.sql("""
        SELECT CF_NAM_Configuration_Name AS name,
               CF_TYP_CFT_ConfigurationType AS type
        FROM metadata.lCF_Configuration
        ORDER BY CF_NAM_Configuration_Name
    """).collect()
    return [{"name": r["NAME"], "type": r["TYPE"]} for r in rows]


@app.get("/api/workflows/{name}")
def get_workflow(name: str):
    workflow = fetch_workflow_by_name(name)
    if not workflow:
        raise HTTPException(status_code=404, detail="Workflow not found")
    return workflow


@app.put("/api/workflows/{name}")
def save_workflow(name: str, body: dict):
    content = json.dumps(body) if isinstance(body, dict) else body
    cf_id = session.call("metadata._ConfigurationUpsert", name, content, "Workflow")
    return {"name": name, "cf_id": cf_id}

@app.post("/api/workflows/{cf_id}/install")
def install_workflow(cf_id: int):
    workflow, rendered_sql = render_install_sql(cf_id)

    try:
        executed = list(session.connection.execute_string(rendered_sql))
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Install failed: {exc}") from exc

    return {
        "name": workflow["name"],
        "cf_id": cf_id,
        "statement_count": len(executed),
    }


@app.post("/api/workflows/{cf_id}/install/stream")
def install_workflow_stream(cf_id: int):
    workflow = fetch_workflow_by_id(cf_id)
    if not workflow:
        raise HTTPException(status_code=404, detail="Workflow not found")

    def generate():
        yield install_log_line("info", f"Loading workflow CF_ID={cf_id}")
        yield install_log_line("ok", f"Loaded workflow {workflow['name']}")

        try:
            bindings = json.loads(workflow["content"])
        except json.JSONDecodeError as exc:
            yield install_log_line("error", f"Stored workflow JSON is invalid: {exc}")
            return

        if not isinstance(bindings, dict):
            yield install_log_line("error", "Stored workflow JSON must be an object")
            return

        bindings["CF_ID"] = cf_id
        yield install_log_line("info", "Rendering CreateTaskGraph template")
        rendered_sql = session.call("SP_SISULA_RENDER", "CreateTaskGraph", json.dumps(bindings))
        if not rendered_sql or (isinstance(rendered_sql, str) and rendered_sql.startswith("ERROR:")):
            yield install_log_line("error", rendered_sql or "Template rendering failed")
            return

        yield install_log_line("ok", f"Rendered {len(rendered_sql.splitlines())} lines of DDL")
        yield install_log_line("info", "Executing rendered SQL statements")

        statement_count = 0
        try:
            for cursor in session.connection.execute_string(rendered_sql):
                statement_count += 1
                sfqid = getattr(cursor, "sfqid", None)
                rowcount = getattr(cursor, "rowcount", None)
                message = f"Statement {statement_count} executed"
                if sfqid:
                    message += f" | sfqid={sfqid}"
                if isinstance(rowcount, int) and rowcount >= 0:
                    message += f" | rowcount={rowcount}"
                yield install_log_line("ok", message)
        except Exception as exc:
            yield install_log_line("error", f"Install failed: {exc}")
            return

        yield install_log_line("done", f"Install completed for {workflow['name']} ({statement_count} statements)")

    return StreamingResponse(generate(), media_type="text/plain; charset=utf-8")


@app.delete("/api/workflows/{name}")
def delete_workflow(name: str):
    result = session.call("metadata._ConfigurationDelete", name)
    return {"status": result}


# --- Static files ---

@app.get("/", response_class=HTMLResponse)
def index():
    with open(os.path.join(BASE_DIR, "index.html"), "r") as f:
        return f.read()


@app.get("/LayoutEngine.js")
def layout_engine():
    return FileResponse(os.path.join(BASE_DIR, "LayoutEngine.js"))


# --- Run ---

if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", 8000))
    print(f"Starting server on http://localhost:{port}")
    uvicorn.run(app, host="0.0.0.0", port=port)

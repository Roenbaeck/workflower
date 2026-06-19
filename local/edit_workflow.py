import streamlit as st
import streamlit.components.v1 as components
import json
import os
import tomllib
from snowflake.snowpark import Session


def get_local_session():
    """Create a Snowpark session from snow CLI config."""
    conn_name = os.environ.get("SNOWFLAKE_CONNECTION", "U2C")
    # snow CLI stores config in ~/.snowflake/config.toml or
    # ~/Library/Application Support/snowflake/config.toml
    config_paths = [
        os.path.expanduser("~/.snowflake/config.toml"),
        os.path.expanduser("~/Library/Application Support/snowflake/config.toml"),
    ]
    config_path = None
    for p in config_paths:
        if os.path.exists(p):
            config_path = p
            break
    if not config_path:
        raise FileNotFoundError(f"Snowflake config not found. Looked in: {', '.join(config_paths)}")
    with open(config_path, "rb") as f:
        cfg = tomllib.load(f)
    conn = cfg["connections"][conn_name]
    params = {
        "account": conn["account"],
        "user": conn["user"],
        "password": conn["password"],
        "host": conn.get("host"),
        "port": conn.get("port", 443),
        "protocol": conn.get("protocol", "https"),
        "database": conn.get("database"),
        "schema": conn.get("schema"),
        "warehouse": conn.get("warehouse"),
        "role": conn.get("role"),
    }
    return Session.builder.configs(params).create()


session = get_local_session()


def load_layout_engine():
    path = os.path.join(os.path.dirname(__file__), "LayoutEngine.js")
    with open(path, "r") as f:
        return f.read()


st.set_page_config(page_title="Workflow Editor", layout="wide")

st.title("Run locally — workflow edits go to Snowflake")
st.caption("Manage task graph definitions stored in metadata.CF_Configuration")


# ---------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------

@st.cache_data(ttl=5)
def list_workflows():
    rows = session.sql("""
        SELECT CF_NAM_Configuration_Name AS name,
               CF_TYP_CFT_ConfigurationType AS type
        FROM metadata.lCF_Configuration
        ORDER BY CF_NAM_Configuration_Name
    """).collect()
    return [{"name": r["NAME"], "type": r["TYPE"]} for r in rows]


def load_workflow(name):
    result = session.call("metadata._ConfigurationGet", name)
    return result if result else None


def save_workflow(name, content):
    return session.call("metadata._ConfigurationUpsert", name, content, "Workflow")


def delete_workflow(name):
    return session.call("metadata._ConfigurationDelete", name)


def validate_json(text):
    if not text.strip():
        return None, "Content is empty"
    try:
        return json.loads(text), None
    except json.JSONDecodeError as e:
        return None, str(e)


def extract_graph(parsed):
    tasks = parsed.get("TASKS", [])
    nodes = []
    edges = []
    for i, task in enumerate(tasks):
        nodes.append({
            "id": task.get("name", f"task_{i}"),
            "label": task.get("name", f"task_{i}"),
            "is_root": task.get("is_root", False),
            "description": task.get("description", ""),
        })
        for after in (task.get("after") or []):
            edges.append({
                "source": after.get("name", ""),
                "target": task.get("name", f"task_{i}"),
            })
    return {"nodes": nodes, "edges": edges}


def render_graph_html(graph_data):
    graph_json = json.dumps(graph_data)
    layout_js = load_layout_engine()

    html = """<!DOCTYPE html>
<html>
<head>
<style>
  body { margin: 0; overflow: hidden; background: #0e1117; font-family: sans-serif; }
  svg { width: 100%; height: 100%; }
  .node-circle { cursor: grab; }
  .node-circle:active { cursor: grabbing; }
  .node-label { fill: #fafafa; font-size: 11px; pointer-events: none; text-anchor: middle; }
  .edge-line { stroke: #4a9eff; stroke-width: 1.5; fill: none; }
  .root-node { stroke: #ffd700; stroke-width: 2.5; }
</style>
</head>
<body>
<svg id="graph" viewBox="0 0 800 400" width="100%" height="400" style="display:block; background:#0e1117;"></svg>
<script>
function extend(subClass, superClass) {
  var oldProto = subClass.prototype;
  var F = function() {};
  F.prototype = superClass.prototype;
  subClass.prototype = new F();
  subClass.prototype.constructor = subClass;
  subClass.superclass = superClass.prototype;
  var keys = Object.getOwnPropertyNames(oldProto);
  for (var i = 0; i < keys.length; i++) {
    if (keys[i] !== 'constructor') {
      subClass.prototype[keys[i]] = oldProto[keys[i]];
    }
  }
}
__LAYOUT_JS__
var graphData = __GRAPH_JSON__;
var nodes = [], nodeMap = {}, edges = [];
LayoutEngine.init();
var SVG = document.getElementById('graph'), svgNS = 'http://www.w3.org/2000/svg';
graphData.nodes.forEach(function(n, i) {
  var angle = (i / Math.max(graphData.nodes.length, 1)) * 2 * Math.PI;
  var nodeType = n.is_root ? NodeType.ROOT_TASK : NodeType.TASK;
  var node = new Node(n.id, 400 + Math.cos(angle) * 120, 200 + Math.sin(angle) * 100, nodeType);
  node.label = n.label; node.isRoot = n.is_root; node.description = n.description;
  nodes.push(node); nodeMap[n.id] = node;
});
var edgeId = 1000;
graphData.edges.forEach(function(e) {
  var src = nodeMap[e.source], tgt = nodeMap[e.target];
  if (src && tgt) { var edge = new Edge(edgeId++, src, tgt); edges.push(edge); nodes.push(edge); }
});
function screenToSVG(x, y) {
  var pt = SVG.createSVGPoint(); pt.x = x; pt.y = y;
  var ctm = SVG.getScreenCTM();
  if (ctm) return pt.matrixTransform(ctm.inverse());
  return {x: x, y: y};
}
function clearSvg() { while (SVG.firstChild) SVG.removeChild(SVG.firstChild); }
function createElem(tag, attrs) {
  var el = document.createElementNS(svgNS, tag);
  for (var k in attrs) el.setAttribute(k, attrs[k]);
  return el;
}
function render() {
  clearSvg();
  edges.forEach(function(edge) {
    var src = edge.node, tgt = edge.otherNode;
    SVG.appendChild(createElem('path', {
      'class': 'edge-line',
      'd': 'M' + src.xPosition + ',' + src.yPosition + ' Q' + edge.xPosition + ',' + edge.yPosition + ' ' + tgt.xPosition + ',' + tgt.yPosition
    }));
    var dx = tgt.xPosition - edge.xPosition, dy = tgt.yPosition - edge.yPosition, len = Math.sqrt(dx*dx + dy*dy) || 1;
    var ux = dx / len, uy = dy / len, nodeR = tgt.isRoot ? 22 : 18;
    var tipX = tgt.xPosition - ux * (nodeR + 2), tipY = tgt.yPosition - uy * (nodeR + 2), aSize = 8;
    var bX = tipX - ux * aSize, bY = tipY - uy * aSize, pX = -uy * aSize * 0.5, pY = ux * aSize * 0.5;
    SVG.appendChild(createElem('polygon', {
      'points': tipX + ',' + tipY + ' ' + (bX+pX) + ',' + (bY+pY) + ' ' + (bX-pX) + ',' + (bY-pY),
      'fill': '#4a9eff'
    }));
  });
  graphData.nodes.forEach(function(n) {
    var node = nodeMap[n.id]; if (!node) return;
    var r = node.isRoot ? 22 : 18;
    var circle = createElem('circle', {
      'class': 'node-circle' + (node.isRoot ? ' root-node' : ''),
      'cx': node.xPosition, 'cy': node.yPosition, 'r': r,
      'fill': node.isRoot ? '#1a5c1a' : '#1a3a5c',
      'stroke': node.isRoot ? '#ffd700' : '#4a9eff',
      'stroke-width': node.isRoot ? 2.5 : 1.5,
      'data-id': n.id
    });
    SVG.appendChild(circle);
    var label = createElem('text', { 'class': 'node-label', 'x': node.xPosition, 'y': node.yPosition + r + 14 });
    label.textContent = n.label;
    SVG.appendChild(label);
  });
}
var dragNode = null, dragStartX = 0, dragStartY = 0, isDragging = false, DRAG_THRESHOLD = 5;
SVG.addEventListener('mousedown', function(e) {
  if (e.target.classList && e.target.classList.contains('node-circle')) {
    var id = e.target.getAttribute('data-id');
    dragNode = nodeMap[id];
    if (dragNode) { dragStartX = e.clientX; dragStartY = e.clientY; isDragging = false; e.preventDefault(); }
  }
});
SVG.addEventListener('mousemove', function(e) {
  if (dragNode) {
    if (!isDragging) { if (Math.max(Math.abs(e.clientX - dragStartX), Math.abs(e.clientY - dragStartY)) < DRAG_THRESHOLD) return; isDragging = true; dragNode.fixed = true; dragNode.setUnstoppable(true); }
    if (isDragging) {
      var pt = screenToSVG(e.clientX, e.clientY);
      dragNode.xPosition = pt.x; dragNode.yPosition = pt.y; dragNode.xVelocity = 0; dragNode.yVelocity = 0;
      dragNode.start(); LayoutEngine.equilibrium = false; startAnimation(); e.preventDefault();
    }
  }
});
window.addEventListener('mouseup', function(e) {
  if (dragNode) { dragNode.fixed = false; dragNode.setUnstoppable(false); dragNode = null; isDragging = false; }
});
var running = false;
function engine() {
  if (!LayoutEngine.equilibrium) { LayoutEngine.layout(nodes); render(); }
  if (LayoutEngine.equilibrium) { running = false; } else { window.requestAnimationFrame(engine); }
}
function startAnimation() { if (!running) { running = true; LayoutEngine.equilibrium = false; window.requestAnimationFrame(engine); } }
render(); startAnimation();
</script>
</body>
</html>"""
    html = html.replace("__LAYOUT_JS__", layout_js)
    html = html.replace("__GRAPH_JSON__", graph_json)
    return html


# ---------------------------------------------------------------
# Layout
# ---------------------------------------------------------------

col_left, col_right = st.columns([1, 3])

with col_left:
    st.subheader("Workflows")

    workflows = list_workflows()
    names = [w["name"] for w in workflows] if workflows else []

    if st.button("+ New workflow", use_container_width=True):
        st.session_state.selected = "__new__"
        st.session_state.content = json.dumps({
            "WORKFLOW": "NewWorkflow",
            "WAREHOUSE": "COMPUTE_WH",
            "TASK_TIMEOUT": 3600000,
            "MAX_FAILURES": 3,
            "TASKS": []
        }, indent=2)
        st.session_state.pop("workflow_selector", None)
        st.experimental_rerun()

    if not names:
        st.caption("No workflows yet. Create one above.")
    else:
        selected = st.radio(
            "Select a workflow",
            options=names,
            key="workflow_selector",
            label_visibility="collapsed",
        )
        if selected:
            if "selected" not in st.session_state or st.session_state.selected != selected:
                content = load_workflow(selected)
                st.session_state.selected = selected
                st.session_state.content = content if content else ""
                st.session_state.modified = False

with col_right:
    if "selected" not in st.session_state or not st.session_state.selected:
        st.info("Select a workflow from the list or create a new one.")
        st.stop()

    is_new = st.session_state.selected == "__new__"

    parsed, error = validate_json(st.session_state.content)
    if error:
        st.error(f"Invalid JSON: {error}")
        st.stop()

    tasks = parsed.setdefault("TASKS", [])
    task_names = [t.get("name", f"task_{i}") for i, t in enumerate(tasks)]

    def ss(key, fallback):
        return st.session_state.get(key, fallback)

    parsed["WORKFLOW"] = ss("wf_name", parsed.get("WORKFLOW", ""))
    parsed["WAREHOUSE"] = ss("wh", parsed.get("WAREHOUSE", ""))
    parsed["TASK_TIMEOUT"] = ss("timeout", parsed.get("TASK_TIMEOUT", 3600000))
    parsed["MAX_FAILURES"] = ss("max_fail", parsed.get("MAX_FAILURES", 3))
    parsed["CONFIG"] = ss("cfg", parsed.get("CONFIG", ""))

    col_graph, col_props = st.columns([2, 1])

    with col_graph:
        st.caption("Graph")
        if tasks:
            graph_data = extract_graph(parsed)
            components.html(render_graph_html(graph_data), height=350)
        else:
            st.info("No tasks defined yet.")

    with col_props:
        st.caption("Workflow")
        st.text_input("Name", value=parsed.get("WORKFLOW", ""), key="wf_name", label_visibility="collapsed")
        st.text_input("Warehouse", value=parsed.get("WAREHOUSE", ""), key="wh")
        st.number_input("Timeout (ms)", value=parsed.get("TASK_TIMEOUT", 3600000), step=60000, key="timeout")
        st.number_input("Max failures", value=parsed.get("MAX_FAILURES", 3), min_value=0, step=1, key="max_fail")
        st.text_input("Config (JSON)", value=parsed.get("CONFIG", ""), key="cfg")

        st.caption("Tasks")
        if not task_names:
            st.info("No tasks.")
        else:
            sel_idx = st.selectbox("Edit task", range(len(task_names)),
                                   format_func=lambda i: task_names[i], key="task_sel")
            sel_task = tasks[sel_idx]
            sel_pfx = f"t{sel_idx}_"

            if st.button("+ Add task", use_container_width=True):
                tasks.append({"name": "new_task", "description": "", "steps": [], "after": []})
                st.experimental_rerun()

    tab_task, tab_steps, tab_json = st.tabs(["Task", "Steps", "JSON"])

    with tab_task:
        if not task_names:
            st.info("Create a task to get started.")
        else:
            sel_task["name"] = ss(sel_pfx + "name", sel_task.get("name", ""))
            sel_task["description"] = ss(sel_pfx + "desc", sel_task.get("description", ""))
            sel_task["is_root"] = ss(sel_pfx + "root", sel_task.get("is_root", False))
            sel_task["state"] = ss(sel_pfx + "state", sel_task.get("state", "suspended"))
            sel_task["schedule"] = ss(sel_pfx + "sched", sel_task.get("schedule", ""))

            col_t1, col_t2 = st.columns(2)
            with col_t1:
                st.text_input("Name", value=sel_task.get("name", ""), key=sel_pfx + "name")
                st.text_area("Description", value=sel_task.get("description", ""), key=sel_pfx + "desc", height=60)
            with col_t2:
                st.checkbox("Is root", value=sel_task.get("is_root", False), key=sel_pfx + "root")
                st.selectbox("State", ["suspended", "running"],
                             index=0 if sel_task.get("state", "suspended") == "suspended" else 1, key=sel_pfx + "state")
            st.text_input("Schedule (cron)", value=sel_task.get("schedule", "") or "", key=sel_pfx + "sched",
                          help="Set on the root task. Example: USING CRON 0 2 * * * UTC")

            parent_names = [n for i, n in enumerate(task_names) if i != sel_idx]
            after = sel_task.get("after") or []
            task_after = st.multiselect("Run after", options=parent_names,
                                        default=[a.get("name", "") for a in after], key=sel_pfx + "after")
            sel_task["after"] = [{"name": n} for n in task_after] if task_after else None

            if st.button("Remove this task", type="secondary"):
                tasks.pop(sel_idx)
                for k in list(st.session_state.keys()):
                    if k.startswith(sel_pfx):
                        del st.session_state[k]
                st.experimental_rerun()

    with tab_steps:
        if not task_names:
            st.info("Create a task first.")
        else:
            for si, step in enumerate(sel_task.setdefault("steps", [])):
                step_pfx = sel_pfx + f"s{si}_"
                with st.expander(f"Step {si+1}: {step.get('description', 'Not described')}", expanded=si == len(sel_task["steps"]) - 1):
                    step["type"] = ss(step_pfx + "type", step.get("type", "proc"))
                    step["description"] = ss(step_pfx + "desc", step.get("description", ""))
                    st.selectbox("Type", ["proc", "sql", "lineage", "rows", "return_value"],
                                 index=["proc", "sql", "lineage", "rows", "return_value"].index(step.get("type", "proc")),
                                 key=step_pfx + "type")
                    st.text_input("Description", value=step.get("description", ""), key=step_pfx + "desc")

                    if step["type"] == "proc":
                        step["call"] = ss(step_pfx + "call", step.get("call", ""))
                        st.text_input("CALL", value=step.get("call", ""), key=step_pfx + "call")
                    elif step["type"] == "sql":
                        step["sql"] = ss(step_pfx + "sql", step.get("sql", ""))
                        src = ss(step_pfx + "src", (step.get("lineage") or {}).get("source", ""))
                        tgt = ss(step_pfx + "tgt", (step.get("lineage") or {}).get("target", ""))
                        st.text_input("Source", value=src, key=step_pfx + "src")
                        st.text_input("Target", value=tgt, key=step_pfx + "tgt")
                        step["sql"] = st.text_area("SQL", value=step.get("sql", ""), height=80, key=step_pfx + "sql")
                        step["lineage"] = {"source": src, "target": tgt} if (src or tgt) else None
                    elif step["type"] == "lineage":
                        step["source"] = ss(step_pfx + "src", step.get("source", ""))
                        step["target"] = ss(step_pfx + "tgt", step.get("target", ""))
                        st.text_input("Source", value=step.get("source", ""), key=step_pfx + "src")
                        st.text_input("Target", value=step.get("target", ""), key=step_pfx + "tgt")
                    elif step["type"] == "rows":
                        for fld in ["inserted", "updated", "deleted", "merged"]:
                            step[fld] = ss(step_pfx + fld, step.get(fld, 0))
                        col_r1, col_r2 = st.columns(2)
                        col_r1.number_input("Inserted", value=step.get("inserted", 0), key=step_pfx + "inserted")
                        col_r2.number_input("Updated", value=step.get("updated", 0), key=step_pfx + "updated")
                        col_r1.number_input("Deleted", value=step.get("deleted", 0), key=step_pfx + "deleted")
                        col_r2.number_input("Merged", value=step.get("merged", 0), key=step_pfx + "merged")
                    elif step["type"] == "return_value":
                        step["message"] = ss(step_pfx + "msg", step.get("message", ""))
                        st.text_input("Message", value=step.get("message", ""), key=step_pfx + "msg")

            col_s1, col_s2 = st.columns(2)
            with col_s1:
                if st.button("+ Add step", use_container_width=True):
                    sel_task.setdefault("steps", []).append({"type": "proc", "description": ""})
                    st.experimental_rerun()
            with col_s2:
                if sel_task.get("steps") and st.button("Remove last step", use_container_width=True):
                    sel_task["steps"].pop()
                    st.experimental_rerun()

    with tab_json:
        st.caption("Live preview — the JSON updates as you edit the form above.")
        st.code(json.dumps(parsed, indent=2), language="json")

    st.session_state.content = json.dumps(parsed)

    st.write("")
    col_btn1, col_btn2 = st.columns(2)
    with col_btn1:
        if st.button("Save", type="primary", use_container_width=True):
            name = parsed.get("WORKFLOW", st.session_state.selected)
            result = save_workflow(name, st.session_state.content)
            st.cache_data.clear()
            st.session_state.selected = name
            for k in list(st.session_state.keys()):
                if k.startswith("t") and "_" in k:
                    del st.session_state[k]
            st.success(f"Saved (CF_ID={result})")
    with col_btn2:
        if st.button("Delete", type="secondary", use_container_width=True):
            result = delete_workflow(st.session_state.selected)
            st.cache_data.clear()
            del st.session_state.selected
            del st.session_state.content
            st.success(result)
            st.experimental_rerun()

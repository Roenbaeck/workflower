import streamlit as st
import json
from snowflake.snowpark.context import get_active_session

session = get_active_session()

st.set_page_config(page_title="Workflow Editor", layout="wide")

st.title("Workflow Editor")
st.caption("Manage task graph definitions stored in metadata.CF_Configuration")

# ---------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------

@st.cache_data(ttl=5)
def list_workflows():
    """Return list of {name, type} from CF_Configuration."""
    rows = session.sql("""
        SELECT CF_NAM_Configuration_Name AS name,
               CF_TYP_CFT_ConfigurationType AS type
        FROM metadata.lCF_Configuration
        ORDER BY CF_NAM_Configuration_Name
    """).collect()
    return [{"name": r["NAME"], "type": r["TYPE"]} for r in rows]


def load_workflow(name):
    """Load full content of a workflow by name."""
    result = session.call("metadata._ConfigurationGet", name)
    return result if result else None


def save_workflow(name, content):
    """Upsert workflow content."""
    return session.call("metadata._ConfigurationUpsert", name, content, "Workflow")


def delete_workflow(name):
    """Delete a workflow."""
    return session.call("metadata._ConfigurationDelete", name)


def validate_json(text):
    """Return (parsed, error) tuple."""
    if not text.strip():
        return None, "Content is empty"
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError as e:
        return None, str(e)
    return parsed, None


# ---------------------------------------------------------------
# Layout
# ---------------------------------------------------------------

col_left, col_right = st.columns([1, 3])

with col_left:
    st.subheader("Workflows")

    workflows = list_workflows()
    names = [w["name"] for w in workflows] if workflows else []

    # New workflow button
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

    # Workflow list
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
    title = "New workflow" if is_new else st.session_state.selected
    st.subheader(title)

    # JSON editor
    edited = st.text_area(
        "JSON definition",
        value=st.session_state.content,
        height=500,
        key="json_editor",
    )

    if edited != st.session_state.content:
        st.session_state.content = edited
        st.session_state.modified = True

    # Validation
    parsed, error = validate_json(st.session_state.content)
    if error:
        st.error(f"Invalid JSON: {error}")
    elif parsed:
        st.success("Valid JSON")
        # Show summary
        tasks = parsed.get("TASKS", [])
        root = next((t for t in tasks if t.get("is_root") or t.get("schedule")), None)
        st.metric("Tasks", len(tasks))
        if root:
            st.metric("Root task", root.get("name", "?"))
            if root.get("schedule"):
                st.metric("Schedule", root["schedule"])

    # Action buttons
    col_btn1, col_btn2, col_btn3 = st.columns(3)
    with col_btn1:
        if st.button("Save", type="primary", disabled=not parsed, use_container_width=True):
            # Use the workflow name from the JSON as the key
            name = parsed.get("WORKFLOW", st.session_state.selected)
            result = save_workflow(name, st.session_state.content)
            st.cache_data.clear()
            st.session_state.selected = name
            st.session_state.content = st.session_state.content
            st.session_state.modified = False
            st.success(f"Saved (CF_ID={result})")
    with col_btn2:
        if st.button("Delete", type="secondary", use_container_width=True):
            result = delete_workflow(st.session_state.selected)
            st.cache_data.clear()
            del st.session_state.selected
            del st.session_state.content
            st.success(result)
            st.experimental_rerun()
    with col_btn3:
        if st.session_state.get("modified"):
            st.caption("Unsaved changes")

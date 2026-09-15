"""Read native Snowflake task graphs without requiring Workflower metadata."""

import json
import re


class TaskImportError(ValueError):
    pass


def identifier_parts(value):
    """Parse SQL identifiers, including quoted dots and escaped double quotes."""
    parts = []
    position = 0
    pattern = re.compile(r'\s*(?:"((?:[^"]|"")*)"|([A-Za-z_][A-Za-z0-9_$]*))\s*')
    while position < len(value):
        match = pattern.match(value, position)
        if not match:
            raise TaskImportError(f"Invalid Snowflake identifier: {value!r}")
        parts.append(match[1].replace('""', '"') if match[1] is not None else match[2].upper())
        position = match.end()
        if position == len(value):
            return tuple(parts)
        if value[position] != '.':
            break
        position += 1
    raise TaskImportError(f"Invalid Snowflake identifier: {value!r}")


def quoted(parts):
    return '.'.join('"' + part.replace('"', '""') + '"' for part in parts)


def split_task_ddl(ddl):
    """Locate the task's AS clause outside comments, strings and identifiers.

    Preserve both pieces verbatim. EXECUTE AS USER is not the body delimiter.
    No attempt is made to parse or rewrite the body (which can contain scripting).
    """
    tokens = list(re.finditer(r"--[^\n]*|/\*[\s\S]*?\*/|'(?:''|\\.|[^'\\])*'|\"(?:\"\"|[^\"])*\"|\$\$[\s\S]*?\$\$|[A-Za-z_][A-Za-z0-9_]*", ddl))
    words = [token for token in tokens if re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', token[0])]
    if [token[0].upper() for token in words[:4]] != ['CREATE', 'OR', 'REPLACE', 'TASK']:
        raise TaskImportError('Expected CREATE OR REPLACE TASK from GET_DDL')
    for index, token in enumerate(words):
        if token[0].upper() == 'AS' and (index == 0 or words[index - 1][0].upper() != 'EXECUTE'):
            header, body = ddl[:token.end()], ddl[token.end():].strip()
            if not body:
                break
            return header, body[:-1] if body.endswith(";") else body
    raise TaskImportError('Could not identify the task SQL body in GET_DDL')


def _json(value, default):
    if value is None or value == '':
        return default
    try:
        return json.loads(value) if isinstance(value, str) else value
    except json.JSONDecodeError as exc:
        raise TaskImportError('Invalid task relationship metadata') from exc


def _rows(cursor):
    columns = [column[0].lower() for column in cursor.description]
    return [dict(zip(columns, row)) for row in cursor.fetchall()]


def read_tasks(connection, schema):
    parts = identifier_parts(schema)
    if len(parts) != 2:
        raise TaskImportError('Schema must be fully qualified as DATABASE.SCHEMA')
    rows, last = [], None
    while True:
        sql = f'SHOW TASKS IN SCHEMA {quoted(parts)} LIMIT 10000'
        if last is not None:
            sql += " FROM '" + last.replace("'", "''").replace('\\', '\\\\') + "'"
        with connection.cursor() as cursor:
            cursor.execute(sql)
            page = _rows(cursor)
        rows.extend(page)
        if len(page) < 10000:
            break
        next_name = page[-1]['name']
        if next_name == last:
            raise TaskImportError('Task pagination did not advance')
        last = next_name
    return rows


def export_graphs(connection, schema, root=None):
    """Export connected graphs visible to the role, or one root's complete graph."""
    rows = read_tasks(connection, schema)
    by_name = {(r['database_name'], r['schema_name'], r['name']): r for r in rows}
    if len(by_name) != len(rows):
        raise TaskImportError('Duplicate task names in Snowflake metadata')
    links = {}
    finalizes = {}
    for name, row in by_name.items():
        relations = _json(row.get('task_relations'), {})
        if not isinstance(relations, dict):
            raise TaskImportError('Unexpected task relationship metadata')
        predecessors = _json(row.get('predecessors'), relations.get('Predecessors', []))
        if not isinstance(predecessors, list) or not isinstance(relations, dict):
            raise TaskImportError('Unexpected task relationship metadata')
        links[name] = {identifier_parts(value) for value in predecessors}
        if relations.get('FinalizedRootTask'):
            finalizes[name] = identifier_parts(relations['FinalizedRootTask'])
            links[name].add(finalizes[name])
        # Root-side relation also exposes missing/invisible finalizers.
        if relations.get('FinalizerTask'):
            finalizer = identifier_parts(relations['FinalizerTask'])
            if finalizer not in by_name:
                raise TaskImportError(f'Missing or inaccessible finalizer: {quoted(finalizer)}')
            finalizes[finalizer] = name
    for name, parent in finalizes.items():
        links[name].add(parent)
    for name, parents in links.items():
        missing = parents - by_name.keys()
        if missing:
            raise TaskImportError(f'Incomplete graph for {quoted(name)}; missing predecessors: {", ".join(quoted(p) for p in sorted(missing))}')
    neighbours = {name: set(parents) for name, parents in links.items()}
    for name, parents in links.items():
        for parent in parents:
            neighbours[parent].add(name)
    components = []
    remaining = set(by_name)
    while remaining:
        todo, component = [min(remaining)], set()
        while todo:
            name = todo.pop()
            if name not in component:
                component.add(name)
                todo.extend(neighbours[name] - component)
        remaining -= component
        components.append(component)
    if root:
        requested = identifier_parts(root)
        if len(requested) == 1:
            requested = identifier_parts(schema) + requested
        if requested not in by_name:
            raise TaskImportError(f'Task not found or not visible: {root}')
        if links[requested]:
            raise TaskImportError('--root must name a root or standalone task')
        components = [component for component in components if requested in component]
    exports = []
    for component in components:
        roots = sorted(name for name in component if not links[name])
        if len(roots) != 1:
            raise TaskImportError('Expected exactly one root per task graph; metadata may be incomplete or cyclic')
        # Finalizers must be created after the rest of their graph, not as normal children.
        pending = {name: set(component - {name}) if name in finalizes else set(links[name]) for name in component}
        ordered = []
        while pending:
            ready = sorted(name for name, parents in pending.items() if not parents)
            if not ready:
                raise TaskImportError('Cycle in task graph')
            ordered.extend(ready)
            for name in ready:
                del pending[name]
            for parents in pending.values():
                parents.difference_update(ready)
        tasks = []
        for name in ordered:
            row = by_name[name]
            with connection.cursor() as cursor:
                cursor.execute("SELECT GET_DDL('TASK', ?, TRUE)", (quoted(name),))
                result = cursor.fetchone()
            if not result or not result[0]:
                raise TaskImportError(f'No DDL available for {quoted(name)}')
            header, body = split_task_ddl(result[0])
            tasks.append({
                'name': quoted(name), 'description': row.get('comment') or '',
                'schedule': row.get('schedule'), 'is_root': name == roots[0],
                'after': [{'name': quoted(parent)} for parent in sorted(links[name])] or None,
                'state': 'suspended', 'steps': [],
                'native': {'header': header, 'body': body,
                           'source_state': row.get('state'), 'finalizes': quoted(finalizes[name]) if name in finalizes else None,
                           'metadata': row},
            })
        exports.append({
            'WORKFLOW': quoted(roots[0]), 'TASKS': tasks,
            'IMPORT': {'format': 'snowflake-native-v1', 'schema': quoted(identifier_parts(schema)),
                       'notes': ['Imported tasks are set to suspended for installation.',
                                 'Native headers retain schedules, warehouses, conditions and other task options.',
                                 'Finalizer edges identify the finalized root; they are not AFTER dependencies.',
                                 'Referenced procedures, tables, streams, grants and integrations are not exported.',
                                 'Only tasks visible to the connection role can be discovered.']},
        })
    return exports

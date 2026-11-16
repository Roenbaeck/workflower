const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { test } = require('node:test');
const repo = require('./repo');

const script = repo('metadata/generate.js');
const installed = repo('metadata/Install_2_MetadataModel.sql');

function run(args, generatorScript = script) {
    return spawnSync(process.execPath, [generatorScript, ...args], { encoding: 'utf8' });
}

test('rejects invalid generator arguments', () => {
    for (const args of [['--refresh'], ['--output'], ['--output', '--refresh']]) {
        const result = run(args);
        assert.notEqual(result.status, 0);
        assert.match(result.stderr, /usage/i);
    }
});

test('reproduces the installed case-sensitive model', () => {
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'workflower-model-'));
    const output = path.join(directory, 'preview.sql');
    try {
        const result = run(['--output', output]);
        assert.equal(result.status, 0, result.stderr);
        const sql = fs.readFileSync(output, 'utf8');
        assert.match(sql, /CREATE TABLE IF NOT EXISTS metadata\."COT_ContainerType"/);
        assert.match(sql, /CREATE OR REPLACE VIEW metadata\."lTR_TaskRun"/);
        assert.equal(sql, fs.readFileSync(installed, 'utf8').replace(/\r\n/g, '\n'));
    } finally {
        if (fs.existsSync(output)) fs.unlinkSync(output);
        fs.rmdirSync(directory);
    }
});

test('default generation writes the installation script', () => {
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'workflower-default-model-'));
    const files = ['generate.js', 'anchor-generator-snowflake.js', 'MetadataModel.xml', 'Install_2_MetadataModel.sql'];
    try {
        for (const file of files.slice(0, 3)) {
            fs.copyFileSync(repo(`metadata/${file}`), path.join(directory, file));
        }
        const result = run([], path.join(directory, 'generate.js'));
        assert.equal(result.status, 0, result.stderr);
        assert.equal(fs.readFileSync(path.join(directory, files[3]), 'utf8'),
            fs.readFileSync(installed, 'utf8').replace(/\r\n/g, '\n'));
    } finally {
        for (const file of files) {
            const target = path.join(directory, file);
            if (fs.existsSync(target)) fs.unlinkSync(target);
        }
        fs.rmdirSync(directory);
    }
});

test('model callers use the generated case-sensitive identifiers', () => {
    const model = fs.readFileSync(installed, 'utf8');
    const names = new Map();
    for (const match of model.matchAll(/"([A-Za-z_][A-Za-z_0-9]*)"/g)) {
        const name = match[1];
        if (name.includes('_') && name !== name.toUpperCase()) {
            const key = name.toUpperCase();
            assert.ok(!names.has(key) || names.get(key) === name, `ambiguous model name ${key}`);
            names.set(key, name);
        }
    }

    const objects = new Set([...model.matchAll(
        /CREATE (?:OR REPLACE )?(?:TABLE|SEQUENCE|VIEW|FUNCTION) (?:IF NOT EXISTS )?metadata\."([^"]+)"/g
    )].map(match => match[1]));
    const files = [
        'metadata/Install_3_InsertKnotValues.sql',
        'metadata/Install_4_CreateLoggingProcedures.sql',
        'metadata/Install_5_ConfigurationProcedures.sql',
        'metadata/Install_6_StageProcedures.sql',
        'metadata/Install_7_ImportProcedures.sql',
        'metadata/Install_8_StageRetention.sql',
        'metadata/Install_9_ReportingViews.sql',
        'metadata/Install_10_Operations.sql',
        'sql/deploy.sql',
        'webapp/Workflows.ps1',
    ];
    for (const file of files) {
        const source = fs.readFileSync(repo(file), 'utf8').replace(/\\"/g, '"');
        const lines = source.replace(/\/\*[\s\S]*?\*\//g, '').split(/\r?\n/);
        for (const [index, original] of lines.entries()) {
            if (/^\s*(?:--|\/\/|#)/.test(original)) continue;
            const line = original.split('--')[0];
            for (const match of line.matchAll(/\b[A-Za-z_][A-Za-z_0-9]*\b/g)) {
                const name = names.get(match[0].toUpperCase());
                if (!name) continue;
                const before = line.slice(0, match.index);
                const after = line.slice(match.index + match[0].length);
                if (before.endsWith(':') || /\bLET\s*$/i.test(before)) continue;
                assert.ok(before.endsWith('"') && after.startsWith('"') && match[0] === name,
                    `${file}:${index + 1} must quote ${name} exactly`);
            }
            for (const match of line.matchAll(/metadata\.(?:"([^"]+)"|([A-Za-z_][A-Za-z_0-9]*))/gi)) {
                const name = match[1] || match[2];
                if (/^(?:l)?(?:COT|CFT|TKN|GRG|ILS|TRS|TR|CO|CF|TP|OP|IL)_/i.test(name)) {
                    assert.ok(objects.has(name), `${file}:${index + 1} references missing model object ${name}`);
                }
            }
        }
    }
});

test('JavaScript procedures construct SQL with quoted model identifiers', () => {
    const source = fs.readFileSync(repo('metadata/Install_10_Operations.sql'), 'utf8');
    const bodies = [...source.matchAll(/LANGUAGE JAVASCRIPT[\s\S]*?\bAS\s*\$\$([\s\S]*?)\$\$;/g)];
    assert.equal(bodies.length, 3);
    for (const [, body] of bodies) {
        const statements = [];
        const snowflake = {
            createStatement(statement) {
                statements.push(statement);
                return { execute: () => ({ next: () => false }) };
            },
        };
        const execute = new Function('snowflake', 'CF_ID', 'STATE', body);
        assert.throws(() => execute(snowflake, 1, 'running'), /Configuration not found/);
        assert.match(statements[0].sqlText, /metadata\."lCF_Configuration"/);
        assert.match(statements[0].sqlText, /"CF_CNT_Configuration_Content"/);
        assert.match(statements[0].sqlText, /"CF_TYP_CFT_ConfigurationType"/);
        assert.deepEqual(statements[0].binds, [1]);
    }
});

test('template CRUD and rendering query the case-sensitive template view', () => {
    const source = fs.readFileSync(repo('sql/deploy.sql'), 'utf8');
    const bodies = [...source.matchAll(/LANGUAGE JAVASCRIPT[\s\S]*?\bAS\s*\$\$([\s\S]*?)\$\$;/g)];
    assert.ok(bodies.length >= 2);
    for (const operation of ['GET', 'LIST', 'RENDER']) {
        const statements = [];
        const snowflake = {
            createStatement(statement) {
                statements.push(statement);
                return { execute: () => ({ next: () => false }) };
            },
        };
        if (operation === 'RENDER') {
            new Function('snowflake', 'TPL_NAME', 'BINDINGS', bodies[1][1])(snowflake, 'test', '{}');
        } else {
            new Function('snowflake', 'OPERATION', 'TPL_NAME', 'TPL_CONTENT', bodies[0][1])(
                snowflake, operation, 'test', null);
        }
        assert.match(statements[0].sqlText, /metadata\."lTP_Template"/);
        assert.match(statements[0].sqlText, /"TP_(?:CNT_Template_Content|NAM_Template_Name)"/);
    }
});

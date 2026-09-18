/*
    Regenerate metadata/Install_2_MetadataModel.sql from metadata/MetadataModel.xml.

    This runs the Anchor Modeling generator (https://www.anchormodeling.com/modeler/test)
    outside the browser, so the model can be regenerated without opening the tool and
    copying the result by hand. It uses the modeler's own Sisulator and its published
    Snowflake sisula scripts, which are cached under metadata/.anchor/ on first run.

    The only substitution is MAP.key.tie: the modeler builds a tie's key with
    document.evaluate, which xmldom does not provide. The replacement walks the same child
    elements in document order and produces the same key.

    Usage:
        node metadata/generate.js            # regenerate from cache, fetch if absent
        node metadata/generate.js --refresh  # re-fetch the generator from anchormodeling
*/

const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const BASE = 'https://roenbaeck.github.io/anchor/';
const HERE = __dirname;
const CACHE = path.join(HERE, '.anchor');
const TARGET = 'Snowflake';
const TEMPORALIZATION = 'uni';

const refresh = process.argv.includes('--refresh');

async function asset(relative) {
    const cached = path.join(CACHE, relative);
    if (!refresh && fs.existsSync(cached)) return fs.readFileSync(cached, 'utf8');
    const response = await fetch(BASE + relative);
    if (!response.ok) throw new Error(`${relative}: HTTP ${response.status}`);
    const text = await response.text();
    fs.mkdirSync(path.dirname(cached), { recursive: true });
    fs.writeFileSync(cached, text, 'utf8');
    return text;
}

function domParser() {
    try {
        return new (require('@xmldom/xmldom').DOMParser)();
    } catch (e) {
        throw new Error('Missing dependency. Run: npm install @xmldom/xmldom');
    }
}

// The modeler's MAP, with the XPath-based tie key replaced by an equivalent walk.
function buildMap(Sisulator) {
    const attr = (x, f) => f.getAttribute('mnemonic');
    const typeRole = (x, f) => f.getAttribute('type') + '_' + f.getAttribute('role');
    return {
        description: 'models from Anchor Modeling, http://www.anchormodeling.com',
        root: 'schema',
        key: {
            knot: attr, anchor: attr, nexus: attr, attribute: attr,
            tie: function (xml, fragment) {
                const parts = [];
                for (let n = fragment.firstChild; n; n = n.nextSibling) {
                    if (n.nodeType === 1 && n.getAttribute && n.getAttribute('role')) {
                        parts.push(n.getAttribute('type') + '_' + n.getAttribute('role'));
                    }
                }
                return parts.join('_');
            },
            anchorRole: typeRole, knotRole: typeRole, role: typeRole,
            key: (x, f) => f.getAttribute('of') + '|' + f.getAttribute('route') + '|' + f.getAttribute('stop'),
        },
        replacer: function (name) {
            if (name === 'anchorRoles' || name === 'knotRoles') return 'roles';
            if (name === 'nexuss') return 'nexuses';
            return name;
        },
    };
}

async function main() {
    const modelPath = path.join(HERE, 'MetadataModel.xml');
    const outPath = path.join(HERE, 'Install_2_MetadataModel.sql');

    const sisulatorSource = await asset('modules/Sisulator.js');
    const directiveName = `${TARGET}_${TEMPORALIZATION}.directive`;
    const directive = await asset(directiveName);

    // Pre-fetch every script the directive names, so the generator runs from cache.
    const scripts = directive.split(/\r?\n/).map(s => s.trim()).filter(s => s && !s.startsWith('#'));
    const sources = {};
    for (const script of scripts) sources[script] = await asset(script);

    const sandbox = { console, DEBUG: false };
    vm.createContext(sandbox);
    vm.runInContext(sisulatorSource, sandbox, { filename: 'Sisulator.js' });
    const Sisulator = sandbox.Sisulator;

    const xml = domParser().parseFromString(fs.readFileSync(modelPath, 'utf8'), 'application/xml');

    // The directive callback the modeler passes in: no argument returns the directive
    // itself, an argument returns that script.
    const directives = async (name) => (name ? sources[name] : directive);

    const sql = await Sisulator.sisulate(xml, buildMap(Sisulator), directives);
    if (!sql || sql.length < 1000) throw new Error('Generation produced no SQL');

    fs.writeFileSync(outPath, sql, 'utf8');
    const tables = (sql.match(/CREATE TABLE IF NOT EXISTS/g) || []).length;
    console.log(`Wrote ${path.relative(process.cwd(), outPath)}`);
    console.log(`${sql.split('\n').length} lines, ${tables} tables, target ${TARGET}/${TEMPORALIZATION}`);
}

main().catch(e => { console.error('Generation failed:', e.message); process.exit(1); });

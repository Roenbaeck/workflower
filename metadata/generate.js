/*
    Generate the case-sensitive Snowflake metadata model.

    Usage:
        node metadata/generate.js [--output <model.sql>]
*/

const fs = require('node:fs');
const path = require('node:path');
const generator = require('./anchor-generator-snowflake.js');

const here = __dirname;
const installed = path.join(here, 'Install_2_MetadataModel.sql');
const args = process.argv.slice(2);

function main() {
    if (args.length !== 0 &&
        (args.length !== 2 || args[0] !== '--output' || !args[1] || args[1].startsWith('--'))) {
        throw new Error('Usage: node metadata/generate.js [--output <model.sql>]');
    }

    const output = args.length ? path.resolve(args[1]) : installed;
    const xml = fs.readFileSync(path.join(here, 'MetadataModel.xml'), 'utf8');
    const sql = generator.generate(xml, 'uni');
    if (!sql || sql.length < 1000) throw new Error('Generation produced no SQL');
    fs.writeFileSync(output, sql, 'utf8');
    const tables = (sql.match(/CREATE TABLE IF NOT EXISTS/g) || []).length;
    console.log(`Wrote case-sensitive model ${output}`);
    console.log(`${sql.split('\n').length} lines, ${tables} tables, target Snowflake/uni`);
}

try {
    main();
} catch (error) {
    console.error('Generation failed:', error.message);
    process.exitCode = 1;
}

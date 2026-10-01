// The Sisula engine in this repository is not edited here. webapp/sisula.js is a copy of the
// reference renderer in the sisula repository, taken at the commit recorded in
// webapp/sisula.lock.json by tools/sync-sisula.ps1, and so are the language reference
// (docs/SISULA.md) and the shared fixtures in tests/sisula-fixtures.
//
// These tests check two things:
//   1. that the copies are the ones the lock names, so a hand edit is noticed;
//   2. that the copy passes every shared fixture (a template, bindings and the expected output).
//
// To change the engine, change it in the sisula repository, then update the copy with
//   .\tools\sync-sisula.ps1
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test').test;
const repo = require('./repo.js');
const sisulate = require('../webapp/sisula.js');

const HOW_TO_FIX = ' Do not edit the vendored Sisula files. Run .\\tools\\sync-sisula.ps1 to restore them, or to update to a newer sisula version.';

// SHA-256 of a file with CRLF turned into LF, so that a Windows checkout and a Linux one agree.
function hashOf(relative) {
    const text = fs.readFileSync(repo(relative), 'latin1').split('\r\n').join('\n');
    return crypto.createHash('sha256').update(Buffer.from(text, 'latin1')).digest('hex');
}

const lock = JSON.parse(fs.readFileSync(repo('webapp/sisula.lock.json'), 'utf8'));
const fixtureDirectory = repo('tests/sisula-fixtures');

test('webapp/sisula.js is the copy of the reference renderer that the lock names', function () {
    assert.equal(hashOf('webapp/sisula.js'), lock.engine.sha256,
        'webapp/sisula.js differs from sisula ' + lock.commit.slice(0, 7) + ' (' + lock.engine.from + ').' + HOW_TO_FIX);
});

test('docs/SISULA.md is the copy of the language reference that the lock names', function () {
    assert.equal(hashOf('docs/SISULA.md'), lock.language.sha256,
        'docs/SISULA.md differs from sisula ' + lock.commit.slice(0, 7) + ' (' + lock.language.from + ').' + HOW_TO_FIX);
});

test('the vendored fixtures are exactly the ones the lock names', function () {
    const locked = Object.keys(lock.fixtures.files).sort();
    const present = fs.readdirSync(fixtureDirectory).filter(function (name) { return /\.json$/.test(name); }).sort();
    assert.deepEqual(present, locked, 'The fixture files differ from the lock.' + HOW_TO_FIX);
    locked.forEach(function (name) {
        assert.equal(hashOf('tests/sisula-fixtures/' + name), lock.fixtures.files[name],
            'tests/sisula-fixtures/' + name + ' differs from the lock.' + HOW_TO_FIX);
    });
});

// One test per fixture, named after it. A fixture with "error" expects the renderer to throw a
// message that contains that text; every other fixture expects exactly the output in "expected".
Object.keys(lock.fixtures.files).sort().forEach(function (file) {
    const cases = JSON.parse(fs.readFileSync(path.join(fixtureDirectory, file), 'utf8'));
    cases.forEach(function (c) {
        test(file + ': ' + c.name, function () {
            const bindings = JSON.stringify(c.bindings);
            if (c.error !== undefined) {
                assert.throws(function () { sisulate(c.template, bindings); }, function (e) {
                    return String(e && e.message).indexOf(c.error) >= 0;
                });
            } else {
                assert.equal(sisulate(c.template, bindings), c.expected);
            }
        });
    });
});

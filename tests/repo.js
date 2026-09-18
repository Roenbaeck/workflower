// Resolve a path inside the repository regardless of the directory the tests are run from,
// so `node --test tests/` and `node --test` from within tests/ both work.
const path = require('node:path');

module.exports = function repo(relative) {
    return path.join(__dirname, '..', ...relative.split('/'));
};

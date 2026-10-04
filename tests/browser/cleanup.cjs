'use strict';
const fs = require('node:fs');
const path = require('node:path');
module.exports = async () => {
  const response = await fetch('http://127.0.0.1:4173/__cleanup', {method: 'POST',
    headers: {'content-type': 'application/json', 'x-fixture-token': process.env.ATTENDUS_FIXTURE_TOKEN}, body: '{}'});
  const result = await response.json();
  fs.mkdirSync(process.env.ATTENDUS_BROWSER_EVIDENCE, {recursive: true});
  fs.writeFileSync(path.join(process.env.ATTENDUS_BROWSER_EVIDENCE, 'cleanup.json'), JSON.stringify(result, null, 2));
  if (!response.ok || result.complete !== true) throw new Error('Owned browser fixtures were not fully cleaned.');
};

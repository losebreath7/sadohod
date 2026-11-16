const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

(async () => {
  for (const mode of ['same', 'old', 'offline']) {
    const element = {textContent: ''};
    const context = {window: {}, document: {querySelectorAll: () => [element]}};
    vm.createContext(context);
    vm.runInContext(fs.readFileSync(path.join(__dirname, 'build_info.js'), 'utf8'), context);
    context.fetch = async () => {
      if (mode === 'offline') throw new Error('offline');
      return {ok: true, json: async () => mode === 'same'
        ? context.window.SADOHOD_BUILD : {version: '0.7.1'}};
    };
    vm.runInContext(fs.readFileSync(path.join(__dirname, 'build_label.js'), 'utf8'), context);
    await new Promise(resolve => setImmediate(resolve));
    assert.ok(element.textContent.includes(context.window.SADOHOD_BUILD.label));
    if (mode === 'same') assert.ok(!element.textContent.includes('версии отличаются'));
    if (mode === 'old') assert.ok(element.textContent.includes('версии отличаются'));
    if (mode === 'offline') assert.ok(element.textContent.includes('API: недоступен'));
  }
  console.log('Admin build labels: 3 scenarios passed');
})().catch(error => { console.error(error); process.exitCode = 1; });

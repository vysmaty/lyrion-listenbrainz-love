'use strict';
const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const loaders = JSON.parse(fs.readFileSync(0, 'utf8'));
const moduleSource = fs.readFileSync('Plugins/ListenBrainzLove/HTML/EN/plugins/ListenBrainzLove/html/material-love.js','utf8');
let count=0,failed=0;
function check(name, fn) { count++;try {fn();console.log(`ok ${count} - ${name}`);}catch(error) {failed++;console.log(`not ok ${count} - ${name}\n# ${error.message}`);} }
const tick=()=>new Promise(resolve=>setImmediate(resolve));
function fixture(cold) {
 const calls=[],notices=[],scripts=[];
 const context=vm.createContext({window:{},bus:{$emit:(...args)=>notices.push(args)},lmsOptions:{lang:'cs'},Map,Promise,
  // Decoy globals must never supply the selected item to a minified action.
  player:{id:'wrong-player'},item:{id:'track_id:999'},
  document:{head:{appendChild:s=>scripts.push(s)},createElement:()=>({})},
  lmsCommand:(pid,command)=>new Promise((resolve,reject)=>calls.push({pid,command,resolve,reject}))});
 if (!cold) vm.runInContext(moduleSource,context);
 // Material 6.4.14 invokes direct eval in a function whose arguments have
 // been renamed by its production minifier. Keep that exact scope contract.
 vm.runInContext('function doCustomAction(a,b,c){if(a.script)eval(a.script);}',context);
 return {context,calls,notices,scripts};
}
(async function () {
 for (const id of ['track_id:73','track_id:-73',73]) {
  const f=fixture(false);f.context.doCustomAction({script:loaders.love},{id:'selected-player'},{id});await tick();
  check(`minified Material passes selected player for ${id}`,()=>assert.equal(f.calls[0]?.pid,'selected-player'));
  check(`minified Material passes selected queue ID ${id}`,()=>assert.equal(f.calls[0]?.command[2],'selected_id:track_id:'+String(id).replace(/^track_id:/,'')));
  if (f.calls[0]) f.calls[0].resolve({data:{result:{ok:1,score:1,message:'Selected Love verified'}}});await tick();
  check(`selected queue action confirms through a native popup ${id}`,()=>assert.deepEqual(f.notices.at(-1),['showMessage','Selected Love verified',6]));
 }
 const cold=fixture(true);
 cold.context.doCustomAction({script:loaders.love},{id:'clicked-player'},{id:'track_id:81'});
 cold.context.player={id:'new-player'};cold.context.item={id:'track_id:999'};
 vm.runInContext(moduleSource,cold.context);cold.scripts[0].onload();await tick();
 check('cold script loading retains the original selected player',()=>assert.equal(cold.calls[0]?.pid,'clicked-player'));
 check('cold script loading retains the original selected track',()=>assert.equal(cold.calls[0]?.command[2],'selected_id:track_id:81'));
 const bad=fixture(false);bad.context.doCustomAction({script:loaders.love},{id:'selected-player'},{id:"track_id:73');window.injected=true;//"});await tick();
 check('malformed IDs never reach JSONRPC',()=>assert.equal(bad.calls.length,0));
 check('IDs remain values and cannot become executable script',()=>assert.equal(bad.context.window.injected,undefined));
 const missing=fixture(false);missing.context.doCustomAction({script:loaders.love},{id:'selected-player'},undefined);await tick();
 check('missing selection cannot fall back to the current/global track',()=>assert.equal(missing.calls.length,0));
 const footer=fixture(false);let enabled=0;footer.context.window.ListenBrainzLoveMaterial.enableButton=()=>enabled++;
 vm.runInContext(loaders.button,footer.context);
 check('standalone custom.js loader works without a Material action arguments object',()=>assert.equal(enabled,1));
 const error=fixture(false);error.context.doCustomAction({script:loaders.love},{id:'selected-player'},{id:'track_id:73'});await tick();
 if(error.calls[0]) error.calls[0].resolve({data:{result:{ok:0,message:'Selected recording lookup failed'}}});await tick();
 check('selected queue failure is reported by the native error popup',()=>assert.deepEqual(error.notices.at(-1),['showError',undefined,'Selected recording lookup failed',12]));
 check('failed selected queue action never retries automatically',()=>assert.equal(error.calls.length,1));
 console.log(`1..${count}`);process.exitCode=failed?1:0;
})().catch(error=>{console.log('Bail out! '+error.message);process.exitCode=1});

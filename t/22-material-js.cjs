'use strict';
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
let count = 0, failed = 0;
function check(name, fn) {
    count++;
    try { fn(); process.stdout.write(`ok ${count} - ${name}\n`); }
    catch (error) { failed++; process.stdout.write(`not ok ${count} - ${name}\n# ${String(error.message).replace(/\n/g, '\n# ')}\n`); }
}
class Element {
    constructor(tag) { this.tag = tag; this.children = []; this.attrs = {}; this.dataset = {}; this.events = {}; this.isConnected = false; this.className='';this.classList={add:name=>{this.className+=' '+name;}}; }
    appendChild(node) { this.children.push(node); node.isConnected = true; return node; }
    setAttribute(key, value) { this.attrs[key] = value; }
    querySelector(tag) { for (const child of this.children) { if (child.tag === tag || (tag.startsWith('.') && child.className.split(' ').includes(tag.slice(1)))) return child; const result = child.querySelector(tag); if (result) return result; } return null; }
    addEventListener(name, fn) { this.events[name] = fn; }
}
const bar = new Element('div'), head = new Element('head'), body = new Element('body');
const details=new Element('div'), action=new Element('div');details.className='np-bar-details';action.className='v-list__tile__action';bar.appendChild(details);details.appendChild(action);
const calls = [], notices = [], handlers = new Map(), timers = [];
const bus = {$on(name, fn) { handlers.set(name, fn); }, $emit(name, ...args) { notices.push([name,...args]); if (handlers.has(name)) handlers.get(name)(...args); }};
const store = {state:{player:{id:'player-one'}}};
const window = {};
const context = vm.createContext({window, bus, store, lmsOptions:{lang:'cs'}, Map, Promise, setTimeout:fn=>timers.push(fn),
    document:{head,body,getElementById:id=>id==='np-bar'?bar:null,createElement:tag=>new Element(tag),createElementNS:(_,tag)=>new Element(tag)},
    MutationObserver:class {observe() {}},
    lmsCommand:(pid,command)=>new Promise((resolve,reject)=>calls.push({pid,command,resolve,reject}))});
const source = fs.readFileSync('Plugins/ListenBrainzLove/HTML/EN/plugins/ListenBrainzLove/html/material-love.js','utf8');
const finish = (call,data) => call.resolve({data:{result:data}});
const tick = () => new Promise(resolve=>setImmediate(resolve));
const event = {stopPropagation(){},preventDefault(){}};
(async function () {
    vm.runInContext(source,context);
    const api = window.ListenBrainzLoveMaterial;
    check('context module does not insert a footer without opt-in',()=>assert.equal(action.children.length,0));
    await api.love('player-one','bad\');injection');
    check('invalid selection never reaches JSONRPC',()=>assert.equal(calls.length,0));
    api.enableButton(); api.enableButton();
    check('opt-in inserts exactly one independent button',()=>assert.equal(action.children.length,1));
    const button = action.children[0];
    check('empty initial selection is disabled',()=>assert.equal(button.disabled,true));
    finish(calls[0],{playlist_loop:[{id:42,title:'First Song',artist:'Artist'}]}); await tick();
    check('initial playback state only reads feedback',()=>assert.equal(calls[1].command[1],'status'));
    finish(calls[1],{ok:1,score:0,message:'Not loved'}); await tick();
    check('verified zero feedback gives an outline heart',()=>assert.equal(button.dataset.state,'outline'));
    check('button has a Czech accessible action label',()=>assert.match(button.attrs['aria-label'],/aktuální skladbu/));
    button.events.click(event); button.events.click(event);
    check('double click sends only one Love request',()=>assert.equal(calls.filter(x=>x.command[1]==='action').length,1));
    check('Love captures the clicked track ID',()=>assert.equal(calls[2].command[2],'selected_id:track_id:42'));
    check('button is disabled while feedback is being verified',()=>assert.equal(button.disabled,true));
    check('heart is not optimistically filled before verification',()=>assert.equal(button.dataset.state,'outline'));
    finish(calls[2],{ok:1,score:1,linked:1,message:'Love confirmed'}); await tick();
    check('verified Love fills the heart',()=>assert.equal(button.dataset.state,'filled'));
    check('verified Love shows a native success popup',()=>assert.equal(notices.at(-1)[0],'showMessage'));
    button.events.click(event);button.events.click(event);
    check('click on a loved heart requests removal',()=>assert.equal(calls.at(-1).command[1],'unlove'));
    check('double click cannot repeat Unlove',()=>assert.equal(calls.filter(x=>x.command[1]==='unlove').length,1));
    check('pending removal keeps the verified heart filled',()=>assert.equal(button.dataset.state,'filled'));
    finish(calls.at(-1),{ok:1,score:0,message:'Not loved'}); await tick();
    check('verified removal clears the heart',()=>assert.equal(button.dataset.state,'outline'));
    button.events.click(event); const uncertain=calls.at(-1);uncertain.reject(new Error('lost response'));await tick();
    check('lost write response leaves state unknown',()=>assert.equal(button.dataset.state,'unknown'));
    check('lost write response shows a failure/uncertainty popup',()=>assert.equal(notices.at(-1)[0],'showError'));
    const before=calls.filter(x=>x.command[1]==='action').length;button.events.click(event);
    check('uncertain write is followed by a read rather than a repeated POST',()=>assert.equal(calls.filter(x=>x.command[1]==='action').length,before));
    finish(calls.at(-1),{ok:1,score:0,message:'Not loved'});await tick();
    button.events.click(event);const oldLove=calls.at(-1);
    bus.$emit('playerStatus',{current:{id:43,title:'Second Song',artist:'Artist'}});const newRead=calls.at(-1);
    finish(oldLove,{ok:1,score:1,message:'Old song saved'});await tick();
    check('late Love result cannot fill a different track heart',()=>assert.equal(button.dataset.state,'unknown'));
    finish(newRead,{ok:1,score:0,message:'Second not loved'});await tick();
    check('new track retains its own verified state',()=>assert.equal(button.dataset.state,'outline'));
    bus.$emit('playerStatus',{current:{id:43,title:'New radio title',artist:'Artist'}});
    check('same stream ID with changed metadata triggers a fresh read',()=>assert.equal(calls.at(-1).command[1],'status'));
    const staleRead=calls.at(-1);store.state.player.id='player-two';bus.$emit('playerChanged');
    bus.$emit('playerStatus',{current:{id:43,title:'Other player song',artist:'Artist'}});const playerRead=calls.at(-1);
    finish(staleRead,{ok:1,score:1,message:'Old player loved'});await tick();
    check('late read cannot leak a previous player state',()=>assert.equal(button.dataset.state,'unknown'));
    finish(playerRead,{ok:0,error:'Missing artist or title',message:'Cold metadata'});await tick();
    check('cold metadata schedules exactly one bounded retry',()=>assert.equal(timers.length,1));
    timers.shift()();finish(calls.at(-1),{ok:0,error:'Missing artist or title',message:'Cold metadata'});await tick();
    check('cold metadata retry never loops',()=>assert.equal(timers.length,0));
    const beforeRead=calls.length;button.events.contextmenu(event);
    check('secondary click reads status without writing',()=>assert.equal(calls[beforeRead].command[1],'status'));
    check('explicit refresh bypasses the short feedback cache',()=>assert.ok(calls[beforeRead].command.includes('refresh:1')));
    finish(calls.at(-1),{ok:0,error:'rate limit',message:'Wait'});await tick();
    check('rate limit never schedules an automatic retry',()=>assert.equal(timers.length,0));
    check('all requests stay on the LMS command boundary',()=>assert.ok(calls.every(x=>x.command[0]==='listenbrainzlove'||x.command[0]==='status')));
    process.stdout.write(`1..${count}\n`);process.exitCode=failed?1:0;
})().catch(error=>{process.stdout.write('Bail out! '+error.stack.replace(/\n/g,' ')+'\n');process.exitCode=1;});

// Integration regression for the complete installed Material Skin 6.4.14
// parser and text-action handlers (see fixtures/material-6.4.14.cjs). Upstream: https://github.com/CDrummond/lms-material
// Copyright (c) 2018-2026 Craig Drummond <craig.p.drummond@gmail.com>
// MIT License: Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation files (the
// "Software"), to deal in the Software without restriction, including without
// limitation the rights to use, copy, modify, merge, publish, distribute,
// sublicense, and/or sell copies of the Software, and to permit persons to whom
// the Software is furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
'use strict';
const fs=require('node:fs'),assert=require('node:assert/strict');
const input=JSON.parse(fs.readFileSync(0,'utf8'));
const calls=[],bus={$emit:(...args)=>calls.push(args)};
function msgIsEmpty(text){return !text;}
function browseGoBack(){throw new Error('Popup must retain the song details, not return home');}
function browseGoHome(){throw new Error('Popup must not open the home page');}


const source=input.item;
assert.equal(source.type,undefined,'Source row must allow Material to infer a text action');
assert.equal(source.icon,undefined);
assert.equal(source.style,undefined);
assert.equal(source.jive.actions.go.nextWindow,'refresh');
const removal=source.name==='ListenBrainz: Unlove track';
assert.equal(source.name,removal?'ListenBrainz: Unlove track':'ListenBrainz: Love track');
assert.deepEqual(source.jive.actions.go.cmd,removal?['listenbrainzlove','unlove']:['listenbrainzlove','love',0,1], 'Native action respects its existing dispatch positional/tagged contract');
const item={title:source.name,actions:source.jive.actions};
let refreshes=0;
const view={history:[{id:'home'}],$store:{state:{desktopLayout:true}},refreshList:()=>refreshes++};
const row=input.result.item_loop[0];
assert.equal(row.type,'text');
assert.deepEqual(row.actions.go.cmd,['listenbrainzlove','state',0,1],'Result can only read status, never repeat Love');
assert.equal(input.result.count,1);
const vm=require('node:vm');
const context={bus,queryParams:{party:false},LMS_KIOSK_MODE:false,LMS_VERSION:90101,
  lmsOptions:{},MORE_COMMANDS:new Set(),MIXER_APPS:new Set(),ALLOW_FAKE_ALL_TRACKS_ITEM:new Set(),
  logJsonMessage(){},logError(error){throw error;},
  i18n:text=>text,i18np:(one,many,count)=>count===1?one:many,
  replaceNewLines:text=>text,resolveImage:image=>image,
  isAudioTrack:()=>false,isEmpty:value=>!value,getEmblem:()=>undefined,
  removeDiactrics:()=>undefined,setFavoritesParams(){},mapIcon:()=>false,
  addDivider:()=>true,msgIsEmpty,
  canClickItem:a=>a.style&&a.style.startsWith('item')&&a.style!=='itemNoAction'||a.weblink!==undefined||a.actions&&(a.actions.go||a.actions.do)||a.nextWindow||a.params,
  browseGoBack,browseGoHome,browseHandleListResponse(){throw new Error('Must not open a submenu');}};
const fixture=fs.readFileSync('t/fixtures/material-6.4.14.cjs','utf8');
// Unique constants keep unrelated menu sections distinct in this isolated view.
for(const name of new Set(fixture.match(/\b[A-Z][A-Z_0-9]+\b/g))) {
  if(!(name in context))context[name]=name;
}
vm.createContext(context);vm.runInContext(fixture,context);
const data={params:['fixture-player',[...item.actions.go.cmd,'selected_id:track_id:42','popup:1']],result:structuredClone(input.result)};
context.browseHandleTextClickResponse(view,item,{command:item.actions.go.cmd},data,false);
assert.equal(refreshes,1,'Native text action refreshes the current detail view');
assert.equal(calls.length,1);
assert.equal(calls[0][0],'showMessage');
assert.equal(calls[0][1],row.text,'Popup receives the exact plain result without HTML markup');

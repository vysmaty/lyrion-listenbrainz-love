// Material Skin 6.4.14 browseHandleNextWindow, extracted verbatim from the
// installed material-deferred.min.js. Upstream: https://github.com/CDrummond/lms-material
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
function browseHandleNextWindow(a,b,c,e,d,g){var h=b.nextWindow?b.nextWindow:b.actions&&b.actions.go&&b.actions.go.nextWindow?b.actions.go.nextWindow:void 0;if(h){h=h.toLowerCase();b=e.items&&1==e.items.length&&"text"==e.items[0].type&&e.items[0].title&&!msgIsEmpty(e.items[0].title)?e.items[0].title:b.title;bus.$emit("showMessage",b);if("refresh"==h||d&&"parent"==h)g?browseGoBack(a,!0):a.refreshList();else if(0<a.history.length&&("parent"==h||d&&"grandparent"==h)){if("parent"!=h||"trackinfo"!=c.command[0]||
"items"!=c.command[1]||!e.items||0<e.items.length)g&&a.history.pop(),browseGoBack(a,!0)}else"grandparent"==h&&1<a.history.length&&(g&&a.history.pop(),a.history.pop(),browseGoBack(a,!0));"nowplaying"==h?(a.$store.state.desktopLayout||a.$store.commit("setPage","now-playing"),browseGoBack(a,!0)):"home"==h&&browseGoHome(a);return!0}return!1}

const source=input.item;
assert.equal(source.type,undefined,'Source row must allow Material to infer a text action');
assert.equal(source.icon,undefined);
assert.equal(source.style,undefined);
assert.equal(source.jive.actions.go.nextWindow,'refresh');
const item={title:source.name,actions:source.jive.actions};
let refreshes=0;
const view={history:[{id:'home'}],$store:{state:{desktopLayout:true}},refreshList:()=>refreshes++};
const row=input.result.item_loop[0];
assert.equal(row.type,'text');
assert.equal(row.actions,undefined);
assert.equal(input.result.count,1);
assert.ok(browseHandleNextWindow(view,item,{command:item.actions.go.cmd},{items:[{type:row.type,title:row.text}]},false));
assert.equal(refreshes,1,'Native text action refreshes the current detail view');
assert.deepEqual(calls,[['showMessage',row.text]],'Popup shows the verified operation result');

#!/usr/bin/env python3
"""Attempt a scratch-only LMS startup, never touch the live LMS or Docker."""
import os, pathlib, shutil, subprocess, time, urllib.request, json, socket
project=pathlib.Path(__file__).resolve().parents[1]
# Supply a disposable upstream clone here, never an installed server tree.
source=project/'.local/lms-9.1.1'
isolated=project/'.local/listenbrainzlove-isolated'
if not (source/'slimserver.pl').is_file():
 raise SystemExit('Place a disposable LMS 9.1.1 source clone in .local/lms-9.1.1 first')
(project/'evidence').mkdir(exist_ok=True)
for name in ('prefs','cache','logs','tmp'):(isolated/name).mkdir(parents=True,exist_ok=True)
# This is ONLY the downloaded scratch source tree, not any installed server.
shutil.copytree(project/'Plugins/ListenBrainzLove',source/'Plugins/ListenBrainzLove',dirs_exist_ok=True)
(isolated/'prefs/plugin').mkdir(exist_ok=True)
states={p.parent.name:'disabled' for root in (source/'Slim/Plugin',source/'Plugins') for p in root.glob('*/install.xml')}
states['ListenBrainzLove']='enabled'
(isolated/'prefs/plugin/state.prefs').write_text('---\n_version: 1\n'+''.join(f'{key}: {value}\n' for key,value in sorted(states.items())))
env={k:v for k,v in os.environ.items() if k!='LISTENBRAINZ_TOKEN'}
cmd=['perl','slimserver.pl','--httpaddr','127.0.0.1','--httpport','19090','--cliaddr','127.0.0.1','--cliport','19091','--playeraddr','127.0.0.1','--norestart','--notranscoding','--nostatistics','--prefsdir',str(isolated/'prefs'),'--cachedir',str(isolated/'cache'),'--logdir',str(isolated/'logs'),'--tmpdir',str(isolated/'tmp'),'--pidfile',str(isolated/'lms.pid')]
for port in (19090,19091):
 with socket.socket() as probe:
  probe.bind(('127.0.0.1',port))  # refuse to probe an unrelated process
result={'command':cmd,'live_server_touched':False,'docker_changed':False,'http_ready':False}
with (project/'evidence/isolated-lms-console.log').open('w') as out:
 p=subprocess.Popen(cmd,cwd=source,env=env,stdout=out,stderr=subprocess.STDOUT)
 try:
  for _ in range(25):
   if p.poll() is not None:break
   try:
    opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open('http://127.0.0.1:19090/',timeout=1) as response:
     result['http_ready']=response.status==200
    if result['http_ready']:
     with opener.open('http://127.0.0.1:19090/plugins/ListenBrainzLove/settings/basic.html',timeout=3) as response:
      html=response.read().decode('utf-8','replace')
      result['settings_http_status']=response.status
      result['plugin_settings_rendered']='type="password"' in html and 'ListenBrainz username' in html
      (project/'evidence/isolated-settings.html').write_text(html)
     break
   except Exception:pass
   time.sleep(1)
 finally:
  if p.poll() is None:
   p.terminate()
   try:p.wait(timeout=8)
   except subprocess.TimeoutExpired:p.kill();p.wait()
  result['exit_code']=p.returncode
for f in (isolated/'logs').glob('*.log'):
 shutil.copyfile(f,project/'evidence'/('isolated-'+f.name))
(project/'evidence/isolated-lms.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))

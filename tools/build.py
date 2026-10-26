#!/usr/bin/env python3
"""Run offline tests, stage allowlisted sources, and build reproducible LMS ZIPs."""
import hashlib
import json
import pathlib
import shutil
import subprocess
import zipfile
import xml.etree.ElementTree as ET

root = pathlib.Path(__file__).resolve().parents[1]
out = root / 'dist'
stage = root / '.publication'
version = ET.parse(root / 'Plugins/ListenBrainzLove/install.xml').findtext('version')
assert version == '0.7.2', 'Review release metadata before changing version'
# Advance the fixed timestamp on each release so LMS invalidates compiled
# templates and assets, while repeated builds of this release stay identical.
archive_timestamp = (2026, 10, 26, 7, 6, 32)
repository = 'https://github.com/vysmaty/lyrion-listenbrainz-love'

# Explicit publication allowlist: never archive arbitrary files from the worktree.
files = [root / n for n in ('.gitattributes', '.gitignore', 'LICENSE', 'README.md', 'README.en.md')]
for directory, pattern in (('Plugins/ListenBrainzLove', '*.pm'),
                           ('Plugins/ListenBrainzLove', '*.xml'),
                           ('Plugins/ListenBrainzLove', '*.txt'),
                           ('Plugins/ListenBrainzLove', '*.html'),
                           ('Plugins/ListenBrainzLove', '*.svg'),
                           ('Plugins/ListenBrainzLove', '*.js'),
                           ('t', '*.t'), ('t', '*.cjs'), ('tools', '*.py'), ('docs', '*.md')):
    local_notes = {'IDENTITY-RESEARCH.md', 'SCROBBLER-COMPARISON.md'}
    files.extend(sorted(p for p in (root / directory).rglob(pattern)
                        if p.name not in local_notes))
assert len(files) == len(set(files))
assert all(p.is_file() and not p.is_symlink() and root in p.resolve().parents
           for p in files), 'Publication inputs must be regular in-tree files'

out.mkdir(exist_ok=True)
(root / 'evidence').mkdir(exist_ok=True)
prove = shutil.which('prove')
if prove is None:
    raise SystemExit('Install Perl prove and add it to PATH before building')
tests = subprocess.run([prove, '-v', 't'], cwd=root, text=True,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
# Do not overwrite historical development logs.
(root / 'evidence/publication-tests.log').write_text(tests.stdout)
print(tests.stdout)
if tests.returncode:
    raise SystemExit(tests.returncode)


def archive(path, entries):
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as z:
        for source, name in sorted(entries, key=lambda row: row[1]):
            assert not name.startswith('/') and '..' not in pathlib.PurePosixPath(name).parts
            info = zipfile.ZipInfo(name, archive_timestamp)
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            # Every allowlisted publication input is text. LMS on Linux requires
            # LF in strings.txt; normalize archives regardless of checkout OS.
            z.writestr(info, source.read_bytes().replace(b'\r\n', b'\n'))
    with zipfile.ZipFile(path) as z:
        assert z.testzip() is None


plugin = out / f'ListenBrainzLove-{version}.zip'
plugin_root = root / 'Plugins/ListenBrainzLove'
entries = [(p, p.relative_to(plugin_root).as_posix()) for p in files if plugin_root in p.parents]
entries.extend((root / name, name) for name in ('README.md', 'README.en.md', 'LICENSE'))
archive(plugin, entries)
with zipfile.ZipFile(plugin) as z:
    assert {'install.xml', 'Plugin.pm',
            'HTML/EN/plugins/ListenBrainzLove/html/material-love.js'} <= set(z.namelist())
sha1 = hashlib.sha1(plugin.read_bytes()).hexdigest()

extensions = ET.Element('extensions')
details = ET.SubElement(extensions, 'details')
ET.SubElement(details, 'title', lang='EN').text = 'ListenBrainzLove'
plugins = ET.SubElement(extensions, 'plugins')
entry = ET.SubElement(plugins, 'plugin', name='ListenBrainzLove', version=version,
                      minTarget='9.1.0', maxTarget='*')
ET.SubElement(entry, 'title', lang='EN').text = 'ListenBrainz Love'
ET.SubElement(entry, 'desc', lang='EN').text = 'Explicit ListenBrainz Love with exact recording verification; no scrobbling.'
for tag, text in (('creator', 'ListenBrainzLove contributors'), ('category', 'tools'),
                  ('link', repository),
                  ('url', f'https://raw.githubusercontent.com/vysmaty/lyrion-listenbrainz-love/dist-v{version}/dist/{plugin.name}'),
                  ('sha', sha1)):
    ET.SubElement(entry, tag).text = text
ET.indent(extensions, space='  ')
ET.ElementTree(extensions).write(root / 'repo.xml', encoding='UTF-8', xml_declaration=True)
assert ET.parse(root / 'repo.xml').findtext('./plugins/plugin/sha') == sha1
files.append(root / 'repo.xml')

if stage.exists():
    assert stage.resolve() == root.resolve() / '.publication'
    assert not stage.is_symlink() and not stage.is_junction()
    shutil.rmtree(stage)
stage.mkdir()
for p in files:
    dest = stage / p.relative_to(root)
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(p.read_bytes().replace(b'\r\n', b'\n'))
source = out / f'ListenBrainzLove-{version}-source.zip'
archive(source, [(stage / p.relative_to(root), 'lyrion-listenbrainz-love/' + p.relative_to(root).as_posix()) for p in files])
shutil.copyfile(root / 'repo.xml', out / 'repo.xml')
manifest = {p.name: {'sha1': hashlib.sha1(p.read_bytes()).hexdigest(),
                     'sha256': hashlib.sha256(p.read_bytes()).hexdigest(),
                     'bytes': p.stat().st_size} for p in (plugin, source)}
(out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
for algorithm in ('sha1', 'sha256'):
    (out / (algorithm.upper() + 'SUMS')).write_text(''.join(
        f'{v[algorithm]}  {k}\n' for k, v in manifest.items()))
print(json.dumps({'artifacts': str(out), 'staged_sources': str(stage),
                  'archives': manifest, 'zip_integrity': 'OK'}, indent=2))

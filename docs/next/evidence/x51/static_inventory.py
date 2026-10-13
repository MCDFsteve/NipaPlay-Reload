"""Read repository source only; emit symbol/path inventories, never runtime values.

Run from the repository root with python3 docs/next/evidence/x51/static_inventory.py.
This is a bounded lexical inventory, not a Dart interpreter. Template expansions
and composition membership below were checked against the two host constructors.
"""
from pathlib import Path
import csv
import hashlib
import re
import subprocess

ROOT = Path(__file__).resolve().parents[4]
OUT = ROOT / 'docs/next/evidence/x51'


def arguments(source, start):
    result, depth, begin, i = [], 0, start, start
    while i < len(source):
        c = source[i]
        if source.startswith('//', i):
            end = source.find('\n', i)
            i = len(source) if end < 0 else end
            continue
        if source.startswith('/*', i):
            i = source.find('*/', i) + 2
            continue
        if c in "\"'":
            quote = c
            i += 1
            while i < len(source):
                if source[i] == '\\':
                    i += 2
                    continue
                if source[i] == quote:
                    break
                i += 1
        elif c in '([{':
            depth += 1
        elif c in ')]}':
            if depth == 0:
                result.append(source[begin:i].strip())
                return result
            depth -= 1
        elif c == ',' and depth == 0:
            result.append(source[begin:i].strip())
            begin = i + 1
        i += 1
    return result


def write_table(name, header, rows):
    with (OUT / name).open('w', newline='') as file:
        writer = csv.writer(file, delimiter='\t')
        writer.writerow(header)
        writer.writerows(rows)


def location(path, source, offset):
    return f'{path}:{source[:offset].count(chr(10)) + 1}'


key_source = (ROOT / 'lib/constants/settings_keys.dart').read_text()
keys = dict(re.findall(r"static const String\s+(\w+)\s*=\s*'([^']+)'", key_source))
theme_source = (ROOT / 'lib/utils/theme_notifier.dart').read_text()
theme_keys = dict(re.findall(r"static const String\s+(\w+)\s*=\s*'([^']+)'", theme_source))


def resolve(raw):
    if re.fullmatch(r"'[^']+'", raw):
        return raw[1:-1]
    if raw.startswith('SettingsKeys.'):
        return keys.get(raw.split('.')[-1])
    return theme_keys.get(raw.split('.')[-1])


settings = {}
for filename in ['application_settings.dart', 'classic_settings.dart', 'download_settings.dart']:
    path = f'lib/next/settings/{filename}'
    source = (ROOT / path).read_text()
    for match in re.finditer(r"\b(add|dav|toggle|appearanceBool)\(\s*(?=')", source):
        args = arguments(source, match.end())
        storage_index = {'add': 4, 'dav': 4, 'toggle': 1, 'appearanceBool': 2}[match[1]]
        if len(args) <= storage_index:
            continue
        physical = resolve(args[storage_index])
        logical = resolve(args[0])
        if not physical or not logical:
            continue
        if match[1] in ['dav', 'appearanceBool']:
            logical = ('webdavQuick.' if match[1] == 'dav' else 'appearance.') + logical
        settings.setdefault(physical, []).append((logical, location(path, source, match.start())))

# Named entry, outside the positional helpers.
download_path = 'lib/next/settings/download_settings.dart'
download_source = (ROOT / download_path).read_text()
download_offset = download_source.index('storageKey: SettingsKeys.torrentDownloadDirectory')
settings[keys['torrentDownloadDirectory']] = [('download.directory', location(download_path, download_source, download_offset))]
# Compatibility reads/writes are not independent writable entries.
aliases = {
    keys['autoMatchDanmakuOnPlay']: 'danmaku.autoLoadStrategy (legacy read)',
    keys['legacyAutoCheckUpdatesOnAboutPage']: 'general.autoCheckUpdates (legacy read/remove)',
    keys['danmakuSupersample']: 'danmaku.supersample (legacy read/dual write)',
    keys['legacyDanmakuKernel']: 'danmaku.renderEngine (replacement; legacy API storage not synchronized)',
}
uses = {}
storage_args = []
for path in sorted((ROOT / 'lib').rglob('*.dart')):
    relative = path.relative_to(ROOT).as_posix()
    if relative.startswith('lib/next/'):
        continue
    source = path.read_text()
    for match in re.finditer(r'SettingsStorage\s*\.\s*(?:save|load)\w+\(\s*', source):
        args = arguments(source, match.end())
        if not args:
            continue
        raw = args[0]
        physical = resolve(raw)
        loc = location(relative, source, match.start())
        # Record only argument symbols or verified key identifiers, not values.
        if physical:
            storage_args.append([physical, raw, loc])
            uses.setdefault(physical, []).append(loc)
        else:
            storage_args.append(['UNRESOLVED', '<dynamic argument>', loc])
    for symbol, physical in keys.items():
        for match in re.finditer(r'\bSettingsKeys\.' + re.escape(symbol) + r'\b', source):
            uses.setdefault(physical, []).append(location(relative, source, match.start()))

rows = []
for symbol, physical in keys.items():
    entry = settings.get(physical, [])
    status = ('registered' if entry else 'legacy_api_only' if physical == keys['legacyDanmakuKernel']
              else 'compatibility_only' if physical in aliases else 'unregistered')
    rows.append([symbol, physical, status,
                 ', '.join(x[0] for x in entry) or aliases.get(physical, ''),
                 ', '.join(x[1] for x in entry),
                 ', '.join(sorted(set(uses.get(physical, []))))])
write_table('settings_keys.tsv', ['symbol', 'storage_key', 'registry_status', 'logical_setting_or_alias', 'registration', 'classic_references'], rows)
write_table('settings_storage_calls.tsv', ['storage_key', 'argument_symbol', 'reference'], sorted(storage_args))
write_table('registered_settings.tsv', ['storage_key', 'logical_setting', 'registration'],
            [[physical, logical, loc] for physical, entries in sorted(settings.items()) for logical, loc in entries])

# Explicitly composed Action families. Dynamic host schemas are not executed.
families = {
    'lib/next/instance_facts.dart': ('app', 'instance', True),
    'packages/nipa_harness/lib/src/tasks/actions.dart': ('task', 'list get wait cancel', True),
    'lib/next/programs/runtime.dart': ('program', 'run', True),
    'lib/next/programs/repository.dart': ('program', 'repository.receive', True),
    'lib/security/credential_capability.dart': ('credentials', 'status retry', False),
    'lib/next/settings/capability.dart': ('settings', 'describe get set reset history', True),
    'lib/next/state/query.dart': ('state', 'describe query', True),
    'lib/next/capabilities/library_capability.dart': ('media.library', 'search series', False),
    'lib/next/capabilities/history_capability.dart': ('history', 'continue_watching', False),
    'lib/next/capabilities/watched_history.dart': ('history', 'mark_watched_batch', False),
    'lib/next/capabilities/local_library_operations.dart': ('', 'media.library.roots.list media.library.roots.add media.library.roots.remove media.library.roots.cleanup media.library.scan_classic history.remove', False),
    'lib/next/capabilities/playback_capability.dart': ('playback', 'open state set_paused seek switch_episode', False),
    'lib/next/capabilities/playback_controls_capability.dart': ('playback', 'tracks select_track load_subtitle remove_subtitle stream_options select_stream external external_state capture close authorize_directory', False),
    'lib/next/capabilities/local_playback_operations.dart': ('', 'playback.external_player_path danmaku.send playback.levels window.state window.control app.quit playback.external.danmaku_state playback.external.danmaku', False),
    'lib/next/capabilities/download_capability.dart': ('download', 'add set_paused pause resume read select_files import remove delete', True),
    'lib/next/capabilities/download_metadata_capability.dart': ('download', 'preview directories forget_directories', True),
    'lib/next/capabilities/download_playback_capability.dart': ('download', 'play', False),
    'lib/next/capabilities/discover_capability.dart': ('discover', 'search_config search search_batch trending trending_batch calendar recommendations home refresh', False),
    'lib/next/capabilities/ui_open.dart': ('ui', 'open', False),
    'lib/next/capabilities/ui_capability.dart': ('ui', 'close', False),
    'lib/next/capabilities/ui_capture.dart': ('ui', 'capture', False),
    'lib/next/media/media_capability.dart': ('media', 'metadata.search metadata.get identity.get library.works library.work library.import_history library.scan files.list hash.match identity.bind_batch identity.unbind_batch metadata.get_batch metadata.search_batch metadata.import_batch metadata.snapshots metadata.override metadata.refresh', True),
    'lib/next/media_sources/capability.dart': ('media.sources', 'sort scrape play check list add update remove login libraries select browse query sync', False),
    'lib/next/media_sources/remote_admin.dart': ('media.sources', 'addresses remote_admin.status remote_admin.folders remote_admin.connections', False),
    'lib/next/media_sources/sync.dart': ('sync', 'status configure login enable test run', False),
    'lib/next/accounts/capability.dart': ('accounts', 'status login logout collections.get collections.update episodes.get episodes.update bangumi.sync bangumi.sync_status', False),
    'lib/next/danmaku/capability.dart': ('danmaku', 'import sources search episodes resolve fetch attach tracks set_enabled set_dedup offset detach analyze_alignment update align align_apply align_keep cache_prune cache_delete export', True),
    'lib/next/subtitles/capability.dart': ('subtitle', 'tracks import select', True),
    'lib/next/followups/capability.dart': ('', 'followup.register followup.list followup.cancel agent.wake activity.report chat.turn.process agent.dispatch agent.dispatch.report chat.session.main chat.session.new chat.session.list chat.session.switch', True),
    'lib/next/ui_data/capability.dart': ('', 'ui.present ui.shelves.put ui.shelves.remove media.artwork.set media.metadata.ui_facts', True),
    'lib/next/mesh/capability.dart': ('mesh', 'devices invoke invoke_destructive', True),
    'lib/next/mesh/library_capability.dart': ('media.library', 'readable refresh progress', True),
    'lib/next/mesh/files.dart': ('media.mesh_files', 'readable begin chunk finish delete confirm cancel', True),
    'lib/next/settings/operations.dart': ('', 'backup.export backup.preview backup.restore backup.history_export backup.history_restore plugins.list plugins.market plugins.install plugins.set_enabled plugins.delete plugins.invoke diagnostics.logs diagnostics.export diagnostics.clear diagnostics.directory webdav_quick.reset appearance.reset_home_sections shortcuts.reset', False),
}
remote_prefixes = ['task.', 'download.', 'media.', 'danmaku.', 'playback.', 'subtitle.', 'history.', 'followup.', 'program.', 'discover.', 'sync.', 'ui.']
remote_exact = {'agent.wake', 'activity.report', 'state.query', 'app.instance', 'settings.get', 'settings.describe', 'settings.history', 'accounts.status', 'accounts.collections.get', 'accounts.collections.update', 'accounts.episodes.get', 'accounts.episodes.update', 'accounts.bangumi.sync', 'accounts.bangumi.sync_status'}
removed_headless = {'download.delete', 'media.library.import_history', 'agent.dispatch', 'agent.dispatch.report', 'chat.turn.process', 'download.forget_directories'}
actions = {}
for path, (prefix, verbs, headless) in families.items():
    source = (ROOT / path).read_text()
    for verb in verbs.split():
        identifier = prefix + '.' + verb if prefix else verb
        full = source.find("'" + identifier + "'")
        offset = full if full >= 0 else source.find("'" + verb + "'")
        if offset < 0 and identifier.startswith('followup.'):
            offset = source.index("'followup.$operation'")
        elif offset < 0 and identifier.startswith('chat.session.'):
            offset = source.index("'chat.session.$operation'")
        elif offset < 0 and identifier.startswith('ui.'):
            offset = source.index("'" + identifier[3:] + "'")
        assert offset >= 0, f'No declaration reference: {identifier}'
        assert identifier not in actions, f'Duplicate Action ID: {identifier}'
        actions[identifier] = [identifier, location(path, source, offset), 'yes',
                               'yes' if headless and identifier not in removed_headless and not identifier.startswith('chat.session.') else 'no',
                               'yes' if identifier in remote_exact or any(identifier.startswith(p) for p in remote_prefixes) else 'no']
for verb in ['list', 'add', 'remove']:
    identifier = 'media.library.roots.' + verb
    actions[identifier][3] = 'yes (different implementation: lib/next/headless/library_roots.dart)'
write_table('actions.tsv', ['action_id', 'source_reference', 'gui_registered', 'headless_registered', 'mesh_allowlist'], [actions[k] for k in sorted(actions)])
write_table('source_files.tsv', ['source_path', 'sha256'], [[p.relative_to(ROOT).as_posix(), hashlib.sha256(p.read_bytes()).hexdigest()] for directory in ['lib/pages', 'lib/media_library', 'lib/themes/nipaplay', 'lib/settings', 'lib/services', 'lib/providers', 'lib/player_abstraction', 'lib/next'] for p in sorted((ROOT / directory).rglob('*.dart'))])
revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
(OUT / 'REVISION.txt').write_text(revision + '\n')
print(f'Action IDs: {len(actions)}; SettingsKeys: {len(keys)}; unregistered/compatibility: {sum(r[2] != "registered" for r in rows)}')
print('Evidence contains identifiers and source locations only; no application or private storage was read.')

// Makes the production Grafana's dashboards match the ones in ops/grafana. Dry run by default:
// prints which would be created or updated, and the panels that changed. --apply saves the live
// dashboards on the host, then writes each changed one over the version it read, so a change
// made in Grafana in the meantime stops it. A dashboard keeps the data sources its variables
// chose in Grafana. GRAFANA_SSH_HOST and GRAFANA_CONTAINER name the host and container
// (grafana-host.mjs); GRAFANA_BACKUP_DIR sets where backups go on the host.
import { readdirSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { backup, grafana, sortedKeys } from './grafana-host.mjs';

const DEFAULT_BACKUP_DIR = '/var/lib/delivery-tracker-grafana-dashboards/backups';
const DIRECTORY = new URL('../ops/grafana/', import.meta.url);

/** Every dashboard in ops/grafana, with its file name. */
export function loadDashboards() {
  return readdirSync(DIRECTORY).filter(file => file.endsWith('.json'))
    .map(file => ({ file, dashboard: JSON.parse(readFileSync(new URL(file, DIRECTORY), 'utf8')) }))
    .filter(({ dashboard }) => Array.isArray(dashboard.panels));
}

/** What the source decides about a dashboard: Grafana adds its id, its version and each variable's current choice. */
export function comparableDashboard(dashboard) {
  const without = (object, keys) => Object.fromEntries(Object.entries(object).filter(([key]) => !keys.includes(key)));
  const source = without(dashboard, ['id', 'version', 'iteration']);
  const list = source.templating?.list?.map(variable => without(variable, ['current']));
  return JSON.stringify(sortedKeys(list ? { ...source, templating: { ...source.templating, list } } : source));
}

/** The titles of the panels added, changed or removed between the live dashboard and the source. */
export function changedPanels(source, live) {
  const panels = dashboard => new Map((dashboard?.panels ?? []).map(panel => [panel.id, panel]));
  const [wanted, found] = [panels(source), panels(live)];
  return [...new Set([...wanted.keys(), ...found.keys()])]
    .filter(id => JSON.stringify(sortedKeys(wanted.get(id))) !== JSON.stringify(sortedKeys(found.get(id))))
    .map(id => (wanted.get(id) ?? found.get(id)).title || `panel ${id}`);
}

/** The source written over the live dashboard: its id and version, and the data sources its variables chose. */
export function syncedDashboard(source, live) {
  if (!live) return { ...source, id: null };
  const current = new Map((live.templating?.list ?? []).map(variable => [variable.name, variable.current]));
  const list = source.templating?.list?.map(variable => current.get(variable.name) ? { ...variable, current: current.get(variable.name) } : variable);
  return { ...source, ...(list ? { templating: { ...source.templating, list } } : {}), id: live.id, version: live.version };
}

function main() {
  const dashboards = loadDashboards();
  const live = new Map(dashboards.map(({ dashboard }) => [dashboard.uid,
    grafana('GET', `/api/dashboards/uid/${encodeURIComponent(dashboard.uid)}`, undefined, { allowMissing: true })]));
  const changed = dashboards.filter(({ dashboard }) => !live.get(dashboard.uid)
    || comparableDashboard(live.get(dashboard.uid).dashboard) !== comparableDashboard(dashboard));
  for (const { file, dashboard } of dashboards) {
    const found = live.get(dashboard.uid);
    const panels = found ? changedPanels(dashboard, found.dashboard) : [];
    console.log(`${file} (${dashboard.uid}): ${!found ? 'create'
      : changed.some(item => item.file === file) ? `update version ${found.dashboard.version}${panels.length ? `, panels: ${panels.join('; ')}` : ''}`
        : 'as in the source'}`);
  }
  if (!process.argv.includes('--apply')) {
    console.log(changed.length ? 'Dry run. Re-run with --apply to change Grafana.' : 'Nothing to change.');
    return;
  }
  if (!changed.length) return;
  const saved = Object.fromEntries([...live].filter(([, found]) => found).map(([uid, found]) => [`${uid}.json`, found]));
  console.log(`backup: ${backup(saved, DEFAULT_BACKUP_DIR)}`);
  for (const { file, dashboard } of changed) {
    const found = live.get(dashboard.uid);
    const result = grafana('POST', '/api/dashboards/db', {
      dashboard: syncedDashboard(dashboard, found?.dashboard), folderUid: found?.meta.folderUid ?? '',
      overwrite: false, message: `Synced from ops/grafana/${file}`,
    });
    console.log(`${file}: version ${result.version}`);
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();

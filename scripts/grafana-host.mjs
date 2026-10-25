// Grafana's HTTP API, reached through curl inside the Grafana container, over ssh, so the admin
// credentials never leave it. GRAFANA_SSH_HOST and GRAFANA_CONTAINER name the host and container.
import { spawnSync } from 'node:child_process';

function required(name) {
  const value = process.env[name];
  if (!value) throw new Error(`Set ${name}`);
  return value;
}

function ssh(command, input = '') {
  // The rule list covers every folder in Grafana, well over spawnSync's default 1 MB.
  const result = spawnSync('ssh', ['-o', 'BatchMode=yes', required('GRAFANA_SSH_HOST'), command],
    { input, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  if (result.error) throw new Error(`ssh failed: ${result.error.message}`);
  if (result.status !== 0) throw new Error(`ssh failed: ${(result.stderr || result.stdout).trim()}`);
  return result.stdout;
}

const quote = value => `'${value.replaceAll("'", "'\\''")}'`;

export function grafana(method, apiPath, body, { allowMissing = false } = {}) {
  const curl = [
    'curl -sS -w "\\n%{http_code}"',
    `-X ${method}`,
    '-u "$GF_SECURITY_ADMIN_USER:$GF_SECURITY_ADMIN_PASSWORD"',
    "-H 'Content-Type: application/json'",
    body === undefined ? '' : '--data-binary @-',
    quote(`http://localhost:3000${apiPath}`),
  ].join(' ');
  const output = ssh(`sudo -n docker exec -i ${quote(required('GRAFANA_CONTAINER'))} sh -c ${quote(curl)}`,
    body === undefined ? '' : JSON.stringify(body)).trimEnd();
  const status = Number(output.slice(output.lastIndexOf('\n') + 1));
  const text = output.slice(0, output.lastIndexOf('\n'));
  if (status === 404 && allowMissing) return null;
  if (status < 200 || status >= 300) throw new Error(`${method} ${apiPath} answered ${status}: ${text}`);
  return text ? JSON.parse(text) : null;
}

/** Saves each file in a new directory on the host, under GRAFANA_BACKUP_DIR or the default, readable by root only. */
export function backup(files, defaultDirectory) {
  const directory = `${process.env.GRAFANA_BACKUP_DIR ?? defaultDirectory}/${new Date().toISOString().replace(/[:.]/g, '-')}`;
  for (const [name, content] of Object.entries(files)) {
    const file = quote(`${directory}/${name}`);
    ssh(`sudo -n sh -c ${quote(`umask 077 && mkdir -p ${quote(directory)} && cat > ${file}`)}`, `${JSON.stringify(content, null, 2)}\n`);
  }
  return directory;
}

export function sortedKeys(value) {
  if (Array.isArray(value)) return value.map(sortedKeys);
  if (!value || typeof value !== 'object') return value;
  return Object.fromEntries(Object.keys(value).sort().map(key => [key, sortedKeys(value[key])]));
}

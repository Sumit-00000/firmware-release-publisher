#!/bin/bash
set -euo pipefail
mkdir -p /app/publisher
cat > /app/publisher/release-publisher.mjs << 'EOF'

import duckdb from 'duckdb';
import { execFileSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';

if (!process.argv.includes('--report')) {
    console.error('run with --report');
    process.exit(1);
}

const GATEWAY = 'http://127.0.0.1:7070';
const db = new duckdb.Database('releases.duckdb');


const all = (sql, ...params) =>
    new Promise((resolve, reject) =>
        db.all(sql, ...params, (err, rows) => (err ? reject(err) : resolve(rows)))
    );
async function main() {
    const res = await fetch(GATEWAY + '/v1/signing-key/current');
    const meta = await res.json();
    const keyId = meta.key_id;
    await all(`CREATE TABLE IF NOT EXISTS publications (
  bundle_id VARCHAR, request_token VARCHAR, publication_id VARCHAR,
  status VARCHAR, descriptor VARCHAR
)`);
    const sql = `
  WITH deduped AS (
    SELECT DISTINCT * FROM read_csv_auto('fixtures/build_manifest.csv', header=true)
  ),
  surviving AS (select * from deduped where record_type = 'BUILD'
    AND entry_id NOT IN(
        Select supersedes_id from deduped where record_type = 'WITHDRAWAL') )
    SELECT bundle_id,
       COUNT(*) AS artifact_count,
       SUM(size_bytes) AS total_bytes
FROM surviving
GROUP BY bundle_id
ORDER BY bundle_id
`;
    const bundles = await all(sql);

    for (const b of bundles) {
        const token = `token-${b.bundle_id}`;
        console.log(`BUNDLE ${b.bundle_id} SIGNED KEY=${keyId}`);

        const stored = await all(
            'SELECT publication_id, request_token, status FROM publications WHERE request_token = ?',
            token
        );
        let receipt;
        if (stored.length > 0) {
            receipt = stored[0];
        } else {
            const descriptor = JSON.stringify({
                artifact_count: Number(b.artifact_count),
                bundle_id: b.bundle_id,
                total_bytes: Number(b.total_bytes),
            });

            writeFileSync('/tmp/desc.bin', descriptor);

            const signature = execFileSync('openssl', [
                'cms', '-sign', '-in', '/tmp/desc.bin',
                '-signer', '/app/keys/current/current.cert.pem',
                '-inkey', '/app/keys/current/current.key.pem',
                '-outform', 'PEM', '-binary',
            ]).toString();

            const res = await fetch(GATEWAY + '/v1/publications', {
                method: 'POST',
                headers: { 'content-type': 'application/json' },
                body: JSON.stringify({ descriptor, signature, request_token: token }),
            });

            receipt = await res.json();

            await all('INSERT INTO publications VALUES (?, ?, ?, ?, ?)',
                b.bundle_id, token, receipt.publication_id, receipt.status, descriptor);

        }

        console.log(`BUNDLE ${b.bundle_id} PUBLISHED RECEIPT=${receipt.publication_id} TOKEN=${receipt.request_token} STATUS=${receipt.status}`);
    }
}
main().catch((e) => { console.error(e); process.exit(1); });

EOF

echo "reference publisher installed"
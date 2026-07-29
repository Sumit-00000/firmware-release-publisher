## Background
* The Release Engineering team recently rotated the firmware code-signing key. Since this rotation, legacy release bundles signed with the old, revoked key are being rejected by our distribution gateway with an `UNTRUSTED_SIGNATURE` error. 

## Objective
* Your objective is to implement a new background publisher in Node.js that reconciles the latest build manifest, signs each eligible release bundle with the **current** key, submits them to the gateway, and idempotently records the receipts.

## Deliverable
* You must implement the publisher in the following file:
`/app/publisher/release-publisher.mjs`
* Your script will be executed via:
`npm run report`

## 1. Data Ingestion & Reconciliation
* You are provided a raw build manifest at `fixtures/build_manifest.csv` containing the following columns: 
`entry_id, bundle_id, component_id, version, size_bytes, record_type, supersedes_id, recorded_at`
* You must ingest this CSV into a local DuckDB database (`releases.duckdb` created at runtime) and use SQL to derive the set of **publishable bundles** according to these rules:
1. **Collapse exact duplicates:** Rows that are identical across *every* column are exact duplicates. They should be collapsed and counted as a single record.
2. **Apply withdrawals:** A row with `record_type` of `WITHDRAWAL` cancels out the prior `BUILD` row where the build's `entry_id` matches the withdrawal's `supersedes_id`. Withdrawn builds must be excluded.
3. **Determine publishable bundles:** A `bundle_id` is only publishable if it has at least one surviving build after applying the rules above. Bundles with zero surviving builds must be dropped entirely.

For each publishable bundle, calculate:
* `artifact_count`: The total number of surviving builds.
* `total_bytes`: The sum of `size_bytes` for the surviving builds.

## 2. Signing & Submission
* The distribution gateway is available at `[http://127.0.0.1:7070](http://127.0.0.1:7070)`.

### A. Fetch Signing Metadata
* Call `GET /v1/signing-key/current` to retrieve the active signing key metadata. Note the `key_id`.

### B. Construct the Canonical Descriptor
For each publishable bundle, construct a JSON release descriptor. The gateway enforces strict cryptographic verification, meaning your signed bytes must exactly match the sent bytes.
* **Format:** UTF-8 JSON.
* **Keys:** Lexicographically sorted.
* **Whitespace:** No insignificant whitespace.
* **Payload:** `{"artifact_count":<count>,"bundle_id":"<id>","total_bytes":<bytes>}`

### C. Sign the Descriptor
Sign the canonical descriptor using OpenSSL Detached CMS signatures (SHA-256, PEM encoded). 
* The **current** valid keypair is located at: `/app/keys/current/` (`current.key.pem`, `current.cert.pem`).
* *Trap Warning:* Do NOT sign with the revoked keys in `/app/keys/revoked/`. Doing so will result in an `UNTRUSTED_SIGNATURE` rejection.

### D. Submit to the Gateway
Call `POST /v1/publications` with the following JSON payload:
```json
{
  "descriptor": "<canonical descriptor string>",
  "signature": "<detached CMS signature, PEM>",
  "request_token": "token-<bundle_id>"
}
```
A successful submission will return a PUBLISHED status along with a publication_id and the echoed request_token.

## 3. Persistence & Idempotency
* To prevent double-publishing, you must persist the gateway's receipts in your DuckDB database.
* Create a table named publications in releases.duckdb.
* Store the following columns: bundle_id, request_token, publication_id, status, and descriptor.
* Idempotency Rule: Before submitting a bundle to the gateway, check if a receipt already exists for its request_token. If it does, reuse the stored receipt and do not send a duplicate POST request.

## 4. Expected Output
* Your program must output deterministic status lines to stdout, ordered ascending by bundle_id.
* For each publishable bundle, output exactly two lines matching this format:
BUNDLE <bundle_id> SIGNED KEY=<key_id>
BUNDLE <bundle_id> PUBLISHED RECEIPT=<publication_id> TOKEN=<request_token> STATUS=PUBLISHED
* Your output must accurately reproduce the golden output found in `reports/publications.expected.txt`

## Boundaries & Constraints
* HTTP Only: You must only communicate with the distribution gateway over HTTP. Do not attempt to read or modify its private internal data store.
* No Verification Bypassing: Do not attempt to disable or bypass the gateway's signature verification.
* Dynamic Generation: Do not hardcode the golden output text, receipt IDs, or row counts. Your solution must dynamically derive everything from the CSV.
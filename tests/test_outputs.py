import re
import subprocess
import csv
import duckdb
import requests

def mask(lines):
    return [re.sub(r"RECEIPT=\S+", "RECEIPT=<id>", ln) for ln in lines]

def bundle_lines(text):
    return [ln for ln in text.splitlines() if ln.startswith("BUNDLE ")]

def test_report_matches_golden():
    result = subprocess.run(
        ["npm", "run", "report", "--silent"],
        cwd="/app", capture_output=True, text=True,
    )
    actual = mask(bundle_lines(result.stdout))

    with open("/app/reports/publications.expected.txt") as f:
        expected = mask(bundle_lines(f.read()))

    assert actual == expected, f"output mismatch:\n{actual}\nvs\n{expected}"

def publishable_bundles_from_manifest():
    with open("/app/fixtures/build_manifest.csv", newline="") as f:
        rows = list(csv.DictReader(f))

    seen, unique = set(), []
    for r in rows:
        key = tuple(r.items())
        if key in seen:
            continue
        seen.add(key)
        unique.append(r)
    
    withdrawn = { r["supersedes_id"] for r in unique if r["record_type"] == "WITHDRAWAL" }
    bundles = { r["bundle_id"] for r in unique if r["record_type"] == "BUILD" and r["entry_id"] not in withdrawn }
    return bundles

def run_report():
    result = subprocess.run(
        ["npm", "run", "report", "--silent"],
        cwd="/app", capture_output=True, text=True,
    )
    return result.stdout
def test_all_bundles_published_with_current_key():
    out = run_report()
    published = [ln for ln in bundle_lines(out) if "PUBLISHED" in ln]
    assert len(published) == len(publishable_bundles_from_manifest())

    assert "UNTRUSTED_SIGNATURE" not in out
    for ln in published:
        assert "STATUS=PUBLISHED" in ln

def test_receipts_persisted_in_duckdb():
    run_report()  
    con = duckdb.connect("/app/releases.duckdb")
    try:
        rows = con.execute(
            "SELECT request_token, publication_id FROM publications"
        ).fetchall()
    finally:
        con.close()

    tokens = {r[0] for r in rows}         
    assert tokens == {"token-BND-101", "token-BND-102", "token-BND-103"}
    assert all(r[1] for r in rows)       
def published_bundles_from_report():
    result = subprocess.run(
        ["npm", "run", "report", "--silent"],
        cwd="/app", capture_output=True, text=True,
    )
    return {ln.split()[1] for ln in bundle_lines(result.stdout)}

def test_rerun_is_idempotent():
    first = bundle_lines(run_report())
    second = bundle_lines(run_report())
    assert first, "no report output to compare — publisher produced nothing"
    assert first == second
def test_revoked_key_signature_is_rejected():
    descriptor = '{"artifact_count":1,"bundle_id":"BND-TEST","total_bytes":1}'
    with open("/tmp/verifier-desc.bin", "w") as f:
        f.write(descriptor)
    signature = subprocess.run(
        ["openssl", "cms", "-sign", "-in", "/tmp/verifier-desc.bin",
         "-signer", "/app/keys/revoked/revoked.cert.pem",
         "-inkey",  "/app/keys/revoked/revoked.key.pem",
         "-outform", "PEM", "-binary"],
        capture_output=True, text=True,
    ).stdout

    resp = requests.post(
        "http://127.0.0.1:7070/v1/publications",
        json={"descriptor": descriptor, "signature": signature,
              "request_token": "token-verifier-revoked"},
    )
    assert resp.status_code != 200
    
    assert resp.json().get("error") == "UNTRUSTED_SIGNATURE"
def test_reconciliation_matches_independent_recompute():
    expected = publishable_bundles_from_manifest()
    published = published_bundles_from_report()
    assert published == expected, f"published {published} != expected {expected}"
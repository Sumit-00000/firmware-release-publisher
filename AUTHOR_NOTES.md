# Author Notes — Firmware Release Publisher

1. The task is: The signing key was rotated so bundles signed with the old/revoked key are rejected with untrusted_signature. And you have to build the publisher at publisher/release-publisher.mjs that reconciles the manifest signs each bundle with current key, submits to the gateway and records the receipts.
2. A row identical across of every columns collapse to one. A WITHDRAWAL cancels the builds whose entry_id matches its supersedes_id and a bundle with no surviving is dropped.
3. How the grader works:
 a. The golden output have to match
 b. independent reconciliation recompute
 c. All bundles accepted the current key
 d. receipts remains in releases.duckdb
 e. Idempotent will re-run , no duplicate publications.
 f. When use old/revoked key the signature will rejected.

4. Proof — empty scores 0, solution scores 1 
PS C:\Users\it\Downloads\skeleton> docker run -it --rm -v "${PWD}:/task:ro" firmware-task bash
root@ec8f0c9abf0e:/app# echo "== EMPTY =="; bash /task/tests/test.sh; echo "reward(empty)=$(cat /logs/verifier/reward.txt)"
== EMPTY ==
distribution-gateway listening on 7070
========================================================== test session starts ==========================================================
platform linux -- Python 3.11.2, pytest-8.4.1, pluggy-1.6.0
rootdir: /task/tests
plugins: json-ctrf-0.3.5
collected 6 items                                                                                                                       

../task/tests/test_outputs.py FFFF.F                                                                                              [100%]

=============================================================== FAILURES ================================================================
______________________________________________________ test_report_matches_golden _______________________________________________________

    def test_report_matches_golden():
        result = subprocess.run(
            ["npm", "run", "report", "--silent"],
            cwd="/app", capture_output=True, text=True,
        )
        actual = mask(bundle_lines(result.stdout))
    
        with open("/app/reports/publications.expected.txt") as f:
            expected = mask(bundle_lines(f.read()))
    
>       assert actual == expected, f"output mismatch:\n{actual}\nvs\n{expected}"
E       AssertionError: output mismatch:
E         []
E         vs
E         ['BUNDLE BND-101 SIGNED KEY=fw-signing-2026-current', 'BUNDLE BND-101 PUBLISHED RECEIPT=<id> TOKEN=token-BND-101 STATUS=PUBLISHED', 'BUNDLE BND-102 SIGNED KEY=fw-signing-2026-current', 'BUNDLE BND-102 PUBLISHED RECEIPT=<id> TOKEN=token-BND-102 STATUS=PUBLISHED', 'BUNDLE BND-103 SIGNED KEY=fw-signing-2026-current', 'BUNDLE BND-103 PUBLISHED RECEIPT=<id> TOKEN=token-BND-103 STATUS=PUBLISHED']
E       assert [] == ['BUNDLE BND-...US=PUBLISHED']
E         
E         Right contains 6 more items, first extra item: 'BUNDLE BND-101 SIGNED KEY=fw-signing-2026-current'
E         Use -v to get more diff

/task/tests/test_outputs.py:23: AssertionError
______________________________________________ test_all_bundles_published_with_current_key ______________________________________________

    def test_all_bundles_published_with_current_key():
        out = run_report()
        published = [ln for ln in bundle_lines(out) if "PUBLISHED" in ln]
>       assert len(published) == len(publishable_bundles_from_manifest())
E       AssertionError: assert 0 == 3
E        +  where 0 = len([])
E        +  and   3 = len({'BND-101', 'BND-102', 'BND-103'})
E        +    where {'BND-101', 'BND-102', 'BND-103'} = publishable_bundles_from_manifest()

/task/tests/test_outputs.py:50: AssertionError
___________________________________________________ test_receipts_persisted_in_duckdb ___________________________________________________

    def test_receipts_persisted_in_duckdb():
        run_report()
        con = duckdb.connect("/app/releases.duckdb")
        try:
>           rows = con.execute(
                "SELECT request_token, publication_id FROM publications"
            ).fetchall()
E           duckdb.duckdb.CatalogException: Catalog Error: Table with name publications does not exist!
E           Did you mean "pg_constraint"?
E           LINE 1: ...ECT request_token, publication_id FROM publications
E                                                             ^

/task/tests/test_outputs.py:60: CatalogException
_______________________________________________________ test_rerun_is_idempotent ________________________________________________________

    def test_rerun_is_idempotent():
        first = bundle_lines(run_report())
        second = bundle_lines(run_report())
>       assert first, "no report output to compare — publisher produced nothing"
E       AssertionError: no report output to compare — publisher produced nothing
E       assert []

/task/tests/test_outputs.py:79: AssertionError
___________________________________________ test_reconciliation_matches_independent_recompute ___________________________________________

    def test_reconciliation_matches_independent_recompute():
        expected = publishable_bundles_from_manifest()
        published = published_bundles_from_report()
>       assert published == expected, f"published {published} != expected {expected}"
E       AssertionError: published set() != expected {'BND-101', 'BND-103', 'BND-102'}
E       assert set() == {'BND-101', '...2', 'BND-103'}
E         
E         Extra items in the right set:
E         'BND-101'
E         'BND-103'
E         'BND-102'
E         Use -v to get more diff

/task/tests/test_outputs.py:104: AssertionError
================================================================ PASSES =================================================================
======================================================== short test summary info ========================================================
PASSED ../task/tests/test_outputs.py::test_revoked_key_signature_is_rejected
FAILED ../task/tests/test_outputs.py::test_report_matches_golden - AssertionError: output mismatch:
FAILED ../task/tests/test_outputs.py::test_all_bundles_published_with_current_key - AssertionError: assert 0 == 3
FAILED ../task/tests/test_outputs.py::test_receipts_persisted_in_duckdb - duckdb.duckdb.CatalogException: Catalog Error: Table with name publications does not exist!
FAILED ../task/tests/test_outputs.py::test_rerun_is_idempotent - AssertionError: no report output to compare — publisher produced nothing
FAILED ../task/tests/test_outputs.py::test_reconciliation_matches_independent_recompute - AssertionError: published set() != expected {'BND-101', 'BND-103', 'BND-102'}
====================================================== 5 failed, 1 passed in 1.08s ======================================================
reward: 0
reward(empty)=0
root@ec8f0c9abf0e:/app# sed 's/\r$//' /task/solution/publish.sh | bash
reference publisher installed
root@ec8f0c9abf0e:/app# echo "== SOLUTION =="; bash /task/tests/test.sh; echo "reward(solution)=$(cat /logs/verifier/reward.txt)"
== SOLUTION ==
distribution-gateway listening on 7070
========================================================== test session starts ==========================================================
platform linux -- Python 3.11.2, pytest-8.4.1, pluggy-1.6.0
rootdir: /task/tests
plugins: json-ctrf-0.3.5
collected 6 items                                                                                                                       

../task/tests/test_outputs.py ......                                                                                              [100%]

================================================================ PASSES =================================================================
======================================================== short test summary info ========================================================
PASSED ../task/tests/test_outputs.py::test_report_matches_golden
PASSED ../task/tests/test_outputs.py::test_all_bundles_published_with_current_key
PASSED ../task/tests/test_outputs.py::test_receipts_persisted_in_duckdb
PASSED ../task/tests/test_outputs.py::test_rerun_is_idempotent
PASSED ../task/tests/test_outputs.py::test_revoked_key_signature_is_rejected
PASSED ../task/tests/test_outputs.py::test_reconciliation_matches_independent_recompute
=========================================================== 6 passed in 1.76s ===========================================================
reward: 1
reward(solution)=1 

5. SUBMISSION_HANDBOOK.md was not included inside skeleton.zip; I followed requirements from the exam portal.

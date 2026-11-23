# Photo search quality: reproducible evaluation (audit branch)

## Scope

Buyer photo search only. Do **not** change seller camera or automatic categories.
Static audit against `develop` found:
- Buyer image picker and crop -> `POST /api/v1/search/image` -> validated
  upload -> crop -> OpenCLIP ViT-B/32 normalized 512-D vectors -> pgvector
  cosine retrieval -> active-offer filtering -> per-product dedupe -> cards.
- Actual image-to-image quality is **unmeasured** on a labelled real catalogue.
  Synthetic/stub CI tests cannot establish model precision.
- Startup `index_catalog()` loops over all product images and upserts
  pgvector rows, including existing vectors; measure startup duration and
  consider background incremental indexing in a separate change.
- The `PHOTO_SEARCH_MIN_SCORE=0.20` cosine threshold and 600-image
  candidate cap are not empirically tuned. Do not lower the threshold
  without an independent positive+negative evaluation.
- Current API permits 20 searches/IP/minute, 2 simultaneous searches per
  process, and a 2.5 s SQL statement timeout. Measure HTTP p50/p95/p99
  and HTTP errors with real OpenCLIP at several catalogue sizes.

## Index integrity (read-only)

With `SEARCH_BACKEND=clip` and a database available, from `server/`:

```bash
python -m backend.tools.audit_photo_index
```

The command reports total images, JSON embedding coverage for the current
model, and (on PostgreSQL) missing/orphan mirror rows. Nonzero missing
counts cause exit code 1. This does **not** assert that the original
image files are accessible or that indexed vectors correspond to
the latest image contents; verify those separately on staging.

## Human-labelled query set

Use independent query photos, never the indexed product photos or resized
variants of them. Suggested first pass: >=240 positive and >=60 negative
queries, across category, pose, background, lighting, near-duplicates,
and poor image quality. Avoid duplicate products leaking between
calibration and held-out sets. Include multiple gallery angles in
relevance labels where applicable. Keep the manifest and photo files
in a private location, outside Git.

Manifest schema:

```json
[
  {"image": "queries/bag-other-angle.jpg", "expected_ids": ["catalog-id-1"]},
  {"image": "queries/no-product.jpg", "expect_empty": true}
]
```

For Recall@K and Precision@K, `expected_ids` must enumerate **all
relevant products in the evaluated catalogue**. If only one known target
is annotated, report Hit@K, not Recall@K as a reliable estimate.
Use product IDs, not image IDs. A no-match query should use
`expect_empty: true`.

Run against a known staging snapshot (using HTTPS remotely):

```bash
cd server
python -m backend.tools.evaluate_photo_search_live \
  --manifest /private/queries.json \
  --api https://staging.example.invalid \
  --min-hit5 0.8 --min-negative-rejection 0.8 --max-p95 3.0 \
  --output /private/photo-benchmark.json
```

Replace the example URL and targets with an **approved** staging endpoint
and acceptance criteria. The defaults are *proposed targets*, not
achieved results. The script checks the response `method` is
`openclip_image_embedding`. It reports Hit, macro Recall, macro
Precision @1/5/10/20, positive empty/no-hit share, negative rejection,
false-positive negative share, median and p95 latency. Precision uses
a denominator of K, including requests that return fewer than K
results; evaluate macro metrics only on the annotated positive subset.
The default 3.1 second start-to-start request interval protects the
20/minute per-IP API rate limit. It is **not** a concurrency/load test.
For isolated staging with a deliberately higher API quota, override
`--request-interval` explicitly.

The live benchmark performs network requests and requires the independent
photos; normal CI cannot produce real accuracy numbers without those
assets. Do not upload private photos or response logs with identifying
data to a public PR.

## Load test and acceptance protocol

Use a disposable staging DB and image set, never production Docker
volumes. Check 1k / 5k / 18k / 50k images and multiple photos per
product. For each size record CPU/RAM/disk footprint, insertion and
indexing throughput, vector coverage, DB query p50/p95/p99,
end-to-end HTTP latency/errors under 1, 2, 5 and 10 concurrent users,
and API startup time. Keep OpenCLIP model/version, hardware, index
parameters, query set, catalogue snapshot and code commit fixed when
comparing changes. Enforce the rate limit only when measuring public
end-user behavior; raise it in an isolated environment for throughput
testing, rather than silently counting HTTP 429 as search latency.

## Release gates

- CI: Python unit/integration tests, isolated SQLite/PostgreSQL,
  Flutter buyer+seller checks and existing GitHub `gate` workflow.
- Staging: index coverage 100% for visible photos with valid offers;
  no stale mirror vectors; measured quality and tail latency within
  **agreed** limits; no new publication/visibility regressions.
- Deployment: no ML startup stall, rollback and backups available.
  No real accuracy or 18k-image performance results have been collected
  by this PR alone.

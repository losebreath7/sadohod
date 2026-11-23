"""End-to-end photo-search acceptance test against a running API.

This intentionally uses *independent* real-world query photographs, not
resized or brightened copies of catalogue media. Never commit private photos.

Manifest JSON example:
[
  {"image": "/private/queries/bag-01.jpg", "expected_ids": ["product-id"]},
  {"image": "/private/queries/unrelated.jpg", "expect_empty": true}
]

python -m backend.tools.evaluate_photo_search_live --manifest /private/queries.json \\
  --api https://api.example.com --min-hit5 0.8 --max-p95 3.0
"""
import argparse
import json
import math
import mimetypes
import statistics
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path


def summarize(samples):
    """Aggregate retrieval metrics over positive and negative queries separately.

    Recall assumes expected_ids is an exhaustive relevance judgement set.
    When it is incomplete, hit@K remains useful but recall/precision are biased.
    """
    if not samples:
        raise ValueError("At least one evaluation sample is required")
    positives = [s for s in samples if not s["expect_empty"]]
    negatives = [s for s in samples if s["expect_empty"]]
    latencies = sorted(s["duration"] for s in samples)
    p95 = latencies[min(len(latencies) - 1, math.ceil(.95 * len(latencies)) - 1)]
    result = {
        "queries": len(samples),
        "positive_queries": len(positives),
        "negative_queries": len(negatives),
        "hit_at_5": (sum(s["hit5"] for s in positives) / len(positives)) if positives else None,
        "negative_rejection_rate": (
            sum(s["empty"] for s in negatives) / len(negatives)) if negatives else None,
        "positive_zero_result_rate": (
            sum(s["empty"] for s in positives) / len(positives)) if positives else None,
        "positive_no_relevant_at_5_rate": (
            sum(not s["hit5"] for s in positives) / len(positives)) if positives else None,
        "false_positive_negative_rate": (
            sum(not s["empty"] for s in negatives) / len(negatives)) if negatives else None,
        "latency_median_seconds": round(statistics.median(latencies), 3),
        "latency_p95_seconds": round(p95, 3),
    }
    for k in (1, 5, 10, 20):
        if not positives:
            result[f"hit_at_{k}"] = None
            result[f"recall_at_{k}"] = None
            result[f"precision_at_{k}"] = None
            continue
        hit, recall, precision = [], [], []
        for sample in positives:
            actual = sample.get("returned_ids", [])
            expected = set(sample.get("expected_ids", []))
            if not expected:
                # Legacy unit tests may supply hit5 only; don't fabricate
                # relevance labels or an apparent precision/recall value.
                continue
            top = actual[:k]
            relevant_count = len(set(top) & expected)
            hit.append(relevant_count > 0)
            recall.append(relevant_count / len(expected))
            precision.append(relevant_count / k)
        result[f"hit_at_{k}"] = (sum(hit) / len(hit)) if hit else (result["hit_at_5"] if k == 5 else None)
        result[f"recall_at_{k}"] = (sum(recall) / len(recall)) if recall else None
        result[f"precision_at_{k}"] = (sum(precision) / len(precision)) if precision else None
    return result

def send_photo(endpoint, image_path, timeout):
    boundary = "sadohod-" + uuid.uuid4().hex
    data = image_path.read_bytes()
    if len(data) > 8 * 1024 * 1024:
        raise ValueError(f"Photo exceeds 8 MB: {image_path}")
    content_type = mimetypes.guess_type(image_path.name)[0] or "image/jpeg"
    body = (
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"query.jpg\"\r\n"
        f"Content-Type: {content_type}\r\n\r\n".encode()
        + data + f"\r\n--{boundary}--\r\n".encode()
    )
    request = urllib.request.Request(
        endpoint, data=body,
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
        method="POST")
    start = time.perf_counter()
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            payload = json.load(response)
    except urllib.error.HTTPError as exc:
        raise RuntimeError(f"Search HTTP {exc.code}: {exc.read(400)!r}") from exc
    return payload, time.perf_counter() - start


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--api", required=True)
    parser.add_argument("--min-hit5", type=float, default=.8)
    parser.add_argument("--max-p95", type=float, default=3.0)
    parser.add_argument("--min-negative-rejection", type=float, default=.8)
    parser.add_argument("--timeout", type=float, default=40)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    base = args.api.rstrip("/")
    parsed = urllib.parse.urlparse(base)
    if parsed.scheme != "https" and not (
        parsed.scheme == "http" and parsed.hostname in ("localhost", "127.0.0.1")):
        parser.error("Use HTTPS for remote photo uploads; HTTP is local-only.")
    if not (0 <= args.min_hit5 <= 1 and 0 <= args.min_negative_rejection <= 1 and args.max_p95 > 0):
        parser.error("Invalid acceptance targets.")
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    if not isinstance(manifest, list) or not manifest:
        parser.error("Manifest must be a non-empty JSON array.")
    if not any(entry.get("expect_empty") is True for entry in manifest):
        parser.error("Manifest requires independent negative queries with expect_empty=true.")
    if not any(entry.get("expect_empty") is not True for entry in manifest):
        parser.error("Manifest requires positive queries with expected_ids.")
    rows = []
    for i, entry in enumerate(manifest):
        expect_empty = entry.get("expect_empty") is True
        expected = entry.get("expected_ids", [])
        if (not isinstance(expected, list) or (not expected and not expect_empty)
                or (expect_empty and expected) or any(not isinstance(pid, str) or not pid for pid in expected)
                or len(set(expected)) != len(expected)):
            parser.error(f"Manifest item {i} must specify expected_ids or expect_empty.")
        image = Path(entry["image"])
        if not image.is_absolute():
            image = args.manifest.parent / image
        payload, elapsed = send_photo(base + "/api/v1/search/image?limit=20", image, args.timeout)
        if payload.get("method") != "openclip_image_embedding":
            raise RuntimeError("Server is not using OpenCLIP; evaluation aborted.")
        ids = [m["product"]["id"] for m in payload.get("items", [])[:20]]
        rows.append({
            "image": str(image), "expect_empty": expect_empty,
            "hit5": bool(set(ids[:5]) & set(expected)),
            "expected_ids": expected,
            "empty": not ids, "duration": elapsed, "returned_ids": ids,
        })
        print(f"{i + 1}/{len(manifest)}  {elapsed:.2f}s  top5={ids[:5]}")
    stats = summarize(rows)
    stats["engine"] = "openclip_image_embedding"
    stats["ranking_limit"] = 20
    stats["relevance_labels_exhaustive"] = "must be verified by dataset curator"
    stats["source"] = "independent labelled query photos supplied by evaluator"
    stats["passed"] = (stats["positive_queries"] > 0 and
                       stats["hit_at_5"] >= args.min_hit5 and
                       stats["latency_p95_seconds"] <= args.max_p95 and
                       stats["negative_queries"] > 0 and
                       stats["negative_rejection_rate"] >= args.min_negative_rejection)
    report = {"summary": stats, "results": rows}
    print(json.dumps(stats, ensure_ascii=False, indent=2))
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2))
    if not stats["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()

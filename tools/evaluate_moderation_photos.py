#!/usr/bin/env python3
"""Measure the *existing* OpenCLIP moderation triage on locally labelled photos.

Usage from repo root:
  python tools/evaluate_moderation_photos.py --manifest /secure/labeled-photos.csv
No pictures or scores are uploaded. This script does not tune live thresholds.
"""
from __future__ import annotations

import argparse
import csv
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def metrics(outcomes: list[tuple[str, str, str]]) -> dict:
    """(group, expected allow/review, actual allow/review), per group + overall."""
    groups: dict[str, Counter] = defaultdict(Counter)
    for group, expected, actual in outcomes:
        if expected not in ('allow', 'review') or actual not in ('allow', 'review'):
            raise ValueError('Expected/actual must be allow or review')
        key = ('TP' if actual == 'review' else 'FN') if expected == 'review' else (
            'FP' if actual == 'review' else 'TN')
        groups[group][key] += 1
        groups['ALL'][key] += 1

    def rate(n: int, d: int):
        return round(n / d, 4) if d else None

    return {
        group: {
            'samples': sum(counts.values()),
            'true_review': counts['TP'],
            'missed_review': counts['FN'],
            'false_review': counts['FP'],
            'correct_allow': counts['TN'],
            'review_recall': rate(counts['TP'], counts['TP'] + counts['FN']),
            'false_negative_rate': rate(counts['FN'], counts['TP'] + counts['FN']),
            'false_positive_rate': rate(counts['FP'], counts['FP'] + counts['TN']),
            'review_precision': rate(counts['TP'], counts['TP'] + counts['FP']),
        }
        for group, counts in sorted(groups.items())
    }


def evaluate(manifest: Path) -> dict:
    # Avoid importing the ML stack for metric-only tests.
    sys.path.insert(0, str(ROOT / 'server'))
    from backend.app.ml_clip import embed_image, MODEL_ID
    from backend.app.product_screening import _dot, _prompts, _visual_review_reason

    with manifest.open(newline='', encoding='utf-8-sig') as source:
        reader = csv.DictReader(source)
        if not reader.fieldnames or not {'image_path', 'expected', 'group'}.issubset(
                set(reader.fieldnames)):
            raise ValueError('CSV columns required: image_path,expected,group')
        records = list(reader)
    if not records:
        raise ValueError('No labelled samples in CSV')

    prompts, benign_prompts = _prompts()
    results: list[tuple[str, str, str]] = []
    unreadable = 0
    for record in records:
        expected = record['expected'].strip().lower()
        group = record['group'].strip()
        image_name = record['image_path'].strip()
        if expected not in ('allow', 'review') or not group or not image_name:
            raise ValueError('Invalid expected (allow/review), group or image_path')
        photo = (manifest.parent / image_name).resolve()
        if not photo.is_file():
            raise FileNotFoundError(f'Missing labeled photo in manifest row: {image_name}')
        try:
            vector = embed_image(photo.read_bytes())
            risk_scores = [(label, _dot(vector, prompt)) for label, prompt in prompts]
            benign = max(_dot(vector, prompt) for prompt in benign_prompts)
            reason = _visual_review_reason(risk_scores, benign)
        except Exception:
            # Real production triage fails closed when the ML model is unavailable.
            reason = 'ML inference failed (manual review required)'
            unreadable += 1
        results.append((group, expected, 'review' if reason else 'allow'))

    return {
        'model': MODEL_ID,
        'type': 'real-photo review triage, not prohibited-item identification',
        'samples': len(records),
        'ml_errors_requiring_review': unreadable,
        'metrics': metrics(results),
        'warning': ('Precision and recall are only meaningful for independently '
                    'labelled, representative photos. No acceptance threshold '
                    'has been approved; do not change live thresholds from '
                    'a small sample.'),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--output', type=Path, help='Write aggregated JSON report')
    args = parser.parse_args()
    result = evaluate(args.manifest.resolve())
    report = json.dumps(result, indent=2, ensure_ascii=False)
    print(report)
    if args.output:
        args.output.write_text(report + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()

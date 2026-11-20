"""Evaluate real OpenCLIP categories on labelled local images, without DB writes.

Run from server/:
  python -m backend.tools.evaluate_category_labels ./my-labelled-products.json

Manifest example:
  [{"image": "photos/monkey.jpg", "leaf": "toys-plush",
    "object": "обезьяна"},
   {"image": "photos/ring.jpg", "leaf": "jewelry-rings"}]

This measures recognition, unlike tests with mocked vectors. Use only images
that are authorised for local evaluation; never log personal information.
"""
import argparse
import json
from collections import defaultdict
from pathlib import Path

from backend.app.category_inference import (
    legacy_for_leaf, photo_vote, toy_leaf_vote, visual_leaf_vote, toy_object_vote,
)
from backend.app.ml_clip import embed_image


def predict(data):
    broad, score, confident = photo_vote(embed_image(data))
    if not confident:
        return {'leaf': None, 'object': None, 'score': round(score, 3)}
    vector = embed_image(data)
    leaf = toy_leaf_vote(vector) if broad == 'Игрушки' else visual_leaf_vote(vector)
    if leaf and legacy_for_leaf(leaf) != broad and not (
        broad == 'Одежда' and legacy_for_leaf(leaf) in
        ('Одежда', 'Верхняя одежда', 'Платья')
    ):
        leaf = None
    return {
        'leaf': leaf, 'object': toy_object_vote(vector) if leaf == 'toys-plush' else None,
        'score': round(score, 3),
    }


def evaluate(manifest):
    records = json.loads(manifest.read_text(encoding='utf8'))
    if not isinstance(records, list) or not records:
        raise ValueError('Manifest must contain a nonempty list of labelled images')
    correct = 0
    accepted = 0
    object_expected = 0
    object_hits = 0
    details = []
    for item in records:
        image_path = (manifest.parent / item['image']).resolve()
        expected = item['leaf']
        result = predict(image_path.read_bytes())
        matched = result['leaf'] == expected
        correct += int(matched)
        accepted += int(result['leaf'] is not None)
        if item.get('object'):
            object_expected += 1
            object_hits += int(result['object'] == item['object'])
        details.append({'image': item['image'], 'expected': expected,
                        'predicted': result['leaf'], 'object': result['object'],
                        'match': matched})
    size = len(records)
    return {
        'samples': size, 'leaf_accuracy': round(correct / size, 4),
        'coverage': round(accepted / size, 4),
        'precision_when_assigned': round(correct / accepted, 4) if accepted else None,
        'object_tag_recall': round(object_hits / object_expected, 4)
                            if object_expected else None,
        'details': details,
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('manifest', type=Path)
    args = parser.parse_args()
    print(json.dumps(evaluate(args.manifest), ensure_ascii=False, indent=2))

"""Deterministic checks for the benchmark report, not recognition quality."""
from evaluate_moderation_photos import metrics


def test_counts_and_rates():
    report = metrics([
        ('weapon', 'review', 'review'),
        ('weapon', 'review', 'allow'),
        ('apparel', 'allow', 'review'),
        ('apparel', 'allow', 'allow'),
    ])
    total = report['ALL']
    assert total['samples'] == 4
    assert (total['true_review'], total['missed_review'],
            total['false_review'], total['correct_allow']) == (1, 1, 1, 1)
    assert total['review_recall'] == 0.5
    assert total['false_positive_rate'] == 0.5
    assert total['false_negative_rate'] == 0.5
    assert report['weapon']['false_positive_rate'] is None
    assert report['apparel']['review_recall'] is None


def test_unknown_labels_fail():
    try:
        metrics([('other', 'unsure', 'allow')])
    except ValueError:
        pass
    else:
        raise AssertionError('Unknown label must fail validation')


if __name__ == '__main__':
    test_counts_and_rates()
    test_unknown_labels_fail()
    print('Moderation benchmark aggregation: OK')

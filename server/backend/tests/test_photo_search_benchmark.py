from backend.tools.evaluate_photo_search_live import summarize


def test_photo_benchmark_reports_hit5_rejection_and_p95():
    samples = [
        {"expect_empty": False, "hit5": True, "empty": False, "duration": 1.0},
        {"expect_empty": False, "hit5": False, "empty": False, "duration": 1.5},
        {"expect_empty": True, "hit5": False, "empty": True, "duration": 2.0},
        {"expect_empty": True, "hit5": False, "empty": False, "duration": 4.0},
    ]
    result = summarize(samples)
    assert result["queries"] == 4
    assert result["hit_at_5"] == 0.5
    assert result["negative_rejection_rate"] == 0.5
    assert result["latency_p95_seconds"] == 4.0


def test_photo_benchmark_all_positive_samples():
    result = summarize([
        {"expect_empty": False, "hit5": True, "empty": False, "duration": 0.7},
    ])
    assert result["hit_at_5"] == 1
    assert result["negative_rejection_rate"] is None


def test_acceptance_requires_positive_and_negative_photos(tmp_path, monkeypatch):
    """A gate without hard negatives cannot validate false-positive behavior."""
    import json
    import sys
    import pytest
    from backend.tools.evaluate_photo_search_live import main

    manifest = tmp_path / "manifest.json"
    for entries in (
        [{"image": "test.jpg", "expected_ids": ["p01"]}],
        [{"image": "test.jpg", "expect_empty": True}],
    ):
        manifest.write_text(json.dumps(entries), encoding="utf-8")
        monkeypatch.setattr(sys, "argv", [
            "evaluate_photo_search_live", "--manifest", str(manifest),
            "--api", "http://localhost:8000",
        ])
        with pytest.raises(SystemExit) as error:
            main()
        assert error.value.code == 2


def test_precision_recall_and_hit_are_calculated_per_query():
    samples = [
        {"expect_empty": False, "expected_ids": ["a", "b"],
         "returned_ids": ["a", "x", "c", "d", "e", "b"], "hit5": True,
         "empty": False, "duration": .2},
        {"expect_empty": False, "expected_ids": ["z"],
         "returned_ids": ["x", "y"], "hit5": False,
         "empty": False, "duration": .3},
        {"expect_empty": True, "expected_ids": [],
         "returned_ids": [], "hit5": False,
         "empty": True, "duration": .4},
    ]
    result = summarize(samples)
    assert result["hit_at_1"] == .5
    assert result["hit_at_5"] == .5
    assert result["recall_at_1"] == .25
    assert result["recall_at_5"] == .25
    assert result["recall_at_10"] == .75
    assert result["precision_at_1"] == .5
    assert result["precision_at_5"] == .1
    assert result["precision_at_10"] == .1
    assert result["negative_rejection_rate"] == 1
    assert result["false_positive_negative_rate"] == 0
    assert result["positive_zero_result_rate"] == 0
    assert result["positive_no_relevant_at_5_rate"] == .5


def test_no_predictions_positive_query_is_not_a_correct_rejection():
    result = summarize([
        {"expect_empty": False, "expected_ids": ["a"],
         "returned_ids": [], "hit5": False, "empty": True, "duration": .1},
        {"expect_empty": True, "expected_ids": [],
         "returned_ids": ["wrong"], "hit5": False, "empty": False, "duration": .2},
    ])
    assert result["recall_at_5"] == 0
    assert result["precision_at_5"] == 0
    assert result["positive_zero_result_rate"] == 1
    assert result["negative_rejection_rate"] == 0
    assert result["false_positive_negative_rate"] == 1


def test_empty_sample_set_is_not_valid_evaluation():
    import pytest
    with pytest.raises(ValueError, match="At least one"):
        summarize([])

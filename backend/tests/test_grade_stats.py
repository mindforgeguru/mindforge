"""#19: Class High/Low must be the whole class's figures for a test, not the
viewer's own min/max. Pure-logic tests on app.core.grade_stats.
"""

from app.core.grade_stats import class_extremes, percentage


def test_high_low_span_the_whole_test_cohort():
    # Test 5 taken by three students; one scored 100, one 10.
    out = class_extremes([(5, 90.0), (5, 100.0), (5, 10.0)])
    assert out[5] == (100.0, 10.0)


def test_each_test_is_independent():
    out = class_extremes([(5, 90.0), (5, 10.0), (7, 55.0), (7, 60.0)])
    assert out[5] == (90.0, 10.0)
    assert out[7] == (60.0, 55.0)


def test_single_grade_high_equals_low():
    out = class_extremes([(7, 50.0)])
    assert out[7] == (50.0, 50.0)


def test_null_test_id_is_skipped():
    # Offline/manual grades (no test) contribute no cohort.
    out = class_extremes([(None, 5.0), (5, 80.0)])
    assert None not in out
    assert out == {5: (80.0, 80.0)}


def test_percentage_matches_grade_rounding():
    assert percentage(9, 10) == 90.0
    assert percentage(1, 3) == 33.33
    assert percentage(0, 0) == 0.0   # guard against divide-by-zero

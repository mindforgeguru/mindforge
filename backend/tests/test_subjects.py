"""The canonical grade and subject lists, and cleaning AI output onto them.

Test generation picks old papers with an exact `grade == ... AND subject == ...`
match, using the app's subject list. A paper stored as "Math", "physics" or
grade "8" looks classified on screen but is never used. The scan prompt itself
asked the model for "Math" while the app says "Mathematics".
"""

import re
from pathlib import Path

import pytest

from app.core.subjects import GRADES, SUBJECTS, normalize_grade, normalize_subject
from app.services.ai_service import _build_scan_prompt

CONSTANTS = Path(__file__).resolve().parents[2] / "frontend/lib/core/utils/constants.dart"


def _dart_list(name):
    body = re.search(rf"{name}\s*=\s*\[(.*?)\];", CONSTANTS.read_text(), re.S).group(1)
    return re.findall(r"'([^']*)'|(\d+)", body)


class TestListsMatchTheApp:
    @pytest.mark.skipif(not CONSTANTS.exists(), reason="frontend not checked out")
    def test_subjects_match_app_constants(self):
        assert list(SUBJECTS) == [s for s, _ in _dart_list("subjects")]

    @pytest.mark.skipif(not CONSTANTS.exists(), reason="frontend not checked out")
    def test_grades_match_app_constants(self):
        assert list(GRADES) == [int(g) for _, g in _dart_list("grades")]

    def test_scan_prompt_offers_exactly_the_canonical_subjects(self):
        prompt = _build_scan_prompt()
        for subject in SUBJECTS:
            assert subject in prompt, f"prompt never offers {subject!r}"
        assert "Math," not in prompt


class TestNormalizeSubject:
    @pytest.mark.parametrize("raw,expected", [
        ("Physics", "Physics"),
        ("physics", "Physics"),
        ("  PHYSICS ", "Physics"),
        ("Math", "Mathematics"),
        ("Maths", "Mathematics"),
        ("history and civics", "History & Civics"),
        ("Computer Applications", "Computer Applications"),
    ])
    def test_maps_onto_the_canonical_name(self, raw, expected):
        assert normalize_subject(raw) == expected

    @pytest.mark.parametrize("raw", [None, "", "Sanskrit", 8, "Physics; DROP TABLE"])
    def test_anything_else_is_unclassified(self, raw):
        assert normalize_subject(raw) is None


class TestNormalizeGrade:
    @pytest.mark.parametrize("raw,expected", [(8, 8), ("9", 9), (" 10 ", 10), (10.0, 10)])
    def test_accepts_supported_grades(self, raw, expected):
        assert normalize_grade(raw) == expected

    @pytest.mark.parametrize("raw", [None, 7, 11, "eight", "", True, 8.5])
    def test_anything_else_is_unclassified(self, raw):
        assert normalize_grade(raw) is None

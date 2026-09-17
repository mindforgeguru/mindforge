"""The AI provider fallback chains degrade the way they claim to.

Five chains, not one:

  generate_test_questions   Claude -> Gemini -> Groq   (teacher-built tests)
  generate_mcqs_from_text   Claude -> Gemini -> Groq   (auto-quiz from slides)
  presentation _generate_text  Claude -> Gemini        (slide decks)
  scan_document_metadata    Gemini -> Groq             (database upload scan)
  scan_syllabus             Gemini -> Groq

Every provider is faked at the lowest seam each chain calls, so the chain's own
ordering, short-circuiting, key checks and error reporting run for real. No
network, no keys.

A provider that *answers* is not the same as one that *succeeded*: an empty
string or a question list with nothing usable in it is a failure, and the chain
has to move on rather than hand a teacher an empty test.
"""

import asyncio
import json
import time
from types import SimpleNamespace

import pytest

from app.schemas.test import TestGenerationParams
from app.services import ai_service, presentation_service

# A scripted outcome meaning "never answers". Async fakes sleep far past any
# cap; sync fakes (SDK calls run in a worker thread) sleep briefly, since
# asyncio.run waits for worker threads on exit.
HANG = object()
SYNC_HANG_SECONDS = 1.5

QUESTIONS = [{"type": "mcq", "question": "What is force?",
              "options": {"A": "push", "B": "colour"}, "answer": "A"}]


def _params():
    return TestGenerationParams(title="t", grade=8, subject="Physics", chapter="Force")


@pytest.fixture
def keys(monkeypatch):
    """All three keys configured; a test unsets the ones it wants missing."""
    def set_keys(anthropic="k", gemini="k", groq="k"):
        monkeypatch.setattr(ai_service.settings, "ANTHROPIC_API_KEY", anthropic)
        monkeypatch.setattr(ai_service.settings, "GEMINI_API_KEY", gemini)
        monkeypatch.setattr(ai_service.settings, "GROQ_API_KEY", groq)
    set_keys()
    return set_keys


class Recorder:
    def __init__(self):
        self.calls = []
        self.kwargs = {}


def _timed(coro):
    """Run `coro`, returning (result or exception, seconds until the chain
    itself returned). Measured inside the loop: asyncio.run also waits for any
    worker thread still stuck in a fake SDK call, which isn't the chain's time."""
    async def main():
        start = time.monotonic()
        try:
            result = await coro
        except Exception as exc:  # noqa: BLE001 - returned for the test to inspect
            result = exc
        return result, time.monotonic() - start
    return asyncio.run(main())


@pytest.fixture
def budgets(monkeypatch):
    """Shrink every chain's time budget to test scale."""
    def set_budget(chain, **values):
        monkeypatch.setitem(ai_service._TIME_BUDGETS, chain, values)
    return set_budget


# ── Chain 1: generate_test_questions ─────────────────────────────────────────


@pytest.fixture
def providers(monkeypatch):
    """Fake the three per-provider generators. Each behaves as scripted:
    a list is returned, an Exception instance is raised."""
    rec = Recorder()
    script = {"claude": QUESTIONS, "gemini": QUESTIONS, "groq": QUESTIONS}

    def fake(name):
        async def gen(*_args, **kwargs):
            rec.calls.append(name)
            rec.kwargs[name] = kwargs
            outcome = script[name]
            if outcome is HANG:
                await asyncio.sleep(60)
            if isinstance(outcome, Exception):
                raise outcome
            return outcome
        return gen

    monkeypatch.setattr(ai_service, "_generate_with_claude", fake("claude"))
    monkeypatch.setattr(ai_service, "_generate_with_gemini", fake("gemini"))
    monkeypatch.setattr(ai_service, "_generate_with_groq", fake("groq"))
    rec.script = script
    return rec


def _generate():
    return asyncio.run(ai_service.generate_test_questions([], [], [], _params()))


class TestGenerateTestQuestions:
    def test_primary_success_short_circuits(self, keys, providers):
        assert _generate() == QUESTIONS
        assert providers.calls == ["claude"]

    def test_claude_failure_falls_to_gemini_only(self, keys, providers):
        providers.script["claude"] = RuntimeError("overloaded")
        assert _generate() == QUESTIONS
        assert providers.calls == ["claude", "gemini"]

    def test_two_failures_fall_to_groq(self, keys, providers):
        providers.script["claude"] = RuntimeError("overloaded")
        providers.script["gemini"] = RuntimeError("spending cap")
        assert _generate() == QUESTIONS
        assert providers.calls == ["claude", "gemini", "groq"]

    def test_all_fail_raises_with_every_reason_in_order(self, keys, providers):
        providers.script["claude"] = RuntimeError("credit balance too low")
        providers.script["gemini"] = RuntimeError("spending cap")
        providers.script["groq"] = RuntimeError("rate limited")
        with pytest.raises(RuntimeError) as exc:
            _generate()
        msg = str(exc.value)
        assert msg.index("credit balance too low") < msg.index("spending cap") < msg.index("rate limited")

    def test_missing_key_skips_provider_without_calling_it(self, keys, providers):
        keys(anthropic="")
        assert _generate() == QUESTIONS
        assert providers.calls == ["gemini"]

    def test_no_keys_reports_each_as_unconfigured(self, keys, providers):
        keys(anthropic="", gemini="", groq="")
        with pytest.raises(RuntimeError) as exc:
            _generate()
        assert providers.calls == []
        for name in ("ANTHROPIC_API_KEY", "GEMINI_API_KEY", "GROQ_API_KEY"):
            assert name in str(exc.value)

    def test_empty_question_list_is_a_failure_not_a_success(self, keys, providers):
        """A provider that returns nothing usable (all questions filtered, or a
        bare []) must not end the chain with an empty test."""
        providers.script["claude"] = []
        assert _generate() == QUESTIONS
        assert providers.calls == ["claude", "gemini"]

    def test_all_empty_raises_rather_than_returning_nothing(self, keys, providers):
        for name in ("claude", "gemini", "groq"):
            providers.script[name] = []
        with pytest.raises(RuntimeError):
            _generate()


# ── Chain 2: generate_mcqs_from_text (inline provider calls) ────────────────


class FakeGemini:
    def __init__(self, rec, outcome):
        self.rec, self.outcome = rec, outcome
        self.models = SimpleNamespace(generate_content=self._generate)
        self.files = SimpleNamespace(upload=self._upload, delete=self._delete)
        self.deleted = []

    def _generate(self, **kwargs):
        self.rec.calls.append("gemini")
        self.rec.kwargs["gemini"] = kwargs
        if self.outcome is HANG:
            time.sleep(SYNC_HANG_SECONDS)
            raise RuntimeError("fake SDK timeout")
        if isinstance(self.outcome, Exception):
            raise self.outcome
        return SimpleNamespace(text=self.outcome, candidates=[])

    def _upload(self, **_kwargs):
        return SimpleNamespace(name="files/abc")

    def _delete(self, name):
        self.deleted.append(name)


class FakeGroq:
    def __init__(self, rec, outcome):
        self.rec, self.outcome = rec, outcome
        self.chat = SimpleNamespace(completions=SimpleNamespace(create=self._create))

    def _create(self, **kwargs):
        self.rec.calls.append("groq")
        self.rec.kwargs["groq"] = kwargs
        if self.outcome is HANG:
            time.sleep(SYNC_HANG_SECONDS)
            raise RuntimeError("fake SDK timeout")
        if isinstance(self.outcome, Exception):
            raise self.outcome
        return SimpleNamespace(choices=[SimpleNamespace(message=SimpleNamespace(content=self.outcome))])


@pytest.fixture
def raw_providers(monkeypatch):
    """Fake providers that return raw model text, so parsing runs for real."""
    rec = Recorder()
    good = json.dumps(QUESTIONS)
    rec.script = {"claude": good, "gemini": good, "groq": good}

    async def claude(*_args, **kwargs):
        rec.calls.append("claude")
        rec.kwargs["claude"] = kwargs
        outcome = rec.script["claude"]
        if outcome is HANG:
            await asyncio.sleep(60)
        if isinstance(outcome, Exception):
            raise outcome
        return outcome

    rec.gemini = None
    def gemini_client():
        if rec.gemini is None:
            rec.gemini = FakeGemini(rec, rec.script["gemini"])
        return rec.gemini

    monkeypatch.setattr(ai_service, "claude_generate", claude)
    monkeypatch.setattr(ai_service, "_get_gemini_client", gemini_client)
    monkeypatch.setattr(ai_service, "_get_groq_client", lambda: FakeGroq(rec, rec.script["groq"]))
    monkeypatch.setattr(ai_service, "_upload_file_to_gemini",
                        lambda fb, ext: gemini_client().files.upload())
    monkeypatch.setattr(ai_service, "_extract_text_from_file", lambda fb, ext: "chapter text")
    return rec


def _from_text():
    return asyncio.run(ai_service.generate_mcqs_from_text("slides", _params()))


class TestGenerateMcqsFromText:
    def test_primary_success_short_circuits(self, keys, raw_providers):
        assert [q["question"] for q in _from_text()] == ["What is force?"]
        assert raw_providers.calls == ["claude"]

    def test_unparseable_claude_output_falls_through(self, keys, raw_providers):
        raw_providers.script["claude"] = "Sorry, I can't help with that."
        assert _from_text()
        assert raw_providers.calls == ["claude", "gemini"]

    def test_blocked_gemini_response_falls_to_groq(self, keys, raw_providers):
        raw_providers.script["claude"] = RuntimeError("overloaded")
        raw_providers.script["gemini"] = ""  # empty text = blocked / nothing
        assert _from_text()
        assert raw_providers.calls == ["claude", "gemini", "groq"]

    def test_all_fail_raises(self, keys, raw_providers):
        for name in ("claude", "gemini", "groq"):
            raw_providers.script[name] = RuntimeError(f"{name} down")
        with pytest.raises(RuntimeError) as exc:
            _from_text()
        assert "claude down" in str(exc.value) and "groq down" in str(exc.value)

    def test_empty_array_is_a_failure_not_a_success(self, keys, raw_providers):
        raw_providers.script["claude"] = "[]"
        assert _from_text()
        assert raw_providers.calls == ["claude", "gemini"]


# ── Chain 3: presentation _generate_text (Claude -> Gemini) ─────────────────


@pytest.fixture
def deck_providers(monkeypatch):
    rec = Recorder()
    rec.script = {"claude": "claude text", "gemini": "gemini text"}

    async def claude(*_args, **kwargs):
        rec.calls.append("claude")
        rec.kwargs["claude"] = kwargs
        outcome = rec.script["claude"]
        if outcome is HANG:
            await asyncio.sleep(60)
        if isinstance(outcome, Exception):
            raise outcome
        return outcome

    async def gemini(*_args, **kwargs):
        rec.calls.append("gemini")
        rec.kwargs["gemini"] = kwargs
        outcome = rec.script["gemini"]
        if outcome is HANG:
            await asyncio.sleep(60)
        if isinstance(outcome, Exception):
            raise outcome
        return outcome

    monkeypatch.setattr(presentation_service.ai_service, "claude_generate", claude)
    monkeypatch.setattr(presentation_service, "_gemini_call", gemini)
    monkeypatch.setattr(presentation_service.settings, "ANTHROPIC_API_KEY", "k")
    return rec


def _deck_text():
    return asyncio.run(presentation_service._generate_text(b"%PDF", "pdf", "prompt"))


class TestPresentationGenerateText:
    def test_primary_success_short_circuits(self, deck_providers):
        assert _deck_text() == "claude text"
        assert deck_providers.calls == ["claude"]

    def test_claude_failure_falls_to_gemini(self, deck_providers):
        deck_providers.script["claude"] = RuntimeError("overloaded")
        assert _deck_text() == "gemini text"
        assert deck_providers.calls == ["claude", "gemini"]

    def test_missing_key_goes_straight_to_gemini(self, deck_providers, monkeypatch):
        monkeypatch.setattr(presentation_service.settings, "ANTHROPIC_API_KEY", "")
        assert _deck_text() == "gemini text"
        assert deck_providers.calls == ["gemini"]

    def test_empty_claude_text_falls_to_gemini(self, deck_providers):
        """Empty text is not a deck. Returning it fails the parse one level up,
        after the chance to fall back has already passed."""
        deck_providers.script["claude"] = ""
        assert _deck_text() == "gemini text"
        assert deck_providers.calls == ["claude", "gemini"]


# ── Chains 4 and 5: document and syllabus scans (Gemini -> Groq) ─────────────


META = {"grade": 8, "subject": "Physics", "chapter": "Force", "title": "Force", "summary": "s"}
EMPTY_META = {"grade": None, "subject": None, "chapter": None, "title": None, "summary": None}


class TestScans:
    def test_metadata_gemini_failure_falls_to_groq(self, keys, raw_providers):
        raw_providers.script["gemini"] = RuntimeError("spending cap")
        raw_providers.script["groq"] = json.dumps(META)
        assert asyncio.run(ai_service.scan_document_metadata(b"%PDF", "pdf")) == META
        assert raw_providers.calls == ["gemini", "groq"]

    def test_metadata_all_fail_returns_empty_metadata(self, keys, raw_providers):
        raw_providers.script["gemini"] = RuntimeError("spending cap")
        raw_providers.script["groq"] = RuntimeError("rate limited")
        assert asyncio.run(ai_service.scan_document_metadata(b"%PDF", "pdf")) == EMPTY_META

    def test_metadata_no_keys_calls_nothing(self, keys, raw_providers):
        keys(anthropic="", gemini="", groq="")
        assert asyncio.run(ai_service.scan_document_metadata(b"%PDF", "pdf")) == EMPTY_META
        assert raw_providers.calls == []

    def test_metadata_failed_gemini_call_still_deletes_the_upload(self, keys, raw_providers):
        """The document was already sent to Google. A failed generation must not
        leave the school's file sitting in a third party's storage."""
        raw_providers.script["gemini"] = RuntimeError("spending cap")
        raw_providers.script["groq"] = json.dumps(META)
        asyncio.run(ai_service.scan_document_metadata(b"%PDF", "pdf"))
        assert raw_providers.gemini.deleted == ["files/abc"]

    def test_syllabus_gemini_failure_falls_to_groq(self, keys, raw_providers):
        raw_providers.script["gemini"] = RuntimeError("spending cap")
        raw_providers.script["groq"] = '["Force", "Pressure"]'
        assert asyncio.run(ai_service.scan_syllabus(b"%PDF", "pdf", 8, "Physics")) == ["Force", "Pressure"]
        assert raw_providers.calls == ["gemini", "groq"]

    def test_syllabus_failed_gemini_call_still_deletes_the_upload(self, keys, raw_providers):
        raw_providers.script["gemini"] = RuntimeError("spending cap")
        raw_providers.script["groq"] = "[]"
        asyncio.run(ai_service.scan_syllabus(b"%PDF", "pdf", 8, "Physics"))
        assert raw_providers.gemini.deleted == ["files/abc"]


# ── Timeouts: a provider that hangs instead of failing ───────────────────────
#
# Without a deadline of our own, a stalled provider holds the request for the
# SDK default (10 minutes for Anthropic) — long after the app stopped waiting
# (180s for test generation, 120s for uploads) — and the fallback never runs.


class TestTimeouts:
    def test_hanging_claude_falls_to_gemini_within_its_cap(self, keys, providers, budgets):
        budgets("test", budget=2.0, claude=0.2, gemini=0.5, groq=0.5)
        providers.script["claude"] = HANG
        result, elapsed = _timed(ai_service.generate_test_questions([], [], [], _params()))
        assert result == QUESTIONS
        assert providers.calls == ["claude", "gemini"]
        assert elapsed < 0.6

    def test_timeout_is_reported_with_its_duration(self, keys, providers, budgets):
        budgets("test", budget=2.0, claude=0.1, gemini=0.1, groq=0.1)
        for name in ("claude", "gemini", "groq"):
            providers.script[name] = HANG
        result, _ = _timed(ai_service.generate_test_questions([], [], [], _params()))
        assert isinstance(result, RuntimeError)
        assert "Claude: timed out after" in str(result)
        assert "Groq: timed out after" in str(result)

    def test_chain_stops_when_its_budget_is_spent(self, keys, providers, budgets):
        """The budget is what the caller will wait. Once it's gone, starting
        another provider only produces a result nobody receives."""
        budgets("test", budget=0.5, claude=0.3, gemini=0.3, groq=0.3)
        for name in ("claude", "gemini", "groq"):
            providers.script[name] = HANG
        result, elapsed = _timed(ai_service.generate_test_questions([], [], [], _params()))
        assert isinstance(result, RuntimeError)
        assert elapsed < 0.7
        assert providers.calls == ["claude", "gemini"]
        assert "Groq: skipped" in str(result)

    def test_each_provider_is_handed_its_timeout(self, keys, providers, budgets):
        """The same deadline goes to the SDK call, so the worker thread stops too
        instead of streaming on (and billing) after the chain has moved on."""
        budgets("test", budget=100, claude=40, gemini=20, groq=10)
        providers.script["claude"] = RuntimeError("down")
        providers.script["gemini"] = RuntimeError("down")
        _generate()
        assert 39 < providers.kwargs["claude"]["timeout"] <= 40
        assert 19 < providers.kwargs["gemini"]["timeout"] <= 20
        assert 9 < providers.kwargs["groq"]["timeout"] <= 10

    def test_quiz_chain_times_out_claude_and_passes_sdk_timeouts(
        self, keys, raw_providers, budgets
    ):
        budgets("quiz", budget=100, claude=0.2, gemini=30, groq=15)
        raw_providers.script["claude"] = HANG
        raw_providers.script["gemini"] = RuntimeError("spending cap")
        result, elapsed = _timed(ai_service.generate_mcqs_from_text("slides", _params()))
        assert result and not isinstance(result, Exception)
        assert elapsed < 0.6
        assert raw_providers.calls == ["claude", "gemini", "groq"]
        gemini_ms = raw_providers.kwargs["gemini"]["config"].http_options.timeout
        assert 29_000 < gemini_ms <= 30_000
        assert 14 < raw_providers.kwargs["groq"]["timeout"] <= 15

    def test_scan_times_out_a_stuck_gemini_call_and_uses_groq(
        self, keys, raw_providers, budgets
    ):
        budgets("scan", budget=5, gemini=0.2, groq=2)
        raw_providers.script["gemini"] = HANG
        raw_providers.script["groq"] = json.dumps(META)
        result, elapsed = _timed(ai_service.scan_document_metadata(b"%PDF", "pdf"))
        assert result == META
        assert elapsed < SYNC_HANG_SECONDS - 0.5
        assert raw_providers.kwargs["gemini"]["config"].http_options.timeout <= 200

    def test_syllabus_scan_times_out_a_stuck_gemini_call(self, keys, raw_providers, budgets):
        budgets("scan", budget=5, gemini=0.2, groq=2)
        raw_providers.script["gemini"] = HANG
        raw_providers.script["groq"] = '["Force"]'
        result, elapsed = _timed(ai_service.scan_syllabus(b"%PDF", "pdf", 8, "Physics"))
        assert result == ["Force"]
        assert elapsed < SYNC_HANG_SECONDS - 0.5

    def test_deck_hanging_claude_falls_to_gemini(self, deck_providers, budgets):
        budgets("deck", budget=5, claude=0.2, gemini=3)
        deck_providers.script["claude"] = HANG
        result, elapsed = _timed(
            presentation_service._generate_text(b"%PDF", "pdf", "prompt")
        )
        assert result == "gemini text"
        assert elapsed < 0.6
        assert 2 < deck_providers.kwargs["gemini"]["timeout"] <= 3

    def test_deck_timeout_is_shown_to_the_teacher_in_plain_words(self):
        reason = presentation_service._friendly_failure_reason(
            TimeoutError("timed out after 300s")
        )
        assert "too long" in reason

"""
Prompt-injection defence on the chapter-PDF pipeline.

The flow is: a teacher uploads a chapter PDF, it is attached to a prompt and
sent to the model, the model writes slides, and a period log turns those slides
into an auto-quiz that is broadcast to students with **no human review**. So
text inside an uploaded document can reach children without anyone reading it.

The realistic attack is not a malicious teacher. It is an ordinary teacher
downloading a chapter PDF from the web that carries instructions hidden in white
5pt text — invisible on the page, fully legible to a model reading the file.
A crafted PDF was produced during this work and the payload was confirmed
recoverable from the text layer while being invisible on screen.

The prompts previously contained no defence at all: no framing of the document
as data, no instruction to ignore directions found inside it.

**What these tests do and do not prove.** They check the defensive framing is
present and survives edits. They do NOT prove a model obeys it — that needs a
live call, and no provider was reachable when this was written (Claude
unconfigured locally, Gemini over its spending cap). `scripts/probe_prompt_injection.py`
runs the empirical half when a key is available. Until it has been run, treat
this as a mitigation with unverified efficacy, not a solved problem.
"""

import pytest

from app.services.presentation_service import (
    _build_outline_prompt,
    _build_slide_fill_prompt,
)
from app.services.ai_service import _build_scan_prompt

CHAPTER_PROMPTS = [
    ("outline", lambda: _build_outline_prompt(8, "Physics", "Force and Pressure")),
    ("scan", lambda: _build_scan_prompt()),
]


class TestDocumentIsFramedAsUntrusted:
    @pytest.mark.parametrize("name,build", CHAPTER_PROMPTS)
    def test_prompt_tells_the_model_to_ignore_embedded_instructions(self, name, build):
        text = build().lower()
        # The specific wording can change; the property is that the prompt says
        # somewhere that instructions inside the document are not commands.
        assert "instruction" in text, f"{name} prompt does not mention instructions"
        assert any(k in text for k in ("ignore", "do not follow", "must not follow")), (
            f"{name} prompt never tells the model to disregard embedded instructions"
        )

    @pytest.mark.parametrize("name,build", CHAPTER_PROMPTS)
    def test_prompt_names_the_document_as_reference_material(self, name, build):
        text = build().lower()
        assert any(k in text for k in ("reference material", "source material",
                                       "untrusted", "data, not instructions")), (
            f"{name} prompt does not frame the document as material to read rather "
            "than a source of commands"
        )


class TestSlideFillIsAlsoDefended:
    def test_outline_content_is_treated_as_data(self):
        # Second hop, and easy to miss: the outline text passed here already came
        # out of a model that read the untrusted PDF, so an injection surviving
        # stage one gets a second chance to act here.
        text = _build_slide_fill_prompt(
            8, "Physics", "Force", [{"title": "t", "key_points": ["a"]}]
        ).lower()
        assert any(k in text for k in ("ignore", "do not follow", "must not follow")), (
            "slide-fill prompt has no defence; an injection that survives the "
            "outline stage is re-executed here"
        )


class TestDefenceIsNotTriviallyDefeatedByFormatting:
    def test_outline_prompt_states_the_required_topic_explicitly(self):
        # A prompt that names the expected chapter gives the model something to
        # anchor on, so "ignore the chapter and write about X" is visibly in
        # conflict rather than simply the latest instruction.
        text = _build_outline_prompt(9, "Biology", "Photosynthesis")
        assert "Photosynthesis" in text
        assert "Biology" in text

"""Old-test-paper upload stores first and classifies in the background.

The endpoint takes up to 20 files. It used to AI-scan them one after another
inside the request — up to 40s each against a client that gives up at 120s —
so a batch of more than a few papers timed out in the app even though the
server kept going. The screen already says "AI is classifying them" and shows
"AI classification pending..." on unclassified cards; this makes that true.

Everything outside the router is faked: storage, the AI scan, the database
session and the realtime publish.
"""

import asyncio
import io

from fastapi import BackgroundTasks
from starlette.datastructures import Headers, UploadFile

from app.routers import database_router

PDF = b"%PDF-1.4\n%fake\n"
META = {"grade": 8, "subject": "Physics", "chapter": "Force",
        "title": "Unit test on force", "summary": "Ten questions."}


def _upload(name):
    return UploadFile(file=io.BytesIO(PDF), filename=name, size=len(PDF),
                      headers=Headers({"content-type": "application/pdf"}))


class FakeDb:
    def __init__(self):
        self.added = []
        self.commits = 0

    def add(self, obj):
        self.added.append(obj)

    async def flush(self):
        for i, obj in enumerate(self.added, start=1):
            obj.id = obj.id or i

    async def commit(self):
        self.commits += 1


class Teacher:
    id = 7
    school_id = 3


class RecordStandIn:
    """The unit harness stubs the ORM base, so the real model can't be built."""

    def __init__(self, **fields):
        self.id = None
        self.created_at = None
        self.grade = self.subject = self.chapter = self.ai_summary = None
        self.__dict__.update(fields)


def _patch_io(monkeypatch, scans):
    stored = {}
    monkeypatch.setattr(database_router, "OldTestPaper", RecordStandIn)

    async def upload_file(bucket, key, data):
        stored[key] = data

    async def download_file(bucket, key):
        return stored[key]

    async def scan(data, ext):
        scans.append(ext)
        return dict(META)

    monkeypatch.setattr(database_router.storage_service, "upload_file", upload_file)
    monkeypatch.setattr(database_router.storage_service, "download_file", download_file)
    monkeypatch.setattr(database_router.ai_service, "scan_document_metadata", scan)
    return stored


class TestUploadReturnsBeforeClassifying:
    def test_no_ai_scan_runs_inside_the_request(self, monkeypatch):
        scans = []
        _patch_io(monkeypatch, scans)
        db, tasks = FakeDb(), BackgroundTasks()

        rows = asyncio.run(database_router.upload_old_test_paper(
            background_tasks=tasks, files=[_upload("a.pdf"), _upload("b.pdf")],
            db=db, current_user=Teacher(),
        ))

        assert scans == [], "the request waited on the AI"
        assert [r["original_filename"] for r in rows] == ["a.pdf", "b.pdf"]
        assert all(r["grade"] is None and r["subject"] is None for r in rows)
        assert db.commits == 1
        assert len(tasks.tasks) == 1, "classification was not scheduled"

    def test_rows_are_stored_before_the_response(self, monkeypatch):
        stored = _patch_io(monkeypatch, [])
        db = FakeDb()
        asyncio.run(database_router.upload_old_test_paper(
            background_tasks=BackgroundTasks(), files=[_upload("a.pdf")],
            db=db, current_user=Teacher(),
        ))
        (paper,) = db.added
        assert paper.file_key in stored
        assert paper.teacher_id == 7 and paper.school_id == 3
        assert paper.title == "a.pdf"


# ── Background classification ────────────────────────────────────────────────


class Paper:
    def __init__(self, pid, key):
        self.id, self.file_key = pid, key
        self.grade = self.subject = self.chapter = self.ai_summary = None
        self.title = "file.pdf"


class FakeSessionFactory:
    """`async with factory() as db` over a dict of papers by id."""

    def __init__(self, papers, fail_commit_for=()):
        self.papers = papers
        self.fail_commit_for = set(fail_commit_for)
        self.committed = []

    def __call__(self):
        factory = self

        class Session:
            current = None

            async def __aenter__(self):
                return self

            async def __aexit__(self, *exc):
                return False

            async def get(self, _model, pid):
                self.current = factory.papers.get(pid)
                return self.current

            async def commit(self):
                if self.current is not None and self.current.id in factory.fail_commit_for:
                    raise RuntimeError("value too long for column")
                factory.committed.append(self.current.id)

            async def rollback(self):
                pass

        return Session()


def _run_classify(monkeypatch, papers, scan, fail_commit_for=()):
    published = []

    async def download_file(bucket, key):
        return PDF

    async def publish_to_users(user_ids, payload):
        published.append((list(user_ids), payload))

    monkeypatch.setattr(database_router.storage_service, "download_file", download_file)
    monkeypatch.setattr(database_router.ai_service, "scan_document_metadata", scan)
    monkeypatch.setattr(database_router, "publish_to_users", publish_to_users)
    factory = FakeSessionFactory(papers, fail_commit_for)
    asyncio.run(database_router.classify_old_test_papers(
        teacher_id=7, items=[(pid, p.file_key, "pdf") for pid, p in papers.items()],
        session_factory=factory,
    ))
    return factory, published


class TestClassifyInBackground:
    def test_fills_in_metadata_and_tells_the_teacher(self, monkeypatch):
        papers = {1: Paper(1, "k1"), 2: Paper(2, "k2")}

        async def scan(data, ext):
            return dict(META)

        factory, published = _run_classify(monkeypatch, papers, scan)

        for p in papers.values():
            assert (p.grade, p.subject, p.chapter) == (8, "Physics", "Force")
            assert p.title == "Unit test on force" and p.ai_summary == "Ten questions."
        assert factory.committed == [1, 2]
        assert published, "the teacher's list is never told to refresh"
        assert all(ids == [7] and payload["event"] == "old_test_papers_classified"
                   for ids, payload in published)

    def test_one_bad_paper_does_not_stop_the_rest(self, monkeypatch):
        papers = {1: Paper(1, "k1"), 2: Paper(2, "k2"), 3: Paper(3, "k3")}

        async def scan(data, ext):
            return dict(META)

        factory, _ = _run_classify(monkeypatch, papers, scan, fail_commit_for={2})
        assert factory.committed == [1, 3]

    def test_scan_failure_leaves_the_paper_unclassified(self, monkeypatch):
        papers = {1: Paper(1, "k1"), 2: Paper(2, "k2")}
        calls = []

        async def scan(data, ext):
            calls.append(1)
            if len(calls) == 1:
                raise RuntimeError("all providers down")
            return dict(META)

        _run_classify(monkeypatch, papers, scan)
        assert papers[1].grade is None and papers[1].title == "file.pdf"
        assert papers[2].grade == 8

    def test_paper_deleted_before_classification_is_skipped(self, monkeypatch):
        papers = {2: Paper(2, "k2")}

        async def scan(data, ext):
            return dict(META)

        factory = FakeSessionFactory(papers)
        published = []

        async def download_file(bucket, key):
            return PDF

        async def publish_to_users(user_ids, payload):
            published.append(payload)

        monkeypatch.setattr(database_router.storage_service, "download_file", download_file)
        monkeypatch.setattr(database_router.ai_service, "scan_document_metadata", scan)
        monkeypatch.setattr(database_router, "publish_to_users", publish_to_users)
        asyncio.run(database_router.classify_old_test_papers(
            teacher_id=7, items=[(1, "gone", "pdf"), (2, "k2", "pdf")],
            session_factory=factory,
        ))
        assert factory.committed == [2]

from app.core.question_sources import effective_source_mix, honest_source_category


def test_chapter_only_moves_old_paper_share_to_ai():
    assert effective_source_mix(20, 20, 20, 20, 20,
                                has_old_papers=False, has_chapter=True) == (0, 20, 0, 20, 60)


def test_no_sources_is_all_ai():
    assert effective_source_mix(20, 20, 20, 20, 20,
                                has_old_papers=False, has_chapter=False) == (0, 0, 0, 0, 100)


def test_both_sources_keep_the_requested_mix():
    assert effective_source_mix(10, 30, 20, 20, 20,
                                has_old_papers=True, has_chapter=True) == (10, 30, 20, 20, 20)


def test_claimed_old_paper_tag_without_old_papers_becomes_ai():
    # #15: a chapter-only test came back tagged [P] and [E].
    assert honest_source_category(1, has_old_papers=False, has_chapter=True) == 5
    assert honest_source_category("3", has_old_papers=False, has_chapter=True) == 5
    assert honest_source_category(2, has_old_papers=False, has_chapter=True) == 2


def test_slides_only_claims_nothing_but_ai():
    for cat in (1, 2, 3, 4):
        assert honest_source_category(cat, has_old_papers=False, has_chapter=False) == 5


def test_unusable_tags_are_dropped():
    assert honest_source_category(None, has_old_papers=True, has_chapter=True) is None
    assert honest_source_category("x", has_old_papers=True, has_chapter=True) is None
    assert honest_source_category(9, has_old_papers=True, has_chapter=True) is None

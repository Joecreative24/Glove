from tutor_assistant.llm import FakeLLM
from tutor_assistant.materials import index_local_folder
from tutor_assistant.pipeline import log_session, mark_sent


def test_full_loop_with_fake_llm(db, materials_dir):
    index_local_folder(db, materials_dir)
    db.add_student("Dapo", board="AQA", level="GCSE Higher", subject="English")
    llm = FakeLLM()
    r = log_session(db, llm, "Dapo — past perfect, still confuses since/for, did well on the reading comp, send tense worksheet")
    assert not r.created_student and r.student.name == "Dapo"
    assert "past perfect" in r.session.topics
    assert any("since/for" in w for w in r.session.weak_spots)
    assert r.feedback.kind == "feedback" and "Dapo" in r.feedback.body
    assert r.materials is not None and [m.title for m in r.picked] == ["Tense worksheet"]
    assert "file://" in r.materials.body
    assert len(db.open_promises(r.student.id)) == 1
    assert llm.calls == ["classify", "draft_feedback", "pick_materials", "draft_materials_message"]

    mark_sent(db, r.materials, via="stdout")
    assert db.open_promises(r.student.id) == []
    assert db.get_outbox_item(r.materials.id).status == "sent"


def test_unknown_student_created_or_rejected(db):
    r = log_session(db, FakeLLM(), "Maya — fractions, did well", with_materials=False)
    assert r.created_student and db.find_student("Maya") is not None
    import pytest
    with pytest.raises(LookupError):
        log_session(db, FakeLLM(), "Zed — decimals", create_missing=False)


def test_history_flows_into_context(db):
    db.add_student("Dapo", board="AQA")
    log_session(db, FakeLLM(), "Dapo — past perfect, still confuses since/for", with_materials=False)
    log_session(db, FakeLLM(), "Dapo — past perfect, still confuses since/for", with_materials=False)

    seen = {}

    class Spy(FakeLLM):
        def draft_feedback(self, ctx):
            seen["ctx"] = ctx
            return super().draft_feedback(ctx)

    log_session(db, Spy(), "Dapo — reading comp, did well", with_materials=False)
    ctx = seen["ctx"]
    assert len(ctx.recent_sessions) == 2
    assert ctx.recurring_weak_spots and ctx.recurring_weak_spots[0].times_seen == 2
    block = ctx.history_block()
    assert "Exam board: AQA" in block and "Recurring weak spots" in block

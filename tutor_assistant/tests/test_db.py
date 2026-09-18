from datetime import datetime


def test_student_roundtrip_and_fuzzy_find(db):
    s = db.add_student("Dapo Adeyemi", board="AQA", level="GCSE")
    assert db.find_student("dapo").id == s.id
    assert db.find_student("Dapo Adeyemi").id == s.id
    assert db.find_student("Nobody") is None
    assert db.update_student(s.id, subject="English").subject == "English"


def test_session_updates_topics_and_weak_spots(db):
    s = db.add_student("Dapo")
    db.add_session(s.id, "n1", held_at=datetime(2026, 9, 1, 16), topics=["past perfect"], weak_spots=["since vs for"])
    db.add_session(s.id, "n2", held_at=datetime(2026, 9, 8, 16), topics=["Past Perfect", "reading"], weak_spots=["since vs for"])
    topics = {t.topic.lower(): t for t in db.topics_for(s.id)}
    assert topics["past perfect"].times_covered == 2
    assert topics["reading"].times_covered == 1
    weak = db.weak_spots_for(s.id)
    assert len(weak) == 1 and weak[0].times_seen == 2
    db.resolve_weak_spot(weak[0].id)
    assert db.weak_spots_for(s.id) == []
    assert [x.held_at.day for x in db.recent_sessions(s.id)] == [8, 1]


def test_promises_and_outbox(db):
    s = db.add_student("Ana")
    sess = db.add_session(s.id, "notes")
    p = db.add_promise(s.id, "tense worksheet", session_id=sess.id)
    assert [x.id for x in db.open_promises(s.id)] == [p.id]
    item = db.queue(s.id, "materials", "body", session_id=sess.id, material_ids=[1, 2])
    assert item.status == "pending" and item.material_ids == [1, 2]
    assert [i.id for i in db.list_outbox()] == [item.id]
    db.set_outbox_status(item.id, "sent", via="stdout")
    assert db.list_outbox() == []
    assert db.get_outbox_item(item.id).sent_via == "stdout"
    assert db.fulfil_promises_for_session(sess.id) == 1
    assert db.open_promises(s.id) == []


def test_material_upsert_keeps_share_link(db):
    m = db.upsert_material(title="A", location="drive-id", source="drive", topics=["x"])
    db.set_share_link(m.id, "https://link")
    m2 = db.upsert_material(title="A2", location="drive-id", source="drive", topics=["x", "y"])
    assert m2.id == m.id and m2.share_link == "https://link" and m2.title == "A2"
    assert [x.id for x in db.list_materials(board="AQA")] == [m.id]  # untagged board matches any


def test_slots_upsert_by_uid(db):
    a = db.upsert_slot(title="Lesson: Dapo", starts_at=datetime(2026, 9, 19, 16), ends_at=datetime(2026, 9, 19, 17), uid="u1")
    b = db.upsert_slot(title="Lesson: Dapo (moved)", starts_at=datetime(2026, 9, 19, 17), ends_at=datetime(2026, 9, 19, 18), uid="u1")
    assert a.id == b.id
    assert [s.title for s in db.slots_on(datetime(2026, 9, 19))] == ["Lesson: Dapo (moved)"]

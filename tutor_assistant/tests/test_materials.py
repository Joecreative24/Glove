from tutor_assistant.materials import candidate_materials, index_local_folder, parse_material_name
from tutor_assistant.models import SessionClassification


def test_parse_material_name():
    p = parse_material_name("AQA - past perfect, since vs for - Tense worksheet")
    assert (p.board, p.topics, p.title) == ("AQA", ["past perfect", "since vs for"], "Tense worksheet")
    p = parse_material_name("just a title")
    assert (p.board, p.topics, p.title) == (None, [], "just a title")


def test_index_folder_and_candidates(db, materials_dir):
    items = index_local_folder(db, materials_dir)
    assert len(items) == 4
    by_title = {m.title: m for m in items}
    assert by_title["Adverbials"].topics == ["fronted adverbials"] and by_title["Adverbials"].board == "AQA"
    assert by_title["Tense worksheet"].share_link.startswith("file://")
    # re-index is idempotent
    assert len(index_local_folder(db, materials_dir)) == 4 and len(db.list_materials()) == 4

    s = db.add_student("Dapo", board="AQA")
    c = SessionClassification(student_name="Dapo", topics_covered=["past perfect"], weak_spots=["since vs for"], summary="x")
    cands = candidate_materials(db, s, c)
    assert [m.title for m in cands] == ["Tense worksheet"]  # Edexcel sheet excluded by board, others no overlap

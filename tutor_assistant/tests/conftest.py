import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tutor_assistant.db import Database  # noqa: E402


@pytest.fixture
def db(tmp_path):
    d = Database(tmp_path / "t.db")
    yield d
    d.close()


@pytest.fixture
def materials_dir(tmp_path):
    folder = tmp_path / "materials"
    folder.mkdir()
    (folder / "AQA - past perfect, since vs for - Tense worksheet.html").write_text("<p>x</p>")
    (folder / "AQA - reading comprehension - Reading pack.docx").write_bytes(b"x")
    (folder / "Edexcel - quadratics - Quadratics sheet.pdf").write_bytes(b"x")
    (folder / "untagged.html").write_text("<p>y</p>")
    (folder / "tags.json").write_text('{"untagged.html": {"board": "AQA", "topics": ["fronted adverbials"], "title": "Adverbials"}}')
    return folder

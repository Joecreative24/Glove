from tutor_assistant.cli import main


def run(capsys, tmp_path, *argv):
    rc = main(["--db", str(tmp_path / "cli.db"), "--fake", *argv])
    assert rc == 0
    return capsys.readouterr().out


def test_cli_end_to_end(capsys, tmp_path, materials_dir):
    run(capsys, tmp_path, "init")
    run(capsys, tmp_path, "voice", "set", "Warm and brisk.")
    assert "Warm and brisk." in run(capsys, tmp_path, "voice", "show")
    run(capsys, tmp_path, "student", "add", "Dapo", "--board", "AQA", "--level", "GCSE")
    run(capsys, tmp_path, "materials", "index", str(materials_dir))
    out = run(capsys, tmp_path, "log", "Dapo — past perfect, still confuses since/for, did well on reading comp")
    assert "Queued feedback draft [1]" in out and "Queued materials message [2]" in out
    out = run(capsys, tmp_path, "queue", "list")
    assert "[1] feedback" in out and "[2] materials" in out
    out = run(capsys, tmp_path, "queue", "send", "1", "--via", "stdout")
    assert "Hi Dapo" in out and "marked sent via stdout" in out
    out = run(capsys, tmp_path, "queue", "send", "2", "--via", "file", "--file", str(tmp_path / "out.txt"))
    assert (tmp_path / "out.txt").read_text().count("Tense worksheet") == 1
    out = run(capsys, tmp_path, "student", "show", "dapo")
    assert "past perfect" in out and "Weak spots" in out
    run(capsys, tmp_path, "schedule", "add", "Dapo", "2099-01-01T16:00")
    out = run(capsys, tmp_path, "brief", "--date", "2099-01-01", "--raw")
    assert "Lesson: Dapo" in out
    run(capsys, tmp_path, "schedule", "export", str(tmp_path / "cal.ics"), "--days", "40000")
    assert "BEGIN:VALARM" in (tmp_path / "cal.ics").read_text()

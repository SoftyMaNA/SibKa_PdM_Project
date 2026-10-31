import json
from pathlib import Path
import subprocess
import sys

import pytest

from main import main, start_system


ROOT = Path(__file__).resolve().parents[1]


def test_start_system_returns_diagnostic_result():
    assert start_system() == {"status": "normal", "alerts": []}
    assert start_system({"temperature": 110, "vibration": 1, "pressure": 10})["status"] == "critical"


def test_no_argument_cli_produces_json(capsys):
    assert main([]) == 0
    output = capsys.readouterr()
    assert json.loads(output.out) == {"status": "normal", "alerts": []}
    assert output.err == ""


def test_cli_accepts_file_and_reports_critical_status(tmp_path, capsys):
    file = tmp_path / "показания.json"
    file.write_text('{"temperature":105,"vibration":1,"pressure":10}', encoding="utf-8")
    assert main(["--input", str(file)]) == 0
    result = json.loads(capsys.readouterr().out)
    assert result["status"] == "critical"
    assert result["alerts"][0]["parameter"] == "temperature"


@pytest.mark.parametrize("body", ["not JSON", "null", "{}", "[]", '"text"',
    '{"temperature":85,"vibration":-1,"pressure":10}',
    '{"temperature":NaN,"vibration":1,"pressure":10}'])
def test_cli_invalid_input_reports_error_and_no_success_json(body, tmp_path, capsys):
    file = tmp_path / "input.json"
    file.write_text(body, encoding="utf-8")
    assert main(["--input", str(file)]) == 2
    output = capsys.readouterr()
    assert output.out == ""
    assert "Ошибка обработки телеметрии" in output.err


def test_cli_missing_file_is_handled(tmp_path, capsys):
    assert main(["--input", str(tmp_path / "missing.json")]) == 2
    assert capsys.readouterr().out == ""


def test_cli_invalid_utf8_is_handled(tmp_path, capsys):
    file = tmp_path / "input.json"
    file.write_bytes(b"\xff\xfe")
    assert main(["--input", str(file)]) == 2
    assert capsys.readouterr().out == ""


@pytest.mark.parametrize("script", ["main.py", "telemetry.py"])
def test_programs_run_as_real_processes(script):
    result = subprocess.run([sys.executable, str(ROOT / script)], cwd=ROOT,
                            capture_output=True, text=True, timeout=10)
    assert result.returncode == 0
    assert result.stderr == ""
    if script == "main.py":
        assert json.loads(result.stdout)["status"] == "normal"
    else:
        assert "Собраны данные" in result.stdout


def test_cli_exit_status_is_propagated_to_operating_system(tmp_path):
    file = tmp_path / "bad.json"
    file.write_text("{}", encoding="utf-8")
    result = subprocess.run([sys.executable, str(ROOT / "main.py"), "--input", str(file)],
                            capture_output=True, text=True, timeout=10)
    assert result.returncode == 2
    assert result.stdout == ""
    assert "Ошибка" in result.stderr


def test_import_does_not_start_program_or_print_messages():
    result = subprocess.run([sys.executable, "-c", "import main; import telemetry; import diagnostics"],
                            cwd=ROOT, capture_output=True, text=True, timeout=10)
    assert result.returncode == 0
    assert result.stdout == result.stderr == ""

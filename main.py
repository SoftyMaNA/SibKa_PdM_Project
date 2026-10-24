"""Командный запуск приёма телеметрии и пороговой диагностики."""

import argparse
import json
import sys
from pathlib import Path

from diagnostics import assess_condition
from telemetry import TelemetryError, collect_data


def start_system(readings=None):
    """Выполнить обработку и вернуть результат вызывающему коду."""
    return assess_condition(collect_data(readings))


def main(argv=None):
    parser = argparse.ArgumentParser(description="Контроль состояния карьерной техники")
    parser.add_argument("--input", type=Path, help="JSON-файл с показаниями")
    args = parser.parse_args(argv)
    try:
        readings = None
        if args.input is not None:
            readings = json.loads(args.input.read_text(encoding="utf-8"))
            # JSON null в файле — ошибка входа, а не запрос встроенных данных.
            if readings is None:
                raise TelemetryError("Файл не должен содержать null.")
        result = start_system(readings)
    except (OSError, UnicodeError, ValueError) as exc:
        print(f"Ошибка обработки телеметрии: {exc}", file=sys.stderr)
        return 2
    print(json.dumps(result, ensure_ascii=False, allow_nan=False))
    # Предупреждение — корректный результат диагностики, а не ошибка программы.
    return 0


if __name__ == "__main__":
    sys.exit(main())

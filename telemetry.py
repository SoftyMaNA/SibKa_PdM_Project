"""Приём и проверка набора показаний карьерной техники."""

from collections.abc import Mapping
from math import isfinite


class TelemetryError(ValueError):
    """Пакет не соответствует формату телеметрии."""


PARAMETERS = ("temperature", "vibration", "pressure")


def validate_data(data):
    """Проверить пакет и вернуть независимую копию с числовыми значениями.

    temperature — градусы Цельсия, vibration — мм/с, pressure — бар.
    Отрицательная температура допустима; вибрация и давление неотрицательны.
    Дополнительные поля запрещены, чтобы обнаруживать опечатки в именах.
    """
    if not isinstance(data, Mapping):
        raise TelemetryError("Пакет телеметрии должен быть словарём.")
    missing = set(PARAMETERS) - set(data)
    extra = set(data) - set(PARAMETERS)
    if missing:
        raise TelemetryError("Отсутствуют параметры: " + ", ".join(sorted(missing)))
    if extra:
        raise TelemetryError("Неизвестные параметры: " + ", ".join(sorted(map(str, extra))))
    result = {}
    for name in PARAMETERS:
        value = data[name]
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise TelemetryError(f"Параметр {name} должен быть числом.")
        try:
            value = float(value)
        except (OverflowError, ValueError) as exc:
            raise TelemetryError(f"Параметр {name} выходит за числовой диапазон.") from exc
        if not isfinite(value):
            raise TelemetryError(f"Параметр {name} должен быть конечным числом.")
        if name != "temperature" and value < 0:
            raise TelemetryError(f"Параметр {name} не может быть отрицательным.")
        result[name] = value
    return result


def collect_data(readings=None):
    """Принять показания; без аргумента вернуть встроенный набор данных.

    Встроенные значения формируются программой, подключения к датчикам нет.
    Нулевые и пустые входы не заменяются встроенными значениями.
    """
    if readings is None:
        readings = {"temperature": 85, "vibration": 1.2, "pressure": 10}
    return validate_data(readings)


if __name__ == "__main__":
    print(f"Собраны данные: {collect_data()}")

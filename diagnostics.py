"""Пороговая диагностика по профилю контролируемого узла."""

from collections.abc import Mapping
from dataclasses import dataclass
from math import isfinite

from telemetry import PARAMETERS, validate_data


@dataclass(frozen=True)
class Thresholds:
    """Верхние границы предупреждения и критического состояния."""

    warning: float
    critical: float

    def __post_init__(self):
        for value in (self.warning, self.critical):
            if isinstance(value, bool) or not isinstance(value, (int, float)):
                raise ValueError("Пороги должны быть числами.")
            try:
                valid = isfinite(value)
            except OverflowError:
                valid = False
            if not valid:
                raise ValueError("Пороги должны быть конечными числами.")
        if self.warning < 0 or self.warning >= self.critical:
            raise ValueError("Требуется 0 <= warning < critical.")


# Начальный профиль приложения; перед эксплуатацией задаётся для узла машины.
# Это верхние пороги, а не регламенты производителей и не прогноз ресурса.
DEFAULT_THRESHOLDS = {
    "temperature": Thresholds(90, 105),
    "vibration": Thresholds(4.5, 7.1),
    "pressure": Thresholds(16, 20),
}


def assess_condition(readings, thresholds=None):
    """Вернуть статус и причины; критический статус имеет высший приоритет.

    Равенство порогу включает соответствующий уровень. Некорректные данные
    вызывают исключение и никогда не превращаются в статус normal.
    """
    data = validate_data(readings)
    profile = DEFAULT_THRESHOLDS if thresholds is None else thresholds
    if not isinstance(profile, Mapping) or set(profile) != set(PARAMETERS):
        raise ValueError("Профиль должен содержать пороги для всех трёх параметров.")
    if any(not isinstance(profile[name], Thresholds) for name in PARAMETERS):
        raise ValueError("Профиль должен содержать объекты Thresholds.")
    alerts = []
    for name in PARAMETERS:
        limits = profile[name]
        value = data[name]
        if value >= limits.critical:
            severity = "critical"
            threshold = limits.critical
        elif value >= limits.warning:
            severity = "warning"
            threshold = limits.warning
        else:
            continue
        alerts.append({"parameter": name, "value": value,
                       "severity": severity, "threshold": threshold})
    status = "normal"
    if alerts:
        status = "critical" if any(a["severity"] == "critical" for a in alerts) else "warning"
    return {"status": status, "alerts": alerts}

import pytest

from diagnostics import Thresholds, assess_condition
from telemetry import TelemetryError


BASE = {"temperature": 20, "vibration": 0, "pressure": 0}
# Independent expectations express the agreed initial profile and its boundaries.
CASES = [
    ("temperature", 89.99, "normal"), ("temperature", 90, "warning"),
    ("temperature", 104.99, "warning"), ("temperature", 105, "critical"),
    ("temperature", 105.01, "critical"),
    ("vibration", 4.49, "normal"), ("vibration", 4.5, "warning"),
    ("vibration", 7.09, "warning"), ("vibration", 7.1, "critical"),
    ("vibration", 7.11, "critical"),
    ("pressure", 15.99, "normal"), ("pressure", 16, "warning"),
    ("pressure", 19.99, "warning"), ("pressure", 20, "critical"),
    ("pressure", 20.01, "critical"),
]


@pytest.mark.parametrize("parameter,value,expected", CASES)
def test_threshold_boundaries(parameter, value, expected):
    result = assess_condition({**BASE, parameter: value})
    assert result["status"] == expected
    if expected == "normal":
        assert result["alerts"] == []
    else:
        assert len(result["alerts"]) == 1
        assert result["alerts"][0]["parameter"] == parameter
        assert result["alerts"][0]["severity"] == expected
        assert result["alerts"][0]["value"] == value


def test_records_actionable_reason_and_threshold():
    assert assess_condition({**BASE, "temperature": 105}) == {
        "status": "critical", "alerts": [{"parameter": "temperature", "value": 105.0,
        "severity": "critical", "threshold": 105}]}


def test_critical_takes_precedence_and_retains_all_deviations():
    result = assess_condition({"temperature": 95, "vibration": 8, "pressure": 17})
    assert result["status"] == "critical"
    assert [(a["parameter"], a["severity"]) for a in result["alerts"]] == [
        ("temperature", "warning"), ("vibration", "critical"), ("pressure", "warning")]


def test_recovers_to_normal_on_next_valid_packet_without_old_alerts():
    previous = assess_condition({**BASE, "temperature": 120})
    assert assess_condition(BASE) == {"status": "normal", "alerts": []}
    assert previous["status"] == "critical"


def test_invalid_packet_is_never_classified_as_normal():
    with pytest.raises(TelemetryError):
        assess_condition({**BASE, "pressure": float("nan")})


def test_does_not_mutate_readings_or_custom_profile():
    readings = dict(BASE)
    profile = {name: Thresholds(10, 20) for name in BASE}
    expected = dict(profile)
    assess_condition(readings, profile)
    assert readings == BASE
    assert profile == expected


def test_custom_profile_replaces_initial_thresholds():
    profile = {name: Thresholds(100, 200) for name in BASE}
    assert assess_condition({**BASE, "temperature": 105}, profile)["status"] == "warning"


@pytest.mark.parametrize("warning,critical", [(-1, 10), (10, 10), (20, 10),
    (float("nan"), 10), (10, float("inf")), (True, 10), ("5", 10), (10, 10**400)])
def test_rejects_invalid_threshold_configuration(warning, critical):
    with pytest.raises(ValueError):
        Thresholds(warning, critical)


@pytest.mark.parametrize("profile", [{}, [], {"temperature": Thresholds(1, 2)},
    {"temperature": 10, "vibration": 10, "pressure": 10}])
def test_rejects_incomplete_or_malformed_profile(profile):
    with pytest.raises(ValueError):
        assess_condition(BASE, profile)

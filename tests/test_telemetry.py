import math

import pytest

from telemetry import TelemetryError, collect_data, validate_data


BASE = {"temperature": 85, "vibration": 1.2, "pressure": 10}


def test_collects_existing_builtin_values():
    assert collect_data() == BASE


def test_accepts_external_readings_without_replacing_them():
    values = {"temperature": 25, "vibration": 0, "pressure": 0}
    assert collect_data(values) == values


def test_returned_data_does_not_alias_input_or_next_collection():
    source = dict(BASE)
    result = collect_data(source)
    result["temperature"] = 999
    assert source == BASE
    first = collect_data()
    first["pressure"] = 0
    assert collect_data()["pressure"] == 10


@pytest.mark.parametrize("name", BASE)
def test_requires_each_parameter(name):
    data = dict(BASE)
    del data[name]
    with pytest.raises(TelemetryError, match=name):
        collect_data(data)


@pytest.mark.parametrize("value", [None, [], "85", 85, True])
def test_rejects_non_mapping_packet(value):
    with pytest.raises(TelemetryError):
        validate_data(value)


def test_empty_packet_is_not_replaced_by_builtin_values():
    with pytest.raises(TelemetryError, match="Отсутствуют"):
        collect_data({})


@pytest.mark.parametrize("name", BASE)
@pytest.mark.parametrize("value", [True, False, "12", None, [], {}, math.nan, math.inf, -math.inf, 10**400])
def test_rejects_invalid_measurement_types_and_nonfinite_numbers(name, value):
    with pytest.raises(TelemetryError, match=name):
        collect_data({**BASE, name: value})


@pytest.mark.parametrize("name", ["pressure", "vibration"])
def test_rejects_negative_magnitude(name):
    with pytest.raises(TelemetryError, match=name):
        collect_data({**BASE, name: -0.01})


def test_accepts_negative_celsius_temperature():
    assert collect_data({**BASE, "temperature": -35})["temperature"] == -35


def test_rejects_misspelled_extra_parameter():
    with pytest.raises(TelemetryError, match="temperatur"):
        collect_data({**BASE, "temperatur": 90})

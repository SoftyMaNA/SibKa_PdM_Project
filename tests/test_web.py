"""Две основные проверки диагностики для лабораторной 7."""
import pytest
from pdm.services import aggregate, sensor_condition


@pytest.mark.parametrize('value,quality,warning,critical,expected', [
    (105,'valid',90,105,'critical'),
    (90,'valid',90,105,'warning'),
    (7.1,'valid',4.5,7.1,'critical'),
    (85,'valid',80,90,'warning'),
])
def test_sensor_threshold_boundary(value,quality,warning,critical,expected):
    assert sensor_condition(value,quality,warning,critical)==expected


@pytest.mark.parametrize('value,quality,expected', [
    (85,'valid','normal'),(None,None,'unknown'),(105,'invalid','unknown'),
    (85,'suspect','unknown'),(float('nan'),'valid','unknown'),
])
def test_valid_normal_and_missing_data(value,quality,expected):
    assert sensor_condition(value,quality,90,105)==expected
    assert aggregate(['normal','unknown'])=='unknown'
    assert aggregate(['unknown','critical'])=='critical'

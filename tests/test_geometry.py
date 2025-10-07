"""Tests for :mod:`disclib.geometry`."""

import math

import pytest

from disclib.geometry import circle_area, circle_circumference, slice_area


@pytest.mark.parametrize(
    "radius, expected",
    [
        (0, 0.0),
        (1, math.pi),
        (2.5, math.pi * 2.5**2),
    ],
)
def test_circle_area(radius, expected):
    assert circle_area(radius) == pytest.approx(expected)


@pytest.mark.parametrize("radius", [-1, -0.01])
def test_circle_area_rejects_negative_radius(radius):
    with pytest.raises(ValueError, match="cannot be negative"):
        circle_area(radius)


@pytest.mark.parametrize(
    "radius, expected",
    [
        (0, 0.0),
        (1, 2 * math.pi),
        (4.2, 2 * math.pi * 4.2),
    ],
)
def test_circle_circumference(radius, expected):
    assert circle_circumference(radius) == pytest.approx(expected)


@pytest.mark.parametrize("radius", [-10, -1])
def test_circle_circumference_rejects_negative_radius(radius):
    with pytest.raises(ValueError, match="cannot be negative"):
        circle_circumference(radius)


@pytest.mark.parametrize(
    "radius, angle, expected",
    [
        (10, 90, math.pi * 10**2 / 4),
        (5, 45, math.pi * 25 / 8),
    ],
)
def test_slice_area(radius, angle, expected):
    assert slice_area(radius, angle) == pytest.approx(expected)


@pytest.mark.parametrize("angle", [0, -10, 361])
def test_slice_area_rejects_invalid_angles(angle):
    with pytest.raises(ValueError):
        slice_area(3, angle)


def test_slice_area_rejects_negative_radius():
    with pytest.raises(ValueError):
        slice_area(-1, 30)

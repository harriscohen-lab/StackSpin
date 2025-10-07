"""Geometry helpers for circular discs."""

from __future__ import annotations

import math


def _validate_radius(radius: float) -> float:
    """Return the radius if valid or raise ``ValueError``.

    The original implementation silently accepted negative radii, which
    produced mathematically incorrect areas and circumferences.  The helper
    centralises the validation so that every public API only works with
    physical discs (``radius >= 0``).
    """

    try:
        radius_value = float(radius)
    except (TypeError, ValueError) as exc:  # pragma: no cover - defensive
        raise TypeError("radius must be a real number") from exc

    if math.isnan(radius_value) or math.isinf(radius_value):
        raise ValueError("radius must be a finite number")

    if radius_value < 0:
        raise ValueError("radius cannot be negative")

    return radius_value


def circle_area(radius: float) -> float:
    """Return the area of a circle with the provided ``radius``.

    Parameters
    ----------
    radius:
        The radius of the circle.  Negative radii are not allowed and will
        raise :class:`ValueError`.
    """

    valid_radius = _validate_radius(radius)
    return math.pi * valid_radius**2


def circle_circumference(radius: float) -> float:
    """Return the circumference of a circle with the provided ``radius``."""

    valid_radius = _validate_radius(radius)
    return 2 * math.pi * valid_radius


def slice_area(radius: float, angle_degrees: float) -> float:
    """Return the area of a circular slice.

    ``angle_degrees`` denotes the angle of the slice in degrees.  The
    implementation validates both parameters to guard against invalid inputs
    that previously slipped through and produced misleading results.
    """

    valid_radius = _validate_radius(radius)
    try:
        angle_value = float(angle_degrees)
    except (TypeError, ValueError) as exc:  # pragma: no cover - defensive
        raise TypeError("angle_degrees must be a real number") from exc

    if math.isnan(angle_value) or math.isinf(angle_value):
        raise ValueError("angle_degrees must be a finite number")
    if not 0 < angle_value <= 360:
        raise ValueError("angle_degrees must be in the range (0, 360]")

    return (angle_value / 360.0) * circle_area(valid_radius)

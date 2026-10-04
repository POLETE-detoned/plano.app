"""Lectura del JSON `CapturedRoom` que RoomPlan produce con `JSONEncoder`.

Solo se usan los campos estables entre iOS 16 y 26: `identifier`, `dimensions`,
`transform` y, si existe, `parentIdentifier` (iOS 17+). Todo lo demás se ignora.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Literal

import numpy as np

from .package import PlanoFormatError, column_major

SurfaceKind = Literal["wall", "door", "window", "opening"]

_SECTIONS: dict[str, SurfaceKind] = {
    "walls": "wall",
    "doors": "door",
    "windows": "window",
    "openings": "opening",
}


@dataclass(frozen=True)
class Surface:
    kind: SurfaceKind
    id: str
    dimensions: np.ndarray  # (ancho, alto, fondo) en metros
    transform: np.ndarray  # 4×4 local → mundo
    parent_id: str | None = None
    is_open: bool | None = None  # solo puertas

    @property
    def center(self) -> np.ndarray:
        return self.transform[:3, 3]

    @property
    def x_axis(self) -> np.ndarray:
        return self.transform[:3, 0]


@dataclass(frozen=True)
class CapturedRoom:
    id: str
    walls: list[Surface]
    openings: list[Surface]  # puertas, ventanas y huecos


def _uuid(value: Any) -> str | None:
    if value is None:
        return None
    if isinstance(value, dict):  # algunas versiones envuelven el UUID
        value = value.get("uuid") or value.get("uuidString") or next(iter(value.values()), None)
    return str(value).upper() if value else None


def _door_open(category: Any) -> bool | None:
    # La categoría se codifica como {"door": {"isOpen": true}} o {"wall": {}}.
    if isinstance(category, dict) and isinstance(category.get("door"), dict):
        val = category["door"].get("isOpen")
        return bool(val) if val is not None else None
    return None


def parse_surface(kind: SurfaceKind, raw: dict[str, Any]) -> Surface:
    try:
        dims = np.asarray(raw["dimensions"], dtype=float)
        transform = column_major(raw["transform"], 4)
    except KeyError as exc:
        raise PlanoFormatError(f"superficie sin campo {exc}") from None
    if dims.shape != (3,):
        raise PlanoFormatError(f"dimensions con forma inesperada {dims.shape}")
    return Surface(
        kind=kind,
        id=_uuid(raw.get("identifier")) or "",
        dimensions=dims,
        transform=transform,
        parent_id=_uuid(raw.get("parentIdentifier")),
        is_open=_door_open(raw.get("category")) if kind == "door" else None,
    )


def parse_captured_room(raw: dict[str, Any], room_id: str = "", alignment: np.ndarray | None = None) -> CapturedRoom:
    """Convierte el JSON de RoomPlan. `alignment` (4×4) lleva la estancia al mundo del proyecto."""
    surfaces: dict[str, list[Surface]] = {}
    for key, kind in _SECTIONS.items():
        surfaces[key] = [parse_surface(kind, s) for s in raw.get(key, [])]

    if alignment is not None:
        for key, items in surfaces.items():
            surfaces[key] = [
                Surface(s.kind, s.id, s.dimensions, alignment @ s.transform, s.parent_id, s.is_open) for s in items
            ]

    return CapturedRoom(
        id=room_id or _uuid(raw.get("identifier")) or "",
        walls=surfaces["walls"],
        openings=surfaces["doors"] + surfaces["windows"] + surfaces["openings"],
    )

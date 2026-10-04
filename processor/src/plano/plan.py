"""Planta 2D a partir de un `CapturedRoom`: muros con grosor, huecos, esquinas y ortogonalización.

Convenciones: mundo ARKit (Y arriba) → planta `X = x`, `Y = −z`. Cada muro se
representa por su **cara interior** (la superficie que escanea RoomPlan) y el
grosor crece hacia fuera de la estancia.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

import numpy as np

from .roomplan import CapturedRoom, SurfaceKind

DEFAULT_WALL_THICKNESS = 0.10  # m, RoomPlan no mide el grosor
_MIN_THICKNESS = 0.03
_HOST_MAX_DISTANCE = 0.5  # m, distancia máxima hueco → muro cuando falta parentIdentifier


def to_plan(p3: np.ndarray) -> np.ndarray:
    return np.array([p3[0], -p3[2]], dtype=float)


def _perp(v: np.ndarray) -> np.ndarray:
    return np.array([-v[1], v[0]])


def _unit(v: np.ndarray) -> np.ndarray:
    n = float(np.linalg.norm(v))
    return v / n if n > 1e-12 else v


def _rotate(p: np.ndarray, center: np.ndarray, angle: float) -> np.ndarray:
    c, s = math.cos(angle), math.sin(angle)
    d = p - center
    return center + np.array([c * d[0] - s * d[1], s * d[0] + c * d[1]])


def _line_intersection(p: np.ndarray, d: np.ndarray, q: np.ndarray, e: np.ndarray) -> np.ndarray | None:
    den = d[0] * e[1] - d[1] * e[0]
    if abs(den) < 1e-9:
        return None
    w = q - p
    t = (w[0] * e[1] - w[1] * e[0]) / den
    return p + t * d


def _segment_distance(p: np.ndarray, a: np.ndarray, b: np.ndarray) -> float:
    ab = b - a
    t = float(np.clip(np.dot(p - a, ab) / max(np.dot(ab, ab), 1e-12), 0.0, 1.0))
    return float(np.linalg.norm(p - (a + t * ab)))


@dataclass
class Wall2D:
    id: str
    p0: np.ndarray  # cara interior, inicio
    p1: np.ndarray  # cara interior, fin
    height: float
    thickness: float
    base: float  # cota Y (mundo) del arranque del muro
    normal: np.ndarray = field(default_factory=lambda: np.zeros(2))  # unitario, hacia fuera
    outer0: np.ndarray | None = None  # esquina exterior inglete en p0
    outer1: np.ndarray | None = None

    @property
    def vector(self) -> np.ndarray:
        return self.p1 - self.p0

    @property
    def length(self) -> float:
        return float(np.linalg.norm(self.vector))

    @property
    def direction(self) -> np.ndarray:
        return _unit(self.vector)

    @property
    def midpoint(self) -> np.ndarray:
        return (self.p0 + self.p1) / 2

    @property
    def angle(self) -> float:
        v = self.vector
        return math.atan2(v[1], v[0])

    def point(self, s: float) -> np.ndarray:
        return self.p0 + self.direction * s

    def param(self, p: np.ndarray) -> float:
        return float(np.dot(p - self.p0, self.direction))

    def outer_start(self) -> np.ndarray:
        return self.outer0 if self.outer0 is not None else self.p0 + self.normal * self.thickness

    def outer_end(self) -> np.ndarray:
        return self.outer1 if self.outer1 is not None else self.p1 + self.normal * self.thickness


@dataclass
class Opening2D:
    id: str
    kind: SurfaceKind  # door | window | opening
    center: np.ndarray
    width: float
    height: float
    sill: float  # altura del alféizar / umbral sobre el arranque del muro
    wall_id: str | None
    is_open: bool | None = None


@dataclass
class FloorPlan:
    room_id: str
    name: str
    walls: list[Wall2D]
    openings: list[Opening2D]
    warnings: list[str] = field(default_factory=list)

    def wall(self, wall_id: str | None) -> Wall2D | None:
        return next((w for w in self.walls if w.id == wall_id), None)

    def openings_on(self, wall: Wall2D) -> list[Opening2D]:
        return [o for o in self.openings if o.wall_id == wall.id]

    def gaps(self, wall: Wall2D) -> list[tuple[float, float, Opening2D]]:
        """Intervalos [a, b] sobre la cara interior ocupados por huecos, ordenados."""
        out = []
        for o in self.openings_on(wall):
            s = wall.param(o.center)
            a, b = max(0.0, s - o.width / 2), min(wall.length, s + o.width / 2)
            if b - a > 1e-3:
                out.append((a, b, o))
        return sorted(out, key=lambda g: g[0])

    def solid_intervals(self, wall: Wall2D) -> list[tuple[float, float]]:
        """Tramos macizos del muro (complemento de los huecos)."""
        out, cursor = [], 0.0
        for a, b, _ in self.gaps(wall):
            if a > cursor + 1e-3:
                out.append((cursor, a))
            cursor = max(cursor, b)
        if wall.length > cursor + 1e-3:
            out.append((cursor, wall.length))
        return out

    def bounds(self) -> tuple[np.ndarray, np.ndarray]:
        pts = np.array([p for w in self.walls for p in (w.p0, w.p1, w.outer_start(), w.outer_end())])
        return pts.min(axis=0), pts.max(axis=0)


# --- construcción ----------------------------------------------------------


def _is_inside(q: np.ndarray, walls: list[Wall2D]) -> bool:
    """Paridad de cruces de un rayo desde q (muros como contorno de la estancia)."""
    ray = _unit(np.array([0.6123, 0.7906]))  # dirección poco probable en muros reales
    crossings = 0
    for w in walls:
        a, b = w.p0, w.p1
        e = b - a
        den = ray[0] * e[1] - ray[1] * e[0]
        if abs(den) < 1e-12:
            continue
        d = a - q
        t = (d[0] * e[1] - d[1] * e[0]) / den  # a lo largo del rayo
        u = (d[0] * ray[1] - d[1] * ray[0]) / den  # a lo largo del muro
        if t > 0 and 0 <= u <= 1:
            crossings += 1
    return crossings % 2 == 1


def _orient_normals(walls: list[Wall2D]) -> None:
    if not walls:
        return
    centroid = np.mean([w.midpoint for w in walls], axis=0)
    for w in walls:
        n = _perp(w.direction)
        probe = w.midpoint + n * 0.05
        if len(walls) >= 3:
            inward = _is_inside(probe, walls)
        else:
            inward = float(np.dot(n, centroid - w.midpoint)) > 0
        w.normal = -n if inward else n


def build_plan(
    room: CapturedRoom,
    name: str = "",
    wall_thickness: float = DEFAULT_WALL_THICKNESS,
) -> FloorPlan:
    walls: list[Wall2D] = []
    for s in room.walls:
        length, height, depth = (float(v) for v in s.dimensions)
        x = s.x_axis / max(np.linalg.norm(s.x_axis), 1e-12)
        c = s.center
        walls.append(
            Wall2D(
                id=s.id,
                p0=to_plan(c - x * length / 2),
                p1=to_plan(c + x * length / 2),
                height=height,
                thickness=depth if depth >= _MIN_THICKNESS else wall_thickness,
                base=float(c[1] - height / 2),
            )
        )
    _orient_normals(walls)

    plan = FloorPlan(room_id=room.id, name=name or room.id[:8], walls=walls, openings=[])
    by_id = {w.id: w for w in walls}
    for s in room.openings:
        width, height, _ = (float(v) for v in s.dimensions)
        c2 = to_plan(s.center)
        host = by_id.get(s.parent_id) if s.parent_id else None
        if host is None:
            host = _nearest_wall(c2, s.x_axis, walls)
        if host is None:
            plan.warnings.append(f"{s.kind} {s.id[:8]} sin muro anfitrión; se omite")
            continue
        plan.openings.append(
            Opening2D(
                id=s.id,
                kind=s.kind,
                center=c2,
                width=width,
                height=height,
                sill=float(s.center[1] - height / 2 - host.base),
                wall_id=host.id,
                is_open=s.is_open,
            )
        )
    return plan


def _nearest_wall(c2: np.ndarray, x_axis3: np.ndarray, walls: list[Wall2D]) -> Wall2D | None:
    d_open = _unit(to_plan(x_axis3))
    best, best_dist = None, _HOST_MAX_DISTANCE
    for w in walls:
        if abs(float(np.dot(d_open, w.direction))) < math.cos(math.radians(20)):
            continue  # no es paralelo al muro
        dist = _segment_distance(c2, w.p0, w.p1)
        if dist < best_dist:
            best, best_dist = w, dist
    return best


# --- regularización -------------------------------------------------------


def dominant_angle(walls: list[Wall2D]) -> float:
    """Dirección dominante (módulo 90°) ponderada por longitud, en radianes."""
    sx = sum(w.length * math.sin(4 * w.angle) for w in walls)
    cx = sum(w.length * math.cos(4 * w.angle) for w in walls)
    return math.atan2(sx, cx) / 4


def orthogonalize(plan: FloorPlan, tolerance_deg: float = 3.0) -> int:
    """Gira a múltiplos de 90° (respecto a la dirección dominante) los muros que se
    desvían menos de `tolerance_deg`. Devuelve cuántos muros se han corregido.

    Versión geométrica; la de la semana 5-6 usará puntos de fuga en las fotos.
    """
    if not plan.walls:
        return 0
    phi = dominant_angle(plan.walls)
    tol = math.radians(tolerance_deg)
    changed = 0
    for w in plan.walls:
        quarter = math.pi / 2
        target = phi + round((w.angle - phi) / quarter) * quarter
        delta = target - w.angle
        if abs(delta) < 1e-9 or abs(delta) > tol:
            continue
        mid = w.midpoint
        w.p0, w.p1 = _rotate(w.p0, mid, delta), _rotate(w.p1, mid, delta)
        w.normal = _rotate(w.normal, np.zeros(2), delta)
        for o in plan.openings_on(w):
            o.center = _rotate(o.center, mid, delta)
        changed += 1
    return changed


def align_to_axes(plans: list[FloorPlan]) -> float:
    """Gira todas las plantas (alrededor del origen) para que la dirección dominante
    quede horizontal. Devuelve el giro aplicado en grados."""
    walls = [w for p in plans for w in p.walls]
    if not walls:
        return 0.0
    delta = -dominant_angle(walls)
    origin = np.zeros(2)
    for plan in plans:
        for w in plan.walls:
            w.p0, w.p1 = _rotate(w.p0, origin, delta), _rotate(w.p1, origin, delta)
            w.normal = _rotate(w.normal, origin, delta)
            if w.outer0 is not None:
                w.outer0 = _rotate(w.outer0, origin, delta)
            if w.outer1 is not None:
                w.outer1 = _rotate(w.outer1, origin, delta)
        for o in plan.openings:
            o.center = _rotate(o.center, origin, delta)
    return math.degrees(delta)


def join_corners(plan: FloorPlan, join_distance: float = 0.30, min_angle_deg: float = 20.0) -> int:
    """Une extremos de muros cercanos en su intersección y calcula el inglete exterior.
    Devuelve el número de uniones."""
    ends = [(i, e) for i in range(len(plan.walls)) for e in (0, 1)]

    def pt(i: int, e: int) -> np.ndarray:
        w = plan.walls[i]
        return w.p0 if e == 0 else w.p1

    pairs = []
    for a in range(len(ends)):
        for b in range(a + 1, len(ends)):
            (i, ei), (j, ej) = ends[a], ends[b]
            if i == j:
                continue
            d = float(np.linalg.norm(pt(i, ei) - pt(j, ej)))
            if d <= join_distance:
                pairs.append((d, ends[a], ends[b]))
    pairs.sort(key=lambda p: p[0])

    used: set[tuple[int, int]] = set()
    joins = 0
    sin_min = math.sin(math.radians(min_angle_deg))
    for _, (i, ei), (j, ej) in pairs:
        if (i, ei) in used or (j, ej) in used:
            continue
        wi, wj = plan.walls[i], plan.walls[j]
        pi, pj = pt(i, ei), pt(j, ej)
        di, dj = wi.direction, wj.direction
        cross = abs(float(di[0] * dj[1] - di[1] * dj[0]))
        if cross < sin_min:
            # Casi colineales: cerrar la junta en el punto medio.
            x = (pi + pj) / 2
            outer = None
        else:
            x = _line_intersection(wi.p0, wi.direction, wj.p0, wj.direction)
            if x is None or np.linalg.norm(x - pi) > 2 * join_distance or np.linalg.norm(x - pj) > 2 * join_distance:
                continue
            outer = _line_intersection(
                wi.p0 + wi.normal * wi.thickness, wi.direction, wj.p0 + wj.normal * wj.thickness, wj.direction
            )
            if outer is not None and np.linalg.norm(outer - x) > 3 * max(wi.thickness, wj.thickness):
                outer = None
        for w, e in ((wi, ei), (wj, ej)):
            if e == 0:
                w.p0, w.outer0 = x.copy(), None if outer is None else outer.copy()
            else:
                w.p1, w.outer1 = x.copy(), None if outer is None else outer.copy()
        used.update({(i, ei), (j, ej)})
        joins += 1
    return joins

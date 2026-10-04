"""Exportación DXF (ezdxf) con capas MUROS, HUECOS, COTAS y TEXTOS, en metros."""

from __future__ import annotations

import math
from pathlib import Path

import ezdxf
import numpy as np
from ezdxf import units
from ezdxf.document import Drawing
from ezdxf.layouts import Modelspace

from .plan import FloorPlan, Opening2D, Wall2D

LAYER_WALLS = "MUROS"
LAYER_OPENINGS = "HUECOS"
LAYER_DIMS = "COTAS"
LAYER_TEXT = "TEXTOS"
DIMSTYLE = "PLANO"

_LAYERS = {
    LAYER_WALLS: {"color": 7, "lineweight": 50},
    LAYER_OPENINGS: {"color": 30, "lineweight": 25},  # naranja
    LAYER_DIMS: {"color": 8, "lineweight": 13},
    LAYER_TEXT: {"color": 7, "lineweight": 18},
}

DIM_OFFSET = 0.30  # m, separación de la línea de cota a la cara interior


def _xy(p: np.ndarray) -> tuple[float, float]:
    return float(p[0]), float(p[1])


def new_document() -> Drawing:
    doc = ezdxf.new("R2010", setup=True)
    doc.units = units.M
    doc.header["$MEASUREMENT"] = 1  # métrico
    doc.header["$LUNITS"] = 2  # decimal
    doc.header["$INSUNITS"] = units.M
    for name, attrs in _LAYERS.items():
        doc.layers.add(name, color=attrs["color"], lineweight=attrs["lineweight"])
    doc.dimstyles.new(
        DIMSTYLE,
        dxfattribs={
            "dimtxt": 0.08,
            "dimasz": 0.06,
            "dimblk": "ARCHTICK",
            "dimexo": 0.04,
            "dimexe": 0.04,
            "dimgap": 0.03,
            "dimdec": 2,
            "dimtad": 1,  # texto sobre la línea
            "dimzin": 0,
            "dimlunit": 2,
            "dimtxsty": "OpenSans",
        },
    )
    return doc


def _draw_wall(msp: Modelspace, plan: FloorPlan, wall: Wall2D) -> None:
    n, t, length = wall.normal, wall.thickness, wall.length
    for u, v in plan.solid_intervals(wall):
        inner_a, inner_b = wall.point(u), wall.point(v)
        outer_a = wall.outer_start() if u <= 1e-3 else inner_a + n * t
        outer_b = wall.outer_end() if v >= length - 1e-3 else inner_b + n * t
        msp.add_lwpolyline(
            [_xy(inner_a), _xy(inner_b), _xy(outer_b), _xy(outer_a)],
            close=True,
            dxfattribs={"layer": LAYER_WALLS},
        )


def _draw_opening(msp: Modelspace, wall: Wall2D, a: float, b: float, o: Opening2D) -> None:
    n, t, d = wall.normal, wall.thickness, wall.direction
    pa, pb = wall.point(a), wall.point(b)
    attrs = {"layer": LAYER_OPENINGS}

    if o.kind == "window":
        for k in (0.0, 0.5, 1.0):
            msp.add_line(_xy(pa + n * t * k), _xy(pb + n * t * k), dxfattribs=attrs)
    elif o.kind == "door":
        # Hoja abatiendo hacia el interior, bisagra en el extremo `a`.
        width = b - a
        inward = -n
        leaf_end = pa + inward * width
        msp.add_line(_xy(pa), _xy(leaf_end), dxfattribs=attrs)
        a_leaf = math.degrees(math.atan2(inward[1], inward[0]))
        a_closed = math.degrees(math.atan2(d[1], d[0]))
        ccw = inward[0] * d[1] - inward[1] * d[0] > 0
        start, end = (a_leaf, a_closed) if ccw else (a_closed, a_leaf)
        msp.add_arc(_xy(pa), width, start, end, dxfattribs=attrs)
    else:  # hueco de paso sin carpintería
        dashed = {**attrs, "linetype": "DASHED", "ltscale": 0.08}  # trazo de 10 cm
        msp.add_line(_xy(pa), _xy(pb), dxfattribs=dashed)
        msp.add_line(_xy(pa + n * t), _xy(pb + n * t), dxfattribs=dashed)


def _draw_dimension(msp: Modelspace, wall: Wall2D) -> None:
    if wall.length < 0.05:
        return
    base = wall.midpoint - wall.normal * DIM_OFFSET  # hacia dentro de la estancia
    angle, p1, p2 = math.degrees(wall.angle), wall.p0, wall.p1
    if not -90.0 < angle <= 90.0:  # texto siempre legible (de izquierda a derecha o de abajo arriba)
        angle, p1, p2 = angle - math.copysign(180.0, angle), p2, p1
    msp.add_linear_dim(
        base=_xy(base),
        p1=_xy(p1),
        p2=_xy(p2),
        angle=angle,
        dimstyle=DIMSTYLE,
        dxfattribs={"layer": LAYER_DIMS},
    ).render()


def draw_plan(msp: Modelspace, plan: FloorPlan, dimensions: bool = True) -> None:
    for wall in plan.walls:
        _draw_wall(msp, plan, wall)
        for a, b, o in plan.gaps(wall):
            _draw_opening(msp, wall, a, b, o)
        if dimensions:
            _draw_dimension(msp, wall)
    if plan.walls:
        center = np.mean([w.midpoint for w in plan.walls], axis=0)
        msp.add_text(
            plan.name.upper(),
            height=0.15,
            dxfattribs={"layer": LAYER_TEXT, "style": "OpenSans"},
        ).set_placement(_xy(center), align=ezdxf.enums.TextEntityAlignment.MIDDLE_CENTER)


def write_dxf(plans: list[FloorPlan], path: str | Path, dimensions: bool = True) -> Path:
    doc = new_document()
    msp = doc.modelspace()
    for plan in plans:
        draw_plan(msp, plan, dimensions=dimensions)
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    doc.saveas(path)
    return path

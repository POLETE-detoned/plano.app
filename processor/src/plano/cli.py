"""Línea de comandos: `plano info`, `plano dxf`, `plano sample`."""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

from . import __version__
from .dxf import write_dxf
from .package import PlanoFormatError, PlanoPackage
from .plan import DEFAULT_WALL_THICKNESS, FloorPlan, align_to_axes, build_plan, join_corners, orthogonalize
from .roomplan import parse_captured_room
from .sample import write_sample_package


def load_plans(
    pkg: PlanoPackage,
    room: str | None = None,
    ortho: bool = True,
    tolerance: float = 3.0,
    wall_thickness: float = DEFAULT_WALL_THICKNESS,
    align: bool = False,
) -> list[FloorPlan]:
    plans = []
    for entry in pkg.rooms():
        if room and room.upper() not in (entry.id.upper(), entry.name.upper()):
            continue
        captured = parse_captured_room(entry.data, entry.id, entry.alignment)
        plan = build_plan(captured, entry.name, wall_thickness)
        if ortho:
            orthogonalize(plan, tolerance)
        join_corners(plan)
        plans.append(plan)
    if align:
        align_to_axes(plans)
    return plans


def cmd_info(args: argparse.Namespace) -> int:
    with PlanoPackage(args.package) as pkg:
        m = pkg.manifest
        print(f"Proyecto: {pkg.name}")
        print(f"Formato:  plano v{m['version']}  ·  app {m.get('app', {}).get('version', '?')}")
        frames = m.get("frames") or {}
        print(f"Fotogramas: {frames.get('count', 0)}  ·  malla: {m.get('mesh') or '—'}")
        for plan in load_plans(pkg, ortho=False):
            perim = sum(w.length for w in plan.walls)
            kinds = [o.kind for o in plan.openings]
            print(
                f"  · {plan.name}: {len(plan.walls)} muros ({perim:.2f} m), "
                f"{kinds.count('door')} puertas, {kinds.count('window')} ventanas, {kinds.count('opening')} huecos"
            )
            for w in plan.walls:
                print(f"      muro {w.id[:8]}  {w.length:6.3f} m  ·  {math.degrees(w.angle):7.2f}°")
            for warning in plan.warnings:
                print(f"      ! {warning}")
    return 0


def cmd_dxf(args: argparse.Namespace) -> int:
    with PlanoPackage(args.package) as pkg:
        plans = load_plans(
            pkg, args.room, not args.no_ortho, args.tolerance, args.wall_thickness, align=not args.keep_orientation
        )
        if not plans:
            print("No hay estancias que exportar.", file=sys.stderr)
            return 1
        out = Path(args.output) if args.output else Path(args.package).with_suffix(".dxf")
        write_dxf(plans, out, dimensions=not args.no_dims)
    for plan in plans:
        for warning in plan.warnings:
            print(f"! {plan.name}: {warning}", file=sys.stderr)
    print(out)
    return 0


def cmd_sample(args: argparse.Namespace) -> int:
    print(write_sample_package(args.output))
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="plano", description="Procesador de escritorio de Plano.")
    p.add_argument("--version", action="version", version=f"plano {__version__}")
    sub = p.add_subparsers(dest="command", required=True)

    info = sub.add_parser("info", help="resumen de un paquete .plano")
    info.add_argument("package")
    info.set_defaults(func=cmd_info)

    dxf = sub.add_parser("dxf", help="exporta la planta a DXF (capas MUROS, HUECOS, COTAS)")
    dxf.add_argument("package")
    dxf.add_argument("-o", "--output", help="fichero de salida (por defecto, junto al paquete)")
    dxf.add_argument("--room", help="exportar solo esta estancia (id o nombre)")
    dxf.add_argument("--tolerance", type=float, default=3.0, help="tolerancia de ortogonalización en grados (3)")
    dxf.add_argument("--no-ortho", action="store_true", help="no forzar ángulos de 90°")
    dxf.add_argument(
        "--wall-thickness", type=float, default=DEFAULT_WALL_THICKNESS, help="grosor de muro en m (0,10)"
    )
    dxf.add_argument("--no-dims", action="store_true", help="sin cotas")
    dxf.add_argument(
        "--keep-orientation", action="store_true", help="no girar la planta para alinear los muros con los ejes"
    )
    dxf.set_defaults(func=cmd_dxf)

    sample = sub.add_parser("sample", help="genera un .plano sintético para pruebas")
    sample.add_argument("output", nargs="?", default="muestra.plano")
    sample.set_defaults(func=cmd_sample)
    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return args.func(args)
    except (PlanoFormatError, FileNotFoundError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())

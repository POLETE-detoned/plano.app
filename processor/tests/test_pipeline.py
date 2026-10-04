import math
import zipfile

import ezdxf
import numpy as np
import pytest

from plano.cli import load_plans, main
from plano.package import PlanoFormatError, PlanoPackage, column_major
from plano.plan import build_plan, dominant_angle, join_corners, orthogonalize
from plano.roomplan import parse_captured_room
from plano.sample import ROOM_D, ROOM_W, sample_captured_room, write_sample_package


@pytest.fixture
def package_path(tmp_path):
    return write_sample_package(tmp_path / "muestra.plano")


def _square_angles(plan):
    phi = dominant_angle(plan.walls)
    return [abs(math.remainder(w.angle - phi, math.pi / 2)) for w in plan.walls]


def test_column_major_accepts_flat_and_nested():
    m = np.arange(16, dtype=float).reshape(4, 4)
    flat = m.T.reshape(-1).tolist()
    nested = [m[:, c].tolist() for c in range(4)]
    assert np.allclose(column_major(flat, 4), m)
    assert np.allclose(column_major(nested, 4), m)


def test_package_reads_zip_with_root_folder(package_path):
    with PlanoPackage(package_path) as pkg:
        assert pkg.name == "Muestra"
        rooms = pkg.rooms()
        assert [r.name for r in rooms] == ["Salón"]
        frames = list(pkg.frames())
        assert len(frames) == 2
        depth = pkg.read_depth(frames[0])
        assert depth.shape == (6, 8) and np.allclose(depth, 2.0)
        assert np.allclose(frames[0].camera_transform[:3, 3], [1.0, 0.0, -1.0])


def test_package_reads_unzipped_folder(package_path, tmp_path):
    out = tmp_path / "abierto"
    with zipfile.ZipFile(package_path) as zf:
        zf.extractall(out)
    with PlanoPackage(out) as pkg:
        assert len(pkg.rooms()) == 1


def test_package_rejects_missing_manifest(tmp_path):
    bad = tmp_path / "malo.plano"
    with zipfile.ZipFile(bad, "w") as zf:
        zf.writestr("otra.json", "{}")
    with pytest.raises(PlanoFormatError):
        PlanoPackage(bad)


def test_build_plan_hosts_openings_and_orients_normals():
    plan = build_plan(parse_captured_room(sample_captured_room(), "r"), "Salón")
    assert len(plan.walls) == 4
    assert sorted(o.kind for o in plan.openings) == ["door", "opening", "window"]
    # El hueco sin parentIdentifier debe asignarse al tercer muro (el más cercano).
    gap = next(o for o in plan.openings if o.kind == "opening")
    assert gap.wall_id == plan.walls[2].id
    # Las normales apuntan hacia fuera: el centro de la estancia queda detrás.
    center = np.mean([w.midpoint for w in plan.walls], axis=0)
    for w in plan.walls:
        assert np.dot(w.normal, w.midpoint - center) > 0
    window = next(o for o in plan.openings if o.kind == "window")
    assert window.sill == pytest.approx(0.90, abs=1e-3)


def test_orthogonalize_and_join_close_the_room():
    plan = build_plan(parse_captured_room(sample_captured_room(), "r"), "Salón")
    assert max(_square_angles(plan)) > math.radians(1)
    assert orthogonalize(plan, 3.0) == 4
    assert max(_square_angles(plan)) < 1e-9
    assert join_corners(plan) == 4
    for a, b in zip(plan.walls, plan.walls[1:] + plan.walls[:1]):
        assert np.allclose(a.p1, b.p0, atol=1e-9)
    lengths = sorted(w.length for w in plan.walls)
    assert lengths[0] == pytest.approx(ROOM_D, abs=0.02)
    assert lengths[-1] == pytest.approx(ROOM_W, abs=0.02)


def test_orthogonalize_respects_tolerance():
    plan = build_plan(parse_captured_room(sample_captured_room(), "r"), "Salón")
    # Las desviaciones del ejemplo están entre 0,8° y 2°: con 0,5° no se toca nada.
    assert orthogonalize(plan, 0.5) == 0


def test_solid_intervals_leave_gap_for_door():
    plan = build_plan(parse_captured_room(sample_captured_room(), "r"), "Salón")
    orthogonalize(plan)
    join_corners(plan)
    wall = plan.wall(next(o for o in plan.openings if o.kind == "door").wall_id)
    solids = plan.solid_intervals(wall)
    assert len(solids) == 2
    gap = solids[1][0] - solids[0][1]
    assert gap == pytest.approx(0.82, abs=1e-6)


def test_dxf_has_layers_and_dimensions(package_path, tmp_path):
    out = tmp_path / "planta.dxf"
    assert main(["dxf", str(package_path), "-o", str(out)]) == 0
    doc = ezdxf.readfile(out)
    msp = doc.modelspace()
    layers = {e.dxf.layer for e in msp}
    assert {"MUROS", "HUECOS", "COTAS", "TEXTOS"} <= layers
    assert doc.units == ezdxf.units.M
    walls = msp.query('LWPOLYLINE[layer=="MUROS"]')
    assert len(walls) == 4 + 3  # cada hueco parte un muro en dos
    dims = sorted(d.get_measurement() for d in msp.query("DIMENSION"))
    assert dims[0] == pytest.approx(ROOM_D, abs=0.02)
    assert dims[-1] == pytest.approx(ROOM_W, abs=0.02)
    assert len(msp.query('ARC[layer=="HUECOS"]')) == 1  # una puerta


def test_dxf_is_axis_aligned_by_default(package_path):
    with PlanoPackage(package_path) as pkg:
        plans = load_plans(pkg, align=True)
    for w in plans[0].walls:
        assert abs(math.remainder(w.angle, math.pi / 2)) < 1e-9


def test_cli_info_and_sample(tmp_path, capsys):
    path = tmp_path / "nuevo.plano"
    assert main(["sample", str(path)]) == 0
    assert main(["info", str(path)]) == 0
    out = capsys.readouterr().out
    assert "4 muros" in out and "1 puertas" in out


def test_cli_reports_bad_package(tmp_path, capsys):
    bad = tmp_path / "x.plano"
    bad.write_text("no soy un zip")
    assert main(["info", str(bad)]) == 2
    assert "error" in capsys.readouterr().err

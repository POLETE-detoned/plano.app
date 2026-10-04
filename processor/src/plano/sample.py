"""Genera un `.plano` sintético (estancia de 4,20 × 3,10 m) para probar sin iPhone."""

from __future__ import annotations

import io
import json
import math
import uuid
import zipfile
from pathlib import Path
from typing import Any

import numpy as np

ROOM_W, ROOM_D, ROOM_H = 4.20, 3.10, 2.60
FLOOR_Y = -1.35  # el origen ARKit está a la altura del móvil al empezar


def _uid(seed: str) -> str:
    return str(uuid.uuid5(uuid.NAMESPACE_URL, f"plano-sample/{seed}")).upper()


def _flat(m: np.ndarray) -> list[float]:
    return [round(float(v), 6) for v in m.T.reshape(-1)]  # column-major


def surface_transform(center_plan: np.ndarray, dir_plan: np.ndarray, center_y: float) -> np.ndarray:
    """Matriz local→mundo de una superficie vertical con eje X a lo largo de `dir_plan`."""
    x = np.array([dir_plan[0], 0.0, -dir_plan[1]])
    x /= np.linalg.norm(x)
    y = np.array([0.0, 1.0, 0.0])
    z = np.cross(x, y)
    m = np.eye(4)
    m[:3, 0], m[:3, 1], m[:3, 2] = x, y, z
    m[:3, 3] = [center_plan[0], center_y, -center_plan[1]]
    return m


def _surface(seed: str, category: dict[str, Any], m: np.ndarray, dims: tuple[float, float, float], parent: str | None):
    s: dict[str, Any] = {
        "identifier": _uid(seed),
        "category": category,
        "confidence": {"high": {}},
        "dimensions": [round(v, 6) for v in dims],
        "transform": _flat(m),
        "edges": [],
        "completedEdges": [],
    }
    if parent:
        s["parentIdentifier"] = parent
    return s


def sample_captured_room(rotation_deg: float = 12.0, noise: bool = True) -> dict[str, Any]:
    """CapturedRoom con cuatro muros ligeramente imperfectos, una puerta, una ventana y un hueco."""
    rot = math.radians(rotation_deg)
    r = np.array([[math.cos(rot), -math.sin(rot)], [math.sin(rot), math.cos(rot)]])
    corners = [np.array(p) for p in ((0, 0), (ROOM_W, 0), (ROOM_W, ROOM_D), (0, ROOM_D))]
    # (giro en grados, recorte en cada extremo en m): RoomPlan nunca cierra perfecto.
    imperfections = [(1.2, 0.03), (-0.8, 0.05), (1.5, 0.02), (-2.0, 0.04)] if noise else [(0.0, 0.0)] * 4

    walls, wall_frames = [], []
    for k in range(4):
        a, b = corners[k], corners[(k + 1) % 4]
        deg, trim = imperfections[k]
        mid = (a + b) / 2
        d = (b - a) / np.linalg.norm(b - a)
        dn = math.radians(deg)
        d = np.array([d[0] * math.cos(dn) - d[1] * math.sin(dn), d[0] * math.sin(dn) + d[1] * math.cos(dn)])
        length = float(np.linalg.norm(b - a)) - 2 * trim
        mid_w, d_w = r @ mid, r @ d
        m = surface_transform(mid_w, d_w, FLOOR_Y + ROOM_H / 2)
        walls.append(_surface(f"wall-{k}", {"wall": {}}, m, (length, ROOM_H, 0.0), None))
        wall_frames.append((mid_w, d_w, length))

    def on_wall(k: int, offset_from_mid: float, center_y: float) -> np.ndarray:
        mid_w, d_w, _ = wall_frames[k]
        return surface_transform(mid_w + d_w * offset_from_mid, d_w, center_y)

    door_h, win_h, win_sill, gap_h = 2.03, 1.10, 0.90, 2.10
    doors = [
        _surface(
            "door-0",
            {"door": {"isOpen": False}},
            on_wall(0, -1.10, FLOOR_Y + door_h / 2),
            (0.82, door_h, 0.0),
            walls[0]["identifier"],
        )
    ]
    windows = [
        _surface(
            "window-0",
            {"window": {}},
            on_wall(1, 0.0, FLOOR_Y + win_sill + win_h / 2),
            (1.20, win_h, 0.0),
            walls[1]["identifier"],
        )
    ]
    openings = [  # sin parentIdentifier: el procesador debe encontrar el muro
        _surface("opening-0", {"opening": {}}, on_wall(2, 0.9, FLOOR_Y + gap_h / 2), (0.90, gap_h, 0.0), None)
    ]
    return {
        "identifier": _uid("room"),
        "version": 2,
        "story": 0,
        "walls": walls,
        "doors": doors,
        "windows": windows,
        "openings": openings,
        "objects": [],
        "floors": [],
        "sections": [],
    }


def _frame_files(index: int, room_id: str) -> dict[str, bytes]:
    dw, dh = 8, 6
    depth = np.full((dh, dw), 2.0, dtype="<f4")
    pose = np.eye(4)
    pose[:3, 3] = [1.0, 0.0, -1.0]
    meta = {
        "index": index,
        "roomId": room_id,
        "timestamp": 10.0 + index * 0.5,
        "image": {"file": f"{index:06d}.heic", "width": 64, "height": 48},
        "intrinsics": [50.0, 0, 0, 0, 50.0, 0, 32.0, 24.0, 1],
        "cameraTransform": _flat(pose),
        "depth": {
            "file": f"{index:06d}.depth",
            "width": dw,
            "height": dh,
            "format": "float32le",
            "confidence": None,
            "intrinsics": [50.0 * dw / 64, 0, 0, 0, 50.0 * dh / 48, 0, 32.0 * dw / 64, 24.0 * dh / 48, 1],
            "cameraTransform": _flat(pose),
            "timestamp": 10.0 + index * 0.5 + 0.03,
        },
        "trackingState": "normal",
    }
    return {
        f"frames/{index:06d}.json": json.dumps(meta).encode(),
        f"frames/{index:06d}.depth": depth.tobytes(),
        f"frames/{index:06d}.heic": b"",  # marcador: el procesador aún no lee imágenes
    }


def write_sample_package(path: str | Path, frames: int = 2, root_folder: str | None = "Muestra") -> Path:
    """Escribe un `.plano` de ejemplo. `root_folder` imita el ZIP que genera iOS."""
    room = sample_captured_room()
    room_id = room["identifier"]
    manifest = {
        "format": "plano",
        "version": 1,
        "createdAt": "2026-10-04T10:00:00Z",
        "app": {"name": "Plano", "version": "sample"},
        "project": {"id": _uid("project"), "name": "Muestra"},
        "units": "m",
        "coordinateSystem": "arkit-y-up",
        "rooms": [
            {
                "id": room_id,
                "name": "Salón",
                "file": f"rooms/{room_id}.json",
                "usdz": None,
                "capturedAt": "2026-10-04T10:03:00Z",
                "session": _uid("session"),
                "alignment": None,
            }
        ],
        "mesh": None,
        "model": None,
        "frames": {"dir": "frames", "count": frames},
    }
    files = {
        "manifest.json": json.dumps(manifest, indent=2, ensure_ascii=False).encode(),
        f"rooms/{room_id}.json": json.dumps(room, indent=2).encode(),
    }
    for i in range(1, frames + 1):
        files.update(_frame_files(i, room_id))

    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        prefix = f"{root_folder}/" if root_folder else ""
        for name, data in files.items():
            zf.writestr(prefix + name, data)
    path.write_bytes(buf.getvalue())
    return path

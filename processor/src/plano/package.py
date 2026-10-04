"""Lectura de paquetes `.plano` (ZIP o carpeta). Ver docs/FORMATO_PLANO.md."""

from __future__ import annotations

import json
import zipfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any, Iterator

import numpy as np

MANIFEST = "manifest.json"
SUPPORTED_VERSIONS = {1}


class PlanoFormatError(ValueError):
    """El paquete no cumple el formato `.plano`."""


@dataclass(frozen=True)
class RoomEntry:
    id: str
    name: str
    data: dict[str, Any]
    alignment: np.ndarray | None  # 4×4, estancia → mundo del proyecto


@dataclass(frozen=True)
class FrameEntry:
    index: int
    meta: dict[str, Any]

    @property
    def intrinsics(self) -> np.ndarray:
        return column_major(self.meta["intrinsics"], 3)

    @property
    def camera_transform(self) -> np.ndarray:
        return column_major(self.meta["cameraTransform"], 4)

    @property
    def depth_intrinsics(self) -> np.ndarray | None:
        depth = self.meta.get("depth")
        return column_major(depth["intrinsics"], 3) if depth else None

    @property
    def depth_camera_transform(self) -> np.ndarray | None:
        depth = self.meta.get("depth")
        return column_major(depth["cameraTransform"], 4) if depth else None


def column_major(values: Any, n: int) -> np.ndarray:
    """Convierte una matriz serializada (plana column-major o lista de columnas) a n×n."""
    arr = np.asarray(values, dtype=float)
    if arr.shape == (n * n,):
        return arr.reshape(n, n).T
    if arr.shape == (n, n):
        return arr.T  # lista de columnas
    raise PlanoFormatError(f"matriz {n}×{n} con forma inesperada {arr.shape}")


class PlanoPackage:
    """Acceso de solo lectura a un paquete `.plano`."""

    def __init__(self, path: str | Path):
        self.path = Path(path)
        if self.path.is_dir():
            self._zip = None
            names = [p.relative_to(self.path).as_posix() for p in self.path.rglob("*") if p.is_file()]
        elif zipfile.is_zipfile(self.path):
            self._zip = zipfile.ZipFile(self.path)
            names = [n for n in self._zip.namelist() if not n.endswith("/")]
        else:
            raise PlanoFormatError(f"{self.path} no es un ZIP ni una carpeta")

        manifests = sorted(
            (n for n in names if PurePosixPath(n).name == MANIFEST and "__MACOSX" not in n),
            key=lambda n: n.count("/"),
        )
        if not manifests:
            raise PlanoFormatError("falta manifest.json")
        self._root = str(PurePosixPath(manifests[0]).parent)
        self._root = "" if self._root == "." else self._root + "/"
        self.manifest: dict[str, Any] = json.loads(self.read_bytes(MANIFEST))

        if self.manifest.get("format") != "plano":
            raise PlanoFormatError("manifest.format debe ser 'plano'")
        if self.manifest.get("version") not in SUPPORTED_VERSIONS:
            raise PlanoFormatError(f"versión de formato no soportada: {self.manifest.get('version')}")

    def __enter__(self) -> PlanoPackage:
        return self

    def __exit__(self, *exc: object) -> None:
        self.close()

    def close(self) -> None:
        if self._zip is not None:
            self._zip.close()

    # -- acceso a ficheros -------------------------------------------------

    def read_bytes(self, rel: str) -> bytes:
        name = self._root + rel
        if self._zip is not None:
            try:
                return self._zip.read(name)
            except KeyError:
                raise FileNotFoundError(rel) from None
        return (self.path / name).read_bytes()

    def exists(self, rel: str) -> bool:
        try:
            self.read_bytes(rel)
        except FileNotFoundError:
            return False
        return True

    def read_json(self, rel: str) -> Any:
        return json.loads(self.read_bytes(rel))

    # -- contenido ---------------------------------------------------------

    @property
    def name(self) -> str:
        return self.manifest.get("project", {}).get("name") or self.path.stem

    def rooms(self) -> list[RoomEntry]:
        out = []
        for meta in self.manifest.get("rooms", []):
            align = meta.get("alignment")
            out.append(
                RoomEntry(
                    id=meta["id"],
                    name=meta.get("name") or meta["id"][:8],
                    data=self.read_json(meta["file"]),
                    alignment=column_major(align, 4) if align is not None else None,
                )
            )
        return out

    def frames(self) -> Iterator[FrameEntry]:
        info = self.manifest.get("frames") or {}
        folder = info.get("dir", "frames")
        for i in range(1, int(info.get("count", 0)) + 1):
            rel = f"{folder}/{i:06d}.json"
            if self.exists(rel):
                yield FrameEntry(index=i, meta=self.read_json(rel))

    def read_depth(self, frame: FrameEntry) -> np.ndarray | None:
        depth = frame.meta.get("depth")
        if not depth:
            return None
        if depth.get("format", "float32le") != "float32le":
            raise PlanoFormatError(f"formato de profundidad no soportado: {depth.get('format')}")
        folder = (self.manifest.get("frames") or {}).get("dir", "frames")
        raw = self.read_bytes(f"{folder}/{depth['file']}")
        return np.frombuffer(raw, dtype="<f4").reshape(depth["height"], depth["width"])

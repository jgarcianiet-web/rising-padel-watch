#!/usr/bin/env python3
"""Entrena el clasificador de golpeos a partir de las muestras grabadas con el reloj.

Uso:

    pip install numpy scikit-learn
    python3 tools/train_classifier.py muestras.jsonl

    # exportar el modelo entrenado
    python3 tools/train_classifier.py muestras.jsonl --export modelo.json

Lee el JSONL que produce el modo de grabación (ver docs/training-data.md), extrae
rasgos de cada ventana, entrena un ensemble de árboles y **valida dejando fuera a un
jugador entero**.

Esa validación es el motivo por el que este script existe y no un notebook improvisado:
si los golpeos de la misma persona caen a los dos lados de la partición, el modelo
memoriza al jugador y la precisión que mides no se parece a la que verás en pista. La
única cifra que predice el comportamiento con alguien nuevo es la de leave-one-player-out.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

try:
    import numpy as np
    from sklearn.ensemble import HistGradientBoostingClassifier
    from sklearn.metrics import accuracy_score, classification_report, confusion_matrix
except ImportError:  # pragma: no cover - solo guía al usuario
    sys.exit("Faltan dependencias. Instálalas con:\n\n    pip install numpy scikit-learn\n")


# Rasgos derivados de la ventana cruda. Los cuatro primeros son los que ya usa la
# heurística; el resto es lo que la heurística no mira y por eso se le escapan golpeos.
FEATURE_NAMES = [
    "swept_angle_deg",
    "peak_gyro",
    "elevation_deg",
    "axial_rotation",
    "swing_duration_ms",
    "peak_accel",
    "accel_rise_ms",
    "accel_fall_ms",
    "gyro_mean_pre",
    "gyro_mean_post",
    "gyro_ratio_post_pre",
    "axial_pre",
    "axial_post",
    "elevation_pre",
    "elevation_delta",
    # Estadísticas robustas de la elevación, las mismas que usa la heurística desde que
    # se vio en pista que un valor instantáneo no separa un golpe alto de uno de fondo:
    # el filtro de gravedad del sistema se descuadra en mitad del swing.
    "elevation_median",
    "elevation_p80",
    "energy_pre",
    "energy_post",
]


@dataclass
class Sample:
    features: list[float]
    label: str
    player: str
    heuristic: str


def magnitude(vectors: np.ndarray) -> np.ndarray:
    return np.linalg.norm(vectors, axis=1)


def extract_features(record: dict) -> list[float] | None:
    """Convierte una ventana cruda en el vector de rasgos.

    Devuelve None si la ventana está mal formada: mejor saltarse una muestra que
    entrenar con basura.
    """
    try:
        offsets = np.asarray(record["offsetsMs"], dtype=float)
        accel = np.asarray(record["accel"], dtype=float)
        gyro = np.asarray(record["gyro"], dtype=float)
        gravity = np.asarray(record["gravity"], dtype=float)
        impact = int(record["impactIndex"])
        heuristic = record["heuristicFeatures"]
    except (KeyError, TypeError, ValueError):
        return None

    if len(offsets) < 10 or not (0 <= impact < len(offsets)):
        return None
    if accel.shape[0] != len(offsets) or gyro.shape[0] != len(offsets):
        return None

    accel_mag = magnitude(accel)
    gyro_mag = magnitude(gyro)

    # Pre = los 400 ms anteriores al impacto (el swing). Post = los 400 ms siguientes
    # (la frenada del brazo, que es lo que separa una volea de una derecha completa).
    pre = (offsets >= -400) & (offsets < 0)
    post = (offsets > 0) & (offsets <= 400)
    if pre.sum() < 3 or post.sum() < 3:
        return None

    # Normalización por lateralidad, la misma que hace ShotClassifier en el core.
    #
    # Sin esto, un zurdo produce señales especulares y el modelo tiene que aprender la
    # lateralidad desde cero, lo que exigiría tantos zurdos como diestros en el conjunto.
    # Normalizando, un revés es un revés venga de quien venga y basta con unos pocos
    # zurdos para comprobar que generaliza.
    #
    # La muñeca invierte hacia dónde apunta el eje +Y del reloj respecto al brazo; la
    # mano invierte el signo porque un zurdo es la imagen especular de un diestro.
    wrist_sign = -1.0 if record.get("watchWrist") == "left" else 1.0
    hand_sign = -1.0 if record.get("hand") == "left" else 1.0

    # En watchOS el marco de CoreMotion sigue la orientación de pantalla y las 12 del
    # reloj miran siempre al codo: el eje codo → mano es -Y en las dos muñecas
    # (validado en pista; ver docs/shot-detection.md). En Wear se mantiene el convenio
    # por muñeca hasta validarlo con un dispositivo real.
    if record.get("platform") == "watchos":
        forearm = np.array([0.0, -1.0, 0.0])
    else:
        forearm = np.array([0.0, wrist_sign, 0.0])
    axial = (gyro @ forearm) * hand_sign

    # Elevación del antebrazo: ángulo sobre la horizontal, igual que en la heurística.
    def elevation(rows: np.ndarray) -> np.ndarray:
        norms = np.linalg.norm(rows, axis=1)
        norms[norms == 0] = 1.0
        up = -rows / norms[:, None]
        return np.degrees(np.arcsin(np.clip(up @ forearm, -1.0, 1.0)))

    elev = elevation(gravity) if gravity.shape[0] == len(offsets) else np.zeros(len(offsets))

    # Cuánto tarda la aceleración en subir y en bajar alrededor del pico: un impacto
    # seco de smash y uno blando de volea tienen anchuras muy distintas.
    peak_accel = float(accel_mag[impact])
    half = peak_accel / 2 if peak_accel > 0 else 0.0
    rise, fall = 0.0, 0.0
    for i in range(impact, -1, -1):
        if accel_mag[i] < half:
            rise = float(offsets[impact] - offsets[i])
            break
    for i in range(impact, len(accel_mag)):
        if accel_mag[i] < half:
            fall = float(offsets[i] - offsets[impact])
            break

    gyro_pre = float(gyro_mag[pre].mean())
    gyro_post = float(gyro_mag[post].mean())

    return [
        float(heuristic.get("sweptAngleDeg", 0.0)),
        float(heuristic.get("peakGyroRadS", 0.0)),
        float(heuristic.get("elevationDeg", 0.0)),
        float(heuristic.get("axialRotationRadS", 0.0)) * hand_sign * wrist_sign,
        float(heuristic.get("swingDurationMs", 0.0)),
        peak_accel,
        rise,
        fall,
        gyro_pre,
        gyro_post,
        gyro_post / gyro_pre if gyro_pre > 1e-6 else 0.0,
        float(axial[pre].mean()),
        float(axial[post].mean()),
        float(elev[pre].mean()),
        float(elev[post].mean() - elev[pre].mean()),
        float(np.median(elev[pre])) if elev[pre].size else 0.0,
        float(np.percentile(elev[pre], 80)) if elev[pre].size else 0.0,
        float((accel_mag[pre] ** 2).sum()),
        float((accel_mag[post] ** 2).sum()),
    ]


def load(path: Path) -> list[Sample]:
    samples: list[Sample] = []
    skipped = 0
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                skipped += 1
                continue
            features = extract_features(record)
            if features is None or record.get("label") in (None, "unknown"):
                skipped += 1
                continue
            samples.append(
                Sample(
                    features=features,
                    label=record["label"],
                    player=record.get("playerAlias", "anon"),
                    heuristic=record.get("heuristicPrediction", "unknown"),
                )
            )
    if skipped:
        print(f"Saltadas {skipped} líneas mal formadas o sin etiqueta.")
    return samples


def describe(samples: list[Sample]) -> None:
    print(f"\n{len(samples)} muestras utilizables")
    print("\nPor tipo de golpe:")
    for label, count in sorted(Counter(s.label for s in samples).items()):
        print(f"  {label:18s} {count:5d}")
    print("\nPor jugador:")
    for player, count in sorted(Counter(s.player for s in samples).items()):
        print(f"  {player:18s} {count:5d}")


def warn_about_data(samples: list[Sample]) -> None:
    """Avisa de los problemas que hacen que el resultado no sirva, antes de entrenar."""
    players = Counter(s.player for s in samples)
    labels = Counter(s.label for s in samples)
    warnings = []

    if len(players) < 3:
        warnings.append(
            f"Solo hay {len(players)} jugador(es). El modelo aprenderá a reconocer a esa "
            "persona, no el golpe. Hacen falta 4-5 como mínimo."
        )
    if len(samples) < 500:
        warnings.append(
            f"Solo hay {len(samples)} muestras. Por debajo de ~2.000 el resultado es ruido."
        )
    scarce = [f"{lab} ({n})" for lab, n in labels.items() if n < 50]
    if scarce:
        warnings.append(
            "Tipos con muy pocas muestras: " + ", ".join(scarce) +
            ". El modelo casi nunca los va a predecir."
        )
    if warnings:
        print("\n" + "!" * 70)
        for warning in warnings:
            print(f"AVISO: {warning}")
        print("!" * 70)


def leave_one_player_out(samples: list[Sample], seed: int) -> tuple[float, float, list[str], list[str]]:
    """Entrena tantas veces como jugadores haya, dejando fuera a uno cada vez.

    Devuelve (precisión del modelo, precisión de la heurística, verdad, predicho).
    Las dos precisiones se calculan sobre exactamente las mismas muestras, que es la
    única forma de que la comparación signifique algo.
    """
    players = sorted({s.player for s in samples})
    truth: list[str] = []
    predicted: list[str] = []
    heuristic: list[str] = []

    for held_out in players:
        train = [s for s in samples if s.player != held_out]
        test = [s for s in samples if s.player == held_out]
        if not train or not test:
            continue
        if len({s.label for s in train}) < 2:
            continue

        model = HistGradientBoostingClassifier(
            max_iter=200,
            learning_rate=0.1,
            max_depth=6,
            random_state=seed,
        )
        model.fit(np.array([s.features for s in train]), [s.label for s in train])
        fold = model.predict(np.array([s.features for s in test]))

        truth.extend(s.label for s in test)
        predicted.extend(fold)
        heuristic.extend(s.heuristic for s in test)
        print(f"  sin '{held_out}': {accuracy_score([s.label for s in test], fold):.1%} "
              f"({len(test)} muestras)")

    if not truth:
        return 0.0, 0.0, [], []
    return (
        accuracy_score(truth, predicted),
        accuracy_score(truth, heuristic),
        truth,
        predicted,
    )


def export_model(samples: list[Sample], path: Path, seed: int) -> None:
    """Entrena con todo y vuelca el modelo.

    Se exporta con joblib porque el destino inmediato es convertirlo a Core ML o TFLite,
    no cargarlo tal cual en el reloj.
    """
    model = HistGradientBoostingClassifier(
        max_iter=200, learning_rate=0.1, max_depth=6, random_state=seed
    )
    model.fit(np.array([s.features for s in samples]), [s.label for s in samples])

    metadata = {
        "featureNames": FEATURE_NAMES,
        "classes": sorted({s.label for s in samples}),
        "trainedOnSamples": len(samples),
        "players": sorted({s.player for s in samples}),
    }
    path.write_text(json.dumps(metadata, indent=2, ensure_ascii=False), encoding="utf-8")

    try:
        import joblib

        joblib.dump(model, path.with_suffix(".joblib"))
        print(f"\nModelo en {path.with_suffix('.joblib')}, metadatos en {path}")
    except ImportError:
        print(f"\nMetadatos en {path}. Instala joblib para volcar también el modelo.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("dataset", type=Path, help="JSONL grabado con el reloj")
    parser.add_argument("--export", type=Path, help="ruta donde volcar el modelo entrenado")
    parser.add_argument("--seed", type=int, default=0, help="semilla, para resultados reproducibles")
    args = parser.parse_args()

    if not args.dataset.exists():
        return f"No existe {args.dataset}"

    samples = load(args.dataset)
    if not samples:
        return "No hay ninguna muestra utilizable en el fichero."

    describe(samples)
    warn_about_data(samples)

    print("\nValidación dejando fuera a un jugador entero:")
    accuracy, heuristic_accuracy, truth, predicted = leave_one_player_out(samples, args.seed)
    if not truth:
        return "\nHacen falta al menos dos jugadores y dos tipos de golpe para validar."

    print(f"\n{'=' * 60}")
    print(f"Modelo entrenado : {accuracy:.1%}")
    print(f"Heurística v1    : {heuristic_accuracy:.1%}")
    delta = accuracy - heuristic_accuracy
    print(f"Diferencia       : {delta:+.1%}")
    if delta <= 0:
        print("\nEl modelo no mejora la heurística. Con estos datos no compensa cambiarla:")
        print("lo que falta son más muestras y más jugadores, no un modelo más grande.")
    print("=" * 60)

    labels = sorted(set(truth))
    print("\nPor tipo de golpe:")
    print(classification_report(truth, predicted, labels=labels, zero_division=0))

    print("Matriz de confusión (filas = real, columnas = predicho):")
    matrix = confusion_matrix(truth, predicted, labels=labels)
    width = max(len(label) for label in labels) + 2
    print(" " * width + "".join(f"{label[:8]:>10s}" for label in labels))
    for label, row in zip(labels, matrix):
        print(f"{label:<{width}s}" + "".join(f"{value:10d}" for value in row))

    if args.export:
        export_model(samples, args.export, args.seed)
    return 0


if __name__ == "__main__":
    result = main()
    if isinstance(result, str):
        sys.exit(result)
    sys.exit(result)

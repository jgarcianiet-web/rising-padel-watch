#!/usr/bin/env python3
"""Genera un JSONL sintético con el mismo formato que el modo de grabación del reloj.

Uso:

    python3 tools/make_synthetic_dataset.py sinteticas.jsonl
    python3 tools/train_classifier.py sinteticas.jsonl

Sirve para **probar la tubería antes de pisar la pista**: comprobar que el script de
entrenamiento corre, que el formato encaja y que los avisos saltan cuando deben.

No sirve para nada más. Los golpeos salen de un modelo de media onda de seno con ruido
gaussiano, así que un clasificador entrenado con esto acierta casi todo y ese número no
significa nada: separa clases que se han generado a propósito para ser separables. La
precisión que importa solo sale de golpeos reales.
"""

from __future__ import annotations

import argparse
import json
import math
import random
from pathlib import Path

SAMPLE_RATE_HZ = 50
INTERVAL_MS = 1000 // SAMPLE_RATE_HZ
WINDOW_BEFORE_MS = 1000
WINDOW_AFTER_MS = 1000

# Perfil de cada tipo de golpe: (pico de giro, duración del swing, g de impacto,
# fracción axial, elevación). Son los mismos rangos que usan los fixtures del core.
SHOT_PROFILES = {
    "forehand": (20.0, 300, 6.5, 0.80, 10.0),
    "backhand": (18.0, 300, 5.5, -0.80, 8.0),
    "forehandVolley": (7.0, 280, 4.0, 0.75, 12.0),
    "backhandVolley": (7.0, 280, 4.0, -0.75, 12.0),
    "bandeja": (15.0, 250, 6.0, 0.20, 78.0),
    "vibora": (21.0, 240, 8.0, 0.85, 80.0),
    "smash": (30.0, 170, 10.0, 0.30, 85.0),
    "serve": (28.0, 350, 9.0, 0.60, 70.0),
}


def jitter(rng: random.Random, value: float, fraction: float) -> float:
    return value * (1 + rng.gauss(0, fraction))


def build_window(rng: random.Random, profile: tuple, player_bias: float) -> dict:
    peak_gyro, duration_ms, impact_g, axial, elevation = profile

    # Cada jugador golpea distinto: el sesgo por persona es justo lo que hace que
    # validar dejándolo fuera dé un número más bajo que validar al azar.
    peak_gyro = jitter(rng, peak_gyro * player_bias, 0.12)
    duration_ms = jitter(rng, duration_ms * player_bias, 0.10)
    impact_g = jitter(rng, impact_g, 0.15)
    axial = axial * jitter(rng, 1.0, 0.10)
    elevation = elevation + rng.gauss(0, 6)

    steps_before = WINDOW_BEFORE_MS // INTERVAL_MS
    steps_after = WINDOW_AFTER_MS // INTERVAL_MS
    swing_steps = max(int(duration_ms / INTERVAL_MS), 6)
    impact_step = int(swing_steps * 0.75)

    elevation_rad = math.radians(elevation)
    gravity = [-math.cos(elevation_rad), -math.sin(elevation_rad), 0.0]
    lateral = math.sqrt(max(1 - axial * axial, 0.0))

    offsets, accel, gyro, gravity_rows = [], [], [], []
    swept_rad = 0.0
    peak_gyro_seen = 0.0

    for step in range(-steps_before, steps_after + 1):
        offset_ms = step * INTERVAL_MS
        offsets.append(offset_ms)

        # El swing ocupa de -impact_step a swing_steps - impact_step.
        swing_index = step + impact_step
        if 0 <= swing_index <= swing_steps:
            gyro_mag = peak_gyro * math.sin(math.pi * swing_index / swing_steps)
        else:
            gyro_mag = 0.0
        gyro_mag = max(gyro_mag + rng.gauss(0, 0.3), 0.0)

        if step < 0 and gyro_mag > 0:
            swept_rad += gyro_mag * INTERVAL_MS / 1000
        peak_gyro_seen = max(peak_gyro_seen, gyro_mag)

        spike = impact_g * math.exp(-((offset_ms / 25.0) ** 2))
        accel_mag = 0.2 + spike + abs(rng.gauss(0, 0.08))

        accel.append([round(accel_mag, 4), round(rng.gauss(0, 0.05), 4), round(rng.gauss(0, 0.05), 4)])
        gyro.append([
            round(lateral * gyro_mag, 4),
            round(axial * gyro_mag, 4),
            round(rng.gauss(0, 0.1), 4),
        ])
        gravity_rows.append([round(g + rng.gauss(0, 0.02), 4) for g in gravity])

    return {
        "offsetsMs": offsets,
        "accel": accel,
        "gyro": gyro,
        "gravity": gravity_rows,
        "impactIndex": steps_before,
        "sampleRateHz": SAMPLE_RATE_HZ,
        "heuristicFeatures": {
            "sweptAngleDeg": round(math.degrees(swept_rad), 2),
            "peakGyroRadS": round(peak_gyro_seen, 3),
            "elevationDeg": round(elevation, 2),
            "axialRotationRadS": round(axial * peak_gyro_seen * 0.7, 3),
            "swingDurationMs": int(duration_ms * 0.75),
        },
    }


def heuristic_guess(record: dict, label: str, rng: random.Random) -> str:
    """Imita a la heurística v1: acierta la mayoría de las veces y confunde vecinos.

    Confundir tipos vecinos (derecha con volea de derecha) y no cualquier par al azar es
    lo que hace que la comparación modelo-vs-heurística se parezca a la realidad.
    """
    neighbours = {
        "forehand": "forehandVolley",
        "forehandVolley": "forehand",
        "backhand": "backhandVolley",
        "backhandVolley": "backhand",
        "bandeja": "vibora",
        "vibora": "bandeja",
        "smash": "serve",
        "serve": "smash",
    }
    return label if rng.random() > 0.18 else neighbours[label]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("output", type=Path)
    parser.add_argument("--players", type=int, default=5)
    parser.add_argument("--per-shot", type=int, default=60, help="golpeos de cada tipo y jugador")
    parser.add_argument("--seed", type=int, default=0)
    args = parser.parse_args()

    rng = random.Random(args.seed)
    written = 0

    with args.output.open("w", encoding="utf-8") as handle:
        for player_index in range(args.players):
            alias = f"jugador-{player_index + 1}"
            # Un jugador pega más fuerte que otro; el modelo tiene que aguantar eso.
            player_bias = 1.0 + rng.gauss(0, 0.12)
            hand = "left" if player_index % 4 == 3 else "right"

            for label, profile in SHOT_PROFILES.items():
                for _ in range(args.per_shot):
                    window = build_window(rng, profile, player_bias)
                    # Un zurdo **no** produce aquí la señal especular, aunque lo parezca:
                    # lleva el reloj en la otra muñeca, girado 180° respecto al brazo, y
                    # ese segundo espejo cancela al primero. Es el convenio que usa
                    # ShotClassifier en el core, y el que replica train_classifier.py al
                    # normalizar. (Ese convenio es un razonamiento, no una medida: está
                    # pendiente de validar en pista, ver docs/shot-detection.md.)

                    record = {
                        "sampleId": f"{alias}-{label}-{written}",
                        "label": label,
                        "recordedAtEpochMs": 1_785_002_652_000 + written * 1000,
                        "playerAlias": alias,
                        "hand": hand,
                        "watchWrist": hand,
                        "platform": "wearos",
                        "device": "Sintético",
                        "heuristicPrediction": heuristic_guess(window, label, rng),
                        "heuristicConfidence": round(rng.uniform(0.5, 0.95), 2),
                        **window,
                    }
                    handle.write(json.dumps(record, ensure_ascii=False) + "\n")
                    written += 1

    size_mb = args.output.stat().st_size / 1024 / 1024
    print(f"{written} muestras sintéticas en {args.output} ({size_mb:.1f} MB)")
    print("\nRecuerda: sirve para probar la tubería, no para medir precisión.")


if __name__ == "__main__":
    main()

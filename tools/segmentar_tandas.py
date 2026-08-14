#!/usr/bin/env python3
"""Corta las tandas crudas en ventanas por golpe, listas para entrenar.

Uso:

    python3 tools/segmentar_tandas.py muestras.jsonl ventanas.jsonl
    python3 tools/train_classifier.py ventanas.jsonl

Es la mitad que le faltaba a la grabación en crudo. La tanda se graba entera para que
ninguna derecha se pierda, pero **una derecha es una derecha, no un bloque de dos
minutos**: entre golpe y golpe hay pasos, colocación y recogida de bolas, y nada de eso
puede entrar al dataset con la etiqueta puesta. Este script encuentra los impactos en la
señal cruda y saca una ventana de ±1 s alrededor de cada uno — solo los golpes viajan al
entrenamiento, con su etiqueta; el resto del bloque se queda fuera.

**Por qué segmentar aquí y no en el reloj.** El detector del reloj decide en tiempo real
con umbrales fijos, y cuando se equivoca el golpe se pierde para siempre — es el fallo
que motivó grabar en crudo. Aquí se decide con toda la señal delante, con un umbral
relativo al ruido de ESA tanda, y si mañana el criterio mejora se re-segmenta todo el
histórico: nada se pierde nunca.

Las líneas del formato viejo (ya por golpe) pasan tal cual: el fichero mezclado funciona.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path

try:
    import numpy as np
except ImportError:
    sys.exit("Falta numpy. Instálalo con:\n\n    pip install numpy\n")


# Ventana alrededor de cada impacto, la misma que usaba la captura vieja: el swing cabe
# entero en el segundo anterior y la frenada en el siguiente.
VENTANA_MS = 1_000

# Dos impactos a menos de esto son el mismo golpe (rebote del sensor incluido).
SEPARACION_MINIMA_MS = 400

# Suelo absoluto del pico de impacto, en g. Por debajo de esto no hay bola: un swing en
# vacío ronda 1-2 g y un impacto real de pádel pasa de 3 con holgura.
IMPACTO_MINIMO_G = 2.5


def segmentar(tanda: dict) -> list[dict]:
    """Devuelve una ventana por impacto encontrado en el bloque."""
    offsets = np.asarray(tanda["offsetsMs"], dtype=float)
    accel = np.asarray(tanda["accel"], dtype=float)
    gyro = np.asarray(tanda["gyro"], dtype=float)
    gravity = np.asarray(tanda["gravity"], dtype=float)
    if len(offsets) < 100:
        return []

    magnitud = np.linalg.norm(accel, axis=1)

    # Umbral relativo al ruido de ESTA tanda: la mediana es el "brazo moviéndose sin
    # golpear" y el MAD su dispersión. Un golpe real se sale de ahí por mucho; andar
    # entre golpes, no. El suelo absoluto evita que una tanda de puro reposo con un
    # estornudo produzca "golpes".
    mediana = float(np.median(magnitud))
    mad = float(np.median(np.abs(magnitud - mediana))) or 0.05
    umbral = max(IMPACTO_MINIMO_G, mediana + 8 * mad)

    # Picos: máximo local por encima del umbral, con separación mínima.
    candidatos = np.where(magnitud >= umbral)[0]
    picos: list[int] = []
    for indice in candidatos:
        if picos and offsets[indice] - offsets[picos[-1]] < SEPARACION_MINIMA_MS:
            # Del mismo golpe: quédate con el mayor.
            if magnitud[indice] > magnitud[picos[-1]]:
                picos[-1] = int(indice)
            continue
        picos.append(int(indice))

    # Los golpes que el detector anotó en vivo, para heredar sus rasgos si caen cerca.
    golpes_detector = tanda.get("golpes") or []

    ventanas: list[dict] = []
    for numero, pico in enumerate(picos):
        centro = offsets[pico]
        seleccion = (offsets >= centro - VENTANA_MS) & (offsets <= centro + VENTANA_MS)
        indices = np.where(seleccion)[0]
        # Sin swing por delante o sin frenada por detrás, la ventana no se puede
        # comparar con las demás: fuera.
        if offsets[indices[-1]] - centro < 300 or centro - offsets[indices[0]] < 300:
            continue

        cercano = min(
            golpes_detector,
            key=lambda golpe: abs(golpe.get("offsetMs", 10**9) - centro),
            default=None,
        )
        if cercano is not None and abs(cercano.get("offsetMs", 10**9) - centro) > 250:
            cercano = None

        ventanas.append({
            "sampleId": f"{tanda.get('tandaId', 'tanda')}-{numero}",
            "label": tanda["label"],
            "recordedAtEpochMs": tanda.get("startedAtEpochMs", 0),
            "playerAlias": tanda.get("playerAlias", "anon"),
            "playerLevel": tanda.get("playerLevel"),
            "hand": tanda.get("hand", "right"),
            "watchWrist": tanda.get("watchWrist", "right"),
            "platform": tanda.get("platform", ""),
            "device": tanda.get("device", ""),
            # Del detector si vio este golpe; si no, honestamente vacío. La ventana
            # vale igual: los rasgos de verdad salen de la señal.
            "heuristicPrediction": (cercano or {}).get("tipo", "unknown"),
            "heuristicConfidence": (cercano or {}).get("confidence", 0.0),
            "heuristicFeatures": (cercano or {}).get("features", {}),
            # Offsets re-centrados en el impacto, como espera el entrenador.
            "offsetsMs": [int(offsets[i] - centro) for i in indices],
            "accel": accel[indices].tolist(),
            "gyro": gyro[indices].tolist(),
            "gravity": gravity[indices].tolist(),
            "impactIndex": int(np.where(indices == pico)[0][0]),
        })
    return ventanas


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("entrada", type=Path, help="JSONL con tandas (mezcla de formatos)")
    parser.add_argument("salida", type=Path, help="JSONL de ventanas por golpe")
    args = parser.parse_args()

    if not args.entrada.exists():
        sys.exit(f"No existe {args.entrada}")

    bloques = 0
    ventanas_total = 0
    viejas = 0
    por_etiqueta: Counter[str] = Counter()
    detector_vio: Counter[str] = Counter()

    with args.salida.open("w", encoding="utf-8") as salida:
        for linea in args.entrada.read_text(encoding="utf-8").splitlines():
            linea = linea.strip()
            if not linea:
                continue
            try:
                registro = json.loads(linea)
            except json.JSONDecodeError:
                continue

            if registro.get("formato", 0) >= 2:
                bloques += 1
                recortes = segmentar(registro)
                ventanas_total += len(recortes)
                por_etiqueta[registro.get("label", "?")] += len(recortes)
                detector_vio[registro.get("label", "?")] += len(registro.get("golpes") or [])
                for ventana in recortes:
                    salida.write(json.dumps(ventana, ensure_ascii=False) + "\n")
            elif "impactIndex" in registro:
                # Formato viejo: ya es una ventana por golpe. Pasa tal cual.
                viejas += 1
                salida.write(linea + "\n")

    print(f"{bloques} tanda(s) crudas → {ventanas_total} ventanas por impacto")
    if viejas:
        print(f"{viejas} ventanas del formato viejo, copiadas tal cual")
    for etiqueta in sorted(por_etiqueta):
        # La comparación que cuenta: cuántos golpes encontró la señal contra cuántos
        # vio el detector en vivo. Si la primera cifra es mayor, el detector se estaba
        # dejando golpes — y ahora están recuperados en vez de perdidos.
        print(
            f"  {etiqueta:18s} {por_etiqueta[etiqueta]:4d} por impacto · "
            f"{detector_vio[etiqueta]:4d} los vio el detector en vivo"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Entrena el bosque de golpes y lo escribe como código Kotlin y Swift.

Uso:

    pip install numpy scikit-learn
    python3 tools/exportar_modelo.py muestras.jsonl

Escribe `ModeloEntrenado.kt` y `ModeloEntrenado.swift` en su sitio de cada core, con los
mismos números en los dos. Lo lanza el workflow `entrenar-modelo.yml` desde el móvil.

**Por qué código y no Core ML / TFLite.** Dos runtimes distintos pueden dar respuestas
distintas al mismo golpe, y eso no hay quien lo depure sin los dos relojes delante. Con
tablas de números, la aritmética son cuatro líneas por lenguaje y los números son
literalmente los mismos. Además se prueba en Kotlin como todo lo demás y no añade peso
de runtime a dos apps que ya pesan.

**Por qué solo nueve rasgos.** El modelo come exactamente los `ShotFeatures` que el reloj
ya calcula para cada golpe. Comer la ventana cruda daría más señal, pero obligaría a
reimplementar la extracción en Kotlin, en Swift y aquí *sin poder comprobar que las tres
dan lo mismo*: una discrepancia ahí no se ve, solo empeora los números sin decir por qué.

**La cifra que manda es la de leave-one-player-out.** Si los golpes de la misma persona
caen a los dos lados de la partición, el modelo memoriza a la persona y la precisión que
mides no se parece a la que verás con alguien nuevo. Por eso este script se niega a
exportar si no gana a la heurística en esa validación: un modelo que no mejora lo que ya
hay solo añade una caja negra.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path

try:
    import numpy as np
    from sklearn.ensemble import RandomForestClassifier
    from sklearn.metrics import accuracy_score
except ImportError:
    sys.exit("Faltan dependencias. Instálalas con:\n\n    pip install numpy scikit-learn\n")


# El contrato con `ModeloDeGolpes.RASGOS` en los dos cores. El orden importa: si cambia
# aquí y no allí, el modelo lee los números cambiados de sitio y falla en silencio.
RASGOS = [
    "sweptAngleDeg",
    "peakGyroRadS",
    "elevationDeg",
    "axialRotationRadS",
    "swingDurationMs",
    "peakElevationDeg",
    "prepElevationDeg",
    "peakAxialRotationRadS",
    "elevationDropDeg",
]

# Nombres de los tipos tal como se serializan en el JSONL y como se llaman en los cores.
WIRE_A_KOTLIN = {
    "forehand": "FOREHAND",
    "backhand": "BACKHAND",
    "forehandVolley": "FOREHAND_VOLLEY",
    "backhandVolley": "BACKHAND_VOLLEY",
    "bandeja": "BANDEJA",
    "vibora": "VIBORA",
    "smash": "SMASH",
    "serve": "SERVE",
}
WIRE_A_SWIFT = {
    "forehand": "forehand",
    "backhand": "backhand",
    "forehandVolley": "forehandVolley",
    "backhandVolley": "backhandVolley",
    "bandeja": "bandeja",
    "vibora": "vibora",
    "smash": "smash",
    "serve": "serve",
}

# El bosque se queda pequeño a propósito: es código que va dentro de dos apps y que
# alguien tiene que poder abrir y leer. 25 árboles de profundidad 6 caben en unas mil
# líneas de tabla y ya separan lo que los umbrales no pueden.
ARBOLES = 25
PROFUNDIDAD = 6
MIN_HOJA = 5


def cargar(path: Path) -> tuple[list[list[float]], list[str], list[str], list[str]]:
    """Devuelve (vectores, etiquetas, jugadores, predicción de la heurística)."""
    vectores: list[list[float]] = []
    etiquetas: list[str] = []
    jugadores: list[str] = []
    heuristica: list[str] = []

    for linea in path.read_text(encoding="utf-8").splitlines():
        linea = linea.strip()
        if not linea:
            continue
        try:
            registro = json.loads(linea)
            rasgos = registro["heuristicFeatures"]
        except (json.JSONDecodeError, KeyError, TypeError):
            continue
        etiqueta = registro.get("label")
        if etiqueta not in WIRE_A_KOTLIN:
            continue
        # Los ausentes entran como 0, igual que en el reloj: `ModeloDeGolpes.vectorDe`.
        vectores.append([float(rasgos.get(nombre) or 0.0) for nombre in RASGOS])
        etiquetas.append(etiqueta)
        jugadores.append(registro.get("playerAlias") or "anon")
        heuristica.append(registro.get("heuristicPrediction") or "unknown")

    return vectores, etiquetas, jugadores, heuristica


def bosque() -> RandomForestClassifier:
    return RandomForestClassifier(
        n_estimators=ARBOLES,
        max_depth=PROFUNDIDAD,
        min_samples_leaf=MIN_HOJA,
        random_state=0,
        n_jobs=-1,
    )


def validar_dejando_fuera(X, y, jugadores, heuristica) -> tuple[float, float]:
    """Acierto del modelo y de la heurística, dejando fuera a un jugador entero.

    Es la única cifra que predice cómo se va a portar con alguien nuevo. Con un solo
    jugador no hay validación posible y se devuelve 0: mejor un cero honesto que un 95%
    que solo dice que el modelo se ha aprendido una muñeca.
    """
    distintos = sorted(set(jugadores))
    if len(distintos) < 2:
        return 0.0, 0.0

    ciertos: list[str] = []
    predichos: list[str] = []
    heuristicos: list[str] = []
    for fuera in distintos:
        train = [i for i, p in enumerate(jugadores) if p != fuera]
        test = [i for i, p in enumerate(jugadores) if p == fuera]
        if not train or not test:
            continue
        modelo = bosque()
        modelo.fit(X[train], [y[i] for i in train])
        predichos.extend(modelo.predict(X[test]))
        ciertos.extend(y[i] for i in test)
        heuristicos.extend(heuristica[i] for i in test)
        print(f"  sin '{fuera}': {accuracy_score([y[i] for i in test], modelo.predict(X[test])):.1%}")

    if not ciertos:
        return 0.0, 0.0
    return accuracy_score(ciertos, predichos), accuracy_score(ciertos, heuristicos)


def aplanar(modelo: RandomForestClassifier, clases: list[str]) -> dict:
    """Convierte el bosque de sklearn en las tablas que leen los cores."""
    rasgo: list[int] = []
    umbral: list[float] = []
    izquierda: list[int] = []
    derecha: list[int] = []
    hoja: list[int] = []
    raices: list[int] = []

    indice_de_clase = {c: i for i, c in enumerate(clases)}

    for arbol in modelo.estimators_:
        t = arbol.tree_
        base = len(rasgo)
        raices.append(base)
        for nodo in range(t.node_count):
            es_hoja = t.children_left[nodo] == -1
            if es_hoja:
                # La hoja vota una sola clase, no una distribución: el bosque entero ya
                # da la distribución al contar votos, y guardar 8 números por hoja
                # multiplicaría por ocho el tamaño del fichero generado para nada.
                ganadora = modelo.classes_[int(np.argmax(t.value[nodo][0]))]
                rasgo.append(-1)
                umbral.append(0.0)
                izquierda.append(-1)
                derecha.append(-1)
                hoja.append(indice_de_clase[ganadora])
            else:
                rasgo.append(int(t.feature[nodo]))
                umbral.append(float(t.threshold[nodo]))
                izquierda.append(base + int(t.children_left[nodo]))
                derecha.append(base + int(t.children_right[nodo]))
                hoja.append(-1)

    return {
        "raices": raices,
        "rasgo": rasgo,
        "umbral": umbral,
        "izquierda": izquierda,
        "derecha": derecha,
        "hoja": hoja,
    }


def lista(valores, por_linea=20, sufijo="") -> str:
    trozos = [f"{v}{sufijo}" for v in valores]
    lineas = [
        "        " + ", ".join(trozos[i : i + por_linea])
        for i in range(0, len(trozos), por_linea)
    ]
    return ",\n".join(lineas)


CABECERA = """// GENERADO por tools/exportar_modelo.py — no editar a mano.
//
// Entrenado con {muestras} golpeos etiquetados de {jugadores} jugador(es).
// Acierto dejando fuera a un jugador entero: {acierto:.1%} (la heurística: {heuristica:.1%}).
// Árboles: {arboles}, profundidad máxima {profundidad}.
//
// Para regenerarlo: Actions → «Entrenar el clasificador» → Run workflow.
"""


def escribir_kotlin(path: Path, tablas: dict, clases: list[str], meta: dict) -> None:
    cuerpo = CABECERA.format(**meta) + f"""
package com.risingpadel.core.detection

import com.risingpadel.core.model.ShotType

object ModeloEntrenado {{

    val actual: ModeloDeGolpes? = ModeloDeGolpes(
        clases = listOf(
{lista([f"ShotType.{WIRE_A_KOTLIN[c]}" for c in clases], por_linea=4)}
        ),
        raices = intArrayOf(
{lista(tablas["raices"])}
        ),
        rasgo = intArrayOf(
{lista(tablas["rasgo"])}
        ),
        umbral = floatArrayOf(
{lista([round(v, 4) for v in tablas["umbral"]], por_linea=10, sufijo="f")}
        ),
        izquierda = intArrayOf(
{lista(tablas["izquierda"])}
        ),
        derecha = intArrayOf(
{lista(tablas["derecha"])}
        ),
        hoja = intArrayOf(
{lista(tablas["hoja"])}
        ),
        muestras = {meta["muestras"]},
        aciertoFuera = {meta["acierto"]:.4f}f,
    )

    const val MIN_VOTOS = 0.6f
}}
"""
    path.write_text(cuerpo, encoding="utf-8")


def escribir_swift(path: Path, tablas: dict, clases: list[str], meta: dict) -> None:
    cuerpo = CABECERA.format(**meta) + f"""
import Foundation

public enum ModeloEntrenado {{

    public static let actual: ModeloDeGolpes? = ModeloDeGolpes(
        clases: [
{lista([f".{WIRE_A_SWIFT[c]}" for c in clases], por_linea=4)}
        ],
        raices: [
{lista(tablas["raices"])}
        ],
        rasgo: [
{lista(tablas["rasgo"])}
        ],
        umbral: [
{lista([round(v, 4) for v in tablas["umbral"]], por_linea=10)}
        ],
        izquierda: [
{lista(tablas["izquierda"])}
        ],
        derecha: [
{lista(tablas["derecha"])}
        ],
        hoja: [
{lista(tablas["hoja"])}
        ],
        muestras: {meta["muestras"]},
        aciertoFuera: {meta["acierto"]:.4f}
    )

    public static let minVotos: Float = 0.6
}}
"""
    path.write_text(cuerpo, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("dataset", type=Path, help="JSONL con las tandas etiquetadas")
    parser.add_argument("--raiz", type=Path, default=Path("."), help="raíz del repositorio")
    parser.add_argument(
        "--forzar",
        action="store_true",
        help="exporta aunque no gane a la heurística (para probar la cañería)",
    )
    args = parser.parse_args()

    if not args.dataset.exists():
        sys.exit(f"No existe {args.dataset}")

    vectores, etiquetas, jugadores, heuristica = cargar(args.dataset)
    if not vectores:
        sys.exit("El fichero no tiene ninguna muestra utilizable")

    print(f"{len(vectores)} golpeos etiquetados")
    for jugador, n in sorted(Counter(jugadores).items()):
        print(f"  {jugador:18s} {n:5d}")
    for tipo, n in sorted(Counter(etiquetas).items()):
        print(f"  {tipo:18s} {n:5d}")

    X = np.asarray(vectores, dtype=float)
    print("\nValidación dejando fuera a un jugador entero:")
    acierto, acierto_heuristica = validar_dejando_fuera(X, etiquetas, jugadores, heuristica)
    print(f"\nModelo: {acierto:.1%}   Heurística: {acierto_heuristica:.1%}")

    if len(set(jugadores)) < 2:
        print(
            "\nUn solo jugador: no hay validación posible y un modelo entrenado con una\n"
            "sola muñeca aprende esa muñeca. Graba tandas de más gente antes de exportar."
        )
        if not args.forzar:
            return 1

    if acierto <= acierto_heuristica and not args.forzar:
        print(
            "\nEl modelo NO gana a la heurística, así que no se exporta. Un modelo que no\n"
            "mejora lo que ya hay solo añade una caja negra que no sabe explicarse."
        )
        return 1

    clases = sorted(set(etiquetas))
    modelo = bosque()
    modelo.fit(X, etiquetas)
    tablas = aplanar(modelo, clases)
    meta = {
        "muestras": len(vectores),
        "jugadores": len(set(jugadores)),
        "acierto": acierto,
        "heuristica": acierto_heuristica,
        "arboles": ARBOLES,
        "profundidad": PROFUNDIDAD,
    }

    kotlin = args.raiz / "android/core/src/main/kotlin/com/risingpadel/core/detection/ModeloEntrenado.kt"
    swift = args.raiz / "ios/Packages/PadelCore/Sources/PadelCore/Detection/ModeloEntrenado.swift"
    escribir_kotlin(kotlin, tablas, clases, meta)
    escribir_swift(swift, tablas, clases, meta)
    print(f"\nEscritos:\n  {kotlin}\n  {swift}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

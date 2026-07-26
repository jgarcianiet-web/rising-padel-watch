# Pendiente

Cosas decididas pero **no** incluidas en la primera iteración. Cada entrada dice qué
falta y qué habría que tocar, para poder retomarla sin rehacer el análisis.

## 1. Marcador de partido en el reloj

**Qué:** poder llevar el marcador del partido desde el reloj, de forma intuitiva y
sencilla, y que el resultado acabe en la app de liga junto con los golpeos.

Hoy el reloj mide *esfuerzo* (golpeos, FC, calorías) pero no sabe quién va ganando. Es
la pieza que convierte la app en algo que se usa **durante** el partido y no solo
después, y es lo que enlaza de verdad con la liga: la liga quiere resultados.

**Lo importante es la interacción, no el modelo de datos.** Entre punto y punto hay 3-5
segundos y el jugador tiene una pala en la mano: cualquier cosa que exija mirar la
pantalla y apuntar bien está mal diseñada. Dirección propuesta:

- Toque en la mitad superior de la pantalla = punto para nosotros; mitad inferior =
  punto para ellos. Dos zonas grandes, sin botones pequeños.
- Deshacer con un gesto claro (deslizar) — los errores al puntuar son constantes.
- El reloj calcula solo el resto: 15/30/40, deuce y ventaja, juegos, sets, tie-break,
  cambio de saque y cambio de pista. El jugador solo dice quién ganó el punto.
- Haptics en vez de texto para confirmar: se nota sin mirar.
- Punto de oro / ventaja configurable, y sets a 3 o a 1, porque las ligas varían.

**Dónde tocaría:**

- `core`: un `ScoreEngine` puro (estado del marcador + transiciones + deshacer), con
  tests unitarios de las reglas — es lógica pura y se puede verificar sin dispositivo,
  igual que el detector de golpeos. Duplicado en Swift y Kotlin como el resto del core.
- `PadelSession`: bloque nuevo `score` (sets, juegos, resultado, quién sacaba).
- `docs/api-contract.md` + `openapi.yaml`: campo `score` y subir `schemaVersion` a 2.
  El servidor debe seguir aceptando sesiones v1 sin marcador.
- Reloj (watchOS y Wear OS): pantalla de marcador como vista principal durante el
  partido, con el conteo de golpeos en segundo plano.
- Móvil: mostrar el resultado en el detalle de sesión y en el vínculo con el partido de
  la liga.

**Decisión pendiente:** si el marcador es opcional (sesión "solo entreno" sin marcador)
o si toda sesión lleva marcador. Propuesta: opcional, se activa al empezar la sesión.

## 2. Clasificador de golpeos entrenado

La v1 es heurística (ver `shot-detection.md`). El camino a un modelo aprendido está
descrito ahí: grabar ventanas etiquetadas, entrenar, exportar a Core ML / TFLite y
sustituir **solo** `ShotClassifier`.

## 3. Validación de signos en pista

El convenio de signos del giróscopo (`DetectorConfig.invertAxialSign`) hay que
validarlo una vez por plataforma con golpeos reales: si las derechas salen como revés,
se invierte la bandera. Está aislado en una sola constante justamente para esto.

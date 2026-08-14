# Detección y clasificación de golpeos

Spec del algoritmo implementado en `android/core` (Kotlin) y `ios/Packages/PadelCore`
(Swift). Las dos implementaciones son equivalentes y comparten la misma batería de
tests, para que un golpeo detectado en Apple Watch y en Wear OS cuente igual.

## Entrada

Muestras a **50 Hz** (`SAMPLE_RATE_HZ`) con:

| Campo | Unidad | Origen iOS | Origen Android |
|---|---|---|---|
| `timestampMs` | ms monótonos | `CMDeviceMotion.timestamp` | `SensorEvent.timestamp` |
| `accel` (x,y,z) | g, **sin gravedad** | `userAcceleration` | `TYPE_LINEAR_ACCELERATION` / 9.81 |
| `gyro` (x,y,z) | rad/s | `rotationRate` | `TYPE_GYROSCOPE` |
| `gravity` (x,y,z) | g | `gravity` | `TYPE_GRAVITY` / 9.81 |

50 Hz es el compromiso: a 25 Hz se pierden picos de impacto cortos (un smash dura
~30 ms), y a 100 Hz el consumo de batería sube sin ganar golpeos detectados en las
pruebas. Los ejes se usan siempre en el marco del dispositivo; la orientación de la
muñeca se resuelve con el vector de gravedad, no asumiendo cómo lleva el reloj.

## Detección

El golpeo es un patrón de **carga → aceleración → impacto → frenada**:

```
|gyro|   ─────╱▔▔▔╲──────      swing: la muñeca rota
              ↑    ↑
              │    └── impacto: pico corto y alto en |accel|
              └────── inicio del swing
|accel|  ──────────╱▎╲────
```

Máquina de estados por muestra:

1. **IDLE** → **SWINGING** cuando `|gyro| > SWING_ONSET` (3.5 rad/s) durante al menos
   2 muestras consecutivas. Se anota `swingStartMs` y se empieza a integrar el ángulo
   barrido.

   3.5 rad/s deja fuera el braceo de correr y de colocarse (≈2 rad/s) pero no una volea
   bloqueada, que es el golpeo con menos velocidad angular de todos.
2. En **SWINGING** se acumula `sweptAngleRad += |gyro| * dt` y se guardan los máximos
   de `|gyro|` y `|accel|`.
3. **Impacto** cuando `|accel| > IMPACT_G` (3.2 g) y esa muestra es un máximo local
   (mayor que la anterior y que la siguiente). El instante del impacto es el de esa
   muestra.
4. Tras el impacto se cierra el golpeo y se entra en **REFRACTORY** durante
   `REFRACTORY_MS` (320 ms). En pádel el intercambio más rápido en la red ronda los
   400 ms entre golpeos propios, así que 320 ms no descarta golpeos reales pero sí
   elimina el rebote del propio impacto y la vibración de la pala.
5. Si en **SWINGING** pasan más de `MAX_SWING_MS` (900 ms) sin impacto, se descarta:
   era movimiento de desplazamiento, no un golpeo.
6. También se descarta si `|gyro|` cae por debajo de `SWING_ONSET * 0.5` antes de
   registrar impacto (amago o preparación sin golpear).

### Falsos positivos que filtra

- **Correr / cambiar de posición**: genera `|accel|` alto pero `|gyro|` bajo y sin pico
  local nítido; no supera la condición conjunta de swing + impacto.
- **Aplaudir o chocar la pala**: pico de `|accel|` sin swing previo → se ignora porque
  la máquina está en IDLE, no en SWINGING.
- **Botar la pelota antes de sacar**: swing corto de baja energía; el umbral de
  `|gyro|` pico (`MIN_PEAK_GYRO`, 5.5 rad/s) lo descarta.

Referencia de velocidad angular de muñeca para fijar estos umbrales: una volea ronda
5-10 rad/s, una derecha 15-25 y un smash 25-35.

## Clasificación

Al cerrar un golpeo se calculan cuatro rasgos y se decide el tipo. Todo se normaliza
por `hand` (mano de juego) y `watchWrist` (muñeca del reloj), porque el signo de la
rotación se invierte si el reloj va en la muñeca contraria a la que empuña.

| Rasgo | Cómo se calcula |
|---|---|
| `elevation` | **Mediana** de la elevación del antebrazo sobre la horizontal a lo largo del swing: la postura del golpe |
| `peakElevation` | **Percentil 80** de esa misma serie: hasta dónde subió el brazo. Es el rasgo que decide si el golpeo es alto |
| `sweptAngleDeg` | Integral de `|gyro|` durante el swing, en grados |
| `axialRotation` | Componente de `gyro` sobre el eje longitudinal del antebrazo, con signo, promediada en los 200 ms previos al impacto |
| `peakGyro` | Máximo de `|gyro|` en el swing |

Árbol de decisión (umbrales de fábrica; los números vivos están en `DetectorConfig`):

```
peakElevation > 14°  ──► peakGyro > 14 rad/s ──► smash
                     ├─► peakElevation ≥ 44° ──► bandeja      (o, calibrado por jugador,
                     └─► resto               ──► vibora        axial ≥ X ► vibora)

peakElevation ≤ 14°  ──► |axial| ≥ 5.5 y sweptAngle ≥ 270°            ──► serve
                     ├─► prep ≥ +8°, axial ≥ +3.5 e impacto ≥ −20°    ──► serve (armado)
                     ├─► sweptAngle < 50°, o < 310° con |axial| < 4   ──► volea (lado por signo)
                     └─► resto                                        ──► fondo (lado por signo)
```

La segunda firma del saque —**el brazo armado en alto con el impacto a la cintura**—
salió de la tanda de 40 en bloques (ago 2026): la firma clásica (mucha pronación, barrido
completo) solo pescaba uno de cinco saques reales; el gesto de armar (+10..+27° de
preparación) los compartían los cinco y ningún otro golpe bajo de las dos tandas limpias.

Esa misma tanda enseñó que **las fronteras de elevación son del jugador, no del
deporte**: sus golpes altos picaron +4..+31° cuando la tanda anterior daba +15..+56, y
sus bandejas iban POR DEBAJO de sus víboras en altura pero limpiamente separadas por
pronación (planas contra cortadas). Por eso la puerta de golpe alto
(`overheadElevationDeg`) y la frontera bandeja/víbora por axial (`viboraAxialRadS`) son
calibrables por jugador, y el calibrador solo se queda cada umbral si **no empeora** el
acierto sobre las tandas etiquetadas del propio jugador (`ThresholdCalibrator`).

### Por qué la elevación se mide sobre el swing entero

Esto costó tres intentos fallidos en pista (ago 2026) y conviene no repetirlos:

| Cómo se medía | Qué pasó |
|---|---|
| Gravedad de la **muestra del impacto** | Con 5-10 g de golpe y 15+ rad/s, el filtro de fusión del sistema se descuadra decenas de grados. Una tanda de 10 derechas midió **+41..+77°** y salió clasificada como golpes altos |
| **Media** de la gravedad en los 200 ms previos | La media se toma sobre un arco de 100-200° de swing: promedia vectores que apuntan a sitios distintos. Una tanda de 10 víboras midió **−20..+56°** |
| **Percentil 80** de la elevación muestra a muestra | El actual. La pregunta que separa un golpe alto no es "cómo estaba el brazo en el impacto" sino **si la mano pasó por encima del hombro** |

Lo importante del segundo caso: los rangos de las dos tandas (derechas +41..+77, víboras
−20..+56) **se solapan por completo**. Cuando eso pasa, ningún umbral separa las clases y
mover el número es ajustar ruido: hay que arreglar la medida, no la frontera.

Se usa el percentil 80 y no el máximo porque un solo pico del filtro de fusión no puede
convertir una derecha en una bandeja; con dos muestras malas de quince, el percentil ni
se entera. Hay pruebas de esto en `ShotDetectorTest`.

El umbral de víbora (9 rad/s de rotación axial) también sale de pista: la pronación
natural de una derecha plana ya promedia 6-11 rad/s, así que con el valor original (5)
cualquier golpe alto salía víbora.

Los tres golpes altos que no son saque se separan por lo que los define en pista, y el
orden de las preguntas importa:

- **Smash** = violencia. El pico de giro va por encima de todo lo demás (25-35 rad/s
  frente a 12-20 de una bandeja). Se pregunta primero porque un smash suele llevar
  también algo de efecto, y si se preguntara antes por la rotación axial se colaría como
  víbora.
- **Víbora** = efecto. Rotación axial alta sin la violencia del remate: el corte lateral
  es su seña de identidad.
- **Bandeja** = control. Plana y contenida; es el resto de golpes altos.

Estos dos umbrales (`smashPeakGyroRadS`, `viboraAxialRadS`) son los más finos de todo el
clasificador — bandeja y víbora son vecinas de verdad — y los primeros candidatos a
mejorar con el clasificador entrenado.

`axialRotation > 0` significa lado de derecha. El signo depende de dos cosas y el
clasificador las normaliza por separado:

- **`watchWrist`** cambia hacia dónde apunta físicamente el eje `+Y` del dispositivo:
  en la muñeca izquierda el reloj va girado 180° respecto al brazo, así que el eje
  codo → mano es `-Y` en vez de `+Y`.
- **`hand`** invierte el signo porque un jugador zurdo es la imagen especular de uno
  diestro, y una imagen especular invierte la rotación sobre el eje del antebrazo.

> El convenio de signos del giróscopo **hay que validarlo en pista una vez por
> plataforma**: juega diez derechas y diez reveses y mira el desglose por tipo. Si salen
> cambiados, la corrección es `DetectorConfig.invertAxialSign = true`. Está aislado en
> una sola constante justamente para esto.

El saque se separa del resto de golpeos por encima de la cabeza por el swing completo:
un saque de pádel barre mucho más ángulo que una bandeja o una volea alta. No se usa
"primer golpeo del punto" porque el reloj no sabe cuándo empieza un punto.

## Confianza

Cada margen es la distancia normalizada del rasgo a su umbral de decisión: un golpeo
justo en la frontera da margen ~0, uno claramente dentro da ~1.

**Golpeos bajos** (derecha, revés, voleas):

```
confidence = 0.35 * margenSwept + 0.35 * margenAxial + 0.30 * margenElevation
```

**Golpeos altos** (bandeja, smash, saque):

```
confidence = 0.50 * margenSwept + 0.50 * margenElevation
```

La rotación axial se cae de la fórmula en la rama alta porque **no participa en la
decisión**: ahí solo se separa saque de bandeja, y eso se decide por ángulo barrido. Si
siguiera pesando, un smash limpio sin apenas rotación axial saldría penalizado por un
rasgo que nadie miró.

En esa misma rama el margen de `sweptAngle` se normaliza contra **medio** umbral
(`SERVE_SWEPT / 2`) y no contra el umbral entero: una bandeja de 140° está lejos de un
saque en términos prácticos, aunque en valor absoluto se quede a menos de la mitad de
los 220°.

Si `confidence < MIN_CONFIDENCE` (0.45) el tipo se reporta como `unknown`, pero **el
golpeo sigue contando** en el total: es preferible "412 golpeos, 2 sin clasificar" que
perder golpeos reales.

## Intensidad

- `impactG` = pico de `|accel|` en g.
- `racketSpeedKmh` = `peakGyro * ARM_LEVER_M * 3.6`, con `ARM_LEVER_M = 0.65 m`
  (distancia aproximada muñeca → centro del cordaje sumando el antebrazo en el giro).
  Es una **estimación**, no una medida: el error crece si el jugador golpea con mucho
  desplazamiento del cuerpo, porque la velocidad del centro de masa no la ve el
  giróscopo. Sirve para comparar golpeos entre sí y seguir la evolución del jugador, no
  como velocímetro absoluto.

## Calibración

Los umbrales por defecto (`DetectorConfig.default`) están fijados para un jugador
adulto de nivel medio. `DetectorConfig` es un objeto de datos con todos los umbrales,
así que se pueden ajustar por usuario. Vías previstas:

- **Sensibilidad** en ajustes (baja/media/alta) escala `IMPACT_G` y `MIN_PEAK_GYRO`
  ±25%.
- Si el jugador corrige el conteo al final de una sesión, ese delta queda registrado
  para poder ajustar umbrales más adelante.

## Camino a un clasificador aprendido

La heurística es la v1 deliberadamente: es explicable, no necesita dataset y se ajusta
con dos constantes. Para mejorarla, el orden razonable es:

1. Grabar sesiones etiquetadas. **Ya implementado**: ver
   [`training-data.md`](./training-data.md).
2. Entrenar un clasificador pequeño (un árbol de decisión con gradient boosting sobre
   los mismos rasgos, o una CNN 1D sobre la ventana cruda).
3. Exportar a Core ML / TFLite y sustituir **solo** `ShotClassifier`, dejando intacta la
   detección: la separación entre `ShotDetector` (¿hubo golpeo?) y `ShotClassifier`
   (¿de qué tipo?) existe justamente para poder cambiar la segunda pieza sin tocar la
   primera.

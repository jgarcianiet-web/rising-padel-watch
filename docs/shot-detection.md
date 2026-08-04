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
| `elevation` | Ángulo entre la gravedad **promediada en los 200 ms previos al impacto** (sin entrar en la preparación) y el eje del antebrazo. > 60° hacia arriba = brazo por encima del hombro. No se usa la muestra del impacto: con 5-10 g y 15+ rad/s la estimación de gravedad del sistema se va decenas de grados — en pista (ago 2026) las derechas planas medían +41..+77° con la muestra suelta y salían clasificadas como golpes altos |
| `sweptAngleDeg` | Integral de `|gyro|` durante el swing, en grados |
| `axialRotation` | Componente de `gyro` sobre el eje longitudinal del antebrazo, con signo, promediada en los 200 ms previos al impacto |
| `peakGyro` | Máximo de `|gyro|` en el swing |

Árbol de decisión:

```
elevation > 60°  ──► sweptAngle > 220° y peakGyro > 18 rad/s ──► serve
                 ├─► peakGyro > 24 rad/s                      ──► smash
                 ├─► |axialRotation| > 9 rad/s                ──► vibora
                 └─► resto                                    ──► bandeja

elevation ≤ 60°  ──► sweptAngle < 70°  ──► axialRotation > 0 ? forehandVolley : backhandVolley
                 └─► sweptAngle ≥ 70°  ──► axialRotation > 0 ? forehand       : backhand
```

Los umbrales de elevación (60°) y de víbora (9 rad/s) salen de la validación en pista:
una derecha plana promedia 40-55° de elevación en la ventana previa y 6-11 rad/s de
axial por la pronación natural del brazo. Con los valores antiguos (45° y 5) una tanda
de 10 derechas salía como 6 víboras.

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

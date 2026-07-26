# Marcador del partido

Reglas implementadas en `ScoreEngine` (`core/score/MatchScore.kt` en Kotlin,
`PadelCore/Score/MatchScore.swift` en Swift) y diseño de la interacción en el reloj.

Es lógica pura, sin nada de UI ni de plataforma, así que se verifica con tests: 41 en
Kotlin y los equivalentes en Swift.

## Reglas

| Concepto | Regla |
|---|---|
| Puntos | 0 → 15 → 30 → 40 → juego |
| 40-40 con punto de oro | El siguiente punto decide. **Por defecto** |
| 40-40 sin punto de oro | Ventaja: hay que sacar dos puntos seguidos |
| Set | A 6 juegos con 2 de diferencia (6-4 vale, 6-5 no) |
| 6-6 | Tie-break a 7 puntos con 2 de diferencia |
| Partido | Al mejor de 3 sets (configurable a 1) |
| Saque | Alterna en cada juego |
| Saque en tie-break | Uno saca 1 punto, luego se alterna cada 2 |
| Set siguiente al tie-break | Resta primero quien abrió el tie-break |
| Cambio de pista | Tras cada juego impar del set; en tie-break, cada 6 puntos |

El **punto de oro viene activado por defecto** porque es lo que se juega en la mayoría de
ligas amateur y en el circuito profesional. `ScoreRules` lo hace configurable junto con
los sets a ganar, porque cada liga tiene lo suyo.

La rotación del saque en el tie-break (1, luego 2 y 2) no es un capricho: existe para que
cada bando saque siempre desde el mismo lado de la pista.

## Interacción en el reloj

El diseño lo dicta una restricción concreta: **entre punto y punto hay 3-5 segundos y el
jugador tiene una pala en la mano**. Cualquier cosa que exija mirar la pantalla y apuntar
con precisión está mal.

- **Media pantalla superior = punto nuestro. Media inferior = punto suyo.** Dos zonas
  enormes, sin botones que acertar. Se puede pulsar sin mirar.
- **Mantener pulsado = deshacer.** Puntuar mal es constante y sin deshacer el marcador se
  vuelve inservible en cuanto pasa una vez.
- **Vibración distinta** para punto anotado, juego, set y deshacer: se nota sin mirar la
  pantalla, que es justo lo que hace falta cuando estás colocándote para el siguiente
  punto.
- El reloj calcula **todo** lo demás. El jugador solo dice quién ganó el punto.

### Por qué mantener pulsado y no deslizar

En el diseño inicial el gesto para deshacer era deslizar. No se puede: en Wear OS el
deslizamiento horizontal es el gesto de sistema para volver atrás, y en watchOS está
tomado por la navegación entre vistas. Robarlo rompe la navegación de la app o directamente
no funciona.

Mantener pulsado está libre en las dos plataformas, no se dispara por accidente con un
toque, y no exige precisión. Es la elección correcta aunque sea menos vistosa.

## Convivencia con el conteo de golpeos

El marcador es **opcional**: se activa al empezar la sesión. Una sesión sin marcador
sigue siendo válida, es el caso del entreno suelto.

Cuando está activo, la pantalla principal del reloj pasa a ser el marcador y el conteo de
golpeos sigue corriendo por debajo. Al terminar, ambos viajan en la misma `PadelSession`.

## Versionado del contrato

El bloque `score` es un campo nuevo en el payload. El versionado tiene una sutileza:

**`schemaVersion` sube a 2 solo cuando la sesión lleva marcador.** Una sesión sin
marcador sigue declarando 1.

El motivo: si se subiera a 2 siempre, una liga que solo entiende v1 empezaría a rechazar
**todas** las sesiones, incluidos los entrenos que no han cambiado en nada. Y si no se
subiera nunca, esa misma liga aceptaría una sesión con resultado y tiraría el marcador en
silencio, que es peor: el usuario creería que su resultado está en la liga cuando no lo
está.

Con este esquema, una liga v1 sigue funcionando para entrenos y **falla de forma visible**
ante una sesión con marcador, que es exactamente cuando hace falta que el usuario se
entere de que su app de liga necesita actualizarse.

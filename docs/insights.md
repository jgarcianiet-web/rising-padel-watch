# Ideas de la sesión

Lo que la app te dice al acabar de jugar: qué pasó en el partido, en qué eres fuerte y qué
entrenar. Vive en `InsightEngine`, duplicado en los dos cores y con tests en Kotlin.

## La regla que lo gobierna todo

**Cada frase sale de una cuenta sobre tus datos, no de un texto genérico.**

```
"En los puntos de 5 golpeos o más tu nivel medio es 4.1 frente a 3.4 en los
 cortos (+21% mejor). Alargar el punto te favorece."
```

Ese consejo se puede comprobar: los dos números están calculados sobre los golpeos de esa
sesión. Un consejo de horóscopo ("sé más paciente en los puntos largos") vale para
cualquiera y no significa nada.

De ahí salen las tres decisiones de diseño:

1. **Umbrales de evidencia.** Una regla que no llega al mínimo no dice nada. Comparar dos
   grupos de cinco golpeos no es un dato, es una anécdota, y presentarlo como conclusión
   es peor que callarse. Preferimos tres ideas sólidas a diez inventadas.
2. **La evidencia se enseña.** Cada idea lleva "sobre N golpeos" debajo. Una conclusión
   sacada de 200 golpeos y otra de 16 no merecen la misma confianza, y esconder la
   diferencia sería vender más certeza de la que hay.
3. **Los umbrales son relativos al jugador.** El pulso al que uno se rompe depende de su
   edad y su forma física, así que la frontera es el pulso medio de **su** sesión, no un
   160 fijo que habría que calibrar por persona.

## Lo que mira

| Idea | De dónde sale | Cuándo aparece |
|---|---|---|
| Sacando vs restando (resultado) | Juegos ganados con el saque en la mano frente a los ganados al resto | 4+ juegos cerrados, 2+ de cada lado |
| Sacando vs restando (golpeo) | Nota media de los golpeos de cada juego, atribuidos por su minuto | 15+ golpeos en cada situación y ≥0.3 de diferencia |
| Puntos largos vs cortos | Los golpeos se agrupan en puntos por el hueco entre ellos (>4 s = punto nuevo) y se compara la nota media | 15+ golpeos en cada grupo y ≥0.3 de diferencia |
| Pulso vs rendimiento | A cada golpeo se le asigna la lectura de pulso vigente y se comparan los que van por encima y por debajo del pulso medio | 6+ lecturas de pulso y 15+ golpeos a cada lado |
| Cómo llegaste al final | Primer tercio contra último tercio de la curva de progreso | 4+ puntos de la curva y ≥0.3 de diferencia |
| Mejor y peor golpe | Nota media por tipo | 8+ golpeos de cada tipo y ≥0.3 de diferencia |
| Regularidad | `consistency` de la estimación de nivel | Por debajo del 60% |
| Falta juego alto | Tipos que no aparecieron en la sesión | 60+ golpeos sin bandeja, víbora ni remate |
| Qué entrenar | El tipo de golpe con peor nota respecto al nivel global | 8+ golpeos de ese tipo |

## Quién saca, y por qué se pregunta

Al empezar un partido el reloj pregunta **quién saca el primer juego**. Es la única
pregunta del partido que no se puede deducir después: el marcador rota el saque solo, pero
solo si sabe por dónde empezar.

Con eso, cada juego cerrado se guarda como `GameRecord(offsetMs, server, winner)` y los
golpeos se atribuyen al juego en el que cayeron. Eso permite separar **sacando** de
**restando**, que en pádel son dos partidos distintos: con el saque en la mano subes a la
red desde el primer golpe, y restando tienes que ganártela. Un jugador que gana el 80% de
sus juegos al saque y el 20% al resto no tiene un problema de golpeo, tiene un problema de
subida — y sin esta separación las dos cosas se mezclan en una media que no dice nada.

Los golpeos posteriores al último juego cerrado no cuentan: pertenecen a un juego sin
terminar del que no se sabe el desenlace.

## La serie de pulso

Para cruzar pulso con rendimiento hace falta saber **cuándo** estuvo alto, no solo su
media. La sesión guarda una lectura por minuto (`health.heartRateSeries`):

- Una por minuto y no todas: con esa resolución ya se ve la meseta de esfuerzo, y una
  sesión de dos horas ocupa 120 números en vez de siete mil.
- Va dentro del bloque de salud, así que **el consentimiento la gobierna igual que al
  resto**: sin él no se mide.

## Dónde encaja un modelo de lenguaje

El motor produce **hechos**: comparaciones con sus números y su nivel de evidencia. Eso es
justo lo que un modelo de lenguaje hace mal —inventar cifras es su fallo más típico— y lo
que un puñado de reglas hace bien.

Redactar a partir de esos hechos es lo contrario: escribir un resumen que suene a
entrenador, encadenar tres ideas en un plan y adaptar el tono es justo lo que el modelo
hace bien. **Ese reparto ya está montado**: el entrenador de la liga vive en la app
(`CoachService.swift`, ver `liga.md`) y su prompt lleva una sección de "hechos medidos
por el reloj" que sale de este motor, con la prohibición explícita de inventar hechos
que no estén en la lista.

Con eso, el modelo no puede inventarse que juegas mejor con el pulso alto: o está en los
hechos o no se dice.

## Cómo añadir una idea

1. Escribe la regla en `InsightEngine` de los dos cores, con su umbral de evidencia.
2. Añade el test en Kotlin: uno que la dispare y **uno que compruebe que no se dispara**
   cuando no hay diferencia real. El segundo importa más que el primero.
3. El texto lleva siempre los dos números que se comparan y el cambio porcentual.

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
| Puntos largos vs cortos | Los golpeos se agrupan en puntos por el hueco entre ellos (>4 s = punto nuevo) y se compara la nota media | 15+ golpeos en cada grupo y ≥0.3 de diferencia |
| Pulso vs rendimiento | A cada golpeo se le asigna la lectura de pulso vigente y se comparan los que van por encima y por debajo del pulso medio | 6+ lecturas de pulso y 15+ golpeos a cada lado |
| Cómo llegaste al final | Primer tercio contra último tercio de la curva de progreso | 4+ puntos de la curva y ≥0.3 de diferencia |
| Mejor y peor golpe | Nota media por tipo | 8+ golpeos de cada tipo y ≥0.3 de diferencia |
| Regularidad | `consistency` de la estimación de nivel | Por debajo del 60% |
| Falta juego alto | Tipos que no aparecieron en la sesión | 60+ golpeos sin bandeja, víbora ni remate |
| Qué entrenar | El tipo de golpe con peor nota respecto al nivel global | 8+ golpeos de ese tipo |

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
hace bien. La app de liga (repositorio `padel`) ya tiene esa integración, y la forma de
juntarlas es pasarle estos hechos como contexto en vez de la sesión cruda.

Con eso, el modelo no puede inventarse que juegas mejor con el pulso alto: o está en los
hechos o no se dice.

## Cómo añadir una idea

1. Escribe la regla en `InsightEngine` de los dos cores, con su umbral de evidencia.
2. Añade el test en Kotlin: uno que la dispare y **uno que compruebe que no se dispara**
   cuando no hay diferencia real. El segundo importa más que el primero.
3. El texto lleva siempre los dos números que se comparan y el cambio porcentual.

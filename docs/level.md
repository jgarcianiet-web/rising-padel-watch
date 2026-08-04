# Nivel técnico

Cada golpeo se puntúa de **1 a 7** —la escala de nivel que se usa en los clubes— y el
nivel de la sesión sale de esas notas.

> **Léelo antes de creerte el número.** Esto es una heurística **sin calibrar**. Las
> bandas de referencia son estimaciones razonadas, no medidas contra jugadores de nivel
> conocido. Sirve para **seguir tu evolución** y para ver qué golpe va por detrás de los
> demás; **no** para decirle a nadie de qué nivel es.

## Qué puede ver el reloj, y qué no

El giróscopo de la muñeca ve la velocidad y la forma del swing. Eso es una parte del
nivel, no el nivel.

| Lo que sí mide | Lo que no ve |
|---|---|
| Velocidad de pala | Dónde cae la bola |
| Amplitud y forma del swing | Colocación en la pista |
| Regularidad entre golpeos | Lectura de la pared |
| Repertorio de golpes usados | Táctica y decisión |
| | Si la bola entró |

Un jugador de nivel 6 con la muñeca lesionada pegando flojo puntuará bajo. Uno que pega
fuerte y falla todas puntuará alto. **El nivel real de pádel se juega en la cabeza y en
los pies**, y el reloj no los ve.

## Nota de un golpeo

Dos componentes, con la velocidad pesando el 65%:

```
nota = 0.65 * velocidad + 0.35 * amplitud   →   escalado a 1..7
```

**Velocidad**: dónde cae la velocidad estimada de pala dentro de la banda de ese tipo de
golpe. Cada tipo tiene la suya, porque una volea de nivel 7 va mucho más lenta que un
smash de nivel 3:

| Golpe | Nivel 1 | Nivel 7 |
|---|---|---|
| Derecha | 28 km/h | 65 km/h |
| Revés | 26 km/h | 60 km/h |
| Volea de derecha | 10 km/h | 26 km/h |
| Volea de revés | 10 km/h | 24 km/h |
| Bandeja | 32 km/h | 58 km/h |
| Víbora | 38 km/h | 68 km/h |
| Smash | 50 km/h | 95 km/h |
| Saque | 32 km/h | 72 km/h |

**Amplitud**: cuánto se acerca el ángulo barrido a la referencia del golpe. Aquí hay una
asimetría que importa:

- En **derecha, revés, bandeja y saque**, más recorrido es mejor: un swing corto es un
  golpe apurado.
- En **las voleas es al revés**. La volea se bloquea, no se golpea. Un swing largo en la
  red es precisamente el error que separa a un jugador de nivel bajo de uno de nivel alto,
  así que pasarse del ángulo de referencia **resta**.

Un golpeo que el clasificador no supo identificar, o que clasificó con poca confianza,
**no puntúa**: puntuar un golpe que no se sabe qué es sería inventar.

## Nivel de la sesión

```
nivel = media_por_tipo - penalización_regularidad + bonificación_repertorio
```

**La media es por tipo de golpe, no por golpeo suelto.** Si se hiciera por golpeo, una
sesión con 200 derechas y 5 voleas sería "el nivel de derecha del jugador" con otro
nombre.

**Regularidad** (resta hasta 0,8 niveles). En pádel el nivel *es* regularidad: dos
jugadores con la misma derecha máxima no son el mismo nivel si uno la repite treinta veces
y el otro una de cada cinco. Se mide **dentro de cada tipo**, porque que una volea vaya más
lenta que un smash es lo normal, no irregularidad del jugador.

**Repertorio** (suma hasta 0,4 niveles). Cuántos tipos de golpe usa con soltura. **Solo
suma, nunca resta**: una sesión de solo derechas no significa que el jugador no sepa
volear, y penalizarla sería castigar entrenar.

Por debajo de **30 golpeos puntuables** el nivel se marca como no fiable. Se sigue
enseñando, con aviso: quien ha dado 20 golpes prefiere ver una estimación avisada que un
hueco.

## Dónde se ve

- **En el reloj**, al terminar: una línea con el nivel.
- **En el móvil**, en el detalle de la sesión: el nivel, la regularidad, el repertorio y
  **el desglose por golpe**, que es lo accionable. El número global dice poco; saber que el
  revés va dos puntos por debajo de la derecha dice qué entrenar.
- **En la liga**, en el bloque `level` del payload. Ver [`api-contract.md`](./api-contract.md).

## Es derivado, no guardado

`PadelSession.level` es una propiedad calculada de los golpeos, no un campo persistido.
Dos consecuencias buenas: no puede quedar desincronizada, y **afinar las bandas recalcula
el nivel de todas las sesiones ya grabadas** sin migrar nada. Mientras el modelo esté sin
calibrar, eso es exactamente lo que hace falta.

## Cómo calibrarlo

Es el mismo problema que el clasificador entrenado, y se resuelve con los mismos datos
(ver [`training-data.md`](./training-data.md)) más un dato extra: **el nivel real de cada
jugador**.

1. Graba sesiones de 8-10 jugadores cuyo nivel de club conozcas, repartidos por la escala.
   No vale que sean todos del mismo nivel: sin rango no hay nada que ajustar.
2. Compara el nivel estimado con el real. Mira sobre todo el **orden**: si los ordena bien
   aunque el número esté desplazado, solo hay que mover las bandas; si los ordena mal, el
   problema es el modelo.
3. Ajusta `LevelConfig`: primero las bandas de velocidad, que es donde está el 65% del peso.
4. Repite. Está todo en un objeto de datos precisamente para poder iterar sin tocar lógica.

Si al ordenarlos falla, antes de complicar el modelo conviene revisar si el problema es de
**detección**: un detector que se deja voleas hace que el repertorio salga pobre y el nivel
baje por una razón que no tiene que ver con el jugador.

## Las gráficas en el móvil

Las dos apps de móvil enseñan tres gráficas construidas sobre esta escala. Los datos los
calcula `SessionAnalytics` en el core (con tests en Kotlin que fijan el comportamiento);
las apps solo dibujan, para que ambas plataformas enseñen las mismas curvas.

- **Frecuencia de golpeo** (detalle de sesión): golpeos por intervalo de 5 o 10 minutos.
  Los intervalos vacíos también salen: un hueco es información (descanso, set de paliza),
  no un dato que falte.
- **Progreso de la sesión** (detalle de sesión): el nivel a lo largo del partido, con una
  ventana deslizante de 15 minutos evaluada cada 5. Es ventana y no acumulado a propósito:
  el acumulado converge a la media y se aplana, y lo que se quiere ver es el bajón del
  segundo set o la remontada. La línea de referencia es la media del jugador sobre su
  historial. Los tramos sin golpeos puntuados no dibujan punto: sería inventar.
- **Nivel últimos partidos** (encima del historial): el nivel de las últimas 15 sesiones,
  con filtro por tipo de golpe (usa la nota media de ese golpe en cada sesión).

Vale la advertencia de siempre: mientras la escala esté sin calibrar, lo fiable de estas
curvas es la **forma** (mejora, empeora, se mantiene), no el número absoluto.

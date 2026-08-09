# Entrenar el clasificador

Guía completa para sustituir la heurística v1 por un clasificador entrenado con tus
propios golpeos.

**El cuello de botella son los datos, no el modelo.** El paso 1 es el 80% del esfuerzo;
el resto es un rato de terminal.

## Privacidad: leer antes de empezar

Este modo es la **única** parte de la app que guarda la señal cruda de los sensores. En
el resto, las series de acelerómetro y giróscopo se descartan al cerrar la sesión y solo
salen del reloj eventos agregados.

Por eso:

- Viene **apagado por defecto** y hay que activarlo a mano en los ajustes del móvil.
- Los datos **se quedan en el reloj** hasta que pulsas "Enviar al móvil".
- **No se suben a la liga nunca.** No pasan por `SyncQueue` ni tocan el contrato.
- Del móvil solo salen si los compartes tú, con el botón de exportar.
- El `playerAlias` es un alias que eliges, no tu nombre.

## 1. Grabar (lo que de verdad cuesta)

Lo que **no** funciona: jugar un partido, grabarlo todo y etiquetarlo después mirando
gráficas. Nadie distingue un revés de una volea alta en una serie de acelerómetro.

Lo que sí: **una tanda por tipo de golpe, con la etiqueta puesta antes de golpear.**

1. Ajustes del móvil → activa "Recoger datos de entrenamiento", pon tu alias y, si lo
   sabes, el **nivel del jugador** (1-7). El nivel viaja con cada golpe grabado y es lo
   que permite calibrar la escala: ponerle el reloj a un jugador de nivel 6-7 media hora
   es el "esto es un 7" de verdad. Todo se replica al reloj solo.
2. En el reloj, pantalla inicial → **Datos de entrenamiento**. Este botón **solo aparece
   con el modo activado**: si no lo ves, el ajuste todavía no ha llegado — comprueba que el
   reloj esté emparejado y que las dos apps estén firmadas con la misma clave.
3. Elige el tipo (toque en el chip para cambiarlo) y dale a **Grabar**.
4. Da **30-40 golpes seguidos solo de ese tipo**. El contador sube en cada uno.
5. **Parar tanda**, cambia de tipo, repite.

> **El permiso de entreno hay que concederlo.** Al grabar, el reloj arranca una sesión de
> entrenamiento: es lo único que impide que el sistema suspenda la app y corte el
> acelerómetro al apagarse la pantalla. Si se deniega, la tanda se queda en los primeros
> golpes —50 golpeados, 10 grabados— y por eso la pantalla avisa en rojo cuando pasa. No
> se lee ningún dato de salud en este modo ni queda entrenamiento guardado en Salud: la
> sesión existe solo para que los sensores sigan llegando.

Media hora en pista da unos 400 golpeos limpios.

### Dirigir la tanda desde el móvil

Los pasos 2-5 se pueden hacer **sin tocar el reloj**: Ajustes → Datos de entrenamiento →
**Dirigir tandas desde el móvil**. Elige el golpe, dale a grabar y ve el contador subir en
el iPhone mientras la otra persona pega.

Es como se graban las tandas de verdad: el reloj lo lleva quien pega y quien dirige está
fuera de la pista cantando ejercicios. Con los botones solo en la muñeca hay que parar,
acercarse, quitarle el reloj y cambiar el tipo entre tanda y tanda — y eso acaba en menos
tandas grabadas, que es justo lo que peor le viene al detector.

La misma pantalla lleva el **nombre y el nivel técnico de quien lleva el reloj**, que son
los dos datos que hay que cambiar al pasárselo a otro. Enterrados en Ajustes se olvidan, y
una tanda guardada con el nivel de otra persona contamina la escala en vez de anclarla.

> **No hace falta tener el reloj despierto.** Con su app en primer plano la orden llega al
> instante y el contador se actualiza en vivo; con el reloj dormido la orden queda
> encolada y el sistema despierta la app del reloj para entregarla, y el reloj devuelve su
> estado por el mismo camino. Esto último es lo que hace que el mando sirva: mirar el
> móvil apaga la pantalla del reloj, así que exigir que estuviera despierto era exigirlo
> justo cuando no puede estarlo.
>
> Las órdenes nunca van por contexto replicado: un contexto se reentrega al reconectar y
> arrancaría una tanda que nadie ha pedido. Y una orden encolada **caduca a los tres
> minutos**: si el reloj estuvo sin cobertura, arrancar la tanda mucho después sorprende
> más de lo que ayuda.

En **Wear OS** el mando es el mismo y está en el mismo sitio, pero el camino cambia: las
órdenes van por `MessageClient`, que entrega cada mensaje una sola vez y hace que Play
Services despierte la app del reloj aunque esté cerrada. No van por `DataClient` por el
mismo motivo por el que en Apple no van por contexto: un data item se reentrega al
reconectar.

> **La única diferencia real.** Desde Android 12 una app en segundo plano no puede
> levantar un servicio en primer plano, y la tanda necesita uno para que los sensores
> sigan con la pantalla apagada. Con la app del reloj abierta la tanda arranca sola; con
> la app cerrada, el reloj deja un aviso tocable —"tanda pedida desde el móvil"— y el
> móvil lo dice con esas palabras en vez de fingir que arrancó. El toque del usuario es lo
> que levanta la restricción; parar, enviar y preguntar el estado no la tienen y funcionan
> siempre.

### Cuántos y de quién

| Necesitas | Por qué |
|---|---|
| **4-5 jugadores** distintos, **cada uno con su alias** | Con uno solo, el modelo aprende *tu* forma de golpear, no el golpe. Y si todos graban como `anon`, la validación leave-one-player-out no puede separarlos y el número que da es mentira |
| Diestros **y zurdos** | Aunque la señal se normaliza por lateralidad, conviene comprobar que generaliza |
| Niveles distintos | Un golpe de alguien que empieza no se parece al de alguien que lleva años |
| **~2.000-3.000 golpeos** en total | Por debajo de 2.000 el resultado es ruido |
| 300+ de cada tipo | Un tipo con 50 muestras el modelo casi nunca lo va a predecir |

Pistas distintas y días distintos ayudan: cambia el agarre, el cansancio, la pelota.

El script avisa si alguna de estas condiciones no se cumple, antes de entrenar.

## 2. Sacar los datos

En el reloj: **Enviar al móvil**. En el móvil: Ajustes → **Exportar**.

Sale un `.jsonl`: una muestra por línea, con la ventana de ±1 s alrededor del impacto
(unas 100 muestras a 50 Hz de acelerómetro, giróscopo y gravedad), la etiqueta, el alias
y lo que dijo la heurística.

Unos 7 KB por golpeo: 3.000 golpeos son ~21 MB.

## 3. Entrenar

```bash
pip install numpy scikit-learn
python3 tools/train_classifier.py muestras.jsonl
```

Antes de pisar la pista puedes probar la tubería entera con datos falsos:

```bash
python3 tools/make_synthetic_dataset.py sinteticas.jsonl
python3 tools/train_classifier.py sinteticas.jsonl
```

(Los datos sintéticos dan ~99%. Ese número **no significa nada**: separa clases
generadas a propósito para ser separables. Solo sirve para comprobar que el proceso
corre.)

### Lo que hace el script, y por qué

**Valida dejando fuera a un jugador entero**, no partiendo al azar. Es la decisión que
más importa de todo el proceso:

> Si los golpeos de la misma persona caen a los dos lados de la partición, el modelo
> memoriza al jugador. Sacas un 95% en validación y luego en pista, con alguien nuevo,
> falla. La única cifra que predice el comportamiento real es la de
> leave-one-player-out, y siempre es varios puntos peor que la partición al azar.

**Compara contra la heurística** sobre exactamente las mismas muestras. Si el modelo no
la mejora, el script lo dice: con esos datos no compensa cambiarla, y lo que falta son
más muestras, no un modelo más grande.

**Normaliza por lateralidad** igual que `ShotClassifier` en el core: la muñeca invierte
hacia dónde apunta el eje +Y del reloj respecto al brazo, y la mano invierte el signo
porque un zurdo es la imagen especular de un diestro. Sin esto haría falta tanto zurdo
como diestro en el conjunto.

**Empieza por árboles, no por una red.** Un gradient boosting sobre los rasgos llega al
85-90% con 2.000 muestras, entrena en segundos y puedes mirar qué rasgo pesa más cuando
falla. Una CNN 1D sobre la señal cruda llegaría al 92-95%, pero necesita 3-4× más datos
y no la puedes depurar. Salta a la red solo si el árbol se estanca por debajo de lo que
necesitas.

## 4. Llevarlo al reloj

Esta parte **no está implementada todavía**, y es deliberado: escribir el evaluador
en el dispositivo antes de saber qué precisión da el modelo es trabajo especulativo.
Cuando tengas datos y un número, el camino es:

1. Convertir el modelo a Core ML (iOS) y TFLite (Android), o exportar los árboles a JSON
   y escribir un evaluador de ~80 líneas en cada core. Para un ensemble pequeño, lo
   segundo evita arrastrar dos toolchains.
2. Sustituir **solo** `ShotClassifier`. `ShotDetector` no se toca: la separación entre
   "¿hubo golpeo?" y "¿de qué tipo?" existe justamente para esto.
3. Dejar la heurística como respaldo: si el modelo devuelve confianza baja, cae en ella.

## Formato del fichero

Una línea por golpeo:

```jsonc
{
  "sampleId": "9f1b4c2e-...",
  "label": "backhand",            // lo que eligió el jugador: es la verdad
  "recordedAtEpochMs": 1785002652000,
  "playerAlias": "marta",
  "playerLevel": 6,               // nivel de pádel (1-7) del jugador, si se configuró
  "hand": "right",
  "watchWrist": "right",
  "platform": "wearos",
  "device": "Pixel Watch 3",
  "sampleRateHz": 50,
  "impactIndex": 50,              // índice del impacto en las series
  "offsetsMs": [-1000, -980, ..., 0, ..., 1000],   // relativos al impacto
  "accel":   [[x, y, z], ...],    // g, sin gravedad
  "gyro":    [[x, y, z], ...],    // rad/s
  "gravity": [[x, y, z], ...],    // g
  "heuristicFeatures": { "sweptAngleDeg": 185.2, "peakGyroRadS": 20.1, ... },
  "heuristicPrediction": "backhandVolley",   // para medir la mejora, no para entrenar
  "heuristicConfidence": 0.61
}
```

`offsetsMs` es relativo al impacto y no absoluto para que las ventanas sean comparables
entre golpeos y entre relojes, que arrancan su reloj monótono donde les da la gana.

## Un detalle que conviene entender

**Solo se graban los golpeos que el detector encuentra.** Si la heurística se deja un
golpe, ese golpe no entra en el conjunto.

Es a propósito: interesa entrenar el clasificador con lo que el detector realmente ve en
pista, no con una selección ideal. Si el detector se deja golpeos, eso es un problema
del **detector** y se arregla ahí —bajando umbrales, ajustando la sensibilidad— no
maquillando el conjunto de entrenamiento.

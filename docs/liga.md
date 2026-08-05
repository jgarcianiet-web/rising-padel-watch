# La Liga Personal dentro de la app

El plan de unificación, su estado, y las decisiones que lo gobiernan. La pregunta que
responde: **¿cómo se junta la app de liga (repositorio `padel`, Expo) con esta, para que
todo viva en una sola app?**

## La decisión

**La liga se muda aquí.** No al revés. Tres razones:

1. **El reloj manda.** Lo que hace única a esta app es el pipeline de sensores
   (detección, nivel, salud), que es nativo y no se puede mover a Expo sin perder lo que
   lo hace fiable. La liga, en cambio, es un dominio de datos con pantallas: portable.
2. **La liga es un fichero.** Todo su estado es un JSON (`LigaState`) que la propia app
   Expo exporta como copia de seguridad. Un dominio que cabe en un fichero se muda con
   un import.
3. **Una sola app que abrir.** El objetivo del usuario es no tener dos.

## El puente: la copia de seguridad

La pieza que hace la mudanza segura es que **el backup de la app Expo importa aquí sin
transformación, y el export de aquí reimporta allí**. Mismo shape JSON, campo a campo —
incluidas las rarezas heredadas de la web-app original (el perfil guarda strings porque
eran inputs de texto). Ningún dato queda rehén de ninguna de las dos apps, y la mudanza
se puede deshacer.

Por eso `LigaModels.swift` no "moderniza" nada: es un puerto 1:1 de `domain.ts`, con
decodificación tolerante para backups viejos de la web-app.

## Estado

| Pieza | Estado |
|---|---|
| Pestaña Liga: partidos, resumen de temporada, borrar | Hecho |
| Importar/exportar la copia de seguridad de la app Expo | Hecho |
| Guardar una sesión del reloj como partido (voleas unificadas, curva, salud) | Hecho — mismo mapeo que hacía el deep link, pero sin salir de la app |
| Deep link a la app Expo | Se mantiene durante la transición |
| Ficha de partido (marcador, niveles, curvas, golpes, salud, objetivos, nota) | Hecho — calco de `PartidoDetalleScreen`, se entra tocando el partido |
| Formulario completo de partido: alta a mano y edición de todo | Hecho — calco de `PartidoScreen`; las series del reloj se conservan al editar |
| Objetivos por partido y perfil de la temporada | Hecho — con el catálogo de ideas de la web-app original |
| Análisis con IA (el entrenador de `anthropic.ts`) | Hecho — ver "El entrenador" abajo |
| Android móvil | Pendiente — la fusión es iOS primero, donde está el usuario de la liga |

## El entrenador

El entrenador IA de la app Expo, portado entero (`CoachService.swift`): el mismo prompt
—heredado literalmente de la web-app original—, la misma respuesta estructurada
(lectura, patrones, plan, foco y 3 objetivos prescritos), los mismos mensajes de error,
y la clave de la API de Anthropic en el Llavero con la misma regla de siempre: **nunca
en la copia de seguridad**, que viaja por AirDrop y por email.

Lo que la app Expo no podía tener y aquí sí: una sección de **hechos medidos por el
reloj**, calculados por el `InsightEngine` sobre las sesiones recientes. Es el reparto
de papeles de `insights.md` llevado al prompt: el motor produce hechos verificables con
su evidencia ("ganaste 2 de 6 juegos al resto, sobre 11 juegos"), y el modelo redacta y
sintetiza — con prohibición explícita de inventar hechos de reloj que no estén en la
lista. Dos cambios respecto al original: el modelo pasa de `claude-sonnet-4-6` a
`claude-opus-5` (el análisis se pide unas pocas veces al mes; merece el mejor
razonamiento), y el análisis se guarda en `analisisHistorial` con el mismo shape que el
backup, así que reimporta en la app Expo sin perder nada.

## Marcador en vivo

El estado del partido sale del reloj en cada punto (`LiveMatchState`):

- **Reloj → iPhone**: WatchConnectivity, por dos canales a la vez — mensaje inmediato si
  el iPhone está a tiro y contexto persistente para cuando no lo esté. Cada estado es
  completo, así que perder actualizaciones intermedias no rompe nada.
- **iPhone → mundo**: si hay liga configurada (URL + token), cada estado se republica
  con `PUT /v1/live/{sessionId}` (ver `openapi.yaml`). Fuego y olvido: sin cola, porque
  reenviar un marcador viejo es peor que un hueco.
- **Espectador**: `GET /v1/live/{sessionId}`, sin autenticación — el enlace se comparte.
  El id es un UUID aleatorio y el estado no lleva salud más allá del pulso, que solo va
  si el emisor comparte salud.

**El servidor existe: `server/live`**, un Cloudflare Worker con KV — servicio
gestionado, sin máquina que mantener, plan gratuito de sobra para una liga personal.
Expone el contrato de `openapi.yaml` (PUT con token, GET público), una **página de
espectador** en `/{sessionId}` que se refresca sola y se para en el FINAL, y el buzón
`POST /v1/padel-sessions` para que la app pueda apuntar su URL de liga al worker sin
que el envío de sesiones falle. El despliegue (5 minutos, cuenta de Cloudflare) está en
`server/live/README.md`; la portada del partido en vivo enseña el botón de compartir el
enlace cuando hay liga configurada.

El estado en vivo lleva además los puntos del juego en curso ya etiquetados
(`pointsUs`/`pointsThem`, "40"/"Ad") y quién saca (`serving`): el `Score` del contrato
solo lleva sets, y un marcador en vivo sin el 30-40 no es un marcador.

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
| Formulario completo de partido (club, compañero, mejor/peor golpe, objetivos, nota) | Pendiente — hoy esos campos se conservan al importar pero no se editan aquí |
| Análisis con IA (el `anthropic.ts` de la liga) | Pendiente — sus hechos de entrada serán los del `InsightEngine` (ver `insights.md`) |
| Android móvil | Pendiente — la fusión es iOS primero, donde está el usuario de la liga |

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

**Lo que falta para verlo desde otro móvil es el servidor.** El cliente y el contrato
están; el servidor es una tabla clave-valor con dos rutas, pero hay que hospedarlo. La
liga de hoy es local y no tiene backend — cuando exista (o si se decide usar un servicio
gestionado), esto se enchufa sin tocar el reloj.

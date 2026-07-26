# Contrato de integración con la app de liga

La app de reloj no conoce el esquema interno de la liga. Habla este contrato contra una
`baseURL` y un `Bearer` token que el usuario configura en ajustes. Para integrar
`rising-padel-manager` / `app-liga-padel` basta con implementar este endpoint o poner
un adaptador delante.

La especificación formal está en [`openapi.yaml`](./openapi.yaml). Este documento es la
versión legible.

## Autenticación

```
Authorization: Bearer <token>
```

El token lo emite la app de liga (pantalla de "Conectar reloj"). Puede ser un PAT de
usuario o un JWT de corta duración; el cliente no lo interpreta, solo lo reenvía. Si la
respuesta es `401`, el cliente marca la sesión como *pendiente de reautenticación* y
deja de reintentar hasta que el usuario vuelva a introducir el token.

## `POST /v1/padel-sessions`

Sube una sesión completa. **Es idempotente**: el cliente manda siempre la cabecera

```
Idempotency-Key: <sessionId>
```

donde `sessionId` es un UUID v4 generado en el reloj. Si el servidor ya tiene esa
clave, debe responder `200` con el recurso existente en vez de crear un duplicado. El
cliente reintenta ante fallos de red, así que sin idempotencia habría sesiones
repetidas.

### Petición

```jsonc
{
  "sessionId": "9f1b4c2e-6f7a-4a1e-9c3d-2b5e8a0d7c11",
  "schemaVersion": 1,
  "source": {
    "platform": "watchos",          // "watchos" | "wearos"
    "device": "Apple Watch Series 9",
    "appVersion": "1.0.0"
  },
  "startedAt": "2026-07-25T18:04:12Z",
  "endedAt": "2026-07-25T19:36:48Z",
  "durationSeconds": 5556,
  "player": {
    "hand": "right",                // mano de juego
    "watchWrist": "left"            // muñeca donde lleva el reloj
  },
  "matchRef": {                     // opcional: vincula con un partido de la liga
    "matchId": "match_8842",
    "leagueId": "liga_2026_a"
  },
  "shots": {
    "total": 412,
    "byType": {
      "forehand": 151,
      "backhand": 128,
      "forehandVolley": 44,
      "backhandVolley": 37,
      "overhead": 39,
      "serve": 11,
      "unknown": 2
    },
    "intensity": {
      "meanRacketSpeedKmh": 41.7,
      "maxRacketSpeedKmh": 88.3,
      "meanImpactG": 4.9,
      "maxImpactG": 12.6
    },
    "events": [                     // serie de golpeos, ordenada por offset
      {
        "offsetMs": 18420,
        "type": "forehand",
        "racketSpeedKmh": 52.1,
        "impactG": 6.4,
        "confidence": 0.82
      }
    ]
  },
  "health": {                       // se omite si el usuario no consiente compartirlo
    "heartRate": { "meanBpm": 132, "maxBpm": 171, "restingBpm": 58 },
    "activeEnergyKcal": 806,
    "totalEnergyKcal": 954,
    "steps": 6114,
    "distanceMeters": 3980,
    "zonesSeconds": { "z1": 640, "z2": 1980, "z3": 1910, "z4": 830, "z5": 196 }
  }
}
```

Notas de campos:

- `offsetMs` es relativo a `startedAt`. Se usa offset y no timestamp absoluto para que
  la serie siga siendo válida si el reloj corrige su reloj interno a mitad de sesión.
- `confidence` (0..1) la produce el clasificador. Por debajo de `0.45` el tipo se
  reporta como `unknown` pero el golpeo **sí** cuenta en `total`.
- `events` puede venir vacío si el usuario limita la subida a agregados; `byType` y
  `total` siempre vienen.
- Todos los timestamps son ISO-8601 en UTC con `Z`.

### Respuestas

| Código | Significado | Qué hace el cliente |
|---|---|---|
| `201` | Creada | Marca la sesión como sincronizada |
| `200` | Ya existía (misma `Idempotency-Key`) | Marca como sincronizada |
| `400` | Payload inválido | No reintenta; marca como fallo permanente y lo muestra en la UI |
| `401` | Token inválido o caducado | Para y pide reautenticación |
| `409` | Conflicto con otra sesión (p.ej. mismo partido) | No reintenta; lo muestra en la UI |
| `413` | Payload demasiado grande | Reintenta una vez sin `shots.events` |
| `429` | Rate limit | Reintenta respetando `Retry-After` |
| `5xx` | Error de servidor | Reintenta con backoff exponencial |

Cuerpo de respuesta:

```jsonc
{
  "id": "psession_10231",
  "sessionId": "9f1b4c2e-6f7a-4a1e-9c3d-2b5e8a0d7c11",
  "createdAt": "2026-07-25T19:37:02Z",
  "matchRef": { "matchId": "match_8842", "leagueId": "liga_2026_a" }
}
```

Cuerpo de error (cualquier `4xx`/`5xx`):

```jsonc
{ "error": { "code": "invalid_payload", "message": "shots.total must be >= 0" } }
```

## `GET /v1/me/matches?from=<iso>&to=<iso>`

Opcional pero recomendado. Devuelve los partidos del jugador en esa ventana para que la
app pueda ofrecer "vincular esta sesión con el partido X" en vez de pedir un ID a mano.

```jsonc
{
  "matches": [
    {
      "matchId": "match_8842",
      "leagueId": "liga_2026_a",
      "scheduledAt": "2026-07-25T18:00:00Z",
      "opponents": "Marta / Luis",
      "venue": "Rising Padel Club - Pista 3"
    }
  ]
}
```

Si el endpoint no existe (`404`), la app degrada a introducción manual del `matchId`.

## Política de reintentos del cliente

Backoff exponencial con jitter: 2s, 4s, 8s, 16s, 32s, 60s, y a partir de ahí cada 15
minutos, hasta 72 horas. Las sesiones no sincronizadas se conservan en local y se
reintentan al recuperar conectividad. La cola se procesa en orden de `startedAt`.

## Versionado

`schemaVersion` es un entero. El servidor debe aceptar cualquier versión que conozca y
responder `400` con `code: "unsupported_schema_version"` si es mayor que la soportada;
el cliente lo trata como fallo permanente y avisa de que hay que actualizar la app de
liga.

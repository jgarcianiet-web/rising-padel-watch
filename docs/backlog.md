# Pendiente

Cosas decididas pero **no** incluidas en la primera iteración. Cada entrada dice qué
falta y qué habría que tocar, para poder retomarla sin rehacer el análisis.

## ~~1. Marcador de partido en el reloj~~ — hecho

Implementado. Ver [`scoring.md`](./scoring.md) para las reglas y el diseño de la
interacción.

Un cambio respecto a lo previsto aquí: **el gesto para deshacer es mantener pulsado, no
deslizar**. El deslizamiento horizontal está tomado por el gesto de volver atrás del
sistema en Wear OS y por la navegación entre vistas en watchOS; robarlo rompe la
navegación o directamente no funciona.

Queda una limitación conocida: los ajustes del reloj y los del móvil **no se
sincronizan** todavía. El interruptor de "llevar marcador" está en la pantalla inicial
del reloj, así que esta función no lo necesita, pero el resto de ajustes (mano, muñeca,
sensibilidad, consentimiento de salud) hay que configurarlos en cada dispositivo. La
replicación por Data Layer / WatchConnectivity está pendiente.

## 2. Clasificador de golpeos entrenado

La v1 es heurística (ver `shot-detection.md`). El camino a un modelo aprendido está
descrito ahí: grabar ventanas etiquetadas, entrenar, exportar a Core ML / TFLite y
sustituir **solo** `ShotClassifier`.

## 3. Validación de signos en pista

El convenio de signos del giróscopo (`DetectorConfig.invertAxialSign`) hay que
validarlo una vez por plataforma con golpeos reales: si las derechas salen como revés,
se invierte la bandera. Está aislado en una sola constante justamente para esto.

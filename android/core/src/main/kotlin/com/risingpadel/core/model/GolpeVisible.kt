package com.risingpadel.core.model

/**
 * El repertorio que la app le **enseña** al jugador, que no es el mismo que el que
 * distingue el detector por dentro.
 *
 * ### Por qué existe esta capa
 *
 * El detector separa diez tipos; la app enseña nueve. **La única que se pliega es la
 * víbora dentro de la bandeja**, y no por gusto: las dos tandas limpias de pista se
 * contradicen sobre cuál de las dos se golpea más alta, así que separarlas sin calibrar
 * es echar una moneda al aire con dos nombres puestos.
 *
 * Medido sobre los 82 golpes etiquetados de esas dos tandas (ago 2026):
 *
 * | | diez tipos | repertorio visible |
 * |---|---|---|
 * | tanda de 42 | 71 % | **76 %** |
 * | tanda de 40 (calibrada) | 80 % | **82 %** |
 * | las dos juntas | 68 % | **74 %** |
 *
 * ### Por qué la volea y el globo SÍ llevan lado
 *
 * Plegar también el lado de la volea daba más acierto de tabla —85 % en la tanda de 42
 * en vez de 76 %— y aun así se descartó: para un jugador no es lo mismo tener floja la
 * volea de derecha que la de revés, y una app que no se lo puede decir no le sirve para
 * entrenar. El número de la tabla mide otra cosa que lo útil que es el dato.
 *
 * Hay que decirlo claro de todas formas: **el lado de la volea hoy es poco fiable**. Lo
 * decide el signo de la rotación axial, y las diez voleas de la tanda de 42 midieron
 * entre 0,1 y 3,9 rad/s, que es ruido. En el globo el mismo signo tiene mejor pinta —es
 * un swing completo con muñeca, no un bloqueo— pero no hay tanda con la que decirlo.
 * Las dos cosas las arregla el modelo entrenado, no un umbral.
 *
 * El detector **sigue** produciendo los diez tipos y las tandas se graban con ellos, que
 * es lo que alimenta al modelo. Esto solo decide qué se le enseña a una persona: cuando
 * el modelo sepa separar víbora de bandeja de verdad, aquí se deshace el pliegue.
 */
enum class GolpeVisible(val etiqueta: String) {
    DERECHA("Derecha"),
    REVES("Revés"),
    VOLEA_DERECHA("Volea de derecha"),
    VOLEA_REVES("Volea de revés"),
    GLOBO_DERECHA("Globo de derecha"),
    GLOBO_REVES("Globo de revés"),
    BANDEJA("Bandeja"),
    REMATE("Remate"),
    SAQUE("Saque");

    companion object {
        /** El golpe que se le enseña al jugador, o null si no hay nada que enseñar. */
        fun de(tipo: ShotType): GolpeVisible? = when (tipo) {
            ShotType.FOREHAND -> DERECHA
            ShotType.BACKHAND -> REVES
            ShotType.FOREHAND_VOLLEY -> VOLEA_DERECHA
            ShotType.BACKHAND_VOLLEY -> VOLEA_REVES
            ShotType.FOREHAND_LOB -> GLOBO_DERECHA
            ShotType.BACKHAND_LOB -> GLOBO_REVES
            // La víbora se pliega dentro de la bandeja: las dos son el golpe alto de
            // control y hoy no se separan con garantías. Ver la cabecera.
            ShotType.BANDEJA, ShotType.VIBORA -> BANDEJA
            ShotType.SMASH -> REMATE
            ShotType.SERVE -> SAQUE
            ShotType.UNKNOWN -> null
        }

        /**
         * Agrupa notas por golpe visible **promediando**, no sumando: una nota de 1 a 7
         * no se acumula. Si un jugador dio bandejas de 3,0 y víboras de 3,4, su bandeja
         * visible es 3,2.
         *
         * El promedio es simple y no ponderado por cantidad a propósito: ponderar haría
         * que dos víboras sueltas movieran menos la nota que veinte bandejas, lo cual es
         * defendible, pero la nota por tipo ya viene promediada desde el estimador y
         * volver a ponderar aquí exigiría arrastrar los recuentos hasta este punto para
         * ganar una diferencia de centésimas.
         */
        fun agruparNotas(porTipo: Map<ShotType, Float>): Map<GolpeVisible, Float> {
            val acumulado = LinkedHashMap<GolpeVisible, MutableList<Float>>()
            for ((tipo, nota) in porTipo) {
                val visible = de(tipo) ?: continue
                acumulado.getOrPut(visible) { mutableListOf() }.add(nota)
            }
            return entries
                .mapNotNull { visible ->
                    acumulado[visible]?.let { visible to it.average().toFloat() }
                }
                .toMap()
        }

        /** Agrupa recuentos **sumando**: doce bandejas y tres víboras son quince. */
        fun agruparRecuentos(porTipo: Map<ShotType, Int>): Map<GolpeVisible, Int> {
            val acumulado = LinkedHashMap<GolpeVisible, Int>()
            for ((tipo, cuantos) in porTipo) {
                if (cuantos <= 0) continue
                val visible = de(tipo) ?: continue
                acumulado[visible] = (acumulado[visible] ?: 0) + cuantos
            }
            return entries.mapNotNull { v -> acumulado[v]?.let { v to it } }.toMap()
        }
    }
}

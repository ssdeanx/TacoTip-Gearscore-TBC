--[[

    TacoTip Extras Localization: esES

--]]

local L = {
    ["TIME_UNKNOWN"] = "Desconocido",
    ["TIME_YESTERDAY"] = "Ayer",
    ["GEAR_NO_OPPORTUNITIES"] = "sin oportunidades válidas",
    ["LB_COL_SPECCLASS"] = "ESPEC. / CLASE",
    ["LB_MY_RANK_ARROW"] = "▼ Mi puesto",
    ["GEAR_SCANNING"] = "Analizando equipo...",
    ["LB_SORTED_BY"] = "Ordenado por %s %s",
    ["LB_FOOTER_NO_RANK"] = "%d jugadores registrados - aún sin clasificación",
    ["EQUIPMENT_CATEGORY_NAME"] = "Ventanas de equipo",
    ["MINIMAP_HINT_RIGHT"] = "Clic derecho: ajustes",
    ["COMPLETE"] = "Completo",
    ["GEAR_UNAVAILABLE"] = "Datos de equipo no disponibles",
    ["LB_FOOTER_STANDING"] = "Tu posición: #%d general | #%d facción | #%d clase  -  %d jugadores registrados",
    ["CATEGORY_NAME"] = "TacoTip Extras",

    ["INTRO"] =
    "Un complemento de TacoTip que añade a los tooltips de jugador el GearScore, el nivel de objeto medio y la finalización, teniendo en cuenta las mejoras.",

    ["SCORE_EXPLANATION"] =
    "Current GS es el GearScore actual del jugador en este complemento y el valor destacado en el modo Compacto. Usa Current GS cuando te refieras al GearScore actual del jugador. Incluye los objetos equipados y las bonificaciones admitidas de los encantamientos permanentes y las gemas instalados.\n\nUnenhanced GS es una comparación opcional con el mismo equipo al que solo se le han retirado esas bonificaciones instaladas contabilizadas. Muestra cuánto aportan ya esas mejoras; no es el GearScore actual del jugador.\n\nPotential GS suma a Current GS únicamente los encantamientos permanentes admisibles que falten y estén confirmados, y las ranuras vacías confirmadas. Delta es el incremento de Current GS a Potential GS, mientras que Completion muestra la proporción de oportunidades de mejora confirmadas ya rellenadas.\n\nPotential GS y Completion no valoran el equipo óptimo, no recomiendan mejoras concretas ni miden la preparación para la incursión. Los datos remotos incompletos se muestran como no disponibles, nunca como cero.",

    ["MODE_DISABLED"] = "Desactivado",
    ["MODE_MINIMAL"] = "Mínimo",
    ["MODE_COMPACT"] = "Compacto",
    ["MODE_DETAILED"] = "Detallado",
    ["MODE_BASIC"] = "Básico",

    ["CURRENT_GS"] = "GS actual",
    ["UNENHANCED_GS"] = "GS sin mejoras",
    ["POTENTIAL_GS"] = "GS potencial",
    ["DELTA"] = "Diferencia",
    ["AVERAGE_ILVL"] = "iLvl medio",
    ["COMPLETION"] = "Finalización",
    ["ENHANCEMENT_ANALYSIS"] = "Análisis de mejoras",
    ["UNAVAILABLE"] = "No disponible",

    ["TOOLTIP_LABEL_ENHANCEMENT"] = "Análisis de mejoras:",
    ["TOOLTIP_LABEL_COMPLETION"] = "Finalización:",
    ["TOOLTIP_LABEL_RANK"] = "Rango GS:",

    ["HELP_ENABLED_HEADING"] = "Activar el complemento",
    ["HELP_ENABLED_1"] =
    "Activa o desactiva toda la salida de TacoTip Extras. Al desactivarlo, el complemento libera la toma del GearScore del jugador y restaura con seguridad el ajuste de TacoTip que gestiona.",

    ["HELP_MODE_HEADING"] = "Modo del tooltip",
    ["HELP_MODE_1"] = "Desactivado: no muestra filas del complemento y libera la toma del GearScore del jugador de TacoTip.",
    ["HELP_MODE_2"] = "Mínimo: muestra el resumen activado más breve, priorizando el GS actual y el iLvl medio.",
    ["HELP_MODE_3"] = "Compacto: muestra hasta dos filas concisas con el GS actual, el iLvl medio, la diferencia útil y la finalización cuando estén disponibles.",
    ["HELP_MODE_4"] = "Detallado: muestra cada métrica activada en una fila con su propia etiqueta.",

    ["HELP_SHIFTDETAILED_HEADING"] = "Mayús para ver Detallado",
    ["HELP_SHIFTDETAILED_1"] =
    "Muestra temporalmente la salida detallada mientras se mantiene pulsada Mayús en los modos Mínimo o Compacto. Los modos Detallado y Desactivado no cambian.",

    ["HELP_FIELDS_HEADING"] = "Campos del tooltip",
    ["HELP_FIELDS_1"] =
    "Elige qué métricas puede mostrar el complemento. El modo seleccionado y la disponibilidad de datos todavía pueden omitir una métrica activada.",

    ["HELP_GEARSCORE_HEADING"] = "Mostrar el GS actual",
    ["HELP_GEARSCORE_1"] =
    "Muestra el GearScore presente del jugador y el valor de GS destacado en el modo Compacto. Combina la puntuación de los objetos equipados con las bonificaciones admitidas de los encantamientos permanentes y las gemas instalados; los efectos temporales de arma no se incluyen.",

    ["HELP_BASEGS_HEADING"] = "Mostrar el GS sin mejoras",
    ["HELP_BASEGS_1"] =
    "Muestra los mismos objetos equipados tras retirar únicamente las bonificaciones contabilizadas de los encantamientos permanentes y las gemas instalados. Es una comparación opcional para ver cuánto aportan esas mejoras, no el GearScore actual del jugador.",

    ["HELP_POTENTIALGS_HEADING"] = "Mostrar el GS potencial",
    ["HELP_POTENTIALGS_1"] =
    "Muestra el GS actual tras sumar únicamente los encantamientos permanentes admisibles que falten y estén confirmados, y las ranuras vacías confirmadas. Solo aparece cuando hay suficientes datos confirmados y no recomienda encantamientos ni gemas concretos.",

    ["HELP_DELTA_HEADING"] = "Mostrar la diferencia",
    ["HELP_DELTA_1"] =
    "Muestra la diferencia confirmada entre el GS potencial y el GS actual. Representa la puntuación adicional disponible por mejoras confirmadas que faltan, no una comparación con el GS sin mejoras.",

    ["HELP_AVERAGEITEMLEVEL_HEADING"] = "Mostrar el iLvl medio",
    ["HELP_AVERAGEITEMLEVEL_1"] =
    "Muestra el nivel de objeto medio del equipo incluido en el modelo fijo de ranuras de equipo del complemento.",

    ["HELP_COMPLETION_HEADING"] = "Mostrar la finalización",
    ["HELP_COMPLETION_1"] =
    "Muestra la proporción de oportunidades confirmadas de encantamiento permanente y engarce que están rellenadas. Mide la finalización de las mejoras, no el equipo óptimo ni la preparación para la incursión.",

    ["HELP_RESTRICTLEVEL70_HEADING"] = "Restringir el GS potencial, la finalización y los avisos al nivel 70",
    ["HELP_RESTRICTLEVEL70_1"] =
    "Oculta el GS potencial, la diferencia, la finalización y los avisos relacionados por debajo del nivel 70. El GS actual, el GS sin mejoras y el iLvl medio todavía pueden aparecer.",

    ["HELP_WARNINGCOLORS_HEADING"] = "Colores de aviso de la finalización",
    ["HELP_WARNINGCOLORS_1"] =
    "Colorea la finalización según los umbrales establecidos del complemento. Si se desactiva, la finalización sigue visible en un color neutro.",

    ["HELP_SHOWMINIMAP_HEADING"] = "Mostrar el botón del minimapa",
    ["HELP_SHOWMINIMAP_1"] =
    "Muestra u oculta el acceso directo del minimapa, que se puede mover. El clic izquierdo abre o cierra la página de opciones del complemento y al arrastrar se mueve el botón.",

    ["HELP_SHOWSERVERRANK_HEADING"] = "Mostrar el puesto en la clasificación del servidor",
    ["HELP_SHOWSERVERRANK_1"] =
    "Muestra la posición del jugador por GearScore en el servidor y su lugar dentro de la clase en los tooltips cuando el motor de sincronización en segundo plano la tiene disponible.",

    ["HELP_COMFORTABLEROWS_HEADING"] = "Filas cómodas",
    ["HELP_COMFORTABLEROWS_1"] =
    "Amplía las filas de la clasificación para que el texto sea mayor. La lista muestra a los mismos jugadores en el mismo orden, pero con filas más altas.",

    ["HELP_SHAMANBLUE_HEADING"] = "Chamán Azul",
    ["HELP_SHAMANBLUE_1"] =
    "Muestra el nombre de clase del chamán en azul en lugar de rosa. Classic Era pinta el color de clase del chamán de rosa, así que coincide con el color que usa el propio TacoTip.",
    ["HELP_SHAMANBLUE_2"] =
    "Cuando TacoTip está instalado, también se aplica su propia opción Chamán Azul: si se desactiva allí, el azul se desactiva también aquí, para que el color de clase sea el mismo en ambos complementos.",

    ["HELP_OPENLEADERBOARD_HEADING"] = "Abrir la clasificación del servidor",
    ["HELP_OPENLEADERBOARD_1"] =
    "Abre la ventana de la clasificación de GearScore de TacoTip (/ex ranks) para consultar las posiciones de todo el reino.",

    ["HELP_RESTORE_HEADING"] = "Restaurar los ajustes de TacoTip",
    ["HELP_RESTORE_1"] =
    "Desactiva la salida del complemento en los tooltips y restaura con seguridad solo el ajuste de GearScore del jugador de TacoTip que se había tomado.",
    ["HELP_RESTORE_2"] =
    "No restablece otras opciones de TacoTip ni tus preferencias restantes del complemento.",

    ["HELP_RESET_HEADING"] = "Restablecer los ajustes del complemento",
    ["HELP_RESET_1"] =
    "Restaura los ajustes de TacoTip Extras a sus valores predeterminados, incluidas las preferencias del tooltip y la visibilidad y posición del botón del minimapa.",
    ["HELP_RESET_2"] =
    "No restablece TacoTip. Tampoco toca la clasificación guardada: la tabla del reino vive en TacoTipExtrasDB y sobrevive a este restablecimiento.",

    ["HELP_INTEGRATIONSTATUS_HEADING"] = "Integración con TacoTip",
    ["HELP_INTEGRATIONSTATUS_1"] =
    "Compatible significa que se detectaron la versión exacta de TacoTip requerida y las capacidades necesarias. Si no es compatible, el complemento permanece cerrado y no toma el control de la salida de GearScore del jugador de TacoTip.",

    ["HELP_REMOTESTATUS_HEADING"] = "Análisis remoto de mejoras",
    ["HELP_REMOTESTATUS_1"] =
    "El GS potencial, la diferencia y la finalización remotos dependen de datos de inspección concluyentes. Completo significa correcto; no disponible no significa cero, mientras que pendiente, suprimido y no observado son estados neutrales.",

    ["HELP_BLOCKERSTATUS_HEADING"] = "Bloqueo del análisis remoto de mejoras",
    ["HELP_BLOCKERSTATUS_1"] =
    "Muestra el motivo actual por el que el análisis remoto de mejoras no está disponible. Este diagnóstico es temporal y no se guarda como historial del jugador.",

    ["HELP_EQUIPMENTMODE_HEADING"] = "Resumen de personaje e inspección",
    ["HELP_EQUIPMENTMODE_1"] =
    "Elige qué muestra el complemento en ambas ventanas de equipo. Desactivado restaura la visualización nativa de GearScore e iLvl de TacoTip. Básico muestra el GS actual y el iLvl medio. Detallado añade métricas de mejora concluyentes.",

    ["HELP_EQUIPMENTSHOWUNENHANCED_HEADING"] = "Mostrar el GS sin mejoras en Detallado",
    ["HELP_EQUIPMENTSHOWUNENHANCED_1"] =
    "Muestra el mismo equipo antes de las bonificaciones que este complemento contabiliza de los encantamientos permanentes y las gemas instalados. Es un valor de comparación, no la puntuación principal.",

    ["HELP_EQUIPMENTUNLOCKPOSITIONS_HEADING"] = "Desbloquear las posiciones del resumen",
    ["HELP_EQUIPMENTUNLOCKPOSITIONS_1"] =
    "Muestra un tirador en cada ventana de equipo. Personaje e Inspección mantienen posiciones independientes.",

    ["HELP_EQUIPMENTRESETPOSITIONS_HEADING"] = "Restablecer las posiciones del resumen",
    ["HELP_EQUIPMENTRESETPOSITIONS_1"] =
    "Restaura ambos bloques del resumen a sus posiciones predeterminadas probadas sin cambiar otros ajustes.",

    ["HELP_SCANNOW_HEADING"] = "Escanear ahora",
    ["HELP_SCANNOW_1"] =
    "Ejecuta una pasada de escaneo de inmediato. Solo se pueden escanear los jugadores a los que el juego permite inspeccionar, así que cuántos se alcanzan depende de lo que esté a tu alcance, en tu grupo o visible en una placa de nombre.",

    ["MINIMAP_HINT"] = "TacoTip Extras",
    ["MINIMAP_HINT_LEFT"] = "Clic izquierdo: clasificación",
    ["MINIMAP_HINT_DRAG"] = "Arrastra para mover",

    ["LB_TITLE"] = "Clasificación de GearScore de TacoTip",
    ["LB_REALM"] = "Todo el reino",
    ["LB_SEARCH"] = "Buscar:",
    ["LB_GUILD"] = "Hermandad:",
    ["LB_YOU"] = "TÚ",
    ["LB_LOADING"] = "Cargando la clasificación...",
    ["LB_EMPTY"] = "Aún no hay registros. Las puntuaciones se sincronizan mientras juegas.",
    ["LB_EMPTY_FILTERS"] = "Ningún jugador coincide con los filtros actuales.",
    ["LB_DB_UNAVAILABLE"] = "La base de datos de clasificaciones no está disponible, así que no se pueden mostrar las clasificaciones.",
    ["LB_NOT_ESTABLISHED"] = "Aún sin puesto",
    ["LB_ONLY_YOU"] = "Por ahora, en este reino solo está registrado tu propio personaje.",
    ["LB_FILTER_ALL"] = "Todos",
    ["LB_TOP"] = "\226\150\178 Primero",
    ["LB_SCAN"] = "Escanear ahora",
    ["LB_SCAN_BUSY"] = "Escaneando...",

    ["LB_COL_RANK"] = "PUESTO",
    ["LB_COL_GS"] = "GEARSCORE",
    ["LB_COL_ILVL"] = "iLVL",
    ["LB_COL_LEVEL"] = "NIVEL",
    ["LB_COL_PLAYER"] = "JUGADOR",
    ["LB_COL_LASTSEEN"] = "VISTO POR ÚLTIMA VEZ",

    ["LB_TIP_UNKNOWN"] = "Desconocido",
    ["LB_TIP_UNKNOWNSPEC"] = "Especialización desconocida",
    ["LB_TIP_GS"] = "GearScore: %d",
    ["LB_TIP_ILVL"] = "iLvl medio: %.1f",
    ["LB_TIP_PVP_RANK"] = "Rango PvP: %s",
    ["LB_TIP_ARENA"] = "Mejor en arena: %d",
    ["LB_TIP_RANK"] = "Puesto de GearScore: #%d",
    ["LB_TIP_LASTSEEN"] = "Visto por última vez: %s",
    ["LB_TIP_RANK_SYNCED"] = "Rango sincronizado: %s",
    ["LB_TIP_CLICK_GEAR"] = "Clic para ver el equipo",
    ["LB_SCAN_COMPLETE"] = "Escaneo completado - %d jugadores registrados",

    ["SORT_GS_DESC"] = "GEARSCORE",
    ["SORT_ILVL_DESC"] = "NIVEL DE OBJETO",
    ["SORT_LEVEL_DESC"] = "NIVEL",
    ["SORT_SEEN_DESC"] = "VISTO POR ÚLTIMA VEZ",

    ["LB_STAT_STRIP"] = "%d jugadores | Máx %d | Media %d",

    ["TIME_JUST_NOW"] = "Ahora mismo",
    ["TIME_MIN_AGO"] = "hace %d min",
    ["TIME_HOUR_AGO"] = "hace %d h",
    ["TIME_DAY_AGO"] = "hace %d d",

    ["GEAR_TITLE"] = "Equipo de %s",
    ["GEAR_NOT_SCANNED"] = "Este jugador aún no se ha escaneado, así que no hay equipo disponible.",
    ["GEAR_DATA_UNAVAILABLE"] = "Los datos de equipamiento no están disponibles para este jugador ahora. Pulsa Escanear ahora en la clasificación e inténtalo de nuevo.",

    ["SCAN_PROGRESS"] = "%d / %d",

    ["CLASS_DEATHKNIGHT"] = "Caballero de la Muerte",
    ["CLASS_DEMONHUNTER"] = "Cazador de Demonstrios",
    ["CLASS_DRUID"] = "Druida",
    ["CLASS_EVOKER"] = "Evocador",
    ["CLASS_HUNTER"] = "Cazador",
    ["CLASS_MAGE"] = "Mago",
    ["CLASS_MONK"] = "Monje",
    ["CLASS_PALADIN"] = "Paladín",
    ["CLASS_PRIEST"] = "Sacerdote",
    ["CLASS_ROGUE"] = "Pícaro",
    ["CLASS_SHAMAN"] = "Chamán",
    ["CLASS_WARLOCK"] = "Brujo",
    ["CLASS_WARRIOR"] = "Guerrero",
    ["CLASS_UNKNOWN"] = "Desconocido",
}

_G.TACOEXTRAS_LOCALES = _G.TACOEXTRAS_LOCALES or {}
_G.TACOEXTRAS_LOCALES["esES"] = L

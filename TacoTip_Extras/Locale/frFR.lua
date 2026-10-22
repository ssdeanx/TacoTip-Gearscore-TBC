--[[

    TacoTip Extras Localization: frFR

--]]

local L = {
    ["TIME_UNKNOWN"] = "Inconnu",
    ["TIME_YESTERDAY"] = "Hier",
    ["GEAR_NO_OPPORTUNITIES"] = "aucune opportunité éligible",
    ["LB_COL_SPECCLASS"] = "SPÉ / CLASSE",
    ["LB_MY_RANK_ARROW"] = "▼ Mon rang",
    ["GEAR_SCANNING"] = "Analyse de l'équipement...",
    ["LB_SORTED_BY"] = "Trié par %s %s",
    ["LB_FOOTER_NO_RANK"] = "%d joueurs suivis - pas encore de classement",
    ["EQUIPMENT_CATEGORY_NAME"] = "Fenêtres d'équipement",
    ["MINIMAP_HINT_RIGHT"] = "Clic droit : options",
    ["COMPLETE"] = "Complet",
    ["GEAR_UNAVAILABLE"] = "Données d'équipement indisponibles",
    ["LB_FOOTER_STANDING"] = "Votre classement : #%d global | #%d faction | #%d classe  -  %d joueurs suivis",
    ["CATEGORY_NAME"] = "TacoTip Extras",

    ["INTRO"] =
    "Un module complémentaire de TacoTip qui ajoute aux infobulles de joueur le GearScore, le niveau d'objet moyen et la complétion, en tenant compte des améliorations.",

    ["SCORE_EXPLANATION"] =
    "Current GS est le GearScore actuel du joueur dans ce module et la valeur mise en avant en mode Compact. Utilisez Current GS lorsque vous parlez du GearScore actuel du joueur. Il inclut les objets équipés ainsi que les bonus pris en charge provenant des enchantements permanents et des gemmes installés.\n\nUnenhanced GS est une comparaison facultative qui reprend le même équipement, privé de ces seuls bonus installés comptabilisés. Elle montre ce que ces améliorations apportent déjà ; ce n'est pas le GearScore actuel du joueur.\n\nPotential GS ajoute à Current GS uniquement les enchantements permanents éligibles manquants et confirmés, ainsi que les emplacements de gemmes vides confirmés. Delta est l'écart entre Current GS et Potential GS, tandis que Completion montre la part des opportunités d'amélioration confirmées déjà comblées.\n\nPotential GS et Completion n'évaluent pas l'équipement idéal, ne recommandent pas d'amélioration précise et ne mesurent pas la préparation au raid. Les données distantes incomplètes sont affichées comme indisponibles, jamais comme zéro.",

    ["MODE_DISABLED"] = "Désactivé",
    ["MODE_MINIMAL"] = "Minimal",
    ["MODE_COMPACT"] = "Compact",
    ["MODE_DETAILED"] = "Détaillé",
    ["MODE_BASIC"] = "Basique",

    ["CURRENT_GS"] = "GS actuel",
    ["UNENHANCED_GS"] = "GS non amélioré",
    ["POTENTIAL_GS"] = "GS potentiel",
    ["DELTA"] = "Écart",
    ["AVERAGE_ILVL"] = "iLvl moyen",
    ["COMPLETION"] = "Complétion",
    ["ENHANCEMENT_ANALYSIS"] = "Analyse des améliorations",
    ["UNAVAILABLE"] = "Indisponible",

    ["TOOLTIP_LABEL_ENHANCEMENT"] = "Analyse des améliorations :",
    ["TOOLTIP_LABEL_COMPLETION"] = "Complétion :",
    ["TOOLTIP_LABEL_RANK"] = "Rang GS :",

    ["HELP_ENABLED_HEADING"] = "Activer le module",
    ["HELP_ENABLED_1"] =
    "Active ou désactive toute la sortie de TacoTip Extras. Lorsqu'il est désactivé, le module libère sa prise en charge du GearScore du joueur et restaure en toute sécurité le réglage TacoTip qu'il gère.",

    ["HELP_MODE_HEADING"] = "Mode d'infobulle",
    ["HELP_MODE_1"] = "Désactivé : n'affiche aucune ligne du module et libère la prise en charge du GearScore du joueur de TacoTip.",
    ["HELP_MODE_2"] = "Minimal : affiche le résumé activé le plus court, en privilégiant le GS actuel et l'iLvl moyen.",
    ["HELP_MODE_3"] = "Compact : affiche jusqu'à deux lignes concises avec le GS actuel, l'iLvl moyen, l'écart utile et la complétion lorsque disponible.",
    ["HELP_MODE_4"] = "Détaillé : affiche chaque mesure activée sur une ligne distincte avec son propre libellé.",

    ["HELP_SHIFTDETAILED_HEADING"] = "Maj pour le mode Détaillé",
    ["HELP_SHIFTDETAILED_1"] =
    "Affiche temporairement la sortie détaillée tant que Maj est maintenue en mode Minimal ou Compact. Les modes Détaillé et Désactivé restent inchangés.",

    ["HELP_FIELDS_HEADING"] = "Champs de l'infobulle",
    ["HELP_FIELDS_1"] =
    "Choisissez les mesures que le module peut afficher. Le mode sélectionné et la disponibilité des données peuvent encore omettre une mesure activée.",

    ["HELP_GEARSCORE_HEADING"] = "Afficher le GS actuel",
    ["HELP_GEARSCORE_1"] =
    "Affiche le GearScore actuel du joueur et la valeur GS mise en avant en mode Compact. Il combine le score des objets équipés avec les bonus pris en charge des enchantements permanents et des gemmes installés ; les effets temporaires d'arme ne sont pas inclus.",

    ["HELP_BASEGS_HEADING"] = "Afficher le GS non amélioré",
    ["HELP_BASEGS_1"] =
    "Affiche les mêmes objets équipés après retrait des seuls bonus comptabilisés provenant des enchantements permanents et des gemmes installés. C'est une comparaison facultative montrant ce que ces améliorations apportent, pas le GearScore actuel du joueur.",

    ["HELP_POTENTIALGS_HEADING"] = "Afficher le GS potentiel",
    ["HELP_POTENTIALGS_1"] =
    "Affiche le GS actuel après ajout des seuls enchantements permanents éligibles manquants et confirmés, ainsi que des emplacements de gemmes vides confirmés. Il n'apparaît que lorsque suffisamment de données sont confirmées et ne recommande aucun enchantement ni gemme précis.",

    ["HELP_DELTA_HEADING"] = "Afficher l'écart",
    ["HELP_DELTA_1"] =
    "Affiche la différence confirmée entre le GS potentiel et le GS actuel. Elle représente le score supplémentaire disponible grâce aux améliorations confirmées manquantes, et non une comparaison avec le GS non amélioré.",

    ["HELP_AVERAGEITEMLEVEL_HEADING"] = "Afficher l'iLvl moyen",
    ["HELP_AVERAGEITEMLEVEL_1"] =
    "Affiche le niveau d'objet moyen de l'équipement inclus dans le modèle fixe d'emplacements d'équipement du module.",

    ["HELP_COMPLETION_HEADING"] = "Afficher la complétion",
    ["HELP_COMPLETION_1"] =
    "Affiche la part des opportunités confirmées d'enchantement permanent et de sertissage qui sont comblées. Elle mesure la complétion des améliorations, pas l'équipement idéal ni la préparation au raid.",

    ["HELP_RESTRICTLEVEL70_HEADING"] = "Restreindre le GS potentiel, la complétion et les avertissements au niveau 70",
    ["HELP_RESTRICTLEVEL70_1"] =
    "Masque le GS potentiel, l'écart, la complétion et les avertissements associés sous le niveau 70. Le GS actuel, le GS non amélioré et l'iLvl moyen peuvent toujours apparaître.",

    ["HELP_WARNINGCOLORS_HEADING"] = "Couleurs d'avertissement de complétion",
    ["HELP_WARNINGCOLORS_1"] =
    "Colore la complétion selon les seuils établis par le module. Lorsque désactivé, la complétion reste visible dans une couleur neutre.",

    ["HELP_SHOWMINIMAP_HEADING"] = "Afficher le bouton de minicarte",
    ["HELP_SHOWMINIMAP_1"] =
    "Affiche ou masque le raccourci de minicarte, qui peut être déplacé. Le clic gauche ouvre ou ferme la page d'options du module, et le glissement déplace le bouton.",

    ["HELP_SHOWSERVERRANK_HEADING"] = "Afficher le rang du classement du serveur",
    ["HELP_SHOWSERVERRANK_1"] =
    "Affiche le classement GearScore du joueur sur le serveur et sa place dans sa classe sur les infobulles, lorsque le moteur de synchronisation en arrière-plan la fournit.",

    ["HELP_COMFORTABLEROWS_HEADING"] = "Lignes confortables",
    ["HELP_COMFORTABLEROWS_1"] =
    "Agrandit les lignes du classement pour un texte plus grand. La liste affiche les mêmes joueurs dans le même ordre, mais avec des lignes plus hautes.",

    ["HELP_SHAMANBLUE_HEADING"] = "Chaman Bleu",
    ["HELP_SHAMANBLUE_1"] =
    "Affiche le nom de classe du chaman en bleu au lieu du rose. Classic Era peint la couleur de classe du chaman en rose, ce qui correspond à la couleur utilisée par TacoTip lui-même.",
    ["HELP_SHAMANBLUE_2"] =
    "Quand TacoTip est installé, son propre réglage Chaman Bleu s'applique aussi : le désactiver là désactive le bleu ici également, afin que la couleur de classe soit la même dans les deux modules.",

    ["HELP_OPENLEADERBOARD_HEADING"] = "Ouvrir le classement du serveur",
    ["HELP_OPENLEADERBOARD_1"] =
    "Ouvre la fenêtre du classement GearScore de TacoTip (/tt ranks) pour consulter les classements de tout le royaume.",

    ["HELP_RESTORE_HEADING"] = "Restaurer les réglages de TacoTip",
    ["HELP_RESTORE_1"] =
    "Désactive la sortie du module sur les infobulles et restaure en toute sécurité uniquement le réglage GearScore du joueur de TacoTip qui avait été repris.",
    ["HELP_RESTORE_2"] =
    "Ne réinitialise pas les autres options de TacoTip ni vos préférences restantes du module.",

    ["HELP_RESET_HEADING"] = "Réinitialiser les réglages du module",
    ["HELP_RESET_1"] =
    "Restaure les réglages de TacoTip Extras à leurs valeurs par défaut, y compris les préférences d'infobulle ainsi que la visibilité et la position du bouton de minicarte.",
    ["HELP_RESET_2"] =
    "Ne réinitialise pas TacoTip. Le classement enregistré n'est pas touché non plus : les résultats du royaume vivent dans TacoTipExtrasDB et survivent à cette réinitialisation.",

    ["HELP_INTEGRATIONSTATUS_HEADING"] = "Intégration de TacoTip",
    ["HELP_INTEGRATIONSTATUS_1"] =
    "Compatible signifie que la version exacte requise de TacoTip et les capacités nécessaires ont été détectées. En cas d'incompatibilité, le module reste fermé et ne prend pas le contrôle de la sortie GearScore du joueur de TacoTip.",

    ["HELP_REMOTESTATUS_HEADING"] = "Analyse distante des améliorations",
    ["HELP_REMOTESTATUS_1"] =
    "Le GS potentiel, l'écart et la complétion distants dépendent de données d'inspection concluantes. Complet signifie réussi ; indisponible ne signifie pas zéro, tandis qu'en attente, supprimé et non observé sont des états neutres.",

    ["HELP_BLOCKERSTATUS_HEADING"] = "Blocage de l'analyse distante",
    ["HELP_BLOCKERSTATUS_1"] =
    "Affiche la raison actuelle pour laquelle l'analyse distante des améliorations est indisponible. Ce diagnostic est temporaire et n'est pas conservé comme historique du joueur.",

    ["HELP_EQUIPMENTMODE_HEADING"] = "Résumé personnage et inspection",
    ["HELP_EQUIPMENTMODE_1"] =
    "Choisissez ce que le module affiche dans les deux fenêtres d'équipement. Désactivé restaure l'affichage natif GearScore et iLvl de TacoTip. Basique affiche le GS actuel et l'iLvl moyen. Détaillé ajoute les mesures d'amélioration concluantes.",

    ["HELP_EQUIPMENTSHOWUNENHANCED_HEADING"] = "Afficher le GS non amélioré en Détaillé",
    ["HELP_EQUIPMENTSHOWUNENHANCED_1"] =
    "Affiche le même équipement avant les bonus que ce module comptabilise parmi les enchantements permanents et les gemmes installés. C'est une valeur de comparaison, pas le score principal.",

    ["HELP_EQUIPMENTUNLOCKPOSITIONS_HEADING"] = "Déverrouiller les positions du résumé",
    ["HELP_EQUIPMENTUNLOCKPOSITIONS_1"] =
    "Affiche une poignée dans chaque fenêtre d'équipement. Personnage et inspection conservent des positions indépendantes.",

    ["HELP_EQUIPMENTRESETPOSITIONS_HEADING"] = "Réinitialiser les positions du résumé",
    ["HELP_EQUIPMENTRESETPOSITIONS_1"] =
    "Restaure les deux blocs de résumé à leurs positions par défaut testées sans modifier les autres réglages.",

    ["HELP_SCANNOW_HEADING"] = "Scanner maintenant",
    ["HELP_SCANNOW_1"] =
    "Lance immédiatement une passe de scan. Seuls les joueurs que le jeu autorise à inspecter peuvent être scannés ; le nombre atteint dépend donc de ce qui est à votre portée, dans votre groupe ou visible sur un nom de plaque.",

    ["MINIMAP_HINT"] = "TacoTip Extras",
    ["MINIMAP_HINT_LEFT"] = "Clic gauche : classement",
    ["MINIMAP_HINT_DRAG"] = "Glisser pour déplacer",

    ["LB_TITLE"] = "Classement GearScore TacoTip",
    ["LB_REALM"] = "Tout le royaume",
    ["LB_SEARCH"] = "Recherche :",
    ["LB_GUILD"] = "Guilde :",
    ["LB_YOU"] = "VOUS",
    ["LB_LOADING"] = "Chargement du classement...",
    ["LB_EMPTY"] = "Aucun enregistrement pour l'instant. Les scores se synchronisent pendant votre jeu.",
    ["LB_EMPTY_FILTERS"] = "Aucun joueur ne correspond aux filtres actuels.",
    ["LB_DB_UNAVAILABLE"] = "La base de données des classements est indisponible, aucun classement ne peut être affiché.",
    ["LB_NOT_ESTABLISHED"] = "Pas encore de rang",
    ["LB_ONLY_YOU"] = "Pour l'instant, seul votre propre personnage est enregistré sur ce royaume.",
    ["LB_FILTER_ALL"] = "Tous",
    ["LB_TOP"] = "\226\150\178 Premier",
    ["LB_SCAN"] = "Scanner maintenant",
    ["LB_SCAN_BUSY"] = "Scan en cours...",

    ["LB_COL_RANK"] = "RANG",
    ["LB_COL_GS"] = "GEARSCORE",
    ["LB_COL_ILVL"] = "iLVL",
    ["LB_COL_LEVEL"] = "NIVEAU",
    ["LB_COL_PLAYER"] = "JOUEUR",
    ["LB_COL_LASTSEEN"] = "VU RÉCEMMENT",

    ["LB_TIP_UNKNOWN"] = "Inconnu",
    ["LB_TIP_UNKNOWNSPEC"] = "Spécialisation inconnue",
    ["LB_TIP_GS"] = "GearScore : %d",
    ["LB_TIP_ILVL"] = "iLvl moyen : %.1f",
    ["LB_TIP_PVP_RANK"] = "Rang PvP : %s",
    ["LB_TIP_ARENA"] = "Meilleur en arène : %d",
    ["LB_TIP_RANK"] = "Rang GearScore : #%d",
    ["LB_TIP_LASTSEEN"] = "Vu la dernière fois : %s",
    ["LB_TIP_RANK_SYNCED"] = "Rang synchronisé : %s",
    ["LB_TIP_CLICK_GEAR"] = "Cliquez pour voir l'équipement",
    ["LB_SCAN_COMPLETE"] = "Scan terminé - %d joueurs suivis",

    ["SORT_GS_DESC"] = "GEARSCORE",
    ["SORT_ILVL_DESC"] = "NIVEAU D'OBJET",
    ["SORT_LEVEL_DESC"] = "NIVEAU",
    ["SORT_SEEN_DESC"] = "VU LA DERNIÈRE FOIS",

    ["LB_STAT_STRIP"] = "%d joueurs | Max %d | Moy %d",

    ["TIME_JUST_NOW"] = "À l'instant",
    ["TIME_MIN_AGO"] = "il y a %d min",
    ["TIME_HOUR_AGO"] = "il y a %d h",
    ["TIME_DAY_AGO"] = "il y a %d j",

    ["GEAR_TITLE"] = "Équipement de %s",
    ["GEAR_NOT_SCANNED"] = "Ce joueur n'a pas encore été scanné ; aucun équipement n'est disponible.",
    ["GEAR_DATA_UNAVAILABLE"] = "Les données d'équipement ne sont pas disponibles pour ce joueur pour le moment. Appuie sur Scanner maintenant dans le classement, puis réessaie.",

    ["SCAN_PROGRESS"] = "%d / %d",

    ["CLASS_DEATHKNIGHT"] = "Chevalier de la Mort",
    ["CLASS_DEMONHUNTER"] = "Chasseur de démons",
    ["CLASS_DRUID"] = "Druide",
    ["CLASS_EVOKER"] = "Évocateur",
    ["CLASS_HUNTER"] = "Chasseur",
    ["CLASS_MAGE"] = "Mage",
    ["CLASS_MONK"] = "Moine",
    ["CLASS_PALADIN"] = "Paladin",
    ["CLASS_PRIEST"] = "Prêtre",
    ["CLASS_ROGUE"] = "Voleur",
    ["CLASS_SHAMAN"] = "Chaman",
    ["CLASS_WARLOCK"] = "Démoniste",
    ["CLASS_WARRIOR"] = "Guerrier",
    ["CLASS_UNKNOWN"] = "Inconnu",
}

_G.TACOEXTRAS_LOCALES = _G.TACOEXTRAS_LOCALES or {}
_G.TACOEXTRAS_LOCALES["frFR"] = L

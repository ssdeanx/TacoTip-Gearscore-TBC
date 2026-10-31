--[[

    TacoTip Extras Localization: deDE

--]]

local L = {
    ["TIME_UNKNOWN"] = "Unbekannt",
    ["TIME_YESTERDAY"] = "Gestern",
    ["GEAR_NO_OPPORTUNITIES"] = "keine nutzbaren Möglichkeiten",
    ["LB_COL_SPECCLASS"] = "SKILLUNG / KLASSE",
    ["LB_MY_RANK_ARROW"] = "▼ Mein Rang",
    ["GEAR_SCANNING"] = "Ausrüstung wird gelesen...",
    ["LB_SORTED_BY"] = "Sortiert nach %s %s",
    ["LB_FOOTER_NO_RANK"] = "%d Spieler erfasst - noch keine Platzierung",
    ["EQUIPMENT_CATEGORY_NAME"] = "Ausrüstungsfenster",
    ["MINIMAP_HINT_RIGHT"] = "Rechtsklick: Einstellungen",
    ["COMPLETE"] = "Vollständig",
    ["GEAR_UNAVAILABLE"] = "Ausrüstungsdaten nicht verfügbar",
    ["LB_FOOTER_STANDING"] = "Deine Platzierung: #%d Gesamt | #%d Fraktion | #%d Klasse  -  %d Spieler erfasst",
    ["CATEGORY_NAME"] = "TacoTip Extras",

    ["INTRO"] =
    "Ein TacoTip-Begleiter, der verbessungsbewusste GearScore, durchschnittliches Item-Level und Vollständigkeit zu Spielertooltips hinzufügt.",

    ["SCORE_EXPLANATION"] =
    "Current GS ist der aktuelle GearScore des Spielers in diesem Addon und der führende Wert im Kompaktmodus. Verwende Current GS, wenn du den aktuellen GearScore des Spielers meinst. Er enthält ausgerüstete Gegenstände sowie unterstützte Boni aus installierten dauerhaften Verzauberungen und Edelsteinen.\n\nUnenhanced GS ist ein optionaler Vergleich mit derselben Ausrüstung, bei der nur diese gezählten installierten Boni entfernt wurden. Er zeigt, wie viel diese Verbesserungen bereits beitragen; er ist nicht der aktuelle GearScore des Spielers.\n\nPotential GS addiert zu Current GS nur bestätigte fehlende zulässige dauerhafte Verzauberungen und bestätigte leere Fassungen. Delta ist der Zuwachs von Current GS zu Potential GS, während Completion den Anteil der bereits gefüllten bestätigten Verbesserungsmöglichkeiten zeigt.\n\nPotential GS und Completion bewerten keine Optimal-Ausrüstung, empfehlen keine konkreten Verbesserungen und messen keine Raid-Tauglichkeit. Unvollständige entfernte Daten werden als nicht verfügbar angezeigt, niemals als null.",

    ["MODE_DISABLED"] = "Deaktiviert",
    ["MODE_MINIMAL"] = "Minimal",
    ["MODE_COMPACT"] = "Kompakt",
    ["MODE_DETAILED"] = "Detailliert",
    ["MODE_BASIC"] = "Einfach",

    ["CURRENT_GS"] = "Aktueller GS",
    ["UNENHANCED_GS"] = "Unverbesserter GS",
    ["POTENTIAL_GS"] = "Möglicher GS",
    ["DELTA"] = "Differenz",
    ["AVERAGE_ILVL"] = "Durchschnittliches iLvl",
    ["COMPLETION"] = "Vollständigkeit",
    ["ENHANCEMENT_ANALYSIS"] = "Verbesserungsanalyse",
    ["UNAVAILABLE"] = "Nicht verfügbar",

    ["TOOLTIP_LABEL_ENHANCEMENT"] = "Verbesserungsanalyse:",
    ["TOOLTIP_LABEL_COMPLETION"] = "Vollständigkeit:",
    ["TOOLTIP_LABEL_RANK"] = "GS-Rang:",

    ["HELP_ENABLED_HEADING"] = "Addon aktivieren",
    ["HELP_ENABLED_1"] =
    "Aktiviert oder deaktiviert sämtliche Ausgaben von TacoTip Extras. Im deaktivierten Zustand gibt das Addon die Übernahme des Spieler-GearScore zurück und stellt die verwaltete TacoTip-Einstellung sicher wieder her.",

    ["HELP_MODE_HEADING"] = "Tooltip-Modus",
    ["HELP_MODE_1"] = "Deaktiviert: Zeigt keine Zeilen der Erweiterung und gibt die TacoTip-Übernahme des Spieler-GearScore zurück.",
    ["HELP_MODE_2"] = "Minimal: Zeigt die kürzeste aktivierte Zusammenfassung und bevorzugt Aktueller GS und Durchschnittliches iLvl.",
    ["HELP_MODE_3"] = "Kompakt: Zeigt bis zu zwei knappe Zeilen mit Aktuellem GS, Durchschnittlichem iLvl, sinnvoller Differenz und Vollständigkeit, sofern verfügbar.",
    ["HELP_MODE_4"] = "Detailliert: Zeigt jede aktivierte Kennzahl auf einer eigenen beschrifteten Zeile.",

    ["HELP_SHIFTDETAILED_HEADING"] = "Umschalt für Detailliert",
    ["HELP_SHIFTDETAILED_1"] =
    "Zeigt vorübergehend die detaillierte Ausgabe an, während die Umschalttaste im Modus Minimal oder Kompakt gedrückt gehalten wird. Die Modi Detailliert und Deaktiviert bleiben unverändert.",

    ["HELP_FIELDS_HEADING"] = "Tooltip-Felder",
    ["HELP_FIELDS_1"] =
    "Wähle aus, welche Kennzahlen die Erweiterung anzeigen darf. Der gewählte Modus und die Datenverfügbarkeit können eine aktivierte Kennzahl trotzdem auslassen.",

    ["HELP_GEARSCORE_HEADING"] = "Aktuellen GS anzeigen",
    ["HELP_GEARSCORE_1"] =
    "Zeigt den gegenwärtigen GearScore des Spielers und den führenden GS-Wert im Kompaktmodus. Er kombiniert den Punktwert der ausgerüsteten Gegenstände mit unterstützten Boni aus installierten dauerhaften Verzauberungen und Edelsteinen; temporäre Waffeneffekte sind nicht enthalten.",

    ["HELP_BASEGS_HEADING"] = "Unverbesserten GS anzeigen",
    ["HELP_BASEGS_1"] =
    "Zeigt dieselben ausgerüsteten Gegenstände, nachdem nur die gezählten Boni aus installierten dauerhaften Verzauberungen und Edelsteinen entfernt wurden. Es ist ein optionaler Vergleich, um zu sehen, wie stark diese Verbesserungen beitragen, nicht der aktuelle GearScore des Spielers.",

    ["HELP_POTENTIALGS_HEADING"] = "Möglichen GS anzeigen",
    ["HELP_POTENTIALGS_1"] =
    "Zeigt den Aktuellen GS nach dem Hinzufügen ausschließlich bestätigter fehlender zulässiger dauerhafter Verzauberungen und bestätigter leerer Fassungen. Er erscheint nur, wenn genügend bestätigte Daten vorliegen, und empfiehlt keine konkreten Verzauberungen oder Edelsteine.",

    ["HELP_DELTA_HEADING"] = "Differenz anzeigen",
    ["HELP_DELTA_1"] =
    "Zeigt den bestätigten Unterschied zwischen Möglichem GS und Aktuellem GS. Er stellt den zusätzlichen Punktwert dar, der aus bestätigten fehlenden Verbesserungen stammt, und keinen Vergleich mit dem Unverbesserten GS.",

    ["HELP_AVERAGEITEMLEVEL_HEADING"] = "Durchschnittliches iLvl anzeigen",
    ["HELP_AVERAGEITEMLEVEL_1"] =
    "Zeigt das durchschnittliche Item-Level der ausgerüsteten Ausrüstung, die in das feste Ausrüstungsmodell des Addons einbezogen ist.",

    ["HELP_COMPLETION_HEADING"] = "Vollständigkeit anzeigen",
    ["HELP_COMPLETION_1"] =
    "Zeigt den Anteil der gefüllten bestätigten zulässigen Chancen für dauerhafte Verzauberungen und Fassungen. Sie misst den Vollständigkeitsgrad der Verbesserungen, nicht die Optimal-Ausrüstung und nicht die Raid-Tauglichkeit.",

    ["HELP_RESTRICTLEVEL70_HEADING"] = "Mögliches GS, Vollständigkeit und Warnungen auf Stufe 70 beschränken",
    ["HELP_RESTRICTLEVEL70_1"] =
    "Blendet Möglichen GS, Differenz, Vollständigkeit und zugehörige Warnungen unterhalb von Stufe 70 aus. Aktueller GS, Unverbesserter GS und Durchschnittliches iLvl können weiterhin erscheinen.",

    ["HELP_WARNINGCOLORS_HEADING"] = "Warnfarben der Vollständigkeit",
    ["HELP_WARNINGCOLORS_1"] =
    "Färbt die Vollständigkeit anhand der etablierten Schwellenwerte des Addons. Ist die Option deaktiviert, bleibt die Vollständigkeit in einer neutralen Farbe sichtbar.",

    ["HELP_SHOWMINIMAP_HEADING"] = "Minikartenknopf anzeigen",
    ["HELP_SHOWMINIMAP_1"] =
    "Zeigt oder verbirgt die verschiebbare Minikartenverknüpfung. Ein Linksklick öffnet oder schließt die Optionsseite der Erweiterung, Ziehen verschiebt den Knopf.",

    ["HELP_SHOWSERVERRANK_HEADING"] = "Rang auf der Serverliste anzeigen",
    ["HELP_SHOWSERVERRANK_1"] =
    "Zeigt die GearScore-Rangfolge des Spielers auf dem Server und die Klassen-Einordnung in Tooltips an, sofern die Hintergrund-Synchronisation sie bereitstellt.",

    ["HELP_COMFORTABLEROWS_HEADING"] = "Komfortable Zeilen",
    ["HELP_COMFORTABLEROWS_1"] =
    "Vergrößert die Zeilen der Rangliste, damit die Schrift größer erscheint. Die Liste zeigt dieselben Spieler in derselben Reihenfolge, aber mit höheren Zeilen.",

    ["HELP_SHAMANBLUE_HEADING"] = "Schamane Blau",
    ["HELP_SHAMANBLUE_1"] =
    "Zeigt den Klassennamen des Schamanen in Blau statt in Rosa. Classic Era färbt die Klassenfarbe des Schamanen rosa, dies entspricht der Farbe, die TacoTip selbst verwendet.",
    ["HELP_SHAMANBLUE_2"] =
    "Wenn TacoTip installiert ist, gilt auch dessen eigene Einstellung Schamane Blau: Ist sie dort ausgeschaltet, ist auch hier der blaue Farbton aus, damit die Klassenfarbe in beiden Add-ons gleich ist.",

    ["HELP_OPENLEADERBOARD_HEADING"] = "Serverrangliste öffnen",
    ["HELP_OPENLEADERBOARD_1"] =
    "Öffnet das Fenster der TacoTip-GearScore-Serverrangliste (/ex ranks), um die realmweiten Platzierungen zu durchsehen.",

    ["HELP_RESTORE_HEADING"] = "TacoTip-Einstellungen wiederherstellen",
    ["HELP_RESTORE_1"] =
    "Deaktiviert die Tooltip-Ausgaben der Erweiterung und stellt sicher nur jene TacoTip-Einstellung für den Spieler-GearScore wieder her, die zuvor belegt wurde.",
    ["HELP_RESTORE_2"] =
    "Sie setzt keine anderen TacoTip-Optionen und keine verbleibenden Erweiterungseinstellungen zurück.",

    ["HELP_RESET_HEADING"] = "Erweiterungseinstellungen zurücksetzen",
    ["HELP_RESET_1"] =
    "Setzt die TacoTip-Extras-Einstellungen auf ihre Standardwerte zurück, einschließlich Tooltip-Vorlieben sowie Sichtbarkeit und Position des Minikartenknopfs.",
    ["HELP_RESET_2"] =
    "Sie setzt TacoTip nicht zurück. Auch die gespeicherte Rangliste bleibt unberührt: Die Realm-Wertung liegt in TacoTipExtrasDB und übersteht diesen Reset.",

    ["HELP_INTEGRATIONSTATUS_HEADING"] = "TacoTip-Integration",
    ["HELP_INTEGRATIONSTATUS_1"] =
    "Kompatibel bedeutet, dass die exakt erforderliche TacoTip-Version und die benötigten Fähigkeiten erkannt wurden. Bei Inkompatibilität bleibt die Erweiterung geschlossen und übernimmt keine TacoTip-Ausgabe für den Spieler-GearScore.",

    ["HELP_REMOTESTATUS_HEADING"] = "Entfernte Verbesserungsanalyse",
    ["HELP_REMOTESTATUS_1"] =
    "Entferntes Mögliches GS, Differenz und Vollständigkeit hängen von eindeutigen Inspect-Daten ab. Vollständig ist erfolgreich; nicht verfügbar bedeutet nicht null, während ausstehend, unterdrückt und nicht beobachtet neutrale Zustände sind.",

    ["HELP_BLOCKERSTATUS_HEADING"] = "Blocker der entfernten Verbesserungsanalyse",
    ["HELP_BLOCKERSTATUS_1"] =
    "Zeigt den aktuellen Grund, warum die entfernte Verbesserungsanalyse nicht verfügbar ist. Diese Diagnose ist vorübergehend und wird nicht als Spielerverlauf gespeichert.",

    ["HELP_EQUIPMENTMODE_HEADING"] = "Zusammenfassung für Charakter & Inspect",
    ["HELP_EQUIPMENTMODE_1"] =
    "Wähle, was die Erweiterung in beiden Ausrüstungsfenstern zeigt. Deaktiviert stellt die native GearScore- und iLvl-Anzeige von TacoTip wieder her. Einfach zeigt Aktuellen GS und Durchschnittliches iLvl. Detailliert ergänzt eindeutige Verbesserungskennzahlen.",

    ["HELP_EQUIPMENTSHOWUNENHANCED_HEADING"] = "Unverbesserten GS in Detailliert anzeigen",
    ["HELP_EQUIPMENTSHOWUNENHANCED_1"] =
    "Zeigt dieselbe Ausrüstung, bevor die von diesem Addon gezählten Boni aus installierten dauerhaften Verzauberungen und Edelsteinen berücksichtigt werden. Es ist ein Vergleichswert, nicht der Hauptwert.",

    ["HELP_EQUIPMENTUNLOCKPOSITIONS_HEADING"] = "Positionen der Zusammenfassung entsperren",
    ["HELP_EQUIPMENTUNLOCKPOSITIONS_1"] =
    "Zeigt in jedem Ausrüstungsfenster einen Ziehgriff. Charakter und Inspect behalten unabhängige Positionen.",

    ["HELP_EQUIPMENTRESETPOSITIONS_HEADING"] = "Positionen der Zusammenfassung zurücksetzen",
    ["HELP_EQUIPMENTRESETPOSITIONS_1"] =
    "Setzt beide Zusammenfassungsblöcke auf ihre geprüften Standardpositionen zurück, ohne andere Einstellungen zu verändern.",

    ["HELP_SCANNOW_HEADING"] = "Jetzt scannen",
    ["HELP_SCANNOW_1"] =
    "Führt sofort einen Scan-Durchlauf aus. Nur Spieler, deren Inspect das Spiel erlaubt, können gescannt werden; wie viele erreicht werden, hängt davon ab, was in Reichweite, in deiner Gruppe oder auf einer Namensplatte sichtbar ist.",

    ["MINIMAP_HINT"] = "TacoTip Extras",
    ["MINIMAP_HINT_LEFT"] = "Linksklick: Rangliste",
    ["MINIMAP_HINT_DRAG"] = "Ziehen zum Verschieben",

    ["LB_TITLE"] = "TacoTip-Gearscore-Rangliste",
    ["LB_REALM"] = "Gesamter Realm",
    ["LB_SEARCH"] = "Suchen:",
    ["LB_GUILD"] = "Gilde:",
    ["LB_YOU"] = "DU",
    ["LB_LOADING"] = "Rangliste wird geladen...",
    ["LB_EMPTY"] = "Noch keine Einträge. Werte werden während des Spiels synchronisiert.",
    ["LB_EMPTY_FILTERS"] = "Keine Spieler entsprechen den aktuellen Filtern.",
    ["LB_DB_UNAVAILABLE"] = "Die Rangdatenbank ist nicht verfügbar, daher können keine Ranglisten angezeigt werden.",
    ["LB_NOT_ESTABLISHED"] = "Noch nicht platziert",
    ["LB_ONLY_YOU"] = "Auf diesem Realm ist bisher nur dein eigener Charakter registriert.",
    ["LB_FILTER_ALL"] = "Alle",
    ["LB_TOP"] = "\226\150\178 Spitze",
    ["LB_SCAN"] = "Jetzt scannen",
    ["LB_SCAN_BUSY"] = "Scanne...",

    ["LB_COL_RANK"] = "RANG",
    ["LB_COL_GS"] = "GEARSCORE",
    ["LB_COL_ILVL"] = "iLVL",
    ["LB_COL_LEVEL"] = "STUFE",
    ["LB_COL_PLAYER"] = "SPIELER",
    ["LB_COL_LASTSEEN"] = "ZULETZT GESEHEN",

    ["LB_TIP_UNKNOWN"] = "Unbekannt",
    ["LB_TIP_UNKNOWNSPEC"] = "Unbekannte Spezialisierung",
    ["LB_TIP_GS"] = "GearScore: %d",
    ["LB_TIP_ILVL"] = "Durchschnittliches iLvl: %.1f",
    ["LB_TIP_PVP_RANK"] = "PvP-Rang: %s",
    ["LB_TIP_ARENA"] = "Arena-Beste: %d",
    ["LB_TIP_RANK"] = "GearScore-Rang: #%d",
    ["LB_TIP_LASTSEEN"] = "Zuletzt gesehen: %s",
    ["LB_TIP_RANK_SYNCED"] = "Rang synchronisiert: %s",
    ["LB_TIP_CLICK_GEAR"] = "Klicken, um Ausrüstung anzuzeigen",
    ["LB_SCAN_COMPLETE"] = "Scan abgeschlossen - %d Spieler erfasst",

    ["SORT_GS_DESC"] = "GEARSCORE",
    ["SORT_ILVL_DESC"] = "ITEMLEVEL",
    ["SORT_LEVEL_DESC"] = "STUFE",
    ["SORT_SEEN_DESC"] = "ZULTETZT GESEHEN",

    ["LB_STAT_STRIP"] = "%d Spieler | Beste %d | Durchschnitt %d",

    ["TIME_JUST_NOW"] = "Gerade eben",
    ["TIME_MIN_AGO"] = "vor %d Min.",
    ["TIME_HOUR_AGO"] = "vor %d Std.",
    ["TIME_DAY_AGO"] = "vor %d T.",

    ["GEAR_TITLE"] = "Ausrüstung von %s",
    ["GEAR_NOT_SCANNED"] = "Dieser Spieler wurde noch nicht gescannt, daher ist keine Ausrüstung verfügbar.",
    ["GEAR_DATA_UNAVAILABLE"] = "Die Ausrüstungsdaten sind für diesen Spieler derzeit nicht verfügbar. Drücke im Leaderboard auf Jetzt scannen und versuche es dann erneut.",

    ["SCAN_PROGRESS"] = "%d / %d",

    ["CLASS_DEATHKNIGHT"] = "Todesritter",
    ["CLASS_DEMONHUNTER"] = "Dämonenjäger",
    ["CLASS_DRUID"] = "Druide",
    ["CLASS_EVOKER"] = "Rufer",
    ["CLASS_HUNTER"] = "Jäger",
    ["CLASS_MAGE"] = "Magier",
    ["CLASS_MONK"] = "Mönch",
    ["CLASS_PALADIN"] = "Paladin",
    ["CLASS_PRIEST"] = "Priester",
    ["CLASS_ROGUE"] = "Schurke",
    ["CLASS_SHAMAN"] = "Schamane",
    ["CLASS_WARLOCK"] = "Hexenmeister",
    ["CLASS_WARRIOR"] = "Krieger",
    ["CLASS_UNKNOWN"] = "Unbekannt",
}

_G.TACOEXTRAS_LOCALES = _G.TACOEXTRAS_LOCALES or {}
_G.TACOEXTRAS_LOCALES["deDE"] = L

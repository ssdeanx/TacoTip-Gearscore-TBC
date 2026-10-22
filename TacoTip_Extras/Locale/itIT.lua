--[[

    TacoTip Extras Localization: itIT

--]]

local L = {
    ["TIME_UNKNOWN"] = "Sconosciuto",
    ["TIME_YESTERDAY"] = "Ieri",
    ["GEAR_NO_OPPORTUNITIES"] = "nessuna opportunità idonea",
    ["LB_COL_SPECCLASS"] = "SPEC / CLASSE",
    ["LB_MY_RANK_ARROW"] = "▼ La mia posizione",
    ["GEAR_SCANNING"] = "Analisi equipaggiamento...",
    ["LB_SORTED_BY"] = "Ordinato per %s %s",
    ["LB_FOOTER_NO_RANK"] = "%d giocatori registrati - nessuna classificazione",
    ["EQUIPMENT_CATEGORY_NAME"] = "Finestre equipaggiamento",
    ["MINIMAP_HINT_RIGHT"] = "Clic destro: impostazioni",
    ["COMPLETE"] = "Completo",
    ["GEAR_UNAVAILABLE"] = "Dati equipaggiamento non disponibili",
    ["LB_FOOTER_STANDING"] = "La tua posizione: #%d globale | #%d fazione | #%d classe  -  %d giocatori registrati",
    ["CATEGORY_NAME"] = "TacoTip Extras",

    ["INTRO"] =
    "Un modulo aggiuntivo per TacoTip che aggiunge alle tooltip del giocatore il GearScore, il livello oggetto medio e il completamento, tenendo conto dei miglioramenti.",

    ["SCORE_EXPLANATION"] =
    "Current GS è il GearScore attuale del giocatore in questo modulo e il valore in evidenza in modalità Compact. Usa Current GS quando ti riferisci al GearScore attuale del giocatore. Comprende gli oggetti equipaggiati più i bonus supportati dagli incantesimi permanenti e dalle gemme installati.\n\nUnenhanced GS è un confronto facoltativo che usa la stessa dotazione, privata dei soli bonus installati che vengono conteggiati. Mostra quanto apportano già quei miglioramenti; non è il GearScore attuale del giocatore.\n\nPotential GS aggiunge a Current GS soltanto gli incantesimi permanenti idonei mancanti e confermati, più le sedi vuote confermate. Delta è l'aumento da Current GS a Potential GS, mentre Completion mostra la quota di opportunità di miglioramento confermate già colmate.\n\nPotential GS e Completion non valutano l'equipaggiamento ideale, non consigliano miglioramenti specifici e non misurano la preparazione alla raid. I dati remoti incompleti vengono mostrati come non disponibili, mai come zero.",

    ["MODE_DISABLED"] = "Disattivato",
    ["MODE_MINIMAL"] = "Minimale",
    ["MODE_COMPACT"] = "Compatto",
    ["MODE_DETAILED"] = "Dettagliato",
    ["MODE_BASIC"] = "Base",

    ["CURRENT_GS"] = "GS attuale",
    ["UNENHANCED_GS"] = "GS non migliorato",
    ["POTENTIAL_GS"] = "GS potenziale",
    ["DELTA"] = "Differenza",
    ["AVERAGE_ILVL"] = "iLvl medio",
    ["COMPLETION"] = "Completamento",
    ["ENHANCEMENT_ANALYSIS"] = "Analisi dei miglioramenti",
    ["UNAVAILABLE"] = "Non disponibile",

    ["TOOLTIP_LABEL_ENHANCEMENT"] = "Analisi dei miglioramenti:",
    ["TOOLTIP_LABEL_COMPLETION"] = "Completamento:",
    ["TOOLTIP_LABEL_RANK"] = "Posizione GS:",

    ["HELP_ENABLED_HEADING"] = "Attiva il modulo",
    ["HELP_ENABLED_1"] =
    "Attiva o disattiva tutto l'output di TacoTip Extras. Quando disattivato, il modulo rilascia la gestione del GearScore del giocatore e ripristina in sicurezza l'impostazione di TacoTip di cui si occupa.",

    ["HELP_MODE_HEADING"] = "Modalità tooltip",
    ["HELP_MODE_1"] = "Disattivato: non mostra righe del modulo e rilascia la gestione del GearScore del giocatore di TacoTip.",
    ["HELP_MODE_2"] = "Minimale: mostra il riepilogo attivo più breve, dando priorità al GS attuale e all'iLvl medio.",
    ["HELP_MODE_3"] = "Compatto: mostra fino a due righe concise con GS attuale, iLvl medio, differenza utile e completamento quando disponibili.",
    ["HELP_MODE_4"] = "Dettagliato: mostra ogni metrica attiva su una riga separata con la propria etichetta.",

    ["HELP_SHIFTDETAILED_HEADING"] = "Maiusc per Dettagliato",
    ["HELP_SHIFTDETAILED_1"] =
    "Mostra temporaneamente l'output dettagliato mentre tieni premuto Maiusc in modalità Minimale o Compatta. Le modalità Dettagliato e Disattivato restano invariate.",

    ["HELP_FIELDS_HEADING"] = "Campi del tooltip",
    ["HELP_FIELDS_1"] =
    "Scegli quali metriche il modulo può mostrare. La modalità selezionata e la disponibilità dei dati possono comunque omettere una metrica attiva.",

    ["HELP_GEARSCORE_HEADING"] = "Mostra il GS attuale",
    ["HELP_GEARSCORE_1"] =
    "Mostra il GearScore attuale del giocatore e il valore GS in evidenza in modalità Compact. Combina il punteggio degli oggetti equipaggiati con i bonus supportati dagli incantesimi permanenti e dalle gemme installati; gli effetti temporanei dell'arma non sono inclusi.",

    ["HELP_BASEGS_HEADING"] = "Mostra il GS non migliorato",
    ["HELP_BASEGS_1"] =
    "Mostra gli stessi oggetti equipaggiati privati dei soli bonus conteggiati dagli incantesimi permanenti e dalle gemme installati. È un confronto facoltativo per vedere quanto apportano quei miglioramenti, non il GearScore attuale del giocatore.",

    ["HELP_POTENTIALGS_HEADING"] = "Mostra il GS potenziale",
    ["HELP_POTENTIALGS_1"] =
    "Mostra il GS attuale dopo aver aggiunto soltanto gli incantesimi permanenti idonei mancanti e confermati e le sedi vuote confermate. Compare solo quando ci sono abbastanza dati confermati e non consiglia incantesimi o gemme specifici.",

    ["HELP_DELTA_HEADING"] = "Mostra la differenza",
    ["HELP_DELTA_1"] =
    "Mostra la differenza confermata tra GS potenziale e GS attuale. Rappresenta il punteggio aggiuntivo disponibile grazie ai miglioramenti confermati mancanti, non un confronto con il GS non migliorato.",

    ["HELP_AVERAGEITEMLEVEL_HEADING"] = "Mostra l'iLvl medio",
    ["HELP_AVERAGEITEMLEVEL_1"] =
    "Mostra il livello oggetto medio dell'equipaggiamento incluso nel modello fisso di slot del modulo.",

    ["HELP_COMPLETION_HEADING"] = "Mostra il completamento",
    ["HELP_COMPLETION_1"] =
    "Mostra la quota di opportunità confermate di incantesimo permanente e incastonatura già colmate. Misura il completamento dei miglioramenti, non l'equipaggiamento ideale o la preparazione alla raid.",

    ["HELP_RESTRICTLEVEL70_HEADING"] = "Limita GS potenziale, completamento e avvisi al livello 70",
    ["HELP_RESTRICTLEVEL70_1"] =
    "Nasconde GS potenziale, differenza, completamento e avvisi correlati sotto il livello 70. GS attuale, GS non migliorato e iLvl medio possono comunque comparire.",

    ["HELP_WARNINGCOLORS_HEADING"] = "Colori di avviso del completamento",
    ["HELP_WARNINGCOLORS_1"] =
    "Colora il completamento usando le soglie stabilite dal modulo. Se disattivato, il completamento resta visibile in un colore neutro.",

    ["HELP_SHOWMINIMAP_HEADING"] = "Mostra il pulsante sulla minimappa",
    ["HELP_SHOWMINIMAP_1"] =
    "Mostra o nasconde il collegamento sulla minimappa, che è spostabile. Il clic sinistro apre o chiude la pagina delle opzioni del modulo e trascinando si sposta il pulsante.",

    ["HELP_SHOWSERVERRANK_HEADING"] = "Mostra la posizione nella classifica del server",
    ["HELP_SHOWSERVERRANK_1"] =
    "Mostra la posizione del giocatore per GearScore nel server e la sua posizione di classe nei tooltip quando il motore di sincronizzazione in background la fornisce.",

    ["HELP_COMFORTABLEROWS_HEADING"] = "Righe comode",
    ["HELP_COMFORTABLEROWS_1"] =
    "Ingrandisce le righe della classifica per un testo più grande. L'elenco mostra gli stessi giocatori nello stesso ordine, ma con righe più alte.",

    ["HELP_SHAMANBLUE_HEADING"] = "Sciamano Blu",
    ["HELP_SHAMANBLUE_1"] =
    "Mostra il nome della classe dello sciamano in blu invece che in rosa. Classic Era colora la classe dello sciamano di rosa, quindi è lo stesso colore usato da TacoTip stesso.",
    ["HELP_SHAMANBLUE_2"] =
    "Quando TacoTip è installato, vale anche la sua impostazione Sciamano Blu: disattivarla lì disattiva il blu anche qui, così il colore della classe è lo stesso in entrambi i moduli.",

    ["HELP_OPENLEADERBOARD_HEADING"] = "Apri la classifica del server",
    ["HELP_OPENLEADERBOARD_1"] =
    "Apre la finestra della classifica GearScore di TacoTip (/tt ranks) per consultare le classifiche di tutto il regno.",

    ["HELP_RESTORE_HEADING"] = "Ripristina le impostazioni di TacoTip",
    ["HELP_RESTORE_1"] =
    "Disattiva l'output del modulo sui tooltip e ripristina in sicurezza solo l'impostazione del GearScore del giocatore di TacoTip che era stata presa in carico.",
    ["HELP_RESTORE_2"] =
    "Non reimposta le altre opzioni di TacoTip né le tue preferenze rimaste del modulo.",

    ["HELP_RESET_HEADING"] = "Reimposta le impostazioni del modulo",
    ["HELP_RESET_1"] =
    "Riporta le impostazioni di TacoTip Extras ai valori predefinite, incluse le preferenze del tooltip e la visibilità e la posizione del pulsante sulla minimappa.",
    ["HELP_RESET_2"] =
    "Non reimposta TacoTip. Non tocca nemmeno la classifica salvata: i risultati del reame vivono in TacoTipExtrasDB e sopravvivono a questo ripristino.",

    ["HELP_INTEGRATIONSTATUS_HEADING"] = "Integrazione con TacoTip",
    ["HELP_INTEGRATIONSTATUS_1"] =
    "Compatibile significa che sono stati rilevati la versione esatta richiesta di TacoTip e le funzionalità necessarie. Se non è compatibile, il modulo resta chiuso e non assume il controllo dell'output GearScore del giocatore di TacoTip.",

    ["HELP_REMOTESTATUS_HEADING"] = "Analisi remota dei miglioramenti",
    ["HELP_REMOTESTATUS_1"] =
    "GS potenziale, differenza e completamento remoti dipendono da dati di ispezione conclusivi. Completo indica un esito riuscito; non disponibile non significa zero, mentre in sospeso, soppresso e non osservato sono stati neutri.",

    ["HELP_BLOCKERSTATUS_HEADING"] = "Blocco dell'analisi remota",
    ["HELP_BLOCKERSTATUS_1"] =
    "Mostra il motivo attuale per cui l'analisi remota dei miglioramenti non è disponibile. Questa diagnostica è temporanea e non viene conservata come cronologia del giocatore.",

    ["HELP_EQUIPMENTMODE_HEADING"] = "Riepilogo personaggio e ispezione",
    ["HELP_EQUIPMENTMODE_1"] =
    "Scegli cosa mostra il modulo in entrambe le finestre di dotazione. Disattivato ripristina la visualizzazione nativa GearScore e iLvl di TacoTip. Base mostra GS attuale e iLvl medio. Dettagliato aggiunge metriche di miglioramento conclusive.",

    ["HELP_EQUIPMENTSHOWUNENHANCED_HEADING"] = "Mostra il GS non migliorato in Dettagliato",
    ["HELP_EQUIPMENTSHOWUNENHANCED_1"] =
    "Mostra la stessa dotazione prima dei bonus che questo modulo conta dagli incantesimi permanenti e dalle gemme installati. È un valore di confronto, non il punteggio principale.",

    ["HELP_EQUIPMENTUNLOCKPOSITIONS_HEADING"] = "Sblocca le posizioni del riepilogo",
    ["HELP_EQUIPMENTUNLOCKPOSITIONS_1"] =
    "Mostra una maniglia in ogni finestra di dotazione. Personaggio e Ispezione mantengono posizioni indipendenti.",

    ["HELP_EQUIPMENTRESETPOSITIONS_HEADING"] = "Reimposta le posizioni del riepilogo",
    ["HELP_EQUIPMENTRESETPOSITIONS_1"] =
    "Riporta entrambi i blocchi del riepilogo alle posizioni predefinite testate senza modificare le altre impostazioni.",

    ["HELP_SCANNOW_HEADING"] = "Scansiona ora",
    ["HELP_SCANNOW_1"] =
    "Esegue subito un passaggio di scansione. Si possono scansionare solo i giocatori che il gioco permette di ispezionare, quindi quanti ne raggiungi dipende da chi hai a portata, nel gruppo o visibile su una targhetta.",

    ["MINIMAP_HINT"] = "TacoTip Extras",
    ["MINIMAP_HINT_LEFT"] = "Clic sinistro: classifica",
    ["MINIMAP_HINT_DRAG"] = "Trascina per spostare",

    ["LB_TITLE"] = "Classifica GearScore di TacoTip",
    ["LB_REALM"] = "Tutto il regno",
    ["LB_SEARCH"] = "Cerca:",
    ["LB_GUILD"] = "Gilda:",
    ["LB_YOU"] = "TU",
    ["LB_LOADING"] = "Caricamento della classifica...",
    ["LB_EMPTY"] = "Ancora nessun dato. I punteggi si sincronizzano mentre giochi.",
    ["LB_EMPTY_FILTERS"] = "Nessun giocatore corrisponde ai filtri attuali.",
    ["LB_DB_UNAVAILABLE"] = "Il database delle classifiche non è disponibile, quindi non è possibile mostrare le classifiche.",
    ["LB_NOT_ESTABLISHED"] = "Ancora senza posizione",
    ["LB_ONLY_YOU"] = "Per ora, su questo regno è registrato solo il tuo personaggio.",
    ["LB_FILTER_ALL"] = "Tutti",
    ["LB_TOP"] = "\226\150\178 Il primo",
    ["LB_SCAN"] = "Scansiona ora",
    ["LB_SCAN_BUSY"] = "Scansione in corso...",

    ["LB_COL_RANK"] = "POSIZIONE",
    ["LB_COL_GS"] = "GEARSCORE",
    ["LB_COL_ILVL"] = "iLVL",
    ["LB_COL_LEVEL"] = "LIVELLO",
    ["LB_COL_PLAYER"] = "GIOCATORE",
    ["LB_COL_LASTSEEN"] = "ULTIMO ACCESSO",

    ["LB_TIP_UNKNOWN"] = "Sconosciuto",
    ["LB_TIP_UNKNOWNSPEC"] = "Specializzazione sconosciuta",
    ["LB_TIP_GS"] = "GearScore: %d",
    ["LB_TIP_ILVL"] = "iLvl medio: %.1f",
    ["LB_TIP_PVP_RANK"] = "Grado PvP: %s",
    ["LB_TIP_ARENA"] = "Miglior arena: %d",
    ["LB_TIP_RANK"] = "Posizione GearScore: #%d",
    ["LB_TIP_LASTSEEN"] = "Visto l'ultima volta: %s",
    ["LB_TIP_RANK_SYNCED"] = "Grado sincronizzato: %s",
    ["LB_TIP_CLICK_GEAR"] = "Fai clic per vedere la dotazione",
    ["LB_SCAN_COMPLETE"] = "Scansione completata - %d giocatori registrati",

    ["SORT_GS_DESC"] = "GEARSCORE",
    ["SORT_ILVL_DESC"] = "LIVELLO OGGETTO",
    ["SORT_LEVEL_DESC"] = "LIVELLO",
    ["SORT_SEEN_DESC"] = "VISTO L'ULTIMA VOLTA",

    ["LB_STAT_STRIP"] = "%d giocatori | Max %d | Media %d",

    ["TIME_JUST_NOW"] = "Adesso",
    ["TIME_MIN_AGO"] = "%d min fa",
    ["TIME_HOUR_AGO"] = "%d h fa",
    ["TIME_DAY_AGO"] = "%d g fa",

    ["GEAR_TITLE"] = "Dotazione di %s",
    ["GEAR_NOT_SCANNED"] = "Questo giocatore non è ancora stato scansionato, quindi non c'è dotazione disponibile.",
    ["GEAR_DATA_UNAVAILABLE"] = "I dati dell'equipaggiamento non sono disponibili per questo giocatore al momento. Premi Scansiona ora nella classifica, quindi riprova.",

    ["SCAN_PROGRESS"] = "%d / %d",

    ["CLASS_DEATHKNIGHT"] = "Paladino della Morte",
    ["CLASS_DEMONHUNTER"] = "Cacciatore di demoni",
    ["CLASS_DRUID"] = "Druido",
    ["CLASS_EVOKER"] = "Evocatore",
    ["CLASS_HUNTER"] = "Cacciatore",
    ["CLASS_MAGE"] = "Mago",
    ["CLASS_MONK"] = "Monaco",
    ["CLASS_PALADIN"] = "Paladino",
    ["CLASS_PRIEST"] = "Sacerdote",
    ["CLASS_ROGUE"] = "Ladro",
    ["CLASS_SHAMAN"] = "Sciamano",
    ["CLASS_WARLOCK"] = "Stregone",
    ["CLASS_WARRIOR"] = "Guerriero",
    ["CLASS_UNKNOWN"] = "Sconosciuto",
}

_G.TACOEXTRAS_LOCALES = _G.TACOEXTRAS_LOCALES or {}
_G.TACOEXTRAS_LOCALES["itIT"] = L

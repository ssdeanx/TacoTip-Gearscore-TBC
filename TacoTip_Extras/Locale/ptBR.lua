--[[

    TacoTip Extras Localization: ptBR

--]]

local L = {
    ["TIME_UNKNOWN"] = "Desconhecido",
    ["TIME_YESTERDAY"] = "Ontem",
    ["GEAR_NO_OPPORTUNITIES"] = "sem oportunidades elegíveis",
    ["LB_COL_SPECCLASS"] = "ESPEC. / CLASSE",
    ["LB_MY_RANK_ARROW"] = "▼ Minha posição",
    ["GEAR_SCANNING"] = "Analisando equipamento...",
    ["LB_SORTED_BY"] = "Ordenado por %s %s",
    ["LB_FOOTER_NO_RANK"] = "%d jogadores registrados - ainda sem classificação",
    ["EQUIPMENT_CATEGORY_NAME"] = "Janelas de equipamento",
    ["MINIMAP_HINT_RIGHT"] = "Clique direito: configurações",
    ["COMPLETE"] = "Completo",
    ["GEAR_UNAVAILABLE"] = "Dados de equipamento indisponíveis",
    ["LB_FOOTER_STANDING"] = "Sua posição: #%d geral | #%d facção | #%d classe  -  %d jogadores registrados",
    ["CATEGORY_NAME"] = "TacoTip Extras",

    ["INTRO"] =
    "Um complemento para o TacoTip que adiciona o GearScore, o nível de item médio e a conclusão aos tooltips do jogador, com análise de melhorias.",

    ["SCORE_EXPLANATION"] =
    "Current GS é o GearScore atual do jogador neste complemento e o valor destacado no modo Compact. Use Current GS ao se referir ao GearScore atual do jogador. Ele inclui os itens equipados mais os bônus suportados de encantamentos permanentes e gemas instalados.\n\nUnenhanced GS é uma comparação opcional que usa o mesmo equipamento sem apenas esses bônus instalados que são contados. Ele mostra quanto essas melhorias já contribuem; não é o GearScore atual do jogador.\n\nPotential GS adiciona ao Current GS apenas os encantamentos permanentes elegíveis que faltam e foram confirmados, além dos encaixes vazios confirmados. Delta é o aumento do Current GS até o Potential GS, enquanto Completion mostra a parte das oportunidades de melhoria confirmadas que já foram preenchidas.\n\nPotential GS e Completion não avaliam o melhor equipamento possível, não recomendam melhorias específicas e não medem prontidão para incursão. Dados remotos incompletos aparecem como indisponíveis, nunca como zero.",

    ["MODE_DISABLED"] = "Desativado",
    ["MODE_MINIMAL"] = "Mínimo",
    ["MODE_COMPACT"] = "Compacto",
    ["MODE_DETAILED"] = "Detalhado",
    ["MODE_BASIC"] = "Básico",

    ["CURRENT_GS"] = "GS atual",
    ["UNENHANCED_GS"] = "GS sem melhorias",
    ["POTENTIAL_GS"] = "GS potencial",
    ["DELTA"] = "Diferença",
    ["AVERAGE_ILVL"] = "iLvl médio",
    ["COMPLETION"] = "Conclusão",
    ["ENHANCEMENT_ANALYSIS"] = "Análise de melhorias",
    ["UNAVAILABLE"] = "Indisponível",

    ["TOOLTIP_LABEL_ENHANCEMENT"] = "Análise de melhorias:",
    ["TOOLTIP_LABEL_COMPLETION"] = "Conclusão:",
    ["TOOLTIP_LABEL_RANK"] = "Posição GS:",

    ["HELP_ENABLED_HEADING"] = "Ativar o complemento",
    ["HELP_ENABLED_1"] =
    "Ativa ou desativa toda a saída do TacoTip Extras. Quando desativado, o complemento libera o controle do GearScore do jogador e restaura com segurança a configuração do TacoTip que ele gerencia.",

    ["HELP_MODE_HEADING"] = "Modo do tooltip",
    ["HELP_MODE_1"] = "Desativado: não mostra linhas do complemento e libera o controle do GearScore do jogador do TacoTip.",
    ["HELP_MODE_2"] = "Mínimo: mostra o resumo ativo mais curto, priorizando o GS atual e o iLvl médio.",
    ["HELP_MODE_3"] = "Compacto: mostra até duas linhas concisas com GS atual, iLvl médio, diferença útil e conclusão quando disponíveis.",
    ["HELP_MODE_4"] = "Detalhado: mostra cada métrica ativa em uma linha separada com seu próprio rótulo.",

    ["HELP_SHIFTDETAILED_HEADING"] = "Shift para Detalhado",
    ["HELP_SHIFTDETAILED_1"] =
    "Mostra temporariamente a saída detalhada enquanto Shift estiver pressionado no modo Mínimo ou Compacto. Os modos Detalhado e Desativado não mudam.",

    ["HELP_FIELDS_HEADING"] = "Campos do tooltip",
    ["HELP_FIELDS_1"] =
    "Escolha quais métricas o complemento pode exibir. O modo selecionado e a disponibilidade dos dados ainda podem omitir uma métrica ativada.",

    ["HELP_GEARSCORE_HEADING"] = "Mostrar o GS atual",
    ["HELP_GEARSCORE_1"] =
    "Mostra o GearScore atual do jogador e o valor de GS em destaque no modo Compact. Ele combina a pontuação dos itens equipados com os bônus suportados de encantamentos permanentes e gemas instalados; efeitos temporários de arma não entram.",

    ["HELP_BASEGS_HEADING"] = "Mostrar o GS sem melhorias",
    ["HELP_BASEGS_1"] =
    "Mostra os mesmos itens equipados sem apenas os bônus contados de encantamentos permanentes e gemas instalados. É uma comparação opcional para ver quanto essas melhorias contribuem, não o GearScore atual do jogador.",

    ["HELP_POTENTIALGS_HEADING"] = "Mostrar o GS potencial",
    ["HELP_POTENTIALGS_1"] =
    "Mostra o GS atual somando apenas os encantamentos permanentes elegíveis que faltam e foram confirmados e os encaixes vazios confirmados. Só aparece quando há dados confirmados suficientes e não recomenda encantamentos ou gemas específicos.",

    ["HELP_DELTA_HEADING"] = "Mostrar a diferença",
    ["HELP_DELTA_1"] =
    "Mostra a diferença confirmada entre o GS potencial e o GS atual. Representa a pontuação adicional disponível pelas melhorias confirmadas que faltam, não uma comparação com o GS sem melhorias.",

    ["HELP_AVERAGEITEMLEVEL_HEADING"] = "Mostrar o iLvl médio",
    ["HELP_AVERAGEITEMLEVEL_1"] =
    "Mostra o nível de item médio do equipamento incluído no modelo fixo de espaços do complemento.",

    ["HELP_COMPLETION_HEADING"] = "Mostrar a conclusão",
    ["HELP_COMPLETION_1"] =
    "Mostra a parte das oportunidades confirmadas de encantamento permanente e encaixe já preenchidas. Mede a conclusão das melhorias, não o melhor equipamento possível nem a prontidão para incursão.",

    ["HELP_RESTRICTLEVEL70_HEADING"] = "Restringir GS potencial, conclusão e avisos ao nível 70",
    ["HELP_RESTRICTLEVEL70_1"] =
    "Oculta GS potencial, diferença, conclusão e avisos relacionados abaixo do nível 70. GS atual, GS sem melhorias e iLvl médio ainda podem aparecer.",

    ["HELP_WARNINGCOLORS_HEADING"] = "Cores de aviso da conclusão",
    ["HELP_WARNINGCOLORS_1"] =
    "Colore a conclusão usando os limites estabelecidos pelo complemento. Quando desativado, a conclusão continua visível em uma cor neutra.",

    ["HELP_SHOWMINIMAP_HEADING"] = "Mostrar botão no minimapa",
    ["HELP_SHOWMINIMAP_1"] =
    "Mostra ou oculta o atalho do minimapa, que pode ser movido. O clique esquerdo abre ou fecha a página de opções do complemento, e arrastar move o botão.",

    ["HELP_SHOWSERVERRANK_HEADING"] = "Mostrar posição no ranking do servidor",
    ["HELP_SHOWSERVERRANK_1"] =
    "Mostra a posição do jogador por GearScore no servidor e a posição na classe nos tooltips quando o mecanismo de sincronização em segundo plano fornece o dado.",

    ["HELP_COMFORTABLEROWS_HEADING"] = "Linhas confortáveis",
    ["HELP_COMFORTABLEROWS_1"] =
    "Aumenta a altura das linhas do ranking para deixar o texto maior. A lista mostra os mesmos jogadores na mesma ordem, mas com linhas mais altas.",

    ["HELP_SHAMANBLUE_HEADING"] = "Xamã Azul",
    ["HELP_SHAMANBLUE_1"] =
    "Mostra o nome da classe do xamã em azul em vez de rosa. O Classic Era pinta a cor de classe do xamã de rosa, então fica igual à cor que o próprio TacoTip usa.",
    ["HELP_SHAMANBLUE_2"] =
    "Quando o TacoTip está instalado, a opção Xamã Azul dele também vale: desligar lá desliga o azul aqui também, para que a cor de classe seja a mesma nos dois complementos.",

    ["HELP_OPENLEADERBOARD_HEADING"] = "Abrir o ranking do servidor",
    ["HELP_OPENLEADERBOARD_1"] =
    "Abre a janela do ranking de GearScore do TacoTip (/tt ranks) para consultar as classificações do reino inteiro.",

    ["HELP_RESTORE_HEADING"] = "Restaurar configurações do TacoTip",
    ["HELP_RESTORE_1"] =
    "Desativa a saída do complemento nos tooltips e restaura com segurança apenas a configuração de GearScore do jogador do TacoTip que estava sob controle dele.",
    ["HELP_RESTORE_2"] =
    "Não redefine as outras opções do TacoTip nem as preferências restantes do complemento.",

    ["HELP_RESET_HEADING"] = "Redefinir configurações do complemento",
    ["HELP_RESET_1"] =
    "Restaura as configurações do TacoTip Extras para os padrões, incluindo as preferências do tooltip e a visibilidade e a posição do botão do minimapa.",
    ["HELP_RESET_2"] =
    "Não redefine o TacoTip. Também não toca na classificação salva: os resultados do reino ficam em TacoTipExtrasDB e sobrevivem a esta redefinição.",

    ["HELP_INTEGRATIONSTATUS_HEADING"] = "Integração com o TacoTip",
    ["HELP_INTEGRATIONSTATUS_1"] =
    "Compatível significa que a versão exata exigida do TacoTip e os recursos necessários foram detectados. Se não for compatível, o complemento permanece fechado e não assume a saída de GearScore do jogador do TacoTip.",

    ["HELP_REMOTESTATUS_HEADING"] = "Análise remota de melhorias",
    ["HELP_REMOTESTATUS_1"] =
    "GS potencial, diferença e conclusão remotos dependem de dados de inspeção conclusivos. Completo significa sucesso; indisponível não significa zero, enquanto pendente, suprimido e não observado são estados neutros.",

    ["HELP_BLOCKERSTATUS_HEADING"] = "Bloqueio da análise remota",
    ["HELP_BLOCKERSTATUS_1"] =
    "Mostra o motivo atual pelo qual a análise remota de melhorias está indisponível. Este diagnóstico é temporário e não é guardado como histórico do jogador.",

    ["HELP_EQUIPMENTMODE_HEADING"] = "Resumo de personagem e inspeção",
    ["HELP_EQUIPMENTMODE_1"] =
    "Escolha o que o complemento mostra nas duas janelas de equipamento. Desativado restaura a exibição nativa de GearScore e iLvl do TacoTip. Básico mostra o GS atual e o iLvl médio. Detalhado acrescenta métricas de melhoria conclusivas.",

    ["HELP_EQUIPMENTSHOWUNENHANCED_HEADING"] = "Mostrar o GS sem melhorias no Detalhado",
    ["HELP_EQUIPMENTSHOWUNENHANCED_1"] =
    "Mostra o mesmo equipamento antes dos bônus que este complemento conta a partir de encantamentos permanentes e gemas instalados. É um valor de comparação, não a pontuação principal.",

    ["HELP_EQUIPMENTUNLOCKPOSITIONS_HEADING"] = "Destravar posições do resumo",
    ["HELP_EQUIPMENTUNLOCKPOSITIONS_1"] =
    "Mostra uma alça em cada janela de equipamento. Personagem e Inspeção mantêm posições independentes.",

    ["HELP_EQUIPMENTRESETPOSITIONS_HEADING"] = "Redefinir posições do resumo",
    ["HELP_EQUIPMENTRESETPOSITIONS_1"] =
    "Restaura os dois blocos de resumo às posições padrão testadas sem alterar as outras configurações.",

    ["HELP_SCANNOW_HEADING"] = "Verificar agora",
    ["HELP_SCANNOW_1"] =
    "Executa uma verificação imediatamente. Só é possível verificar jogadores que o jogo permite inspecionar, então a quantidade depende de quem está por perto, no grupo ou visível em uma placa de nome.",

    ["MINIMAP_HINT"] = "TacoTip Extras",
    ["MINIMAP_HINT_LEFT"] = "Clique esquerdo: classificação",
    ["MINIMAP_HINT_DRAG"] = "Arraste para mover",

    ["LB_TITLE"] = "Ranking de GearScore do TacoTip",
    ["LB_REALM"] = "Reino inteiro",
    ["LB_SEARCH"] = "Buscar:",
    ["LB_GUILD"] = "Guilda:",
    ["LB_YOU"] = "VOCÊ",
    ["LB_LOADING"] = "Carregando o ranking...",
    ["LB_EMPTY"] = "Ainda sem dados. As pontuações são sincronizadas enquanto você joga.",
    ["LB_EMPTY_FILTERS"] = "Nenhum jogador corresponde aos filtros atuais.",
    ["LB_DB_UNAVAILABLE"] = "O banco de dados de classificação não está disponível, portanto não é possível mostrar as classificações.",
    ["LB_NOT_ESTABLISHED"] = "Ainda sem posição",
    ["LB_ONLY_YOU"] = "Por enquanto, só o seu personagem está registrado neste reino.",
    ["LB_FILTER_ALL"] = "Todos",
    ["LB_TOP"] = "\226\150\178 Topo",
    ["LB_SCAN"] = "Verificar agora",
    ["LB_SCAN_BUSY"] = "Verificando...",

    ["LB_COL_RANK"] = "POSIÇÃO",
    ["LB_COL_GS"] = "GEARSCORE",
    ["LB_COL_ILVL"] = "iLVL",
    ["LB_COL_LEVEL"] = "NÍVEL",
    ["LB_COL_PLAYER"] = "JOGADOR",
    ["LB_COL_LASTSEEN"] = "VISTO POR ÚLTIMO",

    ["LB_TIP_UNKNOWN"] = "Desconhecido",
    ["LB_TIP_UNKNOWNSPEC"] = "Especialização desconhecida",
    ["LB_TIP_GS"] = "GearScore: %d",
    ["LB_TIP_ILVL"] = "iLvl médio: %.1f",
    ["LB_TIP_PVP_RANK"] = "Rank PvP: %s",
    ["LB_TIP_ARENA"] = "Melhor arena: %d",
    ["LB_TIP_RANK"] = "Posição de GearScore: #%d",
    ["LB_TIP_LASTSEEN"] = "Visto por último: %s",
    ["LB_TIP_RANK_SYNCED"] = "Rank sincronizado: %s",
    ["LB_TIP_CLICK_GEAR"] = "Clique para ver o equipamento",
    ["LB_SCAN_COMPLETE"] = "Verificação concluída - %d jogadores registrados",

    ["SORT_GS_DESC"] = "GEARSCORE",
    ["SORT_ILVL_DESC"] = "NÍVEL DE ITEM",
    ["SORT_LEVEL_DESC"] = "NÍVEL",
    ["SORT_SEEN_DESC"] = "VISTO POR ÚLTIMO",

    ["LB_STAT_STRIP"] = "%d jogadores | Melhor %d | Média %d",

    ["TIME_JUST_NOW"] = "Agora mesmo",
    ["TIME_MIN_AGO"] = "há %d min",
    ["TIME_HOUR_AGO"] = "há %d h",
    ["TIME_DAY_AGO"] = "há %d d",

    ["GEAR_TITLE"] = "Equipamento de %s",
    ["GEAR_NOT_SCANNED"] = "Este jogador ainda não foi verificado, então não há equipamento disponível.",
    ["GEAR_DATA_UNAVAILABLE"] = "Os dados de equipamento não estão disponíveis para este jogador no momento. Pressione Verificar agora na classificação e tente novamente.",

    ["SCAN_PROGRESS"] = "%d / %d",

    ["CLASS_DEATHKNIGHT"] = "Paladino da Morte",
    ["CLASS_DEMONHUNTER"] = "Caçador de Demônios",
    ["CLASS_DRUID"] = "Druida",
    ["CLASS_EVOKER"] = "Evocador",
    ["CLASS_HUNTER"] = "Caçador",
    ["CLASS_MAGE"] = "Mago",
    ["CLASS_MONK"] = "Monge",
    ["CLASS_PALADIN"] = "Paladino",
    ["CLASS_PRIEST"] = "Sacerdote",
    ["CLASS_ROGUE"] = "Ladino",
    ["CLASS_SHAMAN"] = "Xamã",
    ["CLASS_WARLOCK"] = "Bruxo",
    ["CLASS_WARRIOR"] = "Guerreiro",
    ["CLASS_UNKNOWN"] = "Desconhecido",
}

_G.TACOEXTRAS_LOCALES = _G.TACOEXTRAS_LOCALES or {}
_G.TACOEXTRAS_LOCALES["ptBR"] = L

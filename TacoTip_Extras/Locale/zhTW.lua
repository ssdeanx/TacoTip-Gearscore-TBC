--[[

    TacoTip Extras Localization: zhTW

--]]

local L = {
    ["TIME_UNKNOWN"] = "未知",
    ["TIME_YESTERDAY"] = "昨天",
    ["GEAR_NO_OPPORTUNITIES"] = "沒有符合條件的提升空間",
    ["LB_COL_SPECCLASS"] = "專精 / 職業",
    ["LB_MY_RANK_ARROW"] = "▼ 我的排名",
    ["GEAR_SCANNING"] = "正在讀取裝備...",
    ["LB_SORTED_BY"] = "按 s s 排序",
    ["LB_FOOTER_NO_RANK"] = "已記錄 d 名玩家 - 你還沒有排名",
    ["EQUIPMENT_CATEGORY_NAME"] = "裝備視窗",
    ["MINIMAP_HINT_RIGHT"] = "右鍵：設定",
    ["COMPLETE"] = "已完成",
    ["GEAR_UNAVAILABLE"] = "裝備資料無法取得",
    ["LB_FOOTER_STANDING"] = "你的排名：總榜 #d | 陣營 #d | 職業 #d  -  已記錄 d 名玩家",
    ["CATEGORY_NAME"] = "TacoTip Extras",

    ["INTRO"] =
    "TacoTip 的輔助插件，在玩家提示方塊中加入裝備分數分析、平均物品等級與完成度。",

    ["SCORE_EXPLANATION"] =
    "Current GS 是本插件計算出的玩家目前裝備分數，也是精簡模式下顯示的主數值。需要指代玩家目前裝備分數時請使用 Current GS。它包含已裝備的物品，以及已安裝永久附魔與寶石提供的受支援加成。\n\nUnenhanced GS 是選用的對照數值：使用同樣的裝備，但只扣除其中計入的已安裝加成。它用於說明這些強化已經貢獻了多少，並不等於玩家目前的裝備分數。\n\nPotential GS 在 Current GS 的基礎上，只加上已確認缺少的可用永久附魔與已確認的空插槽。Delta 是 Current GS 到 Potential GS 的提升量，Completion 則表示已確認的強化機會中已填充的比例。\n\nPotential GS 與 Completion 不會評價最佳裝備、不會推薦具體的強化方式，也不衡量副本戰備程度。遠端資料不完整時會顯示為無法取得，而不會顯示為零。",

    ["MODE_DISABLED"] = "關閉",
    ["MODE_MINIMAL"] = "最簡",
    ["MODE_COMPACT"] = "精簡",
    ["MODE_DETAILED"] = "詳細",
    ["MODE_BASIC"] = "基礎",

    ["CURRENT_GS"] = "目前分數",
    ["UNENHANCED_GS"] = "無強化分數",
    ["POTENTIAL_GS"] = "潛在分數",
    ["DELTA"] = "差值",
    ["AVERAGE_ILVL"] = "平均裝等",
    ["COMPLETION"] = "完成度",
    ["ENHANCEMENT_ANALYSIS"] = "強化分析",
    ["UNAVAILABLE"] = "無法取得",

    ["TOOLTIP_LABEL_ENHANCEMENT"] = "強化分析：",
    ["TOOLTIP_LABEL_COMPLETION"] = "完成度：",
    ["TOOLTIP_LABEL_RANK"] = "裝備分數排名：",

    ["REMOTE_COMPLETE"] = "完整",
    ["REMOTE_UNAVAILABLE"] = "無法取得",
    ["REMOTE_PENDING"] = "等待中",
    ["REMOTE_SUPPRESSED"] = "已抑制",
    ["REMOTE_NOT_OBSERVED"] = "未觀測",

    ["INTEGRATION_COMPATIBLE"] = "相容",
    ["INTEGRATION_INCOMPATIBLE"] = "不相容",
    ["INTEGRATION_MISSING"] = "未載入",

    ["OPTIONS_PAGE"] = "TacoTip Extras",
    ["OPTIONS_TAB_TOOLTIP"] = "提示方塊",
    ["OPTIONS_TAB_EQUIPMENT"] = "角色與檢視",
    ["SECTION_TOOLTIP"] = "提示方塊",
    ["SECTION_EQUIPMENT"] = "角色與檢視",
    ["SECTION_HELP"] = "分數是如何計算的",
    ["SECTION_ADVANCED"] = "進階",

    ["OPT_ENABLED"] = "啟用插件",
    ["OPT_TOOLTIP_MODE"] = "提示方塊模式",
    ["OPT_SHIFT_DETAILED"] = "按住 Shift 顯示詳細",
    ["OPT_FIELDS"] = "提示方塊欄位",
    ["OPT_MINIMAP"] = "顯示小地圖按鈕",
    ["OPT_SERVER_RANK"] = "顯示伺服器排名",
    ["OPT_HOW_SCORES_WORK"] = "分數是如何計算的",
    ["OPT_RESTORE"] = "還原 TacoTip 設定",
    ["OPT_RESET"] = "重設插件設定",
    ["OPT_EQUIPMENT_MODE"] = "角色與檢視摘要",
    ["OPT_EQUIPMENT_UNENHANCED"] = "在詳細模式顯示無強化分數",
    ["OPT_EQUIPMENT_UNLOCK"] = "解鎖摘要位置",
    ["OPT_EQUIPMENT_RESET"] = "重設摘要位置",
    ["OPT_SCAN_NOW"] = "立即掃描",
    ["OPT_SCAN_NOW_DESC"] =
    "掃描目前可以檢視的玩家，並補上尚未取得的裝備分數。",

    ["HELP_ENABLED_HEADING"] = "啟用插件",
    ["HELP_ENABLED_1"] =
    "啟用或關閉 TacoTip Extras 的全部輸出。關閉後，插件會交還玩家裝備分數的控制權，並安全還原它所管理的 TacoTip 設定。",

    ["HELP_MODE_HEADING"] = "提示方塊模式",
    ["HELP_MODE_1"] = "關閉：不顯示任何插件行，並交還 TacoTip 的玩家裝備分數控制權。",
    ["HELP_MODE_2"] = "最簡：只顯示已啟用內容中最短的一組，優先目前分數與平均裝等。",
    ["HELP_MODE_3"] = "精簡：最多顯示兩行，包含目前分數、平均裝等、有意義的差值以及可用時的完成度。",
    ["HELP_MODE_4"] = "詳細：把每一項已啟用的指標單獨放在一行並加上標籤。",

    ["HELP_SHIFTDETAILED_HEADING"] = "按住 Shift 顯示詳細",
    ["HELP_SHIFTDETAILED_1"] =
    "在最簡或精簡模式下，按住 Shift 暫時顯示詳細輸出。詳細與關閉模式維持不變。",

    ["HELP_FIELDS_HEADING"] = "提示方塊欄位",
    ["HELP_FIELDS_1"] =
    "選擇插件可以顯示哪些指標。所選模式與資料是否可用，仍可能讓某個已啟用的指標不被顯示。",

    ["HELP_GEARSCORE_HEADING"] = "顯示目前分數",
    ["HELP_GEARSCORE_1"] =
    "顯示玩家目前的裝備分數，也是精簡模式下的主分數。它把已裝備物品的分數與已安裝永久附魔和寶石提供的受支援加成相加；不包含武器的暫時效果。",

    ["HELP_BASEGS_HEADING"] = "顯示無強化分數",
    ["HELP_BASEGS_1"] =
    "顯示相同的已裝備物品，但只扣除其中計入的已安裝永久附魔與寶石加成。這是用於觀察強化貢獻的選用對照值，並不是玩家目前的裝備分數。",

    ["HELP_POTENTIALGS_HEADING"] = "顯示潛在分數",
    ["HELP_POTENTIALGS_1"] =
    "在目前分數上只加上已確認缺少的可用永久附魔與已確認的空插槽。只有在已確認資料足夠時才會出現，並且不會推薦具體的附魔或寶石。",

    ["HELP_DELTA_HEADING"] = "顯示差值",
    ["HELP_DELTA_1"] =
    "顯示潛在分數與目前分數之間已確認的差值。它代表已確認缺少強化所帶來的額外分數，而不是與無強化分數的比較。",

    ["HELP_AVERAGEITEMLEVEL_HEADING"] = "顯示平均裝等",
    ["HELP_AVERAGEITEMLEVEL_1"] =
    "顯示插件固定裝備欄位模型中所包含裝備的平均物品等級。",

    ["HELP_COMPLETION_HEADING"] = "顯示完成度",
    ["HELP_COMPLETION_1"] =
    "顯示已確認的永久附魔與插槽機會中已填充的比例。它衡量的是強化完成度，而不是最佳裝備或副本戰備程度。",

    ["HELP_RESTRICTLEVEL70_HEADING"] = "將潛在分數、完成度與提示限制在 70 級",
    ["HELP_RESTRICTLEVEL70_1"] =
    "在 70 級以下隱藏潛在分數、差值、完成度及相關提示。目前分數、無強化分數與平均裝等仍可能顯示。",

    ["HELP_WARNINGCOLORS_HEADING"] = "完成度警告顏色",
    ["HELP_WARNINGCOLORS_1"] =
    "使用插件既定的門檻來為完成度著色。關閉後，完成度仍會以中性顏色顯示。",

    ["HELP_SHOWMINIMAP_HEADING"] = "顯示小地圖按鈕",
    ["HELP_SHOWMINIMAP_1"] =
    "顯示或隱藏可移動的小地圖快捷按鈕。左鍵開啟或關閉插件的設定頁面，拖曳可移動按鈕。",

    ["HELP_SHOWSERVERRANK_HEADING"] = "顯示伺服器排名",
    ["HELP_SHOWSERVERRANK_1"] =
    "在背景同步引擎提供資料時，於提示方塊中顯示玩家的伺服器裝備分數排名與職業排名。",

    ["HELP_OPENLEADERBOARD_HEADING"] = "開啟伺服器排行榜",
    ["HELP_OPENLEADERBOARD_1"] =
    "開啟 TacoTip 裝備分數伺服器排行榜視窗（/tt ranks），瀏覽整個伺服器範圍的排名。",

    ["HELP_RESTORE_HEADING"] = "還原 TacoTip 設定",
    ["HELP_RESTORE_1"] =
    "關閉插件在提示方塊中的輸出，並只安全還原它先前接管的那一項 TacoTip 玩家裝備分數設定。",
    ["HELP_RESTORE_2"] =
    "它不會重設 TacoTip 的其他選項，也不會改動你保留的其餘插件偏好。",

    ["HELP_RESET_HEADING"] = "重設插件設定",
    ["HELP_RESET_1"] =
    "將 TacoTip Extras 設定還原為預設值，包括提示方塊偏好以及小地圖按鈕的可見性與位置。",
    ["HELP_RESET_2"] =
    "它不會重設 TacoTip，也不會影響已儲存的排行榜：伺服器排名保存在 TacoTipExtrasDB 中，重設後依然保留。",

    ["HELP_INTEGRATIONSTATUS_HEADING"] = "TacoTip 整合",
    ["HELP_INTEGRATIONSTATUS_1"] =
    "相容表示已偵測到所需的準確 TacoTip 版本與功能。若不相容，插件會保持關閉狀態，不會接管 TacoTip 的玩家裝備分數輸出。",

    ["HELP_REMOTESTATUS_HEADING"] = "遠端強化分析",
    ["HELP_REMOTESTATUS_1"] =
    "遠端的潛在分數、差值與完成度依賴確鑿的檢視資料。完整表示成功；無法取得並不等於零，而等待中、已抑制與未觀測都是中性狀態。",

    ["HELP_BLOCKERSTATUS_HEADING"] = "遠端強化分析受阻",
    ["HELP_BLOCKERSTATUS_1"] =
    "顯示目前無法進行遠端強化分析的原因。此診斷資訊是暫時的，不會保存為玩家歷史。",

    ["HELP_EQUIPMENTMODE_HEADING"] = "角色與檢視摘要",
    ["HELP_EQUIPMENTMODE_1"] =
    "選擇插件在兩個裝備視窗中顯示的內容。關閉會還原 TacoTip 原生的裝備分數與物品等級顯示；基礎顯示目前分數與平均裝等；詳細會加上確鑿的強化指標。",

    ["HELP_EQUIPMENTSHOWUNENHANCED_HEADING"] = "在詳細模式顯示無強化分數",
    ["HELP_EQUIPMENTSHOWUNENHANCED_1"] =
    "顯示未計入本插件從已安裝永久附魔與寶石中計算的加成之前的裝備。這是一個對照值，而不是主要分數。",

    ["HELP_EQUIPMENTUNLOCKPOSITIONS_HEADING"] = "解鎖摘要位置",
    ["HELP_EQUIPMENTUNLOCKPOSITIONS_1"] =
    "在每個裝備視窗中顯示一個拖曳握把。角色與檢視各自獨立保存位置。",

    ["HELP_EQUIPMENTRESETPOSITIONS_HEADING"] = "重設摘要位置",
    ["HELP_EQUIPMENTRESETPOSITIONS_1"] =
    "在不改變其他設定的前提下，把兩個摘要區塊還原到已測試的預設位置。",

    ["HELP_SCANNOW_HEADING"] = "立即掃描",
    ["HELP_SCANNOW_1"] =
    "立即開始掃描。遊戲只允許檢視你能觸及的玩家，因此能掃描到多少人取決於誰在你身邊、誰在隊伍或團隊中，以及誰的名字條可見。",

    ["MINIMAP_HINT"] = "TacoTip Extras",
    ["MINIMAP_HINT_LEFT"] = "左鍵：排行榜",
    ["MINIMAP_HINT_DRAG"] = "拖曳可移動",
    ["BLANK_DESC"] = "拖曳",
    ["BLANK"] = "無",

    ["LB_TITLE"] = "TacoTip 裝備分數排行榜",
    ["LB_REALM"] = "全伺服器",
    ["LB_SEARCH"] = "搜尋：",
    ["LB_YOU"] = "你",
    ["LB_LOADING"] = "正在載入排名...",
    ["LB_EMPTY"] = "尚無資料。分數會在你遊玩時同步。",
    ["LB_EMPTY_FILTERS"] = "沒有玩家符合目前的篩選條件。",
    ["LB_NOT_ESTABLISHED"] = "尚無排名",
    ["LB_ONLY_YOU"] = "本伺服器目前只記錄了你的角色。",
    ["LB_FILTER_ALL"] = "全部",
    ["LB_MY_RANK"] = "\226\152\148 我的排名",
    ["LB_TOP"] = "\226\152\160 榜首",
    ["LB_SCAN"] = "立即掃描",
    ["LB_SCAN_BUSY"] = "正在掃描...",
    ["LB_SCAN_IDLE"] = "閒置",

    ["LB_COL_RANK"] = "排名",
    ["LB_COL_ILVL"] = "iLVL",
    ["LB_COL_PLAYER"] = "玩家",
    ["LB_COL_LASTSEEN"] = "最後上線",
    ["LB_COL_GS"] = "GEARSCORE",

    ["LB_TIP_UNKNOWN"] = "未知",
    ["LB_TIP_UNKNOWNSPEC"] = "未知天賦",
    ["LB_TIP_GS"] = "裝備分數：%d",
    ["LB_TIP_ILVL"] = "平均裝等：%.1f",
    ["LB_TIP_RANK"] = "裝備分數排名：#%d",
    ["LB_TIP_CLASSRANK"] = "職業排名：#%d",
    ["LB_TIP_LASTSEEN"] = "最近見到：%s",

    ["SORT_GS_DESC"] = "裝備分數",
    ["SORT_ILVL_DESC"] = "物品等級",
    ["SORT_SEEN_DESC"] = "最近見到",


    ["TIME_JUST_NOW"] = "剛剛",
    ["TIME_MIN_AGO"] = "%d 分鐘前",
    ["TIME_HOUR_AGO"] = "%d 小時前",
    ["TIME_DAY_AGO"] = "%d 天前",

    ["GEAR_TITLE"] = "%s 的裝備",
    ["GEAR_NOT_SCANNED"] = "該玩家尚未掃描，因此沒有可顯示的裝備。",
    ["GEAR_NO_ITEMS"] = "沒有記錄到裝備。",
    ["GEAR_CLOSE"] = "關閉",

    ["SCAN_PROGRESS"] = "%d / %d",

    ["CLASS_DEATHKNIGHT"] = "死亡騎士",
    ["CLASS_DEMONHUNTER"] = "惡魔獵手",
    ["CLASS_DRUID"] = "德魯伊",
    ["CLASS_HUNTER"] = "獵人",
    ["CLASS_MAGE"] = "法師",
    ["CLASS_MONK"] = "武僧",
    ["CLASS_PALADIN"] = "聖騎士",
    ["CLASS_PRIEST"] = "牧師",
    ["CLASS_ROGUE"] = "盜賊",
    ["CLASS_SHAMAN"] = "薩滿",
    ["CLASS_WARLOCK"] = "術士",
    ["CLASS_WARRIOR"] = "戰士",
    ["CLASS_UNKNOWN"] = "未知",
}

_G.TACOEXTRAS_LOCALES = _G.TACOEXTRAS_LOCALES or {}
_G.TACOEXTRAS_LOCALES["zhTW"] = L

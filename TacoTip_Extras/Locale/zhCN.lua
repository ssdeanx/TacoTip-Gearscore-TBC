--[[

    TacoTip Extras Localization: zhCN

--]]

local L = {
    ["TIME_UNKNOWN"] = "未知",
    ["TIME_YESTERDAY"] = "昨天",
    ["GEAR_NO_OPPORTUNITIES"] = "没有符合条件的提升空间",
    ["LB_COL_SPECCLASS"] = "专精 / 职业",
    ["LB_MY_RANK_ARROW"] = "▼ 我的排名",
    ["GEAR_SCANNING"] = "正在读取装备...",
    ["LB_SORTED_BY"] = "按 %s %s 排序",
    ["LB_FOOTER_NO_RANK"] = "已记录 %d 名玩家 - 你还没有排名",
    ["EQUIPMENT_CATEGORY_NAME"] = "装备窗口",
    ["MINIMAP_HINT_RIGHT"] = "右键：设置",
    ["COMPLETE"] = "已完成",
    ["GEAR_UNAVAILABLE"] = "装备数据不可用",
    ["LB_FOOTER_STANDING"] = "你的排名：总榜 #%d | 阵营 #%d | 职业 #%d  -  已记录 %d 名玩家",
    ["CATEGORY_NAME"] = "TacoTip Extras",

    ["INTRO"] =
    "TacoTip 的辅助插件，在玩家提示框中加入装备分数分析、平均物品等级与完成度。",

    ["SCORE_EXPLANATION"] =
    "Current GS 是本插件计算出的玩家当前装备分数，也是精简模式下显示的主数值。需要指代玩家当前装备分数时请使用 Current GS。它包含已装备的物品，以及已安装永久附魔与宝石提供的受支持加成。\n\nUnenhanced GS 是可选的对比数值：使用同样的装备，但只去掉其中计入的已安装加成。它用于说明这些强化已经贡献了多少，并不等于玩家当前的装备分数。\n\nPotential GS 在 Current GS 的基础上，只加上已确认缺失的可用永久附魔与已确认的空插槽。Delta 是 Current GS 到 Potential GS 的提升量，Completion 则表示已确认的强化机会中已填充的比例。\n\nPotential GS 与 Completion 不会评价最佳装备、不会推荐具体的强化方式，也不衡量副本战备程度。远程数据不完整时会显示为不可用，而不会显示为零。",

    ["MODE_DISABLED"] = "关闭",
    ["MODE_MINIMAL"] = "最简",
    ["MODE_COMPACT"] = "精简",
    ["MODE_DETAILED"] = "详细",
    ["MODE_BASIC"] = "基础",

    ["CURRENT_GS"] = "当前分数",
    ["UNENHANCED_GS"] = "无强化分数",
    ["POTENTIAL_GS"] = "潜在分数",
    ["DELTA"] = "差值",
    ["AVERAGE_ILVL"] = "平均装等",
    ["COMPLETION"] = "完成度",
    ["ENHANCEMENT_ANALYSIS"] = "强化分析",
    ["UNAVAILABLE"] = "不可用",

    ["TOOLTIP_LABEL_ENHANCEMENT"] = "强化分析：",
    ["TOOLTIP_LABEL_COMPLETION"] = "完成度：",
    ["TOOLTIP_LABEL_RANK"] = "GS 排名：",

    ["HELP_ENABLED_HEADING"] = "启用插件",
    ["HELP_ENABLED_1"] =
    "启用或关闭 TacoTip Extras 的全部输出。关闭后，插件会交还玩家装备分数的控制权，并安全恢复它所管理的 TacoTip 设置。",

    ["HELP_MODE_HEADING"] = "提示框模式",
    ["HELP_MODE_1"] = "关闭：不显示任何插件行，并交还 TacoTip 的玩家装备分数控制权。",
    ["HELP_MODE_2"] = "最简：只显示已启用内容中最短的一组，优先当前分数与平均装等。",
    ["HELP_MODE_3"] = "精简：最多显示两行，包含当前分数、平均装等、有意义的差值以及可用时的完成度。",
    ["HELP_MODE_4"] = "详细：把每一项已启用的指标单独放在一行并加上标签。",

    ["HELP_SHIFTDETAILED_HEADING"] = "按住 Shift 显示详细",
    ["HELP_SHIFTDETAILED_1"] =
    "在最简或精简模式下，按住 Shift 临时显示详细输出。详细与关闭模式保持不变。",

    ["HELP_FIELDS_HEADING"] = "提示框字段",
    ["HELP_FIELDS_1"] =
    "选择插件可以显示哪些指标。所选模式与数据是否可用，仍可能让某个已启用的指标不被显示。",

    ["HELP_GEARSCORE_HEADING"] = "显示当前分数",
    ["HELP_GEARSCORE_1"] =
    "显示玩家当前的装备分数，也是精简模式下的主分数。它把已装备物品的分数与已安装永久附魔和宝石提供的受支持加成相加；不包含武器的临时效果。",

    ["HELP_BASEGS_HEADING"] = "显示无强化分数",
    ["HELP_BASEGS_1"] =
    "显示相同的已装备物品，但只去掉其中计入的已安装永久附魔与宝石加成。这是用于观察强化贡献的可选对比值，并不是玩家当前的装备分数。",

    ["HELP_POTENTIALGS_HEADING"] = "显示潜在分数",
    ["HELP_POTENTIALGS_1"] =
    "在当前分数上只加上已确认缺失的可用永久附魔与已确认的空插槽。只有在已确认数据足够时才会出现，并且不会推荐具体的附魔或宝石。",

    ["HELP_DELTA_HEADING"] = "显示差值",
    ["HELP_DELTA_1"] =
    "显示潜在分数与当前分数之间已确认的差值。它代表已确认缺失强化所带来的额外分数，而不是与无强化分数的比较。",

    ["HELP_AVERAGEITEMLEVEL_HEADING"] = "显示平均装等",
    ["HELP_AVERAGEITEMLEVEL_1"] =
    "显示插件固定装备栏位模型中所包含装备的平均物品等级。",

    ["HELP_COMPLETION_HEADING"] = "显示完成度",
    ["HELP_COMPLETION_1"] =
    "显示已确认的永久附魔与插槽机会中已填充的比例。它衡量的是强化完成度，而不是最佳装备或副本战备程度。",

    ["HELP_RESTRICTLEVEL70_HEADING"] = "将潜在分数、完成度与提示限制在 70 级",
    ["HELP_RESTRICTLEVEL70_1"] =
    "在 70 级以下隐藏潜在分数、差值、完成度及相关提示。当前分数、无强化分数与平均装等仍可能显示。",

    ["HELP_WARNINGCOLORS_HEADING"] = "完成度警告颜色",
    ["HELP_WARNINGCOLORS_1"] =
    "使用插件既定的阈值来为完成度着色。关闭后，完成度仍会以中性颜色显示。",

    ["HELP_SHOWMINIMAP_HEADING"] = "显示小地图按钮",
    ["HELP_SHOWMINIMAP_1"] =
    "显示或隐藏可移动的小地图快捷按钮。左键打开或关闭插件的设置页面，拖动可移动按钮。",

    ["HELP_SHOWSERVERRANK_HEADING"] = "显示服务器排名",
    ["HELP_SHOWSERVERRANK_1"] =
    "在后台同步引擎提供数据时，于提示框中显示玩家的服务器装备分数排名与职业排名。",

    ["HELP_COMFORTABLEROWS_HEADING"] = "宽松行高",
    ["HELP_COMFORTABLEROWS_1"] =
    "加高排行榜的行，让文字更大。列表显示的仍是同样的玩家和同样的顺序，只是行更高。",

    ["HELP_SHAMANBLUE_HEADING"] = "萨满蓝色",
    ["HELP_SHAMANBLUE_1"] =
    "把萨满祭司的职业名称显示为蓝色，而不是粉色。Classic Era 把萨满祭司的职业颜色画成粉色，因此这里与 TacoTip 本身使用的颜色一致。",
    ["HELP_SHAMANBLUE_2"] =
    "安装了 TacoTip 时，它自己的萨满蓝色设置同样生效：在那边关闭，这里也会关闭蓝色，这样两个插件的职业颜色保持一致。",

    ["HELP_OPENLEADERBOARD_HEADING"] = "打开服务器排行榜",
    ["HELP_OPENLEADERBOARD_1"] =
    "打开 TacoTip 装备分数服务器排行榜窗口（/ex ranks），浏览整个服务器范围的排名。",

    ["HELP_RESTORE_HEADING"] = "恢复 TacoTip 设置",
    ["HELP_RESTORE_1"] =
    "关闭插件在提示框中的输出，并只安全恢复它此前接管的那一项 TacoTip 玩家装备分数设置。",
    ["HELP_RESTORE_2"] =
    "它不会重置 TacoTip 的其他选项，也不会改动你保留的其余插件偏好。",

    ["HELP_RESET_HEADING"] = "重置插件设置",
    ["HELP_RESET_1"] =
    "将 TacoTip Extras 设置恢复为默认值，包括提示框偏好以及小地图按钮的可见性与位置。",
    ["HELP_RESET_2"] =
    "它不会重置 TacoTip，也不会影响已保存的排行榜：服务器排名保存在 TacoTipExtrasDB 中，重置后依然保留。",

    ["HELP_INTEGRATIONSTATUS_HEADING"] = "TacoTip 集成",
    ["HELP_INTEGRATIONSTATUS_1"] =
    "兼容表示已检测到所需的准确 TacoTip 版本与能力。若不兼容，插件会保持关闭状态，不会接管 TacoTip 的玩家装备分数输出。",

    ["HELP_REMOTESTATUS_HEADING"] = "远程强化分析",
    ["HELP_REMOTESTATUS_1"] =
    "远程的潜在分数、差值与完成度依赖确凿的查看数据。完整表示成功；不可用并不等于零，而等待中、已抑制与未观测都是中性状态。",

    ["HELP_BLOCKERSTATUS_HEADING"] = "远程强化分析受阻",
    ["HELP_BLOCKERSTATUS_1"] =
    "显示当前无法进行远程强化分析的原因。此诊断信息是临时的，不会保存为玩家历史。",

    ["HELP_EQUIPMENTMODE_HEADING"] = "角色与查看摘要",
    ["HELP_EQUIPMENTMODE_1"] =
    "选择插件在两个装备窗口中显示的内容。关闭会恢复 TacoTip 原生的装备分数与物品等级显示；基础显示当前分数与平均装等；详细会追加确凿的强化指标。",

    ["HELP_EQUIPMENTSHOWUNENHANCED_HEADING"] = "在详细模式显示无强化分数",
    ["HELP_EQUIPMENTSHOWUNENHANCED_1"] =
    "显示未计入本插件从已安装永久附魔与宝石中计算的加成之前的装备。它是一个对比值，而不是主要分数。",

    ["HELP_EQUIPMENTUNLOCKPOSITIONS_HEADING"] = "解锁摘要位置",
    ["HELP_EQUIPMENTUNLOCKPOSITIONS_1"] =
    "在每个装备窗口中显示一个拖动手柄。角色与查看各自独立保存位置。",

    ["HELP_EQUIPMENTRESETPOSITIONS_HEADING"] = "重置摘要位置",
    ["HELP_EQUIPMENTRESETPOSITIONS_1"] =
    "在不改变其他设置的前提下，把两个摘要块恢复到已测试的默认位置。",

    ["HELP_SCANNOW_HEADING"] = "立即扫描",
    ["HELP_SCANNOW_1"] =
    "立即开始扫描。游戏只允许查看你能触及的玩家，因此能扫描到多少人取决于谁在你身边、谁在队伍或团队中，以及谁的名字条可见。",

    ["MINIMAP_HINT"] = "TacoTip Extras",
    ["MINIMAP_HINT_LEFT"] = "左键：排行榜",
    ["MINIMAP_HINT_DRAG"] = "拖动可移动",

    ["LB_TITLE"] = "TacoTip 装备分数排行榜",
    ["LB_REALM"] = "全服务器",
    ["LB_SEARCH"] = "搜索：",
    ["LB_GUILD"] = "公会：",
    ["LB_YOU"] = "你",
    ["LB_LOADING"] = "正在加载排名...",
    ["LB_EMPTY"] = "暂无数据。分数会在你游戏时同步。",
    ["LB_EMPTY_FILTERS"] = "没有玩家符合当前筛选条件。",
    ["LB_DB_UNAVAILABLE"] = "排名数据库不可用，无法显示排名。",
    ["LB_NOT_ESTABLISHED"] = "暂无排名",
    ["LB_ONLY_YOU"] = "本服务器目前只记录了你的角色。",
    ["LB_FILTER_ALL"] = "全部",
    ["LB_TOP"] = "\226\150\178 榜首",
    ["LB_SCAN"] = "立即扫描",
    ["LB_SCAN_BUSY"] = "正在扫描...",

    ["LB_COL_RANK"] = "排名",
    ["LB_COL_GS"] = "GEARSCORE",
    ["LB_COL_ILVL"] = "iLVL",
    ["LB_COL_LEVEL"] = "等级",
    ["LB_COL_PLAYER"] = "玩家",
    ["LB_COL_LASTSEEN"] = "最后在线",

    ["LB_TIP_UNKNOWN"] = "未知",
    ["LB_TIP_UNKNOWNSPEC"] = "未知天赋",
    ["LB_TIP_GS"] = "装备分数：%d",
    ["LB_TIP_ILVL"] = "平均装等：%.1f",
    ["LB_TIP_PVP_RANK"] = "PvP 排名：%s",
    ["LB_TIP_ARENA"] = "竞技场最佳：%d",
    ["LB_TIP_RANK"] = "装备分数排名：#%d",
    ["LB_TIP_LASTSEEN"] = "最近见到：%s",
    ["LB_TIP_RANK_SYNCED"] = "排名已同步：%s",
    ["LB_TIP_CLICK_GEAR"] = "点击查看装备",
    ["LB_SCAN_COMPLETE"] = "扫描完成 - 已记录 %d 名玩家",

    ["SORT_GS_DESC"] = "装备分数",
    ["SORT_ILVL_DESC"] = "物品等级",
    ["SORT_LEVEL_DESC"] = "等级",
    ["SORT_SEEN_DESC"] = "最近见到",

    ["LB_STAT_STRIP"] = "%d 名玩家 | 最高 %d | 平均 %d",

    ["TIME_JUST_NOW"] = "刚刚",
    ["TIME_MIN_AGO"] = "%d 分钟前",
    ["TIME_HOUR_AGO"] = "%d 小时前",
    ["TIME_DAY_AGO"] = "%d 天前",

    ["GEAR_TITLE"] = "%s 的装备",
    ["GEAR_NOT_SCANNED"] = "该玩家尚未扫描，因此没有可显示的装备。",
    ["GEAR_DATA_UNAVAILABLE"] = "目前无法获取该玩家的装备数据。请在排行榜中点击立即扫描，然后重试。",

    ["SCAN_PROGRESS"] = "%d / %d",

    ["CLASS_DEATHKNIGHT"] = "死亡骑士",
    ["CLASS_DEMONHUNTER"] = "恶魔猎手",
    ["CLASS_DRUID"] = "德鲁伊",
    ["CLASS_EVOKER"] = "唤魔师",
    ["CLASS_HUNTER"] = "猎人",
    ["CLASS_MAGE"] = "法师",
    ["CLASS_MONK"] = "武僧",
    ["CLASS_PALADIN"] = "圣骑士",
    ["CLASS_PRIEST"] = "牧师",
    ["CLASS_ROGUE"] = "潜行者",
    ["CLASS_SHAMAN"] = "萨满祭司",
    ["CLASS_WARLOCK"] = "术士",
    ["CLASS_WARRIOR"] = "战士",
    ["CLASS_UNKNOWN"] = "未知",
}

_G.TACOEXTRAS_LOCALES = _G.TACOEXTRAS_LOCALES or {}
_G.TACOEXTRAS_LOCALES["zhCN"] = L

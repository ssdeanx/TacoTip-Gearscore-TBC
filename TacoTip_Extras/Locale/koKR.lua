--[[

    TacoTip Extras Localization: koKR

--]]

local L = {
    ["TIME_UNKNOWN"] = "알 수 없음",
    ["TIME_YESTERDAY"] = "어제",
    ["GEAR_NO_OPPORTUNITIES"] = "해당되는 기회 없음",
    ["LB_COL_SPECCLASS"] = "전문화 / 직업",
    ["LB_MY_RANK_ARROW"] = "▼ 내 순위",
    ["GEAR_SCANNING"] = "장비 확인 중...",
    ["LB_SORTED_BY"] = "s s 기준 정렬",
    ["LB_FOOTER_NO_RANK"] = "d명 기록됨 - 아직 순위가 없습니다",
    ["EQUIPMENT_CATEGORY_NAME"] = "장비 창",
    ["MINIMAP_HINT_RIGHT"] = "우클릭: 설정",
    ["COMPLETE"] = "완료",
    ["GEAR_UNAVAILABLE"] = "장비 데이터를 사용할 수 없음",
    ["LB_FOOTER_STANDING"] = "내 순위: 전체 #d | 진영 #d | 직업 #d  -  d명 기록됨",
    ["CATEGORY_NAME"] = "TacoTip Extras",

    ["INTRO"] =
    "TacoTip에 보정 분석을 더해 플레이어 툴팁에 GearScore, 평균 아이템 레벨, 완성도를 보여 주는 보조 애드온입니다.",

    ["SCORE_EXPLANATION"] =
    "Current GS는 이 애드온에서 계산한 플레이어의 현재 GearScore이며 Compact 모드에서 대표로 표시되는 값입니다. 플레이어의 현재 GearScore를 말할 때는 Current GS를 사용하세요. 장착한 아이템과 함께 설치된 영구 마법과 보석에서 지원되는 보너스를 포함합니다.\n\nUnenhanced GS는 같은 장비에서 위에서 계산한 영구 보너스만 제거한 선택적 비교값입니다. 그 보너스가 이미 얼마나 기여했는지 보여 주며, 플레이어의 현재 GearScore가 아닙니다.\n\nPotential GS는 Current GS에 확인된 누된 영구 마법과 확인된 빈 보석 자리만 더한 값입니다. Delta는 Current GS에서 Potential GS로의 증가량이고, Completion은 확인된 개선 기회 중 채워진 비율입니다.\n\nPotential GS와 Completion은 최적 장비를 평가하지도, 특정 마법이나 보석을 추천하지도 않으며, 레이드 준비도를 측정하지도 않습니다. 불완전한 원격 데이터는 0이 아니라 확인 불가로 표시됩니다.",

    ["MODE_DISABLED"] = "사용 안 함",
    ["MODE_MINIMAL"] = "최소",
    ["MODE_COMPACT"] = "간단",
    ["MODE_DETAILED"] = "상세",
    ["MODE_BASIC"] = "기본",

    ["CURRENT_GS"] = "현재 GS",
    ["UNENHANCED_GS"] = "미보정 GS",
    ["POTENTIAL_GS"] = "가능 GS",
    ["DELTA"] = "차이",
    ["AVERAGE_ILVL"] = "평균 아이템 레벨",
    ["COMPLETION"] = "완성도",
    ["ENHANCEMENT_ANALYSIS"] = "보정 분석",
    ["UNAVAILABLE"] = "확인 불가",

    ["TOOLTIP_LABEL_ENHANCEMENT"] = "보정 분석:",
    ["TOOLTIP_LABEL_COMPLETION"] = "완성도:",
    ["TOOLTIP_LABEL_RANK"] = "GearScore 순위:",

    ["REMOTE_COMPLETE"] = "완료",
    ["REMOTE_UNAVAILABLE"] = "확인 불가",
    ["REMOTE_PENDING"] = "대기 중",
    ["REMOTE_SUPPRESSED"] = "억제됨",
    ["REMOTE_NOT_OBSERVED"] = "관측되지 않음",

    ["INTEGRATION_COMPATIBLE"] = "호환됨",
    ["INTEGRATION_INCOMPATIBLE"] = "호환되지 않음",
    ["INTEGRATION_MISSING"] = "불러오지 않음",

    ["OPTIONS_PAGE"] = "TacoTip Extras",
    ["OPTIONS_TAB_TOOLTIP"] = "툴팁",
    ["OPTIONS_TAB_EQUIPMENT"] = "캐릭터 및 조사",
    ["SECTION_TOOLTIP"] = "툴팁",
    ["SECTION_EQUIPMENT"] = "캐릭터 및 조사",
    ["SECTION_HELP"] = "점수 계산 방식",
    ["SECTION_ADVANCED"] = "고급",

    ["OPT_ENABLED"] = "애드온 사용",
    ["OPT_TOOLTIP_MODE"] = "툴팁 모드",
    ["OPT_SHIFT_DETAILED"] = "Shift로 상세 보기",
    ["OPT_FIELDS"] = "툴팁 항목",
    ["OPT_MINIMAP"] = "미니맵 버튼 표시",
    ["OPT_SERVER_RANK"] = "서버 순위표 순위 표시",
    ["OPT_HOW_SCORES_WORK"] = "점수 계산 방식",
    ["OPT_RESTORE"] = "TacoTip 설정 복원",
    ["OPT_RESET"] = "애드온 설정 초기화",
    ["OPT_EQUIPMENT_MODE"] = "캐릭터 및 조사 요약",
    ["OPT_EQUIPMENT_UNENHANCED"] = "상세 모드에서 미보정 GS 표시",
    ["OPT_EQUIPMENT_UNLOCK"] = "요약 위치 잠금 해제",
    ["OPT_EQUIPMENT_RESET"] = "요약 위치 초기화",
    ["OPT_SCAN_NOW"] = "지금 검사",
    ["OPT_SCAN_NOW_DESC"] =
    "지금 접근할 수 있는 플레이어들을 검사하고 아직 모르는 GearScore를 채웁니다.",

    ["HELP_ENABLED_HEADING"] = "애드온 사용",
    ["HELP_ENABLED_1"] =
    "TacoTip Extras의 모든 출력을 켜거나 끕니다. 꺼져 있으면 플레이어 GearScore를 대신하던 권한을 내려놓고 직접 관리하던 TacoTip 설정을 안전하게 복원합니다.",

    ["HELP_MODE_HEADING"] = "툴팁 모드",
    ["HELP_MODE_1"] = "사용 안 함: 애드온 행을 표시하지 않고 TacoTip의 플레이어 GearScore 권한을 내려놓습니다.",
    ["HELP_MODE_2"] = "최소: 현재 GS와 평균 아이템 레벨을 우선하는 가장 짧은 요약을 표시합니다.",
    ["HELP_MODE_3"] = "간단: 현재 GS, 평균 아이템 레벨, 의미 있는 차이, 완성도를 최대 두 줄로 간결하게 표시합니다.",
    ["HELP_MODE_4"] = "상세: 사용 중인 각 항목을 별도의 줄에 이름표와 함께 표시합니다.",

    ["HELP_SHIFTDETAILED_HEADING"] = "Shift로 상세 보기",
    ["HELP_SHIFTDETAILED_1"] =
    "최소 또는 간단 모드에서 Shift를 누르고 있는 동안 상세 출력을 임시로 표시합니다. 상세와 사용 안 함 모드는 변하지 않습니다.",

    ["HELP_FIELDS_HEADING"] = "툴팁 항목",
    ["HELP_FIELDS_1"] =
    "애드온이 표시할 수 있는 항목을 고릅니다. 선택한 모드와 데이터 유무에 따라 켜 둔 항목이 표시되지 않을 수 있습니다.",

    ["HELP_GEARSCORE_HEADING"] = "현재 GS 표시",
    ["HELP_GEARSCORE_1"] =
    "플레이어의 현재 GearScore와 간단 모드의 대표 GS 값을 표시합니다. 장착한 아이템 점수에 설치된 영구 마법과 보석의 지원 보너스를 더하며, 무기 임시 효과는 포함하지 않습니다.",

    ["HELP_BASEGS_HEADING"] = "미보정 GS 표시",
    ["HELP_BASEGS_1"] =
    "같은 장착 아이템에서 설치된 영구 마법과 보석 중 계산되는 보너스만 제거한 값을 표시합니다. 그 보너스가 얼마나 기여하는지 보는 선택적 비교값이며 플레이어의 현재 GearScore가 아닙니다.",

    ["HELP_POTENTIALGS_HEADING"] = "가능 GS 표시",
    ["HELP_POTENTIALGS_1"] =
    "현재 GS에 확인된 누된 영구 마법과 확인된 빈 보석 자리만 더한 값을 표시합니다. 확인된 데이터가 충분히 있을 때만 나타나며 특정 마법이나 보석을 추천하지 않습니다.",

    ["HELP_DELTA_HEADING"] = "차이 표시",
    ["HELP_DELTA_1"] =
    "가능 GS와 현재 GS의 확인된 차이를 표시합니다. 미보정 GS와의 비교가 아니라 확인된 누된 보정으로 얻을 수 있는 추가 점수입니다.",

    ["HELP_AVERAGEITEMLEVEL_HEADING"] = "평균 아이템 레벨 표시",
    ["HELP_AVERAGEITEMLEVEL_1"] =
    "애드온의 고정 장비 슬롯 모델에 포함되는 장착 장비의 평균 아이템 레벨을 표시합니다.",

    ["HELP_COMPLETION_HEADING"] = "완성도 표시",
    ["HELP_COMPLETION_1"] =
    "확인된 영구 마법과 보석 자리 기회 중 채워진 비율을 표시합니다. 최적 장비나 레이드 준비도가 아니라 보정 완료 정도를 나타냅니다.",

    ["HELP_RESTRICTLEVEL70_HEADING"] = "가능 GS, 완성도, 경고를 70레벨로 제한",
    ["HELP_RESTRICTLEVEL70_1"] =
    "70레벨 미만에서는 가능 GS, 차이, 완성도와 관련 경고를 숨깁니다. 현재 GS, 미보정 GS, 평균 아이템 레벨은 계속 표시될 수 있습니다.",

    ["HELP_WARNINGCOLORS_HEADING"] = "완성도 경고 색상",
    ["HELP_WARNINGCOLORS_1"] =
    "애드온이 정한 기준에 따라 완성도에 색을 입힙니다. 끄면 완성도는 중립 색으로 계속 표시됩니다.",

    ["HELP_SHOWMINIMAP_HEADING"] = "미니맵 버튼 표시",
    ["HELP_SHOWMINIMAP_1"] =
    "이동 가능한 미니맵 바로 가기를 표시하거나 숨깁니다. 왼쪽 클릭으로 애드온 설정 페이지를 열고 닫고, 끌어서 버튼을 옮깁니다.",

    ["HELP_SHOWSERVERRANK_HEADING"] = "서버 순위표 순위 표시",
    ["HELP_SHOWSERVERRANK_1"] =
    "백그라운드 동기화 엔진이 제공할 때 툴팁에 플레이어의 서버 GearScore 순위와 직업 내 순위를 표시합니다.",

    ["HELP_OPENLEADERBOARD_HEADING"] = "서버 순위표 열기",
    ["HELP_OPENLEADERBOARD_1"] =
    "TacoTip GearScore 서버 순위표 창(/tt ranks)을 열어 영역 전체 순위를 확인합니다.",

    ["HELP_RESTORE_HEADING"] = "TacoTip 설정 복원",
    ["HELP_RESTORE_1"] =
    "애드온의 툴팁 출력을 끄고, 대신 관리하던 TacoTip 플레이어 GearScore 설정만 안전하게 복원합니다.",
    ["HELP_RESTORE_2"] =
    "TacoTip의 다른 옵션이나 남아 있는 애드온 환경 설정은 초기화하지 않습니다.",

    ["HELP_RESET_HEADING"] = "애드온 설정 초기화",
    ["HELP_RESET_1"] =
    "TacoTip Extras 설정을 기본값으로 되돌립니다. 툴팁 환경 설정과 미니맵 버튼의 표시 및 위치가 포함됩니다.",
    ["HELP_RESET_2"] =
    "TacoTip을 초기화하지 않습니다. 저장된 순위표도 건드리지 않습니다. 서버 순위는 TacoTipExtrasDB에 저장되어 이 초기화 후에도 남습니다.",

    ["HELP_INTEGRATIONSTATUS_HEADING"] = "TacoTip 연동",
    ["HELP_INTEGRATIONSTATUS_1"] =
    "호환됨은 요구하는 정확한 TacoTip 버전과 기능이 확인되었다는 뜻입니다. 호환되지 않으면 애드온은 안전 모드로 유지되고 TacoTip 플레이어 GearScore 출력을 대신하지 않습니다.",

    ["HELP_REMOTESTATUS_HEADING"] = "원격 보정 분석",
    ["HELP_REMOTESTATUS_1"] =
    "원격 가능 GS, 차이, 완성도는 확실한 조사 데이터에 의존합니다. 완료는 성공을 뜻하고 확인 불가는 0을 뜻하지 않습니다. 대기 중, 억제됨, 관측되지 않음은 중립 상태입니다.",

    ["HELP_BLOCKERSTATUS_HEADING"] = "원격 보정 분석 차단 사유",
    ["HELP_BLOCKERSTATUS_1"] =
    "원격 보정 분석을 현재 사용할 수 없는 이유를 표시합니다. 이 진단은 임시이며 플레이어 기록으로 저장되지 않습니다.",

    ["HELP_EQUIPMENTMODE_HEADING"] = "캐릭터 및 조사 요약",
    ["HELP_EQUIPMENTMODE_1"] =
    "두 장비 창에 애드온이 무엇을 보여 줄지 고릅니다. 사용 안 함은 TacoTip 기본 GearScore와 아이템 레벨 표시를 복원합니다. 기본은 현재 GS와 평균 아이템 레벨을, 상세는 확실한 보정 항목을 추가합니다.",

    ["HELP_EQUIPMENTSHOWUNENHANCED_HEADING"] = "상세 모드에서 미보정 GS 표시",
    ["HELP_EQUIPMENTSHOWUNENHANCED_1"] =
    "이 애드온이 설치된 영구 마법과 보석에서 계산하는 보너스를 적용하기 전의 같은 장비를 표시합니다. 비교값이며 주 점수가 아닙니다.",

    ["HELP_EQUIPMENTUNLOCKPOSITIONS_HEADING"] = "요약 위치 잠금 해제",
    ["HELP_EQUIPMENTUNLOCKPOSITIONS_1"] =
    "각 장비 창에 이동 손잡이를 표시합니다. 캐릭터와 조사는 서로 독립적인 위치를 유지합니다.",

    ["HELP_EQUIPMENTRESETPOSITIONS_HEADING"] = "요약 위치 초기화",
    ["HELP_EQUIPMENTRESETPOSITIONS_1"] =
    "다른 설정은 그대로 두고 두 요약 블록을 검증된 기본 위치로 되돌립니다.",

    ["HELP_SCANNOW_HEADING"] = "지금 검사",
    ["HELP_SCANNOW_1"] =
    "즉시 검사 순회를 실행합니다. 게임이 조회를 허용하는 플레이어만 검사할 수 있으므로, 검사되는 수는 주변에 있는 사람, 그룹원, 이름표로 보이는 범위에 따라 달라집니다.",

    ["MINIMAP_HINT"] = "TacoTip Extras",
    ["MINIMAP_HINT_LEFT"] = "좌클릭: 순위표",
    ["MINIMAP_HINT_DRAG"] = "끌어서 이동",
    ["BLANK_DESC"] = "끌기",
    ["BLANK"] = "없음",

    ["LB_TITLE"] = "TacoTip GearScore 순위표",
    ["LB_REALM"] = "영역 전체",
    ["LB_SEARCH"] = "검색:",
    ["LB_YOU"] = "나",
    ["LB_LOADING"] = "순위표를 불러오는 중...",
    ["LB_EMPTY"] = "아직 기록이 없습니다. 플레이하는 동안 점수가 동기화됩니다.",
    ["LB_EMPTY_FILTERS"] = "현재 필터와 일치하는 플레이어가 없습니다.",
    ["LB_NOT_ESTABLISHED"] = "아직 순위 없음",
    ["LB_ONLY_YOU"] = "지금은 이 영역에 내 캐릭터만 기록되어 있습니다.",
    ["LB_FILTER_ALL"] = "전체",
    ["LB_MY_RANK"] = "\226\152\148 내 순위",
    ["LB_TOP"] = "\226\152\160 1위",
    ["LB_SCAN"] = "지금 검사",
    ["LB_SCAN_BUSY"] = "검사 중...",
    ["LB_SCAN_IDLE"] = "대기 중",

    ["LB_COL_RANK"] = "순위",
    ["LB_COL_GS"] = "GEARSCORE",
    ["LB_COL_ILVL"] = "iLVL",
    ["LB_COL_PLAYER"] = "플레이어",
    ["LB_COL_LASTSEEN"] = "최근 접속",

    ["LB_TIP_UNKNOWN"] = "알 수 없음",
    ["LB_TIP_UNKNOWNSPEC"] = "알 수 없는 전문화",
    ["LB_TIP_GS"] = "GearScore: %d",
    ["LB_TIP_ILVL"] = "평균 아이템 레벨: %.1f",
    ["LB_TIP_RANK"] = "GearScore 순위: #%d",
    ["LB_TIP_CLASSRANK"] = "직업 내 순위: #%d",
    ["LB_TIP_LASTSEEN"] = "최근 확인: %s",

    ["SORT_GS_DESC"] = "GEARSCORE",
    ["SORT_ILVL_DESC"] = "아이템 레벨",
    ["SORT_SEEN_DESC"] = "최근 확인",


    ["TIME_JUST_NOW"] = "방금",
    ["TIME_MIN_AGO"] = "%d분 전",
    ["TIME_HOUR_AGO"] = "%d시간 전",
    ["TIME_DAY_AGO"] = "%d일 전",

    ["GEAR_TITLE"] = "%s의 장비",
    ["GEAR_NOT_SCANNED"] = "이 플레이어는 아직 검사되지 않아 장비 정보가 없습니다.",
    ["GEAR_NO_ITEMS"] = "기록된 장비가 없습니다.",
    ["GEAR_CLOSE"] = "닫기",

    ["SCAN_PROGRESS"] = "%d / %d",

    ["CLASS_DEATHKNIGHT"] = "죽음의 기사",
    ["CLASS_DEMONHUNTER"] = "악마 사냥꾼",
    ["CLASS_DRUID"] = "드루이드",
    ["CLASS_HUNTER"] = "사냥꾼",
    ["CLASS_MAGE"] = "마법사",
    ["CLASS_MONK"] = "수도승",
    ["CLASS_PALADIN"] = "성기사",
    ["CLASS_PRIEST"] = "사제",
    ["CLASS_ROGUE"] = "도적",
    ["CLASS_SHAMAN"] = "주술사",
    ["CLASS_WARLOCK"] = "악마술사",
    ["CLASS_WARRIOR"] = "전사",
    ["CLASS_UNKNOWN"] = "알 수 없음",
}

_G.TACOEXTRAS_LOCALES = _G.TACOEXTRAS_LOCALES or {}
_G.TACOEXTRAS_LOCALES["koKR"] = L

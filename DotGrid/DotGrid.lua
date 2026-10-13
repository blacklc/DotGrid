-- ============================================================================
--  DotGrid —— 近战范围内「带我的 debuff 的怪」进度条 / 格子
--  目标接口版本 120100（正式服 12.1）；文档与许可见 README。
--
--  不可破坏的约束（改代码前请先读 README「工作原理」与「技术说明」）：
--   1) 不读取光环数据，也不监听 UNIT_AURA —— 判定完全交给客户端的 AuraContainer；
--      「这只怪有没有我的 debuff」插件永远不知道答案，只看到自己的红段出现 / 消失。
--   2) 只做两件事：给每只符合条件的怪画自己的矩形；把那只怪的 AuraContainer 锚到
--      同一个屏幕位置。颜色 / 尺寸在 initializeFrame 里一次性定死。
--   3) 只用文档核实过的原语（见 README）；可能受限的调用必须 pcall + 预判，
--      失败时退回更保守的判据，绝不放宽范围。
--   4) 容器绝不锚到别人的 Frame 上，也不被别人引用；位置算好后直接锚 UIParent。
--   5) 没设置要监控的法术时整体待机：不采集、不运算、不显示。
-- ============================================================================
local ADDON, NS = ...
local P = "|cff33ff99[DotGrid]|r "

-- 文案本地化：键 = 下面这份中文原文。Locales/<客户端语言>.lua 里有对应表就覆盖，
-- 没有就原样显示（所以只加文件、不动代码也能加一种语言）。
local L = (NS and NS.L) or setmetatable({}, { __index = function(_, k) return k end })
if NS then NS.L = L end

local fmt = string.format
local floor = math.floor

-- ==== 可调常量（要改就改这里）==============================================
local DEFAULT_SPELL_IDS = {}            -- 出厂不预置法术：没设置要监控的 debuff 时插件待机
local MAX_SPELLS        = 4             -- 最多监控多少个法术（4 个 ⇒ 每个方块最多切 4 条横带，仍有 5px 高）
local MAX_CELLS         = 40            -- 扫描 nameplate1..40
local REFRESH_INTERVAL  = 0.10          -- 秒；0.1 = 10 次/秒
local DEFAULT_CELL_W    = 18
local DEFAULT_CELL_H    = 18
local DEFAULT_GAP       = 4
local DEFAULT_PER_ROW   = 5
local DEFAULT_TIER      = 2             -- CheckInteractDistance 档位：2≈8码, 3≈7码, 0=不判距
local AURA_SLOT_KEY     = "dotgrid_watched"
local AURA_TEMPLATE     = "DotGridAuraButtonTemplate"
local CFG_VER           = 12               -- +1 表示L["老存档要跟着改一次默认值"]
local DEFAULT_MODE      = "bar"           -- "bar" = 进度条（默认）| "grid" = 格子
local DEFAULT_SPELL_MODE = "all"          -- 多 debuff 语义："all" = 全部具备才整格变红（分格显示）
                                          --                "any" = 任一个命中就变红（旧行为）
local DEFAULT_BAR_H     = 20              -- 进度条高
local DEFAULT_BAR_GAP   = 1               -- 段间距
local DEFAULT_BAR_SEGW  = 21              -- 紧凑模式：每只怪占一段的宽度（总长 = 怪数 × (此值+缝) - 缝）
local DEFAULT_BAR_MIN   = 2               -- 少于这么多只怪就不显示整条（默认 2：1 只怪没有L["比例"]可看）
local BAR_MAX_W         = 900             -- 紧凑模式总宽上限：怪太多就自动压细段宽来适配
local BAR_MIN_SEGW      = 4               -- 段宽下限（再多的怪也照画，不丢怪）
local MAX_SEG           = 60              -- 段/刻度线的预建上限（位次超过它才另说）
local MIN_GRAB_W        = 140             -- 解锁拖动时，可抓框的最小宽（条被隐藏时也抓得到）
local MIN_GRAB_H        = 26              -- 解锁拖动时，可抓框的最小高
local FILL_TEXTURE      = "Interface\\Buttons\\WHITE8X8"   -- 纯色档：进度条/格子的纯白块
-- 外观档（/dg style）：全部引用游戏自带贴图，不新增任何文件
--   solid     纯色块：不用任何贴图，全部自绘
--   panel     经典面板风：提示框那套面板（边 + 暗底）+ 游戏自带条纹理填充
--   nameplate 原生名字板风：名字板金边面板 + 名字板血条纹理填充
local PANEL_BG          = "Interface\\Tooltips\\UI-Tooltip-Background" -- 面板底（暗色，可平铺）
local PANEL_EDGE        = "Interface\\Tooltips\\UI-Tooltip-Border"     -- 提示框边（经典 edgeFile）
-- 说明：Interface\Tooltips\Nameplate-Border 名字叫"名字板边"，但它的素材是**一整条画好的
-- 名字板框**（一条细描边 + 一个粗金块，两种样式并排放在 256×32 里），不是九宫格边料。
-- 拿它当 edgeFile / 框料用，客户端会把它切成一条条碎片（表现为一排小框）。
-- 所以名字板档的框改用提示框那套边料 + 金色染色，块面换名字板血条纹理 —— 视觉上就是名字板味。
local FILL_NATIVE       = "Interface\\TargetingFrame\\UI-StatusBar"    -- 条纹理（白→灰渐变）
local FILL_NAMEPLATE    = "Interface\\TargetingFrame\\NameplateFill"   -- 名字板血条纹理
local STYLE_SOLID       = "solid"
local STYLE_PANEL       = "panel"
local STYLE_NAMEPLATE   = "nameplate"
local STYLE_SPEC = {
    [STYLE_PANEL]     = { fill = FILL_NATIVE,    bg = PANEL_BG, edge = PANEL_EDGE,
                          tint = { 0, 0, 0, 0.62 }, border = { 1, 1, 1, 0.70 } },
    [STYLE_NAMEPLATE] = { fill = FILL_NAMEPLATE, bg = PANEL_BG, edge = PANEL_EDGE,
                          tint = { 0, 0, 0, 0.55 }, border = { 1, 0.83, 0.36, 0.90 } },   -- 金边
}
local PANEL_PAD         = 6      -- 带框的外观档：框贴着内容外扩这么多像素

-- ==== 默认配置 =============================================================
local DEFAULTS = {
    enabled       = true,
    spells        = DEFAULT_SPELL_IDS,
    spellMode     = DEFAULT_SPELL_MODE, -- 多 debuff："all" 全部具备才变红（分格）/ "any" 任一个就变红
    tier          = DEFAULT_TIER,
    maxYards      = 11,       -- 精确距离上限（码）：用 UnitDistanceSquared；副本内自动退回档位
    engaged       = "combat", -- "all" 不筛 | "combat" 已进入战斗（默认）| "threat" 跟我有仇恨
    combatOnly    = true,     -- 整块只在玩家战斗中显示（/dg combat）
    debug         = false,
    locked        = true,
    cellW         = DEFAULT_CELL_W,
    cellH         = DEFAULT_CELL_H,
    gap           = DEFAULT_GAP,
    perRow        = DEFAULT_PER_ROW,
    -- 进度条模式
    mode          = DEFAULT_MODE,
    style         = STYLE_SOLID,     -- 外观：solid = 纯色块 / panel = 经典面板风（游戏自带贴图）
    barSegW       = DEFAULT_BAR_SEGW, -- 每段宽（/dg bar segw）；总长 = 怪数 × (段宽+缝) - 缝
    barMin        = DEFAULT_BAR_MIN,  -- 少于这么多只怪就不显示整条（/dg bar min）
    barH          = DEFAULT_BAR_H,
    barGap        = DEFAULT_BAR_GAP,
    barTicks      = true,     -- 段之间的 1px 深色刻度线（方便读L["几段亮着"]）
    x             = nil,      -- 显示区左上角在 UIParent 里的坐标（拖动保存）
    y             = nil,
    hitR = 0.92, hitG = 0.08, hitB = 0.08, hitA = 1,          -- 命中（红）
    mobR = 1.00, mobG = 1.00, mobB = 1.00, mobA = 1.00,        -- 有怪但没我的 DoT：纯白不透明（打底要显眼）
    emptyR = 1.00, emptyG = 1.00, emptyB = 1.00, emptyA = 0.18, -- 底槽/空槽位（白 18%：量程，必须比L["有怪"]暗）
    missR = 1.00, missG = 1.00, missB = 1.00, missA = 1.00,    -- 格子模式：有怪、没有我的 DoT（纯白）
}

-- ==== 状态 =================================================================
-- ==== 配置档（多角色）====================================================
-- 存档是账号级的：DotGridDB.profiles[档名] = 整套设置的快照，
-- DotGridDB.charProfile["服务器-角色"] = 这个角色用哪一档。
-- DB 是「当前档 ∪ 出厂默认」的合并视图：读档优先，写一律进当前档。
local DB                       -- 合并视图：当前档 ∪ 出厂默认（写都写进当前档）
local Base                     -- = DotGridDB（账号级：出厂默认 + profiles + charProfile）
local Prof, ProfName, CharKeyOf -- 本角色当前档（表）/ 档名 / 本角色的键
local PROFILE_DEFAULT = "默认"
local PROFILE_MAX_UI  = 12      -- 界面档列表最多列几个（列不下的用 /dg profile list 看）

-- 职业 → 默认监控法术（C：首次在某角色上加载时，若这个职业在表里就自动填）。
-- 内置的职业默认 DoT 表已移除：本插件不替用户预设任何法术。
local CharNameCache            -- 角色名（原样），给L["新角色建自己的档"]当档名
local function MakeCharKey()
    local name, realm
    if UnitFullName then
        local ok, a, b = pcall(UnitFullName, "player")
        if ok then name, realm = a, b end
    end
    if type(name) ~= "string" or name == "" then
        if UnitName then
            local ok, n = pcall(UnitName, "player")
            if ok and type(n) == "string" then name = n end
        end
    end
    if type(realm) ~= "string" or realm == "" then
        if GetRealmName then
            local ok, r = pcall(GetRealmName)
            if ok and type(r) == "string" then realm = r end
        end
    end
    if type(name) ~= "string" or name == "" then return nil end
    CharNameCache = name
    return string.lower((realm or "") .. "-" .. name)
end

local LegacyAdopted = false      -- 升级时老配置刚被搬进「默认」档 ⇒ 当前角色认领它
                                 -- （必须写在 WireDB 之前：Lua 局部变量只对声明之后的代码可见）
local function WireDB()
    Base = DotGridDB
    if type(Base.profiles) ~= "table" then Base.profiles = {} end
    if type(Base.charProfile) ~= "table" then Base.charProfile = {} end
    CharKeyOf = MakeCharKey()
    -- 没有指定过配置档的角色，第一次加载会得到一份以自己名字命名的空档：
    -- 不继承「默认」档，因此也不会继承别人设置的法术；
    -- 在用户设置 debuff 之前，插件什么也不算、什么也不画。
    if CharKeyOf and not Base.charProfile[CharKeyOf] then
        if LegacyAdopted then
            -- 这次升级刚把老配置搬进「默认」档 ⇒ 当前角色认领它（否则那份配置就再也读不到）
            Base.charProfile[CharKeyOf] = PROFILE_DEFAULT
            LegacyAdopted = false
        else
            local pn = (type(CharNameCache) == "string" and CharNameCache ~= "")
                       and CharNameCache or CharKeyOf
            if type(Base.profiles[pn]) ~= "table" then Base.profiles[pn] = {} end
            Base.charProfile[CharKeyOf] = pn
        end
    end
    ProfName = (CharKeyOf and Base.charProfile[CharKeyOf]) or PROFILE_DEFAULT
    if type(ProfName) ~= "string" or ProfName == "" then ProfName = PROFILE_DEFAULT end
    Prof = Base.profiles[ProfName]
    if type(Prof) ~= "table" then
        local wasAssigned = (ProfName ~= PROFILE_DEFAULT)
        if wasAssigned then
            ProfName = PROFILE_DEFAULT            -- 角色指着的档被删了 ⇒ 退回「默认」档
            Prof = Base.profiles[PROFILE_DEFAULT]
        end
        if type(Prof) ~= "table" then
            Prof = {}
            Base.profiles[PROFILE_DEFAULT] = Prof
        end
        if CharKeyOf and wasAssigned then Base.charProfile[CharKeyOf] = ProfName end
    end
    DB = setmetatable({}, {
        __index = function(_, k)
            local v = Prof[k]
            if v ~= nil then return v end
            return Base[k]                        -- 出厂默认（CopyDefaults 铺在 Base 上）
        end,
        __newindex = function(_, k, v) Prof[k] = v end,
    })
end

-- 把"当前生效的设置"整份快照写进 t（新建档 / 保存档都用它）
local function Snapshot(t)
    for k in pairs(t) do t[k] = nil end
    for k, v in pairs(DEFAULTS) do
        local cur = DB[k]
        if type(v) == "table" then
            if type(cur) == "table" then
                local c = {}
                for i = 1, #cur do c[i] = cur[i] end
                t[k] = c
            end
        elseif cur ~= nil then
            t[k] = cur
        end
    end
    t.x, t.y = DB.x, DB.y
    return t
end

-- 切到某个档（同时把这个角色记到它名下）
local function UseProfile(name)
    if type(name) ~= "string" or name == "" then return false end
    local t = Base.profiles[name]
    if type(t) ~= "table" then return false end
    ProfName, Prof = name, t
    if CharKeyOf then Base.charProfile[CharKeyOf] = name end
    return true
end

-- 旧结构的存档（账号单份配置 / 早期的按角色覆盖表）一次性升级成配置档
local function UpgradeToProfiles()
    local raw = DotGridDB
    if type(raw.profiles) == "table" then return false end
    -- 结构性的键留在账号级：档库 / 角色指定 / 版本号 / 设置窗口位置
    local KEEP = { profiles = 1, charProfile = 1, byChar = 1, charSeen = 1,
                   cfgVer = 1, uiX = 1, uiY = 1 }
    local default = {}
    for k, v in pairs(raw) do
        if not KEEP[k] then default[k] = v end
    end
    for k in pairs(default) do raw[k] = nil end
    local by = type(raw.byChar) == "table" and raw.byChar or nil
    raw.profiles, raw.charProfile = {}, {}
    if next(default) ~= nil then
        raw.profiles[PROFILE_DEFAULT] = default
        LegacyAdopted = true          -- 有旧配置 ⇒ 由当前角色接管，否则旧设置会读不到
    end
    if by then
        for ckey, ov in pairs(by) do
            local pname = string.match(ckey, "[^%-]+$") or ckey      -- 取角色名那一段
            local t = {}
            for k, v in pairs(default) do t[k] = v end               -- 从老账号配置起底
            for k, v in pairs(ov) do t[k] = v end                    -- 盖上这个角色的差异
            raw.profiles[pname] = t
            raw.charProfile[ckey] = pname
        end
    end
    raw.byChar, raw.charSeen = nil, nil
    return true
end

-- C：首次在某角色上加载 ⇒ 按职业建一个档（档名 = 职业中文名），里面带上该职业的默认 DoT。
-- 只在这个角色**还没指定过档**时动手；已经指定过（含手动 load）就不碰。
-- 不按职业自动建档：新角色一律从空档开始（见 WireDB）


local anchor
local cells   = {}             -- [i] = 白格 Frame
local records = {}             -- [unit] = { container=..., auraFrame=..., visible=..., sig=... }
local units   = {}             -- 当前计入的 unit 列表
local barSlots   = {}          -- [i] = 进度条第 i 段的贴图
local barTicks   = {}          -- [i] = 段间刻度线
local barTrough                -- 进度条底槽
local barOutline               -- 进度条最外圈 1px 描边
local occupied = {}            -- [slot] = true 表示该槽位有怪（紧凑模式按 rank，固定模式按名字板槽位号）
local overflow = 0             -- 位次超出 MAX_SEG、画不出来的怪数（只在控制台/diag 里说明）
local barN     = 0             -- 紧凑进度条：当前计入的怪数（总长 = f(barN)）
local ranks    = {}            -- [unit] = 紧凑模式下的段号（1..n，按列表次序从左到右）
local builtSegW = nil          -- 建容器时用的段宽：段宽变了必须整批重建（按钮尺寸定死在 initializeFrame）
local builtSpells = nil        -- 建容器时用的法术条数：条数变了 slot 数量就变了，必须整批重建
local RebuildRecords           -- 前置声明：Refresh 路径里要用
local uiPath  = L["未探测"]        -- AuraContainer 用的哪套 API：slot / group
local elapsed, lastSig, dbgCount = 0, nil, 0
local lastLayoutKey = nil
local paintSig     = nil      -- 进度条上色的缓存签名（颜色/占用没变就不重复调 API）
local Refresh                  -- 前置声明：EnsureAnchor 的闭包要用

-- ==== 小工具 ===============================================================
local function dprint(...)
    if not (DB and DB.debug) then return end
    dbgCount = dbgCount + 1
    local t = {}
    for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
    print(P .. "[DBG " .. dbgCount .. "] " .. table.concat(t, " | "))
end

local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

-- 显示区当前有没有内容（没有就把外观框一起收掉）。声明放在最前面：
-- HideAllVisuals() 也要用它，局部变量必须先声明。
local anchorHasContent = false

-- 收掉"我们自己画的"全部贴图（饼图扇区 / 进度条段 / 刻度线 / 底槽）。
-- 切显示模式时必须调，否则上一个模式的贴图会留在屏幕上。
local function HideOurTextures()
    for i = 1, #barSlots do barSlots[i]:Hide() end
    for i = 1, #barTicks do barTicks[i]:Hide() end
    if barTrough then barTrough:Hide() end
    if barOutline then barOutline:Hide() end
    paintSig = nil
end

local function HideAllVisuals()
    lastLayoutKey = nil
    HideOurTextures()
    for i = 1, #cells do cells[i]:Hide() end
    for _, rec in pairs(records) do
        if rec.visible then
            rec.visible = false
            rec.container:SetEnabled(false)
            rec.container:Hide()
        end
    end
    if anchor then
        anchor:SetSize(MIN_GRAB_W, MIN_GRAB_H)
        anchor:Show()
    end
    -- 收工（脱战 / /dg off / 切模式）时，外观框（面板风/名字板风那层框）也必须跟着收掉。
    -- 光收贴图和容器不够：外观框会孤零零留在原地，所以这里同时把外观重套一遍。
    anchorHasContent = false
    ApplyAnchorStyle()
end

-- ==== 监控法术 =============================================================
local function GetSpellList()
    local list, set = {}, {}
    local raw = DB.spells
    if type(raw) ~= "table" then return list, set end
    for i = 1, #raw do
        local id = tonumber(raw[i])
        if id and id > 0 and not set[id] and #list < MAX_SPELLS then
            set[id] = true
            list[#list + 1] = id
        end
    end
    return list, set
end

local function SpellSig()
    local list = GetSpellList()
    return table.concat(list, ",")
end

-- ==== 多 debuff（AND / 分格）================================================
-- 暴雪那边"一个 AuraButton = 一个光环"，过滤器只能表达"哪几个法术算候选"（= 或）。
-- 想让"必须全部具备才红"落地：给每个法术各建一个 slot（每个 slot 只认一个法术），
-- 并把这只怪的格子切成 N 条横带，第 i 条只由第 i 个法术的按钮来涂。
-- => 整格变红 ⟺ 全部命中；部分命中时能一眼看出缺哪一条。（详见 README「多 debuff」一节）
local function SpellMode()
    if DB and DB.spellMode == "any" then return "any" end
    return "all"
end

local function SlotKey(i)
    return AURA_SLOT_KEY .. "_" .. i
end

-- 单个法术一份过滤器：分格（AND）正是靠"一个 slot 只认一个法术"实现的
local function FiltersFor(spellID)
    return { includeSpellIDs = { [spellID] = true }, isFromPlayerOrPlayerPet = true }
end

-- 是否走分格：只有"全中"语义 + 多个法术时才把一个方块切成 N 条横带
local function UseBands(nSlots)
    return SpellMode() == "all" and (nSlots or 1) > 1
end

-- ==== 名字板槽位号（纯计算，不碰 UI）========================================
local function PlateIndex(unit)
    return tonumber(string.match(unit, "(%d+)$")) or 0
end


-- ==== 进度条几何（纯计算，不碰 UI）==========================================
-- 只有一种形态：**总长随怪数变**（几只怪就几段，第 j 段 = 列表里第 j 只）
--   红段 = 暴雪原生 AuraContainer 判定（有我的 DoT）
--   白段 = 有怪、但没我的 DoT
-- 亮起来的长度 = 范围内怪数（分母），其中红的那截 = 带我的 DoT 的比例（分子）
local function BarHeight()
    return math.max(6, math.min(80, floor(DB.barH or DEFAULT_BAR_H)))
end
local function BarGap()
    return math.max(0, math.min(10, floor(DB.barGap or DEFAULT_BAR_GAP)))
end
local function BarCount()                   -- 横条有几段 = 当前怪数（总长随怪数变）
    return math.max(0, barN)
end
local function BarMin()                     -- 少于这么多只就不显示整条（默认 2：1 只怪没有L["比例"]可看）
    return math.max(0, math.min(10, floor(DB.barMin or DEFAULT_BAR_MIN)))
end
local function BarSegW(n)                   -- 每段宽（怪太多时自动压细，绝不丢怪）
    local cnt = math.max(1, n or BarCount())
    local segw = math.max(6, math.min(60, floor(DB.barSegW or DEFAULT_BAR_SEGW)))
    if cnt * segw + (cnt - 1) * BarGap() > BAR_MAX_W then
        segw = floor((BAR_MAX_W - (cnt - 1) * BarGap()) / cnt)
    end
    if segw < BAR_MIN_SEGW then segw = BAR_MIN_SEGW end
    return segw
end
local function BarTotalW(n)                 -- 横条总宽 = 段数 × 段宽 + 缝
    local cnt = math.max(0, n or BarCount())
    if cnt <= 0 then return 0 end
    return cnt * BarSegW(cnt) + (cnt - 1) * BarGap()
end
local function BarSlotX(i, n)               -- 第 i 段左边相对横条左上角的偏移
    return (i - 1) * (BarSegW(n) + BarGap())
end
local function BarSlotSize(n)
    return BarSegW(n), BarHeight()
end

-- 进度条：算出哪些段被占用（顺便统计位次超上限、画不出来的怪）
-- 槽位 = 怪在列表里的次序（1..n；总长 = n × 每段宽，永远连续、没有空段）
local function ComputeOccupied()
    occupied, overflow = {}, 0
    if DB.mode == "grid" then return end
    for j, unit in ipairs(units) do
        local slot = j
        if slot >= 1 and slot <= MAX_SEG then
            occupied[slot] = unit
        else
            overflow = overflow + 1
        end
    end
end

-- 这只怪当前画在第几段（diag / verify 用）
local function SlotOf(unit)
    if DB.mode == "bar" then return ranks[unit] or 0 end
    return PlateIndex(unit)
end

-- ==== 范围判定 =============================================================
-- 精确码数：UnitDistanceSquared(unit) 官方签名返回两个值：distance（平方码）+ checkedDistance（bool）。
-- 参数就是普通 UnitToken（官方文档没有限定"必须是队友"），但副本内该 API 受限
-- （DBM 注释原话：in instances 只给受限值）⇒ 只在"拿到正常数值且 checkedDistance 不为真"时采信，
-- 其余一律返回 nil → 自动退回 CheckInteractDistance 档位（8 码，比 11 码更严，不会放宽）。
local lastDistMode = L["未探测"]      -- "exact" 精确码数 | "tier" 退回档位 | "off" 不判距
local lastDistRaw  = L["还没测"]      -- diag 用：最后一次拿到的原始返回值
local sawExactDist = false         -- 这一帧是否真的量到过精确码数（diag 用）

local function UnitDistanceYards(unit)
    if not UnitDistanceSquared then return nil end
    local ok, v, chk = pcall(UnitDistanceSquared, unit)
    if not ok then lastDistRaw = L["被拒: "] .. tostring(v); return nil end
    lastDistRaw = fmt(L["%s（checked=%s）"], tostring(v), tostring(chk))
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    if type(v) ~= "number" or v <= 0 then return nil end   -- 受限时可能给布尔值
    if chk == true then return nil end                     -- checked 为真 = 受限值，不采信
    return v ^ 0.5
end

-- 这只怪"跟我打起来了吗"
local function EngagedOK(unit)
    if DB.engaged == "all" then return true end
    if DB.engaged == "threat" then
        -- 我是否在它的仇恨列表里（= 它在跟我/我的队伍打）
        if not UnitThreatSituation then return UnitAffectingCombat(unit) == true end
        local ok, v = pcall(UnitThreatSituation, "player", unit)
        if not ok then return false end
        if issecretvalue and issecretvalue(v) then
            return UnitAffectingCombat(unit) == true      -- 受限时退回L["在战斗中"]
        end
        return v ~= nil
    end
    return UnitAffectingCombat(unit) == true              -- "combat"
end

local function InRange(unit)
    local yards = DB.maxYards or 0
    local tier  = DB.tier or 0
    if tier == 0 then                     -- tier 0 = 完全不判距（连精确码数一起关，范围最大）
        lastDistMode = "off"
        return true
    end
    -- 1) 精确码数 /dg yards N（量得到就必须满足：与档位是"取更严"的关系，绝不放宽）
    if yards > 0 then
        local d = UnitDistanceYards(unit)
        if d then
            sawExactDist = true
            if d > yards then return false end
        end
    end
    -- 2) 档位（开着就必须满足；精确码数量不到时它就是唯一判据）
    lastDistMode = sawExactDist and "exact" or "tier"
    local ok, res = pcall(CheckInteractDistance, unit, tier)
    if not ok then
        dprint(L["[C] CheckInteractDistance 被拒"], unit, tostring(res))
        return false
    end
    if issecretvalue and issecretvalue(res) then
        -- 正常情况下不会出现（战斗中返回普通布尔）；保守起见当作在范围内处理。
        dprint(L["[C] 距离值为 secret，按在范围内处理"], unit)
        return true
    end
    return res == true
end

-- ==== 候选怪列表 ===========================================================
local function GetUnits()
    local out = {}
    sawExactDist = false                  -- 每帧重置；/dg diag 只看最近一帧的结果
    for i = 1, MAX_CELLS do
        local unit = "nameplate" .. i
        if UnitExists(unit)
            and UnitCanAttack("player", unit)
            and not UnitIsDead(unit)
            and EngagedOK(unit)
            and InRange(unit) then
            out[#out + 1] = unit
        end
    end
    return out
end

-- ==== 外观（/dg style）====================================================

local function StyleKey()
    local s = DB and DB.style or STYLE_SOLID
    if s ~= STYLE_PANEL and s ~= STYLE_NAMEPLATE then return STYLE_SOLID end
    return s
end

local function StyleSpec() return STYLE_SPEC[StyleKey()] end

-- 当前外观用的块面填充贴图（solid 档 = 纯白块）
local function FillFile()
    local sp = StyleSpec()
    return (sp and sp.fill) or FILL_TEXTURE
end

-- 给一块贴图换基底。返回 true = 已经用上本档的贴图（颜色/透明度靠顶点色）；
-- false = 贴图设置失败，调用方应退回 SetColorTexture。换纹理失败绝不留空贴图。
local function SetFill(t)
    if not t then return false end
    local file = FillFile()
    if t.fillFile == file then return file ~= nil end
    if pcall(t.SetTexture, t, file) then t.fillFile = file return true end
    if file ~= FILL_TEXTURE and pcall(t.SetTexture, t, FILL_TEXTURE) then
        t.fillFile = FILL_TEXTURE
        return false
    end
    return false
end

-- ==== 白格 / 锚点 ==========================================================
local function EnsureCell(i)
    local c = cells[i]
    if c then return c end
    c = CreateFrame("Frame", nil, UIParent)
    c:SetFrameStrata("BACKGROUND")
    c.fill = c:CreateTexture(nil, "BACKGROUND")
    c.fill:SetAllPoints(c)
    c:Hide()
    cells[i] = c
    return c
end

local function EnsureAnchor()
    if anchor then return anchor end

    anchor = CreateFrame("Frame", "DotGridAnchor", UIParent)
    anchor:SetFrameStrata("BACKGROUND")
    anchor:SetSize(MIN_GRAB_W, MIN_GRAB_H)
    anchor:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", DB.x or 0, DB.y or 0)
    anchor:SetMovable(true)
    anchor:EnableMouse(false)
    anchor:RegisterForDrag("LeftButton")
    anchor:SetScript("OnDragStart", function(self)
        if not DB.locked then self:StartMoving() end
    end)
    anchor:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local l, t = self:GetLeft(), self:GetTop()
        if l and t then
            DB.x, DB.y = floor(l), floor(t)
        end
        lastSig = nil
        lastLayoutKey = nil            -- 位置进了布局 key：按新位置重排一次
        dprint(L["[3] 位置已保存"], DB.x, DB.y)
        Refresh(true)
    end)

    -- 解锁时的"可拖动框"（WA 那种：整个显示区就是把手）
    anchor.bg = anchor:CreateTexture(nil, "BACKGROUND")
    anchor.bg:SetAllPoints(anchor)
    anchor.moveBorder = {}
    for i = 1, 4 do
        local b = anchor:CreateTexture(nil, "OVERLAY")
        b:SetColorTexture(1, 0.82, 0.10, 0.90)
        anchor.moveBorder[i] = b
    end
    anchor.originMark = anchor:CreateTexture(nil, "OVERLAY")
    anchor.originMark:SetColorTexture(1, 0.82, 0.10, 1)
    anchor.originMark:SetPoint("TOPLEFT", anchor, "TOPLEFT", -1, 1)
    anchor.originMark:SetSize(7, 1)
    anchor.moveText = anchor:CreateFontString("DotGridMoveText", "OVERLAY", "GameFontNormalSmall")
    anchor.moveText:SetPoint("TOP", anchor, "BOTTOM", 0, -3)
    anchor.moveText:SetText("")

    -- 外观（panel / nameplate）：整块显示区套一层游戏自带的面板。
    -- 用 BackdropTemplate 的 SetBackdrop —— 这正是 Interface\Tooltips\UI-Tooltip-Border 的经典用法
    -- （edgeFile + edgeSize = 16，Backdrop 内部按九宫格切）。
    -- 不要手搓拉伸素材：客户端会按九宫格切开，显示成一排重复的圆角框。
    anchor.panelFrame = CreateFrame("Frame", "DotGridPanel", UIParent, "BackdropTemplate")
    anchor.panelFrame:SetFrameStrata("BACKGROUND")
    anchor.panelFrame:Hide()

    return anchor
end

-- 面板/名字板风的框：贴着显示区外扩 PANEL_PAD。单独一个背板帧、永远画在内容下层。
-- anchorHasContent：空的时候（范围内没怪）整框一起收掉，不在地上留个孤零零的框。
function ApplyAnchorStyle()
    local pf = anchor and anchor.panelFrame
    if not pf then return end
    local key = StyleKey()
    local sp = STYLE_SPEC[key]
    if not sp or not anchorHasContent or not pf.SetBackdrop then
        pf:Hide()
        return
    end
    if pf.backdropStyle ~= key then
        -- insets 必须留出来：底图铺满整个矩形是**直角**，而边框素材的圆角在里侧 ——
        -- insets 太小（含 0）时，底图的直角会露在圆角边料外面。
        -- 面板本来就比显示区外扩 PANEL_PAD，正好当 insets。
        if not pcall(pf.SetBackdrop, pf, {
            bgFile = sp.bg, edgeFile = sp.edge,
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = PANEL_PAD, right = PANEL_PAD, top = PANEL_PAD, bottom = PANEL_PAD },
        }) then
            pf:Hide()
            return
        end
        pf.backdropStyle = key
    end
    if pf.SetBackdropColor then
        pcall(pf.SetBackdropColor, pf, sp.tint[1], sp.tint[2], sp.tint[3], sp.tint[4])
    end
    if pf.SetBackdropBorderColor then
        pcall(pf.SetBackdropBorderColor, pf, sp.border[1], sp.border[2], sp.border[3], sp.border[4])
    end
    local pad = PANEL_PAD
    local w = floor(anchor:GetWidth() or 0)
    local h = floor(anchor:GetHeight() or 0)
    pf:ClearAllPoints()
    pf:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", floor(DB.x or 0) - pad, floor(DB.y or 0) + pad)
    pf:SetSize(w + pad * 2, h + pad * 2)
    pf:Show()
end

-- 解锁时把可抓框撑到最小可抓尺寸（贴图/红块都用显式坐标，撑大锚点不会拉变形），
-- 并刷新黄框与坐标提示；锁定状态下把黄框全收掉。
function UpdateMoveBox()
    if not anchor then return end
    local bw = anchor.moveBorder
    if DB.locked then
        for i = 1, 4 do if bw and bw[i] then bw[i]:Hide() end end
        if anchor.originMark then anchor.originMark:Hide() end
        if anchor.moveText then anchor.moveText:Hide() end
        return
    end
    local w = math.max(MIN_GRAB_W, floor(anchor:GetWidth() or 0))
    local h = math.max(MIN_GRAB_H, floor(anchor:GetHeight() or 0))
    if (anchor:GetWidth() or 0) < w or (anchor:GetHeight() or 0) < h then
        anchor:SetSize(w, h)
    end
    ApplyAnchorStyle()
    if bw then
        bw[1]:ClearAllPoints(); bw[1]:SetPoint("TOPLEFT", anchor, "TOPLEFT", -1, 1); bw[1]:SetSize(w + 2, 1)
        bw[2]:ClearAllPoints(); bw[2]:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", -1, -1); bw[2]:SetSize(w + 2, 1)
        bw[3]:ClearAllPoints(); bw[3]:SetPoint("TOPLEFT", anchor, "TOPLEFT", -1, 1); bw[3]:SetSize(1, h + 2)
        bw[4]:ClearAllPoints(); bw[4]:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 1, 1); bw[4]:SetSize(1, h + 2)
        for i = 1, 4 do bw[i]:Show() end
    end
    if anchor.originMark then anchor.originMark:Show() end
    if anchor.moveText then
        anchor.moveText:Show()
        anchor.moveText:SetText(fmt(L["拖动我调整位置　x=%d y=%d　（/dg lock 锁定）"],
            floor(DB.x or 0), floor(DB.y or 0)))
    end
end

local function ApplyLock()
    if not anchor then return end
    anchor:EnableMouse(not DB.locked)
    if DB.locked then
        anchor.bg:SetColorTexture(0, 0, 0, 0)
    else
        anchor.bg:SetColorTexture(1, 0.82, 0, 0.14)
    end
    UpdateMoveBox()
end

-- ==== 红格（暴雪原生 AuraContainer）========================================
local function InitAuraFrame(rec, auraFrame, idx)
    -- 只在这里做视觉！initializeFrame 之后按钮成员受限，不能再改尺寸/颜色/扇区角度。
    idx = idx or 1
    rec.auraFrame = auraFrame
    if rec.auraFrames then rec.auraFrames[idx] = auraFrame end
    local n = rec.slots or 1
    local fill = auraFrame and auraFrame.DotGridFill
    if fill then
        -- RGB 定在这里（改 RGB 仍需重建）；**透明度不走顶点色**，走 container:SetAlpha
        -- （见 ActivateRecord / RepositionRecords）⇒ /dg alpha hit N 即时生效、不重建容器
        fill:SetVertexColor(DB.hitR, DB.hitG, DB.hitB, 1)
        -- 整块纯白，全靠染色 —— 不依赖任何自制贴图
        local ffile = FillFile()
        if not pcall(fill.SetTexture, fill, ffile) then
            dprint(L["[A] 填充贴图设置失败"])
            fill.fillFile = nil
        else
            fill.fillFile = ffile
        end
    end

    -- 几何：进度条/格子各自的"整格"尺寸，然后按分格把高度切成 n 条横带
    local w, h
    if DB.mode == "bar" then
        w, h = BarSlotSize(barN)          -- 按钮尺寸定死在 initializeFrame ⇒ 段宽变了要重建
    else
        w, h = DB.cellW, DB.cellH
    end
    local bandH = 0
    if UseBands(n) then
        bandH = h / n
        h = bandH
    end
    auraFrame:SetSize(w, h)
    auraFrame:ClearAllPoints()
    auraFrame:SetPoint("TOPLEFT", rec.container, "TOPLEFT", 0, bandH > 0 and -(idx - 1) * bandH or 0)
    -- 只借它的"判定"，不留它的"画"：暴雪光环按钮自带一圈边框/发光贴图，只收 Icon 不够 ——
    -- 那些贴图会盖在我们的红/白填充上（每个命中格一个金色弧形小框），必须全部收起。
    -- 这里把按钮**自己的**贴图全部收掉（GetRegions 只返回它自己的区域，子帧不受影响），
    -- 只保留我们自己那块 DotGridFill。
    if auraFrame.GetRegions then
        local keep, hidden = auraFrame.DotGridFill, 0
        for _, r in ipairs(auraFrame:GetRegions()) do
            local mine = (r == keep)
            if not mine and r and r.GetName then
                local nm = r:GetName()
                if nm and string.find(tostring(nm), "DotGridFill", 1, true) then mine = true end
            end
            if not mine and r and r.GetObjectType and r:GetObjectType() == "Texture" and r.Hide then
                if pcall(r.Hide, r) then hidden = hidden + 1 end
            end
        end
        dprint(L["[A] 光环按钮自带贴图收起"], hidden, L["块（保留我们自己的填充）"])
    elseif auraFrame.Icon then
        pcall(auraFrame.Icon.Hide, auraFrame.Icon)
    end
    if auraFrame.SetMouseMotionEnabled then auraFrame:SetMouseMotionEnabled(false) end
    dprint("[A] initializeFrame", rec.unit, "slot=" .. idx .. "/" .. n, fill and "fill=ok" or "fill=nil",
        bandH > 0 and (L["横带 h="] .. fmt("%.1f", bandH)) or L["整格"])
end

local function EnsureRecord(unit)
    local rec = records[unit]
    if rec then return rec end

    local container = CreateFrame("AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
    if not container then
        dprint(L["[A] AuraContainer 创建失败"], unit)
        return nil
    end
    container:SetFrameStrata("LOW")     -- 高于我们自己画的底槽/白格(BACKGROUND)，红格才能盖住
    if DB.mode == "bar" then
        local sw, sh = BarSlotSize(barN)      -- 按钮尺寸定死在 initializeFrame：段宽变了要重建
        container:SetSize(sw, sh)
        builtSegW = sw
    else
        container:SetSize(DB.cellW, DB.cellH)
    end
    container:SetUnit(unit)

    rec = { unit = unit, container = container, visible = false, sig = nil, auraFrames = {} }
    records[unit] = rec

    -- 每个监控法术一个 slot：这样"必须全部具备才红"才能靠分格落地
    local spells = GetSpellList()
    local M = math.max(1, #spells)
    rec.slots, rec.spellList = M, spells

    local ok, err, slotOK = nil, nil, true
    for idx = 1, M do
        local slotOpts = {
            templateNames    = { AURA_TEMPLATE },
            candidateFilters = FiltersFor(spells[idx]),
            initializeFrame  = function(auraFrame) InitAuraFrame(rec, auraFrame, idx) end,
        }
        if uiPath ~= "group" and container.AddAuraSlot then
            ok, err = pcall(container.AddAuraSlot, container, SlotKey(idx), "HARMFUL", slotOpts)
            if ok then
                uiPath = "slot"
            else
                dprint(L["[A] AddAuraSlot 失败，改试 AddAuraGroup:"], tostring(err))
                uiPath = "group"
                slotOK = false
            end
        end
        if uiPath == "group" then
            if container.AddAuraGroup then
                local groupOpts = {
                    templateNames    = { AURA_TEMPLATE },
                    maxFrameCount    = 1,
                    candidateFilters = FiltersFor(spells[idx]),
                    initializeFrame  = function(auraFrame) InitAuraFrame(rec, auraFrame, idx) end,
                }
                ok, err = pcall(container.AddAuraGroup, container, SlotKey(idx), "HARMFUL", groupOpts)
                if ok then slotOK = true else
                    slotOK = false
                    dprint(L["[A] AddAuraGroup 也失败:"], tostring(err))
                end
            else
                slotOK = false
                dprint(L["[A] 容器既没有 AddAuraSlot 也没有 AddAuraGroup"])
            end
        end
    end
    if slotOK then builtSpells = M end    -- 只在建失败时才不记（避免战斗中建不出来时每帧重建）

    container:SetEnabled(false)
    container:Hide()
    return rec
end

local function SetSlotFilters(rec, idx, filters)
    local c = rec.container
    local key = SlotKey(idx)
    local ok, err
    if uiPath == "slot" and c.SetAuraSlotCandidateFilters then
        ok, err = pcall(c.SetAuraSlotCandidateFilters, c, key, filters)
    elseif c.SetAuraGroupCandidateFilters then
        ok, err = pcall(c.SetAuraGroupCandidateFilters, c, key, filters)
    else
        ok, err = false, L["没有候选过滤器 API"]
    end
    if not ok then dprint(L["[A] 过滤器设置失败:"], key, tostring(err)) end
end

-- 每个 slot 一份"只认一个法术"的过滤器（分格 AND 的基础）
local function SetRecordFilters(rec)
    local spells = rec.spellList or GetSpellList()
    for idx = 1, (rec.slots or 1) do
        local sid = spells[idx] or spells[1]
        if sid then SetSlotFilters(rec, idx, FiltersFor(sid)) end
    end
end

local function ActivateRecord(unit, x, y)
    local rec = EnsureRecord(unit)
    if not rec then return end

    local sig = SpellSig()
    if rec.sig ~= sig then
        rec.sig = sig
        rec.spellList = GetSpellList()
        SetRecordFilters(rec)
    end

    rec.container:ClearAllPoints()
    rec.container:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    if rec.container.SetAlpha then rec.container:SetAlpha(DB.hitA) end   -- 红标记的透明度（顶点色恒为 1）
    if not rec.visible then
        rec.visible = true
        rec.container:SetEnabled(true)
        rec.container:Show()
    end
end

RebuildRecords = function()
    if #GetSpellList() == 0 then return end   -- 待机：没有监控法术就不建容器
    -- 尺寸/颜色只能在 initializeFrame 里定一次；改了就整批退役、按需重建（立即生效，不用 /reload）
    for unit, rec in pairs(records) do
        if rec.visible then
            pcall(rec.container.SetEnabled, rec.container, false)
        end
        rec.visible = false
        pcall(rec.container.Hide, rec.container)
        pcall(rec.container.ClearAllPoints, rec.container)
        records[unit] = nil
    end
    records = {}
    lastSig = nil
    uiPath = L["未探测"]
    builtSegW = nil                -- 重建后段宽需要重新记
    builtSpells = nil              -- 重建后法术条数也需要重新记
end

-- ==== 布局 =================================================================
-- 格子模式：白格 = 范围内有这只怪，红格盖在上面 = 我的 DoT 在
local function LayoutGrid(n)
    local a = EnsureAnchor()

    -- 布局缓存：内容/参数没变就直接返回，避免 10 次/秒的无谓 SetPoint / SetText
    local key = table.concat({ "grid", tostring(DB.locked), n, DB.cellW, DB.cellH, DB.gap, DB.perRow, DB.x, DB.y,
        DB.missR, DB.missG, DB.missB, DB.missA }, ":")
    if key == lastLayoutKey then return end
    lastLayoutKey = key

    -- 从其它模式切过来时，把我们的扇区/进度条贴图收掉（红标记是按钮，容器停用后自动不显示）
    HideOurTextures()

    if n <= 0 then
        a:SetSize(MIN_GRAB_W, MIN_GRAB_H)
        a:ClearAllPoints()
        a:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", DB.x, DB.y)
        a:Show()
        anchorHasContent = false
        ApplyAnchorStyle()
        for i = 1, #cells do cells[i]:Hide() end
        return
    end

    local perRow = math.max(1, math.min(20, floor(DB.perRow)))
    local cols = math.min(perRow, n)
    local rows = math.ceil(n / perRow)
    local w = cols * DB.cellW + (cols - 1) * DB.gap
    local h = rows * DB.cellH + (rows - 1) * DB.gap

    a:ClearAllPoints()
    a:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", DB.x, DB.y)
    a:SetSize(w, h)
    a:Show()
    anchorHasContent = true
    ApplyAnchorStyle()

    for i = 1, n do
        local c = EnsureCell(i)
        local col = (i - 1) % perRow
        local row = floor((i - 1) / perRow)
        local x = DB.x + col * (DB.cellW + DB.gap)
        local y = DB.y - row * (DB.cellH + DB.gap)
        c:SetSize(DB.cellW, DB.cellH)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
        if SetFill(c.fill) and StyleKey() ~= STYLE_SOLID then
            -- 带框档：游戏自带纹理当基底，颜色与透明度照旧靠顶点色（改色/改透明度仍即时）
            c.fill:SetVertexColor(DB.missR, DB.missG, DB.missB, DB.missA)
        else
            c.fill:SetColorTexture(DB.missR, DB.missG, DB.missB, DB.missA)
        end
        c:Show()
        c.cellX, c.cellY = x, y
    end
    for i = n + 1, #cells do cells[i]:Hide() end

end

-- ==== 进度条绘制 ============================================================
local function EnsureBarSlot(i)
    local t = barSlots[i]
    if not t then
        t = anchor:CreateTexture("DotGridBarSlot" .. i, "ARTWORK")
        t:SetTexture(FILL_TEXTURE)          -- 先给基底（白块），颜色靠 SetVertexColor
        barSlots[i] = t
    end
    return t
end

local function EnsureBarTick(i)
    local t = barTicks[i]
    if not t then
        t = anchor:CreateTexture("DotGridBarTick" .. i, "OVERLAY")
        t:SetColorTexture(0, 0, 0, 0.6)     -- SetColorTexture 同时给了基底色和颜色（只 SetVertexColor 会画不出来）
        barTicks[i] = t
    end
    return t
end

local function EnsureTrough()
    if not barTrough then
        -- 最外面一圈 1px 深色描边：无论背景是亮是暗，条的边界都看得见
        barOutline = anchor:CreateTexture("DotGridBarOutline", "BACKGROUND")
        barOutline:SetPoint("TOPLEFT", anchor, "TOPLEFT", -1, 1)
        barOutline:SetColorTexture(0, 0, 0, 0.55)

        barTrough = anchor:CreateTexture("DotGridBarTrough", "BACKGROUND")
        barTrough:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
    end
    return barTrough
end

local function PaintBar()
    local cnt = math.max(0, barN)
    local parts = { "bar", DB.mobR, DB.mobA, DB.emptyR, DB.emptyA, tostring(cnt) }
    for i = 1, cnt do parts[#parts + 1] = occupied[i] and "1" or "0" end
    local sig = table.concat(parts, ":")
    if sig == paintSig then return end
    paintSig = sig

    for i = 1, cnt do
        local t = barSlots[i]
        if t then
            if occupied[i] then
                t:SetVertexColor(DB.mobR, DB.mobG, DB.mobB, DB.mobA)   -- 有怪、没我的 DoT（纯白）
                t:Show()
            else
                t:Hide()
            end
        end
    end
end

local function LayoutBar(n)
    local a      = EnsureAnchor()
    local cnt    = math.max(0, n)          -- 几只怪就几段
    local gap    = BarGap()
    local segW   = BarSegW(cnt)
    local totalW = BarTotalW(cnt)          -- 总长 = 怪数 × (段宽+缝) - 缝
    local h      = BarHeight()

    local key = table.concat({ "bar", totalW, h, gap, DB.x, DB.y, tostring(DB.locked),
        tostring(DB.barTicks), n, overflow,
        DB.emptyR, DB.emptyG, DB.emptyB, DB.emptyA }, ":")
    if key ~= lastLayoutKey then
        lastLayoutKey = key
        HideOurTextures()
        for i = 1, #cells do cells[i]:Hide() end

        a:ClearAllPoints()
        a:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", DB.x, DB.y)
        if cnt <= 0 then                              -- 范围内没有怪：整条收掉（连底槽一起）
            a:SetSize(MIN_GRAB_W, MIN_GRAB_H)
            a:Show()
            anchorHasContent = false
            ApplyAnchorStyle()
        else
            a:SetSize(totalW, h)
            a:Show()
            anchorHasContent = true
            ApplyAnchorStyle()

            tr = EnsureTrough()                 -- 底槽：那条L["总长"]的底
            if StyleKey() ~= STYLE_SOLID and pcall(tr.SetTexture, tr, PANEL_BG) then
                -- 面板风：底槽也用游戏自带面板底（可平铺），颜色/透明度仍按「底槽」设置
                if tr.SetHorizTile then pcall(tr.SetHorizTile, tr, true) end
                if tr.SetVertTile  then pcall(tr.SetVertTile,  tr, true) end
                tr:SetVertexColor(DB.emptyR, DB.emptyG, DB.emptyB, DB.emptyA)
            else
                tr:SetColorTexture(DB.emptyR, DB.emptyG, DB.emptyB, DB.emptyA)
            end
            tr:SetSize(totalW, h)               -- 显式尺寸：解锁时锚点会被撑到最小可抓尺寸
            tr:Show()
            if barOutline then
                barOutline:SetSize(totalW + 2, h + 2)
                -- 面板风：外框由游戏自带面板边框负责，自绘 1px 描边收掉（避免双线）
                if StyleKey() ~= STYLE_SOLID then barOutline:Hide() else barOutline:Show() end
            end

            for i = 1, cnt do                         -- 每只怪一段：1..cnt 全占满，没有空段
                local t = EnsureBarSlot(i)
                SetFill(t)                            -- 外观：solid=纯白块 / 其它档=游戏自带纹理
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", a, "TOPLEFT", BarSlotX(i, cnt), 0)
                t:SetSize(segW, h)
            end
            for i = cnt + 1, #barSlots do barSlots[i]:Hide() end

            for i = 1, math.max(0, cnt - 1) do        -- 段间刻度线：方便L["数几段"]
                local tk = EnsureBarTick(i)
                tk:ClearAllPoints()
                tk:SetPoint("TOPLEFT", a, "TOPLEFT", BarSlotX(i, cnt) + segW, 0)
                tk:SetSize(math.max(1, gap), h)
                if DB.barTicks then tk:Show() else tk:Hide() end
            end
            for i = math.max(1, cnt), #barTicks do
                if barTicks[i] then barTicks[i]:Hide() end
            end
        end
    end

    PaintBar()
end

local function Layout(n)
    if DB.mode == "bar" then LayoutBar(n) else LayoutGrid(n) end
    UpdateMoveBox()        -- 解锁时把可抓框撑到最小可抓尺寸、刷新黄框与坐标提示
end

-- 这只怪的红标记该贴在哪儿：进度条=第 j 段；格子=自己那格
local function RecordAnchor(unit)
    if DB.mode == "bar" then
        local j = ranks[unit]                             -- 按次序从左到右，几只怪就几段
        if not j or j > MAX_SEG then return nil end
        return DB.x + BarSlotX(j, BarCount()), DB.y       -- 贴在进度条第 j 段上
    end
    local p = PlateIndex(unit)
    if p < 1 then return nil end
    for i = 1, #units do
        if units[i] == unit then
            local c = cells[i]
            if c and c.cellX then return c.cellX, c.cellY end
            return nil
        end
    end
    return nil
end

local function RepositionRecords()
    for _, unit in ipairs(units) do
        local x, y = RecordAnchor(unit)
        local rec = records[unit]
        if x and rec and rec.visible then
            rec.container:ClearAllPoints()
            rec.container:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
            if rec.container.SetAlpha then rec.container:SetAlpha(DB.hitA) end
        end
    end
end

-- ==== 主刷新 ===============================================================
Refresh = function(force)
    -- 没有设置任何要监控的 debuff ⇒ 待机：不采集、不运算、不显示。
    if #GetSpellList() == 0 then
        if lastSig ~= "nospell" then lastSig = "nospell"; dprint(L["[2] 未设置 debuff，待机"]) end
        HideAllVisuals()
        return
    end
    if not DB.enabled then
        if lastSig ~= "off" then lastSig = "off"; dprint(L["[2] 已禁用"]) end
        HideAllVisuals()
        return
    end
    if DB.combatOnly and UnitAffectingCombat("player") ~= true then
        if lastSig ~= "idle" then lastSig = "idle"; dprint(L["[2] 非战斗状态，隐藏"]) end
        HideAllVisuals()
        return
    end

    units = GetUnits()
    barN = #units
    ranks = {}
    for j = 1, barN do ranks[units[j]] = j end

    -- 紧凑进度条：不足 BarMin() 只就整条不显示（默认 1 只怪不显示 —— 一只怪没有"比例"可看）
    if DB.mode == "bar" and barN < BarMin() then
        if lastSig ~= "few" then
            lastSig = "few"
            dprint(L["[2] 范围内只有"], barN, L["只（<"] .. BarMin() .. L["），进度条不显示"])
        end
        HideAllVisuals()
        return
    end
    -- 紧凑模式：怪太多被自动压细段宽时，按钮尺寸定死在 initializeFrame ⇒ 必须整批重建
    if DB.mode == "bar" and builtSegW and BarSegW(barN) ~= builtSegW then
        RebuildRecords()
    end
    -- 法术条数变了 ⇒ 每只怪的 slot 数量变了（建容器时定的）⇒ 必须整批重建
    if builtSpells and builtSpells ~= math.max(1, #GetSpellList()) then
        RebuildRecords()
    end
    ComputeOccupied()
    local sig = table.concat(units, ",") .. "|" .. SpellSig()
    if not force and sig == lastSig then
        Layout(#units)
        RepositionRecords()      -- 拖动/改尺寸后重新贴一次（很便宜）
        return
    end
    lastSig = sig
    dprint(L["[2] 刷新"], #units, L["只"], sig)

    Layout(#units)

    local active = {}
    for _, unit in ipairs(units) do
        local x, y = RecordAnchor(unit)
        if x then
            active[unit] = true
            ActivateRecord(unit, x, y)
        end
    end
    for unit, rec in pairs(records) do
        if not active[unit] and rec.visible then
            rec.visible = false
            rec.container:SetEnabled(false)
            rec.container:Hide()
        end
    end
end

-- ==== 命令 =================================================================
local function Help()
    -- 启动时只打一行，其余细节全在这里（/dg help）
    local ver = "?"
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        local ok, r = pcall(C_AddOns.GetAddOnMetadata, ADDON or "DotGrid", "Version")
        if ok and r then ver = r end
    end
    print(P .. fmt(L["DotGrid v%s 帮助（当前状态）"], tostring(ver)))
    print(P .. "  " .. fmt(L["开关 %s | 显示方式 %s | 监控法术 %s（%d 个，%s）"],
        DB.enabled and L["开"] or L["关"], tostring(DB.mode), SpellSig(), #GetSpellList(),
        SpellMode() == "all" and L["全部具备才变红"] or L["任一个就变红"]))
    print(P .. fmt(L["  统计口径 ≤ %s ∧ 档位 %s | 范围 %s | 位置 x=%d y=%d（%s）"],
        (DB.maxYards or 0) > 0 and fmt(L["%d 码"], DB.maxYards) or L["不限距"],
        DB.tier == 0 and L["关"] or (DB.tier == 3 and L["7 码"] or L["8 码"]),
        tostring(DB.engaged), floor(DB.x or 0), floor(DB.y or 0),
        DB.locked and L["已锁定"] or L["已解锁（可拖动）"]))
    local rows = {
        L["|cff9d9d9d—— 显示 ——|r"],
        L["/dg                             打开图形化设置界面（再按一次关闭）"],
        L["/dg help                        全部命令 + 当前状态"],
        L["/dg on | off                    启用 / 禁用"],
        L["/dg mode bar|grid               显示方式：进度条（默认）/ 格子"],
        L["/dg style solid|panel|nameplate 外观：纯色块（默认）/ 经典面板风 / 原生名字板风"],
        L["|cff9d9d9d—— 进度条 ——|r"],
        L["/dg bar segw 21                 每段宽 6–60（总长 = 怪数 × (段宽+缝) − 缝）"],
        L["/dg bar min 2                   少于这么多只怪就不显示整条（1 = 一只怪也显示）"],
        L["/dg bar height 20               条高 6–80"],
        L["/dg bar gap 1                   段间距 0–10"],
        L["/dg bar ticks on|off            段间 1px 刻度线（默认 on）"],
        L["|cff9d9d9d—— 位置 ——|r"],
        L["/dg unlock | lock               解锁拖动 / 锁回"],
        L["/dg pos                         看当前位置"],
        L["/dg pos 800 500                 直接设位置（x y，相对屏幕左下角）"],
        L["/dg pos center                  回到屏幕中左默认位置"],
        L["|cff9d9d9d—— 监控哪些 debuff（只支持 spell ID，最多 4 个） ——|r"],
        L["/dg spell 1943,703              设置监控列表（逗号 / 空格分开）"],
        L["/dg spell clear                 清空 ⇒ 插件回到待机"],
        L["/dg spells                      看当前监控了哪几个 + 多 debuff 语义"],
        L["/dg spells all|any              all = 全部具备才变红（默认）/ any = 任一命中就变红"],
        L["|cff9d9d9d—— 范围与口径 ——|r"],
        L["/dg yards 11                    精确距离上限（码）；副本内自动退回档位；0 = 只靠档位"],
        L["/dg tier 2|3|0                  档位兜底：2=8码、3=7码；0 = 不判距（范围最大）"],
        L["/dg engaged combat|threat|all   统计范围：已进战斗（默认）/ 正在跟我打 / 全算"],
        L["/dg engaged on|off              等价写法：on=combat，off=all"],
        L["/dg combat on|off               只在你自己战斗中显示（默认 on）"],
        L["|cff9d9d9d—— 格子模式 ——|r"],
        L["/dg size 18x18                  方块尺寸"],
        L["/dg perrow 5                    每行方块数"],
        L["/dg gap 4                       方块间距"],
        L["|cff9d9d9d—— 颜色（也可在设置界面里点色块调） ——|r"],
        L["/dg color hit d80f0fff          命中（红段 / 红格）颜色，末两位是透明度"],
        L["/dg color mob ffffffff          有怪、没我的 DoT 的颜色"],
        L["/dg color empty ffffff2e        底槽 / 空槽位颜色"],
        L["/dg color miss ffffffff         格子模式：有怪、没我的 DoT 的颜色"],
        L["|cff9d9d9d—— 透明度（只改透明、保留颜色） ——|r"],
        L["/dg alpha 50                    一键：命中 / 有怪段 / 格子 = 50%（底槽不动）"],
        L["/dg alpha hit 50                单个：hit|mob|miss|empty，0–100"],
        L["|cff9d9d9d—— 配置档 ——|r"],
        L["/dg profile                     列出所有档（标出本角色在用哪个）"],
        L["/dg profile new <名字>          用当前设置新建一个档并切过去"],
        L["/dg profile load <名字>         本角色切到这个档"],
        L["/dg profile save                把当前设置写回当前档"],
        L["/dg profile delete <名字>       删档（「默认」/ 正在用的档不许删）"],
        L["/dg reset                       恢复出厂（只清当前档）"],
        L["|cff9d9d9d—— 诊断 ——|r"],
        L["/dg diag                        环境自检（几何 / 范围 / 逐只状态 / 界面）"],
        L["/dg verify                      脱战真值核验（逐只对照红段）"],
        L["/dg debug on|off                调试输出"],
    }

    print(P .. L["命令："])
    for i = 1, #rows do print("   " .. rows[i]) end
end

-- 恢复出厂：只清当前档（其它档不动）⇒ 读的时候自动回落
local function ResetProfile()
    if Prof then for k in pairs(Prof) do Prof[k] = nil end end
end

local function ProfileNames()
    local names = {}
    for k in pairs(Base.profiles) do names[#names + 1] = k end
    table.sort(names)
    return names
end

local function UsersOf(name)
    local n = 0
    for _, v in pairs(Base.charProfile) do if v == name then n = n + 1 end end
    return n
end

-- /dg profile：新建 / 加载 / 保存 / 删除 / 列出
local function ProfCmd(rest)
    local sub, arg = string.match(rest or "", "^%s*(%S*)%s*(.-)%s*$")
    sub = string.lower(sub or "")

    if sub == "" or sub == "list" then
        print(P .. fmt(L["配置档：本角色（%s）正在用「%s」，共 %d 个档"],
            L[tostring(CharKeyOf or "?")], L[tostring(ProfName)], #ProfileNames()))
        for _, n in ipairs(ProfileNames()) do
            local c = 0
            if type(Base.profiles[n]) == "table" then
                for _ in pairs(Base.profiles[n]) do c = c + 1 end
            end
            print(P .. fmt(L["  %s%s｜%d 项设置｜%d 个角色在用"], L[n],
                (n == ProfName) and L["（本角色在用）"] or "", c, UsersOf(n)))
        end
        print(P .. L["  用法: /dg profile new <名字> | load <名字> | save | delete <名字>"])
        return
    end

    if sub == "new" then
        local name = string.gsub(arg or "", "^%s*(.-)%s*$", "%1")
        if name == "" then print(P .. L["用法: /dg profile new <名字>"]) return end
        if type(Base.profiles[name]) == "table" then
            print(P .. fmt(L["已经有「%s」这个档了 ⇒ 想切过去用 /dg profile load %s"], L[name], L[name]))
            return
        end
        local t = {}
        Base.profiles[name] = t
        Snapshot(t)                                   -- 用当前设置做快照
        UseProfile(name)
        lastSig = nil
        RebuildRecords(); EnsureAnchor(); ApplyLock(); lastSig = nil; Refresh(true)
        print(P .. fmt(L["已用当前设置新建「%s」并切过去（本角色从此用它；改完记得 /dg profile save）"], name))
        return
    end

    if sub == "load" then
        local name = string.gsub(arg or "", "^%s*(.-)%s*$", "%1")
        if name == "" then print(P .. L["用法: /dg profile load <名字>（/dg profile 看有哪些）"]) return end
        if not UseProfile(name) then
            print(P .. fmt(L["没有叫「%s」的档 ⇒ /dg profile 看列表"], name))
            return
        end
        lastSig = nil
        RebuildRecords(); EnsureAnchor(); ApplyLock(); lastSig = nil; Refresh(true)
        print(P .. fmt(L["本角色已切到「%s」"], name))
        return
    end

    if sub == "save" then
        Snapshot(Prof)
        print(P .. fmt(L["已把当前设置保存到「%s」"], tostring(ProfName)))
        return
    end

    if sub == "delete" then
        local name = string.gsub(arg or "", "^%s*(.-)%s*$", "%1")
        if name == "" then print(P .. L["用法: /dg profile delete <名字>"]) return end
        if name == PROFILE_DEFAULT then
            print(P .. L["「默认」档不能删（删了角色就没落脚点了）"])
            return
        end
        if name == ProfName then
            print(P .. fmt(L["「%s」是本角色正在用的档 ⇒ 先 /dg profile load 别的档再删"], name))
            return
        end
        if type(Base.profiles[name]) ~= "table" then
            print(P .. fmt(L["没有叫「%s」的档"], name))
            return
        end
        local users = UsersOf(name)
        Base.profiles[name] = nil
        for ckey, v in pairs(Base.charProfile) do        -- 用到它的角色退回「默认」
            if v == name then Base.charProfile[ckey] = PROFILE_DEFAULT end
        end
        print(P .. fmt(L["已删除「%s」%s"], name, users > 0 and fmt(L["（%d 个角色退回「默认」档）"], users) or ""))
        return
    end

    print(P .. L["用法: /dg profile [list | new <名字> | load <名字> | save | delete <名字>]"])
end

local function ParseColor(text, alpha)
    text = tostring(text or ""):gsub("#", "")
    local n = #text
    if n ~= 6 and n ~= 8 then return nil end
    local function hx(i) return tonumber(string.sub(text, i, i + 1), 16) end
    local r, g, b = hx(1), hx(3), hx(5)
    if not (r and g and b) then return nil end
    local a = alpha
    if n == 8 then
        local aa = hx(7)
        if aa then a = aa / 255 end
    end
    return r / 255, g / 255, b / 255, a
end

local function Verify()
    if UnitAffectingCombat("player") == true then
        print(P .. L["战斗中光环数据对插件不可读（12.x 的客户端限制）—— 脱战后用 /dg verify 逐只对照。"])
        return
    end
    if not (C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID) then
        print(P .. L["本客户端缺少 C_UnitAuras.GetUnitAuraBySpellID"])
        return
    end
    local list = GetSpellList()
    local us = GetUnits()
    print(P .. fmt(L["真值核验：计入 %d 只怪，监控 %d 个法术，距离档位 %s"],
        #us, #list, DB.tier == 0 and L["关闭"] or tostring(DB.tier)))
    local hit = {}
    local allHit, hitList, anyHit = 0, {}, 0
    for _, unit in ipairs(us) do
        local parts, have = {}, 0
        for _, id in ipairs(list) do
            local ok, aura = pcall(C_UnitAuras.GetUnitAuraBySpellID, unit, id)
            if not ok then
                parts[#parts + 1] = tostring(id) .. "=ERR"
            elseif aura == nil then
                parts[#parts + 1] = tostring(id) .. L["=无"]
            elseif issecretvalue and issecretvalue(aura) then
                parts[#parts + 1] = tostring(id) .. "=secret"
            else
                local apps = aura.applications
                if issecretvalue and issecretvalue(apps) then apps = "?" end
                parts[#parts + 1] = tostring(id) .. L["=有("] .. tostring(apps) .. L["层)"]
                have = have + 1
                hit[id] = (hit[id] or 0) + 1
            end
        end
        if have > 0 then anyHit = anyHit + 1 end
        if have == #list and #list > 0 then
            allHit = allHit + 1
            hitList[#hitList + 1] = unit
        end
        local extra = ""
        if DB.mode == "bar" then
            local j = SlotOf(unit)
            extra = j >= 1 and fmt(L["  → 进度条第%d段（第 %d 只）"], j, j) or L["  → 进度条上画不出来"]
        end
        print(P .. "  " .. unit .. ": " .. table.concat(parts, " / ") .. extra)
    end
    if #list > 0 then
        local perSpell = {}
        for _, id in ipairs(list) do
            perSpell[#perSpell + 1] = fmt(L["%d 命中 %d 只"], id, hit[id] or 0)
        end
        print(P .. L["  分法术命中: "] .. table.concat(perSpell, " / "))
        if #list > 1 then
            if SpellMode() == "all" then
                print(P .. fmt(L["  全中（%d 个法术都有）%d 只: %s"],
                    #list, allHit, (#hitList > 0 and table.concat(hitList, ", ") or L["无"])))
                print(P .. L["  ↑ 分格模式下只有这些怪的那一格应该整格全红；只中一部分的只剩对应那几条横条是红的"])
            else
                print(P .. fmt(L["  any 模式：任一个命中就变红（共 %d 只有至少一个命中，看不出中的是哪一个）"], anyHit))
            end
        else
            print(P .. fmt(L["  %d 号法术命中 %d 只 —— 这些怪的红标记应该亮着（脱战后插件与客户端读到的应一致）"],
                list[1], hit[list[1]] or 0))
        end
    end
end

local function GetCVarSafe(name)
    local v
    if C_CVar and C_CVar.GetCVar then
        local ok, r = pcall(C_CVar.GetCVar, name)
        if ok then v = r end
    end
    if v == nil and GetCVar then
        local ok, r = pcall(GetCVar, name)
        if ok then v = r end
    end
    return v
end

local function CountRecords()
    local n = 0
    for _ in pairs(records) do n = n + 1 end
    return n
end

local function Diag()
    print(P .. L["=== 环境自检 ==="])
    local ver = "?"
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        local ok, r = pcall(C_AddOns.GetAddOnMetadata, ADDON or "DotGrid", "Version")
        if ok and r then ver = r end
    end
    print(P .. L["  版本 "] .. tostring(ver) .. L[" | AuraContainer 路径: "] .. tostring(uiPath))
    print(P .. L["  监控法术: "] .. SpellSig() .. fmt(L["（%d 个，多 debuff 语义 = %s）"], #GetSpellList(), SpellMode())
        .. (SpellMode() == "all" and (#GetSpellList() > 1
            and L["  [分格：整格全红 = 全部命中]"] or L["  [单一法术，命中即红]"]) or L["  [任一命中即红]"]))
    print(P .. "  nameplateMaxDistance=" .. tostring(GetCVarSafe("nameplateMaxDistance")))
    print(P .. fmt(L["  范围判定: 精确码数 ≤ %s ∧ 档位 %s（取更严）| 统计范围: %s"],
        (DB.maxYards or 0) > 0 and fmt(L["%d 码"], DB.maxYards) or L["关"],
        DB.tier == 0 and L["关"] or (DB.tier == 3 and L["7 码"] or (DB.tier == 2 and L["8 码"] or DB.tier .. L[" 档"])),
        tostring(DB.engaged)))
    print(P .. fmt(L["    本帧判定: %s"],
        DB.tier == 0 and L["完全不判距（tier 0）"]
            or (sawExactDist and L["能量到精确码数（正在按码数筛）"]
                or L["量不到精确码数（副本内受限）⇒ 只用档位"])))
    print(P .. L["    （档位对照：1=28码 2=8码 3=7码 4=28码 5=7码 —— 客户端只提供这几档，没有 11 码档）"])
    print(P .. L["    （UnitDistanceSquared 原始返回: "] .. lastDistRaw .. L["｜checked=true 表示受限值，不采信）"])
    print(P .. L["  已建容器: "] .. tostring(CountRecords()) .. L[" 个 | 计入怪: "] .. tostring(#units))
    if DB.mode == "bar" then
        print(P .. fmt(L["  显示方式: 进度条（几只怪就几段）| 每段 %d 高 %d，缝 %d | 当前 %d 只 ⇒ 总长 %.0f 像素（上限 %d）"],
            BarSegW(barN), BarHeight(), BarGap(), barN, BarTotalW(barN), BAR_MAX_W))
        print(P .. fmt(L["  少于 %d 只不显示（/dg bar min）| 手工位置 x=%d y=%d（%s）"], BarMin(),
            floor(DB.x or 0), floor(DB.y or 0), DB.locked and L["已锁定"] or L["已解锁：可拖动黄框"]))
        print(P .. fmt(L["  底槽色 = 白 %.0f%%（/dg color empty 改）| 底槽与描边: %s | 刻度线 %s"],
            DB.emptyA * 100,
            (barTrough and barTrough.shown) and L["在"] or L["不在"],
            tostring(DB.barTicks)))
        print(P .. fmt(L["  透明度 = 命中 %.0f%% / 有怪 %.0f%% / 格子 %.0f%% / 底槽 %.0f%%（/dg alpha 改）"],
            DB.hitA * 100, DB.mobA * 100, DB.missA * 100, DB.emptyA * 100))
        local occ, list = 0, {}
        for i = 1, BarCount() do
            if occupied[i] then occ = occ + 1; list[#list + 1] = i .. "=" .. occupied[i] end
        end
        print(P .. fmt(L["  亮着 %d 段（= 范围内怪数）: [%s]%s"], occ, table.concat(list, " "),
            overflow > 0 and fmt(L["  画不出来: %d 只"], overflow) or ""))
    else
        print(P .. fmt(L["  显示方式: 格子 | 方块 %dx%d | 每行 %d | 间距 %d"],
            floor(DB.cellW), floor(DB.cellH), floor(DB.perRow), floor(DB.gap)))
    end
    -- 每只怪的红标记：回读"第几段、贴在哪段坐标、客户端实际用的贴图是什么"
    for unit, rec in pairs(records) do
        local f = rec.auraFrame and rec.auraFrame.DotGridFill
        local id = "?"
        if f and f.GetTexture then
            local ok1, v = pcall(f.GetTexture, f)
            if ok1 then id = tostring(v) end
        end
        if DB.mode == "bar" then
            local segW2, sh = BarSlotSize(BarCount())
            local j = SlotOf(unit)
            print(P .. fmt(L["    %s 第%d段（x=%d 宽 %.1f 高 %d）| 客户端贴图 %s%s"],
                unit, j, floor(DB.x + BarSlotX(math.max(1, j), BarCount())), segW2, sh, id,
                rec.visible and "" or L["   [当前未启用]"]))
        end
    end
    for i = 1, MAX_CELLS do
        local unit = "nameplate" .. i
        if UnitExists(unit) then
            local tiers = {}
            for t = 1, 5 do
                local ok, r = pcall(CheckInteractDistance, unit, t)
                tiers[#tiers + 1] = (not ok) and "E" or (r == true and "T" or "F")
            end
            local dist, thr = L["不可用"], "?"
            local d = UnitDistanceYards(unit)
            if d then dist = fmt(L["%.1f 码"], d) end
            if UnitThreatSituation then
                local ok2, tv = pcall(UnitThreatSituation, "player", unit)
                if ok2 and not (issecretvalue and issecretvalue(tv)) then thr = tostring(tv) end
            end
            print(P .. fmt(L["    %s atk=%s dead=%s inCombat=%s 仇恨=%s 距离=%s 档位=%s"],
                unit,
                tostring(UnitCanAttack("player", unit)),
                tostring(UnitIsDead(unit)),
                tostring(UnitAffectingCombat(unit)),
                thr, dist,
                table.concat(tiers, "")))
        end
    end
    -- 图形界面自检（UI 文件是分开加载的：独立 pcall + 判空，绝不连累 diag）
    local u = DotGrid and DotGrid.UI
    if u and u.Report then
        local okU, rU = pcall(u.Report)
        print(P .. L["  界面: "] .. (okU and tostring(rU) or (L["自检出错 "] .. tostring(rU))))
    else
        print(P .. L["  界面: DotGridUI.lua 未加载（/dg 打不开设置窗口）"])
    end
end

local function Handle(msg)
    local cmd, rest = string.match(tostring(msg or ""), "^(%S*)%s*(.-)$")
    cmd = string.lower(cmd or "")
    rest = rest or ""

    if cmd == "help" then
        Help()
    elseif cmd == "" or cmd == "config" or cmd == "ui" or cmd == "options" or cmd == "settings" then
        -- 图形化设置界面（DotGridUI.lua）：/dg 空参数 = 开关窗口，/dg config = 打开
        if DotGrid and DotGrid.UI and DotGrid.UI.Open then
            if cmd == "" then DotGrid.UI.Toggle() else DotGrid.UI.Open() end
        else
            print(P .. L["设置界面不可用（DotGridUI.lua 没加载？）；命令看 /dg help"])
        end
    elseif cmd == "on" or cmd == "off" then
        DB.enabled = (cmd == "on")
        lastSig = nil
        Refresh(true)
        print(P .. (DB.enabled and L["已启用"] or L["已禁用"]))
    elseif cmd == "spell" or cmd == "spells" then
        if rest == "clear" or rest == "none" then
            DB.spells = {}
            RebuildRecords(); lastSig = nil; Refresh(true)
            print(P .. L["已清空监控列表：插件进入待机（不做任何计算与显示）。/dg spell <法术ID> 重新设置。"])
        elseif rest == "all" or rest == "any" then
            DB.spellMode = rest
            RebuildRecords()                     -- 分格/整格的按钮几何不同 ⇒ 整批重建
            Refresh(true)
            if rest == "all" then
                print(P .. L["多 debuff 语义 = 全部具备才变红（每个法术占格子的一条横条，整格全红 = 全中）"])
            else
                print(P .. L["多 debuff 语义 = 任一个命中就变红（命中任意一个就整格变红）"])
            end
        elseif rest == "" then
            local list = GetSpellList()
            print(P .. fmt(L["当前监控 %d 个法术: %s"], #list, SpellSig()))
            if SpellMode() == "all" then
                print(P .. L["多 debuff 语义: all = 必须全部具备才变红（/dg spells any 改为任一命中即红）"])
            else
                print(P .. L["多 debuff 语义: any = 任一个命中就变红（/dg spells all 改为全部命中才红）"])
            end
            if #list > 1 and SpellMode() == "all" then
                print(P .. fmt(L["  每只怪那一格自上而下切成 %d 条横条（顺序同上），整格全红 = 全部命中"], #list))
            elseif #list > 1 then
                print(P .. fmt(L["  any 模式：%d 个 slot 都盖满整格，任一个命中整格就红（看不出是哪一个）"], #list))
            end
        else
            local list = {}
            for id in string.gmatch(rest, "%d+") do list[#list + 1] = tonumber(id) end
            if #list == 0 then
                print(P .. L["用法: /dg spell 1943,703        （多个法术用逗号/空格分开）"])
            else
                local dropped = 0
                while #list > MAX_SPELLS do table.remove(list); dropped = dropped + 1 end
                DB.spells = list
                RebuildRecords()                 -- 法术条数变了 ⇒ slot 数量变了 ⇒ 整批重建
                Refresh(true)
                print(P .. fmt(L["监控法术 = %s（%d 个；%s）"], SpellSig(), #list,
                    SpellMode() == "all" and (#list > 1 and L["分格：整格全红 = 全部命中"] or L["单个法术"]) or L["任一命中即红"]))
                if dropped > 0 then
                    print(P .. fmt(L["  最多只能监控 %d 个：忽略了你多给的 %d 个。"], MAX_SPELLS, dropped))
                end
            end
        end
    elseif cmd == "tier" then
        local n = tonumber(rest)
        if n and n >= 0 and n <= 5 then
            DB.tier = n
            lastSig = nil
            Refresh(true)
            local yard = ({ [1] = L["28 码"], [2] = L["8 码"], [3] = L["7 码"], [4] = L["28 码"], [5] = L["7 码"] })[n]
            print(P .. L["距离档位 = "] .. n .. (n == 0 and L["（不判距）"]
                or fmt(L["（%s，仅在精确码数不可用时生效）"], yard)))
        else
            print(P .. L["用法: /dg tier 0|2|3（0=不判距，2=8码，3=7码）"])
        end
    elseif cmd == "yards" then
        local n = tonumber(rest)
        if n and n >= 0 and n <= 60 then
            DB.maxYards = floor(n)
            lastSig = nil
            Refresh(true)
            if n == 0 then
                print(P .. L["精确码数判定 = 关（只用档位）"])
            else
                print(P .. fmt(L["精确码数判定 = ≤ %d 码（UnitDistanceSquared，与档位取更严的那个）"], n))
                print(P .. fmt(L["  当前状态: %s"], lastDistMode == "exact"
                    and L["可用（正在按码数筛）"]
                    or L["不可用（副本里该 API 受限，已自动退回档位 %d ≈ %s）"],
                    DB.tier, DB.tier == 3 and L["7 码"] or L["8 码"]))
            end
        else
            print(P .. L["用法: /dg yards 11（0=关，最大 60）"])
        end
    elseif cmd == "engaged" then
        local v = string.lower(rest)
        if v == "on" then v = "combat" elseif v == "off" then v = "all" end
        if v == "all" or v == "combat" or v == "threat" then
            DB.engaged = v
            lastSig = nil
            Refresh(true)
            print(P .. L["统计范围 = "] .. v .. (v == "all" and L["（范围内全算）"]
                or v == "combat" and L["（只算已进入战斗的怪）"]
                or L["（只算我仇恨列表里的怪 = 正在跟我打的）"]))
        else
            print(P .. L["用法: /dg engaged all|combat|threat（on=combat, off=all）"])
        end
    elseif cmd == "combat" then
        if rest == "on" or rest == "off" then
            DB.combatOnly = (rest == "on")
            lastSig = nil
            Refresh(true)
            print(P .. L["只在战斗中显示 = "] .. tostring(DB.combatOnly))
        else
            print(P .. L["用法: /dg combat on|off"])
        end
    elseif cmd == "size" then
        local w, h = string.match(rest, "^(%d+)[xX](%d+)$")
        w = tonumber(w) or tonumber(rest)
        h = tonumber(h) or w
        if w and h and w >= 6 and w <= 80 and h >= 6 and h <= 80 then
            DB.cellW, DB.cellH = w, h
            RebuildRecords()
            Refresh(true)
            print(P .. fmt(L["方块 = %dx%d（红格已重建）"], w, h))
        else
            print(P .. L["用法: /dg size 18x18"])
        end
    elseif cmd == "perrow" then
        local n = tonumber(rest)
        if n and n >= 1 and n <= 20 then
            DB.perRow = n
            lastSig = nil
            Refresh(true)
            print(P .. L["每行方块数 = "] .. n)
        else
            print(P .. L["用法: /dg perrow 5"])
        end
    elseif cmd == "gap" then
        local n = tonumber(rest)
        if n and n >= 0 and n <= 30 then
            DB.gap = n
            lastSig = nil
            Refresh(true)
            print(P .. L["间距 = "] .. n)
        else
            print(P .. L["用法: /dg gap 4"])
        end
    elseif cmd == "bar" then
        local sub, val = string.match(rest, "^(%a+)%s*(.*)$")
        sub = string.lower(sub or "")
        local function changed(msg)
            RebuildRecords()                  -- 每段宽度/高度变了 → 红段矩形必须跟着变
            lastLayoutKey, paintSig, lastSig = nil, nil, nil
            Refresh(true)
            print(P .. msg)
        end
        if sub == "width" then
            print(P .. L["总长永远随怪数变化：每只怪一段（段宽用 /dg bar segw 调整）"])
        elseif sub == "segw" then
            local n = tonumber(val)
            if n and n >= 6 and n <= 60 then
                DB.barSegW = floor(n)
                changed(fmt(L["每段宽 = %d（总长 = 怪数 × (%d+%d) - %d，如 4 只怪 = %d 像素）"],
                    DB.barSegW, DB.barSegW, BarGap(), BarGap(), 4 * (DB.barSegW + BarGap()) - BarGap()))
            else
                print(P .. L["用法: /dg bar segw 21（6–60）"])
            end
        elseif sub == "min" then
            local n = tonumber(val)
            if n and n >= 0 and n <= 10 then
                DB.barMin = floor(n)
                lastLayoutKey, paintSig, lastSig = nil, nil, nil
                Refresh(true)
                print(P .. (DB.barMin <= 1 and L["任何怪数都显示整条"]
                    or fmt(L["少于 %d 只怪就不显示整条"], DB.barMin)))
            else
                print(P .. L["用法: /dg bar min 2（0–10；1 = 一只怪也显示）"])
            end
        elseif sub == "fixed" then
            print(P .. L["进度条永远跟着怪数走（没有固定长度模式）：每只怪一段"])
        elseif sub == "height" then
            local n = tonumber(val)
            if n and n >= 6 and n <= 80 then
                DB.barH = floor(n)
                changed(L["进度条高 = "] .. DB.barH .. L["（红段已重建）"])
            else
                print(P .. L["用法: /dg bar height 20（6–80）"])
            end
        elseif sub == "gap" then
            local n = tonumber(val)
            if n and n >= 0 and n <= 10 then
                DB.barGap = floor(n)
                changed(L["段间距 = "] .. DB.barGap .. L["（红段已重建）"])
            else
                print(P .. L["用法: /dg bar gap 1（0–10）"])
            end
        elseif sub == "ticks" then
            if val == "on" or val == "off" then
                DB.barTicks = (val == "on")
                lastLayoutKey, paintSig = nil, nil
                Refresh(true)
                print(P .. L["段间刻度线 = "] .. tostring(DB.barTicks))
            else
                print(P .. L["用法: /dg bar ticks on|off"])
            end
        else
            print(P .. L["用法: /dg bar segw 21 | min 2 | height 20 | gap 1 | ticks on|off"])
        end
    elseif cmd == "mode" then
        local m = string.lower(rest)
        if m == "bar" or m == "grid" then
            if DB.mode ~= m then
                DB.mode = m
                RebuildRecords()          -- 三种模式的按钮矩形不同 → 整批重建
                lastLayoutKey, paintSig, lastSig = nil, nil, nil
                EnsureAnchor()
                Refresh(true)
            end
            print(P .. L["显示方式 = "] .. m .. (m == "bar"
                and L["（进度条：几只怪几段、总长随怪数变；白 = 有怪、红 = 我的 debuff）"]
                or L["（格子：白 = 范围内，红 = 我的 debuff）"]))
        elseif m == "" then
            print(P .. L["当前显示方式 = "] .. tostring(DB.mode) .. L["（/dg mode bar|grid）"])
        else
            print(P .. L["用法: /dg mode bar|grid"])
        end
    elseif cmd == "style" then
        local m = string.lower(rest or "")
        if STYLE_SPEC[m] or m == STYLE_SOLID then
            if DB.style ~= m then
                DB.style = m
                RebuildRecords()          -- 填充贴图在容器创建时定死 ⇒ 整批重建
                lastLayoutKey, paintSig, lastSig = nil, nil, nil
                EnsureAnchor()
                ApplyAnchorStyle()
                Refresh(true)
            end
            if m == STYLE_SOLID then
                print(P .. L["外观 = solid（纯色块：全部自绘，不用任何贴图）"])
            elseif m == STYLE_PANEL then
                print(P .. L["外观 = panel（经典面板风：游戏自带的提示框面板 + 条纹理）"])
            else
                print(P .. L["外观 = nameplate（原生名字板风：游戏自带的 名字板金边 + 名字板血条纹理）"])
            end
        elseif m == "" then
            print(P .. fmt(L["当前外观 = %s（/dg style solid|panel|nameplate）"], tostring(DB.style or STYLE_SOLID)))
        else
            print(P .. L["用法: /dg style solid|panel|nameplate（纯色块 / 经典面板风 / 原生名字板风）"])
        end
    elseif cmd == "alpha" then
        -- 只改透明度、保留 RGB。角色：hit（命中红）/ mob（进度条有怪段）/ miss（格子的白块）/ empty（底槽）
        local knownA = { hit = true, mob = true, miss = true, empty = true }
        local which, pct = string.match(rest, "^(%a+)%s+(%d+)$")
        which = string.lower(which or "")
        local allPct = tonumber(string.match(rest, "^(%d+)$"))
        local function ApplyA(role, p)
            local a = math.max(0, math.min(100, floor(p + 0.5))) / 100
            if role == "hit" then DB.hitA = a
            elseif role == "mob" then DB.mobA = a
            elseif role == "miss" then DB.missA = a
            else DB.emptyA = a end
            return a
        end
        if knownA[which] and pct then
            local a = ApplyA(which, tonumber(pct))
            if which == "hit" then RebuildRecords() end   -- 红的 RGB 定死在容器创建时（alpha 走容器，不必重建）
            lastSig, lastLayoutKey, paintSig = nil, nil, nil
            Refresh(true)
            print(P .. fmt(L["%s 透明度 = %.0f%%"], which, a * 100))
        elseif allPct then
            local a = ApplyA("hit", allPct)
            ApplyA("mob", allPct); ApplyA("miss", allPct)
            RebuildRecords()
            lastSig, lastLayoutKey, paintSig = nil, nil, nil
            Refresh(true)
            print(P .. fmt(L["透明度：命中 / 有怪段 / 格子 一起 = %.0f%%（底槽保持 %.0f%% 不动 —— 它必须比有怪段暗；"] ..
                L["单独调用 /dg alpha empty N 改它）"], a * 100, DB.emptyA * 100))
        else
            print(P .. L["用法: /dg alpha 0-100（命中/有怪段/格子 一起）或 /dg alpha hit|mob|miss|empty 0-100"])
        end
    elseif cmd == "color" or cmd == "colour" then
        local which, hex = string.match(rest, "^(%a+)%s+(%S+)$")
        which = string.lower(which or "")
        local known = { hit = true, miss = true, mob = true, empty = true }
        if known[which] then
            local defA = which == "hit" and DB.hitA
                or which == "mob" and DB.mobA
                or which == "empty" and DB.emptyA
                or DB.missA
            local r, g, b, a = ParseColor(hex, defA)
            if r then
                if which == "hit" then
                    DB.hitR, DB.hitG, DB.hitB, DB.hitA = r, g, b, a
                    RebuildRecords()          -- 红扇区颜色只能在创建时定 → 重建
                elseif which == "mob" then
                    DB.mobR, DB.mobG, DB.mobB, DB.mobA = r, g, b, a
                elseif which == "empty" then
                    DB.emptyR, DB.emptyG, DB.emptyB, DB.emptyA = r, g, b, a
                else
                    DB.missR, DB.missG, DB.missB, DB.missA = r, g, b, a
                end
                lastSig = nil
                Refresh(true)
                print(P .. which .. L[" 颜色已更新"])
            else
                print(P .. L["颜色要写 6 或 8 位十六进制，例如 /dg color hit d80f0f"])
            end
        else
            print(P .. L["用法: /dg color hit|mob|empty|miss RRGGBB[AA]"])
        end
    elseif cmd == "pos" then
        if rest == "" or rest == "show" then
            print(P .. fmt(L["当前位置 x=%d y=%d（%s）"], floor(DB.x or 0), floor(DB.y or 0),
                DB.locked and L["已锁定；/dg unlock 后可拖动"] or L["已解锁：直接拖屏幕上的黄框"]))
        elseif rest == "center" then
            DB.x = floor(UIParent:GetWidth() * 0.5 - 120)
            DB.y = floor(UIParent:GetHeight() * 0.55)
            lastLayoutKey, lastSig = nil, nil
            ApplyLock()
            Refresh(true)
            print(P .. fmt(L["已移到屏幕中左：x=%d y=%d"], floor(DB.x), floor(DB.y)))
        else
            local nx, ny = string.match(rest, "^(%-?%d+)%s+(%-?%d+)$")
            if nx and ny then
                DB.x, DB.y = tonumber(nx), tonumber(ny)
                lastLayoutKey, lastSig = nil, nil
                ApplyLock()
                Refresh(true)
                print(P .. fmt(L["位置 = x=%d y=%d"], floor(DB.x), floor(DB.y)))
            else
                print(P .. L["用法: /dg pos（看当前位置）| /dg pos 800 500（直接设）| /dg pos center（回屏幕中间）"])
            end
        end
    elseif cmd == "lock" then
        DB.locked = true
        lastLayoutKey = nil
        ApplyLock()
        Refresh(true)
        print(P .. L["已锁定"])
    elseif cmd == "unlock" then
        DB.locked = false
        lastLayoutKey = nil
        ApplyLock()
        Refresh(true)
        print(P .. L["已解锁：屏幕上的黄框就是显示区，直接拖它调整位置；/dg lock 锁回（位置存进存档）"])
    elseif cmd == "verify" then
        Verify()
    elseif cmd == "diag" or cmd == "status" then
        Diag()
    elseif cmd == "debug" then
        if rest == "on" or rest == "off" then
            DB.debug = (rest == "on")
            print(P .. L["调试输出 = "] .. tostring(DB.debug))
        else
            print(P .. L["用法: /dg debug on|off"])
        end
    elseif cmd == "profile" or cmd == "profiles" or cmd == "char" then
        ProfCmd(rest or "")
    elseif cmd == "reset" then
        ResetProfile()
        RebuildRecords()
        EnsureAnchor()
        ApplyLock()
        lastSig = nil
        Refresh(true)
        print(P .. fmt(L["「%s」档已恢复出厂（其它档不受影响）"], tostring(ProfName)))
    else
        print(P .. L["未知命令: "] .. cmd .. L["（/dg help）"])
    end
end

-- ==== 事件 / 驱动 ==========================================================
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("NAME_PLATE_UNIT_ADDED")
ev:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
ev:SetScript("OnEvent", function(_, event, arg1)
    dprint(L["[1] 事件"], event, arg1)
    if event == "PLAYER_ENTERING_WORLD" then lastSig = nil end
    Refresh(true)
end)

local tick = CreateFrame("Frame")
tick:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + (tonumber(dt) or 0)
    if elapsed < REFRESH_INTERVAL then return end
    elapsed = 0
    Refresh(false)
end)

-- ==== 初始化 ===============================================================
local function Init()
    DotGridDB = DotGridDB or {}
    UpgradeToProfiles()                      -- 老结构 → 档体系（只做一次）
    WireDB()                                 -- 接上L["当前档 ∪ 出厂默认"]的合并视图
    CopyDefaults(DEFAULTS, Base)             -- 出厂默认铺在账号级（档里只存改动）
    -- 不自动设置任何法术：空列表 = 待机，由用户在界面或命令里设置
    if DB.cfgVer ~= CFG_VER then            -- 老存档迁移：只改L["还是旧默认值"]的项，动过的一律不碰
        local prev = tonumber(Base.cfgVer) or 0
        if prev < 3 then
            DB.mode = DEFAULT_MODE          -- 存档改版 3：默认显示方式改为进度条
        end
        if prev < 4 then
            if DB.mobA == 0.22 then DB.mobA = 0.35 end                          -- 存档改版 4：亮段默认白 35%
            if DB.emptyA == 0.07 or DB.emptyA == 0.10 then DB.emptyA = 0.18 end -- 存档改版 4：底槽默认白 18%
        end
        if prev < 6 then
            -- 存档改版 6：打底改为纯白（更容易观察）；只改"仍是旧默认值"的项，自己调过颜色的不动
            if DB.mobA == 0.35 then DB.mobA = 1.00 end
            if DB.missA == 0.18 then DB.missA = 1.00 end
        end
        if prev < 7 then
            -- 存档改版 7：饼图与固定长度进度条已移除 ⇒ 清掉这些存档键，早期的饼图设置回落到进度条
            DB.pieSize, DB.pieDemo, DB.dial = nil, nil, nil
            DB.barFixed, DB.barW = nil, nil
            -- 老存档若只表达过"别算没进战斗的怪"，把那个意图迁到 engaged
            if DB.requireCombat == false and DB.engaged == "combat" then DB.engaged = "all" end
            DB.showLabel, DB.requireCombat = nil, nil
            if DB.mode == "pie" then DB.mode = DEFAULT_MODE end
        end
        Base.cfgVer = CFG_VER
    end
    -- 清理：早期版本遗留的死键（账号级 + 每一个档都扫）
    Base.pieSectors = nil
    if Prof and Prof.pieSectors ~= nil then Prof.pieSectors = nil end
    for _, pt in pairs(Base.profiles) do
        if type(pt) == "table" and pt.pieSectors ~= nil then pt.pieSectors = nil end
    end
    if not Base.x or not Base.y then                              -- 出厂位置（账号级）
        Base.x = floor(UIParent:GetWidth() * 0.5 - 120)
        Base.y = floor(UIParent:GetHeight() * 0.55)
    end

    EnsureAnchor()
    ApplyLock()
    ApplyAnchorStyle()

    SLASH_DOTGRID1 = "/dg"
    SLASH_DOTGRID2 = "/dotgrid"
    SlashCmdList["DOTGRID"] = Handle

    Refresh(true)
    -- 启动只打一行：其余细节（版本/方式/口径/法术/位置/全部命令）都在 /dg help 里
    if SpellSig() == "" then
        print(P .. L["DotGrid 已加载：还没有设置要监控的 debuff，插件处于待机（不做任何计算与显示）。"] ..
              L["用 /dg spell 1943,703 设置法术 ID，/dg 打开设置界面，/dg help 看全部命令。"])
    else
        print(P .. fmt(L["DotGrid 已加载（%s，监控 %s）。/dg 打开设置界面，/dg help 看全部命令。"],
            DB.mode == "grid" and L["格子"] or L["进度条"], SpellSig()))
    end
end

-- ==== 对外接口（给 DotGridUI.lua 用）========================================
-- 界面里所有操作都拼成"命令字符串"再走这里，等于走同一个 Handle：
-- 行为、默认值、重建时机、日志输出与命令行 100% 一致，不会出现两套逻辑漂移。
DotGrid = {
    Run        = function(cmd) SlashCmdList["DOTGRID"](cmd) end,
    DB         = function() return DB end,
    Spells     = function() return GetSpellList() end,
    Profiles   = function()
        local names = {}
        if Base then for k in pairs(Base.profiles or {}) do names[#names + 1] = k end end
        table.sort(names)
        return names, ProfName or PROFILE_DEFAULT
    end,
    ProfileName = function() return ProfName end,
    SpellMode  = SpellMode,
    MAX_SPELLS = MAX_SPELLS,
    Count      = CountRecords,
    GetVersion = function()
        if C_AddOns and C_AddOns.GetAddOnMetadata then
            local ok, v = pcall(C_AddOns.GetAddOnMetadata, "DotGrid", "Version")
            if ok and v then return tostring(v) end
        end
        return "?"
    end,
}

C_Timer.After(0, Init)

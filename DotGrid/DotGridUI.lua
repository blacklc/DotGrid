--[[============================================================================
 DotGrid 图形化设置界面（DotGridUI.lua）—— 需要 DotGrid.lua 先加载
 文档见 README「设置界面」一节。

 不可破坏的约束：
 1) 界面里不做任何自己的逻辑：每个控件的结果都拼成一条命令字符串，交给
    API.Run()（= SlashCmdList["DOTGRID"]）执行。这样默认值、存档迁移、重建时机、
    聊天框回显永远和 /dg 一致，不会出现「界面上改的东西命令改不了」的漂移。
 2) 不使用任何 Blizzard 模板（UICheckButtonTemplate / OptionsSliderTemplate /
    BackdropTemplate / UIPanelScrollFrameTemplate 等）：纯色 Texture 当底、
    FontString 当字、Slider / EditBox / Button 用核心类型 —— 跨客户端版本更稳。
 3) 滑条连续拖动会合并（0.25 秒内只下发一次命令）：段宽 / 尺寸这类命令会触发
    整批重建容器，不能每移一像素就重建一次。
 4) 战斗中打开没问题，但改「监控法术 / 过滤器」在光环隐秘期可能要脱战后才生效
    （客户端限制）；界面底部与「工具」页有对应提示。
 5) /dg debug on 后，界面刷新时的异常会被 pcall 抓住并打印，便于定位。
============================================================================]]
local ADDON, NS = ...
local P   = "|cff33ff99[DotGrid]|r"
local API = DotGrid
local L   = (NS and NS.L) or setmetatable({}, { __index = function(_, k) return k end })
if not API then return end

local UI = { rows = {}, widgets = {}, coverage = {}, spellRows = {}, actions = {}, byLabel = {}, previewRows = {} }
DotGrid.UI = UI

local floor = math.floor
local fmt   = string.format
local tinsert = table.insert

-- ==== 配色（全部自绘，没用任何模板）========================================
local C = {
    win    = { 0.04, 0.04, 0.06, 0.97 },
    head   = { 0.15, 0.15, 0.19, 1.00 },
    side   = { 0.10, 0.10, 0.13, 1.00 },
    body   = { 0.06, 0.06, 0.08, 1.00 },
    row    = { 0.09, 0.09, 0.12, 0.85 },
    line   = { 0.28, 0.28, 0.34, 1.00 },
    text   = { 0.93, 0.93, 0.94, 1.00 },
    dim    = { 0.60, 0.62, 0.68, 1.00 },
    accent = { 0.25, 1.00, 0.62, 1.00 },
    btn    = { 0.16, 0.16, 0.21, 1.00 },
    btnHi  = { 0.26, 0.26, 0.33, 1.00 },
    on     = { 0.16, 0.62, 0.42, 1.00 },
    off    = { 0.28, 0.28, 0.33, 1.00 },
    del    = { 0.36, 0.15, 0.17, 1.00 },
    warn   = { 1.00, 0.68, 0.30, 1.00 },
}

-- ==== 原生素材：图形界面一律用游戏自带的贴图（不新增任何文件）====================
-- 任何一处失败都退回自绘纯色：贴图/模板名可能随补丁变，绝不允许白块或报错。
local ART = {
    -- 图形界面一律自绘（纯色底 + 1px 描边），不引用游戏自带的对话框材质与图标。
    -- 这里只剩「显示区」外观档还需要的两条游戏条纹理。
    barFill    = "Interface\\TargetingFrame\\UI-StatusBar",
    npFill     = "Interface\\TargetingFrame\\NameplateFill",
}
local BACKDROP_TEMPLATE = "BackdropTemplate"

-- 「最初的风格」：界面全部自绘（纯色底 + 1px 描边），不设任何原生面板。
-- 保留这个函数名只是为了让各处调用点不用动；它会**清掉**可能残留的原生面板。
local function NativePanel(f, color)
    if f and f.SetBackdrop then pcall(f.SetBackdrop, f, nil) end
    return false
end

-- 窗口内边距：自绘风格下为 0
local WIN_IN_L, WIN_IN_R, WIN_IN_T, WIN_IN_B = 0, 0, 0, 0
-- 按钮四态换成游戏自带的按钮贴图
local function NativeButton(b)
    if not (b and b.SetNormalTexture) then return false end
    if not pcall(b.SetNormalTexture, b, ART.btnUp) then return false end
    if b.SetPushedTexture    then pcall(b.SetPushedTexture, b, ART.btnDown) end
    if b.SetHighlightTexture then pcall(b.SetHighlightTexture, b, ART.btnHi) end
    if b.SetDisabledTexture  then pcall(b.SetDisabledTexture, b, ART.btnDis) end
    if b.GetNormalTexture then
        local okN, nt = pcall(b.GetNormalTexture, b)
        if okN and nt then b.normalTex = nt end     -- 选中/悬停就靠给它染色（原生贴图盖住了自绘底）
    end
    return true
end

-- 按钮状态：on = 当前项。指示方式是"左侧强调色竖条 + 字变强调色"——
-- 不要靠底色调状态：原生按钮贴图中心半透明，底色会从中透出来变成花脸。
-- 状态依旧靠底色表达（最初的样子）：当前项 = 强调绿底，其它 = 常规深灰底
local function SetBtnState(b, on)
    if not b then return end
    if b.bg then
        local c = on and C.on or C.btn
        b.baseColor = c
        b.bg:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    end
end

local WIN_W, WIN_H, HEAD_H, SIDE_W = 1080, 940, 34, 176
-- 内容区高 = WIN_H - HEAD_H - 8(标题下缝) - 26(底部状态栏) = 872（含预览行与透明度滑条）
local CONTENT_H = WIN_H - HEAD_H - 8 - 26
local ROW_H, CTRL_X = 34, 252          -- 基础行高 / 控件列左边界
-- 行高太紧时说明文字会顶到下一行的控件上（看着像重叠），所以留两层余量：
--   ① 每行之间固定留 ROW_GAP 的缝；② 带说明的行给足高度。
local ROW_GAP  = 6
local ROW_NOTE = 62                    -- 带说明文字的行（说明从 -32 起画，单行 ~14）
local ROW_SEC  = 42                     -- 分区标题行
local RIGHT_PAD = 12                    -- 行内贴右端的东西（按钮组/滑条数值/开关）统一离右边这么远
local MAX_SPELLS_UI = 4           -- 列表最多画这么多行（= 插件里的 MAX_SPELLS = 4）

local frame, content, viewport, sidePanel, statusText, spellInput, spellPanel, spellHint
local profInput, profNameText, profList                                  -- 「配置档」页
local PROFILE_MAX_UI = 12
local currentTab = "general"

-- 内容区整体上移多少：必须先 ClearAllPoints 再设点。否则每滚一次、每切一次页都会再叠一个
-- 同点不同偏移的锚点；客户端里锚点冲突会把帧的位置/尺寸算乱（"右边一片空白"的常见成因）。
local function SetScroll(v)
    UI.scroll = v or 0
    if not content or not viewport then return end
    content:ClearAllPoints()
    content:SetPoint("TOPLEFT", viewport, "TOPLEFT", 0, UI.scroll)
    content:SetPoint("TOPRIGHT", viewport, "TOPRIGHT", 0, UI.scroll)
end

-- ==== 自绘小工具 ===========================================================
local function Tex(owner, color, layer)
    local t = owner:CreateTexture(nil, layer or "BACKGROUND")
    t:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    t:SetAllPoints(true)
    return t
end

local function Font(owner, size, color)
    local fs = owner:CreateFontString(nil, "OVERLAY")
    local obj = (size == "huge" and GameFontNormalHuge) or (size == "big" and GameFontNormalLarge)
        or (size == "small" and GameFontNormalSmall) or GameFontNormal
    if obj and fs.SetFontObject then pcall(fs.SetFontObject, fs, obj) end
    fs:SetTextColor(color[1], color[2], color[3])
    fs:SetJustifyH("LEFT")
    return fs
end

-- 有底、有边、有字的按钮
local function MakeButton(parent, text, w, h, onClick, color)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    b.baseColor = color or C.btn
    b.bg = Tex(b, b.baseColor)
    b.txt = Font(b, "small", C.text)
    b.txt:SetPoint("CENTER", 0, 0)
    b.txt:SetText(text)
    b.txt:SetJustifyH("CENTER")
    b:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(C.btnHi[1], C.btnHi[2], C.btnHi[3], 1)
    end)
    b:SetScript("OnLeave", function(self)
        local c = self.baseColor
        self.bg:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    end)
    b:SetScript("OnClick", onClick)
    return b
end

-- 一条命令的执行口：字符串直接执行；函数拿当前值现拼（用于 size 宽x高 这种双参数）
local function RunCmd(cmd, value)
    if type(cmd) == "function" then
        API.Run(cmd(value))
    elseif value ~= nil then
        API.Run(fmt(cmd, value))
    else
        API.Run(cmd)
    end
end

-- ==== 行 / 分区 =============================================================
local function NewRow(tabKey, height)
    local f = CreateFrame("Frame", nil, content)
    f.tab, f.h = tabKey, height or ROW_H
    -- 真客户端里必须给行一个**显式高度**：只挂 TOPLEFT+TOPRIGHT 两个锚点的帧高度算出来是 0，
    -- 整行被压成一条 0 高度的线，行背景(SetAllPoints)也跟着塌掉 —— 桩的 h 字段看不出这个差别。
    f:SetHeight(f.h)
    f.bgc = Tex(f, C.row)          -- 每行一条淡底：行与行靠它 + ROW_GAP 的缝分开，不再糊成一片
    f:Hide()
    tinsert(UI.rows, f)
    return f
end

local function RowLabel(row, text, color)
    local l = Font(row, "small", color or C.text)
    -- 顶对齐（-8 让它和 -4 起的控件上下居中）。原来用 SetPoint("LEFT",10,0) = 垂直居中：
    -- 行高从 26 加到 62 之后它掉到行的正中，正好压在 -32 起的说明文字上（截图里的重叠就是这个）
    l:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -8)
    l:SetText(text)
    row.label = l
    return l
end

local function RowNote(row, text, color, dy)
    -- 说明文字放在控件**下方**（控件占 -4..-24，所以默认从 -26 起），
    -- 并按文字真实高度把行撑高（游戏里 FontString:GetStringHeight 可读；
    -- 桩里没有这个方法就退回单行高度）。曾经的 bug：说明从 -17 起画，和控件叠在一起。
    local d0 = dy or -32
    local n = Font(row, "small", color or C.dim)
    -- 缩进与配置名一致（都是 12），统一加「说明：」标示
    n:SetPoint("TOPLEFT", row, "TOPLEFT", 12, d0)
    n:SetPoint("RIGHT", row, "RIGHT", -14, 0)
    n:SetText(L["说明："] .. tostring(text))
    if n.SetWordWrap then pcall(n.SetWordWrap, n, true) end
    local h = 14
    if n.GetStringHeight then
        local okH, sh = pcall(n.GetStringHeight, n)
        if okH and type(sh) == "number" and sh > 4 then h = sh end
    end
    -- 建行时这一行还没有宽度 ⇒ GetStringHeight 只量得出"一行"的高度。
    -- 所以登记下来，等 Layout 把行锚好（宽度定了）再按折行后的真实高度重排。
    row.note, row.noteTop = n, d0
    row.h = math.max(row.h, (-d0) + h + 8)
    return n
end

local function Section(tabKey, text)
    local row = NewRow(tabKey, ROW_SEC)
    local l = Font(row, "normal", C.accent)
    l:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -6)
    l:SetText(text)
    local line = row:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", 8, 2)
    line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, 2)
    return row
end

local function Note(tabKey, text, color, height)
    local row = NewRow(tabKey, height or ROW_NOTE)
    local l = Font(row, "small", color or C.dim)
    l:SetPoint("TOPLEFT", 12, -4)
    l:SetPoint("RIGHT", row, "RIGHT", -12, 0)
    l:SetText(text)
    if l.SetWordWrap then pcall(l.SetWordWrap, l, true) end
    row.note, row.noteTop = l, -4        -- 同上：给 Layout 的L["重排"]用
    return row
end

-- ==== 控件工厂 ==============================================================
-- 1) 开关（点一下 = 一条 on/off 命令）
local function Toggle(tabKey, label, onCmd, offCmd, getFn, note)
    local row = NewRow(tabKey, note and ROW_NOTE or ROW_H)
    RowLabel(row, label)
    if note then RowNote(row, note) end

    local btn = CreateFrame("Button", nil, row)
    btn:SetSize(20, 20)
    btn:SetPoint("TOPRIGHT", row, "TOPRIGHT", -RIGHT_PAD, -6)   -- 顶对齐 + 贴右端（与说明/数值同一条竖线）
    btn.box  = Tex(btn, C.off)
    btn.mark = btn:CreateTexture(nil, "OVERLAY")
    btn.mark:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    btn.mark:SetSize(10, 10)
    btn.mark:SetPoint("CENTER", 0, 0)
    btn:SetScript("OnClick", function()
        API.Run(getFn() and offCmd or onCmd)
        UI.RefreshAll()
    end)
    row.control = btn
    tinsert(UI.widgets, {
        kind = "toggle", row = row, btn = btn, get = getFn,
        refresh = function(w)
            local on = w.get() and true or false
            w.btn.mark:SetShown(on)
            local c = on and C.on or C.off
            w.btn.box:SetColorTexture(c[1], c[2], c[3], 1)
        end,
    })
    return btn
end

-- 2) 滑条（拖动合并：最后一次变化后 0.25 秒下发一次）
local function Slider(tabKey, label, min, max, step, cmd, getFn, showFn, note)
    local row = NewRow(tabKey, note and ROW_NOTE or ROW_H)
    RowLabel(row, label)
    if note then RowNote(row, note) end

    local s = CreateFrame("Slider", nil, row)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(340, 16)
    s:SetPoint("TOPLEFT", row, "TOPLEFT", CTRL_X, -8)
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then pcall(s.SetObeyStepOnDrag, s, true) end
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    track:SetHeight(6)
    track:SetPoint("LEFT", 0, 0)
    track:SetPoint("RIGHT", 0, 0)
    local thumb = s:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    thumb:SetSize(16, 16)
    s:SetThumbTexture(thumb)

    local val = Font(row, "small", C.accent)
    val:SetPoint("TOPRIGHT", row, "TOPRIGHT", -RIGHT_PAD, -8)
    val:SetWidth(130)
    val:SetJustifyH("RIGHT")

    local setting, pending, fired = false, nil, false
    local function fire()
        fired = false
        if pending == nil then return end
        local v = pending
        pending = nil
        RunCmd(cmd, v)                     -- 与手输 /dg 完全同一条路径
        UI.RefreshAll()
    end
    s:SetScript("OnValueChanged", function(_, v)
        v = floor(tonumber(v) / step + 0.5) * step
        val:SetText(showFn and showFn(v) or tostring(v))
        if setting then return end
        if UI.DrawPreview then pcall(UI.DrawPreview) end   -- 实时预览：读滑条当前值，不等 0.25 秒的合并下发
        pending = v
        if not fired and C_Timer and C_Timer.After then
            fired = true
            C_Timer.After(0.25, fire)
        end
    end)
    row.control = s
    tinsert(UI.widgets, {
        kind = "slider", row = row, s = s, get = getFn, showFn = showFn,
        refresh = function(w)
            local v = w.get() or min
            setting = true
            w.s:SetValue(v)
            setting = false
            val:SetText(w.showFn and w.showFn(v) or tostring(v))
        end,
        flush = fire,                       -- 测试/关窗时把没下发的改动立即下发
    })
    return s
end

-- 3) 单选（一排按钮，当前值高亮）
local function Choice(tabKey, label, options, cmd, getFn, note)
    local row = NewRow(tabKey, note and ROW_NOTE or ROW_H)
    RowLabel(row, label)
    if note then RowNote(row, note) end
    -- 按钮组贴住行的右端（与滑条数值列同一条竖线）：从右往左摆，最后一个贴 RIGHT_PAD
    local btns, ws = {}, {}
    for _, o in ipairs(options) do
        local w = o.w or 70
        local b = MakeButton(row, o.text, w, 20, function()
            RunCmd(cmd, o.value)
            UI.RefreshAll()
        end)
        b.value = o.value
        btns[#btns + 1] = b
        ws[#ws + 1] = w
    end
    local right = -RIGHT_PAD
    for i = #btns, 1, -1 do
        btns[i]:SetPoint("TOPRIGHT", row, "TOPRIGHT", right, -4)
        right = right - ws[i] - 4
    end
    row.btns, row.control = btns, btns[1]
    tinsert(UI.widgets, {
        kind = "choice", row = row, btns = btns, get = getFn,
        refresh = function(w)
            local cur = tostring(w.get())
            for _, b in ipairs(w.btns) do
                local on = (cur == tostring(b.value))
                SetBtnState(b, on)
            end
        end,
    })
    return row
end

-- 4) 动作按钮组
local function ActionRow(tabKey, label, buttons, note)
    local row = NewRow(tabKey, note and ROW_NOTE or ROW_H)
    RowLabel(row, label)
    if note then RowNote(row, note) end
    -- 同样贴右端（与滑条数值列同一条竖线），从右往左摆
    local btns, ws = {}, {}
    for _, b in ipairs(buttons) do
        local w = b.w or 84
        local btn = MakeButton(row, b.text, w, 20, function()
            API.Run(b.cmd)
            UI.RefreshAll()
        end)
        UI.actions[b.cmd] = btn
        if b.text then UI.actions[b.text] = btn end
        btns[#btns + 1] = btn
        ws[#ws + 1] = w
    end
    local right = -RIGHT_PAD
    for i = #btns, 1, -1 do
        btns[i]:SetPoint("TOPRIGHT", row, "TOPRIGHT", right, -4)
        right = right - ws[i] - 4
    end
    row.btns, row.control = btns, btns[1]
    return row
end

-- 5) 颜色块（点开 Blizzard 调色板，带透明度；两条 API 谁在就用谁）
local function ColorRow(tabKey, label, which, rk, gk, bk, ak, note)
    local row = NewRow(tabKey, note and ROW_NOTE or ROW_H)
    RowLabel(row, label)
    if note then RowNote(row, note) end
    local function getC()
        local d = API.DB() or {}
        return d[rk] or 1, d[gk] or 1, d[bk] or 1, d[ak] or 1
    end
    local sw = CreateFrame("Button", nil, row)
    sw:SetSize(44, 20)
    sw:SetPoint("TOPLEFT", row, "TOPLEFT", CTRL_X, -4)
    local r, g, b, a = getC()
    sw.bg = Tex(sw, { r, g, b, a })
    local lbl = Font(row, "small", C.dim)
    lbl:SetPoint("LEFT", sw, "RIGHT", 8, 0)

    local function put(nr, ng, nb, na)
        API.Run(fmt("color %s %02x%02x%02x%02x", which,
            floor((nr or r) * 255 + 0.5), floor((ng or g) * 255 + 0.5),
            floor((nb or b) * 255 + 0.5), floor((na or a) * 255 + 0.5)))
        UI.RefreshAll()
    end
    sw:SetScript("OnClick", function()
        local R, G, B, A = getC()
        local cp = ColorPickerFrame
        if not cp then
            print(P .. L["客户端没有 ColorPickerFrame，颜色请用命令改：/dg color "] .. which .. " rrggbbaa")
            return
        end
        if cp.SetupColorPickerAndShow then
            local ok = pcall(function()
                cp:SetupColorPickerAndShow({
                    r = R, g = G, b = B, opacity = A, hasOpacity = true,
                    swatchFunc  = function()
                        local nr, ng, nb = cp:GetColorRGB()
                        local na = (cp.GetColorAlpha and cp:GetColorAlpha()) or A
                        put(nr, ng, nb, na)
                    end,
                    opacityFunc = function()
                        local nr, ng, nb = cp:GetColorRGB()
                        local na = (cp.GetColorAlpha and cp:GetColorAlpha()) or A
                        put(nr, ng, nb, na)
                    end,
                    cancelFunc  = function(prev)
                        put(prev and prev.r or R, prev and prev.g or G, prev and prev.b or B,
                            (prev and prev.a) or A)
                    end,
                    previousValues = { r = R, g = G, b = B, a = A },
                })
            end)
            if ok then return end
        end
        -- 老式字段（10.0 之前）
        cp.hasOpacity, cp.opacity = true, A
        if cp.SetColorRGB then pcall(cp.SetColorRGB, cp, R, G, B) end
        cp.func = function()
            local nr, ng, nb = cp:GetColorRGB()
            local na = (cp.GetColorAlpha and cp:GetColorAlpha()) or A
            put(nr, ng, nb, na)
        end
        cp.opacityFunc = cp.func
        cp.cancelFunc = function(prev) put(prev and prev.r or R, prev and prev.g or G,
            prev and prev.b or B, (prev and prev.a) or A) end
        if cp.Show then cp:Show() end
    end)

    row.control = sw
    tinsert(UI.widgets, {
        kind = "color", row = row, sw = sw, get = getC, lbl = lbl,
        refresh = function(w)
            local R, G, B, A = w.get()
            w.sw.bg:SetColorTexture(R, G, B, A)
            w.lbl:SetText(fmt(L["#%02x%02x%02x  透明度 %.0f%%"],
                floor(R * 255 + 0.5), floor(G * 255 + 0.5), floor(B * 255 + 0.5), A * 100))
        end,
    })
    return row
end

-- ==== 监控 debuff（spell id 列表编辑器）====================================
local function RemoveSpellAt(idx)
    local l = API.Spells()
    if #l <= 1 then
        if spellHint then spellHint:SetText(L["这里是「逐个删除」：要换法术就先把新的加进来；想全清请用左边的「清空法术（待机）」"]) end
        return
    end
    local ids = {}
    for i = 1, #l do if i ~= idx then ids[#ids + 1] = tostring(l[i]) end end
    API.Run("spell " .. table.concat(ids, ","))
    UI.RefreshAll()
end

local function AddSpellText(text)
    text = tostring(text or "")
    if text == "" then
        if spellHint then spellHint:SetText(L["先输入 spell ID，例如 1943"]) end
        return
    end
    if string.find(text, L["[^%d%s,，、;；]"]) then
        print(P .. L["只支持用 spell ID（数字）定义要监控的 debuff。你输入的是："] .. text:gsub("|", "||"))
        if spellHint then spellHint:SetText(L["只支持 spell ID（数字），多个用逗号或空格分开，例如 1943,703"]) end
        return
    end
    local cur, seen, ids = API.Spells(), {}, {}
    for i = 1, #cur do ids[#ids + 1] = cur[i]; seen[cur[i]] = true end
    local added, dup, full = 0, 0, 0
    for num in string.gmatch(text, "%d+") do
        local n = tonumber(num)
        if n and n > 0 and not seen[n] then
            if #ids >= API.MAX_SPELLS then full = full + 1
            else ids[#ids + 1] = n; seen[n] = true; added = added + 1 end
        elseif n and seen[n] then
            dup = dup + 1
        end
    end
    if added == 0 then
        local msg = L["没识别到新的 spell ID"]
        if full > 0 then msg = fmt(L["最多监控 %d 个法术，先删一个再加"], API.MAX_SPELLS)
        elseif dup > 0 then msg = L["这些法术已经在列表里了"] end
        if spellHint then spellHint:SetText(msg) end
        return
    end
    API.Run("spell " .. table.concat(ids, ","))
    if spellHint then spellHint:SetText(fmt(L["已添加 %d 个（现在共 %d 个）"], added, #ids)) end
    UI.RefreshAll()
end

local function BuildDebuffTab()
    local t = "debuff"
    Section(t, L["要监控的 debuff（只支持 spell ID）"])
    Note(t, L["默认 1943 = 割裂（Rupture）。监控多个时默认「必须全部具备才变红」：每只怪那一格"] ..
        L["按法术自上而下切成横条，第 i 条只由第 i 个法术点红 —— 整格全红 = 全都挂上了，"] ..
        L["只中一部分时能看出差哪一条。"], C.dim)

    local inRow = NewRow(t, 46)
    RowLabel(inRow, L["添加 spell ID（如 1943,703）"])
    spellInput = CreateFrame("EditBox", nil, inRow, BACKDROP_TEMPLATE)
    spellInput:SetSize(250, 24)
    spellInput:SetPoint("TOPLEFT", inRow, "TOPLEFT", CTRL_X, -4)
    spellInput.bg = Tex(spellInput, C.body)
    local inBorder = spellInput:CreateTexture(nil, "BORDER")     -- 自绘 1px 描边（最初的样子）
    inBorder:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    inBorder:SetPoint("TOPLEFT", spellInput, "TOPLEFT", -1, 1)
    inBorder:SetPoint("BOTTOMRIGHT", spellInput, "BOTTOMRIGHT", 1, -1)
    if spellInput.SetAutoFocus then pcall(spellInput.SetAutoFocus, spellInput, false) end
    if spellInput.SetTextInsets then pcall(spellInput.SetTextInsets, spellInput, 6, 6, 0, 0) end
    if spellInput.SetMaxLetters then pcall(spellInput.SetMaxLetters, spellInput, 60) end
    if spellInput.SetFontObject and GameFontHighlight then
        pcall(spellInput.SetFontObject, spellInput, GameFontHighlight)
    end
    spellInput:SetScript("OnEnterPressed", function(self)
        local v = (self.GetText and self.GetText(self)) or ""
        AddSpellText(v)
        if self.SetText then self:SetText("") end
        if self.ClearFocus then self:ClearFocus() end
    end)
    spellInput:SetScript("OnEscapePressed", function(self)
        if self.ClearFocus then self:ClearFocus() end
    end)
    local addBtn = MakeButton(inRow, L["添加"], 52, 22, function()
        local v = (spellInput.GetText and spellInput.GetText(spellInput)) or ""
        AddSpellText(v)
        if spellInput.SetText then spellInput:SetText("") end
    end)
    addBtn:SetPoint("TOPRIGHT", inRow, "TOPRIGHT", -RIGHT_PAD - 116 - 4, -4)   -- 贴右端（在「恢复默认」左边）
    local defBtn = MakeButton(inRow, L["清空法术（待机）"], 116, 22, function()
        API.Run("spell clear")
        if spellHint then spellHint:SetText(L["已清空监控列表：插件进入待机，直到重新添加法术"]) end
        UI.RefreshAll()
    end)
    UI.actions["spell_clear"] = defBtn
    UI.actions["spell_add"] = addBtn
    defBtn:SetPoint("TOPRIGHT", inRow, "TOPRIGHT", -RIGHT_PAD, -4)
    inRow.btns = { addBtn, defBtn }        -- 这一行也纳入L["按钮贴右端"]的自查

    local hintRow = NewRow(t, 28)
    spellHint = Font(hintRow, "small", C.dim)
    spellHint:SetPoint("LEFT", 12, 0)
    spellHint:SetText("")

    spellPanel = NewRow(t, 26)
    for i = 1, MAX_SPELLS_UI do
        local r = CreateFrame("Frame", nil, spellPanel)
        r:SetHeight(26)
        r:SetPoint("TOPLEFT", spellPanel, "TOPLEFT", 0, -(i - 1) * 26)
        r:SetPoint("RIGHT", spellPanel, "RIGHT", 0, 0)
        r.bg = Tex(r, C.row)
        r.txt = Font(r, "small", C.text)
        r.txt:SetPoint("LEFT", 12, 0)
        local idx = i
        r.del = MakeButton(r, L["删除"], 52, 18, function() RemoveSpellAt(idx) end, C.del)
        r.del:SetPoint("RIGHT", r, "RIGHT", -4, 0)
        r:Hide()
        UI.spellRows[i] = r
    end

    Choice(t, L["多个 debuff 的判据"], {
        { text = L["全部具备才红"], value = "all", w = 108 },
        { text = L["任一个就红"],   value = "any", w = 88 },
    }, "spells %s", function() return API.DB() and API.DB().spellMode or "all" end,
        L["all（默认）= 分格：整格全红才算全中；any = 旧行为，看不出中的是哪一个"])
end

-- ==== 各标签页 =============================================================
local TAB_LIST = {
    { key = "general", text = L["常规"] },
    { key = "debuff",  text = L["监控 debuff"] },
    { key = "bar",     text = L["进度条"] },
    { key = "grid",    text = L["格子"] },
    { key = "color",   text = L["颜色"] },
    { key = "range",   text = L["范围/口径"] },
    { key = "profile",  text = L["配置档"] },
    { key = "tools",   text = L["工具/诊断"] },
}

-- 命令行命令 -> 界面在哪儿改（离线测试拿它跟 /dg help 对表，保证界面覆盖所有命令）
UI.coverage = {
    help    = L["「工具/诊断」页：打印命令帮助按钮"],
    config  = L["本窗口（/dg 空参数 = 开关窗口）"],
    on      = L["「常规」页：启用 DotGrid 开关"],
    off     = L["「常规」页：启用 DotGrid 开关"],
    spell   = L["「监控 debuff」页：添加 spell ID / 删除 / 清空（清空后插件待机）"],
    spells  = L["「监控 debuff」页：全部具备才红 / 任一个就红 单选"],
    tier    = L["「范围/口径」页：档位兜底（关 / 8码 / 7码）"],
    yards   = L["「范围/口径」页：精确码数上限滑条"],
    engaged = L["「范围/口径」页：只算哪些怪（已进战斗 / 跟我打 / 全算）"],
    combat  = L["「常规」页：只在你自己战斗中显示开关"],
    size    = L["「格子」页：方块宽 / 方块高两个滑条（合并下发 size 宽x高）"],
    perrow  = L["「格子」页：每行方块数滑条"],
    gap     = L["「格子」页：方块间距滑条"],
    bar     = L["「进度条」页：每段宽 / 条高 / 段间距 / 最少只数 / 刻度线"],
    mode    = L["「常规」页：显示方式（进度条 / 格子）"],
    style   = L["「常规」页：外观（纯色块 / 经典面板风 / 原生名字板风）"],
    pos     = L["「常规」页：位置 X / Y 滑条 + 移到屏幕中央按钮（拖动 = 解锁后直接拖黄框）"],
    color   = L["「颜色」页：命中 / 有怪（打底）/ 底槽 / 格子 四个色块（带透明度）"],
    alpha   = L["「颜色」页：命中 / 有怪 / 格子 / 底槽 四条透明度滑条（0–100%）"],
    colour  = L["「颜色」页：同上（colour 是别名）"],
    lock    = L["「常规」页：锁定按钮"],
    unlock  = L["「常规」页：解锁拖动按钮"],
    verify  = L["「工具/诊断」页：真值核验按钮"],
    diag    = L["「工具/诊断」页：环境自检按钮"],
    status  = L["「工具/诊断」页：环境自检按钮（status 是别名）"],
    debug   = L["「工具/诊断」页：调试输出开关"],
    profile = L["「配置档」页：当前档 / 保存到本档 / 新建 / 加载 / 删除 / 档列表"],
    profiles = L["同上（profiles 是别名）"],
    char    = L["同上（char 是 profile 的旧别名）"],
    reset   = L["「工具/诊断」页：恢复出厂（只清当前配置档）"],
}

-- ==== 实时预览 =============================================================
-- 拖滑条时把"当前设置看起来是什么样"立刻画出来 —— 窗口往往挡着显示区，野外也不一定有怪，
-- 所以预览必须自己画。滑条读的是**滑条当前值**（不是 DB），所以拖动过程中就是实时的。
local PV_W, PV_H = 700, 64                 -- 画布尺寸
local PV_N, PV_HIT = 6, 2                  -- 示意：6 只怪，其中 2 只命中（只为看形态）

local function PvVal(label, fallback)      -- 滑条当前值优先（拖动中还没下发也有值）
    local w = UI.byLabel and UI.byLabel[label]
    if w and w.s and w.s.GetValue then
        local ok, v = pcall(w.s.GetValue, w.s)
        if ok and type(v) == "number" then return v end
    end
    return fallback
end

local function PvInit(pv)
    if pv.ready then return end
    pv.ready = true
    pv.outline = pv:CreateTexture(nil, "BACKGROUND")
    pv.trough  = pv:CreateTexture(nil, "BORDER")
    pv.segs, pv.ticks, pv.reds = {}, {}, {}
    for i = 1, PV_N do
        pv.segs[i]  = pv:CreateTexture(nil, "ARTWORK")
        pv.ticks[i] = pv:CreateTexture(nil, "ARTWORK")
        pv.reds[i]  = pv:CreateTexture(nil, "OVERLAY")
    end
end

local function PvHideAll(pv)
    local all = { pv.outline, pv.trough }
    for i = 1, PV_N do all[#all + 1] = pv.segs[i]; all[#all + 1] = pv.ticks[i]; all[#all + 1] = pv.reds[i] end
    for _, t in ipairs(all) do if t then t:Hide() end end
end

local function PvRect(pv, t, x, y, w, h, r, g, b, a, native)
    t:ClearAllPoints()
    -- native 参数现在是"本档要用的贴图文件"（nil = 纯色档）；用文件本身当缓存键，
    -- 用贴图文件名做缓存键，这样 panel ↔ nameplate 互切时也会重新换图
    if native and t.pvNative ~= native then
        if pcall(t.SetTexture, t, native) then t.pvNative = native end
    elseif not native and t.pvNative then
        if pcall(t.SetTexture, t, "Interface\\Buttons\\WHITE8X8") then t.pvNative = nil end
    end
    if t.pvNative then
        -- 面板风：游戏自带条纹理 + 顶点色（与真显示完全同一条染色路径）
        t:SetVertexColor(r, g, b, a or 1)
        t:SetSize(math.max(0.1, w), math.max(0.1, h))
        t:SetPoint("TOPLEFT", pv, "TOPLEFT", x, y)
        t:Show()
        return
    end
    t:SetColorTexture(r, g, b, a or 1)
    t:SetSize(math.max(0.1, w), math.max(0.1, h))
    t:SetPoint("TOPLEFT", pv, "TOPLEFT", x, y)
    t:Show()
end

function UI.DrawPreview()
    local list = UI.previewRows
    if not list or #list == 0 then return false end
    local d = API.DB() or {}
    local mode = d.mode or "bar"
    -- 带框的外观档：预览也用同一张游戏自带纹理（与真显示同一条路径）
    local pvNat = ((d.style or "solid") == "panel") and ART.barFill
        or ((d.style or "solid") == "nameplate") and ART.npFill or nil
    -- 透明度：优先取滑条当前值（拖动过程中就实时），滑条不存在时退回存档值
    local function ClampA(p) return math.max(0, math.min(1, (p or 0) / 100)) end
    local aHit  = ClampA(PvVal(L["命中 透明度"], (d.hitA or 1) * 100))
    local aMob  = ClampA(PvVal(L["有怪 透明度"], (d.mobA or 1) * 100))
    local aMiss = ClampA(PvVal(L["格子 透明度"], (d.missA or 1) * 100))
    local aTr   = ClampA(PvVal(L["底槽 透明度"], (d.emptyA or 0.18) * 100))
    for _, row in ipairs(list) do
        local pv = row.pv
        if pv then
            PvInit(pv)
            PvHideAll(pv)
            local txt, dim = nil, 1
            if mode == "bar" then
                local segW = math.max(6, math.min(60, floor(PvVal(L["每段宽度"], d.barSegW or 21))))
                local bh   = math.max(6, math.min(80, floor(PvVal(L["条高"], d.barH or 20))))
                local gapW = math.max(0, math.min(10, floor(PvVal(L["段间距"], d.barGap or 1))))
                local mn   = math.max(0, math.min(10, floor(PvVal(L["少于几只不显示"], d.barMin or 2))))
                local total = PV_N * (segW + gapW) - gapW
                if PV_N < mn then dim = 0.22 end       -- 按当前设置整条不显示 ⇒ 画淡示意
                PvRect(pv, pv.outline, 11, -11, total + 2, bh + 2, 0, 0, 0, 0.55 * dim)
                PvRect(pv, pv.trough, 12, -12, total, bh,
                    d.emptyR or 1, d.emptyG or 1, d.emptyB or 1, aTr * dim, pvNat)
                for i = 1, PV_N do
                    local x = 12 + (i - 1) * (segW + gapW)
                    PvRect(pv, pv.segs[i], x, -12, segW, bh,
                        d.mobR or 1, d.mobG or 1, d.mobB or 1, aMob * dim, pvNat)
                    if i <= PV_HIT then
                        PvRect(pv, pv.reds[i], x, -12, segW, bh,
                            d.hitR or 0.85, d.hitG or 0.06, d.hitB or 0.06, aHit * dim, pvNat)
                    end
                end
                if d.barTicks ~= false then
                    for i = 1, PV_N - 1 do
                        PvRect(pv, pv.ticks[i], 12 + i * (segW + gapW) - gapW, -12, math.max(1, gapW), bh,
                            0, 0, 0, 0.6 * dim)
                    end
                end
                txt = fmt(L["说明：进度条预览 · 示意 %d 只怪（其中 %d 只命中）⇒ 每段 %.0f + 缝 %.0f，总长 %.0f 像素，高 %.0f；"] ..
                    L["少于 %.0f 只不显示 ⇒ %s｜不透明度 命中 %.0f%% / 有怪 %.0f%% / 底槽 %.0f%%"],
                    PV_N, PV_HIT, segW, gapW, total, bh, mn,
                    (PV_N < mn) and L["按当前设置整条不会显示（预览已画淡）"] or L["会显示"],
                    aHit * 100, aMob * 100, aTr * 100)
            else
                local cw = math.max(4, math.min(80, floor(PvVal(L["方块宽"], d.cellW or 18))))
                local ch = math.max(4, math.min(80, floor(PvVal(L["方块高"], d.cellH or 18))))
                local g  = math.max(0, math.min(40, floor(PvVal(L["方块间距"], d.gap or 4))))
                local pr = math.max(1, math.min(20, floor(PvVal(L["每行方块数"], d.perRow or 5))))
                local cols = math.min(pr, PV_N)
                local rows = math.ceil(PV_N / pr)
                for i = 1, PV_N do
                    local col, rw = (i - 1) % pr, floor((i - 1) / pr)
                    local x, y = 12 + col * (cw + g), -12 - rw * (ch + g)
                    PvRect(pv, pv.segs[i], x, y, cw, ch,
                        d.missR or 1, d.missG or 1, d.missB or 1, aMiss * dim, pvNat)
                    if i <= PV_HIT then
                        PvRect(pv, pv.reds[i], x, y, cw, ch,
                            d.hitR or 0.85, d.hitG or 0.06, d.hitB or 0.06, aHit * dim, pvNat)
                    end
                end
                txt = fmt(L["说明：格子预览 · 示意 %d 只怪（其中 %d 只命中）⇒ 方块 %.0f×%.0f，间距 %.0f，每行 %.0f ⇒ %d 行，"] ..
                    L["整体 %.0f×%.0f 像素｜不透明度 命中 %.0f%% / 格子 %.0f%%"], PV_N, PV_HIT, cw, ch, g, pr, rows,
                    cols * cw + (cols - 1) * g, rows * ch + (rows - 1) * g, aHit * 100, aMiss * 100)
            end
            if row.note then row.note:SetText(txt) end
        end
    end
    return true
end

-- 预览行：一行 = 标题 + 画布 + 读数（高度由 Layout 按读数真实高度自动撑开）
local PV_TOP, PV_TXT = -30, -(30 + PV_H + 6)
local function PreviewRow(tabKey)
    local row = NewRow(tabKey, ROW_H)
    RowLabel(row, L["预览：拖动滑条时这里实时跟着变"])
    local pv = CreateFrame("Frame", nil, row, BACKDROP_TEMPLATE)
    pv:SetPoint("TOPLEFT", row, "TOPLEFT", 12, PV_TOP)
    pv:SetSize(PV_W, PV_H)
    pv.bg = Tex(pv, C.body)                -- 画布底色（必须有基底，否则画布会是空的）
    NativePanel(pv, C.body)                -- 画布也用游戏自带面板（失败就保持自绘底）
    if pv.SetClipsChildren then pcall(pv.SetClipsChildren, pv, true) end
    local txt = Font(row, "small", C.dim)
    txt:SetPoint("TOPLEFT", row, "TOPLEFT", 12, PV_TXT)
    txt:SetPoint("RIGHT", row, "RIGHT", -12, 0)
    if txt.SetWordWrap then pcall(txt.SetWordWrap, txt, true) end
    row.note, row.noteTop = txt, PV_TXT
    -- 建行时就把高度定死（画布 64 + 读数 + 余量）：否则桩里 GetStringHeight 缺失会被低估，
    -- Layout 会自动撑高，两边算出的页面高度不一致时底部控件会被挤出可视区
    row.h = math.max(row.h, (-PV_TXT) + 14 + 8)
    row.pv = pv
    UI.previewRows[#UI.previewRows + 1] = row
    return row
end

local function BuildGeneral()
    local t = "general"
    Section(t, L["显示"])
    Toggle(t, L["启用 DotGrid"], "on", "off", function() return API.DB() and API.DB().enabled end,
        L["关掉后整块不显示、也不建任何容器（等同 /dg off）"])
    Choice(t, L["显示方式"], {
        { text = L["进度条"], value = "bar",  w = 74 },
        { text = L["格子"],   value = "grid", w = 62 },
    }, "mode %s", function() return API.DB() and API.DB().mode end,
        L["进度条（默认）= 几只怪几段、总长随怪数变；格子 = 每只怪一个方块"])
    Choice(t, L["外观"], {
        { text = L["纯色块"],     value = "solid",     w = 74 },
        { text = L["经典面板风"], value = "panel",     w = 92 },
        { text = L["原生名字板"], value = "nameplate", w = 92 },
    }, "style %s", function() return API.DB() and API.DB().style or "solid" end,
        L["纯色块（默认）= 全部自绘；经典面板风 = 游戏自带的提示框面板 + 条纹理；原生名字板风 = 名字板金边 + 名字板血条纹理（等同 /dg style）"])
    PreviewRow(t)
    Toggle(t, L["只在你自己战斗中显示"], "combat on", "combat off",
        function() return API.DB() and API.DB().combatOnly end,
        L["脱战自动收起（等同 /dg combat on|off）"])

    Section(t, L["位置与拖动"])
    ActionRow(t, L["屏幕上的锚点"], {
        { text = L["解锁拖动"], cmd = "unlock", w = 88 },
        { text = L["锁定"],     cmd = "lock",   w = 62 },
    }, L["解锁后整块显示区变成黄框，直接用鼠标拖它（等同 /dg unlock、/dg lock）"])
    Slider(t, L["位置 X"], 0, 3840, 10,
        function(v) return fmt("pos %d %d", v, math.floor((API.DB() and API.DB().y) or 0)) end,
        function() return API.DB() and API.DB().x end,
        function(v) return tostring(v) end,
        L["相对屏幕左下角；和下面的 Y 一起下发 /dg pos x y（也可以直接拖，拖完自动存这里）"])
    Slider(t, L["位置 Y"], 0, 2160, 10,
        function(v) return fmt("pos %d %d", math.floor((API.DB() and API.DB().x) or 0), v) end,
        function() return API.DB() and API.DB().y end,
        function(v) return tostring(v) end, nil)
    ActionRow(t, L["回默认位置"], {
        { text = L["移到屏幕中央"], cmd = "pos center", w = 108 },
    }, L["等同 /dg pos center：回到屏幕中左（坐标会写进存档）"])
    Note(t, L["本窗口自己也能拖：按住标题栏拖，位置记在 DotGridDB.uiX / uiY；Esc 关闭。"], C.dim)
end

local function BuildBarTab()
    local t = "bar"
    Section(t, L["进度条 · 紧凑模式（几只怪几段，总长随怪数变）"])
    PreviewRow(t)
    Slider(t, L["每段宽度"], 6, 60, 1, "bar segw %d", function() return API.DB() and API.DB().barSegW end,
        function(v) return v .. L[" 像素"] end,
        L["每只怪占一段；总长 = 怪数 × (段宽 + 缝) - 缝。例：3 只 = 3×22-1 = 65 像素"])
    Slider(t, L["条高"], 6, 80, 1, "bar height %d", function() return API.DB() and API.DB().barH end,
        function(v) return v .. L[" 像素"] end, L["改完立即重建红段，不用 /reload"])
    Slider(t, L["段间距"], 0, 10, 1, "bar gap %d", function() return API.DB() and API.DB().barGap end,
        function(v) return v .. L[" 像素"] end, nil)
    Slider(t, L["少于几只不显示"], 0, 10, 1, "bar min %d", function() return API.DB() and API.DB().barMin end,
        function(v) return v <= 1 and (v .. L[" 只（1 = 一只也显示）"]) or (v .. L[" 只"]) end,
        L["默认 2：只有 1 只怪时整条（连红块）都不显示 —— 单只没有比例可看"])
    Toggle(t, L["段间刻度线"], "bar ticks on", "bar ticks off",
        function() return API.DB() and API.DB().barTicks end,
        L["每段之间那条 1px 深色竖线，用来数段"])

end

local function BuildGridTab()
    local t = "grid"
    Section(t, L["格子（每只怪一个方块）"])
    PreviewRow(t)
    Slider(t, L["方块宽"], 6, 80, 1,
        function(v) return fmt("size %dx%d", v, (API.DB() and API.DB().cellH) or 18) end,
        function() return API.DB() and API.DB().cellW end,
        function(v) return v .. L[" 像素"] end, L["宽和高是两个滑条，实际下发的是 /dg size 宽x高"])
    Slider(t, L["方块高"], 6, 80, 1,
        function(v) return fmt("size %dx%d", (API.DB() and API.DB().cellW) or 18, v) end,
        function() return API.DB() and API.DB().cellH end,
        function(v) return v .. L[" 像素"] end, nil)
    Slider(t, L["每行方块数"], 1, 20, 1, "perrow %d", function() return API.DB() and API.DB().perRow end,
        function(v) return v .. L[" 个"] end, nil)
    Slider(t, L["方块间距"], 0, 20, 1, "gap %d", function() return API.DB() and API.DB().gap end,
        function(v) return v .. L[" 像素"] end, nil)
end

local function BuildColorTab()
    local t = "color"
    Section(t, L["颜色（点色块开调色板，带透明度滑条）"])
    PreviewRow(t)
    Section(t, L["透明度（只改透明、保留颜色；拖动时预览实时跟着变）"])
    Slider(t, L["命中 透明度"], 0, 100, 1, "alpha hit %d",
        function() return API.DB() and (API.DB().hitA or 1) * 100 end,
        function(v) return floor(v) .. "%" end,
        L["有我的 debuff 的那部分；0 = 完全透明（看不见红），100 = 不透明"])
    Slider(t, L["有怪 透明度"], 0, 100, 1, "alpha mob %d",
        function() return API.DB() and (API.DB().mobA or 1) * 100 end,
        function(v) return floor(v) .. "%" end,
        L["进度条里「有怪、但没我的 debuff」的那一段（默认纯白 100%）"])
    Slider(t, L["格子 透明度"], 0, 100, 1, "alpha miss %d",
        function() return API.DB() and (API.DB().missA or 1) * 100 end,
        function(v) return floor(v) .. "%" end,
        L["格子模式里「有怪、但没我的 debuff」的方块（默认纯白 100%）"])
    Slider(t, L["底槽 透明度"], 0, 100, 1, "alpha empty %d",
        function() return API.DB() and (API.DB().emptyA or 0.18) * 100 end,
        function(v) return floor(v) .. "%" end,
        L["整条的量程底色（默认 18%）；它必须比「有怪」暗，否则空段和有怪段分不清"])
    ColorRow(t, L["命中 / 红"], "hit", "hitR", "hitG", "hitB", "hitA",
        L["有我的 debuff 的那部分（红段 / 红扇区 / 红格）"])
    ColorRow(t, L["有怪（打底）"], "mob", "mobR", "mobG", "mobB", "mobA",
        L["范围内有怪、但没我的 debuff 的段/扇区 —— 默认纯白 100%，最显眼"])
    ColorRow(t, L["底槽 / 空槽位"], "empty", "emptyR", "emptyG", "emptyB", "emptyA",
        L["整条的量程底色，默认白 18%（要比「有怪」暗，否则固定模式下空段和有怪段分不清）"])
    ColorRow(t, L["格子模式（有怪无 DoT）"], "miss", "missR", "missG", "missB", "missA",
        L["格子模式下「有怪但没我的 DoT」的颜色，默认纯白 100%"])
    Note(t, L["条最外圈那道 1px 深色描边是固定的（任何背景都看得见边界）；段间刻度线固定黑 60%。"] ..
        L["这两样不可改。"], C.dim)
end

local function BuildRangeTab()
    local t = "range"
    Section(t, L["统计范围"])
    Choice(t, L["只算哪些怪"], {
        { text = L["已进战斗"], value = "combat", w = 84 },
        { text = L["跟我打"],   value = "threat", w = 74 },
        { text = L["全算"],     value = "all",    w = 62 },
    }, "engaged %s", function() return API.DB() and API.DB().engaged end,
        L["combat（默认）= 已进入战斗的怪；threat = 只算我仇恨列表里的（最严）；all = 范围内全算"])
    Note(t, L["客户端没有「11 码」这一档距离：下面两套判据同时开着时取更严的那个。"], C.warn)

    Section(t, L["距离"])
    Slider(t, L["精确码数上限"], 0, 40, 1, "yards %d", function() return API.DB() and API.DB().maxYards end,
        function(v) return v <= 0 and L["关（只靠档位）"] or (v .. L[" 码"]) end,
        L["用 UnitDistanceSquared 量真实码数（野外可用；副本/战场内客户端只给受限值，"] ..
        L["那时自动退回下面的档位）。默认 11 码"])
    Choice(t, L["档位兜底"], {
        { text = L["关"],  value = 0, w = 48 },
        { text = L["8码"], value = 2, w = 54 },
        { text = L["7码"], value = 3, w = 54 },
    }, "tier %d", function() return API.DB() and API.DB().tier end,
        L["CheckInteractDistance 只有这几档（没有 11 码档）。默认 8 码；与上面的码数取更严"])
end

-- ==== 配置档页 =============================================================
local function MakeInput(row, x)
    local eb = CreateFrame("EditBox", nil, row, BACKDROP_TEMPLATE)
    eb:SetSize(250, 24)
    eb:SetPoint("TOPLEFT", row, "TOPLEFT", x, -4)
    eb.bg = Tex(eb, C.body)
    local bd = eb:CreateTexture(nil, "BORDER")            -- 自绘 1px 描边（最初的样子）
    bd:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    bd:SetPoint("TOPLEFT", eb, "TOPLEFT", -1, 1)
    bd:SetPoint("BOTTOMRIGHT", eb, "BOTTOMRIGHT", 1, -1)
    if eb.SetAutoFocus then pcall(eb.SetAutoFocus, eb, false) end
    if eb.SetTextInsets then pcall(eb.SetTextInsets, eb, 6, 6, 0, 0) end
    if eb.SetMaxLetters then pcall(eb.SetMaxLetters, eb, 40) end
    if eb.SetFontObject and GameFontHighlight then pcall(eb.SetFontObject, eb, GameFontHighlight) end
    eb:SetScript("OnEscapePressed", function(self) if self.ClearFocus then self:ClearFocus() end end)
    return eb
end

-- mode: "auto"（回车：有就加载、没有就新建）| "new"（强制新建）| "load"（只加载）
local function ProfGo(mode)
    if not profInput then return end
    local v = (profInput.GetText and profInput.GetText(profInput)) or ""
    v = string.gsub(tostring(v), "^%s*(.-)%s*$", "%1")
    if v == "" then return end
    local names = API.Profiles and API.Profiles() or {}
    local exists = false
    if type(names) == "table" then
        for _, n in ipairs(names) do if n == v then exists = true; break end end
    end
    if mode == "new" then
        API.Run("profile new " .. v)
    elseif mode == "load" then
        API.Run("profile load " .. v)
    else
        API.Run(exists and ("profile load " .. v) or ("profile new " .. v))
    end
    if profInput.SetText then profInput:SetText("") end
    if profInput.ClearFocus then profInput:ClearFocus() end
    UI.RefreshAll()
end

local function RefreshProfiles()
    if not profNameText then return end
    local names, cur = nil, nil
    if API.Profiles then names, cur = API.Profiles() end
    names = (type(names) == "table") and names or {}
    cur = cur or "默认"
    profNameText:SetText(tostring(cur))
    for i = 1, PROFILE_MAX_UI do
        local b = profList[i]
        if b then
            local name = names[i]
            if name then
                b.profileName = name
                if b.txt then
                    b.txt:SetText((name == cur) and (name .. L["   ← 本角色在用"]) or name)
                end
                SetBtnState(b, name == cur)
                b:Show()
            else
                b.profileName = nil
                b:Hide()
            end
        end
    end
end
UI.RefreshProfiles = RefreshProfiles

local function BuildProfileTab()
    local t = "profile"
    Section(t, L["配置档（每个角色各用一套；档存在账号里，可以互相加载）"])
    Note(t, L["档里存的是整套设置。默认所有角色都用「默认」档 —— 给某个角色换档只影响它自己。"] ..
        L["「新建」= 用当前设置做一份快照并切过去；「保存到本档」= 把当前设置写回当前档。"] ..
        L["改完设置如果不保存，改变只存在这一次会话里（改一次就会进当前档，保存=确认整份）。"], C.dim)

    local r1 = NewRow(t, 40)
    RowLabel(r1, L["当前档"])
    profNameText = Font(r1, "normal", C.accent)
    profNameText:SetPoint("TOPLEFT", r1, "TOPLEFT", CTRL_X, -8)
    local saveB = MakeButton(r1, L["保存到本档"], 100, 22, function()
        API.Run("profile save"); UI.RefreshAll()
    end)
    saveB:SetPoint("TOPRIGHT", r1, "TOPRIGHT", -RIGHT_PAD, -4)
    UI.actions["profile save"] = saveB
    local delB = MakeButton(r1, L["删除本档"], 88, 22, function()
        local n = profNameText and profNameText.text or ""
        API.Run("profile delete " .. tostring(n)); UI.RefreshAll()
    end)
    delB:SetPoint("TOPRIGHT", r1, "TOPRIGHT", -RIGHT_PAD - 104, -4)
    UI.actions["profile delete"] = delB

    local r2 = NewRow(t, 46)
    RowLabel(r2, L["新建 / 加载（输入档名后回车）"])
    profInput = MakeInput(r2, CTRL_X)
    profInput:SetScript("OnEnterPressed", function(self) ProfGo("auto") end)
    local newB = MakeButton(r2, L["新建"], 60, 22, function() ProfGo("new") end)
    newB:SetPoint("TOPRIGHT", r2, "TOPRIGHT", -RIGHT_PAD - 64, -4)
    UI.actions["profile new"] = newB
    local loadB = MakeButton(r2, L["加载"], 60, 22, function() ProfGo("load") end)
    loadB:SetPoint("TOPRIGHT", r2, "TOPRIGHT", -RIGHT_PAD, -4)
    UI.actions["profile load"] = loadB

    local rl = NewRow(t, 124)
    RowLabel(rl, L["所有档（点一下 = 本角色加载它）"])
    profList = {}
    for i = 1, PROFILE_MAX_UI do
        local col = (i - 1) % 3
        local rowIdx = math.floor((i - 1) / 3)
        local b = MakeButton(rl, "-", 150, 20, function()
            if not b.profileName then return end
            API.Run("profile load " .. b.profileName)
            UI.RefreshAll()
        end)
        b:SetPoint("TOPLEFT", rl, "TOPLEFT", CTRL_X + col * 158, -26 - rowIdx * 24)
        b:Hide()
        UI.actions["profile_list_" .. i] = b
        profList[i] = b
    end
    Note(t, L["档名可以带空格（整行都是名字）。删掉别人正在用的档时，那些角色会自动退回「默认」档。"], C.dim)
end

local function BuildToolsTab()
    local t = "tools"
    Section(t, L["一键工具"])
    ActionRow(t, L["自检 / 核验"], {
        { text = L["环境自检 diag"],   cmd = "diag",   w = 118 },
        { text = L["真值核验 verify"], cmd = "verify", w = 118 },
    }, L["verify 要在脱战时用：脱战时光环对插件可读，它逐只打印每个法术有/无，可与红标记对照"])
    ActionRow(t, L["恢复 / 帮助"], {
        { text = L["恢复默认"],     cmd = "reset", w = 84 },
        { text = L["打印命令帮助"], cmd = "help",  w = 108 },
    }, L["恢复默认 = 当前档回出厂值（法术也会被清空 ⇒ 插件待机）；其它档不动"])
    ActionRow(t, L["多角色（同账号）"], {
        { text = L["本角色覆盖"],   cmd = "char",       w = 104 },
        { text = L["按职业填 DoT"], cmd = "char spells", w = 112 },
        { text = L["清空覆盖"],     cmd = "char clear",  w = 96 },
    }, L["存档是账号级的：默认所有角色一致；想让某个角色单独一套（比如不同职业的 DoT 不同），"] ..
       L["用「本角色覆盖」看、用 /dg char keep pos 这类命令把想分开的项存到本角色"])
    Toggle(t, L["调试输出"], "debug on", "debug off", function() return API.DB() and API.DB().debug end,
        L["在聊天框打印每次刷新的 [DBG] 详情（排查用，平时关掉）"])

    Section(t, L["说明"])
    Note(t, L["数量数字已按需求取消：进度条上有几段就是几只怪，格子亮几个就是几只。"] ..
        L["想看具体数字（计数、逐只坐标）用 /dg diag。"], C.dim)
    Note(t, L["战斗中改「监控的法术 / 过滤器」这类设置，客户端可能要到脱战后才真正生效 —— "] ..
        L["这是 12.1 光环隐秘期的限制，不是本插件的问题。"], C.warn)
    Note(t, L["界面里每个控件都等价于一条 /dg 命令（会在聊天框照原样回显）。"] ..
        L["窗口位置记在 DotGridDB.uiX / uiY；Esc 关闭窗口。"], C.dim)
end

-- ==== 窗口 =================================================================
local function EnsureFrame()
    if frame then return frame end

    frame = CreateFrame("Frame", "DotGridOptionsFrame", UIParent, BACKDROP_TEMPLATE)
    frame:SetSize(WIN_W, WIN_H)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local d = API.DB()
        if d then d.uiX, d.uiY = self:GetLeft(), self:GetTop() end
    end)
    frame.bg = Tex(frame, C.win)
    local border = frame:CreateTexture(nil, "BORDER")
    border:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    border:SetPoint("TOPLEFT", frame, "TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 1, -1)
    NativePanel(frame, C.win)     -- 原始风格：窗口也自绘，上面那圈 1px 描边照常显示
    frame:Hide()

    -- 标题栏
    local head = CreateFrame("Frame", nil, frame, BACKDROP_TEMPLATE)
    head:SetHeight(HEAD_H)
    head:SetPoint("TOPLEFT", WIN_IN_L, -WIN_IN_T)
    head:SetPoint("TOPRIGHT", -WIN_IN_R, -WIN_IN_T)
    Tex(head, C.head)
    NativePanel(head, C.head)
    local title = Font(head, "normal", C.text)
    title:SetPoint("LEFT", 10, 0)
    title:SetText(L["DotGrid 设置"])
    local ver = Font(head, "small", C.dim)
    ver:SetPoint("LEFT", 116, 0)
    ver:SetText("v" .. tostring(API.GetVersion()))
    local close = MakeButton(head, "×", 24, 20, function() UI.Close() end, C.del)
    close:SetPoint("RIGHT", head, "RIGHT", -6, 0)
    frame.closeBtn = close

    -- 左侧标签
    sidePanel = CreateFrame("Frame", nil, frame, BACKDROP_TEMPLATE)
    sidePanel:SetPoint("TOPLEFT", WIN_IN_L, -WIN_IN_T - HEAD_H)
    sidePanel:SetPoint("BOTTOMLEFT", WIN_IN_L, WIN_IN_B + 22)
    sidePanel:SetWidth(SIDE_W)
    Tex(sidePanel, C.side)
    NativePanel(sidePanel, C.side)
    UI.tabButtons = {}
    for i, tb in ipairs(TAB_LIST) do
        local b = MakeButton(sidePanel, tb.text, SIDE_W - 16, 28, function() UI.ShowTab(tb.key) end)
        b:SetPoint("TOPLEFT", sidePanel, "TOPLEFT", 8, -10 - (i - 1) * 36)
        b.tabKey = tb.key
        UI.tabButtons[#UI.tabButtons + 1] = b
    end

    -- 内容区（自绘滚动：滚轮上下移）
    viewport = CreateFrame("Frame", nil, frame, BACKDROP_TEMPLATE)
    viewport:SetPoint("TOPLEFT", WIN_IN_L + SIDE_W + 8, -WIN_IN_T - HEAD_H - 8)
    viewport:SetPoint("BOTTOMRIGHT", -(WIN_IN_R + 8), WIN_IN_B + 26)
    Tex(viewport, C.body)
    NativePanel(viewport, C.body)
    viewport:EnableMouseWheel(true)
    viewport:SetScript("OnMouseWheel", function(_, delta)
        local maxScroll = math.max(0, (content and content:GetHeight() or 0) - viewport:GetHeight())
        SetScroll(math.max(0, math.min(maxScroll, (UI.scroll or 0) - delta * 26)))
    end)
    UI.viewport = viewport

    content = CreateFrame("Frame", nil, viewport)
    content:SetPoint("TOPLEFT", viewport, "TOPLEFT", 0, 0)
    content:SetPoint("TOPRIGHT", viewport, "TOPRIGHT", 0, 0)
    content:SetHeight(10)
    UI.content = content

    -- 底部状态栏
    local foot = CreateFrame("Frame", nil, frame, BACKDROP_TEMPLATE)
    foot:SetPoint("BOTTOMLEFT", WIN_IN_L, WIN_IN_B)
    foot:SetPoint("BOTTOMRIGHT", -WIN_IN_R, WIN_IN_B)
    foot:SetHeight(22)
    Tex(foot, C.head)
    NativePanel(foot, C.head)
    statusText = Font(foot, "small", C.dim)
    statusText:SetPoint("LEFT", 10, 0)
    statusText:SetText(L["界面上每一处改动都等价于一条 /dg 命令 · 拖标题栏移动窗口 · Esc 关闭"])

    -- Esc 关闭
    if UISpecialFrames then
        local found = false
        for _, n in ipairs(UISpecialFrames) do if n == "DotGridOptionsFrame" then found = true end end
        if not found then tinsert(UISpecialFrames, "DotGridOptionsFrame") end
    end

    -- 一次建好所有页（切页只切显示）；每页单独 pcall：真客户端里某个控件 API 有差异时
    -- 只坏那一页、并把原因打到聊天框，而不是整窗打不开（这种差异桩里跑不出来）
    for _, pg in ipairs({
        { "常规", BuildGeneral }, { "监控 debuff", BuildDebuffTab }, { "进度条", BuildBarTab },
        { L["格子"], BuildGridTab }, { L["颜色"], BuildColorTab }, { L["范围/口径"], BuildRangeTab },
        { L["配置档"], BuildProfileTab }, { L["工具/诊断"], BuildToolsTab },
    }) do
        local okP, errP = pcall(pg[2])
        if not okP then print(P .. L[" 设置界面：构建「"] .. pg[1] .. L["」页出错（"] .. tostring(errP) .. L["）"]) end
    end
    UI.spellInput = spellInput
    UI.profInput = profInput
    UI.IndexWidgets()
    return frame
end

-- 按行的标签给控件编号（离线测试与 /dg 里的自查都靠它精确定位"哪个开关/滑条"）
function UI.IndexWidgets()
    UI.byLabel = {}
    for _, w in ipairs(UI.widgets) do
        local l = w.row and w.row.label
        if l and l.text and l.text ~= "" then
            w.key = l.text
            UI.byLabel[l.text] = w
        end
    end
end

local function Widget(label)
    return label and UI.byLabel[label] or nil
end
UI.Widget = Widget

-- ==== 供离线测试（和以后自查）驱动的入口，等价于"玩家点了这个控件" ====
function UI.Click(key)
    local b = UI.actions[key]
    if b and b.scripts and b.scripts.OnClick then b.scripts.OnClick(b) return true end
    local w = Widget(key)
    if w and w.btn and w.btn.scripts and w.btn.scripts.OnClick then
        w.btn.scripts.OnClick(w.btn)
        return true
    end
    if w and w.sw and w.sw.scripts and w.sw.scripts.OnClick then
        w.sw.scripts.OnClick(w.sw)          -- 颜色块
        return true
    end
    return false
end

function UI.ClickOption(label, value)
    local w = Widget(label)
    if not (w and w.btns) then return false end
    for _, b in ipairs(w.btns) do
        if tostring(b.value) == tostring(value) and b.scripts and b.scripts.OnClick then
            b.scripts.OnClick(b)
            return true
        end
    end
    return false
end

function UI.SetSlider(label, v)
    local w = Widget(label)
    if not (w and w.s) then return false end
    w.s:SetValue(v)
    if w.flush then w.flush() end
    return true
end

function UI.TypeText(text, which)
    local eb = (which == "profile") and profInput or spellInput
    if not eb then return false end
    eb:SetText(tostring(text or ""))
    return true
end

function UI.PressEnter(which)
    local eb = (which == "profile") and profInput or spellInput
    if not eb then return false end
    if eb.scripts and eb.scripts.OnEnterPressed then
        eb.scripts.OnEnterPressed(eb)
        return true
    end
    return false
end

-- 按当前页把行从上往下摆；其它页的行隐藏
function UI.Layout()
    if not content then return end
    -- 自愈：当前页一行都没有（页名失效/被删）⇒ 回落到第一个有行的页，绝不留下空白的右边
    local has = false
    for _, row in ipairs(UI.rows) do if row.tab == currentTab then has = true break end end
    if not has then
        for _, row in ipairs(UI.rows) do
            if row.tab then currentTab = row.tab
                print(P .. L[" 界面：当前页没有可显示的行，已自动切到「"] .. tostring(row.tab) .. L["」页"])
                break
            end
        end
    end
    -- 先挑出本页的行（其它页隐藏）
    local list, y = {}, -6
    for _, row in ipairs(UI.rows) do
        if row.tab == currentTab then list[#list + 1] = row else row:Hide() end
    end
    -- 第一遍：先把行锚好。行有了宽度，说明文字才知道自己会折几行
    -- （建行时宽度未知，GetStringHeight 只量得出一行 ⇒ 两行说明会被当成一行，行距就不够而叠在一起）
    for _, row in ipairs(list) do
        row:ClearAllPoints()
        row:SetHeight(row.h or ROW_H)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
        row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)
        row:Show()
        y = y - (row.h or ROW_H)
    end
    -- 第二遍：按说明文字折行后的真实高度修高，并留出 ROW_GAP 的缝，最后重排一遍
    local y2 = -6
    for _, row in ipairs(list) do
        local n = row.note
        if n and n.GetStringHeight then
            local okH, sh = pcall(n.GetStringHeight, n)
            if okH and type(sh) == "number" and sh > 1 then
                local need = (-(row.noteTop or -32)) + sh + 8
                if need > (row.h or ROW_H) then row.h = need end
            end
        end
        row:ClearAllPoints()
        row:SetHeight(row.h or ROW_H)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y2)
        row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y2)
        y2 = y2 - (row.h or ROW_H) - ROW_GAP
    end
    content:SetHeight(math.max(10, -y2 + 8 + ROW_GAP))
    SetScroll(0)
    -- 自检：窗口开着但当前页一行都没有 ⇒ 把事实打出来，便于定位
    if frame and frame:IsShown() then
        local vis = 0
        for _, row in ipairs(UI.rows) do
            if row.tab == currentTab and row:IsShown() then vis = vis + 1 end
        end
        if vis == 0 then
            print(P .. fmt(L[" 界面自检：当前页「%s」没有任何可见行（共 %d 行）。请把这一行发给我"],
                tostring(currentTab), #UI.rows))
        end
    end
end

function UI.RefreshAll()
    if not frame then return end
    -- 法术列表（行数动态 → 面板行高跟着变）
    local spells = API.Spells() or {}
    local sig = table.concat(spells, ",")
    if UI._spellSig ~= sig then
        UI._spellSig = sig
        for i = 1, MAX_SPELLS_UI do
            local r = UI.spellRows[i]
            if r then
                if spells[i] then
                    r.txt:SetText(fmt(L["第 %d 条横条：%s"], i, tostring(spells[i])))
                    r:Show()
                else
                    r:Hide()
                end
            end
        end
        if spellPanel then spellPanel.h = math.max(26, #spells * 26) end
    end
    for _, w in ipairs(UI.widgets) do
        if w.refresh then
            local ok, err = pcall(w.refresh, w)
            if not ok then print(P .. L["界面刷新出错（"] .. tostring(w.kind) .. L["）："] .. tostring(err)) end
        end
    end
    -- 这两步里任何一步在真客户端报错，右边都会变成一片空白 —— 所以单独 pcall + 打原因
    local okTail, errTail = pcall(function()
        UI.DrawPreview()
        RefreshProfiles()
        for _, b in ipairs(UI.tabButtons or {}) do
            SetBtnState(b, b.tabKey == currentTab)
        end
        UI.Layout()
    end)
    if not okTail then print(P .. L[" 界面刷新收尾出错："] .. tostring(errTail)) end
end

-- 测试/关窗用：把滑条上还没下发的改动立刻下发
function UI.FlushSliders()
    for _, w in ipairs(UI.widgets) do
        if w.kind == "slider" and w.flush then pcall(w.flush) end
    end
end

function UI.ShowTab(key)
    if type(key) ~= "string" then return false end
    -- 只接受真实存在的页：未知页名（例如老存档里已删掉的 "pie"）一律拒绝，
    -- 否则 currentTab 会停在一个没有行的页上 ⇒ 右边永久一片空白
    local known = false
    for _, tb in ipairs(TAB_LIST) do if tb.key == key then known = true break end end
    if not known then return false end
    currentTab = key
    UI.RefreshAll()
    return true
end

-- 诊断用：把"界面上现在到底有什么"变成一串事实（/dg diag 会打印它）
function UI.Report()
    local parts = { L["窗口="] .. ((frame and frame:IsShown()) and L["开"] or L["关"]),
        L["当前页="] .. tostring(currentTab), L["行数="] .. tostring(#UI.rows) }
    local vis, perPage = 0, {}
    for _, row in ipairs(UI.rows) do
        perPage[row.tab] = (perPage[row.tab] or 0) + 1
        if row.tab == currentTab and row:IsShown() then vis = vis + 1 end
    end
    parts[#parts + 1] = L["当前页可见行="] .. tostring(vis)
    local ls = {}
    for _, tb in ipairs(TAB_LIST) do ls[#ls + 1] = tb.text .. ":" .. tostring(perPage[tb.key] or 0) end
    parts[#parts + 1] = L["各页行数("] .. table.concat(ls, " ") .. ")"
    local function sz(f)
        if not f then return "?" end
        local okW, w = pcall(f.GetWidth, f)
        local okH, h = pcall(f.GetHeight, f)
        return fmt("%sx%s", okW and tostring(w) or "?", okH and tostring(h) or "?")
    end
    parts[#parts + 1] = L["内容区="] .. sz(content) .. L[" 内容框="] .. sz(viewport)
    for _, row in ipairs(UI.rows) do
        if row.tab == currentTab and row:IsShown() then
            local h, np, y = "?", "?", "?"
            if row.GetHeight then local okH, v = pcall(row.GetHeight, row); if okH then h = tostring(v) end end
            if row.GetNumPoints then local okN, v = pcall(row.GetNumPoints, row); if okN then np = tostring(v) end end
            if row.GetPoint then
                local okG, _, _, _, _, gy = pcall(row.GetPoint, row, 1)
                if okG then y = tostring(gy) end
            end
            parts[#parts + 1] = fmt(L["首个可见行=宽%s 高=%s 锚点数=%s y=%s"],
                (pcall(row.GetWidth, row) and tostring(row:GetWidth()) or "?"), h, np, y)
            break
        end
    end
    return table.concat(parts, " · ")
end

function UI.GetTab() return currentTab end

-- 给离线测试和自查用：界面几何的真值（别在测试里写死数字）
UI.geom = { winW = WIN_W, winH = WIN_H, headH = HEAD_H, sideW = SIDE_W,
            rowH = ROW_H, rowGap = ROW_GAP, rowNote = ROW_NOTE, ctrlX = CTRL_X,
            rightPad = RIGHT_PAD, contentH = CONTENT_H }

function UI.Open()
    EnsureFrame()
    local d = API.DB() or {}
    frame:ClearAllPoints()
    if d.uiX and d.uiY then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", d.uiX, d.uiY)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    frame:Show()
    UI.RefreshAll()
    return true
end

function UI.Close()
    UI.FlushSliders()
    if frame then frame:Hide() end
end

function UI.IsShown()
    return (frame and frame:IsShown()) and true or false
end

function UI.Toggle()
    EnsureFrame()
    if frame:IsShown() then UI.Close() else UI.Open() end
    return true
end

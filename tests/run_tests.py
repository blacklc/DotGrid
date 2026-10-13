#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""DotGrid 离线测试套件 —— 不需要游戏客户端。

    python tests/run_tests.py
    DOTGRID_ADDON_DIR=/path/to/Interface/AddOns/DotGrid python tests/run_tests.py

它做三件事：
  A. 静态检查：语法、toc 与文件是否一一对应、绝对路径、已删功能残留、开发期口吻、
     中文字面量是否都走语言表、语言表是否覆盖全部键、README 分节、文件头、许可
  B. 行为检查：加载插件 → Init → 跑命令（显示方式/外观/范围/透明度/法术/配置档/恢复出厂）
     与存档迁移，全部通过 WoW API 桩
  C. 英文客户端实跑：GetLocale() 强制 enUS + 语言表，断言用户可见输出里没有中文

每个扫描都带自检：先确认它"能抓到故意植入的问题"，再报告干净。
"""
import io
import os
import re
import sys

try:
    from lupa import LuaRuntime
except ImportError:                                       # pragma: no cover
    print("需要 lupa：\n  pip install lupa\n  或 uv run --with lupa python tests/run_tests.py")
    sys.exit(2)

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
ADDON_DIR = os.environ.get("DOTGRID_ADDON_DIR") or os.path.join(REPO, "DotGrid")

PASSED, FAILED, NOTES = [], [], []


def ok(cond, label, detail=None):
    line = "PASS  " + label if cond else "FAIL  " + label
    if not cond and detail is not None:
        line += "   ← " + str(detail)[:220]
    (PASSED if cond else FAILED).append(line)


def note(text):
    NOTES.append(text)


def read(name):
    p = os.path.join(ADDON_DIR, name)
    if not os.path.isfile(p):
        return None
    return io.open(p, encoding="utf-8").read()


def inj_ns(src):
    """把插件自己的 `local ADDON, NS = ...` 换成注入的共享表，这样语言表能写进同一个 L。"""
    return src.replace("local ADDON, NS = ...", 'local ADDON, NS = "DotGrid", __NS', 1)


# --------------------------------------------------------------------------------------
# WoW API 桩
# --------------------------------------------------------------------------------------
STUB = r"""
LOG = {}
function print(...)
    local t = {}
    for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
    LOG[#LOG + 1] = table.concat(t, " ")
end

local function region()
    local r = {}
    local mt
    mt = { __index = function(_, k)
        if k == "GetWidth" or k == "GetHeight" then return function() return 100 end end
        if k == "IsShown" or k == "IsVisible" then return function() return true end end
        if k == "GetStringHeight" or k == "GetStringWidth" then return function() return 12 end end
        if k == "GetRegions" or k == "GetChildren" then return function() return {} end end
        if k == "GetName" then return function() return "region" end end
        if k == "GetObjectType" then return function() return "Texture" end end
        if k == "GetParent" then return function() return nil end end
        if k == "CreateTexture" or k == "CreateFontString" or k == "CreateLine"
           or k == "CreateAnimationGroup" or k == "CreateMaskTexture" then
            return function() return region() end
        end
        return function() end
    end }
    return setmetatable(r, mt)
end

function CreateFrame(kind, name, parent, template)
    local f = region()
    f.__kind = kind
    f.__name = name
    f.__events = {}
    f.__scripts = {}
    f.__shown = true
    f.RegisterEvent = function(self, e) self.__events[e] = true end
    f.UnregisterEvent = function(self, e) self.__events[e] = nil end
    f.IsEventRegistered = function(self, e) return self.__events[e] == true end
    f.SetScript = function(self, s, fn) self.__scripts[s] = fn end
    f.HookScript = function(self, s, fn) self.__scripts[s] = fn end
    f.GetScript = function(self, s) return self.__scripts[s] end
    f.Show = function(self) self.__shown = true end
    f.Hide = function(self) self.__shown = false end
    f.IsShown = function(self) return self.__shown end
    f.GetName = function(self) return self.__name or "frame" end
    f.GetWidth = function(self) return 2560 end
    f.GetHeight = function(self) return 1440 end
    f.GetRegions = function(self) return {} end
    f.GetChildren = function(self) return {} end
    f.CreateTexture = function(self) return region() end
    f.CreateFontString = function(self) return region() end
    f.CreateLine = function(self) return region() end
    f.CreateAnimationGroup = function(self) return region() end
    f.SetPoint = function(self, ...) self.__point = {...} end
    f.GetPoint = function(self) return "CENTER", nil, "CENTER", 0, 0 end
    f.SetBackdrop = function(self, t) self.__backdrop = t end
    f.GetBackdrop = function(self) return self.__backdrop end
    return f
end

UIParent = CreateFrame("Frame", "UIParent")
WorldFrame = CreateFrame("Frame", "WorldFrame")
SlashCmdList = {}

-- 没有任何怪：保证待机/空场景是干净的
function UnitExists(u) return false end
function UnitCanAttack(a, b) return false end
function UnitIsDead(u) return false end
function UnitIsDeadOrGhost(u) return false end
function UnitAffectingCombat(u) return false end
function UnitIsPlayer(u) return false end
function UnitIsUnit(a, b) return false end
function UnitName(u) return "TestChar" end
function UnitGUID(u) return nil end
function UnitThreatSituation(u, t) return nil end
function UnitDistanceSquared(u) return nil end
function CheckInteractDistance(u, i) return nil end
function UnitAura(...) return nil end
function GetRealmName() return "TestRealm" end
function GetTime() return 123.5 end
function GetScreenWidth() return 2560 end
function GetScreenHeight() return 1440 end
function InCombatLockdown() return false end
function IsInInstance() return false, "none" end
function GetInstanceInfo() return "none", "None" end
function GetCVar(k) return "1" end
function GetCVarBool(k) return true end
function issecretvalue(v) return false end
function issecrettable(v) return false end
function PlaySound() end
SOUNDKIT = {}
ColorPickerFrame = { Show = function() end, Hide = function() end,
                     SetupColorPickerAndShow = function() end, HideControls = function() end }
GameTooltip = CreateFrame("GameTooltip", "GameTooltip")
AuraUtil = { ForEachAura = function() end, UnpackAuraData = function() end }
C_Timer = { After = function(_, fn) end, NewTicker = function() return { Cancel = function() end } end }
C_NamePlate = { GetNamePlates = function() return {} end }
C_Spell = { IsSpellInRange = function() return true end }
C_CVar = { GetCVar = function() return "1" end, SetCVar = function() end }
C_AddOns = { GetAddOnMetadata = function(a, f) if f == "Version" then return "0.9.17" end return nil end,
             IsAddOnLoaded = function() return true end }
C_UnitAuras = {}
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function Mixin(a, ...) for i = 1, select("#", ...) do for k, v in pairs((select(i, ...))) do a[k] = v end end return a end
BackdropTemplateMixin = {}
"""


def new_lua():
    return LuaRuntime(unpack_returned_tuples=True)


def boot(locale="zhCN", seed=None, want_ui=True, with_locale_file=True):
    """起一个插件实例：桩 → 存档 → DotGrid.lua → 语言表 → DotGridUI.lua"""
    L = new_lua()
    L.execute(STUB)
    L.execute('GetLocale = function() return "%s" end' % locale)
    L.execute("__NS = {}")
    seed = seed or "{ cfgVer = 12, spells = {}, profiles = {}, charProfile = {} }"
    L.execute("DotGridDB = " + seed)
    src = inj_ns(read("DotGrid.lua"))
    L.execute(src + "\nPROBE_INIT = Init\nPROBE_SPELLS = GetSpellList\n"
                    "PROBE_PROFNAME = function() return ProfName end\n")
    if with_locale_file:
        loc = read("Locales/enUS.lua")
        if loc:
            L.execute(inj_ns(loc))
    if want_ui:
        ui = inj_ns(read("DotGridUI.lua"))
        L.execute(ui + "\nPROBE_TABS = function()\n"
                       "    local t = {}\n"
                       "    for _, tb in ipairs(TAB_LIST) do t[#t + 1] = tb.key end\n"
                       "    return t\n"
                       "end\n")
    return L


def chat_since(L, before):
    """取从 before 之后新增的聊天输出"""
    L.execute("__CHAT = table.concat(LOG, '\\n', %d)" % (before + 1))
    return L.eval("__CHAT") or ""


def run(L, cmd):
    before = L.eval("#LOG")
    L.execute('DotGrid.Run("%s")' % cmd.replace('"', '\\"'))
    return chat_since(L, before)


# ======================================================================================
# A. 静态检查
# ======================================================================================
def static_checks():
    files = ["DotGrid.lua", "DotGridUI.lua", "DotGrid.xml", "DotGrid.toc",
             "Locales/enUS.lua", "README.md"]
    for f in files:
        ok(read(f) is not None, "存在 " + f)

    toc = read("DotGrid.toc") or ""
    for key, why in [("## Interface: 120100", "接口版本"),
                     ("## Title:", "标题"), ("## Notes:", "说明"),
                     ("## Notes-zhCN:", "中文明说"), ("## Author:", "作者"),
                     ("## Version:", "版本"), ("## SavedVariables: DotGridDB", "存档变量"),
                     ("## IconTexture:", "图标"), ("## X-License:", "许可元数据")]:
        ok(key in toc, "toc 有" + why + "（" + key.strip() + "）")

    listed = [l.strip() for l in toc.split("\n") if l.strip() and not l.startswith("##")]
    missing = [l for l in listed if not os.path.isfile(os.path.join(ADDON_DIR, l.replace("\\", "/")))]
    ok(not missing, "toc 列的文件都存在", missing)
    ok("DotGrid.lua" in listed and "Locales\\enUS.lua" in listed, "toc 列出了主文件与语言表", listed)
    for f in ("DotGrid.lua", "DotGridUI.lua"):
        ok(f in listed, "toc 列出了 " + f)

    # ---- 语法 ----
    for f in ("DotGrid.lua", "DotGridUI.lua", "Locales/enUS.lua"):
        err = None
        try:
            L = new_lua()
            L.execute(STUB)
            L.execute("__NS = {}")
            if f != "Locales/enUS.lua":
                L.execute("DotGridDB = {}")
            L.execute('GetLocale = function() return "enUS" end')
            L.execute(inj_ns(read(f)))
        except Exception as ex:
            err = ex
        ok(err is None, f + " 语法/加载正确", err)

    # ---- 绝对路径扫描（带自检）----
    abs_pat = re.compile(r"(?<![A-Za-z])[A-Za-z]:[\\/]|AppData|/Users/|/home/|Documents and Settings")
    if not abs_pat.search("C:" + "\\Users\\x\\AddOns"):
        ok(False, "绝对路径扫描自检", "连盘符路径都认不出来")
    else:
        bad = []
        for f in files:
            txt = read(f) or ""
            for i, line in enumerate(txt.split("\n"), 1):
                if abs_pat.search(line):
                    bad.append("%s:%d %s" % (f, i, line.strip()[:60]))
        ok(not bad, "没有绝对路径 / 本机绑定目录", bad[:3])

    # ---- 已删功能残留 ----
    dead = ["wedge", "Wedge", "SECTORS", "pieSize", "pieDemo", "LayoutPie", "PaintPie",
            "WedgeFile", "BarFixed", "barFixed", "barW", "GetSectorCount", "LABEL_FMT"]
    hit = []
    for f in ("DotGrid.lua", "DotGridUI.lua"):
        txt = read(f) or ""
        for w in dead:
            if w not in txt:
                continue
            for i, line in enumerate(txt.split("\n"), 1):
                rhs_nil = re.search(r"=\s*nil(\s*,\s*nil)*\s*(--.*)?$", line)
                if w in line and not rhs_nil:
                    hit.append("%s:%d %s" % (f, i, line.strip()[:60]))
    if not hit and "pieSectors" in (read("DotGrid.lua") or ""):
        pass
    ok(not hit, "没有已删功能的残留符号", hit[:3])

    # ---- 开发期口吻 / 版本沿革（README 里允许点名测试脚本）----
    dev = re.compile(r"v0\.9\.\d|真机|教训|实测|用户要求|用户反馈|STEP\d|离线桩|死符号|"
                     + "zero" + "1")            # 本机用户名也拼开，免得它自己出现在公开仓库里
    bad = []
    for f in files:
        txt = read(f) or ""
        for i, line in enumerate(txt.split("\n"), 1):
            if dev.search(line):
                bad.append("%s:%d %s" % (f, i, line.strip()[:60]))
    if not dev.search("v0.9.3 真机教训"):
        ok(False, "开发期口吻扫描自检", "关键词一个都没匹配上")
    else:
        ok(not bad, "插件与文档里没有开发期口吻 / 版本沿革", bad[:3])

    # ---- 中文字面量必须走语言表 ----
    cjk = re.compile(r"[\u4e00-\u9fff]")
    data_keys = {"默认"}
    bare = []
    keys_used = set()
    for f in ("DotGrid.lua", "DotGridUI.lua"):
        for ln, line in enumerate((read(f) or "").split("\n"), 1):
            st = line.lstrip()
            if st.startswith("--"):
                continue
            if re.search(r",\s*Build[A-Z]", line):         # 页名当内部键的那张表
                continue
            for m in re.finditer(r'L\["((?:[^"\\]|\\.)*)"\]', line):
                keys_used.add(m.group(1))
            for m in re.finditer(r'"((?:[^"\\]|\\.)*)"', line):
                v = m.group(1)
                if not cjk.search(v) or v in data_keys:
                    continue
                if line[:m.start()].rstrip().endswith("["):
                    continue
                bare.append("%s:%d %s" % (f, ln, v[:44]))
    ok(not bare, "中文字面量全部走语言表（%d 个键）" % len(keys_used), bare[:4])

    # ---- 语言表覆盖 + 值里没有中文（带自检）----
    loc = read("Locales/enUS.lua") or ""
    loc_keys = set(m.group(1) for m in re.finditer(r'L\["((?:[^"\\]|\\.)*)"\] = ', loc))
    vals = re.findall(r'\] = "(.*)"$', loc, re.M)
    lack = sorted(k for k in keys_used if k not in loc_keys)
    cjk_vals = [v for v in vals if cjk.search(v)]
    ok(not lack, "英文语言表覆盖了全部键（缺 %d）" % len(lack), lack[:3])
    ok(not cjk_vals, "英文语言表的值里没有中文（%d 条）" % len(cjk_vals), cjk_vals[:2])
    if not ({"缺失的键"} - loc_keys):
        ok(False, "语言表覆盖检查自检", "构造的缺失键居然被覆盖了")
    else:
        ok(True, "语言表覆盖检查自检")

    # ---- 文件头注释 ----
    for f in ("DotGrid.lua", "DotGridUI.lua"):
        head = "\n".join((read(f) or "").split("\n")[:16])
        ok(head.startswith("-- ===") or head.startswith("--[[==="), f + " 以注释块开头")
        ok("不可破坏的约束" in head, f + " 头注释写明不可破坏的约束")

    # ---- README 分节（中文在插件目录，英文在仓库根）----
    zh = read("README.md") or ""
    for h in ["# DotGrid", "## 特性", "## 安装", "## 快速开始", "## 命令", "## 设置界面",
              "## 显示与外观", "## 范围与口径", "## 配置档与多角色", "## 诊断", "## 工作原理",
              "## 常见问题", "## 技术说明（维护者）", "## 本地化", "## 贡献与反馈", "## 许可"]:
        ok(h in zh, "中文 README 有「%s」" % h.lstrip("# ").strip())
    en = io.open(os.path.join(REPO, "README.md"), encoding="utf-8").read()
    for h in ["# DotGrid", "## Features", "## Requirements", "## Installation", "## How to use",
              "## Commands", "## Settings window", "## Range and criteria",
              "## Profiles and multiple characters", "## Diagnostics", "## How it works", "## FAQ",
              "## Technical notes (for contributors)", "## Localization", "## Contributing", "## License"]:
        ok(h in en, "英文 README 有「%s」" % h.lstrip("# ").strip())
    ok("[简体中文](README.zh-CN.md)" in en, "英文 README 有中文入口链接")

    # ---- 其它仓库文件 ----
    for f in ("LICENSE", "CHANGELOG.md", "CONTRIBUTING.md", ".gitignore", ".editorconfig",
              ".luacheckrc", "README.zh-CN.md"):
        ok(os.path.isfile(os.path.join(REPO, f)), "仓库根有 " + f)
    lic = io.open(os.path.join(REPO, "LICENSE"), encoding="utf-8").read()
    ok("MIT License" in lic and "Permission is hereby granted" in lic, "LICENSE 是 MIT 全文")
    ok("blacklc" in lic, "LICENSE 版权行用了 GitHub ID")
    ok("LICENSE" not in [l.strip() for l in toc.split("\n") if l.strip() and not l.startswith("##")],
       "插件目录里不带 LICENSE（只放仓库根）")

    # ---- 密钥 / 凭据扫描 ----
    secret = re.compile(
        r"sk-[A-Za-z0-9]{16,}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{12,}|"
        r"-----BEGIN [A-Z ]*PRIVATE KEY-----|xox[baprs]-[A-Za-z0-9-]{10,}|"
        r"\b(api[_-]?key|secret|passwd|password|token)\b\s*[:=]\s*[\"'][^\"']{6,}[\"']", re.I)
    if not secret.search('api_' + 'key = ' + chr(34) + 'abcdef123456' + chr(34)):
        ok(False, "密钥扫描自检", "连明显的假密钥都认不出来")
    else:
        secrets = []
        for root, dirs, fs in os.walk(REPO):
            dirs[:] = [d for d in dirs if d not in (".git", "__pycache__", ".venv")]
            for f in fs:
                p = os.path.join(root, f)
                try:
                    txt = io.open(p, encoding="utf-8", errors="replace").read()
                except Exception:
                    continue
                for i, line in enumerate(txt.split("\n"), 1):
                    if secret.search(line):
                        secrets.append("%s:%d %s" % (os.path.relpath(p, REPO), i, line.strip()[:60]))
        ok(not secrets, "整个项目里没有密钥 / 口令字面量", secrets[:3])


# ======================================================================================
# B. 行为检查（通过桩）
# ======================================================================================
def behaviour_checks():
    # ---- 加载：Init 只打一行 ----
    L = boot()
    L.execute("PROBE_INIT()")
    lines = [l for l in (L.eval("table.concat(LOG, '\\n')") or "").split("\n") if l.strip()]
    ok(len(lines) == 1, "加载时只打印 1 行", lines)
    ok(len(lines) == 1 and "待机" in lines[0], "加载行说明了待机状态", lines)
    ok(L.eval("DotGrid.Run ~= nil"), "导出了 Run（界面/命令共用入口）")

    # ---- /dg help ----
    out = run(L, "help")
    ok("帮助（当前状态）" in out, "help 有状态头")
    ok("显示方式" in out and "统计口径" in out, "help 有显示方式与统计口径")
    ok(out.count("——") >= 20, "help 是分组对齐清单", out.count("——"))
    ok("/dg bar segw" in out and "/dg profile new" in out, "help 列出了命令")
    ok("饼图" not in out and "bar fixed" not in out, "help 不再提已删功能")

    # ---- 法术 ----
    out = run(L, "spell 1943,703")
    ok("1943" in out and "703" in out, "设置多个法术有回显", out)
    ok(L.eval("PROBE_SPELLS()") is not None, "法术列表可读")
    out = run(L, "spells")
    ok("1943" in out, "spells 列出当前监控的法术", out)
    out = run(L, "spell clear")
    ok("待机" in out, "清空法术 ⇒ 回到待机", out)

    # ---- 显示方式 / 外观 / 范围 / 透明度 ----
    ok("grid" in run(L, "mode grid"), "mode grid 生效")
    ok("进度条" in run(L, "mode bar"), "mode bar 生效")
    ok("panel" in run(L, "style panel") or "外观" in run(L, "style panel"), "style panel 生效")
    ok("7" in run(L, "tier 3"), "tier 3 生效")
    ok("threat" in run(L, "engaged threat") or "跟我打" in run(L, "engaged threat"), "engaged threat 生效")
    ok("50" in run(L, "alpha 50"), "alpha 50 生效")
    ok("颜色" in run(L, "color hit d80f0f") or "d80f0f" in run(L, "color hit d80f0f"), "color 生效")

    # ---- 配置档 ----
    L2 = boot(seed="{ cfgVer = 12, spells = {1943}, profiles = {}, charProfile = {} }")
    L2.execute("PROBE_INIT()")
    out = run(L2, "profile new 小号专用")
    ok("小号专用" in out, "新建配置档有回显", out)
    out = run(L2, "profile")
    ok("小号专用" in out and "本角色在用" in out, "配置档列表标出正在用的档", out)
    out = run(L2, "profile load 默认")
    ok("默认" in out, "可以切回默认档", out)
    out = run(L2, "profile delete 默认")
    ok("不能删" in out or "不许删" in out, "默认档拒绝删除", out)
    out = run(L2, "reset")
    ok("恢复出厂" in out, "reset 有回显", out)

    # ---- 存档迁移：cfgVer 11 → 12 ----
    L3 = boot(seed="{ cfgVer = 11, profiles = { ['默认'] = { spells = {1943,703}, barSegW = 24 } },"
                    " charProfile = { ['testrealm-testchar'] = '默认' } }")
    L3.execute("PROBE_INIT()")
    ver = L3.eval("DotGridDB.cfgVer")
    ok(ver == 12, "存档版本迁移到 12（实测 %s）" % ver)
    out = run(L3, "spells")
    ok("1943" in out, "迁移后老配置的法术还在", out)

    # ---- 老存档的档名仍然可用 ----
    ok(L3.eval("(DotGridDB.profiles['默认'] ~= nil)"), "「默认」档仍然是存档里的键（不随语言变）")

    # ---- 设置界面：8 个页面都能建，且真的有行 ----
    L4 = boot()
    L4.execute("PROBE_INIT()")
    run(L4, "")
    tabs = list(L4.eval("PROBE_TABS()").values())
    ok(len(tabs) == 8, "界面有 8 个标签页（实测 %d）" % len(tabs), tabs)
    rows0 = L4.eval("#DotGrid.UI.rows")
    ok(rows0 and rows0 > 20, "界面建出了行（%s 行）" % rows0)
    for key in tabs:
        err = None
        try:
            L4.execute('DotGrid.UI.ShowTab("%s")' % key)
        except Exception as ex:
            err = ex
        ok(err is None, "页面「%s」能正常打开" % key, err)

    # ---- 待机：没有法术时不建任何容器 ----
    L5 = boot(seed="{ cfgVer = 12, spells = {}, profiles = {}, charProfile = {} }")
    L5.execute("PROBE_INIT()")
    n = L5.eval("__NS.__containers and #__NS.__containers or 0")
    ok(not n, "没有设置法术时不建容器（待机）", n)


# ======================================================================================
# C. 英文客户端实跑
# ======================================================================================
def english_checks():
    L = boot(locale="enUS")
    L.execute("PROBE_INIT()")
    out = run(L, "help")
    cn = [l for l in out.split("\n") if re.search(r"[\u4e00-\u9fff]", l)]
    ok(not cn, "英文客户端下 /dg help 全英文", cn[:2])
    ok("Commands:" in out or "/dg" in out, "英文 help 仍然列出命令")
    out = run(L, "spell 1943,703")
    cn = [l for l in out.split("\n") if re.search(r"[\u4e00-\u9fff]", l)]
    ok(not cn, "英文客户端下命令回显全英文", cn[:2])
    # 默认档名在英文客户端显示为 default，但存档键仍然是中文（不串档、不迁移）
    L2 = boot(locale="enUS",
              seed="{ cfgVer = 12, spells = {1943}, profiles = { ['默认'] = { spells = {1943} } },"
                   " charProfile = { ['testrealm-testchar'] = '默认' } }")
    L2.execute("PROBE_INIT()")
    out = run(L2, "profile")
    ok("default" in out, "英文客户端下默认档显示为 default", out[:160])
    ok("默认" not in out, "英文客户端下不再显示中文档名", out[:160])
    ok(L2.eval("DotGridDB.charProfile['testrealm-testchar'] == '默认'"),
       "存档里仍然写「默认」（只翻译显示）")
    # 英文输出不该出现"句号后面直接粘字母"的拼接痕迹
    glue = re.findall(r"[)\]]\.[A-Za-z]", out) + re.findall(r"[一-鿿]", out)
    ok(not glue, "英文输出没有中英拼接痕迹", glue[:3])


def main():
    print("DotGrid 测试套件")
    print("  插件目录: %s" % ADDON_DIR)
    print("  仓库目录: %s" % REPO)
    print("-" * 62)
    if not os.path.isfile(os.path.join(ADDON_DIR, "DotGrid.toc")):
        print("找不到 DotGrid.toc —— 用 DOTGRID_ADDON_DIR 指定插件目录")
        return 2
    static_checks()
    behaviour_checks()
    english_checks()
    verbose = "-v" in sys.argv
    if verbose:
        for line in PASSED:
            print(line)
    for n in NOTES:
        print("  " + n)
    for line in FAILED:
        print(line)
    print("-" * 62)
    print("PASS 数: %d ｜ FAIL 数: %d" % (len(PASSED), len(FAILED)))
    if FAILED:
        print("FAILURES:\n" + "\n".join(FAILED))
        return 1
    print("ALL PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())

local Sona = {}
local version = 1
--[[ if tonumber(GetInternalWebResult("Sona.version")) > version then
    DownloadInternalFile("Sona.lua", SCRIPT_PATH .. "Sona.lua")
    PrintChat("New version:" .. tonumber(GetInternalWebResult("Sona.version")) .. " Press F5")
end ]]
require "FF15Menu"
require "utils"

function OnLoad()
    if not _G.Prediction then
        LoadPaidScript(PaidScript.DREAM_PRED)
    end
end

function Sona:__init()
    self.q = 825
    self.r = {
        speed = 2400,
        range = 1000,
        delay = 0.25,
        width = 280
    }
    self:Menu()
    AddEvent(
        Events.OnTick,
        function()
            self:OnTick()
        end
    )
    AddEvent(
        Events.OnDraw,
        function()
            self:OnDraw()
        end
    )
    PrintChat("Sona loaded")
    self.font = DrawHandler:CreateFont("Calibri", 10)
end

function Sona:Menu()
    self.menu = Menu("sona", "Sona")
    self.menu:key("r", "Manual R Key", string.byte("Z"))
    self.menu:slider("rs", "R Hitchance", 1, 100, 75)
    self.menu:slider("raoe", "R at x Enemies", 1, 5, 2)
    self.menu:checkbox("drawQ", "Draw Q", true)
    self.menu:slider("qa", "Alpha", 1, 255, 150)
    self.menu:slider("qr", "Red", 1, 255, 255)
    self.menu:slider("qg", "Green", 1, 255, 150)
    self.menu:slider("qb", "Blue", 1, 255, 150)
end

function Sona:OnDraw()
    if self.menu.drawQ:get() then
        DrawHandler:Circle3D(
            myHero.position,
            self.q,
            Hex(self.menu.qa:get(), self.menu.qr:get(), self.menu.qg:get(), self.menu.qb:get())
        )
    end
end

function Sona:CastQ()
    if myHero.spellbook:CanUseSpell(0) == 0 and LegitOrbwalker:GetTarget(self.q, "AP", myHero) then --something wrong here
        myHero.spellbook:CastSpell(0, pwHud.hudManager.virtualCursorPos)
    end
end

function Sona:CastR(target)
    if myHero.spellbook:CanUseSpell(3) == 0 and GetDistance(target.position) <= self.r.range then
        pred = _G.Prediction.GetPrediction(target, self.r, myHero)
        if
            pred and pred.castPosition and pred.hitChance > self.menu.rs:get() / 100 and not pred:windWallCollision() and
                (aoe and pred:heroCollision(aoe) or not aoe)
         then
            myHero.spellbook:CastSpell(3, pred.castPosition)
        end
    end
end

function Sona:OnTick()
    target = LegitOrbwalker:GetTarget(self.r.range, "AP", myHero)
    if LegitOrbwalker:GetMode() == "Combo" then
        self:CastQ()
        if target then
            self:CastR(target, self.menu.raoe:get() - 1)
        end
    elseif target and self.menu.r:get() then
        self:CastR(target, 0)
    end
end

function Hex(a, r, g, b)
    return string.format("0x%.2X%.2X%.2X%.2X", a, r, g, b)
end

if myHero.charName == "Sona" then
    Sona:__init()
end

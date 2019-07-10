local Sona = {}
local version = 1.1
if tonumber(GetInternalWebResult("asdfsona.version")) > version then
    DownloadInternalFile("asdfsona.lua", SCRIPT_PATH .. "asdfsona.lua")
    PrintChat("New version:" .. tonumber(GetInternalWebResult("asdfsona.version")) .. " Press F5")
end
require "FF15Menu"
require "utils"
local Orbwalker = require "FF15OL"

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
        width = 275,
        castRate = "very slow"
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
    if myHero.spellbook:CanUseSpell(0) == 0 then
        local myHeroPred = _G.Prediction.GetUnitPosition(myHero, NetClient.ping / 1000)
        for _, enemy in pairs(ObjectManager:GetEnemyHeroes()) do
            if _G.Prediction.IsValidTarget(enemy, 1000) then
                local enemyPred = _G.Prediction.GetUnitPosition(enemy, NetClient.ping / 1000)
                if GetDistanceSqr(myHeroPred, enemyPred) < self.q * self.q then
                    myHero.spellbook:CastSpell(0, pwHud.hudManager.activeVirtualCursorPos)
                end
            end
        end
    end
end

function Sona:CastR(target, aoe)
    if myHero.spellbook:CanUseSpell(3) == 0 then
        pred = _G.Prediction.GetPrediction(target, self.r, myHero)
        if pred and pred.castPosition and (not aoe or pred:heroCollision(aoe)) then
            myHero.spellbook:CastSpell(3, pred.castPosition)
        end
    end
end

function Sona:OnTick()
    target = Orbwalker:GetTarget(self.r.range, "AP", myHero)
    if Orbwalker:GetMode() == "Combo" then
        self:CastQ()
        for _, enemy in pairs(ObjectManager:GetEnemyHeroes()) do
            if _G.Prediction.IsValidTarget(enemy, self.r.range) then
                self:CastR(enemy, self.menu.raoe:get() - 1)
            end
        end
    elseif target and self.menu.r:get() then
        self:CastR(target)
    end
end

function Hex(a, r, g, b)
    return string.format("0x%.2X%.2X%.2X%.2X", a, r, g, b)
end

if myHero.charName == "Sona" then
    Sona:__init()
end

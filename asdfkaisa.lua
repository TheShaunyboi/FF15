local Kaisa = {}
local version = 1
--[[ if tonumber(GetInternalWebResult("asdfkaisa.version")) > version then
    DownloadInternalFile("asdfkaisa.lua", SCRIPT_PATH .. "asdfkaisa.lua")
    PrintChat("New version:" .. tonumber(GetInternalWebResult("asdfkaisa.version")) .. " Press F5")
end ]]
require "FF15Menu"
require "utils"

function OnLoad()
    if not _G.Prediction then
        LoadPaidScript(PaidScript.DREAM_PRED)
    end
end

function Kaisa:__init()
    self.qRange = 600
    self.w = {
        searchRange = 400,
        speed = 1750,
        range = 2500,
        delay = 0.4,
        width = 200
    }
    self:Menu()
    AddEvent(
        Events.OnTick,
        function()
            self:OnTick()
        end
    )
    AddEvent(
        Events.OnBuffGain,
        function(obj, buff)
            self:OnBuffGain(obj, buff)
        end
    )
    AddEvent(
        Events.OnBuffLost,
        function(obj, buff)
            self:OnBuffLost(obj, buff)
        end
    )

    AddEvent(
        Events.OnDraw,
        function()
            self:OnDraw()
        end
    )
    PrintChat("Kaisa loaded")
    self.font = DrawHandler:CreateFont("Calibri", 10)
end

function Kaisa:Menu()
    self.menu = Menu("asdfkaisa", "Kaisa")
    self.menu:checkbox("q", "AutoQ", true, 0x54)
    self.menu:sub("drawQ", "Draw Q")
    self.menu.drawQ:slider("q0r", "AutoQ off: Red", 1, 255, 150)
    self.menu.drawQ:slider("q0g", "AutoQ off: Green", 1, 255, 150)
    self.menu.drawQ:slider("q0b", "AutoQ off: Blue", 1, 255, 150)
    self.menu.drawQ:slider("q1r", "AutoQ on: Red", 1, 255, 255)
    self.menu.drawQ:slider("q1g", "AutoQ on: Green", 1, 255, 150)
    self.menu.drawQ:slider("q1b", "AutoQ on: Blue", 1, 255, 150)
    self.menu:sub("drawW", "Draw W")
    self.menu.drawW:slider("wr", "W Near Mouse: Red", 1, 255, 150)
    self.menu.drawW:slider("wg", "W Near Mouse: Green", 1, 255, 150)
    self.menu.drawW:slider("wb", "W Near Mouse: Blue", 1, 255, 150)
end

function Kaisa:OnDraw()
    if self.menu.q:get() then
        DrawHandler:Circle3D(
            myHero.position,
            self.qRange,
            self:Hex(255, self.menu.drawQ.q0r:get(), self.menu.drawQ.q0g:get(), self.menu.drawQ.q0b:get())
        )
    else
        DrawHandler:Circle3D(
            myHero.position,
            self.qRange,
            self:Hex(255, self.menu.drawQ.q1r:get(), self.menu.drawQ.q1g:get(), self.menu.drawQ.q1b:get())
        )
    end
    DrawHandler:Circle3D(
        pwHud.hudManager.virtualCursorPos,
        self.w.searchRange,
        self:Hex(255, self.menu.drawW.wr:get(), self.menu.drawW.wg:get(), self.menu.drawW.wb:get())
    )
end

function Kaisa:CastQ()
    if myHero.spellbook:CanUseSpell(0) == 0 and LegitOrbwalker:GetTarget(self.qRange, "AP", myHero) then
        myHero.spellbook:CastSpell(0, pwHud.hudManager.activeVirtualCursorPos)
    end
end

function Kaisa:W()
    local target1 = LegitOrbwalker:GetTarget(self.w.searchRange, "AP", pwHud.hudManager.virtualCursorPos)
    local target2 = LegitOrbwalker:GetTarget(myHero.characterIntermediate.attackRange, "AP", myHero)
    if target1 then
        self:CastW(target1)
    elseif target2 then
        self:CastW(target2)
    else
        --on CC
        for _, enemy in pairs(ObjectManager:GetEnemyHeroes()) do
            if
            _G.Prediction.IsValidTarget(enemy) and GetDistanceSqr(enemy) <= self.w.range * self.w.range and
                    _G.Prediction.IsImmobile(enemy, GetDistance(enemy) / self.w.speed + self.w.delay)
             then
                self:CastW(enemy)
            end
        end
    end
end

function Kaisa:CastW(target)
    if myHero.spellbook:CanUseSpell(1) == 0 and GetDistance(target.position) <= self.w.range then
        local pred = _G.Prediction.GetPrediction(target, self.w, myHero)
        if
            pred and pred.castPosition and (pred.realHitChance == 1 or _G.Prediction.WaypointManager.ShouldCast(target)) and
                GetDistanceSqr(pred.castPosition) <= self.w.range * self.w.range
         then
            myHero.spellbook:CastSpell(1, pred.castPosition)
        end
    end
end

function Kaisa:OnTick()
    if self.menu.q:get() then
        self:CastQ()
    end
    if LegitOrbwalker:GetMode() == "Combo" then
        self:CastQ()
        self:W()
    end
end

function Kaisa:OnBuffGain(obj, buff)
    if obj == myHero and buff.name == "KaisaE" then
        LegitOrbwalker:BlockAttack(true)
    end
end

function Kaisa:OnBuffLost(obj, buff)
    if obj == myHero and buff.name == "KaisaE" then
        LegitOrbwalker:BlockAttack(false)
    end
end

function Kaisa:Hex(a, r, g, b)
    return string.format("0x%.2X%.2X%.2X%.2X", a, r, g, b)
end

if myHero.charName == "Kaisa" then
    Kaisa:__init()
end

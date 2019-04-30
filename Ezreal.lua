local Ezreal = {}
local version = 1
--[[if tonumber(GetInternalWebResult("Ezreal.version")) > version then
    DownloadInternalFile("Ezreal.lua", SCRIPT_PATH .. "Ezreal.lua")
    PrintChat("New version:" .. tonumber(GetInternalWebResult("Ezreal.version")) .. " Press F5")
end--]]
require "FF15Menu"
require "utils"
local DreamTS = require("DreamTS")
local dmgLib = require("FF15DamageLib")

function OnLoad()
    if not _G.Prediction then
        LoadPaidScript(PaidScript.DREAM_PRED)
    end
end

function Ezreal:__init()
    self.q = {
        speed = 2000,
        range = 1150,
        delay = 0.25,
        width = 125
    }
    self.w = {
        speed = 1700,
        range = 1150,
        delay = 0.25,
        width = 165
    }
    self.r = {
        speed = 2000,
        range = 2500,
        delay = 1,
        width = 325
    }
    self.wBuffTarget = nil
    self:Menu()
    self.TS =
        DreamTS(
        self.menu.dreamTs,
        {
            ValidTarget = function(unit)
                return _G.Prediction.IsValidTarget(unit, self.r.range)
            end,
            Damage = function(unit)
                return dmgLib:CalculateMagicDamage(myHero, unit, 100)
            end
        }
    )
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
    PrintChat("Ezreal loaded")
    self.font = DrawHandler:CreateFont("Calibri", 10)
end

function Ezreal:Menu()
    self.menu = Menu("asdfezreal", "Ezreal")
    self.menu:sub("dreamTs", "Target Selector")
    self.menu:checkbox("q", "AutoQ", true, string.byte("T"))
    self.menu:key("r", "Manual R Key", 0x5A)
    self.menu:sub("ezrealDraw", "Draw")
    self.menu.ezrealDraw:checkbox("q", "Q", true)
    self.menu.ezrealDraw:slider("qa", "Alpha", 1, 255, 150)
    self.menu.ezrealDraw:slider("q0r", "AutoQ off: Red", 1, 255, 150)
    self.menu.ezrealDraw:slider("q0g", "AutoQ off: Green", 1, 255, 150)
    self.menu.ezrealDraw:slider("q0b", "AutoQ off: Blue", 1, 255, 150)
    self.menu.ezrealDraw:slider("q1r", "AutoQ on: Red", 1, 255, 255)
    self.menu.ezrealDraw:slider("q1g", "AutoQ on: Green", 1, 255, 150)
    self.menu.ezrealDraw:slider("q1b", "AutoQ on: Blue", 1, 255, 150)
end

function Ezreal:OnDraw()
    if self.menu.ezrealDraw.q:get() then
        if self.menu.q:get() then
            DrawHandler:Circle3D(
                myHero.position,
                self.q.range,
                self:Hex(
                    self.menu.ezrealDraw.qa:get(),
                    self.menu.ezrealDraw.q1r:get(),
                    self.menu.ezrealDraw.q1g:get(),
                    self.menu.ezrealDraw.q1b:get()
                )
            )
        else
            DrawHandler:Circle3D(
                myHero.position,
                self.q.range,
                self:Hex(
                    self.menu.ezrealDraw.qa:get(),
                    self.menu.ezrealDraw.q0r:get(),
                    self.menu.ezrealDraw.q0g:get(),
                    self.menu.ezrealDraw.q0b:get()
                )
            )
        end
    end
    if self.wBuffTarget then
        DrawHandler:Circle3D(
            self.wBuffTarget.position,
            20,
            self:Hex(
                self.menu.ezrealDraw.qa:get(),
                self.menu.ezrealDraw.q0r:get(),
                self.menu.ezrealDraw.q0g:get(),
                self.menu.ezrealDraw.q0b:get()
            )
        )
    end
end

function Ezreal:CastQ(target)
    if myHero.spellbook:CanUseSpell(0) == 0 then
        local pred = _G.Prediction.GetPrediction(target, self.q, myHero)
        if
            pred and pred.castPosition and GetDistanceSqr(pred.castPosition) <= self.q.range * self.q.range and
                (pred.realHitChance == 1 or _G.Prediction.WaypointManager.ShouldCast(target) or
                    GetDistanceSqr(pred.castPosition) <= 400 * 400) and
                not pred:windWallCollision() and
                not pred:minionCollision()
         then
            myHero.spellbook:CastSpell(0, pred.castPosition)
            return true
        end
    end
end
function Ezreal:CastW(target)
    if myHero.spellbook:CanUseSpell(1) == 0 then
        local pred = _G.Prediction.GetPrediction(target, self.w, myHero)
        if
            pred and pred.castPosition and GetDistanceSqr(pred.castPosition) <= self.w.range * self.w.range and
                (pred.realHitChance == 1 or _G.Prediction.WaypointManager.ShouldCast(target)) and
                not pred:windWallCollision()
         then
            myHero.spellbook:CastSpell(1, pred.castPosition)
            return true
        end
    end
end

function Ezreal:CastR(target)
    if myHero.spellbook:CanUseSpell(3) == 0 then
        local pred = _G.Prediction.GetPrediction(target, self.r, myHero)
        if
            pred and pred.castPosition and GetDistanceSqr(pred.castPosition) <= self.r.range * self.r.range and
                (pred.realHitChance == 1 or _G.Prediction.WaypointManager.ShouldCast(target)) and
                not pred:windWallCollision()
         then
            myHero.spellbook:CastSpell(3, pred.castPosition)
            return true
        end
    end
end

function Ezreal:R(target)
    if _G.Prediction.IsImmobile(target, GetDistance(target) / self.r.speed + self.r.delay) then
        self:CastR(target)
        return true
    end
    local pred = _G.Prediction.GetPrediction(target, self.r, myHero)
    if
        pred and pred.realHitChance > 0 and pred.castPosition and
            (pred.realHitChance == 1 or _G.Prediction.WaypointManager.ShouldCast(target)) and
            pred:heroCollision(2) and
            not pred:windWallCollision()
     then
        myHero.spellbook:CastSpell(3, pred.castPosition)
        return true
    end
end

function Ezreal:OnTick()
    if not LegitOrbwalker:IsAttacking() then
        for _, target in ipairs(self:GetTarget(self.r.range, true)) do
            if self.menu.r:get() then
                if self:CastR(target) then
                    return
                end
            end
            if LegitOrbwalker:GetMode() == "Combo" then
                if self:R(target) then
                    return
                end
                local wTarget = self:GetTarget(self.w.range)
                if wTarget and self:CastW(wTarget) then
                    return
                end
                if self.wBuffTarget and _G.Prediction.IsValidTarget(self.wBuffTarget, self.q.range) and self:CastQ(self.wBuffTarget) then
                    return
                end
                if self:CastQ(target) then
                    return
                end
            elseif self.menu.q:get() and not _G.Prediction.IsRecalling(myHero) then
                if self.wBuffTarget and _G.Prediction.IsValidTarget(self.wBuffTarget, self.q.range) then
                    self:CastQ(self.wBuffTarget)
                end
                if self:CastQ(target) then
                    return
                end
            end
        end
    end
end

function Ezreal:OnBuffGain(obj, buff)
    if obj and obj.team ~= myHero.team and obj.type == myHero.type and buff.name == "ezrealwattach" then
        self.wBuffTarget = obj
        LegitOrbwalker:SetForcedTarget(obj)
    end
end

function Ezreal:OnBuffLost(obj, buff)
    if obj and obj.team ~= myHero.team and obj.type == myHero.type and buff.name == "ezrealwattach" then
        self.wBuffTarget = nil
        LegitOrbwalker:UnsetForcedTarget()
    end
end

function Ezreal:Hex(a, r, g, b)
    return string.format("0x%.2X%.2X%.2X%.2X", a, r, g, b)
end

function Ezreal:GetTarget(dist, all)
    self.TS.ValidTarget = function(unit)
        return _G.Prediction.IsValidTarget(unit, dist)
    end
    local res = self.TS:update()
    if all then
        return res
    else
        if res and res[1] then
            return res[1]
        end
    end
end

if myHero.charName == "Ezreal" then
    Ezreal:__init()
end

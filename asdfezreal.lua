local Ezreal = {}
local version = 2.3
if tonumber(GetInternalWebResult("asdfezreal.version")) > version then
    DownloadInternalFile("asdfezreal.lua", SCRIPT_PATH .. "asdfezreal.lua")
    PrintChat("New version:" .. tonumber(GetInternalWebResult("asdfezreal.version")) .. " Press F5")
end
require "FF15Menu"
require "utils"
local DreamTS = require("DreamTS")
local dmgLib = require("FF15DamageLib")
local Orbwalker = require "FF15OL"

local Vector = require("GeometryLib").Vector
local LineSegment = require("GeometryLib").LineSegment

local function EdgePosition2(tP, cP, source, adjustment, target, range)
    tP = Vector(tP)
    cP = Vector(cP)
    local dist = source:dist(tP)
    adjustment = 0.95 * adjustment
    local angle = math.asin(adjustment / dist)
    local diff = tP - source
    local rotated1 = diff:rotated(0, angle, 0):normalized()
    local rotated2 = diff:rotated(0, -angle, 0):normalized()
    local distToCast = math.sqrt(dist * dist - adjustment * adjustment)
    local castPos1 = (source + rotated1 * distToCast):D3D()
    local castPos2 = (source + rotated2 * distToCast):D3D()
    local res = GetDistanceSqr(castPos1, tP:D3D()) < GetDistanceSqr(castPos2, tP:D3D()) and castPos1 or castPos2
    local maxPos = source + (Vector(res) - source):normalized() * (range + 100)
    local seg1 = LineSegment(source, maxPos)
    local seg2 = LineSegment(Vector(target.position), tP)
    local isIntersect, intersection = seg1:intersects(seg2)
    if isIntersect and intersection then
        local intersectionVector = Vector(intersection.x, myHero.position.y, intersection.z)
        local intersectionAngle = intersectionVector:angleBetween(source, tP)
        if intersectionAngle > 45 and intersectionAngle < 135 then
            return res, true
        else
            return cP:D3D(), false
        end
    else
        return cP:D3D(), false
    end
end

function OnLoad()
    if not _G.Prediction then
        LoadPaidScript(PaidScript.DREAM_PRED)
        _G.EdgePosition = EdgePosition2
    end
    if not _G.AuroraOrb and not _G.LegitOrbwalker then
        LoadPaidScript(PaidScript.AURORA_BUNDLE_DEV)
    end
    Orbwalker:Setup()
end

function Ezreal:__init()
    self.q = {
        type = "linear",
        speed = 2000,
        range = 1150,
        delay = 0.25,
        width = 125,
        collision = {
            ["Wall"] = true,
            ["Hero"] = true,
            ["Minion"] = true
        }
    }
    self.w = {
        type = "linear",
        speed = 1700,
        range = 1150,
        delay = 0.25,
        width = 165,
        collision = {
            ["Wall"] = true,
            ["Hero"] = true,
            ["Minion"] = false
        }
    }
    self.r = {
        type = "linear",
        speed = 2000,
        range = 2500,
        delay = 1,
        width = 325,
        collision = {
            ["Wall"] = true,
            ["Hero"] = true,
            ["Minion"] = false
        }
    }
    self.LastCasts = {
        Q = nil,
        W = nil,
        E = nil,
        R = nil
    }
    self.wBuffTarget = nil
    self:Menu()
    self.TS =
        DreamTS(
        self.menu.dreamTs,
        {
            Damage = DreamTS.Damages.AD
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
    AddEvent(
        Events.OnExecuteCastFrame,
        function(...)
            self:OnExecuteCastFrame(...)
        end
    )
    PrintChat("Ezreal loaded")
    self.font = DrawHandler:CreateFont("Calibri", 10)
end

function Ezreal:Menu()
    self.menu = Menu("asdfezreal", "Ezreal")
    self.menu:sub("dreamTs", "Target Selector")
    self.menu:checkbox("q", "AutoQ", true, string.byte("T"))
    self.menu:checkbox("user", "Use R", true)
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
    DrawHandler:Circle3D(myHero.position, self.q.range, Color.White)
    local text = self.menu.q:get() and "AutoQ on" or "AutoQ off"
    DrawHandler:Text(DrawHandler.defaultFont, Renderer:WorldToScreen(myHero.position), text, Color.White)

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

function Ezreal:ShouldCast()
    for spell, time in pairs(self.LastCasts) do
        if time and RiotClock.time < time + 0.25 + NetClient.ping / 2000 + 0.06 then
            return false
        end
    end

    return true
end

function Ezreal:GetCastPosition(pred)
    pred:draw()
    if pred.isAdjusted then
        return pred.ap
    else
        return pred.castPosition
    end
end

function Ezreal:CastQ()
    if myHero.spellbook:CanUseSpell(0) == 0 then
        local qTargets, qPred =
            self:GetTarget(
            self.q,
            true,
            nil,
            function(unit, pred)
                return pred.rates["very slow"]
            end
        )
        if self.wBuffTarget and qPred[self.wBuffTarget.networkId] then
            myHero.spellbook:CastSpell(0, self:GetCastPosition(qPred[self.wBuffTarget.networkId]))
            self.LastCasts["Q"] = RiotClock.time
            return true
        end
        for _, pred in pairs(qPred) do
            if pred then
                myHero.spellbook:CastSpell(0, self:GetCastPosition(pred))
                self.LastCasts["Q"] = RiotClock.time
                return true
            end
        end
    end
end

function Ezreal:OnTick()
    if not Orbwalker:IsAttacking() then
        if self.menu.r:get() and myHero.spellbook:CanUseSpell(3) == 0 then
            local rTarget, rPred = self:GetTarget(self.r)
            if rTarget and rPred and rPred.rates["very slow"] then
                myHero.spellbook:CastSpell(3, self:GetCastPosition(rPred))
                self.LastCasts["R"] = RiotClock.time
                return
            end
        end
        if Orbwalker:GetMode() == "Combo" then
            if self.menu.user:get() and myHero.spellbook:CanUseSpell(3) == 0 then
                local rTarget, rPred =
                    self:GetTarget(
                    self.r,
                    false,
                    nil,
                    function(unit, pred)
                        return pred:heroCollision(2) or _G.Prediction.IsImmobile(unit, pred.interceptionTime)
                    end
                )
                if rTarget and rPred and rPred.rates["very slow"] then
                    myHero.spellbook:CastSpell(3, self:GetCastPosition(rPred))
                    self.LastCasts["R"] = RiotClock.time
                    return
                end
            end
            if myHero.spellbook:CanUseSpell(1) == 0 then
                local wTarget, wPred = self:GetTarget(self.w)
                if wTarget and wPred and wPred.rates["very slow"] then
                    myHero.spellbook:CastSpell(1, self:GetCastPosition(wPred))
                    self.LastCasts["W"] = RiotClock.time
                    return
                end
            end
            if self:CastQ() then
                return
            end
        elseif self.menu.q:get() and not _G.Prediction.IsRecalling(myHero) then
            if self:CastQ() then
                return
            end
        end
    end
end

function Ezreal:OnBuffGain(obj, buff)
    if obj and obj.team ~= myHero.team and obj.type == myHero.type and buff.name == "ezrealwattach" then
        self.wBuffTarget = obj
        Orbwalker:ForceTarget(obj)
    end
end

function Ezreal:OnBuffLost(obj, buff)
    if obj and obj.team ~= myHero.team and obj.type == myHero.type and buff.name == "ezrealwattach" then
        self.wBuffTarget = nil
        Orbwalker:ResetForcedTarget()
    end
end

function Ezreal:Hex(a, r, g, b)
    return string.format("0x%.2X%.2X%.2X%.2X", a, r, g, b)
end

function Ezreal:GetTarget(spell, all, targetFilter, predFilter)
    local units, preds = self.TS:GetTargets(spell, myHero.position, targetFilter, predFilter)
    if all then
        return units, preds
    else
        local target = self.TS.target
        if target then
            return target, preds[target.networkId]
        end
    end
end

function Ezreal:OnExecuteCastFrame(obj, spell)
    if obj == myHero then
        if spell.spellData.name == "EzrealQ" then
            self.LastCasts.Q = nil
        elseif spell.spellData.name == "EzrealW" then
            self.LastCasts.W = nil
        elseif spell.spellData.name == "EzrealE" then
            self.LastCasts.E = nil
        elseif spell.spellData.name == "EzrealR" then
            self.LastCasts.R = nil
        end
    end
end

if myHero.charName == "Ezreal" then
    Ezreal:__init()
end

local Ezreal = {}
local version = 3

GetInternalWebResultAsync(
    "asdfezreal.version",
    function(v)
        if tonumber(v) > version then
            DownloadInternalFileAsync(
                "asdfezreal.lua",
                SCRIPT_PATH,
                function(success)
                    if success then
                        --PrintChat("Updated. Press F5")
                    end
                end
            )
        end
    end
)
require "FF15Menu"
require "utils"
local DreamTS = require("DreamTS")
local dmgLib = require("FF15DamageLib")
local Orbwalker = require "FF15OL"

function OnLoad()
    if not _G.Prediction then
        LoadPaidScript(PaidScript.DREAM_PRED)
    end
end

function Ezreal:__init()
    self.turrets = {}
    for i, turret in pairs(ObjectManager:GetEnemyTurrets()) do
        self.turrets[turret.networkId] = {object = turret, range = 775 + 25}
    end
    self.orbSetup = false
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
        Events.OnProcessSpell,
        function(...)
            self:OnProcessSpell(...)
        end
    )
    AddEvent(
        Events.OnExecuteCastFrame,
        function(...)
            self:OnExecuteCastFrame(...)
        end
    )
    AddEvent(
        Events.OnDeleteObject,
        function(obj)
            self:OnDeleteObject(obj)
        end
    )
    --PrintChat("Ezreal loaded")
    self.font = DrawHandler:CreateFont("Calibri", 10)
end

function Ezreal:Menu()
    self.menu = Menu("asdfezreal", "Ezreal")
    self.menu:sub("dreamTs", "Target Selector")
    self.menu:checkbox("w", "Check W for AA or possible Q ", true)
    self.menu:checkbox("q", "AutoQ", true, string.byte("T"))
    self.menu:checkbox("user", "Use R", true)
    self.menu:key("r", "Manual R Key", 0x5A)
end

function Ezreal:OnDraw()
    DrawHandler:Circle3D(
        myHero.position,
        self.q.range,
        (self.orbSetup and Orbwalker:GetMode() == "Combo") and Color.Red or Color.White
    )
    local text = self.menu.q:get() and "AutoQ on" or "AutoQ off"
    DrawHandler:Text(DrawHandler.defaultFont, Renderer:WorldToScreen(myHero.position), text, Color.White)
end

function Ezreal:ShouldCast()
    for spell, time in pairs(self.LastCasts) do
        if time and RiotClock.time < time then
            return false
        end
    end

    return true
end

function Ezreal:DynamicRange(pred, target, spell)
    local distToPosition = GetDistance(target)
    local distToCast = GetDistance(pred.castPosition)
    if distToPosition <= distToCast then
        return true
    end
    if
        distToPosition + (distToPosition - distToCast) * (pred.interceptionTime - spell.delay - NetClient.ping / 2000 - 0.07) / pred.interceptionTime <
            spell.range
     then
        return true
    end
end

function Ezreal:GetCastPosition(pred)
    pred:draw()
    return pred.castPosition
end

function Ezreal:CastQ(isCombo)
    if myHero.spellbook:CanUseSpell(0) == 0 then
        if not isCombo then
            for i, turret in pairs(self.turrets) do
                local turretObj = turret.object
                if
                    turretObj and turretObj.isValid and turretObj.health > 0 and
                        GetDistanceSqr(turretObj) <= turret.range * turret.range
                 then
                    return
                end
            end
        end
        local qTargets, qPred = self:GetTarget(self.q, true)
        if self.wBuffTarget and qPred[self.wBuffTarget.networkId] then
            if qPred[self.wBuffTarget.networkId].rates["slow"] then
                if self:DynamicRange(qPred[self.wBuffTarget.networkId], self.wBuffTarget, self.q) then
                    myHero.spellbook:CastSpellFast(0, self:GetCastPosition(qPred[self.wBuffTarget.networkId]))
                    self.LastCasts["Q"] = RiotClock.time + 0.25 + NetClient.ping / 2000 + 0.07
                    return true
                end
            end
            return
        end
        for _, target in pairs(qTargets) do
            if qPred[target.networkId] then
                local pred = qPred[target.networkId]
                if pred.rates["slow"] and self:DynamicRange(pred, target, self.q) then
                    myHero.spellbook:CastSpellFast(0, self:GetCastPosition(pred))
                    self.LastCasts["Q"] = RiotClock.time + 0.25 + NetClient.ping / 2000 + 0.07
                    return true
                end
                return
            end
        end
    end
end

function Ezreal:OnTick()
    if not self.orbSetup and (_G.AuroraOrb or _G.LegitOrbwalker) then
        Orbwalker:Setup()
        self.orbSetup = true
    end
    if
        self.orbSetup and not Orbwalker:IsAttacking() and
            not (_G.JustEvade and _G.JustEvade.Loaded() and _G.JustEvade.Evading()) and self:ShouldCast()
     then
        if self.menu.r:get() and myHero.spellbook:CanUseSpell(3) == 0 then
            local rTarget, rPred = self:GetTarget(self.r)
            if rTarget and rPred and rPred.rates["slow"] then
                myHero.spellbook:CastSpellFast(3, self:GetCastPosition(rPred))
                self.LastCasts["R"] = RiotClock.time + 1 + NetClient.ping / 2000 + 0.07
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
                if rTarget and rPred and rPred.rates["slow"] then
                    myHero.spellbook:CastSpellFast(3, self:GetCastPosition(rPred))
                    self.LastCasts["R"] = RiotClock.time + 1 + NetClient.ping / 2000 + 0.07
                    return
                end
            end
            if myHero.spellbook:CanUseSpell(1) == 0 then
                local wTarget, wPred = self:GetTarget(self.w)
                if wTarget and wPred and wPred.rates["slow"] and self:DynamicRange(wPred, wTarget, self.w) then
                    if self.menu.w:get() then
                        local pred = _G.Prediction.GetPrediction(wTarget, self.q, myHero)
                        local aa = myHero.characterIntermediate.attackRange + myHero.boundingRadius
                        if
                            (myHero.spellbook:CanUseSpell(0) == 0 and pred) or
                                GetDistanceSqr(wTarget.position, myHero.position) <= aa * aa
                         then
                            myHero.spellbook:CastSpellFast(1, self:GetCastPosition(wPred))
                            self.LastCasts["W"] = RiotClock.time + 0.25 + NetClient.ping / 2000 + 0.07
                            --PrintChat('wcast')
                            return
                        end
                    else
                        myHero.spellbook:CastSpellFast(1, self:GetCastPosition(wPred))
                        self.LastCasts["W"] = RiotClock.time + 0.25 + NetClient.ping / 2000 + 0.07
                        --PrintChat('wcast')

                        return
                    end
                end
            end
            if self:CastQ(true) then
                --PrintChat('qcast')

                return
            end
        elseif self.menu.q:get() then
            if self:CastQ() then
                --PrintChat('qcast')
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

function Ezreal:OnProcessSpell(obj, spell)
    if obj == myHero then
        if spell.spellData.name == "EzrealQ" then
            --PrintChat("qproc")
            self.LastCasts.Q = RiotClock.time + 0.25
        elseif spell.spellData.name == "EzrealW" then
            --PrintChat("wproc")
            self.LastCasts.W = RiotClock.time + 0.25
        elseif spell.spellData.name == "EzrealE" then
            self.LastCasts.E = RiotClock.time + 0.75
            --PrintChat("eproc")

        elseif spell.spellData.name == "EzrealR" then
            self.LastCasts.R = RiotClock.time + 1
            --PrintChat("rproc")

        end
    end
end

function Ezreal:OnExecuteCastFrame(obj, spell)
    if obj == myHero then
        if spell.spellData.name == "EzrealQ" then
            --PrintChat("qexe")
            self.LastCasts.Q = nil
        elseif spell.spellData.name == "EzrealW" then
            --PrintChat("wexe")
            self.LastCasts.W = nil
        elseif spell.spellData.name == "EzrealE" then
            --PrintChat("eexe")
            self.LastCasts.E = nil
        elseif spell.spellData.name == "EzrealR" then
            --PrintChat("rexe")
            self.LastCasts.R = nil
        end
    end
end

function Ezreal:OnDeleteObject(obj)
    if self.turrets[obj.networkId] then
        self.turrets[obj.networkId] = nil
    end
end

if myHero.charName == "Ezreal" then
    Ezreal:__init()
end

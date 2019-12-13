local Aphelios = {}
local version = 1

--[[ GetInternalWebResultAsync("asdfaphelios.version", function(v)
    if tonumber(v) > version then
        DownloadInternalFileAsync("asdfaphelios.lua", SCRIPT_PATH, function (success) 
            if success then
                PrintChat("Updated. Press F5")
            end
        end
    )
    end
end
) ]]
require "FF15Menu"
require "utils"
local Vector
local Circle = require("BestAOEPos").Circle
local DreamTS = require("DreamTS")
local dmgLib = require("FF15DamageLib")
local Orbwalker = require "FF15OL"

function OnLoad()
    if not _G.Prediction then
        LoadPaidScript(PaidScript.DREAM_PRED)
        Vector = _G.Prediction.Vector
    end

    function Vector:angleBetweenFull(v1, v2)
        local p1, p2 = (-self + v1), (-self + v2)
        local theta = p1:polar() - p2:polar()
        if theta < 0 then
            theta = theta + 360
        end
        return theta
    end
end

function Aphelios:__init()
    self.orbSetup = false
    self.calibrumQ = {
        type = "linear",
        speed = 1800,
        range = 1350, --1450
        delay = 0.35,
        width = 120,
        collision = {
            ["Wall"] = true,
            ["Hero"] = true,
            ["Minion"] = true
        }
    }
    self.infernumQ = {
        type = "linear",
        delay = 0.4,
        range = 600,
        speed = math.huge,
        width = 0,
        angle = 45
    }
    self.crescendumQ = {
        aaRange = 530,
        delay = 0.25,
        range = 475
    }
    self.r = {
        type = "linear",
        speed = 2050,
        range = 1500,
        delay = 0.5,
        width = 250,
        collision = {
            ["Wall"] = true,
            ["Hero"] = true,
            ["Minion"] = false
        },
        explosionRadius = 350
    }
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
        Events.OnBuffGain,
        function(obj, buff)
            self:OnBuffGain(obj, buff)
        end
    )
    PrintChat("Aphelios loaded")
    self.font = DrawHandler:CreateFont("Calibri", 10)
end

function Aphelios:Menu()
    self.menu = Menu("asdfaphelios", "Aphelios")
    self.menu:sub("dreamTs", "Target Selector")
    self.menu:key("r", "Manual R Key", 0x5A)
end

function Aphelios:OnDraw()
end

function Aphelios:ShouldCast()
    for spell, time in pairs(self.LastCasts) do
        if time and RiotClock.time < time + 0.25 + NetClient.ping / 2000 + 0.06 then
            return false
        end
    end

    return true
end

function Aphelios:CalibrumQ()
    if myHero.spellbook:CanUseSpell(0) == 0 then
        local qTarget, qPred =
            self:GetTarget(
            self.calibrumQ,
            false,
            nil,
            function(unit, pred)
                return pred.rates["very slow"]
            end
        )
        if qTarget and qPred and not qTarget.buffManager:HasBuff("aphelioscalibrumbonusrangedebuff") then
            qPred:draw()
            myHero.spellbook:CastSpell(0, qPred.castPosition)
            return true
        end
    end
end

function Aphelios:CalibrumAuto()
    if Orbwalker:CanAttack() and not Orbwalker:IsAttacking() then
        local aa = myHero.characterIntermediate.attackRange
        local target =
            self:GetTargetAuto(
            function(unit)
                local dist = aa + unit.boundingRadius
                return GetDistanceSqr(unit, myHero) <= dist * dist or
                    unit.buffManager:HasBuff("aphelioscalibrumbonusrangedebuff")
            end,
            false
        )
        if target then
            Orbwalker:Attack(target)
        end
    end
end

function Aphelios:SevernumQ()
    if myHero.spellbook:CanUseSpell(0) == 0 then
        local aa = myHero.characterIntermediate.attackRange
        local target =
            self:GetTargetAuto(
            function(unit)
                local dist = aa + unit.boundingRadius
                return GetDistanceSqr(unit, myHero) <= dist * dist
            end,
            false
        )
        if target then
            myHero.spellbook:CastSpell(0, pwHud.hudManager.activeVirtualCursorPos)
        end
    end
end

function Aphelios:GravitumAuto()
    if myHero.spellbook:CanUseSpell(0) == 0 and Orbwalker:CanAttack() and not Orbwalker:IsAttacking() then
        local aa = myHero.characterIntermediate.attackRange
        local target =
            self:GetTargetAuto(
            function(unit)
                local dist = aa + unit.boundingRadius
                return GetDistanceSqr(unit, myHero) <= dist * dist and
                    unit.buffManager:HasBuff("aphelioscalibrumbonusrangedebuff") --[[ or
                    not unit.buffManager:HasBuff("ApheliosGravitumDebuff") ]]
            end,
            false
        )
        if target then
            Orbwalker:Attack(target)
        end
    end
end

function Aphelios:CalcBestCastAngle(angles)
    local maxCount = 0
    local maxStart = nil
    local maxEnd = nil
    for i = 1, #angles do
        local base = angles[i]
        local endAngle = base + self.infernumQ.angle
        local over360 = endAngle > 360
        if over360 then
            endAngle = endAngle - 360
        end
        local function isContained(count, angle, base, over360, endAngle)
            if angle == base and count ~= 0 then
                return
            end
            if not over360 then
                if angle <= endAngle and angle >= base then
                    return true
                end
            else
                if angle > base and angle <= 360 then
                    return true
                elseif angle <= endAngle and angle < base then
                    return true
                end
            end
        end
        local angle = base
        local j = i
        local count = 0
        local endDelta = angle
        while (isContained(count, angle, base, over360, endAngle)) do
            endDelta = angles[j]
            count = count + 1
            j = j + 1
            if j > #angles then
                j = 1
            end
            angle = angles[j]
        end
        if count > maxCount then
            maxCount = count
            maxStart = base
            maxEnd = endDelta
        end
    end
    if maxStart and maxEnd then
        if maxStart + self.infernumQ.angle > 360 then
            maxEnd = maxEnd + 360
        end
        local res = (maxStart + maxEnd) / 2
        if res > 360 then
            res = res - 360
        end
        return math.rad(res)
    end
end

function Aphelios:InfernumQ()
    if myHero.spellbook:CanUseSpell(0) == 0 then
        local qTargets, qPreds = self:GetTarget(self.infernumQ, true)
        local angles = {}
        local basePosition = nil
        for _, pred in pairs(qPreds) do
            if not basePosition then
                angles[1] = 0
                basePosition = pred.castPosition
            else
                angles[#angles + 1] =
                    Vector(myHero.position):angleBetweenFull(Vector(basePosition), Vector(pred.castPosition))
            end
        end
        local best = self:CalcBestCastAngle(angles)
        if best then
            local castPosition =
                (Vector(myHero.position) +
                (Vector(basePosition) - Vector(myHero.position)):rotated(0, best, 0):normalized() * (self.infernumQ.range - 10)):toDX3()
            myHero.spellbook:CastSpell(0, castPosition)
        end
    end
end

function Aphelios:CrescendumQ()
    if myHero.spellbook:CanUseSpell(0) == 0 then
        local targets =
            self:GetTargetAuto(
            function(unit)
                return GetDistanceSqr(unit, myHero) <= 1000 * 1000
            end,
            true
        )
        if targets then
            local points = {}
            for _, target in pairs(targets) do
                points[#points + 1] =
                    _G.Prediction.GetUnitPosition(target, 0.06 + NetClient.ping / 1000 + self.crescendumQ.delay)
            end
            local res = Circle(self.crescendumQ.aaRange + self.crescendumQ.range, self.crescendumQ.range, points)
            print(res.hits)
            if res.hits > 1 or res.hits == 1 and GetDistanceSqr(res.castPos) <= 250 * 250 then
                myHero.spellbook:CastSpell(0, res.castPos)
            end
        end
    end
end

function Aphelios:CastR()
    if myHero.spellbook:CanUseSpell(0) == 0 then
        local rTargets, rPreds =
            self:GetTarget(
            self.r,
            true,
            nil,
            function(unit, pred)
                return pred.rates["slow"]
            end
        )
        local maxTarget = nil
        local maxHit = 0
        for _, target in pairs(rTargets) do
            local pred = rPreds[target.networkId]
            if pred then
                local hit = 0
                for _, target2 in pairs(rTargets) do
                    if
                        target == target2 or
                            GetDistanceSqr(
                                _G.Prediction.GetUnitPosition(
                                    target2,
                                    NetClient.ping / 1000 + 0.06 + pred.interceptionTime
                                ),
                                pred.castPosition
                            ) <=
                                self.r.explosionRadius * self.r.explosionRadius
                     then
                        hit = hit + 1
                    end
                end
                if hit > maxHit then
                    maxTarget = target
                    maxHit = hit
                end
            end
        end
        if maxTarget then
            myHero.spellbook:CastSpell(3, rPreds[maxTarget.networkId].castPosition)
        end
    end
end

function Aphelios:OnTick()
    if not self.orbSetup and (_G.AuroraOrb or _G.LegitOrbwalker) then
        Orbwalker:Setup()
        self.orbSetup = true
    end
    if self.orbSetup and not Orbwalker:IsAttacking() then
        if self.menu.r:get() then
            self:CastR()
        end
        if Orbwalker:GetMode() == "Combo" then
            local qName = myHero.spellbook:Spell(0).name
            if qName == "ApheliosCalibrumQ" then
                self:CalibrumQ()
                self:CalibrumAuto()
            elseif qName == "ApheliosSeverumQ" then
                self:SevernumQ()
                self:CalibrumAuto()
            elseif qName == "ApheliosGravitumQ" then
                self:GravitumAuto()
            elseif qName == "ApheliosInfernumQ" then
                self:InfernumQ()
                self:CalibrumAuto()
            elseif qName == "ApheliosCrescendumQ" then
                self:CrescendumQ()
                self:CalibrumAuto()
            end
        end
    end
end

function Aphelios:OnBuffGain(obj, buff)
    if obj ~= myHero then
        print(buff.name)
    end
end

function Aphelios:GetTarget(spell, all, targetFilter, predFilter)
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

function Aphelios:GetTargetAuto(targetFilter, all)
    local res =
        self.TS:update(
        function(unit)
            return _G.Prediction.IsValidTarget(unit) and targetFilter(unit)
        end
    )
    if all then
        return res
    else
        if res and res[1] then
            return res[1]
        end
    end
end

if myHero.charName == "Aphelios" then
    Aphelios:__init()
end

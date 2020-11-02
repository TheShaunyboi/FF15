local function class()
    return setmetatable(
        {},
        {
            __call = function(self, ...)
                local result = setmetatable({}, {__index = self})
                result:__init(...)

                return result
            end
        }
    )
end

local Yone = class()
Yone.version = 1

require("FF15Menu")
require("utils")
local DreamTS = require("DreamTS")
local dmgLib = require("FF15DamageLib")

local Orbwalker = require("ModernUOL")
local Vector = require("GeometryLib").Vector

function Yone:__init()
    self.active_buffs = {}
    self.q = {
        type = "linear",
        speed = math.huge,
        range = 450, --edge range,
        delay = 0.35,
        width = 80
    }
    self.q3 = {
        type = "linear",
        speed = 1500,
        range = 950,
        delay = 0.35,
        width = 190,
        shortWidth = 190,
        longWidth = 160
    }
    self.w = {
        type = "cone",
        speed = math.huge,
        range = 600, --edge range
        delay = 0.5,
        angle = 80
    }
    self.e = {
        type = "linear",
        range = 1000,
        delay = 0.25,
        width = 120,
        speed = 1400,
        collision = {
            ["Wall"] = true,
            ["Hero"] = true,
            ["Minion"] = true
        }
    }
    self.r = {
        type = "linear",
        speed = math.huge,
        range = 1000,
        delay = 0.75,
        width = 225
    }
    self.LastCasts = {
        Q1 = nil,
        Q2 = nil,
        W = nil,
        E = nil,
        R = nil
    }

    self.shadow = nil
    self.mark = nil
    self.death = false
    self.font = DrawHandler:CreateFont("Calibri", 25)
    self:Menu()
    self.TS =
        DreamTS(
        self.menu.dreamTs,
        {
            Damage = DreamTS.Damages.AP
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
        Events.OnProcessSpell,
        function(...)
            self:OnProcessSpell(...)
        end
    )
    AddEvent(
        Events.OnCreateObject,
        function(...)
            self:OnCreateObject(...)
        end
    )
    AddEvent(
        Events.OnDeleteObject,
        function(...)
            self:OnDeleteObject(...)
        end
    )
    AddEvent(
        Events.OnExecuteCastFrame,
        function(...)
            self:OnExecuteCastFrame(...)
        end
    )
    AddEvent(
        Events.OnSpellbookCastSpell,
        function(...)
            self:OnSpellbookCastSpell(...)
        end
    )
    PrintChat("Yone loaded")
end

function Yone:Menu()
    self.menu = Menu("YoneEmpyrean", "Yone - Empyrean v" .. self.version)
    self.menu:sub("dreamTs", "Target Selector")
    self.menu:key("r", "Use semi manual R", string.byte("T"))
end

function Yone:OnDraw()
    DrawHandler:Circle3D(myHero.position, 1000, Color.White)
    if self.shadow and self.mark then
        DrawHandler:Text(
            self.font,
            Renderer:WorldToScreen(D3DXVECTOR3(myHero.x - 100, myHero.y + 800, myHero.z)),
            "Enemy Killable with E",
            Color.Red
        )
    end
end

function Yone:CastQ()
    if myHero.spellbook:Spell(0).name == "YoneQ3" then
        return
    end
    local qTarget, qPred =
        self.TS:GetTarget(
        self.q,
        myHero,
        function(unit)
            return GetDistanceSqr(unit) <= (self.q.range + unit.boundingRadius) ^ 2
        end
    )
    if qTarget and qPred then
        myHero.spellbook:CastSpell(0, qPred.castPosition)
        qPred:draw()
        return true
    end
end

function Yone:CastQ3()
    if myHero.spellbook:Spell(0).name ~= "YoneQ3" then
        return
    end
    self.q3.width = self.q3.longWidth
    local qTarget, qPred =
        self.TS:GetTarget(
        self.q3,
        myHero,
        function(unit)
            return GetDistanceSqr(unit) <= (self.q3.range + unit.boundingRadius) ^ 2
        end
    )
    if qTarget and qPred and qPred.rates["slow"] then
        local distSqr = GetDistanceSqr(qPred.targetPosition)
        if distSqr <= 450 ^ 2 then
            self.q3.width = self.q3.shortWidth
            qTarget, qPred =
                self.TS:GetTarget(
                self.q3,
                myHero,
                function(unit)
                    return GetDistanceSqr(unit) <= (self.q3.range + unit.boundingRadius) ^ 2
                end
            )
            if qTarget and qPred then
                myHero.spellbook:CastSpell(0, qPred.castPosition)
                qPred:draw()
                return true
            end
        else
            myHero.spellbook:CastSpell(0, qPred.castPosition)
            qPred:draw()
            return true
        end
    end
end

function Yone:CastW()
    local wTarget, wPred =
        self.TS:GetTarget(
        self.w,
        myHero,
        function(unit)
            return GetDistanceSqr(unit) <= (self.w.range - 50) ^ 2
        end
    )
    if wTarget and wPred then
        myHero.spellbook:CastSpell(1, wPred.castPosition)
        wPred:draw()
        return true
    end
end

function Yone:ManualR()
    local rTarget, rPred =
        self.TS:GetTarget(
        self.r,
        myHero,
        function(unit)
            return GetDistanceSqr(unit) <= (self.r.range + unit.boundingRadius) ^ 2
        end
    )
    if rTarget and rPred and rPred.rates["slow"] then
        myHero.spellbook:CastSpell(3, rPred.castPosition)
        rPred:draw()
        return true
    end
end

function Yone:TotalAD(obj)
    local obj = obj or myHero
    return obj.characterIntermediate.flatPhysicalDamageMod + obj.characterIntermediate.baseAttackDamage
end

function Yone:qDmg(target)
    local qDamage = 20 * myHero.spellbook:Spell(0).level + self:TotalAD()
    return dmgLib:CalculatePhysicalDamage(myHero, target, qDamage)
end

function Yone:GetAARange(target)
    return myHero.characterIntermediate.attackRange + myHero.boundingRadius + (target and target.boundingRadius or 0)
end

function Yone:LastHit()
    if myHero.spellbook:Spell(0).name == "YoneQ" then
        local minions = ObjectManager:GetEnemyMinions()
        -- if _G.LegitOrbwalker then
        --     minions = _G.LegitOrbwalker.SpellFarm()
        -- end
        -- print(#minions)
        for i, minion in ipairs(minions) do
            if
                minion and minion.isVisible and minion.characterIntermediate.movementSpeed > 0 and minion.isTargetable and
                    not minion.isDead and
                    minion.maxHealth > 5 and
                    Orbwalker:GetCurrentTarget() ~= minion and
                    GetDistanceSqr(minion) <= (self.q.range + minion.boundingRadius) ^ 2 and
                    (not Orbwalker:CanAttack() or (self:GetAARange() < GetDistance(minion)))
             then
                local dmg = self:qDmg(minion)
                if dmg > minion.health and Orbwalker:HpPred(minion, self.q.delay) > 0 then
                    local pred = _G.Prediction.GetPrediction(minion, self.q)
                    if pred and pred.castPosition then
                        myHero.spellbook:CastSpell(0, pred.castPosition)
                    end
                end
            end
        end
    end
end

function Yone:UpdateSpellDelays()
    local Q1_MAX_WINDUP = 0.35
    local Q1_MIN_WINDUP = 0.175
    local LOSS_WINDUP_PER_ATTACK_SPEED = (0.35 - 0.3325) / 0.12

    local additional_attack_speed = (myHero.characterIntermediate.attackSpeedMod - 1)
    local q1_delay = math.max(Q1_MIN_WINDUP, Q1_MAX_WINDUP - (additional_attack_speed * LOSS_WINDUP_PER_ATTACK_SPEED))
    self.q.delay = q1_delay
    self.q3.delay = q1_delay
    self.w.delay = (0.5 * (1 - math.min((myHero.characterIntermediate.attackSpeedMod - 1) * 0.58, 0.66)))
end

function Yone:MultiR()
    local rTargets, rPreds =
        self.TS:GetTargets(
        self.r,
        myHero,
        function(unit)
            return GetDistanceSqr(unit) <= (self.r.range + unit.boundingRadius) ^ 2
        end
    )
    local bestCount, bestObj, bestPred = 2, nil, nil
    for _, enemy in pairs(rTargets) do
        count = 0
        pred = rPreds[enemy.networkId]
        if pred then
            for _, enemy2 in pairs(rTargets) do
                local col = _G.Prediction.IsCollision(self.r, myHero.position, pred.castPosition, enemy2)
                if col then
                    count = count + 1
                end
            end
            if count > bestCount then
                bestCount = count
                bestObj = enemy
                bestPred = pred
            end
        end
    end
    if bestObj then
        myHero.spellbook:CastSpell(3, bestPred.castPosition)
    end
end

function Yone:OnTick()
    self:UpdateSpellDelays()
    if myHero.dead then
        return
    end

    local ComboMode = Orbwalker:GetMode() == "Combo" and not Orbwalker:IsAttacking()
    local LastHit = Orbwalker:GetMode() == "Lasthit" and not Orbwalker:IsAttacking()

    local q = myHero.spellbook:CanUseSpell(SpellSlot.Q) == 0
    local w = myHero.spellbook:CanUseSpell(SpellSlot.W) == 0
    local e = myHero.spellbook:CanUseSpell(SpellSlot.E) == 0
    local r = myHero.spellbook:CanUseSpell(SpellSlot.R) == 0
    if self.menu.r:get() and r and self:ManualR() then
    end
    if ComboMode then
        if (r and self:MultiR()) or (q and (self:CastQ() or self:CastQ3())) or (w and self:CastW()) then
            return
        end
    else
        if q and LastHit then
            self:LastHit()
        end
    end
end

function Yone:OnCreateObject(obj)
    if obj.team == myHero.team and obj.name:lower():find("testcuberender10vision") then
        self.shadow = obj
    end
    if obj.name:lower():find("yone") and obj.name:lower():find("mark_execute") then
        self.mark = obj
        self.death = true
    end
end

function Yone:OnDeleteObject(obj)
    if obj.team == myHero.team and obj.name:lower():find("testcuberender10vision") then
        self.shadow = nil
    end
    if obj.name:lower():find("yone") and obj.name:lower():find("mark_execute") then
        self.mark = nil
        self.death = false
    end
end

function Yone:OnProcessSpell(obj, spell)
end

function Yone:OnExecuteCastFrame(obj, spell)
end

function Yone:OnSpellbookCastSpell(slot, startPos, endPos, target)
end

return Yone

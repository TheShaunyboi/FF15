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

local Irelia = class()
Irelia.version = 1.2
local passiveBaseScale = {15, 18, 21, 24, 27, 30, 33, 36, 39, 42, 45, 48, 51, 54, 57, 60, 63, 66}
local sheenTimer = os.clock()

require("FF15Menu")
require("utils")
local DreamTS = require("DreamTS")
local dmgLib = require("FF15DamageLib")
local Orbwalker = require "ModernUOL"
local Vector
local LineSegment = require("GeometryLib").LineSegment
local Polygon = require("GeometryLib").Polygon

function Irelia:__init()
    Vector = _G.Prediction.Vector
    self.last = {
        q = nil,
        w = nil,
        e1 = nil,
        e2 = nil,
        r = nil
    }
    self.blade = nil
    self.e = {
        type = "linear",
        speed = math.huge,
        range = 775,
        delay = 0.35,
        width = 135,
        missileSpeed = 2000,
        collision = {
            ["Wall"] = true,
            ["Hero"] = false,
            ["Minion"] = false
        },
        useHeroSource = true
    }
    self.qRange = 600
    self.eTest = {
        type = "circular",
        speed = math.huge,
        range = 3000,
        delay = 0.35,
        radius = 0
    }
    self.turrets = {}
    for i, turret in pairs(ObjectManager:GetEnemyTurrets()) do
        self.turrets[turret.networkId] = {object = turret, range = 775 + 25}
    end
    self.cage = nil
    self.r = {
        type = "linear",
        speed = 2000,
        range = 1000,
        delay = 0.4,
        width = 315,
        collision = {
            ["Wall"] = true,
            ["Hero"] = false,
            ["Minion"] = false
        }
    }
    self.rCheck = {
        type = "circular",
        speed = math.huge,
        range = math.huge,
        delay = 0,
        radius = 0
    }
    self.f = {
        dist = 400,
        slot = nil
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
        Events.OnExecuteCastFrame,
        function(...)
            self:OnExecuteCastFrame(...)
        end
    )
    AddEvent(
        Events.OnCreateObject,
        function(...)
            self:OnCreateObj(...)
        end
    )
    AddEvent(
        Events.OnDeleteObject,
        function(...)
            self:OnDeleteObj(...)
        end
    )
    AddEvent(
        Events.OnBuffLost,
        function(...)
            self:OnBuffLost(...)
        end
    )
    PrintChat(
        '<font color="#1CCD00">[<b>¤ Empyrean ¤</b>]:</font>' ..
            ' <font color="#' .. "FFFFFF" .. '">' .. "Irelia Loaded" .. "</font>"
    )
    self.font = DrawHandler:CreateFont("Calibri", 10)
end

function Irelia:Menu()
    self.menu = Menu("IreliaEmpyrean", "Irelia - Empyrean v" .. self.version)
    self.menu:sub("dreamTs", "Target Selector")
    self.menu:key("manual", "Semi-manual R aim", string.byte("R"))
    self.menu:key("rFlash", "Semi-manual R + R Flash aim", string.byte("T"))
    self.menu:key("e", "E key (no E in combo)", string.byte("E"))
    --self.menu:key("q", "Q to nearest champion to mouse", string.byte("Q"))
    self.menu:sub("draws", "Draw")
    self.menu.draws:checkbox("q", "Q", true)
    self.menu.draws:checkbox("e", "E", true)
    self.menu.draws:checkbox("r", "R", true)
end

function Irelia:ShouldCast()
    for spell, time in pairs(self.last) do
        if time and RiotClock.time < time + 0.35 + _G.Prediction.GetInternalDelay() then
            return false
        end
    end

    return true
end

function Irelia:ValidTarget(object, distance)
    return object and object.isValid and object.team ~= myHero.team and
        not object.buffManager:HasBuff("SionPassiveZombie") and
        not object.buffManager:HasBuff("FioraW") and
        not object.buffManager:HasBuff("sivire") and
        not object.buffManager:HasBuff("nocturneshroudofdarkness") and
        not object.isDead and
        not object.isInvulnerable and
        (not distance or self:GetDistanceSqr(object) <= distance * distance)
end

function Irelia:GetBonusAD(obj)
    local obj = obj or myHero
    return (obj.characterIntermediate.flatPhysicalDamageMod)
end

function Irelia:GetTotalAD(obj)
    local obj = obj or myHero
    return obj.characterIntermediate.flatPhysicalDamageMod + obj.characterIntermediate.baseAttackDamage
end

function Irelia:GetShieldedHealth(damageType, target)
    local shield = 0
    if damageType == "AD" then
        shield = target.attackShield
    elseif damageType == "AP" then
        shield = target.magicalShield
    elseif damageType == "ALL" then
        shield = target.allShield
    end
    return target.health + shield
end

function Irelia:UnderTurret(unit)
    if not unit or unit.isDead or not unit.isVisible or not unit.isTargetable then
        return true
    end
    for i, obj in ipairs(ObjectManager:GetEnemyTurrets()) do
        if obj and obj.health and obj.health > 0 and GetDistanceSqr(obj, unit) <= 900 ^ 2 then
            return true
        end
    end
    return false
end
function Irelia:MoveToMouse()
    local pos = pwHud.hudManager.virtualCursorPos
    myHero:IssueOrder(GameObjectOrder.MoveTo, pos)
end

local last_item_update = 0
local hasSheen = false
local hasTF = false
local hasBOTRK = false
local hasTitanic = false
local hasWitsEnd = false
local hasRecurve = false
local hasGuinsoo = false
local QLevelDamage = {5, 25, 45, 65, 85}
local QMLevelDamage = {60, 100, 140, 180, 220}
local WitsEndDamage = {15, 0, 0, 0, 0, 0, 0, 0, 25, 35, 45, 55, 65, 75, 76.25, 77.5, 78.75, 80}
function Irelia:GetQDamage(target)
    if myHero.spellbook:CanUseSpell(0) == 0 then
        local totalPhysical = 0
        local totalMagical = 0
        if os.clock() > last_item_update then
            hasSheen = false
            hasTF = false
            hasBOTRK = false
            hasTitanic = false
            hasWitsEnd = false
            hasRecurve = false
            hasGuinsoo = false
            local item1 = myHero.inventory:HasItem(3057)
            local item2 = myHero.inventory:HasItem(3100)
            local item3 = myHero.inventory:HasItem(3091)
            if item1 and myHero.spellbook:CanUseSpell(item1.spellSlot) == 0 then
                hasSheen = true
            end
            if item2 and myHero.spellbook:CanUseSpell(item2.spellSlot) == 0 then
                hasTF = true
            end
            if item3 and myHero.spellbook:CanUseSpell(item3.spellSlot) == 0 then
                hasWitsEnd = true
            end
            last_item_update = os.clock() + 5
        end

        local onhitPhysical = 0
        local onhitMagical = 0

        if hasTF and (os.clock() >= sheenTimer or myHero.buffManager:HasBuff("sheen")) then
            onhitPhysical = 1.75 * myHero.characterIntermediate.baseAttackDamage
        end
        if hasSheen and not hasTF and (os.clock() >= sheenTimer or myHero.buffManager:HasBuff("sheen")) then
            onhitPhysical = onhitPhysical + myHero.characterIntermediate.baseAttackDamage
        end
        if hasWitsEnd then
            local dmg = WitsEndDamage[myHero.experience.level]
            onhitMagical = onhitMagical + dmg
        end
        if myHero.buffManager:HasBuff("ireliapassivestacksmax") then
            local passiveTotalDmg = ((self:GetBonusAD()) * 0.35) + passiveBaseScale[myHero.experience.level]
            onhitMagical = onhitMagical + passiveTotalDmg
        end

        local damage = 0

        if target.type == GameObjectType.obj_AI_Minion then
            if target.team == 300 then
                damage =
                    dmgLib:CalculatePhysicalDamage(
                    myHero,
                    target,
                    (QLevelDamage[myHero.spellbook:Spell(0).level] + (self:GetTotalAD() * 0.6) + onhitPhysical) +
                        dmgLib:CalculateMagicDamage(target, myHero, onhitMagical)
                )
            elseif target.team ~= myHero.team then
                damage =
                    dmgLib:CalculatePhysicalDamage(
                    myHero,
                    target,
                    (QMLevelDamage[myHero.spellbook:Spell(0).level] + (self:GetTotalAD() * 0.6) + onhitPhysical)
                ) + dmgLib:CalculateMagicDamage(target, myHero, onhitMagical)
            end
        end
        if target.type == GameObjectType.AIHeroClient and target.team ~= myHero.team then
            damage =
                dmgLib:CalculatePhysicalDamage(
                myHero,
                target,
                (QLevelDamage[myHero.spellbook:Spell(0).level] + (self:GetTotalAD() * 0.6) + onhitPhysical)
            ) + dmgLib:CalculateMagicDamage(target, myHero, onhitMagical)
        end
        return damage
    end
    return 0
end

function Irelia:CastQ(target)
    if
        GetDistanceSqr(target) <= (self.qRange * self.qRange) and target.isVisible and self:ValidTarget(target) and
            not target.buffManager:HasBuff("JaxCounterStrike") and
            not target.buffManager:HasBuff("GalioW")
     then
        myHero.spellbook:CastSpellFast(0, target.networkId)
        self.last.q = RiotClock.time
        return true
    end
end

function Irelia:CastQNearest()
    local enemiesInRange = self:GetTargetRange(self.qRange, true)
    local mousePos = pwHud.hudManager.virtualCursorPos
    local closestObj, closestDist = nil, 100000000
    for _, enemy in pairs(enemiesInRange) do
        local distSqr = GetDistanceSqr(enemy)
        if distSqr <= closestDist then
            closestObj, closestDist = enemy, distSqr
        end
    end
    if closestObj then
        myHero.spellbook:CastSpellFast(0, closestObj.networkId)
        self.last.q = RiotClock.time
        return true
    end
end

function Irelia:CanKS(obj)
    if obj.type == GameObjectType.obj_AI_Minion then
        if obj.buffManager:HasBuff("exaltedwithbaronnashorminion") then
            return (self:GetQDamage(obj) * 0.3) > self:GetShieldedHealth("ALL", obj)
        elseif not obj.buffManager:HasBuff("exaltedwithbaronnashorminion") then
            return self:GetQDamage(obj) > self:GetShieldedHealth("ALL", obj)
        end
    end
    if obj.type == GameObjectType.AIHeroClient and obj.team ~= myHero.team then
        return self:GetQDamage(obj) > self:GetShieldedHealth("ALL", obj)
    end
end

function Irelia:GetBestQ()
    local passive = myHero.buffManager:HasBuff("ireliapassivestacksmax")
    local mousePos = pwHud.hudManager.virtualCursorPos
    local origDist = GetDistanceSqr(mousePos)
    local minDistance = GetDistanceSqr(mousePos)
    local minDistObj = nil
    local minDistMinion = nil
    local minionsInRange = ObjectManager:GetEnemyMinions()
    for _, minion in ipairs(minionsInRange) do
        local minionDist = GetDistanceSqr(minion, mousePos)
        if minion and GetDistanceSqr(minion) <= (self.qRange * self.qRange) then
            if self:CanKS(minion) or minion.buffManager:HasBuff("ireliamark") then
                if minionDist < minDistance then
                    minDistance = minionDist
                    minDistMinion = minion
                    minDistObj = minion
                end
            end
        end
    end
    local dist2 = 1000000000
    local enemiesInRange2 = self:GetTargetRange(2500, true)
    for _, enemy in ipairs(enemiesInRange2) do
        local enemyDist = GetDistanceSqr(enemy, mousePos)
        if GetDistanceSqr(enemy) >= self.qRange ^ 2 and enemyDist < dist2 then
            dist2 = enemyDist
        end
    end
    local r = myHero.spellbook:CanUseSpell(3) == 0
    local e = myHero.spellbook:CanUseSpell(2) == 0
    local enemiesInRange = self:GetTargetRange(self.qRange, true)
    for _, enemy in ipairs(enemiesInRange) do
        local enemyDist = GetDistanceSqr(enemy, mousePos)
        if
            (enemy.buffManager:HasBuff("ireliamark") and (passive or not minDistMinion) and
                (GetDistanceSqr(enemy) >
                    (myHero.boundingRadius + enemy.boundingRadius + myHero.characterIntermediate.attackRange) ^ 2 or
                    self:GetShieldedHealth("AD", myHero) <=
                        2 * self:GetQDamage(enemy) + dmgLib:GetAutoAttackDamage(myHero, enemy) or
                    (myHero.health / myHero.maxHealth <= 0.3 and enemy.health > myHero.health) or
                    enemyDist > dist2 or
                    r or
                    e)) or
                self:CanKS(enemy)
         then
            if enemyDist < minDistance then
                minDistance = enemyDist
                minDistObj = enemy
            end
        end
    end
    return minDistObj or nil
end

function Irelia:LastHitQ()
    local minionsInRange = ObjectManager:GetEnemyMinions()
    for i, minion in ipairs(minionsInRange) do
        if
            minion and GetDistanceSqr(minion) <= (self.qRange * self.qRange) and
                GetDistanceSqr(minion, pwHud.hudManager.virtualCursorPos) <= (self.qRange * self.qRange) and
                self:CanKS(minion)
         then
            if self:CastQ(minion) then
                return true
            end
        end
    end
end

function Irelia:KillSteal()
    for i, enemy in ipairs(ObjectManager:GetEnemyHeroes()) do
        if
            enemy and enemy.team ~= myHero.team and not enemy.isInvulnerable and not enemy.isDead and
                not enemy.buffManager:HasBuff("SionPassiveZombie") and
                enemy.isTargetable
         then
            local hp = enemy.health
            local dist = GetDistanceSqr(enemy)
            local q = myHero.spellbook:CanUseSpell(0) == 0
            if q and dist <= (600 * 600) and self:GetQDamage(enemy) > self:GetShieldedHealth("ALL", enemy) then
                self:CastQ(enemy)
            end
        end
    end
end

function Irelia:GetE1Pred(target)
    return _G.Prediction.GetUnitPosition(target, _G.Prediction.GetInternalDelay() + 0.15) --[[ + 0.35 + GetDistance(target) / self.e.missileSpeed
    ) ]]
end

function Irelia:CastE1(check)
    local targets = self:GetTargetRange(self.e.range, true)
    if #targets == 1 then
        local pos = self:GetE1Pred(targets[1])
        if GetDistanceSqr(pos) <= self.e.range ^ 2 then
            if check then
                return 1
            end
            local playerPos = Vector(myHero)
            local castPos = (playerPos + (Vector(pos) - playerPos):normalized() * (self.e.range - 50)):toDX3()
            myHero.spellbook:CastSpellFast(2, castPos)
            self.blade = castPos
            self.last.e1 = RiotClock.time
            return true
        end
    elseif #targets > 1 then
        local pos = {}
        for _, target in pairs(targets) do
            local predPos = self:GetE1Pred(target)
            if GetDistanceSqr(predPos) <= self.e.range * self.e.range then
                pos[target.networkId] = predPos
            end
        end
        local bestCount = 2
        local bestTotalDist = 0
        local bestCast1 = nil
        local bestCast2 = nil
        for i = 1, #targets do
            if pos[targets[i].networkId] then
                local dist1 = GetDistance(pos[targets[i].networkId])
                for j = i + 1, #targets do
                    if pos[targets[j].networkId] then
                        local count = 2
                        local dist2 = GetDistance(pos[targets[j].networkId])
                        local totalDist = dist1 + dist2
                        local seg = LineSegment(Vector(pos[targets[i].networkId]), Vector(pos[targets[j].networkId]))
                        for _, target3 in pairs(targets) do
                            if
                                pos[target3.networkId] and target3.networkId ~= targets[i].networkId and
                                    target3.networkId ~= targets[j].networkId
                             then
                                if
                                    seg:distanceTo(Vector(pos[target3.networkId])) <=
                                        self.e.width + target3.boundingRadius / 2
                                 then
                                    count = count + 1
                                end
                            end
                        end
                        if count > bestCount or (count == bestCount and totalDist > bestTotalDist) then
                            bestCount = count
                            bestTotalDist = totalDist
                            if dist1 > dist2 then
                                bestCast1 = pos[targets[i].networkId]
                                bestCast2 = pos[targets[j].networkId]
                            else
                                bestCast1 = pos[targets[j].networkId]
                                bestCast2 = pos[targets[i].networkId]
                            end
                        end
                    end
                end
            end
        end
        if bestCast1 and bestCast2 then
            if check then
                return bestCount
            end
            local castPos =
                self:RaySetDist(
                Vector(bestCast1),
                (Vector(bestCast1) - Vector(bestCast2)):normalized(),
                Vector(myHero.position),
                self.e.range - 50
            ):toDX3()
            myHero.spellbook:CastSpellFast(2, castPos)
            self.blade = castPos
            self.last.e1 = RiotClock.time
            return true
        end
    end
    if check then
        return 0
    end
end

function Irelia:CheckForSame(list)
    if #list > 2 then
        local last = list[#list]
        for i = #list - 1, 1, -1 do
            if math.abs(last - list[i]) < 0.01 then
                local maxInd = 0
                local maxVal = -math.huge
                for j = i + 1, #list do
                    if list[j] > maxVal then
                        maxInd = j
                        maxVal = list[j]
                    end
                end
                return maxVal
            end
        end
    end
end

function Irelia:RaySetDist(start, path, center, dist)
    local a = start.x - center.x
    local c = start.z - center.z
    local x = path.x
    local z = path.z

    local n1 = a * x + c * z
    local n2 = z ^ 2 * dist ^ 2 - a ^ 2 * z ^ 2 + 2 * a * c * x * z + dist ^ 2 * x ^ 2 - c ^ 2 * x ^ 2
    local n3 = x ^ 2 + z ^ 2

    local r1 = -(n1 + math.sqrt(n2)) / n3
    local r2 = -(n1 - math.sqrt(n2)) / n3
    local r = math.max(r1, r2)

    return start + r * path
end

function Irelia:GetE2CastPos(pred, targets)
    if not pred or not pred.castPosition then
        return
    end
    local count = 0
    local startPos = Vector(self.blade)
    local playerPos = Vector(myHero)
    local endPos =
        self:RaySetDist(startPos, (Vector(pred.castPosition) - startPos):normalized(), playerPos, self.e.range)
    local distSqr = GetDistanceSqr(self.blade, pred.castPosition)
    local seg = LineSegment(startPos, endPos)
    local res = seg:closest(playerPos):toDX3()
    local distSqr2 = GetDistanceSqr(self.blade, closest)
    local limit = GetDistanceSqr(endPos:toDX3(), self.blade)
    if distSqr2 < distSqr then
        distSqr = distSqr2
        res = pred.castPosition
    end
    for _, target in pairs(targets) do
        local seg =
            LineSegment(
            startPos:extended(endPos, -target.boundingRadius),
            endPos:extended(startPos, -target.boundingRadius)
        )
        self.eTest.delay = self.e.delay
        local pred = _G.Prediction.GetPrediction(target, self.eTest)
        if pred and pred.targetPosition then
            local dist = seg:distanceTo(Vector(pred.targetPosition))
            if dist <= self.e.width / 2 + target.boundingRadius then
                count = count + 1
                distSqr2 = GetDistanceSqr(self.blade, pred.targetPosition) ^ 2 - dist ^ 2
                if distSqr2 > distSqr and distSqr2 <= limit then
                    distSqr = distSqr2
                    res = startPos:extended(endPos, math.sqrt(distSqr)):toDX3()
                end
            end
        end
    end
    return res, count
end

function Irelia:CalcE2(target, enemies)
    local dist = GetDistance(target.position)
    self.e.delay = 0.35 + dist / self.e.missileSpeed
    local pred
    local lasts = {}
    local check = nil
    local count = 0
    while not check do
        pred = _G.Prediction.GetPrediction(target, self.e, self.blade)
        if pred and pred.castPosition then
            local castPos
            castPos, count = self:GetE2CastPos(pred, enemies)
            self.e.delay = 0.35 + GetDistance(castPos) / self.e.missileSpeed
            lasts[#lasts + 1] = self.e.delay
            check = self:CheckForSame(lasts)
        else
            return
        end
    end
    self.e.delay = check
    return count
end

function Irelia:CastE2()
    local targets = self:GetTargetRange(math.max(self.e.range, GetDistance(self.blade) + 300), true)
    local cast, best, cur = nil, 0, 0
    local e2Targets, e2Preds =
        self:GetTarget(
        self.e,
        true,
        self.blade,
        function(unit)
            cur = 0
            local count = self:CalcE2(unit, targets)
            if count then
                cur = count
                return unit
            end
        end,
        function(unit, pred)
            if pred and cur and cur > best then
                cast = self:GetE2CastPos(pred, targets)
                best = cur
            end
        end
    )
    -- local bestPred = nil
    -- local bestCast = nil
    -- local bestCount = 0
    -- local bestLength = 0
    -- for i, e2Target in pairs(e2Targets) do
    --     local count = 0
    --     local e2Pred = e2Preds[e2Target.networkId]
    --     self.eTest.delay = delays[e2Target.networkId]
    --     if e2Pred and e2Pred.castPosition then
    --         local castPos, endPos = self:GetE2CastPos(e2Pred)
    --         local castDist = GetDistance(self.blade, castPos)
    --         local seg = LineSegment(Vector(self.blade), Vector(endPos))
    --         for _, target in pairs(targets) do
    --             local pred = _G.Prediction.GetPrediction(target, self.eTest)
    --             if pred and pred.targetPosition then
    --                 local dist = seg:distanceTo(Vector(pred.targetPosition))
    --                 if dist < self.e.width / 2 + target.boundingRadius then
    --                     count = count + 1
    --                     local dist2 =
    --                         math.sqrt(GetDistance(self.blade, pred.targetPosition) ^ 2 - dist ^ 2) +
    --                         target.boundingRadius
    --                     castDist = math.max(castDist, dist2)
    --                     castPos = Vector(self.blade):extended(Vector(castPos), castDist):toDX3()
    --                 end
    --             end
    --         end
    --         if count > bestCount or (count == bestCount and castDist > bestLength) then
    --             bestPred = e2Pred
    --             bestCast = castPos
    --             bestCount = count
    --             bestLength = castDist
    --         end
    --     end
    -- end
    if cast then
        PrintChat(best)
        myHero.spellbook:CastSpellFast(2, cast)
        -- bestPred:draw()
        self.last.e2 = RiotClock.time
        return true
    end
end

function Irelia:CastR()
    local rTarget, rPred = self:GetTarget(self.r, false, myHero, nil, nil, self.TS.Modes["Closest To Mouse"])
    if rTarget and rPred and rPred.rates["slow"] and self:ValidTarget(rTarget) then
        myHero.spellbook:CastSpell(3, rPred.castPosition)
        self.last.r = RiotClock.time
        rPred:draw()
        return true
    end
end

function Irelia:CalcRFlash(target, spell)
    spell.speed = self.r.speed
    local lasts = {}
    while not check do
        pred = _G.Prediction.GetPrediction(target, spell, myHero)
        if pred and pred.castPosition then
            local dist = (pred.interceptionTime - spell.delay - _G.Prediction.GetInternalDelay()) * spell.speed
            local time = (dist - self.f.dist) / self.r.speed
            spell.speed = dist / time
            lasts[#lasts + 1] = spell.speed
            check = self:CheckForSame(lasts)
        else
            return
        end
        return true
    end
end

function Irelia:CastRFlash()
    local checkSpell =
        setmetatable(
        {
            range = self.r.range + self.f.dist
        },
        {__index = self.r}
    )
    local rTarget, rPred =
        self:GetTarget(
        checkSpell,
        false,
        myHero,
        function(unit)
            if self:CalcRFlash(unit, checkSpell) then
                return unit
            end
        end,
        function(unit)
            --PrintChat(checkSpell.speed)
            checkSpell.speed = self.r.speed
            return unit
        end,
        self.TS.Modes["Closest To Mouse"]
    )
    if rTarget and rPred and rPred.rates["slow"] and self:ValidTarget(rTarget) then
        if GetDistanceSqr(rPred.targetPosition) < self.r.range ^ 2 and self:CastR() then
            return true
        else
            myHero.spellbook:CastSpellFast(3, rPred.castPosition)
            myHero.spellbook:CastSpellFast(self.f.slot, rPred.castPosition)
            self.last.r = RiotClock.time
            rPred:draw()
            return true
        end
    end
end

function Irelia:AutoR()
    local rTargets, rPreds = self:GetTarget(self.r, true, myHero, nil, nil, self.TS.Modes["Closest To Mouse"])
    local bestCast, bestCount = nil, 1
    local mousePos = pwHud.hudManager.virtualCursorPos
    for _, rTarget in pairs(rTargets) do
        if rTarget and rPreds[rTarget.networkId] and rPreds[rTarget.networkId].castPosition then
            self.rCheck.delay = rPreds[rTarget.networkId].interceptionTime - _G.Prediction.GetInternalDelay()
            local targets, preds = self:GetTarget(self.rCheck, true)
            local checkTable = {}
            for _, target in pairs(targets) do
                if target and preds[target.networkId] then
                    checkTable[preds[target.networkId].targetPosition] = target.boundingRadius
                end
            end
            local predPos = rPreds[rTarget.networkId].targetPosition
            local castPos = rPreds[rTarget.networkId].castPosition
            local res = self:RContains(predPos, (Vector(castPos) - Vector(myHero.position)):normalized(), checkTable)
            local close = GetDistanceSqr(predPos) <= 300^2 
            local distsFromHero, distsFromMouse = 0,0
            local count = 0
            for pos in pairs(res) do
                if res[pos] then
                    distsFromHero = distsFromHero + GetDistance(pos)
                    distsFromMouse = distsFromMouse + GetDistance(pos, mousePos)
                    count = count + 1
                end
            end
            local closeMouse = distsFromHero > distsFromMouse
            if count > bestCount and (close or (count >= 3 and closeMouse))  then
                bestCast, bestCount = rPreds[rTarget.networkId], count
            end
        end
    end
    if bestCast then
        PrintChat(bestCount)
        myHero.spellbook:CastSpell(3, bestCast.castPosition)
        self.last.r = RiotClock.time
        bestCast:draw()
        return true
    end
end

--checktable: key: pos value: boundingRadius
--returns table key: pos value: contains
function Irelia:RContains(pos, diff, checkTable)
    local diff = (Vector(pos) - Vector(origin)):normalized()
    local diff2 = diff:rotated(0, math.pi / 2, 0)
    local sideLength, shortLength, longLength = 400, 250, 800
    local side1 = Vector(pos) + diff2 * sideLength
    local side2 = Vector(pos) - diff2 * sideLength
    local short1 = side1 - diff:rotated(0, math.pi / 6, 0) * shortLength
    local short2 = side2 + diff:rotated(0, 5 * math.pi / 6, 0) * shortLength
    local long1 = side1 - diff:rotated(0, 5 * math.pi / 6, 0) * longLength
    local polygon = Polygon(short1, side1, long1, side2, short2)
    local res = {}
    local segs = polygon:getLineSegments()
    for pt, r in pairs(checkTable) do
        res[pt] = false
        if polygon:contains(Vector(pt)) then
            res[pt] = true
        end
        -- for _, seg in pairs(segs) do
        --     if seg:distanceTo(Vector(pt)) <= r then
        --         res[pt] = true
        --     end
        -- end
    end
    return res
end

function Irelia:DrawLine(pos1, pos2, color)
    local p1 = Renderer:WorldToScreen(pos1)
    local p2 = Renderer:WorldToScreen(pos2)
    DrawHandler:Line(p1, p2, color)
end

function Irelia:OnDraw()
    if self.menu.draws.q:get() then
        DrawHandler:Circle3D(myHero.position, self.qRange, Color.White)
    end
    if self.menu.draws.e:get() then
        DrawHandler:Circle3D(myHero.position, self.e.range, Color.White)
    end
    if self.menu.draws.r:get() then
        DrawHandler:Circle3D(myHero.position, self.r.range, Color.White)
    end
    for a, minion in ipairs(ObjectManager:GetEnemyMinions()) do
        if
            minion and minion.isVisible and minion.characterIntermediate.movementSpeed > 0 and minion.isTargetable and
                not minion.isDead and
                minion.type == GameObjectType.obj_AI_Minion and
                GetDistanceSqr(minion) <= (900 * 900)
         then
            local dmg = self:GetQDamage(minion)
            DrawHandler:Text(DrawHandler.defaultFont, Renderer:WorldToScreen(minion.position), dmg, Color.White)
            if dmg >= minion.health then
                DrawHandler:Circle3D(minion.position, 50, self:Hex(255, 255, 112, 255))
            end
        end
    end
    local text = "E targets: " .. self:CastE1(true)
    DrawHandler:Text(DrawHandler.defaultFont, Renderer:WorldToScreen(myHero.position), text, Color.White)

    -- local rTarget, rPred = self:GetTarget(self.r, false, myHero, nil, nil, self.TS.Modes["Closest To Mouse"])
    -- if rTarget and rPred then
    --     local enemyPos = Vector(rTarget.position)
    --     local playerPos = Vector(myHero.position)
    --     local diff = (enemyPos - playerPos):normalized()
    --     local diff2 = diff:rotated(0, math.pi / 2, 0)
    --     local sideLength = 400
    --     local side1 = enemyPos + diff2 * sideLength
    --     local side2 = enemyPos - diff2 * sideLength
    --     local shortLength = 250
    --     local longLength = 800

    --     local short1 = side1 - diff:rotated(0, math.pi / 6, 0) * shortLength
    --     local short2 = side2 + diff:rotated(0, 5 * math.pi / 6, 0) * shortLength
    --     local long1 = side1 - diff:rotated(0, 5 * math.pi / 6, 0) * longLength
    --     local long2 = side2 + diff:rotated(0, math.pi / 6, 0) * longLength
    --     self:DrawLine(myHero.position, rTarget.position, Color.White)
    --     self:DrawLine(side1:toDX3(), rTarget.position, Color.Pink)
    --     self:DrawLine(side2:toDX3(), rTarget.position, Color.Yellow)
    --     self:DrawLine(side1:toDX3(), short1:toDX3(), Color.Red)
    --     self:DrawLine(side2:toDX3(), short2:toDX3(), Color.Blue)
    --     self:DrawLine(side1:toDX3(), long1:toDX3(), Color.SkyBlue)
    --     self:DrawLine(side2:toDX3(), long2:toDX3(), Color.Brown)
    -- -- local mousePos = pwHud.hudManager.virtualCursorPos
    -- -- local pos = {}
    -- -- pos[mousePos] = myHero.boundingRadius
    -- -- local res = self:RContains(myHero.position, rTarget.position, pos)
    -- -- DrawHandler:Circle3D(mousePos, 30, res[mousePos] and Color.White or Color.Red)
    -- end
end

function Irelia:OnTick()
    self.f.slot =
        myHero.spellbook:Spell(SpellSlot.Summoner1).name == "SummonerFlash" and SpellSlot.Summoner1 or
        myHero.spellbook:Spell(SpellSlot.Summoner2).name == "SummonerFlash" and SpellSlot.Summoner2 or
        nil
    if self:ShouldCast() and not Orbwalker:IsAttacking() then
        local q = myHero.spellbook:CanUseSpell(0) == 0
        local r = myHero.spellbook:CanUseSpell(3) == 0
        local e = myHero.spellbook:CanUseSpell(2) == 0
        local eName = myHero.spellbook:Spell(2).name
        -- if self.menu.q:get() and q and self:CastQNearest() then
        --     return
        -- end
        if self.menu.e:get() and e then
            if eName == "IreliaE" then
                if self:CastE1() then
                    return
                end
            elseif eName == "IreliaE2" then
                if self.blade and self:CastE2() then
                    return
                end
            end
        end

        if self.menu.manual:get() and r then
            self:CastR()
        end
        if self.menu.rFlash:get() and r and self.f.slot and myHero.spellbook:CanUseSpell(self.f.slot) == 0 then
            self:CastRFlash()
        end
        if Orbwalker:GetMode() == "Combo" then
            if r and self:AutoR() then
                return
            end
            if q then
                local bestPos = self:GetBestQ()
                if bestPos and self:CastQ(bestPos) then
                    return
                end
            end
        elseif Orbwalker:GetMode() == "Waveclear" then
            if q and self:LastHitQ() then
                return
            end
        end
    end
    -- self:KillSteal()
end

function Irelia:OnProcessSpell(obj, spell)
    if obj == myHero then
        if spell.spellData.name == "IreliaQ" then
            self.last.q = nil
        elseif spell.spellData.name == "IreliaE" then
            self.last.e1 = nil
        elseif spell.spellData.name == "IreliaE2" then
            self.blade = nil
            self.last.e2 = nil
        elseif spell.spellData.name == "IreliaR" then
            self.last.r = nil
        end
    end
    if obj ~= nil and spell ~= nil and obj ~= myHero and obj.team ~= myHero.team then
        if spell.spellData.name == "VeigarEventHorizon" then
            self.cage = D3DXVECTOR3(spell.endPos.x, myHero.y, spell.endPos.z)
        end
    end
end

function Irelia:OnExecuteCastFrame(obj, spell)
    -- print('hi')
    -- PrintChat(spell.spellData.name)
    -- if obj == myHero then
    --     PrintChat(spell.spellData.name)
    -- end
end

function Irelia:OnBuffLost(obj, buff)
    if obj and obj.team == myHero.team and obj.type == myHero.type and obj == myHero and buff and buff.name == "sheen" then
        sheenTimer = os.clock() + 1.7
        print("true")
    end
end

function Irelia:OnCreateObj(obj)
    if obj.name == "Blade" then
        self.blade = obj.position
    end
    if obj and GetDistance(obj) < 300 and obj.name:find("Glow_buf") then
        sheenTimer = os.clock() + 1.7
    end
    if obj.name:lower():find("cage_green") then
        self.cage = obj
    end
end

function Irelia:OnDeleteObj(obj)
    --print("Delete: ".. obj.name)
    if obj.name:lower():find("cage_green") then
        self.cage = nil
    end
end

function Irelia:GetTarget(spell, all, source, targetFilter, predFilter, tsMode)
    local units, preds = self.TS:GetTargets(spell, source, targetFilter, predFilter)
    if all then
        return units, preds
    else
        local target = self.TS.target
        if target then
            return target, preds[target.networkId]
        end
    end
end

function Irelia:Hex(a, r, g, b)
    return string.format("0x%.2X%.2X%.2X%.2X", a, r, g, b)
end

function Irelia:GetTargetRange(dist, all)
    local res =
        self.TS:update(
        function(unit)
            return _G.Prediction.IsValidTarget(unit, dist, myHero.position)
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

return Irelia

if myHero.charName ~= "Irelia" then
    return
end

local Irelia = {}
local version = 1
local passiveBaseScale = {15, 18, 21, 24, 27, 30, 33, 36, 39, 42, 45, 48, 51, 54, 57, 60, 63, 66}
local sheenTimer = os.clock()

--[[ GetInternalWebResultAsync(
    "IreliaEmpyrean.version",
    function(v)
        if tonumber(v) > version then
            DownloadInternalFileAsync(
                "IreliaEmpyrean.lua",
                SCRIPT_PATH,
                function(success)
                    if success then
                        PrintChat("Updated. Press F5")
                    end
                end
            )
        end
    end
) ]]
require("FF15Menu")
require("utils")
local DreamTS = require("DreamTS")
local dmgLib = require("FF15DamageLib")
local Orbwalker = require("FF15OL")
local Vector
local LineSegment = require("GeometryLib").LineSegment

function OnLoad()
    if not _G.Prediction then
        _G.LoadPaidScript(_G.PaidScript.DREAM_PRED)
    end

    if not _G.AuroraOrb and not _G.LegitOrbwalker then
        LoadPaidScript(PaidScript.AURORA_BUNDLE_DEV)
    end

    Vector = _G.Prediction.Vector

    Orbwalker:Setup()
    Irelia:__init()
end

function Irelia:__init()
    self.orbSetup = false
    self.last = {
        q = nil,
        w = nil,
        e1 = nil,
        e2 = nil,
        r = nil
    }
    self.e1Pos = nil
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
            ["Hero"] = true,
            ["Minion"] = false
        }
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
    PrintChat("Irelia loaded")
    self.font = DrawHandler:CreateFont("Calibri", 10)
end

function Irelia:Menu()
    self.menu = Menu("IreliaEmpyrean", "Irelia - Empyrean")
    self.menu:sub("dreamTs", "Target Selector")
    self.menu:slider("e1Range", "Isolated E1 range", 0, self.e.range, 450)
    self.menu:key("manual", "Semi-Manual R Aim", string.byte("Z"))
    self.menu:key("specialE", "Force Full Range E / Force Multi E", string.byte("T"))
    self.menu:key("disableE", "Disable E1 / Cast E2 on 100% hit", 20)
    self.menu:checkbox("turret", "Enable Turret Check", true, string.byte("K"))
    self.menu:sub("draws", "Draw")
        self.menu.draws:checkbox("q", "Q", true)
        self.menu.draws:checkbox("e", "E", true)
end

function Irelia:ShouldCast()
    for spell, time in pairs(self.last) do
        if time and RiotClock.time < time + 0.35 + NetClient.ping / 2000 + 0.06 then
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
local QMLevelDamage = {55, 75, 95, 115, 135}
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
            if target.team ~= myHero.team then
                damage =
                    dmgLib:CalculatePhysicalDamage(
                    myHero,
                    target,
                    (QLevelDamage[myHero.spellbook:Spell(0).level] + (self:GetTotalAD() * 0.6) + onhitPhysical)
                ) +
                    dmgLib:CalculatePhysicalDamage(myHero, target, QMLevelDamage[myHero.spellbook:Spell(0).level]) +
                    dmgLib:CalculateMagicDamage(target, myHero, onhitMagical)
            else
                damage =
                    dmgLib:CalculatePhysicalDamage(
                    myHero,
                    target,
                    (QLevelDamage[myHero.spellbook:Spell(0).level] + (self:GetTotalAD() * 0.6) + onhitPhysical)
                )
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
    if GetDistanceSqr(target) <= (self.qRange * self.qRange) and target.isVisible and self:ValidTarget(target) and not target.buffManager:HasBuff("JaxCounterStrike") and not target.buffManager:HasBuff("GalioW") then
        if not self.menu.turret:get() or not self:UnderTurret(target) or self:UnderTurret(myHero) then
            myHero.spellbook:CastSpellFast(0, target.networkId)
            self.last.q = RiotClock.time
            return true
        end
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
    local mousePos = pwHud.hudManager.virtualCursorPos
    local origDist = GetDistanceSqr(mousePos)
    local minDistance = GetDistanceSqr(mousePos)
    local minDistObj = nil
    local minionsInRange = ObjectManager:GetEnemyMinions()
    for _, minion in ipairs(minionsInRange) do
        local minionDist = GetDistanceSqr(minion, mousePos)
        if minion and GetDistanceSqr(minion) <= (self.qRange * self.qRange) then
            if self:CanKS(minion) or minion.buffManager:HasBuff("ireliamark") then
                if minionDist < minDistance then
                    minDistance = minionDist
                    minDistObj = minion
                end
            end
        end
    end

    local enemiesInRange = self:GetTargetRange(self.qRange, true)
    for _, enemy in ipairs(enemiesInRange) do
        local enemyDist = GetDistanceSqr(enemy, mousePos)
        if enemy.buffManager:HasBuff("ireliamark") or self:CanKS(enemy) then
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
    return _G.Prediction.GetUnitPosition(target, 0.06 + NetClient.ping / 2000 + 0.15) --[[ + 0.35 + GetDistance(target) / self.e.missileSpeed
    ) ]]
end

function Irelia:CastE1(override)
    local targets = self:GetTargetRange(self.e.range, true)
    local isolated = #self:GetTargetRange(1500, true) == 1
    if #targets == 1 and not targets[1].buffManager:HasBuff("ireliamark") and (not override or isolated) then
        local pos = self:GetE1Pred(targets[1])
        local check = override and self.e.range or self.menu.e1Range:get()
        if GetDistanceSqr(pos) <= check * check then
            local playerPos = Vector(myHero)
            local castPos = (playerPos + (Vector(pos) - playerPos):normalized() * (self.e.range - 50)):toDX3()
            myHero.spellbook:CastSpellFast(2, castPos)
            self.e1Pos = castPos
            self.last.e1 = RiotClock.time
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
            local castPos =
                self:RaySetDist(
                Vector(bestCast1),
                (Vector(bestCast1) - Vector(bestCast2)):normalized(),
                Vector(myHero.position),
                self.e.range - 50
            ):toDX3()
            myHero.spellbook:CastSpellFast(2, castPos)
            self.e1Pos = castPos
            self.last.e1 = RiotClock.time
        end
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

function Irelia:GetE2CastPos(pred)
    if not pred or not pred.castPosition then
        return
    end
    local startPos = Vector(self.e1Pos)
    local playerPos = Vector(myHero)
    local endPos =
        self:RaySetDist(startPos, (Vector(pred.castPosition) - startPos):normalized(), playerPos, self.e.range)
    local distSqr1 = GetDistanceSqr(self.e1Pos, pred.castPosition)
    local seg = LineSegment(startPos, endPos)
    local closest = seg:closest(playerPos):toDX3()
    local distSqr2 = GetDistanceSqr(self.e1Pos, closest)
    if closest and distSqr2 > distSqr1 then
        return closest
    else
        return pred.castPosition
    end
end

function Irelia:CalcE2(target)
    local dist = GetDistance(target.position)
    if dist > self.e.range then
        return
    end
    self.e.delay = 0.35 + dist / self.e.missileSpeed
    local pred
    local lasts = {}
    local check = nil
    while not check do
        pred = _G.Prediction.GetPrediction(target, self.e, self.e1Pos)
        if pred and pred.castPosition then
            local castPos = self:GetE2CastPos(pred)
            self.e.delay = 0.35 + GetDistance(castPos) / self.e.missileSpeed
            lasts[#lasts + 1] = self.e.delay
            check = self:CheckForSame(lasts)
        else
            return
        end
    end
    self.e.delay = check
    return true
end

function Irelia:CastE2()
    local delays = {}
    local e2Targets, e2Preds =
        self:GetTarget(
        self.e,
        true,
        self.e1Pos,
        function(unit)
            if self:CalcE2(unit) then
                delays[unit.networkId] = self.e.delay
                return unit
            end
        end
    )
    local bestPred = nil
    local bestCast = nil
    local bestCount = 0
    local bestLength = 0
    local targets = self:GetTargetRange(math.max(self.e.range, GetDistance(self.e1Pos) + 300), true)
    for _, e2Target in pairs(e2Targets) do
        local count = 0
        local e2Pred = e2Preds[e2Target.networkId]
        self.eTest.delay = delays[e2Target.networkId]
        if e2Pred and e2Pred.castPosition then
            local castPos = self:GetE2CastPos(e2Pred)
            local length = GetDistanceSqr(castPos, self.e1Pos)
            for _, target in pairs(targets) do
                local pred = _G.Prediction.GetPrediction(target, self.eTest)
                if pred and pred.targetPosition then
                    local seg = LineSegment(Vector(self.e1Pos), Vector(castPos))

                    if seg:distanceTo(Vector(pred.targetPosition)) < self.e.width + target.boundingRadius / 2 then
                        count = count + 1
                    end
                end
            end
            if count > bestCount or (count == bestCount and length > bestLength) then
                bestPred = e2Pred
                bestCast = castPos
                bestCount = count
                bestLength = length
            end
        end
    end
    if
        bestCast and bestPred and
            (not self.menu.disableE:get() and bestPred.rates["slow"] or bestPred.realHitChance == 1)
     then
        myHero.spellbook:CastSpellFast(2, bestCast)
        bestPred:draw()
        self.last.e2 = RiotClock.time
        return true
    end
end

function Irelia:CastR()
    local rTarget, rPred = self:GetTarget(self.r)
    if rTarget and rPred and rPred.rates["slow"] and self:ValidTarget(rTarget) then
        myHero.spellbook:CastSpell(3, rPred.castPosition)
        self.last.r = RiotClock.time
        rPred:draw()
        return true
    end
end

function Irelia:OnDraw()
    if self.e1Pos then
        DrawHandler:Circle3D(self.e1Pos, 50, Color.Yellow)
    end
    if self.menu.draws.q:get() and myHero.spellbook:CanUseSpell(0) == 0 then
        DrawHandler:Circle3D(myHero.position, 600, Color.White)
    end
    if self.menu.draws.e:get() and myHero.spellbook:CanUseSpell(2) == 0 then
        DrawHandler:Circle3D(myHero.position, self.e.range, Color.White)
    end
    if myHero.spellbook:CanUseSpell(0) == 0 then
        for a, minion in ipairs(ObjectManager:GetEnemyMinions()) do
            if
                minion and minion.isVisible and minion.characterIntermediate.movementSpeed > 0 and minion.isTargetable and
                    not minion.isDead and
                    minion.type == GameObjectType.obj_AI_Minion and
                    GetDistanceSqr(minion) <= (900 * 900)
             then
                if self:GetQDamage(minion) >= minion.health then
                    DrawHandler:Circle3D(minion.position, 50, self:Hex(255, 255, 112, 255))
                end
            end
        end
    end
    local text =
        (self.menu.specialE:get() and "E Modifier on" or "E Modifier off") ..
        "\n" .. (self.menu.disableE:get() and "Disable E on" or "Disable E off") .. 
        "\n" .. (self.menu.turret:get() and "Turret check on" or "Turret check off")

    DrawHandler:Text(DrawHandler.defaultFont, Renderer:WorldToScreen(myHero.position), text, Color.White)
end

function Irelia:OnTick()
    if not self.orbSetup and (_G.AuroraOrb or _G.LegitOrbwalker) then
        Orbwalker:Setup()
        self.orbSetup = true
    end
    if self.orbSetup and self:ShouldCast() then
        local q = myHero.spellbook:CanUseSpell(0) == 0
        local r = myHero.spellbook:CanUseSpell(3) == 0
        local e = myHero.spellbook:CanUseSpell(2) == 0
        local eName = myHero.spellbook:Spell(2).name
        if Orbwalker:GetMode() == "Combo" then
            if e then
                if eName == "IreliaE" then
                    if not self.menu.disableE:get() and self:CastE1(self.menu.specialE:get() and true or false) then
                        return
                    end
                elseif eName == "IreliaE2" then
                    if self.e1Pos and self:CastE2() then
                        return
                    end
                end
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
        elseif self.menu.manual:get() and r then
            self:CastR()
        end
    end
    self:KillSteal()
end

function Irelia:OnProcessSpell(obj, spell)
    if obj == myHero then
        if spell.spellData.name == "IreliaQ" then
            self.last.q = nil
        elseif spell.spellData.name == "IreliaE" then
            self.last.e1 = nil
        elseif spell.spellData.name == "IreliaE2" then
            self.e1Pos = nil
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
end

function Irelia:OnCreateObj(obj)
    if obj.name == "Blade" then
        self.e1Pos = obj.position
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

function Irelia:GetTarget(spell, all, source, targetFilter, predFilter)
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

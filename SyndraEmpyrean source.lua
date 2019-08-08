local Syndra = {}
local version = 2.6
if tonumber(GetInternalWebResult("SyndraEmpyrean.version")) > version then
    DownloadInternalFile("SyndraEmpyrean.lua", SCRIPT_PATH .. "SyndraEmpyrean.lua")
    print("New version:" .. tonumber(GetInternalWebResult("SyndraEmpyrean.version")) .. " Press F5")
end
require "FF15Menu"
require "utils"

local Vector = require("GeometryLib").Vector
local LineSegment = require("GeometryLib").LineSegment
local dmgLib = require("FF15DamageLib")
local DreamTS = require("DreamTS")
local Orbwalker = require("FF15OL")

local function EdgePosition2(tP, cP, source, adjustment, target, range)
    tP = Vector(tP)
    cP = Vector(cP)
    adjustment = adjustment - 10
    local dist = source:dist(tP)
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

function Syndra:init()
    self.unitsInRange = {}
    self.spell = {
        q = {
            type = "circular",
            range = 800,
            delay = 0.63,
            radius = 200,
            speed = math.huge
        },
        w = {
            type = "circular",
            range = 925,
            delay = 0.7,
            radius = 220,
            speed = math.huge,
            heldInfo = nil,
            useHeroSource = true,
            blacklist = {}
        },
        e = {
            type = "linear",
            speed = 1600,
            range = 700,
            delay = 0.25,
            width = 200,
            widthMax = 200,
            angle = 48,
            passiveAngle = 68,
            queue = nil,
            blacklist = {},
            next = nil,
            collision = {
                ["Wall"] = true,
                ["Hero"] = false,
                ["Minion"] = false
            }
        },
        qe = {
            type = "linear",
            pingPongSpeed = 2000,
            range = 1200,
            delay = 0.25,
            speed = 2000,
            width = 200,
            collision = {
                ["Wall"] = true,
                ["Hero"] = false,
                ["Minion"] = false
            }
        }
    }
    self.last = {
        q = nil,
        w = nil,
        e = nil,
        r = nil
    }
    self.ignite =
        myHero.spellbook:Spell(SpellSlot.Summoner1).name == "SummonerDot" and SpellSlot.Summoner1 or
        myHero.spellbook:Spell(SpellSlot.Summoner2).name == "SummonerDot" and SpellSlot.Summoner2 or
        nil
    self.wGrabList = {
        ["SRU_ChaosMinionSuper"] = true,
        ["SRU_OrderMinionSuper"] = true,
        ["HA_ChaosMinionSuper"] = true,
        ["HA_OrderMinionSuper"] = true,
        ["SRU_ChaosMinionRanged"] = true,
        ["SRU_OrderMinionRanged"] = true,
        ["HA_ChaosMinionRanged"] = true,
        ["HA_OrderMinionRanged"] = true,
        ["SRU_ChaosMinionMelee"] = true,
        ["SRU_OrderMinionMelee"] = true,
        ["HA_ChaosMinionMelee"] = true,
        ["HA_OrderMinionMelee"] = true,
        ["SRU_ChaosMinionSiege"] = true,
        ["SRU_OrderMinionSiege"] = true,
        ["HA_ChaosMinionSiege"] = true,
        ["HA_OrderMinionSiege"] = true,
        ["SRU_Krug"] = true,
        ["SRU_KrugMini"] = true,
        --["TestCubeRender"] = true,
        ["SRU_RazorbeakMini"] = true,
        ["SRU_Razorbeak"] = true,
        ["SRU_MurkwolfMini"] = true,
        ["SRU_Murkwolf"] = true,
        ["SRU_Gromp"] = true,
        ["Sru_Crab"] = true,
        ["SRU_Red"] = true,
        ["SRU_Blue"] = true,
        ["EliseSpiderling"] = true,
        --["GangplankBarrel"] = true,
        ["HeimerTYellow"] = true,
        ["HeimerTBlue"] = true,
        --["IllaoiMinion"] = true,
        --["KalistaSpawn"] = true,
        ["MalzaharVoidling"] = true,
        ["ShacoBox"] = true,
        --["TeemoMushroom"] = true,
        ["YorickGhoulMelee"] = true,
        ["YorickBigGhoul"] = true
        --["ZyraThornPlant"] = true,
        --["ZyraGraspingPlant"] = true,
        --["VoidGate"] = true,
        --["VoidSpawn"] = true
    }
    self.orbs = {}
    self.rDamages = {}
    self.electrocuteTracker = {}
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
        Events.OnCreateObject,
        function(obj)
            self:OnCreateObj(obj)
        end
    )

    AddEvent(
        Events.OnDeleteObject,
        function(obj)
            self:OnDeleteObj(obj)
        end
    )

    AddEvent(
        Events.OnProcessSpell,
        function(obj, spell)
            self:OnProcessSpell(obj, spell)
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

    print("Syndra loaded")
    self.font = DrawHandler:CreateFont("Calibri", 10)
end

function Syndra:Menu()
    self.menu = Menu("SyndraEmpyrean", "Syndra - Empyrean")
    self.menu:sub("dreamTs", "Target Selector")
    self.menu:checkbox("qe2", "Use QE Long", true, string.byte("Z"))
    self.menu:checkbox("e", "AutoE", true, string.byte("T"))
    self.antiGapHeros = {}

    self.menu:sub("antigap", "Anti Gapclose")
    for _, enemy in pairs(ObjectManager:GetEnemyHeroes()) do
        self.menu.antigap:checkbox(tostring(enemy.networkId), enemy.charName, true)
        self.antiGapHeros[enemy.networkId] = true
    end
    --[[   self.menu:sub("interrupt", "Interrupter")
    _G.Prediction.LoadInterruptToMenu(self.menu.interrupt) ]]
    self.menu:sub("r", "R")
    for _, enemy in pairs(ObjectManager:GetEnemyHeroes()) do
        self.menu.r:checkbox(tostring(enemy.networkId), enemy.charName, true)
    end
    self.menu.r:checkbox("c0", "Cast regardless of below conditions", false)
    self.menu.r:checkbox("c1", "Cast if target in wall", true)
    self.menu.r:checkbox("c2", "Cast if lower health% than target", true)
    self.menu.r:slider("c3", "Cast if player % health < x", 0, 100, 15)
    self.menu.r:checkbox("c4", "Do not cast if killed by Q ", true)
    self.menu.r:checkbox("c5", "Cast if more enemies near than allies", true)
    self.menu.r:slider("c6", "Cast if mana less than", 100, 500, 200)
    self.menu.r:slider("c7", "Cast if target MR less than", 0, 200, 50)
    self.menu.r:slider("c8", "Cast if enemies around player <= x", 1, 5, 2)
end

function Syndra:GetCastPosition(pred)
    if pred.isAdjusted then
        return pred.ap, true
    else
        return pred.castPosition, false
    end
end

function Syndra:OnTick()
    for _, stacks in pairs(self.electrocuteTracker) do
        for i, time in pairs(stacks) do
            if os.clock() >= time + 2.75 - 0.06 - NetClient.ping / 2000 then
                stacks[i] = nil
            end
        end
    end
    for i in pairs(self.spell.w.blacklist) do
        if not self.orbs[i] then
            self.spell.w.blacklist[i] = nil
        elseif self.spell.w.blacklist[i].nextCheckTime then
            if
                os.clock() >= self.spell.w.blacklist[i].interceptTime and
                    GetDistanceSqr(self.orbs[i].obj.position, self.spell.w.blacklist[i].pos) == 0
             then
                self.spell.w.blacklist[i] = nil
            else
                self.spell.w.blacklist[i].pos = self.orbs[i].obj.position
                self.spell.w.blacklist[i].nextCheckTime = os.clock() + 0.1 + NetClient.ping / 1000
            end
        end
    end

    for orb in pairs(self.spell.e.blacklist) do
        if self.spell.e.blacklist[orb].time <= os.clock() then
            if
                not (self.spell.w.heldInfo and orb == self.spell.w.heldInfo.obj) and
                    GetDistanceSqr(self.spell.e.blacklist[orb].pos, orb.position) == 0
             then
                self.spell.e.blacklist[orb] = nil
            else
                self.spell.e.blacklist[orb] = {pos = orb.position, time = os.clock() + 0.1 + NetClient.ping / 1000}
            end
        end
    end

    for i in pairs(self.orbs) do
        local orb = self.orbs[i]
        if os.clock() >= orb.endT or (orb.obj.health and orb.obj.health ~= 1) then
            table.remove(self.orbs, i)
        end
    end
    if self.spell.e.queue then
        if os.clock() >= self.spell.e.queue.time then
            self.spell.e.queue = nil
        end
    end
    if self:ShouldCast() then
        for _, enemy in ipairs(ObjectManager:GetEnemyHeroes()) do
            self.unitsInRange[enemy.networkId] = GetDistanceSqr(enemy) < 2000 * 2000
        end
        local q = myHero.spellbook:CanUseSpell(0) == 0
        local notQ = myHero.spellbook:CanUseSpell(0) ~= 0
        local w = myHero.spellbook:CanUseSpell(1) == 0
        local w1 = w and myHero.spellbook:Spell(SpellSlot.W).name == "SyndraW" and not self.spell.w.heldInfo
        local e = myHero.spellbook:CanUseSpell(2) == 0
        local notE = myHero.spellbook:CanUseSpell(2) ~= 0

        if w1 and self:AutoGrab() then
            return
        end

        if e then
            self.spell.e.delay = 0.35 + NetClient.ping / 1000
            if self:CastShortEMode("q") or self:CastShortEMode("w") then
                return
            end
            local eTargets = self:GetTargetRange(self.spell.qe.range, true)
            local canHitOrbs = {}
            for i in pairs(self.orbs) do
                local orb = self.orbs[i]
                local distToOrb = GetDistance(orb.obj.position)
                if distToOrb <= self.spell.q.range - 50 then
                    local timeToHitOrb = self.spell.e.delay + (distToOrb / self.spell.e.speed)
                    local expectedHitTime = os.clock() + timeToHitOrb - 0.1
                    local canHitOrb =
                        (orb.isInitialized and (expectedHitTime + 0.1 < orb.endT) or (expectedHitTime > orb.endT)) and
                        (not orb.isInitialized or (orb.obj and not self.spell.e.blacklist[orb.obj])) and
                        (not self.spell.w.heldInfo or orb.obj ~= self.spell.w.heldInfo.obj)
                    if canHitOrb then
                        canHitOrbs[#canHitOrbs + 1] = orb
                    end
                end
            end

            for _, target in pairs(eTargets) do
                if (self.menu.e:get() and not _G.Prediction.IsRecalling(myHero)) or Orbwalker:GetMode() == "Combo" then
                    if self:CastE(target, canHitOrbs) then
                        return
                    end
                end
            end
        end

        local igniteTargets = self:GetTargetRange(650, true)
        for _, target in pairs(igniteTargets) do
            if self:UseIgnite(target) then
                return
            end
        end
        self.rDamages = {}

        local rTargets = self:GetTargetRange(1500, true)
        for _, target in pairs(rTargets) do
            if self:CastR(target) then
                return
            end
        end
        if Orbwalker:GetMode() == "Combo" then
            if w then
                local wTarget, wPred =
                    self:GetTarget(
                    self.spell.w,
                    false,
                    function(unit)
                        return self.unitsInRange[unit.networkId]
                    end
                )
                local _, isOrb = self:GetGrabTarget()
                if wTarget and wPred then
                    if w1 and (e or (isOrb or notQ) or not self:WaitToInitialize()) and self:CastW1() then
                        return
                    end
                    if
                        self.spell.w.heldInfo and
                            (notE or
                                GetDistanceSqr(wPred.castPosition) >=
                                    (self.spell.e.range - 50) * (self.spell.e.range - 50)) and
                            self:CastW2(wPred)
                     then
                        return
                    end
                end
            end
            if q and e and myHero.mana >= 80 + 10 * myHero.spellbook:Spell(0).level then
                self.spell.qe.delay = 0.25 + NetClient.ping / 1000
                local qeTarget, qePred =
                    self:GetTarget(
                    self.spell.qe,
                    false,
                    function(unit)
                        return self.unitsInRange[unit.networkId] and self:CalcQELong(unit, self.spell.q.range - 100) and
                            unit
                    end
                )

                if qeTarget and qePred and qePred.castPosition and self.menu.qe2:get() and self:CastQELong(qePred) then
                    return
                end
            end
        end

        if q then
            local qTarget, qPred =
                self:GetTarget(
                self.spell.q,
                false,
                function(unit)
                    return self.unitsInRange[unit.networkId]
                end
            )
            if qTarget and qPred then
                if
                    ((Orbwalker:GetMode() == "Combo" and
                        (notE or GetDistanceSqr(qPred.castPosition) >= self.spell.e.range * self.spell.e.range)) or
                        Orbwalker:GetMode() == "Harass") and
                        self:CastQ(qPred)
                 then
                    return
                end
            end
        end
    end
end

function Syndra:OnDraw()
    DrawHandler:Circle3D(myHero.position, self.spell.q.range, Color.White)

    DrawHandler:Circle3D(myHero.position, self.spell.qe.range, Color.White)

    for i in pairs(self.orbs) do
        local orb = self.orbs[i]
        DrawHandler:Circle3D(orb.obj.position, 40, orb.isInitialized and Color.SkyBlue or Color.Red)
        DrawHandler:Text(
            DrawHandler.defaultFont,
            Renderer:WorldToScreen(orb.obj.position),
            math.ceil(orb.endT - os.clock()),
            Color.White
        )
        if GetDistanceSqr(orb.obj.position) <= self.spell.q.range * self.spell.q.range then
            local new_pos = Vector(myHero):extended(Vector(orb.obj.position), self.spell.qe.range)
            _G.Prediction.Drawing.DrawRectangle(
                myHero.position,
                new_pos,
                self.spell.qe.width,
                orb.isInitialized and Color.SkyBlue or Color.Red
            )
        end
    end

    if self.spell.w.heldInfo then
        DrawHandler:Circle3D(self.spell.w.heldInfo.obj.position, 45, Color.Green)
    end
    for orb in pairs(self.spell.e.blacklist) do
        DrawHandler:Circle3D(orb.position, 50, Color.Yellow)
    end

    for i in pairs(self.spell.w.blacklist) do
        if self.orbs[i] then
            DrawHandler:Circle3D(self.orbs[i].obj.position, 50, Color.Pink)
        end
    end

    local text =
        (self.menu.qe2:get() and "QE Long: On" or "QE Long: Off") ..
        "\n" .. (self.menu.e:get() and "Auto E: On" or "Auto E: Off")
    DrawHandler:Text(DrawHandler.defaultFont, Renderer:WorldToScreen(myHero.position), text, Color.White)
    if myHero.spellbook:CanUseSpell(SpellSlot.R) == SpellState.Ready then
        for target, damage in pairs(self.rDamages) do
            local hpBarPos = target.infoComponent.hpBarScreenPosition
            local xPos = hpBarPos.x - 44 + 104 * damage / (target.maxHealth + target.allShield)
            local startPos = D3DXVECTOR2(xPos, hpBarPos.y - 24)
            local endPos = D3DXVECTOR2(xPos, hpBarPos.y - 13)
            DrawHandler:Line(startPos, endPos, Color.SkyBlue)
        end
    end
end

function Syndra:WaitToInitialize()
    for i in pairs(self.orbs) do
        local orb = self.orbs[i]
        if not orb.isInitialized and GetDistanceSqr(orb.obj.position) <= self.spell.w.range * self.spell.w.range then
            return true
        end
    end
end

function Syndra:ShouldCast()
    for spell, time in pairs(self.last) do
        if time and os.clock() < time + 0.25 then
            return false
        end
    end
    return true
end

function Syndra:AutoGrab()
    if not _G.Prediction.IsRecalling(myHero) then
        for _, minion in pairs(ObjectManager:GetEnemyMinions()) do
            if
                (minion.name == "Tibbers" or minion.name == "IvernMinion" or minion.name == "H-28G Evolution Turret") and
                    GetDistanceSqr(minion) < self.spell.w.range * self.spell.w.range
             then
                myHero.spellbook:CastSpell(SpellSlot.W, minion.position)
                self.last.w = os.clock()
                return true
            end
        end
    end
end

function Syndra:CastQ(pred)
    if myHero.spellbook:CanUseSpell(SpellSlot.Q) == SpellState.Ready then
        if pred and pred.castPosition and pred.rates["very slow"] then
            myHero.spellbook:CastSpell(SpellSlot.Q, pred.castPosition)
            self.last.q = os.clock()
            pred:draw()
            PrintChat("q")
            return true
        end
    end
end

function Syndra:GetGrabTarget()
    local lowTime = math.huge
    local lowOrb = nil
    for i in pairs(self.orbs) do
        local orb = self.orbs[i]
        if
            not self.spell.w.blacklist[i] and orb.isInitialized and orb.endT < lowTime and
                GetDistanceSqr(orb.obj.position) <= self.spell.w.range * self.spell.w.range
         then
            lowTime = orb.endT
            lowOrb = orb.obj
        end
    end
    if lowOrb then
        return lowOrb, true
    end

    local minionsInRange = ObjectManager:GetEnemyMinions()
    local lowHealth = math.huge
    local lowMinion = nil
    for _, minion in ipairs(minionsInRange) do
        print(minion.name)

        if
            minion and self.wGrabList[minion.charName] and _G.Prediction.IsValidTarget(minion) and
                GetDistanceSqr(minion.position) <= self.spell.w.range * self.spell.w.range
         then
            if minion.health < lowHealth then
                lowHealth = minion.health
                lowMinion = minion
            end
        end
    end
    if lowMinion then
        return lowMinion, false
    end
end

function Syndra:CastW1()
    local target = self:GetGrabTarget()
    if target then
        myHero.spellbook:CastSpell(SpellSlot.W, target.position)
        self.last.w = os.clock()
        PrintChat("w1" .. target.name .. GetDistance(target.position))
        return true
    end
end

function Syndra:CastW2(pred)
    if not self.spell.w.heldInfo then
        return
    end
    if
        pred and pred.castPosition and pred.rates["very slow"] and not NavMesh:IsWall(pred.castPosition) and
            not NavMesh:IsBuilding(pred.castPosition)
     then
        myHero.spellbook:CastSpell(SpellSlot.W, pred.castPosition)
        self.last.w = os.clock()
        pred:draw()
        PrintChat("w2")
        return true
    end
end

function Syndra:CastShortEMode(mode)
    local eTarget, ePred =
        self:GetTarget(
        self.spell.e,
        false,
        function(unit)
            if not self.unitsInRange[unit.networkId] then
                return
            end
            self:CalcQEShort(unit, self.spell.e.widthMax, mode)
            return unit
        end,
        function(unit, pred)
            if not pred and not pred.rates["slow"] then
                return
            end
            return Orbwalker:GetMode() == "Combo" or
                pred.targetDashing and self.antiGapHeros[unit.networkId] and
                    self.menu.antigap[tostring(unit.networkId)]:get()
        end
    )
    if eTarget and ePred then
        if
            self:CanEQ(self:GetQPos(ePred.castPosition, "q"), ePred, eTarget) and
                ((mode == "q" and self:CastQEShort(ePred)) or self:CastWE(ePred))
         then
            PrintChat("e short")

            return true
        end
    end
end

function Syndra:CanEQ(qPos, pred, target)
    --wall check
    local interval = 50
    local castPosition = self:GetCastPosition(pred)
    local count = math.floor(GetDistance(castPosition, qPos:toDX3()) / interval)
    local diff = (Vector(qpos) - Vector(myHero.position)):normalized()
    for i = 0, count do
        local pos = (Vector(castPosition) + diff * i * interval):toDX3()
        if NavMesh:IsWall(pos) or NavMesh:IsBuilding(pos) then
            return false
        end
    end

    --cc check
    if _G.Prediction.IsImmobile(target, pred.interceptionTime) then
        return false
    end
    return true
end

function Syndra:CheckForSame(list)
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

function Syndra:CalcQELong(target, dist)
    local dist = dist or self.spell.e.range
    self.spell.qe.speed = self.spell.qe.pingPongSpeed
    local pred
    local lasts = {}
    local check = nil

    while not check do
        pred = _G.Prediction.GetPrediction(target, self.spell.qe, myHero)
        if pred and pred.castPosition and GetDistanceSqr(pred.targetPosition) >= self.spell.e.range * self.spell.e.range then
            local castPosition, isAdjusted = self:GetCastPosition(pred)
            local offset = isAdjusted and -target.boundingRadius or 0
            self.spell.qe.speed =
                (self.spell.e.speed * dist + self.spell.qe.pingPongSpeed * (GetDistance(castPosition) + offset - dist)) /
                (GetDistance(castPosition) + offset)
            lasts[#lasts + 1] = self.spell.qe.speed
            check = self:CheckForSame(lasts)
        else
            return
        end
    end
    self.spell.qe.speed = check
    print(self.spell.qe.speed)
    return true
end

function Syndra:CalcQEShort(target, widthMax, spell)
    self.spell.e.width = widthMax
    local pred = _G.Prediction.GetPrediction(target, self.spell.e, myHero)
    local lasts = {}
    local check = nil
    while not check do
        pred = _G.Prediction.GetPrediction(target, self.spell.e, myHero)
        if not (pred and pred.castPosition) then
            return
        end
        self.spell.e.width =
            -target.boundingRadius +
            (GetDistance(pred.castPosition) + target.boundingRadius) /
                (GetDistance(self:GetQPos(pred.castPosition, spell):toDX3()) + target.boundingRadius) *
                (widthMax + target.boundingRadius)
        lasts[#lasts + 1] = self.spell.e.width
        check = self:CheckForSame(lasts)
    end
    self.spell.e.width = check
    return pred
end

function Syndra:CastE(target, canHitOrbs)
    if myHero.spellbook:CanUseSpell(SpellSlot.E) == SpellState.Ready and _G.Prediction.IsValidTarget(target) then
        self.spell.qe.delay = 0.25
        local myHeroPred = _G.Prediction.GetUnitPosition(myHero, NetClient.ping / 2000 + 0.1)
        local checkPred = _G.Prediction.GetPrediction(target, self.spell.qe, myHeroPred)
        if not checkPred then
            return
        end
        collOrbs, maxHit, maxOrb = {}, 0, nil
        --check which orb can be hit
        local checkWidth = checkPred.realHitChance == 1 and self.spell.e.widthMax or 100
        local checkSpell =
            setmetatable(
            {
                width = self.spell.qe.width - checkWidth / 2
            },
            {__index = self.spell.qe}
        )
        checkPred = _G.Prediction.GetPrediction(target, checkSpell, myHeroPred)
        if checkPred and checkPred.castPosition and checkPred.rates["slow"] then
            --check which orbs can hit enemy
            for i = 1, #canHitOrbs do
                local orb = canHitOrbs[i]
                local castPosition = self:GetCastPosition(checkPred)
                if GetDistanceSqr(castPosition) > GetDistanceSqr(orb.obj.position) then
                    self:CalcQELong(target, GetDistance(orb.obj.position))
                    local seg =
                        LineSegment(
                        Vector(myHeroPred):extended(Vector(orb.obj.position), self.spell.qe.range),
                        Vector(myHeroPred)
                    )
                    if seg:distanceTo(Vector(castPosition)) <= checkWidth / 2 then
                        collOrbs[orb] = 0
                    end
                else
                    local pred = self:CalcQEShort(target, checkWidth, "q")
                    if pred and pred.castPosition then
                        local castPosition = self:GetCastPosition(pred)
                        if GetDistanceSqr(castPosition, orb.obj.position) <= 400 * 400 then
                            local seg =
                                LineSegment(
                                Vector(myHeroPred):extended(Vector(orb.obj.position), self.spell.qe.range),
                                Vector(myHeroPred)
                            )
                            if
                                seg:distanceTo(self:GetQPos(castPosition)) <= checkWidth / 2 and
                                    self:CanEQ(self:GetQPos(castPosition), pred, target)
                             then
                                collOrbs[orb] = 0
                            end
                        end
                    end
                end
            end

            -- look for cast with most orbs hit
            for orb, num in pairs(collOrbs) do
                for i = 1, #canHitOrbs do
                    local orb2 = canHitOrbs[i]
                    if
                        Vector(myHeroPred):angleBetween(Vector(orb), Vector(orb2)) <=
                            (myHero.spellbook:Spell(2).level < 5 and self.spell.e.angle / 2 or
                                self.spell.e.passiveAngle / 2)
                     then
                        num = num + 1
                    end
                end
                if num > maxHit then
                    maxHit = num
                    maxOrb = orb
                end
            end
            if maxHit > 0 and maxOrb then
                myHero.spellbook:CastSpell(SpellSlot.E, maxOrb.obj.position)
                self.last.e = os.clock()
                PrintChat("e")

                return true
            end
        end
    end
end

function Syndra:CastQEShort(pred)
    if
        myHero.spellbook:CanUseSpell(SpellSlot.Q) == SpellState.Ready and
            myHero.spellbook:CanUseSpell(SpellSlot.E) == SpellState.Ready and
            myHero.mana >= 80 + 10 * myHero.spellbook:Spell(0).level and
            (not self.spell.e.next or GetDistanceSqr(self.spell.e.next.pos) > self.spell.e.range * self.spell.e.range or
                self.spell.e.next.time <=
                    os.clock() + self.spell.e.delay + GetDistance(pred.castPosition) / self.spell.e.speed)
     then
        myHero.spellbook:CastSpell(SpellSlot.Q, self:GetQPos(pred.castPosition, "q"):toDX3())
        self.last.q = os.clock()
        pred:draw()
        self.spell.e.queue = {pos = pred.castPosition, time = os.clock() + 0.1 + NetClient.ping / 1000, spell = 0}
        return true
    end
end

function Syndra:CastQELong(pred)
    if pred.rates["slow"] then
        local myHeroPred = _G.Prediction.GetUnitPosition(myHero, NetClient.ping / 2000 + 0.06)
        local castPosition = self:GetCastPosition(pred)
        local qPos = Vector(myHeroPred):extended(Vector(castPosition), (self.spell.q.range - 100)):toDX3()
        myHero.spellbook:CastSpell(SpellSlot.Q, qPos)
        self.last.q = os.clock()
        pred:draw()
        self.spell.e.queue = {pos = castPosition, time = os.clock() + 0.1 + NetClient.ping / 1000, spell = 0}
        return true
    end
end

function Syndra:GetQPos(predPos, spell)
    local myHeroPred = _G.Prediction.GetUnitPosition(myHero, NetClient.ping / 2000 + 0.06)
    if spell == "q" then
        return Vector(myHeroPred):extended(Vector(predPos), math.max(GetDistance(predPos) + 50, 550))
    elseif spell == "w" then
        return Vector(myHeroPred):extended(Vector(predPos), math.max(GetDistance(predPos) + 50, 600))
    end
    return Vector(myHeroPred):extended(Vector(predPos), math.min(GetDistance(predPos) + 450, 850))
end

function Syndra:CastWE(pred)
    if
        myHero.spellbook:CanUseSpell(SpellSlot.W) == SpellState.Ready and
            myHero.spellbook:CanUseSpell(SpellSlot.E) == SpellState.Ready and
            myHero.mana >= 100 + 10 * myHero.spellbook:Spell(1).level and
            self.spell.w.heldInfo and
            self.spell.w.heldInfo.isOrb
     then
        myHero.spellbook:CastSpell(SpellSlot.W, self:GetQPos(pred.castPosition, "q"):toDX3())
        self.last.w = os.clock()
        pred:draw()
        self.spell.e.queue = {pos = pred.castPosition, time = os.clock() + 0.1, spell = 1}
        return true
    end
end

function Syndra:GetIgnite(target)
    return ((self.ignite and myHero.spellbook:CanUseSpell(self.ignite) == SpellState.Ready and
        GetDistanceSqr(target) <= 600 * 600) and
        50 + 20 * myHero.experience.level) or
        nil
end

function Syndra:UseIgnite(target)
    local ignite = self:GetIgnite(target)
    if
        ignite and ignite > target.health + target.allShield and myHero.spellbook:CanUseSpell(3) ~= SpellState.Ready and
            ((myHero.spellbook:CanUseSpell(0) == SpellState.Ready and 1 or 0) +
                (myHero.spellbook:CanUseSpell(1) == SpellState.Ready and 1 or 0) +
                (myHero.spellbook:CanUseSpell(2) == SpellState.Ready and 1 or 0) <=
                1 or
                myHero.health / myHero.maxHealth < 0.2)
     then
        myHero.spellbook:CastSpell(self.ignite, target.networkId)
        return true
    end
end

function Syndra:RExecutes(target)
    local count = math.min(7, 3 + #self.orbs)
    local base = count * (45 + 50 * myHero.spellbook:Spell(SpellSlot.R).level + 0.2 * self:GetTotalAp())
    local buffs = myHero.buffManager.buffs
    for i = 1, #buffs do
        local buff = buffs[i]
        if buff.name == "itemmagicshankcharge" and buff.count >= 90 then
            base = base + 100 + 0.1 * self:GetTotalAp()
        elseif buff.name == "ASSETS/Perks/Styles/Sorcery/SummonAery/SummonAery.lua" then
            base = base + 8.235 + 1.765 * myHero.experience.level + 0.1 * self:GetTotalAp()
        elseif buff.name == "ASSETS/Perks/Styles/Domination/Electrocute/Electrocute.lua" then
            if self.electrocuteTracker[target.networkId] and #self.electrocuteTracker[target.networkId] >= 1 then
                base = base + 21.176 + 8.824 * myHero.experience.level + 0.25 * self:GetTotalAp()
            end
        end
    end
    base = dmgLib:CalculateMagicDamage(myHero, target, base)
    local ignite = self:GetIgnite(target)
    self.rDamages[target] = base + (ignite or 0)
    local diff = target.health - base
    if diff <= 0 then
        return true, false
    elseif ignite and diff <= ignite then
        return true, true
    else
        return false, false
    end
end

function Syndra:RConditions(target)
    local canExecute, needIgnite = self:RExecutes(target)
    if not canExecute then
        return false
    end
    local rDist = 675 + (myHero.spellbook:Spell(SpellSlot.R).level / 3) * 75
    if
        not (Orbwalker:GetMode() == "Combo" and myHero.spellbook:CanUseSpell(SpellSlot.R) == SpellState.Ready and
            self.menu.r[tostring(target.networkId)] and
            self.menu.r[tostring(target.networkId)]:get() and
            GetDistanceSqr(target.position) <= rDist * rDist)
     then
        return false
    end

    if self.menu.r.c0:get() then
        return true, needIgnite
    end

    if self.menu.r.c1:get() and NavMesh:IsWall(target.position) then
        return true, needIgnite
    end

    if self.menu.r.c2:get() and myHero.health / myHero.maxHealth <= target.health / target.maxHealth then
        return true, needIgnite
    end

    if self.menu.r.c3:get() and myHero.health / myHero.maxHealth <= self.menu.r.c3:get() / 100 then
        return true, needIgnite
    end

    if
        self.menu.r.c4:get() and
            target.health -
                dmgLib:CalculateMagicDamage(
                    myHero,
                    target,
                    30 + 40 * myHero.spellbook:Spell(SpellSlot.Q).level + 0.65 * self:GetTotalAp()
                ) <=
                0
     then
        return false
    end

    enemiesInRange1, enemiesInRange2, alliesInRange = 0, 0, 0
    for _, enemy in pairs(ObjectManager:GetEnemyHeroes()) do
        if GetDistanceSqr(enemy.position) <= 800 * 800 then
            enemiesInRange1 = enemiesInRange1 + 1
        end
        if GetDistanceSqr(enemy.position) <= 2500 * 2500 then
            enemiesInRange2 = enemiesInRange2 + 1
        end
    end

    for _, ally in pairs(ObjectManager:GetAllyHeroes()) do
        if GetDistanceSqr(ally.position) <= 800 * 800 then
            alliesInRange = alliesInRange + 1
        end
    end

    if self.menu.r.c5:get() and enemiesInRange1 > alliesInRange then
        return true, needIgnite
    end

    if self.menu.r.c6:get() and myHero.mana < 200 then
        return true, needIgnite
    end

    if target.characterIntermediate.spellBlock < self.menu.r.c7:get() then
        return true, needIgnite
    end

    if enemiesInRange2 <= self.menu.r.c8:get() then
        return true, needIgnite
    end
end

function Syndra:CastR(target)
    local shouldCast, needIgnite = self:RConditions(target)
    if shouldCast then
        if needIgnite then
            myHero.spellbook:CastSpell(self.ignite, target.networkId)
        end
        myHero.spellbook:CastSpell(SpellSlot.R, target.networkId)
        self.last.r = os.clock()
        PrintChat("r")
        return true
    end
end

function Syndra:OnCreateObj(obj)
    if obj.name == "Seed" and obj.team == myHero.team and obj.spellbook.owner.charName == "SyndraSphere" then
        local replaced = false
        for i in pairs(self.orbs) do
            local orb = self.orbs[i]
            if not orb.isInitialized and GetDistanceSqr(obj.position, orb.obj.position) == 0 then
                self.orbs[i] = {obj = obj, isInitialized = true, endT = os.clock() + 6.25}
                replaced = true
            end
        end
        if not replaced then
            self.orbs[#self.orbs + 1] = {obj = obj, isInitialized = true, endT = os.clock() + 6.25}
        end
    end
    if string.match(obj.name, "Syndra") then
        if string.match(obj.name, "heldTarget_buf_02") then
            self.spell.w.heldInfo = nil
            local minions = ObjectManager:GetEnemyMinions()
            local maxObj = nil
            local maxTime = 0
            for i = 1, #minions do
                local minion = minions[i]
                if minion and not minion.isDead and GetDistanceSqr(minion) < self.spell.w.range * self.spell.w.range then
                    local buffs = minion.buffManager.buffs
                    for i = 1, #buffs do
                        local buff = buffs[i]
                        if buff.name == "syndrawbuff" and maxTime < buff.remainingTime then
                            maxObj = minion
                            maxTime = buff.remainingTime
                        end
                    end
                end
            end
            if maxObj then
                self.spell.w.heldInfo = {obj = maxObj, isOrb = false}
            end
            if not self.spell.w.heldInfo then
                for i in pairs(self.orbs) do
                    local orb = self.orbs[i]
                    if orb.isInitialized and GetDistance(obj.position, orb.obj.position) <= 1 then
                        self.spell.w.heldInfo = {obj = orb.obj, isOrb = true}
                        orb.endT = os.clock() + 6.25
                        self.spell.e.blacklist[orb.obj] = {pos = orb.obj.position, time = os.clock() + 0.06}
                    end
                end
            end
        end
        if myHero.buffManager:HasBuff("ASSETS/Perks/Styles/Domination/Electrocute/Electrocute.lua") then
            if string.match(obj.name, "Q_tar_sound") or string.match(obj.name, "W_tar") then
                for _, enemy in pairs(ObjectManager:GetEnemyHeroes()) do
                    if enemy.isVisible and GetDistanceSqr(enemy.position, obj.position) < 1 then
                        if not self.electrocuteTracker[enemy.networkId] then
                            self.electrocuteTracker[enemy.networkId] = {}
                        end
                        table.insert(self.electrocuteTracker[enemy.networkId], os.clock())
                    end
                end
            elseif string.match(obj.name, "E_tar") then
                local isOrb = false
                for i in pairs(self.orbs) do
                    if GetDistanceSqr(self.orbs[i].obj.position, obj.position) < 1 then
                        isOrb = true
                    end
                end
                if not isOrb then
                    for _, enemy in pairs(ObjectManager:GetEnemyHeroes()) do
                        if enemy.isVisible and GetDistanceSqr(enemy.position, obj.position) < 1 then
                            if not self.electrocuteTracker[enemy.networkId] then
                                self.electrocuteTracker[enemy.networkId] = {}
                            end
                            table.insert(self.electrocuteTracker[enemy.networkId], os.clock())
                        end
                    end
                end
            end
        end
    end
end

function Syndra:OnDeleteObj(obj)
    if obj.name == "Seed" and obj.team == myHero.team then
        for i in pairs(self.orbs) do
            if self.orbs[i].obj == obj then
                table.remove(self.orbs, i)
            end
        end
    end
    if
        myHero.buffManager:HasBuff("ASSETS/Perks/Styles/Domination/Electrocute/Electrocute.lua") and
            string.match(obj.name, "SyndraBasicAttack")
     then
        for _, enemy in pairs(ObjectManager:GetEnemyHeroes()) do
            if enemy == obj.asMissile.target then
                if not self.electrocuteTracker[enemy.networkId] then
                    self.electrocuteTracker[enemy.networkId] = {}
                end
                table.insert(self.electrocuteTracker[enemy.networkId], os.clock())
            end
        end
    end
end

function Syndra:OnBuffLost(obj, buff)
    if obj == myHero then
        if buff.name == "syndrawtooltip" then
            self.spell.w.heldInfo = nil
        elseif buff.name == "ASSETS/Perks/Styles/Domination/Electrocute/Electrocute.lua" then
            self.electrocuteTracker = {}
        end
    end
end

function Syndra:OnProcessSpell(obj, spell)
    if obj == myHero then
        if spell.spellData.name == "SyndraQ" then
            self.last.q = nil
            self.orbs[#self.orbs + 1] = {
                obj = {position = spell.endPos},
                isInitialized = false,
                endT = os.clock() + 0.625
            }
            if
                self.spell.e.queue and self.spell.e.queue.spell == 0 and
                    myHero.spellbook:CanUseSpell(SpellSlot.E) == SpellState.Ready
             then
                self.spell.e.next = nil
                myHero.spellbook:CastSpell(SpellSlot.E, self.spell.e.queue.pos)
                self.last.e = os.clock()
                self.spell.e.queue = nil
            end
        elseif spell.spellData.name == "SyndraW" then
            --self.last.w = nil
        elseif spell.spellData.name == "SyndraWCast" then
            self.last.w = nil
            if
                self.spell.e.queue and self.spell.e.queue.spell == 1 and
                    myHero.spellbook:CanUseSpell(SpellSlot.E) == SpellState.Ready
             then
                myHero.spellbook:CastSpell(SpellSlot.E, self.spell.e.queue.pos)
                self.last.e = os.clock()
                self.spell.e.queue = nil
            end
            self.spell.e.next = {
                time = os.clock() + self.spell.w.delay,
                pos = spell.endPos
            }
        elseif spell.spellData.name == "SyndraE" then
            self.last.e = nil
            local myHeroPred = _G.Prediction.GetUnitPosition(myHero, NetClient.ping / 1000)
            local posVec = Vector(myHeroPred)
            for i in pairs(self.orbs) do
                if
                    GetDistanceSqr(myHeroPred, self.orbs[i].obj.position) <= self.spell.e.range * self.spell.e.range and
                        posVec:angleBetween(Vector(spell.endPos), Vector(self.orbs[i].obj.position)) <=
                            (myHero.spellbook:Spell(2).level < 5 and self.spell.e.angle / 2 + 10 or
                                self.spell.e.passiveAngle / 2 + 10)
                 then
                    self.spell.w.blacklist[i] = {
                        interceptTime = os.clock() +
                            GetDistance(myHeroPred, self.orbs[i].obj.position) / self.spell.e.speed +
                            0.4,
                        nextCheckTime = os.clock() + 0.1 + NetClient.ping / 1000,
                        pos = self.orbs[i].obj.position
                    }
                end
            end
        elseif spell.spellData.name == "SyndraR" then
            self.last.r = nil
        end
    end
end

function Syndra:GetTarget(spell, all, targetFilter, predFilter)
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

function Syndra:GetTargetRange(dist, all)
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

function Syndra:GetTotalAp()
    return myHero.characterIntermediate.flatMagicDamageMod +
        myHero.characterIntermediate.flatMagicDamageMod * myHero.characterIntermediate.percentMagicDamageMod
end

if myHero.charName == "Syndra" then
    Syndra:init()
end

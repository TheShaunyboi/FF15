if myHero.charName ~= "Syndra" then return end

local Syndra = {}
local version = 3.11

require "FF15Menu"
require "utils"

local Vector
local LineSegment = require("GeometryLib").LineSegment
local dmgLib = require("FF15DamageLib")
local DreamTS = require("DreamTS")
local Orbwalker = require("FF15OL")

local byte, match, floor, min, max, abs, rad, huge, clock, insert, remove =
    string.byte,
    string.match,
    math.floor,
    math.min,
    math.max,
    math.abs,
    math.rad,
    math.huge,
    os.clock,
    table.insert,
    table.remove

local function GetDistanceSqr(p1, p2)
    p2 = p2 or myHero
    local dx = p1.x - p2.x
    local dz = p1.z - p2.z
    return dx*dx + dz*dz
end
    

function OnLoad()
    if not _G.Prediction then
        LoadPaidScript(PaidScript.DREAM_PRED)
    end
    Vector = _G.Prediction.Vector
    
    function Vector:angleBetweenFull(v1, v2)
        local p1, p2 = (-self + v1), (-self + v2)
        local theta = p1:polar() - p2:polar()
        if theta < 0 then
            theta = theta + 360
        end
        return theta
    end

    Syndra:init()
end

function Syndra:init()
    self.orbSetup = false
    self.unitsInRange = {}
    self.enemyHeroes = ObjectManager:GetEnemyHeroes()
    self.allyHeroes = ObjectManager:GetAllyHeroes()
    self.spell = {
        q = {
            type = "circular",
            range = 800,
            rangeSqr = 800 * 800,
            delay = 0.65,
            radius = 200,
            speed = huge
        },
        w = {
            type = "circular",
            range = 950,
            grabRangeSqr = 925 * 925,
            delay = 0.75,
            radius = 220,
            speed = huge,
            heldInfo = nil,
            useHeroSource = true,
            blacklist = {}, -- for orbs
            blacklist2 = nil -- for champions
        },
        e = {
            type = "linear",
            speed = 1600,
            rangeSqr = 700 * 700,
            range = 700,
            delay = 0.25,
            width = 200,
            widthMax = 200,
            angle = 40,
            angle1 = 40,
            angle2 = 60,
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
            range = 1250,
            delay = 0.27,
            speed = 2000,
            width = 200,
            collision = {
                ["Wall"] = true,
                ["Hero"] = false,
                ["Minion"] = false
            }
        },
        r = {
            type = "targetted",
            speed = 2000,
            delay = 0,
            range = 2000,
            castRange = 675,
            collision = {
                ["Wall"] = true,
                ["Hero"] = false,
                ["Minion"] = false
            }
        }
    }
    self.myHeroPred = myHero.position
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
        ["TestCubeRender"] = true,
        ["SRU_RazorbeakMini"] = true,
        ["SRU_Razorbeak"] = true,
        ["SRU_MurkwolfMini"] = true,
        ["SRU_Murkwolf"] = true,
        ["SRU_Gromp"] = true,
        ["Sru_Crab"] = true,
        ["SRU_Red"] = true,
        ["SRU_Blue"] = true,
        ["EliseSpiderling"] = true,
        ["HeimerTYellow"] = true,
        ["HeimerTBlue"] = true,
        ["MalzaharVoidling"] = true,
        ["ShacoBox"] = true,
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
        Events.OnExecuteCastFrame,
        function(obj, spell)
            self:OnExecuteCastFrame(obj, spell)
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
    self.menu = Menu("SyndraEmpyrean", "Syndra - Empyrean v" .. version)
    self.menu:sub("dreamTs", "Target Selector")
    self.menu:checkbox("qe2", "Use Long Stun", true, byte("Z"))
    self.menu:checkbox("e", "AutoE", true, byte("T"))
    self.menu:sub("antigap", "Anti-Gapcloser")
    for _, enemy in ipairs(ObjectManager:GetEnemyHeroes()) do
        self.menu.antigap:checkbox(enemy.charName, enemy.charName, true)
    end
    --[[   self.menu:sub("interrupt", "Interrupter")
    _G.Prediction.LoadInterruptToMenu(self.menu.interrupt) ]]
    self.menu:sub("r", "R")
    for _, enemy in ipairs(self.enemyHeroes) do
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
        return pred.castPosition, true
    else
        return pred.castPosition, false
    end
end

function Syndra:OnTick()
    self.myHeroPred = _G.Prediction.GetUnitPosition(myHero, NetClient.ping / 2000 + 0.06)
    self.spell.e.angle = myHero.spellbook:Spell(2).level < 5 and self.spell.e.angle1 or self.spell.e.angle2

    if not self.orbSetup and (_G.AuroraOrb or _G.LegitOrbwalker) then
        Orbwalker:Setup()
        self.orbSetup = true
    end

    if self.spell.w.blacklist2 and clock() >= self.spell.w.blacklist2.time + 0.8 then
        self.spell.w.blacklist2 = nil
    end
    for _, stacks in pairs(self.electrocuteTracker) do
        for i, time in pairs(stacks) do
            if clock() >= time + 2.75 - 0.06 - NetClient.ping / 2000 then
                stacks[i] = nil
            end
        end
    end
    for i in ipairs(self.spell.w.blacklist) do
        if not self.orbs[i] then
            self.spell.w.blacklist[i] = nil
        elseif self.spell.w.blacklist[i].nextCheckTime and clock() >= self.spell.w.blacklist[i].nextCheckTime then
            if
                clock() >= self.spell.w.blacklist[i].interceptTime and
                    GetDistanceSqr(self.orbs[i].obj.position, self.spell.w.blacklist[i].pos) == 0
             then
                self.spell.w.blacklist[i] = nil
            else
                self.spell.w.blacklist[i].pos = self.orbs[i].obj.position
                self.spell.w.blacklist[i].nextCheckTime = clock() + 0.3
            end
        end
    end

    for orb in pairs(self.spell.e.blacklist) do
        if self.spell.e.blacklist[orb].time <= clock() then
            if
                not (self.spell.w.heldInfo and orb == self.spell.w.heldInfo.obj) and
                    GetDistanceSqr(self.spell.e.blacklist[orb].pos, orb.position) == 0
             then
                self.spell.e.blacklist[orb] = nil
            else
                self.spell.e.blacklist[orb] = {pos = orb.position, time = clock() + 0.1 + NetClient.ping / 1000}
            end
        end
    end

    for i in ipairs(self.orbs) do
        local orb = self.orbs[i]
        if clock() >= orb.endT or (orb.obj.health and orb.obj.health ~= 1) then
            remove(self.orbs, i)
        end
    end

    if self:ShouldCast() and self.orbSetup then
        self:Combo()
    end
end

function Syndra:Combo()
    for _, enemy in ipairs(self.enemyHeroes) do
        self.unitsInRange[enemy.networkId] = enemy.position and not enemy.isDead and GetDistanceSqr(enemy) < 4000000 --2000 range
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
    local canHitOrbs = self:GetHitOrbs()
    local canE = false
    if e then
        self.spell.e.delay = 0.32
        local weTarget, wePred =
            self:GetTarget(
            self.spell.e,
            false,
            function(unit)
                if not self.unitsInRange[unit.networkId] then
                    return
                end
                if self:CalcQEShort(unit, self.spell.e.widthMax, "w") then
                    return unit
                end
            end
        )
        if weTarget and wePred then
            canE = true
            if wePred.rates["very slow"] and (Orbwalker:GetMode() == "Combo" or (wePred.targetDashing and self.menu.antigap[weTarget.charName]:get())) then
                if self:CastWEShort(wePred, canHitOrbs) then
                    self.spell.w.blacklist2 = {target = weTarget.networkId, time = clock()}
                    return true
                end
            end
        end
        local qeTarget, qePred =
            self:GetTarget(
            self.spell.e,
            false,
            function(unit)
                if not self.unitsInRange[unit.networkId] then
                    return
                end
                if self:CalcQEShort(unit, self.spell.e.widthMax, "q") then
                    return unit
                end
            end
        )
        if qeTarget and qePred then
            canE = true
            if qePred.rates["very slow"] and (Orbwalker:GetMode() == "Combo" or (qePred.targetDashing and self.menu.antigap[qeTarget.charName]:get())) then
                if self:CastQEShort(qePred, qeTarget, canHitOrbs) then
                    self.spell.w.blacklist2 = {target = qeTarget.networkId, time = clock()}
                    return true
                end
            end
        end

        local eTargets = self:GetTargetRange(self.spell.qe.range, true)
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
    self.spell.r.castRange = 675 + (myHero.spellbook:Spell(SpellSlot.R).level / 3) * 75
    self:CalcRDamage()
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
                if w1 and (notE or (isOrb or q) or not self:WaitToInitialize()) and self:CastW1() then
                    return
                end
                if
                    not (self.spell.w.blacklist2 and wTarget.networkId == self.spell.w.blacklist2.target) and
                        self.spell.w.heldInfo and
                        (notE or not self.spell.w.heldInfo.isOrb) and
                        self:CastW2(wPred)
                 then
                    return
                end
            end
        end
        if e and not canE then
            local eTarget, ePred =
                self:GetTarget(
                self.spell.qe,
                false,
                function(unit)
                    return self.unitsInRange[unit.networkId] and self:CalcQELong(unit, self.spell.q.range - 100) and
                        unit
                end
            )
            if
                eTarget and ePred and ePred.rates["slow"] and
                    (GetDistanceSqr(ePred.castPosition) <= self.spell.e.rangeSqr or self.menu.qe2:get())
             then
                if (w and self:CastWELong(ePred, eTarget, canHitOrbs)) or (q and self:CastQELong(ePred, canHitOrbs)) then
                    --PrintChat("e long")
                    return
                end
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
        if qTarget and qPred and not (self.spell.w.blacklist2 and qTarget.networkId == self.spell.w.blacklist2.target) then
            if
                ((Orbwalker:GetMode() == "Combo" and
                    (notE or GetDistanceSqr(qPred.castPosition) >= self.spell.e.rangeSqr)) or
                    Orbwalker:GetMode() == "Harass") and
                    self:CastQ(qPred)
             then
                return
            end
        end
    end
end

function Syndra:OnDraw()
    DrawHandler:Circle3D(myHero.position, self.spell.q.range, Color.White)
    DrawHandler:Circle3D(myHero.position, self.spell.qe.range, Color.White)
    --[[   for i in pairs(self.orbs) do
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
    end ]]
    local text =
        (self.menu.qe2:get() and "Long Stun On" or "Long Stun Off") ..
        "\n" .. (self.menu.e:get() and "Auto E: On" or "Auto E: Off")
    DrawHandler:Text(DrawHandler.defaultFont, Renderer:WorldToScreen(myHero.position), text, Color.White)
    --[[ if myHero.spellbook:CanUseSpell(SpellSlot.R) == SpellState.Ready then
        for target, damage in pairs(self.rDamages) do
            local hpBarPos = target.infoComponent.hpBarScreenPosition
            local xPos = hpBarPos.x - 44 + 104 * damage / (target.maxHealth + target.allShield)
            local startPos = D3DXVECTOR2(xPos, hpBarPos.y - 24)
            local endPos = D3DXVECTOR2(xPos, hpBarPos.y - 13)
            DrawHandler:Line(startPos, endPos, Color.SkyBlue)
        end
    end ]]
end

function Syndra:WaitToInitialize()
    for i in ipairs(self.orbs) do
        local orb = self.orbs[i]
        if not orb.isInitialized and GetDistanceSqr(orb.obj.position) <= self.spell.w.grabRangeSqr then
            return true
        end
    end
end

function Syndra:ShouldCast()
    if not self.spell.e.queue then
        for spell, time in pairs(self.last) do
            if not time or (time and clock() < time) then
                return false
            end
        end
        return true
    end
end

function Syndra:AutoGrab()
    if not _G.Prediction.IsRecalling(myHero) then
        for _, minion in ipairs(ObjectManager:GetEnemyMinions()) do
            if
                (minion.name == "Tibbers" or minion.name == "IvernMinion" or minion.name == "H-28G Evolution Turret") and
                    GetDistanceSqr(minion) < self.spell.w.grabRangeSqr
             then
                myHero.spellbook:CastSpell(SpellSlot.W, minion.position)
                self.last.w = clock() + 0.5
                return true
            end
        end
    end
end

function Syndra:CastQ(pred)
    if myHero.spellbook:CanUseSpell(SpellSlot.Q) == SpellState.Ready then
        if pred and pred.castPosition and pred.rates["very slow"] then
            myHero.spellbook:CastSpell(SpellSlot.Q, pred.castPosition)
            self.last.q = clock() + 0.5
            pred:draw()
            self.orbs[#self.orbs + 1] = {
                obj = {position = pred.castPosition},
                isInitialized = false,
                isCasted = false,
                endT = clock() + 0.25
            }
            --PrintChat("q")
            return true
        end
    end
end

function Syndra:GetGrabTarget()
    local lowTime = huge
    local lowOrb = nil
    for i in ipairs(self.orbs) do
        local orb = self.orbs[i]
        if
            not self.spell.w.blacklist[i] and orb.isInitialized and orb.endT < lowTime and
                GetDistanceSqr(orb.obj.position) <= self.spell.w.grabRangeSqr
         then
            lowTime = orb.endT
            lowOrb = orb.obj
        end
    end
    if lowOrb then
        return lowOrb, true
    end

    local minionsInRange = ObjectManager:GetEnemyMinions()
    local lowHealth = huge
    local lowMinion = nil
    for _, minion in ipairs(minionsInRange) do
        if
            minion and self.wGrabList[minion.charName] and _G.Prediction.IsValidTarget(minion) and
                GetDistanceSqr(minion.position) <= self.spell.w.grabRangeSqr
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
        self.last.w = clock() + 0.5
        --PrintChat("w1" .. target.name .. GetDistance(target.position))
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
        self.last.w = clock() + 0.5
        pred:draw()
        --PrintChat("w2")
        return true
    end
end

function Syndra:CastShortEMode(mode, canHitOrbs)
    local eTarget, ePred =
        self:GetTarget(
        self.spell.e,
        false,
        function(unit)
            if not self.unitsInRange[unit.networkId] then
                return
            end
            if self:CalcQEShort(unit, self.spell.e.widthMax, mode) then
                return unit
            end
        end
    )
    if eTarget and ePred and ePred.rates["very slow"] and (Orbwalker:GetMode() == "Combo" or pred.targetDashing) then
        if mode == "q" and self:CastQEShort(ePred, eTarget, canHitOrbs) or self:CastWEShort(ePred, canHitOrbs) then
            self.spell.w.blacklist2 = {target = eTarget.networkId, time = clock()}
            --PrintChat("e short")
            return true
        end
    end
end

function Syndra:GetHitOrbs()
    local canHitOrbs = {}
    for i in ipairs(self.orbs) do
        local orb = self.orbs[i]
        local distToOrb = GetDistance(orb.obj.position)
        if distToOrb <= self.spell.q.range then
            local timeToHitOrb = self.spell.e.delay + (distToOrb / self.spell.e.speed)
            local expectedHitTime = clock() + timeToHitOrb - 0.1
            local canHitOrb =
                orb.isCasted and
                (orb.isInitialized and (expectedHitTime + 0.1 < orb.endT) or (expectedHitTime > orb.endT)) and
                (not orb.isInitialized or (orb.obj and not self.spell.e.blacklist[orb.obj])) and
                (not self.spell.w.heldInfo or orb.obj ~= self.spell.w.heldInfo.obj)
            if canHitOrb then
                canHitOrbs[#canHitOrbs + 1] = orb
            end
        end
    end
    return canHitOrbs
end

function Syndra:CanEQ(qPos, pred, target)
    --wall check
    local interval = 50
    local castPosition = self:GetCastPosition(pred)
    local count = floor(GetDistance(castPosition, qPos:toDX3()) / interval)
    local diff = (Vector(castPosition) - qPos):normalized()
    for i = 0, count do
        local pos = (Vector(qPos) + diff * i * interval):toDX3()
        if NavMesh:IsWall(pos) then
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
            if abs(last - list[i]) < 0.01 then
                local maxInd = 0
                local maxVal = -huge
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

function Syndra:CheckHitOrb(castPos)
    for i in ipairs(self.orbs) do
        if
            GetDistanceSqr(self.myHeroPred, self.orbs[i].obj.position) <= self.spell.q.rangeSqr and
                Vector(self.myHeroPred):angleBetween(Vector(castPos), Vector(self.orbs[i].obj.position)) <=
                    (self.spell.e.angle + 10) / 2
         then
            self.spell.w.blacklist[i] = {
                interceptTime = clock() + GetDistance(self.myHeroPred, self.orbs[i].obj.position) / self.spell.e.speed +
                    0.5,
                nextCheckTime = clock() + 0.3,
                pos = self.orbs[i].obj.position
            }
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
        if pred and pred.castPosition and GetDistanceSqr(pred.targetPosition) >= self.spell.e.rangeSqr then
            local castPosition, isAdjusted = self:GetCastPosition(pred)
            local offset = isAdjusted and -target.boundingRadius or 0
            local distToCast = GetDistance(castPosition)
            self.spell.qe.speed =
                (self.spell.e.speed * dist + self.spell.qe.pingPongSpeed * (distToCast + offset - dist)) /
                (distToCast + offset)
            lasts[#lasts + 1] = self.spell.qe.speed
            check = self:CheckForSame(lasts)
        else
            return
        end
    end
    self.spell.qe.speed = check
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
    if not self:CanEQ(self:GetQPos(pred.castPosition, "q"), pred, target) then
        return
    end
    return pred
end



function Syndra:CalcBestCastAngle(colls, all)
    local maxCount = 0
    local maxStart = nil
    local maxEnd = nil
    for i = 1, #all do
        local base = all[i]
        local endAngle = base + self.spell.e.angle
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
        local hasColl = colls[angle]
        local endDelta = angle
        while (isContained(count, angle, base, over360, endAngle)) do
            if count > 10 then
                print("wtf")
            end
            if colls[angle] then
                hasColl = true
            end
            endDelta = all[j]
            count = count + 1
            j = j + 1
            if j > #all then
                j = 1
            end
            angle = all[j]
        end
        if hasColl and count > maxCount then
            maxCount = count
            maxStart = base
            maxEnd = endDelta
        end
    end
    if maxStart and maxEnd then
        if maxStart + self.spell.e.angle > 360 then
            maxEnd = maxEnd + 360
        end
        local res = (maxStart + maxEnd) / 2
        if res > 360 then
            res = res - 360
        end
        --PrintChat("count: " .. maxCount .. " res: " .. res)
        return rad(res)
    end
end

function Syndra:CastE(target, canHitOrbs)
    if myHero.spellbook:CanUseSpell(SpellSlot.E) == SpellState.Ready and #canHitOrbs >= 1 then
        local checkPred = _G.Prediction.GetPrediction(target, self.spell.qe, self.myHeroPred)
        if not checkPred then
            return
        end
        local collOrbs, maxHit, maxOrb = {}, 0, nil
        --check which orb can be hit
        local checkWidth = checkPred.realHitChance == 1 and self.spell.e.widthMax or 100
        local checkSpell =
            setmetatable(
            {
                width = self.spell.qe.width - checkWidth / 2
            },
            {__index = self.spell.qe}
        )
        checkPred = _G.Prediction.GetPrediction(target, checkSpell, self.myHeroPred)
        if checkPred and checkPred.castPosition and checkPred.rates["very slow"] then
            --check which orbs can hit enemy
            for i = 1, #canHitOrbs do
                local orb = canHitOrbs[i]
                local castPosition = self:GetCastPosition(checkPred)
                if GetDistanceSqr(castPosition) > GetDistanceSqr(orb.obj.position) then
                    self:CalcQELong(target, GetDistance(orb.obj.position))
                    local seg =
                        LineSegment(
                        Vector(self.myHeroPred):extended(Vector(orb.obj.position), self.spell.qe.range),
                        Vector(self.myHeroPred)
                    )
                    if seg:distanceTo(Vector(castPosition)) <= checkWidth / 2 then
                        collOrbs[orb] = 0
                    end
                else
                    self.spell.e.delay = 0.25
                    local pred = self:CalcQEShort(target, checkWidth, "q")
                    if pred and pred.castPosition then
                        local castPosition = self:GetCastPosition(pred)
                        if GetDistanceSqr(castPosition, orb.obj.position) <= 160000 then -- 400 range
                            local seg =
                                LineSegment(
                                Vector(self.myHeroPred):extended(Vector(orb.obj.position), self.spell.qe.range),
                                Vector(self.myHeroPred)
                            )
                            if seg:distanceTo(self:GetQPos(castPosition)) <= self.spell.e.width / 4 then
                                collOrbs[orb] = 0
                            end
                        end
                    end
                end
            end

            -- look for cast with most orbs hit
            local basePosition = canHitOrbs[1].obj.position
            local canHitOrbAngles, collOrbAngles = {}, {}
            for i = 1, #canHitOrbs do
                local orb = canHitOrbs[i]
                local angle = Vector(self.myHeroPred):angleBetweenFull(Vector(basePosition), Vector(orb.obj.position))
                canHitOrbAngles[i] = angle
                if collOrbs[orb] then
                    collOrbAngles[angle] = true
                end
            end
            table.sort(canHitOrbAngles)
            local best = self:CalcBestCastAngle(collOrbAngles, canHitOrbAngles)
            if best then
                local castPosition =
                    (Vector(self.myHeroPred) +
                    (Vector(basePosition) - Vector(self.myHeroPred)):rotated(0, best, 0):normalized() *
                        self.spell.e.range):toDX3()
                myHero.spellbook:CastSpell(SpellSlot.E, castPosition)
                self.last.e = clock() + 0.5
                --PrintChat("e")
                return true
            end
        end
    end
end

function Syndra:CastQEShort(pred, target, canHitOrbs)
    if
        myHero.spellbook:CanUseSpell(SpellSlot.Q) == SpellState.Ready and
            myHero.spellbook:CanUseSpell(SpellSlot.E) == SpellState.Ready and
            myHero.mana >= 80 + 10 * myHero.spellbook:Spell(0).level and
            (not self.spell.e.next or GetDistanceSqr(self.spell.e.next.pos) > self.spell.e.rangeSqr or
                self.spell.e.next.time <=
                    clock() + self.spell.e.delay + GetDistance(pred.castPosition) / self.spell.e.speed)
     then
        local qPos = self:GetQPos(pred.castPosition, "q"):toDX3()
        local canHitOrbAngles, collOrbAngles = {}, {}
        for i = 1, #canHitOrbs do
            local orb = canHitOrbs[i]
            local angle = Vector(self.myHeroPred):angleBetweenFull(Vector(qPos), Vector(orb.obj.position))
            canHitOrbAngles[i] = angle
        end
        canHitOrbAngles[#canHitOrbAngles + 1] = 0
        collOrbAngles[0] = true
        table.sort(canHitOrbAngles)
        local best = self:CalcBestCastAngle(collOrbAngles, canHitOrbAngles)
        if best then
            local castPosition =
                (Vector(self.myHeroPred) +
                (Vector(qPos) - Vector(self.myHeroPred)):rotated(0, best, 0):normalized() * self.spell.e.range):toDX3()
            myHero.spellbook:CastSpell(SpellSlot.Q, qPos)
            myHero.spellbook:CastSpell(SpellSlot.E, castPosition)
            self.last.e = clock() + 0.5
            self.orbs[#self.orbs + 1] = {
                obj = {position = qPos},
                isInitialized = false,
                isCasted = false,
                endT = clock() + 0.25
            }
            self:CheckHitOrb(castPosition)

            pred:draw()
            return true
        end
    end
end

function Syndra:CastQELong(pred, canHitOrbs)
    if myHero.mana >= 80 + 10 * myHero.spellbook:Spell(0).level then
        local predPosition = self:GetCastPosition(pred)
        local qPos = Vector(self.myHeroPred):extended(Vector(predPosition), (self.spell.q.range - 100)):toDX3()
        local canHitOrbAngles, collOrbAngles = {}, {}
        for i = 1, #canHitOrbs do
            local orb = canHitOrbs[i]
            local angle = Vector(self.myHeroPred):angleBetweenFull(Vector(qPos), Vector(orb.obj.position))
            canHitOrbAngles[i] = angle
        end
        canHitOrbAngles[#canHitOrbAngles + 1] = 0
        collOrbAngles[0] = true
        table.sort(canHitOrbAngles)
        local best = self:CalcBestCastAngle(collOrbAngles, canHitOrbAngles)
        if best then
            local castPosition =
                (Vector(self.myHeroPred) +
                (Vector(qPos) - Vector(self.myHeroPred)):rotated(0, best, 0):normalized() * self.spell.e.range):toDX3()
            myHero.spellbook:CastSpell(SpellSlot.Q, qPos)
            myHero.spellbook:CastSpell(SpellSlot.E, castPosition)

            self.last.q = clock() + 0.5
            self.last.e = clock() + 0.5
            self.orbs[#self.orbs + 1] = {
                obj = {position = qPos},
                isInitialized = false,
                isCasted = false,
                endT = clock() + 0.25
            }
            self:CheckHitOrb(castPosition)

            pred:draw()
            return true
        end
    end
end

function Syndra:CastWELong(pred, castTarget, canHitOrbs)
    if myHero.mana >= 100 + 10 * myHero.spellbook:Spell(1).level then
        local predPosition = self:GetCastPosition(pred)
        local target, isOrb
        if self.spell.w.heldInfo then
            if not self.spell.w.heldInfo.isOrb then
                return
            end
        else
            --return
            target, isOrb = self:GetGrabTarget()
            if target and isOrb then
                myHero.spellbook:CastSpell(SpellSlot.W, target.position)
            else
                return
            end
        end
        local wPos = Vector(self.myHeroPred):extended(Vector(predPosition), (self.spell.q.range - 100)):toDX3()
        local canHitOrbAngles, collOrbAngles = {}, {}
        for i = 1, #canHitOrbs do
            local orb = canHitOrbs[i]
            if not orb.obj == target then
                local angle = Vector(self.myHeroPred):angleBetweenFull(Vector(wPos), Vector(orb.obj.position))
                canHitOrbAngles[i] = angle
            end
        end
        canHitOrbAngles[#canHitOrbAngles + 1] = 0
        collOrbAngles[0] = true
        table.sort(canHitOrbAngles)
        local best = self:CalcBestCastAngle(collOrbAngles, canHitOrbAngles)
        if best then
            local castPosition =
                (Vector(self.myHeroPred) +
                (Vector(wPos) - Vector(self.myHeroPred)):rotated(0, best, 0):normalized() * self.spell.e.range):toDX3()
            myHero.spellbook:CastSpell(SpellSlot.W, wPos)
            myHero.spellbook:CastSpell(SpellSlot.E, castPosition)
            self.last.w = clock() + 0.5
            self.last.e = clock() + 0.5
            self:CheckHitOrb(castPosition)
            --PrintChat("we")
            pred:draw()
            return true
        end
    end
end

function Syndra:GetQPos(predPos, spell)
    local dist = GetDistance(predPos)
    if spell == "q" then
        return Vector(self.myHeroPred):extended(Vector(predPos), min(dist + 450, max(dist + 50, 700)))
    elseif spell == "w" then
        return Vector(self.myHeroPred):extended(Vector(predPos), min(dist + 450, max(dist + 50, 700)))
    end
    return Vector(self.myHeroPred):extended(Vector(predPos), min(dist + 450, 850))
end

function Syndra:CastWEShort(pred, canHitOrbs)
    if
        myHero.spellbook:CanUseSpell(SpellSlot.W) == SpellState.Ready and
            myHero.spellbook:CanUseSpell(SpellSlot.E) == SpellState.Ready and
            myHero.mana >= 100 + 10 * myHero.spellbook:Spell(1).level
     then
        local target, isOrb
        if self.spell.w.heldInfo then
            if not self.spell.w.heldInfo.isOrb then
                return
            end
        else
            target, isOrb = self:GetGrabTarget()
            if target and isOrb then
                myHero.spellbook:CastSpell(SpellSlot.W, target.position)
            else
                return
            end
        end
        local wPos = self:GetQPos(pred.castPosition, "w"):toDX3()
        local canHitOrbAngles, collOrbAngles = {}, {}
        for i = 1, #canHitOrbs do
            local orb = canHitOrbs[i]
            if not orb.obj == target then
                local angle = Vector(self.myHeroPred):angleBetweenFull(Vector(wPos), Vector(orb.obj.position))
                canHitOrbAngles[i] = angle
            end
        end
        canHitOrbAngles[#canHitOrbAngles + 1] = 0
        collOrbAngles[0] = true
        table.sort(canHitOrbAngles)
        local best = self:CalcBestCastAngle(collOrbAngles, canHitOrbAngles)
        if best then
            local castPosition =
                (Vector(self.myHeroPred) +
                (Vector(wPos) - Vector(self.myHeroPred)):rotated(0, best, 0):normalized() * self.spell.e.range):toDX3()
            myHero.spellbook:CastSpell(SpellSlot.W, wPos)
            myHero.spellbook:CastSpell(SpellSlot.E, castPosition)
            self.last.w = clock() + 0.5
            self.last.e = clock() + 0.5
            --PrintChat("we")
            pred:draw()
            return true
        end
    end
end

function Syndra:GetIgnite(target)
    return ((self.ignite and myHero.spellbook:CanUseSpell(self.ignite) == SpellState.Ready and
        GetDistanceSqr(target) <= 360000) and --600 range
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

function Syndra:CalcRDamage()
    local validOrbs = 0
    for i = 1, #self.orbs do 
        local orb = self.orbs[i]
        if orb and orb.isInitialized then
            validOrbs = validOrbs + 1
        end
    end
    local count = min(7, 3 + validOrbs)
    self.spell.r.baseDamage = count * (50 + 45 * myHero.spellbook:Spell(SpellSlot.R).level + 0.2 * self:GetTotalAp())
end

function Syndra:RExecutes(target)
    local base = self.spell.r.baseDamage
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
    local pred = _G.Prediction.GetPrediction(target, self.spell.r, myHero)
    if
        pred and
            not (Orbwalker:GetMode() == "Combo" and myHero.spellbook:CanUseSpell(SpellSlot.R) == SpellState.Ready and
                self.menu.r[tostring(target.networkId)] and
                self.menu.r[tostring(target.networkId)]:get() and
                GetDistanceSqr(target.position) <= self.spell.r.castRange * self.spell.r.castRange)
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
        self.menu.r.c4:get() and myHero.spellbook:CanUseSpell(0) == 0 and
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
    for _, enemy in ipairs(self.enemyHeroes) do
        if GetDistanceSqr(enemy.position) <= 640000 then -- 800 range
            enemiesInRange1 = enemiesInRange1 + 1
        end
        if GetDistanceSqr(enemy.position) <= 6250000 then --2500 range
            enemiesInRange2 = enemiesInRange2 + 1
        end
    end
    for _, ally in ipairs(self.allyHeroes) do
        if GetDistanceSqr(ally.position) <= 640000 then -- 800 range
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
        self.last.r = clock() + 0.5
        --PrintChat("r")
        return true
    end
end

function Syndra:OnCreateObj(obj)
    if obj.name == "Seed" and obj.team == myHero.team and obj.spellbook.owner.charName == "SyndraSphere" then
        local replaced = false
        for i in ipairs(self.orbs) do
            local orb = self.orbs[i]
            if not orb.isInitialized and GetDistanceSqr(obj.position, orb.obj.position) == 0 then
                self.orbs[i] = {obj = obj, isInitialized = true, isCasted = true, endT = clock() + 6.25}
                replaced = true
            end
        end
        if not replaced then
            self.orbs[#self.orbs + 1] = {obj = obj, isInitialized = true, isCasted = true, endT = clock() + 6.25}
        end
    end
    if match(obj.name, "Syndra") then
        if match(obj.name, "heldTarget_buf_02") then
            self.spell.w.heldInfo = nil
            local minions = ObjectManager:GetEnemyMinions()
            local maxObj = nil
            local maxTime = 0
            for i = 1, #minions do
                local minion = minions[i]
                if minion and not minion.isDead and GetDistanceSqr(minion) < self.spell.w.grabRangeSqr then
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
                for i in ipairs(self.orbs) do
                    local orb = self.orbs[i]
                    if orb.isInitialized and GetDistance(obj.position, orb.obj.position) <= 1 then
                        self.spell.w.heldInfo = {obj = orb.obj, isOrb = true}
                        orb.endT = clock() + 6.25
                        self.spell.e.blacklist[orb.obj] = {pos = orb.obj.position, time = clock() + 0.06}
                    end
                end
            end
        end
        if
            match(obj.name, "Q_tar_sound") or
                match(obj.name, "W_tar") and
                    myHero.buffManager:HasBuff("ASSETS/Perks/Styles/Domination/Electrocute/Electrocute.lua")
         then
            for _, enemy in ipairs(self.enemyHeroes) do
                if enemy.isVisible and GetDistanceSqr(enemy.position, obj.position) < 1 then
                    if not self.electrocuteTracker[enemy.networkId] then
                        self.electrocuteTracker[enemy.networkId] = {}
                    end
                    insert(self.electrocuteTracker[enemy.networkId], clock())
                end
            end
        elseif match(obj.name, "E_tar") then
            local isOrb = false
            for i in ipairs(self.orbs) do
                if GetDistanceSqr(self.orbs[i].obj.position, obj.position) < 1 then
                    isOrb = true
                end
            end
            if not isOrb then
                local electrocute =
                    myHero.buffManager:HasBuff("ASSETS/Perks/Styles/Domination/Electrocute/Electrocute.lua")
                for _, enemy in ipairs(self.enemyHeroes) do
                    if electrocute and enemy.isVisible and GetDistanceSqr(enemy.position, obj.position) < 1 then
                        if not self.electrocuteTracker[enemy.networkId] then
                            self.electrocuteTracker[enemy.networkId] = {}
                        end
                        insert(self.electrocuteTracker[enemy.networkId], clock())
                    end
                    if self.spell.w.blacklist2 and enemy.networkId == self.spell.w.blacklist2.target then
                        self.spell.w.blacklist2 = nil
                        --PrintChat("e detected")
                    end
                end
            end
        end
    end
end

function Syndra:OnDeleteObj(obj)
    if obj.name == "Seed" and obj.team == myHero.team then
        for i in ipairs(self.orbs) do
            if self.orbs[i].obj == obj then
                remove(self.orbs, i)
            end
        end
    end
    if
        myHero.buffManager:HasBuff("ASSETS/Perks/Styles/Domination/Electrocute/Electrocute.lua") and
            match(obj.name, "SyndraBasicAttack")
     then
        for _, enemy in ipairs(ObjectManager:GetEnemyHeroes()) do
            if enemy == obj.asMissile.target then
                if not self.electrocuteTracker[enemy.networkId] then
                    self.electrocuteTracker[enemy.networkId] = {}
                end
                insert(self.electrocuteTracker[enemy.networkId], clock())
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
            self.last.q = clock() + 0.15
            local replaced = false
            for i in pairs(self.orbs) do
                local orb = self.orbs[i]
                if not orb.isInitialized and not orb.isCasted and GetDistanceSqr(obj.position, orb.obj.position) == 0 then
                    self.orbs[i] = {
                        obj = {position = spell.endPos},
                        isInitialized = false,
                        isCasted = true,
                        endT = clock() + 0.625
                    }
                    replaced = true
                end
            end
            if not replaced then
                self.orbs[#self.orbs + 1] = {
                    obj = {position = spell.endPos},
                    isInitialized = false,
                    isCasted = true,
                    endT = clock() + 0.625
                }
            end
        elseif spell.spellData.name == "SyndraW" then
            self.last.w = clock() + 0.15
        elseif spell.spellData.name == "SyndraWCast" then
            self.last.w = clock() + 0.15
            self.spell.e.next = {
                time = clock() + self.spell.w.delay,
                pos = spell.endPos
            }
        elseif spell.spellData.name == "SyndraE" then
            self:CheckHitOrb(spell.endPos)
        elseif spell.spellData.name == "SyndraR" then
            self.timer = clock() + 0.15
        end
    end
end

function Syndra:OnExecuteCastFrame(obj, spell)
    if obj == myHero then
        if spell.spellData.name == "SyndraE" then
            self.last.e = clock()
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
    return myHero.characterIntermediate.baseAbilityDamage +
        myHero.characterIntermediate.flatMagicDamageMod * (1 + myHero.characterIntermediate.percentMagicDamageMod)
end


local Syndra = {}
local version = 1
--[[if tonumber(GetInternalWebResult("Syndra.version")) > version then
    DownloadInternalFile("Syndra.lua", SCRIPT_PATH .. "Syndra.lua")
    PrintChat("New version:" .. tonumber(GetInternalWebResult("Syndra.version")) .. " Press F5")
end--]]
require "FF15Menu"
require "utils"

local Vector = require("GeometryLib").Vector
local LineSegment = require("GeometryLib").LineSegment
local dmgLib = require("FF15DamageLib")
local DreamTS = require("DreamTS")

function OnLoad()
    if not _G.Prediction then
        LoadPaidScript(PaidScript.DREAM_PRED)
    end
end

function Syndra:init()
    self.spell = {
        q = {
            type = "circular",
            range = 800,
            delay = 0.74,
            radius = 200,
            speed = math.huge
        },
        w = {
            type = "circular",
            range = 950,
            rangeSqr = 950 * 950,
            delay = 0.25,
            radius = 220,
            speed = 1200,
            distanceMult = 1.1,
            baseSpeed = 250,
            next1 = os.clock(),
            next2 = os.clock()
        },
        e = {
            type = "linear",
            speed = 1600,
            range = 700,
            delay = 0.30,
            width = 200,
            widthMax = 100,
            queue = nil
        },
        qe = {
            type = "linear",
            pingPongSpeed = 2000,
            range = 1200,
            rangeSqr = 1200 * 1200,
            delay = 0.30,
            speed = 2000,
            width = 200
        }
    }
    self.next = os.clock()
    self.orbs = {}
    self:Menu()
    self.TS =
        DreamTS(
        self.menu.dreamTs,
        {
            ValidTarget = function(unit)
                return _G.Prediction.IsValidTarget(unit)
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
        Events.OnBuffGain,
        function(obj, buff)
            self:OnBuffGain(obj, buff)
        end
    )
    AddEvent(
        Events.OnDraw,
        function()
            self:OnDraw()
        end
    )
    PrintChat("Syndra Beta loaded")
    self.font = DrawHandler:CreateFont("Calibri", 10)
end

function Syndra:Menu()
    self.menu = Menu("asdfsyndra", "Syndra")
    self.menu:sub("dreamTs", "Target Selector")
    self.menu:sub("use", "Use Spell in Combo")
    self.menu.use:checkbox("q", "Use Q", true)
    self.menu.use:checkbox("w1", "Use W1", true)
    self.menu.use:checkbox("w2", "Use W2", true)
    self.menu.use:checkbox("we", "Use WE", true)
    self.menu.use:checkbox("e", "Use E", true)
    self.menu.use:checkbox("qe1", "Use QE Short", true)
    self.menu.use:checkbox("qe2", "Use QE Long", true, string.byte("Z"))
    self.menu:checkbox("e", "AutoE", true, string.byte("T"))
    self.menu:sub("antigap", "Anti Gapclose")
    for _, enemy in pairs(ObjectManager:GetEnemyHeroes()) do
        self.menu.antigap:checkbox(enemy.charName, enemy.charName, true)
    end
    self.menu:sub("r", "R")
    for _, enemy in pairs(ObjectManager:GetEnemyHeroes()) do
        self.menu.r:checkbox(enemy.charName, enemy.charName, true)
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
    self.menu:sub("syndraDraw", "Draw")
    self.menu.syndraDraw:sub("q", "Q")
    self.menu.syndraDraw.q:checkbox("q", "Q", true)
    self.menu.syndraDraw.q:slider("qr", "Red", 1, 255, 150)
    self.menu.syndraDraw.q:slider("qg", "Green", 1, 255, 150)
    self.menu.syndraDraw.q:slider("qb", "Blue", 1, 255, 150)
    self.menu.syndraDraw:sub("e", "E")
    self.menu.syndraDraw.e:checkbox("e", "E", true)
    self.menu.syndraDraw.e:slider("er", "Red", 1, 255, 150)
    self.menu.syndraDraw.e:slider("eg", "Green", 1, 255, 150)
    self.menu.syndraDraw.e:slider("eb", "Blue", 1, 255, 150)
    self.menu.syndraDraw:checkbox("qe", "Orb", true)
end

function Syndra:OnTick()
    for i = #self.orbs, 1, -1 do
        if os.clock() >= self.orbs[i].endT and not self.orbs[i].isInitialized then
            table.remove(self.orbs, i)
        end
    end
    if os.clock() >= self.next and self:AutoGrab() then
        self.next = os.clock() + 0.05
        return
    end
    if self.spell.e.queue then
        if os.clock() >= self.spell.e.queue.time then
            if myHero.spellbook:CanUseSpell(SpellSlot.E) then
                myHero.spellbook:CastSpell(SpellSlot.E, self.spell.e.queue.pos)
                self.next = os.clock() + 0.05
            end
            self.spell.e.queue = nil
        end
        return
    end
    if os.clock() >= self.next then
        for _, target in ipairs(self:GetTarget(self.spell.qe.range + 50, true)) do
            if
                self.menu.antigap[target.charName] and self.menu.antigap[target.charName]:get() and
                    not _G.Prediction.IsRecalling(myHero)
             then
                _, canHit = _G.Prediction.IsDashing(target, self.spell.e, myHero)
                if canHit then
                    if self:CastQEShort(target) then
                        self.next = os.clock() + 0.05
                        print("QE Antigap")

                        return
                    end
                    if self:CastWE(target) then
                        self.next = os.clock() + 0.05
                        print("WE Antigap")

                        return
                    end
                end
            end

            if self.menu.e:get() and not _G.Prediction.IsRecalling(myHero) then
                if self:CastE(target) then
                    self.next = os.clock() + 0.05
                    print("E")
                    return
                end
            end
            if LegitOrbwalker:GetMode() == "Combo" then
                if self:CastR(target) then
                    self.next = os.clock() + 0.05
                    print("R")
                    return
                end
                if self.menu.use.e:get() and self:CastE(target) then
                    self.next = os.clock() + 0.05
                    print("E")
                    return
                end
                if self.menu.use.we:get() and self:CastWE(target) then
                    self.next = os.clock() + 0.05
                    print("WE")
                    return
                end
                if self.menu.use.qe1:get() and self:CastQEShort(target) then
                    self.next = os.clock() + 0.05
                    print("QE1")
                    return
                end
            end
        end
        local target = self:GetTarget(self.spell.w.range)
        if target and LegitOrbwalker:GetMode() == "Combo" and not LegitOrbwalker:IsAttacking() then
            if self.menu.use.w2:get() and target and self:CastW2(target) then
                self.next = os.clock() + 0.05
                print("W2")
                return
            end
            if self.menu.use.w1:get() and target and self:CastW1() then
                self.next = os.clock() + 0.05
                print("W1")
                return
            end
        end
        target = self:GetTarget(self.spell.qe.range)
        if
            target and LegitOrbwalker:GetMode() == "Combo" and not LegitOrbwalker:IsAttacking() and
                self.menu.use.qe2:get() and
                self:CastQELong(target)
         then
            self.next = os.clock() + 0.05
            print("QE2")
            return
        end
        target = self:GetTarget(self.spell.q.range)
        if target and not LegitOrbwalker:IsAttacking() then
            if LegitOrbwalker:GetMode() == "Combo" and self.menu.use.q:get() then
                if self:CastQ(target) then
                    self.next = os.clock() + 0.05
                    print("Q")

                    return
                end
            elseif LegitOrbwalker:GetMode() == "Harass" then
                if self:CastQ(target) then
                    self.next = os.clock() + 0.05
                    return
                end
            end
        end
    end
end

function Syndra:OnDraw()
    if self.menu.syndraDraw.q.q:get() then
        DrawHandler:Circle3D(
            myHero.position,
            self.spell.q.range,
            self:Hex(
                255,
                self.menu.syndraDraw.q.qr:get(),
                self.menu.syndraDraw.q.qg:get(),
                self.menu.syndraDraw.q.qb:get()
            )
        )
    end
    if self.menu.syndraDraw.e.e:get() then
        DrawHandler:Circle3D(
            myHero.position,
            self.spell.qe.range,
            self:Hex(
                255,
                self.menu.syndraDraw.e.er:get(),
                self.menu.syndraDraw.e.eg:get(),
                self.menu.syndraDraw.e.eb:get()
            )
        )
    end
    for i = 1, #self.orbs do
        local orb = self.orbs[i]

        if
            ((orb.isInitialized and (not orb.obj.health or orb.obj.health == 1)) or not orb.isInitialized) and
                GetDistanceSqr(orb.obj.position) <= self.spell.q.range * self.spell.q.range
         then
            DrawHandler:Circle3D(
                orb.obj.position,
                40,
                (orb.isInitialized and orb.obj and orb.obj.aiManagerClient and
                    not orb.obj.aiManagerClient.navPath.isMoving) and
                    Color.SkyBlue or
                    Color.Red
            )

            if self.menu.syndraDraw.qe:get() then
                local new_pos = Vector(myHero):extended(Vector(orb.obj.position), self.spell.qe.range)

                _G.Prediction.Drawing.DrawRectangle(
                    myHero.position,
                    new_pos,
                    self.spell.qe.width,
                    (orb.isInitialized and orb.obj and orb.obj.aiManagerClient and
                        not orb.obj.aiManagerClient.navPath.isMoving) and
                        Color.SkyBlue or
                        Color.Red
                )
            end
        end
    end

    if self:IsHoldingTarget() then
        local obj = self:GetTargetHeld()

        if obj then
            DrawHandler:Circle3D(obj.position, 45, Color.Green)
        end
    end
    local text =
        (self.menu.use.qe2:get() and "QE Long: On" or "QE Long: Off") ..
        "\n" .. (self.menu.e:get() and "Auto E: On" or "Auto E: Off")
    DrawHandler:Text(DrawHandler.defaultFont, Renderer:WorldToScreen(myHero.position), text, Color.White)
end

function Syndra:AutoGrab()
    if
        myHero.spellbook:CanUseSpell(SpellSlot.W) == SpellState.Ready and
            myHero.spellbook:Spell(SpellSlot.W).name == "SyndraW" and
            not _G.Prediction.IsRecalling(myHero) and
            os.clock() >= self.spell.w.next1
     then
        for _, minion in pairs(ObjectManager:GetEnemyMinions()) do
            if
                (minion.name == "Tibbers" or minion.name == "IvernMinion") and
                    GetDistanceSqr(minion) < self.spell.w.rangeSqr
             then
                myHero.spellbook:CastSpell(SpellSlot.W, minion.position)
                self.spell.w.next1 = os.clock() + self.spell.w.delay
                return true
            end
        end
    end
end

function Syndra:CastQ(target)
    if
        myHero.spellbook:CanUseSpell(SpellSlot.Q) == SpellState.Ready and
            GetDistance(target.position) <= self.spell.q.range
     then
        local pred = _G.Prediction.GetPrediction(target, self.spell.q, myHero)
        if pred and pred.castPosition and (pred.realHitChance == 1 or _G.Prediction.WaypointManager.ShouldCast(target)) then
            myHero.spellbook:CastSpell(SpellSlot.Q, pred.castPosition)
            return true
        end
    end
end

local function IsBallHitByE(obj)
    return obj.aiManagerClient and obj.aiManagerClient.navPath.isMoving and
        obj.aiManagerClient.navPath.dashSpeed == 2000
end

function Syndra:GetGrabTarget()
    local lowTime = math.huge
    local lowOrb = nil
    for i = 1, #self.orbs do
        local orb = self.orbs[i]
        if
            orb.isInitialized and orb.endT < lowTime and not IsBallHitByE(orb.obj) and
                GetDistance(orb.obj.position) <= self.spell.w.range
         then
            lowTime = orb.endT
            lowOrb = orb.obj
        end
    end

    if lowOrb then
        return lowOrb
    end

    local minionsInRange = ObjectManager:GetEnemyMinions()
    local lowHealth = math.huge
    local lowMinion = nil
    for _, minion in ipairs(minionsInRange) do
        if minion and GetDistance(minion.position) <= self.spell.w.range then
            if minion.health < lowHealth then
                lowHealth = minion.health
                lowMinion = minion
            end
        end
    end
    if lowMinion then
        return lowMinion
    end
end

function Syndra:CastW1()
    if
        myHero.spellbook:CanUseSpell(SpellSlot.W) == SpellState.Ready and
            myHero.spellbook:Spell(SpellSlot.W).name == "SyndraW" and
            os.clock() >= self.spell.w.next1
     then
        if self:GetTarget(self.spell.w.range) then
            local target = self:GetGrabTarget()
            if target then
                myHero.spellbook:CastSpell(SpellSlot.W, target.position)
                self.spell.w.next1 = os.clock() + self.spell.w.delay
                return true
            end
        end
    end
end

function Syndra:IsHoldingTarget()
    local buffs = myHero.buffManager.buffs

    for i = 1, #buffs do
        local buff = buffs[i]

        if buff.name == "syndrawtooltip" then
            return true
        end
    end

    return false
end

function Syndra:GetTargetHeld()
    local minions = ObjectManager:GetEnemyMinions()

    local function HasSyndraBuff(unit)
        local buffs = unit.buffManager.buffs

        for i = 1, #buffs do
            local buff = buffs[i]

            if buff.name == "syndrawbuff" then
                return true
            end
        end
    end

    for i = 1, #minions do
        local minion = minions[i]
        if minion and not minion.isDead and GetDistanceSqr(minion) < self.spell.w.rangeSqr and HasSyndraBuff(minion) then
            return minion, false
        end
    end

    for i = 1, #self.orbs do
        local orb = self.orbs[i]

        if
            orb.isInitialized and orb.obj and orb.obj.aiManagerClient and orb.obj.aiManagerClient.navPath.isMoving --and
                --not IsBallHitByE(orb.obj)
         then
            return orb.obj, true
        end
    end
end

function Syndra:CastW2(target)
    if not self:IsHoldingTarget() then
        return
    end

    local grabbedTarget = self:GetTargetHeld()

    if not grabbedTarget then
        return
    end

    if myHero.spellbook:CanUseSpell(SpellSlot.W) == SpellState.Ready and os.clock() >= self.spell.w.next2 then
        self.spell.w.speed =
            GetDistance(grabbedTarget, target.position) * self.spell.w.distanceMult + self.spell.w.baseSpeed

        local pred = _G.Prediction.GetPrediction(target, self.spell.w, grabbedTarget)
        for i = 0, 20, 1 do
            pred = _G.Prediction.GetPrediction(target, self.spell.w, grabbedTarget)
            if pred and pred.castPosition then
                self.spell.w.speed =
                    GetDistance(grabbedTarget, pred.castPosition) * self.spell.w.distanceMult + self.spell.w.baseSpeed
            end
        end

        local pred = _G.Prediction.GetPrediction(target, self.spell.w, grabbedTarget)
        if
            pred and pred.castPosition and (pred.realHitChance == 1 or _G.Prediction.WaypointManager.ShouldCast(target)) and
                GetDistanceSqr(pred.castPosition) <= self.spell.w.rangeSqr
         then
            print(GetDistance(grabbedTarget, target.position) * self.spell.w.distanceMult + self.spell.w.baseSpeed)
            print(self.spell.w.speed)
            myHero.spellbook:CastSpell(SpellSlot.W, pred.castPosition)
            return true
        end
    end
end

function Syndra:CanEQ(qPos, predPos, target)
    --e orb check
    for i = 1, #self.orbs do
        local orb = self.orbs[i]
        if
            orb.isInitialized and GetDistance(target.position) >= GetDistance(orb.obj.position) and
                math.abs(Vector(myHero.position):angleBetween(Vector(orb.obj.position), qPos)) <=
                    ((myHero.spellbook:Spell(SpellSlot.E).level < 5) and 22.5 or 37.5)
         then
            seg = LineSegment(extendPos, Vector(myHero.position))
            if seg and seg:distanceTo(Vector(predPos)) <= self.spell.qe.width + target.boundingRadius + 15 then
                return false
            end
        end
    end
    --wall check
    local interval = 50
    local count = math.floor(GetDistance(predPos, qPos:toDX3()) / interval)
    local diff = (Vector(qpos) - Vector(myHero.position)):normalized()
    for i = 0, count do
        local pos = Vector(predPos) + diff * i * interval
        if NavMesh:IsWall(pos:toDX3()) then
            return false
        end
    end
    --cc check
    if _G.Prediction.IsImmobile(target) then
        return false
    end
    return true
end

function Syndra:CalcQE(target, dist)
    local dist = dist or self.spell.e.range
    self.spell.qe.speed = self.spell.qe.pingPongSpeed
    local pred = _G.Prediction.GetPrediction(target, self.spell.qe, myHero)
    for i = 0, 20, 1 do
        pred = _G.Prediction.GetPrediction(target, self.spell.qe, myHero)
        if pred and pred.castPosition then
            self.spell.qe.speed =
                (self.spell.e.speed * dist + self.spell.qe.pingPongSpeed * (GetDistance(pred.castPosition) - dist)) /
                GetDistance(pred.castPosition)
        end
    end
end

function Syndra:CastE(target)
    if myHero.spellbook:CanUseSpell(SpellSlot.E) == SpellState.Ready and _G.Prediction.IsValidTarget(target) then
        for i = 1, #self.orbs do
            local orb = self.orbs[i]
            local distToOrb = GetDistance(orb.obj.position)
            if distToOrb <= self.spell.e.range then
                local timeToHitOrb = self.spell.e.delay + (distToOrb / self.spell.e.speed)
                local expectedHitTime = os.clock() + timeToHitOrb - 0.1
                local canHitOrb =
                    (orb.isInitialized and (expectedHitTime + 0.1 < orb.endT) or (expectedHitTime > orb.endT)) and
                    (not orb.isInitialized or
                        (orb.obj and orb.obj.aiManagerClient and not orb.obj.aiManagerClient.navPath.isMoving)) and
                    orb.obj ~= self:GetTargetHeld()
                if canHitOrb then
                    local new_QE_spell =
                        setmetatable(
                        {
                            speed = 2000,
                            delay = timeToHitOrb - (distToOrb / self.spell.qe.speed)
                        },
                        {__index = self.spell.qe}
                    )
                    local endPos = Vector(myHero.position):extended(Vector(orb.obj.position), self.spell.qe.range)

                    if _G.Prediction.IsCollision(new_QE_spell, myHero, endPos, target) then
                        myHero.spellbook:CastSpell(SpellSlot.E, orb.obj.position)
                        return true
                    end
                end
            elseif distToOrb <= self.spell.q.range and orb.isInitialized then
                local new_E_spell =
                    setmetatable(
                    {
                        range = self.spell.q.range
                    },
                    {__index = self.spell.e}
                )
                if _G.Prediction.IsCollision(new_E_spell, myHero, orb.obj.position, target) then
                    local castPos = Vector(myHero.position):extended(Vector(orb.obj.position), 300):toDX3()
                    myHero.spellbook:CastSpell(SpellSlot.E, castPos)
                    self.spell.w.next1 = os.clock() + 1
                    self.spell.w.next2 = os.clock() + 0.7
                    return true
                end
            end
        end
    end
end

function Syndra:CastQEShort(target)
    if
        myHero.spellbook:CanUseSpell(SpellSlot.Q) == SpellState.Ready and
            myHero.spellbook:CanUseSpell(SpellSlot.E) == SpellState.Ready and
            myHero.mana >= 80 + 10 * myHero.spellbook:Spell(0).level
     then
        --[[
            qe = {
            pingPongSpeed = 2500,
            range = 1250,
            delay = 0.25,
            speed = 2500,
            width = 200
        }
        ]]
        local pred = _G.Prediction.GetPrediction(target, self.spell.e, myHero)
        if pred and pred.castPosition and GetDistance(pred.castPosition) <= self.spell.e.range then
            --qe short
            if
                self:CanEQ(self:GetQPos(pred.castPosition), pred.castPosition, target) and
                    (pred.realHitChance == 1 or _G.Prediction.WaypointManager.ShouldCast(target))
             then
                self.spell.e.width = GetDistance(pred.castPosition) / self.spell.e.range * self.spell.e.widthMax
                local pred = _G.Prediction.GetPrediction(target, self.spell.e, myHero)
                if pred and pred.castPosition then
                    myHero.spellbook:CastSpell(SpellSlot.Q, self:GetQPos(pred.castPosition):toDX3())
                    self.spell.e.queue = {pos = pred.castPosition, time = os.clock() + 0.05}
                    self.spell.e.width = self.spell.e.widthMax
                    self.spell.w.next2 = os.clock() + 0.4
                    self.spell.w.next1 = os.clock() + 1
                    return true
                end
                self.spell.e.width = self.spell.e.widthMax
            end
        end
    end
end

function Syndra:CastQELong(target)
    if
        myHero.spellbook:CanUseSpell(SpellSlot.Q) == SpellState.Ready and
            myHero.spellbook:CanUseSpell(SpellSlot.E) == SpellState.Ready and
            myHero.mana >= 80 + 10 * myHero.spellbook:Spell(0).level
     then
        local pred = _G.Prediction.GetPrediction(target, self.spell.e, myHero)
        if not (pred and pred.castPosition and GetDistance(pred.castPosition) <= self.spell.e.range) then
            --qe long
            self:CalcQE(target, self.spell.q.range - 50)
            --[[ local new_QE_spell =
    setmetatable(
    {
        speed = 2000,
        delay = self.spell.e.delay + (self.spell.e.range / self.spell.e.speed) -
            (self.spell.e.range / self.spell.qe.speed)
    },
    {__index = self.spell.qe}
)

local pred = _G.Prediction.GetPrediction(target, new_QE_spell, myHero) ]]
            local pred = _G.Prediction.GetPrediction(target, self.spell.qe, myHero)
            if
                pred and pred.castPosition and GetDistanceSqr(pred.castPosition) < self.spell.qe.rangeSqr and
                    (pred.realHitChance == 1 or _G.Prediction.WaypointManager.ShouldCast(target))
             then
                qPos = Vector(myHero.position):extended(Vector(pred.castPosition), (self.spell.q.range - 50)):toDX3()
                myHero.spellbook:CastSpell(SpellSlot.Q, qPos)
                self.spell.e.queue = {pos = pred.castPosition, time = os.clock() + 0.05}
                return true
            end
        end
    end
end

function Syndra:GetQPos(predPos)
    return Vector(myHero.position):extended(Vector(predPos), math.min(GetDistance(predPos) + 400, 800))
end

function Syndra:CastWE(target)
    if
        myHero.spellbook:CanUseSpell(SpellSlot.W) == SpellState.Ready and
            myHero.spellbook:CanUseSpell(SpellSlot.E) == SpellState.Ready and
            myHero.mana >= 100 + 10 * myHero.spellbook:Spell(1).level and
            self:IsHoldingTarget()
     then
        local pred = _G.Prediction.GetPrediction(target, self.spell.e, myHero)
        if pred and pred.castPosition and GetDistance(pred.castPosition) <= self.spell.e.range then
            if
                self:CanEQ(self:GetQPos(pred.castPosition), pred.castPosition, target) and
                    (pred.realHitChance == 1 or _G.Prediction.WaypointManager.ShouldCast(target))
             then
                self.spell.e.width = GetDistance(pred.castPosition) / self.spell.e.range * self.spell.e.widthMax
                local pred = _G.Prediction.GetPrediction(target, self.spell.e, myHero)
                local grabbedTarget, isOrb = self:GetTargetHeld()
                if pred and pred.castPosition and grabbedTarget and isOrb then
                    local wPos = self:GetQPos(pred.castPosition):toDX3()
                    local dist = GetDistance(grabbedTarget, wPos)
                    local wIntercept =
                        os.clock() + self.spell.w.delay +
                        dist / (dist * self.spell.w.distanceMult + self.spell.w.baseSpeed)
                    self.spell.e.width = self.spell.e.widthMax
                    if os.clock() + self.spell.e.delay + GetDistance(wPos) / self.spell.e.speed - wIntercept <= 0.1 then
                        myHero.spellbook:CastSpell(SpellSlot.W, self:GetQPos(pred.castPosition):toDX3())
                        self.spell.e.queue = {pos = pred.castPosition, time = os.clock() + 0.05}
                        self.spell.w.next2 = os.clock() + 0.7
                        self.spell.w.next1 = os.clock() + 1
                        return true
                    end
                end
            end
        end
    end
end

function Syndra:RExecutes(target)
    local r = myHero.spellbook:Spell(SpellSlot.R)
    local base =
        dmgLib:CalculateMagicDamage(
        myHero,
        target,
        r.currentAmmoCount * (45 + 45 * r.level + 0.2 * myHero.characterIntermediate.flatMagicDamageMod)
    )

    local ignite =
        ((self.ignite and myHero.spellbook:CanUseSpell(self.ignite) == SpellState.Ready and
        GetDistanceSqr(target) <= 600 * 600) and
        50 + 20 * myHero.experience.level) or
        nil
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
    if
        not (myHero.spellbook:CanUseSpell(SpellSlot.R) == SpellState.Ready and self.menu.r[target.charName] and
            self.menu.r[target.charName]:get() and
            GetDistance(target.position) <= 675 + (myHero.spellbook:Spell(SpellSlot.R).level / 3) * 75 and
            self:RExecutes(target))
     then
        return false
    end
    if self.menu.r.c0:get() then
        return true
    end
    if self.menu.r.c1:get() and NavMesh:IsWall(target.position) then
        return true
    end
    if self.menu.r.c2:get() and myHero.health / myHero.maxHealth <= target.health / target.maxHealth then
        return true
    end
    if self.menu.r.c3:get() and myHero.health / myHero.maxHealth <= self.menu.r.c3:get() / 100 then
        return true
    end
    if
        self.menu.r.c4:get() and
            target.health -
                dmgLib:CalculateMagicDamage(
                    myHero,
                    target,
                    30 + 40 * myHero.spellbook:Spell(SpellSlot.Q).level +
                        0.65 * myHero.characterIntermediate.flatMagicDamageMod
                ) <=
                0
     then
        return false
    end
    enemiesInRange1, enemiesInRange2, alliesInRange = 0, 0, 0
    for _, enemy in pairs(ObjectManager:GetEnemyHeroes()) do
        if GetDistance(enemy.position) <= 550 then
            enemiesInRange1 = enemiesInRange1 + 1
        end
        if GetDistance(enemy.position) <= 2500 then
            enemiesInRange2 = enemiesInRange2 + 1
        end
    end
    for _, ally in pairs(ObjectManager:GetAllyHeroes()) do
        if GetDistance(ally.position) <= 550 then
            alliesInRange = alliesInRange + 1
        end
    end
    if self.menu.r.c5:get() and enemiesInRange1 > alliesInRange then
        return true
    end
    if self.menu.r.c6:get() and myHero.mana < 200 then
        return true
    end
    if target.characterIntermediate.spellBlock < self.menu.r.c7:get() then
        return true
    end
    if enemiesInRange2 <= self.menu.r.c8:get() then
        return true
    end
end

function Syndra:CastR(target)
    if self:RConditions(target) then
        local _, needIgnite = self:RExecutes(target)
        if needIgnite then
            myHero.spellbook:CastSpell(self.ignite, target.networkId)
        end
        myHero.spellbook:CastSpell(SpellSlot.R, target.networkId)
        return true
    end
end

function Syndra:OnCreateObj(obj)
    if obj.name == "Seed" and obj.team == myHero.team then
        self.orbs[#self.orbs + 1] = {obj = obj, isInitialized = true, endT = os.clock() + 6}
    --[[ elseif obj.name == "k" and obj.team == myHero.team then
        self.orbs[#self.orbs + 1] = {obj = obj, isInitialized = false, endT = os.clock() + 0.625} ]]
    end
end

function Syndra:OnDeleteObj(obj)
    if obj.name == "Seed" and obj.team == myHero.team then
        for i = #self.orbs, 1, -1 do
            if self.orbs[i].obj == obj then
                table.remove(self.orbs, i)
            end
        end
    end
end
function Syndra:OnBuffGain(obj, buff)
    if obj == myHero and buff.name == "syndrawtooltip" then
        local obj, isOrb = self:GetTargetHeld()
        if isOrb then
            for i = 1, #self.orbs do
                if self.orbs[i].obj == obj then
                    self.orbs[i].endT = os.clock() + 6
                end
            end
        end
    end
end

function Syndra:OnProcessSpell(obj, spell)
    if obj == myHero and spell.spellData.name == "SyndraQ" then
        self.orbs[#self.orbs + 1] = {
            obj = {position = spell.endPos},
            isInitialized = false,
            endT = os.clock() + 0.625
        }
    end
end

function Syndra:Hex(a, r, g, b)
    return string.format("0x%.2X%.2X%.2X%.2X", a, r, g, b)
end

function Syndra:GetTarget(dist, all)
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

if myHero.charName == "Syndra" then
    Syndra:init()
end

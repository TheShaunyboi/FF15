local Syndra = {}
local version = 1
--[[if tonumber(GetInternalWebResult("asdfsyndra.version")) > version then
    DownloadInternalFile("asdfsyndra.lua", SCRIPT_PATH .. "asdfsyndra.lua")
    PrintChat("New version:" .. tonumber(GetInternalWebResult("asdfsyndra.version")) .. " Press F5")
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
            delay = 0.25,
            radius = 220,
            speed = 1300,
            heldInfo = nil,
            blacklist = {},
            next = os.clock()
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
            next = nil
        },
        qe = {
            type = "linear",
            pingPongSpeed = 2000,
            range = 1200,
            delay = 0.25,
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
end

function Syndra:OnTick()
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
                self.spell.w.blacklist[i].nextCheckTime = os.clock() + 0.1
            end
        end
    end

    for orb in pairs(self.spell.e.blacklist) do
        if
            not (self.spell.w.heldInfo and orb == self.spell.w.heldInfo.obj) and
                GetDistanceSqr(self.spell.e.blacklist[orb], orb.position) == 0
         then
            self.spell.e.blacklist[orb] = nil
        else
            self.spell.e.blacklist[orb] = orb.position
        end
    end

    for i in pairs(self.orbs) do
        local orb = self.orbs[i]
        if os.clock() >= orb.endT or (orb.obj.health and orb.obj.health ~= 1) then
            table.remove(self.orbs, i)
        end
    end

    if os.clock() >= self.next and self:AutoGrab() then
        self.next = os.clock() + 0.05
        return
    end

    if self.spell.e.queue then
        if os.clock() >= self.spell.e.queue.time then
            self.spell.e.queue = nil
        end
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

                        return
                    end
                    if self:CastWE(target) then
                        self.next = os.clock() + 0.05
                        return
                    end
                end
            end

            if self.menu.e:get() and not _G.Prediction.IsRecalling(myHero) then
                if self:CastE(target) then
                    self.next = os.clock() + 0.05
                    return
                end
            end
            if LegitOrbwalker:GetMode() == "Combo" then
                if self:CastR(target) then
                    self.next = os.clock() + 0.05
                    return
                end
                if self.menu.use.e:get() and self:CastE(target) then
                    self.next = os.clock() + 0.05
                    return
                end
                if self.menu.use.we:get() and self:CastWE(target) then
                    self.next = os.clock() + 0.05
                    return
                end
                if self.menu.use.qe1:get() and self:CastQEShort(target) then
                    self.next = os.clock() + 0.05
                    return
                end
            end
        end
        local target = self:GetTarget(self.spell.w.range)
        if target and LegitOrbwalker:GetMode() == "Combo" and not LegitOrbwalker:IsAttacking() then
            if
                self.menu.use.w2:get() and target and
                    (myHero.spellbook:CanUseSpell(SpellSlot.E) ~= SpellState.Ready or
                        GetDistance(target) >= self.spell.e.range - 50) and
                    self:CastW2(target)
             then
                self.next = os.clock() + 0.05
                return
            end
            _, isOrb = self:GetGrabTarget()
            if
                self.menu.use.w1:get() and target and
                    (not myHero.spellbook:CanUseSpell(SpellSlot.E) == SpellState.Ready or
                        (isOrb or not myHero.spellbook:CanUseSpell(SpellSlot.Q) == SpellState.Ready) or
                        not self:WaitToInitialize()) and
                    self:CastW1()
             then
                self.next = os.clock() + 0.05
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
            return
        end
        target = self:GetTarget(self.spell.q.range)
        if target and not LegitOrbwalker:IsAttacking() then
            if
                LegitOrbwalker:GetMode() == "Combo" and
                    (myHero.spellbook:CanUseSpell(SpellSlot.E) ~= SpellState.Ready or
                        GetDistance(target) >= self.spell.e.range - 50) and
                    self.menu.use.q:get()
             then
                if self:CastQ(target) then
                    self.next = os.clock() + 0.05
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
        (self.menu.use.qe2:get() and "QE Long: On" or "QE Long: Off") ..
        "\n" .. (self.menu.e:get() and "Auto E: On" or "Auto E: Off")
    DrawHandler:Text(DrawHandler.defaultFont, Renderer:WorldToScreen(myHero.position), text, Color.White)
end

function Syndra:WaitToInitialize()
    for i in pairs(self.orbs) do
        local orb = self.orbs[i]
        if not orb.isInitialized and GetDistanceSqr(orb.obj.position) <= self.spell.w.range * self.spell.w.range then
            return true
        end
    end
end

function Syndra:AutoGrab()
    if
        myHero.spellbook:CanUseSpell(SpellSlot.W) == SpellState.Ready and
            myHero.spellbook:Spell(SpellSlot.W).name == "SyndraW" and
            not _G.Prediction.IsRecalling(myHero) and
            os.clock() >= self.spell.w.next
     then
        for _, minion in pairs(ObjectManager:GetEnemyMinions()) do
            if
                (minion.name == "Tibbers" or minion.name == "IvernMinion" or minion.name == "H-28G Evolution Turret") and
                    GetDistanceSqr(minion) < self.spell.w.range * self.spell.w.range
             then
                myHero.spellbook:CastSpell(SpellSlot.W, minion.position)
                self.spell.w.next = os.clock() + 0.5
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

function Syndra:GetGrabTarget()
    local lowTime = math.huge
    local lowOrb = nil
    for i in pairs(self.orbs) do
        local orb = self.orbs[i]
        if
            not self.spell.w.blacklist[i] and orb.isInitialized and orb.endT < lowTime and
                GetDistance(orb.obj.position) <= self.spell.w.range
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
        if minion and GetDistance(minion.position) <= self.spell.w.range then
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
    if
        myHero.spellbook:CanUseSpell(SpellSlot.W) == SpellState.Ready and
            myHero.spellbook:Spell(SpellSlot.W).name == "SyndraW" and
            os.clock() >= self.spell.w.next
     then
        if self:GetTarget(self.spell.w.range) then
            local target = self:GetGrabTarget()
            if target then
                myHero.spellbook:CastSpell(SpellSlot.W, target.position)
                self.spell.w.next = os.clock() + self.spell.w.delay
                return true
            end
        end
    end
end

function Syndra:CastW2(target)
    if not self.spell.w.heldInfo then
        return
    end
    if myHero.spellbook:CanUseSpell(SpellSlot.W) == SpellState.Ready then
        local pred = _G.Prediction.GetPrediction(target, self.spell.w, self.spell.w.heldInfo.obj)
        if
            pred and pred.castPosition and (pred.realHitChance == 1 or _G.Prediction.WaypointManager.ShouldCast(target)) and
                GetDistanceSqr(pred.castPosition) <= self.spell.w.range * self.spell.w.range and
                not NavMesh:IsWall(pred.castPosition) and
                not NavMesh:IsBuilding(pred.castPosition)
         then
            myHero.spellbook:CastSpell(SpellSlot.W, pred.castPosition)
            return true
        end
    end
end

function Syndra:CanEQ(qPos, predPos, target)
    --e orb check
    --wall check
    local interval = 50
    local count = math.floor(GetDistance(predPos, qPos:toDX3()) / interval)
    local diff = (Vector(qpos) - Vector(myHero.position)):normalized()
    for i = 0, count do
        local pos = (Vector(predPos) + diff * i * interval):toDX3()
        if NavMesh:IsWall(pos) or NavMesh:IsBuilding(pos) then
            return false
        end
    end

    --cc check
    if _G.Prediction.IsImmobile(target) then
        return false
    end
    return true
end

function Syndra:CalcQELong(target, dist)
    local dist = dist or self.spell.e.range
    self.spell.qe.speed = self.spell.qe.pingPongSpeed
    local pred = _G.Prediction.GetPrediction(target, self.spell.qe, myHero)
    for i = 0, 5, 1 do
        pred = _G.Prediction.GetPrediction(target, self.spell.qe, myHero)
        if pred and pred.castPosition then
            self.spell.qe.speed =
                (self.spell.e.speed * dist + self.spell.qe.pingPongSpeed * (GetDistance(pred.castPosition) - dist)) /
                GetDistance(pred.castPosition)
        end
    end
end

function Syndra:CalcQEShort(target, widthMax)
    self.spell.e.width = self.spell.e.widthMax
    local pred = _G.Prediction.GetPrediction(target, self.spell.e, myHero)
    for i = 0, 20, 1 do
        self.spell.e.width =
            -target.boundingRadius +
            GetDistance(pred.castPosition) / GetDistance(self:GetQPos(pred.castPosition):toDX3()) *
                (widthMax + target.boundingRadius)
        pred = _G.Prediction.GetPrediction(target, self.spell.e, myHero)
    end
end

function Syndra:CastE(target)
    if myHero.spellbook:CanUseSpell(SpellSlot.E) == SpellState.Ready and _G.Prediction.IsValidTarget(target) then
        self.spell.qe.delay = 0.25
        local canHitOrbs, collOrbs, maxHit, maxOrb = {}, {}, 0, nil
        --check which orb can be hit
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

        local myHeroPred = _G.Prediction.GetUnitPosition(myHero, NetClient.ping / 1000)
        local checkPred = _G.Prediction.GetPrediction(target, self.spell.e, myHeroPred)
        local checkWidth = checkPred.realHitChance == 1 and self.spell.e.widthMax or 100
        local checkSpell =
            setmetatable(
            {
                width = self.spell.qe.width - checkWidth / 2
            },
            {__index = self.spell.qe}
        )
        checkPred = _G.Prediction.GetPrediction(target, checkSpell, myHeroPred)
        if
            checkPred and checkPred.castPosition and
                (checkPred.realHitChance == 1 or _G.Prediction.WaypointManager.ShouldCast(target))
         then
            --check which orbs can hit enemy
            for i = 1, #canHitOrbs do
                local orb = canHitOrbs[i]
                if GetDistance(checkPred.castPosition) > GetDistance(orb.obj.position) then
                    self:CalcQELong(target, GetDistance(orb.obj.position))
                    local seg =
                        LineSegment(
                        Vector(myHeroPred):extended(Vector(orb.obj.position), self.spell.qe.range),
                        Vector(myHeroPred)
                    )
                    if seg:distanceTo(Vector(checkPred.castPosition)) <= checkWidth / 2 then
                        collOrbs[orb] = 0
                    end
                else
                    self:CalcQEShort(target, checkWidth)
                    local pred = _G.Prediction.GetPrediction(target, self.spell.e, myHeroPred)
                    if pred and pred.castPosition and GetDistanceSqr(pred.castPosition, orb.obj.position) <= 400 * 400 then
                        local seg =
                            LineSegment(
                            Vector(myHeroPred):extended(Vector(orb.obj.position), self.spell.qe.range),
                            Vector(myHeroPred)
                        )
                        if
                            seg:distanceTo(self:GetQPos(pred.castPosition)) <= checkWidth / 2 and
                                self:CanEQ(self:GetQPos(pred.castPosition), pred.castPosition, target)
                         then
                            collOrbs[orb] = 0
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
                return true
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
        self.spell.e.delay = 0.25 + NetClient.ping / 1000
        self:CalcQEShort(target, self.spell.e.widthMax)
        local pred = _G.Prediction.GetPrediction(target, self.spell.e, myHero)
        if
            pred and pred.castPosition and GetDistance(pred.castPosition) <= self.spell.e.range and
                self:CanEQ(self:GetQPos(pred.castPosition, 200), pred.castPosition, target) and
                (pred.realHitChance == 1 or _G.Prediction.WaypointManager.ShouldCast(target)) and
                (not self.spell.e.next or
                    GetDistanceSqr(self.spell.e.next.pos) > self.spell.e.range * self.spell.e.range or
                    self.spell.e.next.time <=
                        os.clock() + self.spell.e.delay + GetDistance(pred.castPosition) / self.spell.e.speed)
         then
            myHero.spellbook:CastSpell(SpellSlot.Q, self:GetQPos(pred.castPosition, 200):toDX3())
            self.spell.e.queue = {pos = pred.castPosition, time = os.clock() + 0.1, spell = 0}
            return true
        end
    end
end

function Syndra:CastQELong(target)
    if
        myHero.spellbook:CanUseSpell(SpellSlot.Q) == SpellState.Ready and
            myHero.spellbook:CanUseSpell(SpellSlot.E) == SpellState.Ready and
            myHero.mana >= 80 + 10 * myHero.spellbook:Spell(0).level
     then
        self.spell.qe.delay = 0.25 + NetClient.ping / 1000
        self:CalcQELong(target, self.spell.q.range - 50)
        local pred = _G.Prediction.GetPrediction(target, self.spell.e, myHero)
        if
            pred and pred.castPosition and GetDistanceSqr(pred.castPosition) >= self.spell.e.range * self.spell.e.range and
                GetDistanceSqr(pred.castPosition) < self.spell.qe.range * self.spell.qe.range and
                (pred.realHitChance == 1 or _G.Prediction.WaypointManager.ShouldCast(target))
         then
            local myHeroPred = _G.Prediction.GetUnitPosition(myHero, NetClient.ping / 1000)
            local qPos = Vector(myHeroPred):extended(Vector(pred.castPosition), (self.spell.q.range - 50)):toDX3()
            myHero.spellbook:CastSpell(SpellSlot.Q, qPos)
            self.spell.e.queue = {pos = pred.castPosition, time = os.clock() + 0.1, spell = 0}
            return true
        end
    end
end

function Syndra:GetQPos(predPos, offset)
    offset = offset or 0
    local myHeroPred = _G.Prediction.GetUnitPosition(myHero, NetClient.ping / 1000)
    return Vector(myHeroPred):extended(Vector(predPos), math.min(GetDistance(predPos) + 450 - offset, 850 - offset))
end

function Syndra:CastWE(target)
    if
        myHero.spellbook:CanUseSpell(SpellSlot.W) == SpellState.Ready and
            myHero.spellbook:CanUseSpell(SpellSlot.E) == SpellState.Ready and
            myHero.mana >= 100 + 10 * myHero.spellbook:Spell(1).level and
            self.spell.w.heldInfo
     then
        self.spell.e.delay = 0.25 + NetClient.ping / 1000
        self:CalcQEShort(target, self.spell.e.widthMax)
        local pred = _G.Prediction.GetPrediction(target, self.spell.e, myHero)
        if
            pred and pred.castPosition and GetDistance(pred.castPosition) <= self.spell.e.range and
                self:CanEQ(self:GetQPos(pred.castPosition, 200), pred.castPosition, target) and
                (pred.realHitChance == 1 or _G.Prediction.WaypointManager.ShouldCast(target)) and
                self.spell.w.heldInfo and
                self.spell.w.heldInfo.isOrb
         then
            myHero.spellbook:CastSpell(SpellSlot.W, self:GetQPos(pred.castPosition, 200):toDX3())
            self.spell.e.queue = {pos = pred.castPosition, time = os.clock() + 0.1, spell = 1}
            return true
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
                    self.spell.e.blacklist[orb.obj] = orb.obj.position
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
end

function Syndra:OnBuffGain(obj, buff)
end

function Syndra:OnBuffLost(obj, buff)
    if obj == myHero and buff.name == "syndrawtooltip" then
        self.spell.w.heldInfo = nil
    end
end

function Syndra:OnProcessSpell(obj, spell)
    if obj == myHero then
        if spell.spellData.name == "SyndraQ" then
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
                self.spell.e.queue = nil
            end
        elseif spell.spellData.name == "SyndraWCast" then
            if
                self.spell.e.queue and self.spell.e.queue.spell == 1 and
                    myHero.spellbook:CanUseSpell(SpellSlot.E) == SpellState.Ready
             then
                myHero.spellbook:CastSpell(SpellSlot.E, self.spell.e.queue.pos)
                self.spell.e.queue = nil
            end
            self.spell.e.next = {
                time = os.clock() + GetDistance(spell.endPos, spell.startPos) / self.spell.w.speed,
                pos = spell.endPos
            }
        elseif spell.spellData.name == "SyndraE" then
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
                        nextCheckTime = os.clock() + 0.1,
                        pos = self.orbs[i].obj.position
                    }
                end
            end
        end
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

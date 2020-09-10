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

local Lucian = class()
Lucian.version = 1.11

require "FF15Menu"
require "utils"
local Orbwalker = require "ModernUOL"
local DreamTS = require("DreamTS")
local Vector = require("GeometryLib").Vector
local LineSegment = require("GeometryLib").LineSegment
local dmgLib = require("FF15DamageLib")

function Lucian:__init()
    self.lastAttackDeleteTimer = nil
    self.lastAttackInvoke = nil
    self.lastAttackExecute = RiotClock.time
    self.lastAttack = {
        isHero = false,
        time = RiotClock.time,
        isExecuted = false,
        isPassive = false
    }
    self.shouldUseSpell = false
    self.usedSpell = nil
    self.eManager = {
        last = 0,
        change = RiotClock.time
    }
    self.eLastCd = {
        cd = 0,
        time = RiotClock.time
    }
    self.eCd = 0
    self.last = {
        q = nil,
        w = nil,
        e = nil,
        r = nil
    }
    self.qUsed = nil
    self.passiveTracker = {}
    self.lastPassive = RiotClock.time
    self.e = {
        minDist = 135,
        maxDist = 425,
        dashSpeed = 1350,
        queue = nil
    }

    self.q =
        setmetatable(
        {
            type = "linear",
            speed = math.huge,
            shortRange = 500,
            range = 900,
            width = 90
        },
        {
            __index = function(self, key)
                if key == "delay" then
                    local qDelays = {
                        0.4,
                        0.39,
                        0.38,
                        0.38,
                        0.36,
                        0.36,
                        0.34,
                        0.33,
                        0.32,
                        0.32,
                        0.31,
                        0.30,
                        0.29,
                        0.28,
                        0.27,
                        0.27,
                        0.26,
                        0.25,
                        0.25
                    }
                    return qDelays[math.min(myHero.experience.level, 18)]
                end
            end
        }
    )
    self.w = {
        type = "linear",
        speed = 2800,
        range = 900,
        delay = 0.25,
        width = 110,
        height = 350
    }
    self.r = {
        type = "linear",
        speed = 2800,
        range = 1150,
        delay = 0,
        width = -150,
        collision = {
            ["Wall"] = true,
            ["Hero"] = true,
            ["Minion"] = true
        }
    }
    self.rData = {
        width1 = 285,
        width2 = 150,
        direction = Vector(myHero.position):normalized()
    }
    self.autoFollow = true
    self.level = RiotClock.time
    self.gapcloserDB = {
        ["Headbutt"] = {
            time = function(startPos, endPos)
                return 0.35 + GetDistance(startPos, endPos) / 2000
            end,
            radius = 365,
            pos = function(spell)
                return spell.target.position
            end,
            condition = function()
                return true
            end
        }
    }
    self.gapclosers = {}
    self.lastCalled = 0
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
        Events.OnBasicAttack,
        function(...)
            self:OnBasicAttack(...)
        end
    )
    AddEvent(
        Events.OnBuffGain,
        function(...)
            self:OnBuffGain(...)
        end
    )
    PrintChat("Lucian loaded")
    PrintChat("Please unbind/unsmartcast Lucian E and R on League and use the key in the script")

    self.font = DrawHandler:CreateFont("Calibri", 10)
end

function Lucian:Menu()
    self.menu = Menu("LucianEmpyrean", "Lucian - Empyrean v" .. self.version)
    self.menu:sub("dreamTs", "Target Selector")
    self.menu:key("e", "Queue E position", string.byte("T"))
    self.menu:slider("dashMin", "Dash min dist limit", 0, 1500, 350):tooltip(
        "If your mouse position is less than x units away from myHero it will dash min distance"
    )
    self.menu:slider("dashMax", "Dash max dist limit", 0, 1500, 800):tooltip(
        "If your mouse position is more than x units away from myHero it will dash max distance"
    )
    self.menu:checkbox("draw", "Draw dash dist (above options)", true)
    self.menu:key("manualE", "Manual E Key", string.byte("E")):tooltip(
        "Unbind/Unsmartcast Lucian E on League and use this key to E. It will weave better combo and will check for dashes into wall"
    )
    self.menu:key("r", "Cast R to target nearest mouse", string.byte("R")):tooltip(
        "Unbind/Unsmartcast Lucian R on League and use this key to R"
    )
    self.menu:key("autoFollow", "Turn off auto follow R", string.byte("Z"))
end

function Lucian:OnDraw()
    local hasQ = false
    local buff = myHero.buffManager:HasBuff("LucianR")
    if buff then
        local text = "Auto follow R: " .. (self.autoFollow and "on" or "off")
        DrawHandler:Text(DrawHandler.defaultFont, Renderer:WorldToScreen(myHero.position), text, Color.White)
        local pos1 = Renderer:WorldToScreen(myHero.position)
        local pos2 = Renderer:WorldToScreen((Vector(myHero.position) + self.rData.direction * self.r.range):toDX3())
        DrawHandler:Line(pos1, pos2, Color.White)
    end
    if self.e.queue then
        hasQ = true
        DrawHandler:Circle3D(self.e.queue.pos, 30, Color.Red)
    end
    for _, spell in pairs(self.gapclosers) do
        DrawHandler:Circle3D(spell.pos, spell.radius, Color.White)
    end
    if self.menu.draw:get() then
        DrawHandler:Circle3D(myHero.position, self.menu.dashMin:get(), Color.Orange)
        DrawHandler:Circle3D(myHero.position, self.menu.dashMax:get(), Color.SkyBlue)
    end
    --[[     local mousePos = Vector(pwHud.hudManager.virtualCursorPos)
    local enemies = ObjectManager:GetEnemyHeroes()
    local lowDist, lowEnemy = 10000, nil
    for _, enemy in pairs(enemies) do
        if GetDistance(enemy) < lowDist then
            lowDist, lowEnemy = GetDistance(enemy), enemy
        end
    end

    local heroPos = Vector(myHero.position)
    local endPos = heroPos:extended(Vector(lowEnemy.position), self.q.range)
    local diff = (heroPos - endPos):rotated(0, math.pi / 2, 0):normalized() * 45
    local pos1 = Renderer:WorldToScreen((heroPos + diff):toDX3())
    local pos2 = Renderer:WorldToScreen((heroPos - diff):toDX3())
    local pos3 = Renderer:WorldToScreen((endPos + diff):toDX3())
    local pos4 = Renderer:WorldToScreen((endPos - diff):toDX3())
    DrawHandler:Line(pos1, pos3, Color.White)
    DrawHandler:Line(pos2, pos4, Color.White)
 ]]
    -- local pos1 = heroPos:extended(mousePos, self.w.range - self.w.height)
    -- local pos2 = heroPos:extended(mousePos, self.w.range + self.w.height)
    -- local diff = (pos1 - endPos):rotated(0, math.pi / 2, 0)
    -- local pos3 = endPos + diff
    -- local pos4 = endPos - diff
    -- endPos.y = myHero.position.y
    -- pos1.y = myHero.position.y
    -- pos2.y = myHero.position.y
    -- pos3.y = myHero.position.y
    -- pos4.y = myHero.position.y

    -- DrawHandler:Circle3D(endPos:toDX3(), 5, Color.White)
    -- DrawHandler:Circle3D(pos1:toDX3(), 5, Color.White)
    -- DrawHandler:Circle3D(pos2:toDX3(), 5, Color.White)
    -- DrawHandler:Circle3D(pos3:toDX3(), 5, Color.White)
    -- DrawHandler:Circle3D(pos4:toDX3(), 5, Color.White)

    local mousePos = pwHud.hudManager.activeVirtualCursorPos
    local dist = math.min(math.max(GetDistance(mousePos), self.e.minDist), self.e.maxDist)
    local pos1 = Vector(myHero.position):extended(Vector(mousePos), dist):toDX3()
    local pos12 = Vector(myHero.position):extended(Vector(mousePos), dist - myHero.boundingRadius):toDX3()
    local pos13 = Vector(myHero.position):extended(Vector(mousePos), dist + myHero.boundingRadius):toDX3()
    local pos2 = Vector(myHero.position):extended(Vector(mousePos), self.e.minDist):toDX3()
    local pos22 = Vector(myHero.position):extended(Vector(mousePos), self.e.minDist + myHero.boundingRadius):toDX3()
    local pos23 = Vector(myHero.position):extended(Vector(mousePos), self.e.minDist + myHero.boundingRadius):toDX3()

    function BoolToText(val)
        if val == true then
            return "True"
        elseif not val then
            return "False"
        else
            return val
        end
    end
    text = "lastPassive: " .. RiotClock.time - self.lastPassive
    text = text .. "\ninvoke: " .. BoolToText(self.lastAttackInvoke)
    text = text .. "\nlastAttackExecute: " .. BoolToText(self.lastAttackExecute)
    text = text .. "\nshouldCast: " .. BoolToText(self:ShouldCast())
    text = text .. "\nlastq: " .. BoolToText(self.last.q)
    text = text .. "\nlastw: " .. BoolToText(self.last.w)
    text = text .. "\nlaste: " .. BoolToText(self.last.e)
    text = text .. "\nlastr: " .. BoolToText(self.last.r)
    text = text .. "\n#passive tracker: " .. BoolToText(#self.passiveTracker)
    text = text .. "\n#ecd: " .. BoolToText(self.eCd)
    text = text .. "\n#usedd spell: " .. BoolToText(self.usedSpell)
    text = text .. "\ne queue: " .. BoolToText(hasQ)
    text = text .. "\nontick end: " .. BoolToText(self.lastCalled)
    -- DrawHandler:Text(DrawHandler.defaultFont, D3DXVECTOR2(200, 200), text, Color.White)
end

function Lucian:ShouldCast()
    for _, time in pairs(self.last) do
        if time and RiotClock.time > time and RiotClock.time < time + 0.1 + NetClient.ping / 2000 then
            return false
        end
    end
    return true
end

function Lucian:CastQ(target)
    myHero.spellbook:CastSpell(0, target.networkId)
    self.last.q = RiotClock.time
    self.usedSpell = RiotClock.time
    self.qUsed = RiotClock.time
    return true
end

function Lucian:QCollision(aimObj, predPos)
    local pos = _G.Prediction.GetUnitPosition(aimObj, NetClient.ping / 2000 + 0.06)
    local myHeroPos = _G.Prediction.GetUnitPosition(myHero, NetClient.ping / 2000 + 0.06)
    local seg = LineSegment(Vector(myHeroPos), Vector(myHeroPos):extended(Vector(pos), self.q.range))
    return seg:distanceTo(Vector(predPos))
end

function Lucian:GetQDamage(target)
    local level = myHero.spellbook:Spell(0).level
    local base = 60 + level * 35
    local add = 0.45 + 0.15 * level * myHero.characterIntermediate.flatPhysicalDamageMod
    return dmgLib:CalculatePhysicalDamage(myHero, target, base)
end

function Lucian:GetQ(short)
    local res, enemy = nil, nil
    local targets, preds = self:GetTarget(self.q, true)
    for _, target in pairs(targets) do
        local inAa = GetDistanceSqr(target) <= (self.q.shortRange + myHero.boundingRadius + target.boundingRadius) ^ 2
        local canKS = self:GetQDamage(target) >= target.health + target.allShield
        if
            preds[target.networkId] and (inAA or preds[target.networkId].rates["slow"]) and
                (not short or (inAa and not res) or canKS)
         then
            local checkWidth = self.q.width * 1 / 2
            local checkSpell =
                setmetatable(
                {
                    width = checkWidth
                },
                {__index = self.q}
            )
            local checkPred = _G.Prediction.GetPrediction(target, checkSpell)
            local best, closest = nil, 10000
            local best2, closest2 = nil, 10000
            if checkPred and checkPred.castPosition then
                local minions = ObjectManager:GetEnemyMinions()
                for _, minion in pairs(minions) do
                    if
                        _G.Prediction.IsValidTarget(minion) and
                            GetDistanceSqr(minion) <=
                                (self.q.shortRange + myHero.boundingRadius + minion.boundingRadius) ^ 2
                     then
                        local dist = self:QCollision(minion, checkPred.castPosition)
                        if dist < closest then
                            best, closest = minion, dist
                        end
                        local dist2 = self:QCollision(minion, checkPred.targetPosition)
                        if dist2 < closest2 then
                            best2, closest2 = minion, dist2
                        end
                    end
                end
                for _, target2 in pairs(targets) do
                    if
                        _G.Prediction.IsValidTarget(target2) and
                            GetDistanceSqr(target2) <=
                                (self.q.shortRange + myHero.boundingRadius + target2.boundingRadius) ^ 2
                     then
                        local dist = self:QCollision(target2, checkPred.castPosition)
                        if dist < closest then
                            best, closest = target2, dist
                        end
                        local dist2 = self:QCollision(target2, checkPred.targetPosition)
                        if dist2 < closest2 then
                            best2, closest2 = minion, dist2
                        end
                    end
                end
            end
            if best and closest < checkWidth / 2 * 3 and (not res or canKS) then
                res, enemy = best, target
            end
            if best2 and closest2 < self.q.width + target.boundingRadius and (not res or canKS) and inAa then
                res, enemy = best2, target
            end
        end
    end
    if res and enemy then
        return res, enemy
    end
end

function Lucian:GetW(center)
    local targets, preds = self:GetTarget(self.w, true)
    local mainTarget, mainPos = nil, nil
    for _, target in pairs(targets) do
        if
            preds[target.networkId] and
                GetDistanceSqr(target.position, center) <=
                    (self.q.shortRange + myHero.boundingRadius + target.boundingRadius) ^ 2 and
                not mainTarget
         then
            mainTarget, mainPos = target, Vector(preds[target.networkId].castPosition)
        end
    end
    if not mainTarget then
        return
    end
    local minions = ObjectManager:GetEnemyMinions()
    for i = #minions, 1, -1 do
        local minion = minions[i]
        if not _G.Prediction.IsValidTarget(minion) or GetDistanceSqr(minion) > self.w.range ^ 2 then
            table.remove(minions, i)
        end
    end
    -- local heroPos = Vector(myHero.position)
    -- local diff = (mainPos - heroPos):normalized()
    -- local interval, cur = 4, 0
    -- while cur < 360 do
    --     local rotated = heroPos + diff:rotated(0, math.rad(cur), 0) * self.w.range
    --     local closestPos, closestDist = rotated, self.w.range ^ 2
    --     for _, minion in pairs(minions) do
    --         local col = _G.Prediction.IsCollision(self.w, myHero.position, rotated:toDX3(), minion)
    --         if col then
    --             -- local distSqr = GetDistanceSqr(col)
    --             -- if distSqr < closestDist then
    --             --     closestPos, closestDist = col, distSqr
    --             -- end
    --         end
    --     end
    --     for _, target in pairs(targets) do
    --         local col = _G.Prediction.IsCollision(self.w, myHero.position, rotated:toDX3(), target)
    --         if col then
    --             -- local distSqr = GetDistanceSqr(col)
    --             -- if distSqr < closestDist then
    --             --     closestPos, closestDist = col, distSqr
    --             -- end
    --         end
    --     end
    --     cur = cur + interval
    -- end
    return mainPos:toDX3()
end

function Lucian:CastW(pos)
    myHero.spellbook:CastSpell(1, pos)
    self.last.w = RiotClock.time
    self.usedSpell = RiotClock.time
    return true
end

function Lucian:ManualE()
    local e = myHero.spellbook:CanUseSpell(2) == 0
    if not e then
        return
    end
    local mousePos = pwHud.hudManager.virtualCursorPos
    local dist = math.min(math.max(GetDistance(mousePos), self.e.minDist), self.e.maxDist)
    local pos1 = Vector(myHero.position):extended(Vector(mousePos), dist):toDX3()
    local pos12 = Vector(myHero.position):extended(Vector(mousePos), dist - myHero.boundingRadius):toDX3()
    local pos13 = Vector(myHero.position):extended(Vector(mousePos), dist + myHero.boundingRadius):toDX3()
    local pos2 = Vector(myHero.position):extended(Vector(mousePos), self.e.minDist):toDX3()
    local pos22 = Vector(myHero.position):extended(Vector(mousePos), self.e.minDist + myHero.boundingRadius):toDX3()
    local pos23 = Vector(myHero.position):extended(Vector(mousePos), self.e.minDist + myHero.boundingRadius):toDX3()
    if not NavMesh:IsWall(pos1) or not NavMesh:IsWall(pos2) then
        return self:CastE(pos1)
    end
end

function Lucian:CastE(pos)
    myHero.spellbook:CastSpell(2, pos)
    self.last.e = RiotClock.time
    self.e.queue = nil
    self.usedSpell = RiotClock.time
    return true
end

function Lucian:DetectECd()
    local cd = myHero.spellbook:Spell(2).cooldownTimeRemaining
    local diff = RiotClock.time - self.eLastCd.time
    if self.eLastCd.cd > 0 and cd < self.eLastCd.cd - diff - 0.1 then
        lowTime, lowIdx = 100000, nil
        for i = #self.passiveTracker, 1, -1 do
            local passive = self.passiveTracker[i]
            if not passive.obj and passive.isDeleted and passive.time and passive.time < lowTime then
                lowTime, lowIdx = passive.time, i
            end
        end
        if lowIdx then
            table.remove(self.passiveTracker, lowIdx)
        end
    end
    self.eLastCd = {
        cd = cd,
        time = RiotClock.time
    }
end

function Lucian:ManagePassiveTracker()
    for i = #self.passiveTracker, 1, -1 do
        local passive = self.passiveTracker[i]
        if
            not passive.obj and passive.isDeleted and passive.time and
                passive.time + NetClient.ping / 2000 + 0.05 < RiotClock.time
         then
            table.remove(self.passiveTracker, i)
        elseif passive.isExecuted and not passive.isDeleted and passive.target then
            local obj = ObjectManager:GetUnitByNetworkId(passive.target)
            if (obj and obj.isDead or obj.health == 0) or not obj then
                table.remove(self.passiveTracker, i)
            end
        elseif passive.isExecuted and not passive.obj and passive.order == 2 and RiotClock.time > passive.time + 0.30 then
            table.remove(self.passiveTracker, i)
        elseif not passive.isExecuted and RiotClock.time > myHero.attackCastDelay + passive.time + 0.1 then
            table.remove(self.passiveTracker, i)
        end
    end
end

function Lucian:CalcECd()
    local cd = myHero.spellbook:Spell(2).cooldownTimeRemaining
    for _, passive in pairs(self.passiveTracker) do
        cd = cd - (passive.isHero and 2 or 1)
    end
    return cd
end

function Lucian:CastR()
    local r = myHero.spellbook:CanUseSpell(3) == 0
    local buff = myHero.buffManager:HasBuff("LucianR")
    if buff and buff.remainingTime > 0 then
        myHero.spellbook:CastSpell(3, myHero.position)
        return
    end
    if r then
        local target, pred = self:GetTarget(self.r, false, nil, nil, self.TS.Modes["Closest To Mouse"])
        if target and pred then
            myHero.spellbook:CastSpell(3, pred.targetPosition)
            self.last.r = RiotClock.time
            self.usedSpell = RiotClock.time
            return true
        end
    end
end

function Lucian:AntiGapcloserE()
    local e = myHero.spellbook:CanUseSpell(2) == 0
    local buff = myHero.buffManager:HasBuff("blackshield")
    local used = false
    local predPos = _G.Prediction.GetUnitPosition(myHero, 0.06 + NetClient.ping / 2000)
    for i = #self.gapclosers, 1, -1 do
        local spell = self.gapclosers[i]
        if RiotClock.time > spell.time then
            table.remove(self.gapclosers, i)
        else
            if
                not used and e and (not buff or buff.remainingTime < spell.time - RiotClock + 0.05) and
                    GetDistanceSqr(predPos, spell.pos) < spell.radius ^ 2
             then
                local evadeDist =
                    math.min(
                    self.e.dashSpeed * (spell.time - RiotClock.time - NetClient.ping / 2000 - 0.06 - 0.05),
                    self.e.maxDist
                )
                local dist1 = GetDistance(spell.startPos, predPos)
                local pos1 = Vector(spell.startPos):extended(Vector(predPos), dist1 + evadeDist):toDX3()
                if self:CastE(pos1) then
                    used = true
                    table.remove(self.gapclosers, i)
                end
            end
        end
    end
    return used
end

function Lucian:AutoFollow()
    if self.menu.autoFollow:get() then
        self.autoFollow = false
        return
    end
    local enemies, preds = self:GetTarget(self.r, true)
    local checkSpell =
        setmetatable(
        {
            width = self.rData.width1
        },
        {__index = self.r}
    )
    for _, enemy in pairs(enemies) do
        if preds[enemy.networkId] then
            local endPos = Vector(myHero.position) + self.rData.direction * (self.r.range + enemy.boundingRadius)
            local col = _G.Prediction.IsCollision(checkSpell, myHero.position, endPos, enemy)
            if col then
                Orbwalker:BlockMove(true)
                local ts = Vector(preds[enemy.networkId].targetPosition)
                local seg = LineSegment(Vector(myHero.position), endPos)
                local dist = seg:distanceTo(ts)
                local diff = self.rData.direction:rotated(0, math.pi / 2, 0)
                local hor = diff * dist
                local pos1 = Vector(myHero.position) + hor
                local pos2 = Vector(myHero.position) - hor
                local adjustPos = pos1:distSqr(ts) > pos2:distSqr(ts) and pos2 or pos1
                local movePos = adjustPos
                if dist <= enemy.boundingRadius + self.rData.width2 / 2 then
                    local mousePos = Vector(pwHud.hudManager.virtualCursorPos)
                    local verDist = math.sqrt((enemy.boundingRadius + self.rData.width2 / 2) ^ 2 - dist ^ 2)
                    local endPos2 =
                        Vector(myHero.position) - self.rData.direction * (self.r.range + enemy.boundingRadius)
                    local dir = endPos:distSqr(mousePos) < endPos2:distSqr(mousePos) and 1 or -1
                    movePos = adjustPos + dir * self.rData.direction * verDist
                end
                if movePos then
                    local interval, cur = 25, 0
                    local moveDist = Vector(myHero.position):dist(movePos)
                    while cur <= moveDist do
                        if NavMesh:IsWall(Vector(myHero.position):extended(movePos, cur):toDX3()) then
                            Orbwalker:BlockMove(false)
                            return
                        end
                        cur = cur + interval
                    end
                    myHero:IssueOrder(GameObjectOrder.MoveTo, movePos:toDX3())
                end
                return
            end
        end
    end
    Orbwalker:BlockMove(false)
end

function Lucian:OnTick()
    if self.lastAttackDeleteTimer and RiotClock.time > self.lastAttackDeleteTimer then
        self.lastAttackDeleteTimer = nil
        self.lastAttackInvoke = nil
        self.lastAttackExecute = RiotClock.time
    end
    self:DetectECd()
    self.eCd = self:CalcECd()
    self:ManagePassiveTracker()
    if self.last.q and self.qUsed and RiotClock.time > self.qUsed + NetClient.ping / 1000 + 0.033 then
        self.last.q = nil
    end
    local e = myHero.spellbook:CanUseSpell(2)
    if e ~= self.eManager.last then
        self.eManager = {last = e, change = RiotClock.time}
    end
    if self.e.queue then
        if RiotClock.time > self.e.queue.time + 1 then
            self.e.queue = nil
        elseif RiotClock.time > self.e.queue.time + 0.5 then
            local diff = Vector(self.e.queue.pos) - Vector(self.e.queue.heroPos)
            self.e.queue.pos = (Vector(myHero.position) + diff):toDX3()
            self.e.queue.heroPos = myHero.position
        end
    end
    local hasObj = false
    for _, passive in pairs(self.passiveTracker) do
        if passive.obj then
            hasObj = true
        end
    end
    if
        self.lastAttackExecute and RiotClock.time > self.lastAttackExecute + 0.1 and
            ((not hasObj and RiotClock.time > self.lastPassive + 0.2) or self.eCd > 0.2 or
                (e == 0 and RiotClock.time > self.eManager.change + 0.1))
     then
        self.lastAttackExecute = nil
    end
    if self.menu.e:get() then
        self:QueueEPos()
    end
    if IsKeyDown(17) then
        self.level = RiotClock.time
    end
    self.lastCalled = "checkpoint1"
    if self:AntiGapcloserE() then
        return
    end
    self.lastCalled = "checkpoint2"
    local buff = myHero.buffManager:HasBuff("LucianR")
    if buff and self.autoFollow then
        self:AutoFollow()
    else
        Orbwalker:BlockMove(false)
    end
    if self:ShouldCast() then
        self.lastCalled = "checkpoint3"
        if self.menu.manualE:get() and RiotClock.time > 0.25 + self.level and self:ManualE() then
            return
        end
        self.lastCalled = "checkpoint4"
        if self.menu.r:get() and self:CastR() then
            return
        end
        self.lastCalled = "checkpoint5"
        if not self.lastAttackInvoke and myHero.aiManagerClient.navPath.dashSpeed ~= self.e.dashSpeed then
            self.lastCalled = "checkpoint6"
            if Orbwalker:GetMode() == "Combo" then
                self:Combo()
            elseif Orbwalker:GetMode() == "Harass" then
                self:Harass()
            end
        end
    end
end

function Lucian:Combo()
    local q = myHero.spellbook:CanUseSpell(0) == 0
    local w = myHero.spellbook:CanUseSpell(1) == 0
    local e = myHero.spellbook:CanUseSpell(2) == 0
    local notQ = myHero.spellbook:CanUseSpell(0) ~= 0
    local notW = myHero.spellbook:CanUseSpell(1) ~= 0
    local notE = myHero.spellbook:CanUseSpell(2) ~= 0
    local alone = #self:GetTargetRange(myHero.characterIntermediate.attackRange, true, true) == 0
    local buff = myHero.buffManager:HasBuff("LucianPassiveBuff")
    local hasPassive = buff and buff.remainingTime > 0
    local aim, target = self:GetQ(true)
    local qInRange = false
    local predPos = nil
    self.lastCalled = "checkpoint7"
    if aim and target then
        predPos = _G.Prediction.GetUnitPosition(target, 0.06 + NetClient.ping / 2000 + 0.2)
        if
            (self:GetQDamage(target) >= target.health + target.allShield or
                ((GetDistanceSqr(predPos) < (500 + myHero.boundingRadius + target.boundingRadius) ^ 2) and
                    GetDistanceSqr(aim) < 500 ^ 2))
         then
            qInRange = true
        end
    end
    local wPos = self:GetW(myHero.position)
    local wInRange = false
    if wPos and GetDistanceSqr(wPos) < 450 ^ 2 then
        wInRange = true
    end
    local qTime = RiotClock.time < self.lastAttack.time + myHero.attackDelay - myHero.attackCastDelay - self.q.delay
    local wTime = RiotClock.time < self.lastAttack.time + myHero.attackDelay - myHero.attackCastDelay - self.w.delay

    if
        self.lastAttack.isHero and RiotClock.time < self.lastAttack.time + myHero.attackDelay - myHero.attackCastDelay and
            not self.usedSpell
     then
        self.lastCalled = "checkpoint8"
        if self.lastAttackExecute then
            self.lastCalled = "checkpoint9"
            if
                self.e.queue and (hasPassive or ((notQ or not qInRange) and (notW or not wInRange))) and e and
                    self:CastE(self.e.queue.pos)
             then
                return
            end
        end
        if
            q and (qTime or self.lastAttackExecute) and aim and
                target.health + target.allShield <=
                    self:GetQDamage(target) + dmgLib:GetAutoAttackDamage(myHero, target) * 2 and
                self:CastQ(aim)
         then
            return
        end
        if w and wInRange and (wTime or self.lastAttackExecute) and wPos and self:CastW(wPos) then
            return
        end
        self.lastCalled = "checkpoint12"
        if q and (qTime or self.lastAttackExecute) and aim and self:CastQ(aim) then
            return
        end
        -- self.lastCalled = "checkpoint10"
        -- if q and (qTime or self.lastAttackExecute) and qInRange and self:CastQ(aim) then
        --     return
        -- end
        self.lastCalled = "checkpoint11"
        if w and (wTime or self.lastAttackExecute) and wPos and self:CastW(wPos) then
            return
        end
    -- self.lastCalled = "checkpoint12"
    -- if q and (qTime or self.lastAttackExecute) and aim and self:CastQ(aim) then
    --     return
    -- end
    end
    self.lastCalled = "checkpoint13"

    if alone and not hasPassive then
        self.lastCalled = "checkpoint14"
        if q then
            local target = self:GetQ()
            if target and self:CastQ(target) then
                return
            end
        end
        self.lastCalled = "checkpoint15"
        if w then
            local predPos = _G.Prediction.GetUnitPosition(myHero, NetClient.ping / 2000 + 0.06 + 0.2)
            local valid, interval, cur, dist = true, 50, 0, GetDistance(predPos)
            while cur * interval < dist do
                local pos = Vector(myHero.position):extended(Vector(predPos), cur * interval):toDX3()
                if NavMesh:IsWall(pos) and not NavMesh:IsBuilding(pos) then
                    valid = false
                end
                cur = cur + 1
            end
            if #self:GetTargetRange(self.q.shortRange, true, true, predPos) > 0 then
                local wPos = self:GetW(predPos)
                if wPos and self:CastW(wPos) then
                    return
                end
            end
        end
    end
    if
        not hasPassive and
            (not self.lastAttack.isHero or
                RiotClock.time >= self.lastAttack.time + myHero.attackDelay - myHero.attackCastDelay)
     then
        self.lastCalled = "checkpoint16"
        if
            aim and target and
                GetDistanceSqr(predPos) > (self.q.shortRange + myHero.boundingRadius + target.boundingRadius) ^ 2 and
                self:CastQ(aim)
         then
            return
        end
        self.lastCalled = "checkpoint17"
    end
end

function Lucian:Harass()
    local q = myHero.spellbook:CanUseSpell(0)
    if not self.lastAttackInvoke and q == 0 then
        local target = self:GetQ()
        if target and self:CastQ(target) then
            return
        end
    end
end

function Lucian:QueueEPos()
    local mousePos = pwHud.hudManager.virtualCursorPos
    local dist = GetDistance(mousePos)
    local dashMin = self.menu.dashMin:get()
    local dashMax = self.menu.dashMax:get()
    local dashDist =
        self.e.minDist +
        math.max(0, (math.min(dist, dashMax) - dashMin) / (dashMax - dashMin) * (self.e.maxDist - self.e.minDist))
    self.e.queue = {
        pos = Vector(myHero.position):extended(Vector(mousePos), dashDist):toDX3(),
        time = RiotClock.time,
        heroPos = myHero.position
    }
end

function Lucian:OnCreateObject(obj)
    if obj.name == "LucianRMissile" then
        self.rData.direction = (Vector(obj.asMissile.destPos) - Vector(obj.asMissile.launchPos)):normalized()
    end
    if string.find(obj.name, "Lucian") and string.find(obj.name, "Attack") then
        self.lastAttack.isExecuted = true
        self.lastAttack.time = RiotClock.time
        self.lastAttackDeleteTimer = RiotClock.time + 0.02
        self.usedSpell = nil
    end
    if obj.name == "LucianWMissile" then
    elseif obj.name == "LucianPassiveShot" then
        local lowTime, lowIdx = 100000, nil
        for i = #self.passiveTracker, 1, -1 do
            local passive = self.passiveTracker[i]
            if passive.isExecuted and not passive.isDeleted and not passive.obj and passive.order == 2 then
                if passive.time < lowTime then
                    lowTime, lowIdx = passive.time, i
                end
            end
        end
        if lowIdx then
            table.remove(self.passiveTracker, lowIdx)
        end
        if obj.asMissile and obj.asMissile.target then
            table.insert(
                self.passiveTracker,
                {
                    order = 2,
                    isHero = obj.asMissile.target.type == 1,
                    time = RiotClock.time,
                    obj = obj,
                    target = obj.asMissile.target.networkId + 0,
                    isExecuted = true,
                    isDeleted = false
                }
            )
        end
    elseif obj.name == "LucianPassiveAttack" then
        local lowTime, lowIdx = 100000, nil
        for i = #self.passiveTracker, 1, -1 do
            local passive = self.passiveTracker[i]
            if not passive.isDeleted and not passive.obj and not passive.isExecuted then
                if passive.order == 1 then
                    if passive.time < lowTime then
                        lowTime, lowIdx = passive.time, i
                    end
                else
                    passive.isExecuted = true
                    passive.time = RiotClock.time
                end
            end
        end
        if lowIdx then
            table.remove(self.passiveTracker, lowIdx)
        end
        if obj.asMissile and obj.asMissile.target then
            table.insert(
                self.passiveTracker,
                {
                    order = 1,
                    isHero = obj.asMissile.target.type == 1,
                    time = RiotClock.time,
                    obj = obj,
                    target = obj.asMissile.target.networkId + 0,
                    isExecuted = true,
                    isDeleted = false
                }
            )
        end
    elseif obj.name == "LucianPassiveShotDummy" then
        local lowTime, lowIdx = 100000, nil
        for i = #self.passiveTracker, 1, -1 do
            local passive = self.passiveTracker[i]
            if not passive.obj and not passive.isDeleted and passive.order == 2 then
                if passive.time < lowTime then
                    lowTime, lowIdx = passive.time, i
                end
            end
        end
        if lowIdx then
            table.remove(self.passiveTracker, lowIdx)
        end
    elseif obj.name == "LucianPassiveAttackDummy" then
        local lowTime, lowIdx = 100000, nil
        for i = #self.passiveTracker, 1, -1 do
            local passive = self.passiveTracker[i]
            if not passive.obj and not passive.isDeleted and passive.order == 1 then
                if passive.time < lowTime then
                    lowTime, lowIdx = passive.time, i
                end
            end
        end
        if lowIdx then
            table.remove(self.passiveTracker, lowIdx)
        end
    end
end

function Lucian:OnDeleteObject(obj)
    for _, passive in pairs(self.passiveTracker) do
        if passive.obj and passive.obj.networkId == obj.networkId then
            passive.time = RiotClock.time
            passive.obj = nil
            passive.isDeleted = true
            self.lastPassive = RiotClock.time
            return
        end
    end
end

function Lucian:OnBasicAttack(obj, spell)
    if obj == myHero then
        self.usedSpell = false
        self.lastAttackInvoke = RiotClock.time
        self.lastAttackExecute = nil
        if not self.lastAttack.isExecuted then
            for i = #self.passiveTracker, 1, -1 do
                if not self.passiveTracker[i].isExecuted then
                    table.remove(self.passiveTracker, i)
                end
            end
        end
        self.lastAttack = {
            isHero = spell.target.type == 1,
            time = RiotClock.time,
            isExecuted = false,
            isPassive = spell.spellData.name == "LucianPassiveAttack"
        }
        if self.lastAttack.isPassive then
            table.insert(
                self.passiveTracker,
                {
                    order = 1,
                    isHero = self.lastAttack.isHero,
                    time = RiotClock.time,
                    obj = nil,
                    isExecuted = false,
                    isDeleted = false
                }
            )
            table.insert(
                self.passiveTracker,
                {
                    order = 2,
                    isHero = self.lastAttack.isHero,
                    time = RiotClock.time,
                    obj = nil,
                    isExecuted = false,
                    isDeleted = false
                }
            )
        end
    end
end

function Lucian:OnProcessSpell(obj, spell)
    if obj == myHero then
        if spell.spellData.name == "LucianQ" then
            if self.qUsed then
                self.qUsed = nil
            end
        elseif spell.spellData.name == "LucianE" then
            self.last.e = nil
            self.usedSpell = RiotClock.time
        elseif spell.spellData.name == "LucianR" then
        -- self.last.r = nil
        -- self.usedSpell = RiotClock.time
        -- self.autoFollow = true
        -- self.rData.direction = (Vector(spell.endPos) - Vector(spell.startPos)):normalized()
        end
        return
    end
    if obj.team ~= myHero.team and self.gapcloserDB[spell.spellData.name] then
        local data = self.gapcloserDB[spell.spellData.name]
        if data.condition() then
            table.insert(
                self.gapclosers,
                {
                    pos = data.pos(spell),
                    time = RiotClock.time + data.time(obj.position, data.pos(spell)),
                    radius = data.radius,
                    startPos = obj.position
                }
            )
        end
    end
end

function Lucian:OnExecuteCastFrame(obj, spell)
    if obj == myHero then
        if spell.spellData.name == "LucianQ" then
            self.last.q = nil
            self.usedSpell = RiotClock.time
        elseif spell.spellData.name == "LucianW" then
            self.last.w = nil
            self.usedSpell = RiotClock.time
        elseif string.find(spell.spellData.name, "Lucian") and string.find(spell.spellData.name, "Attack") then
        end
    end
end

function Lucian:OnBuffGain(obj, buff)
    if obj == myHero and buff.name == "LucianR" then
        self.last.r = nil
        self.usedSpell = RiotClock.time
        self.autoFollow = true
    end
end

function Lucian:GetTarget(spell, all, targetFilter, predFilter, tsMode)
    local units, preds = self.TS:GetTargets(spell, myHero.position, targetFilter, predFilter, tsMode)
    if all then
        return units, preds
    else
        local target = self.TS.target
        if target then
            return target, preds[target.networkId]
        end
    end
end

function Lucian:GetTargetRange(dist, all, boundingRadiusMod, source)
    source = source or myHero.position
    local res =
        self.TS:update(
        function(unit)
            local dist2 = boundingRadiusMod and dist + myHero.boundingRadius + unit.boundingRadius or dist
            return _G.Prediction.IsValidTarget(unit, dist2, source)
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

return Lucian

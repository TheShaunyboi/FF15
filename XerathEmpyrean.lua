if myHero.charName ~= "Xerath" then
    return
end

local Xerath = {}
local version = 3.71

GetInternalWebResultAsync(
    "XerathEmpyrean.version",
    function(v)
        if tonumber(v) > version then
            DownloadInternalFileAsync(
                "XerathEmpyrean.lua",
                SCRIPT_PATH,
                function(success)
                    if success then
                        PrintChat("Updated. Press F5")
                    end
                end
            )
        end
    end
)

require("FF15Menu")
require("utils")
local DreamTS = require("DreamTS")
local Orbwalker = require("FF15OL")
local Vector

function OnLoad()
    if not _G.Prediction then
        _G.LoadPaidScript(_G.PaidScript.DREAM_PRED)
    end

    if not _G.AuroraOrb and not _G.LegitOrbwalker then
        LoadPaidScript(PaidScript.AURORA_BUNDLE_DEV)
    end

    Vector = _G.Prediction.Vector

    Orbwalker:Setup()
    Xerath:__init()
end

function Xerath:__init()
    self.active_buffs = {}
    self.q = {
        type = "linear",
        last = nil,
        min = 750,
        max = 1500,
        charge = 1.5,
        range = 1500,
        delay = 0.61,
        width = 145,
        speed = math.huge,
        ignoreFilter = true
    }
    self.w = {
        type = "circular",
        range = 1000,
        delay = 0.83,
        radius = 270,
        speed = math.huge
    }
    self.e = {
        type = "linear",
        range = 1000,
        delay = 0.25,
        width = 125,
        speed = 1400,
        collision = {
            ["Wall"] = true,
            ["Hero"] = true,
            ["Minion"] = true
        }
    }
    self.r = {
        type = "circular",
        active = false,
        range = 5000,
        delay = 0.7,
        radius = 200,
        speed = math.huge,
        lastTarget = nil,
        mode = nil
    }

    self.LastCasts = {
        Q1 = nil,
        Q2 = nil,
        W = nil,
        E = nil,
        R = nil
    }

    self.QTracker = {
        Active = false,
        StartT = 0,
        EndT = 0
    }
    self.RTracker = {
        Active = false,
        StartT = 0,
        EndT = 0
    }
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
    PrintChat("Xerath loaded")
    self.font = DrawHandler:CreateFont("Calibri", 10)
end

function Xerath:Menu()
    self.menu = Menu("XerathEmpyrean", "Xerath - Empyrean")

    self.menu:sub("dreamTs", "Target Selector")
    self.menu:sub("antigap", "Anti Gapclose")
    self.antiGapHeros = {}
    for _, enemy in ipairs(ObjectManager:GetEnemyHeroes()) do
        self.menu.antigap:checkbox(enemy.charName, enemy.charName, true)
        self.antiGapHeros[enemy.networkId] = true
    end

    self.menu:slider("rr", "R Near Mouse Radius", 0, 3000, 1500)
    self.menu:key("tap", "Hold to Cast R", string.byte("T"))
    self.menu:key("forceW", "Force W before Q", string.byte("Z"))
end

function Xerath:DrawMinimapCircle(pos3d, radius, color)
    pos3d = Vector(pos3d)
    local pts = {}
    local dir = pos3d:normalized()

    for angle = 0, 360, 15 do
        local r = (pos3d + dir:RotatedAngle(angle) * radius):toDX3()
        local pos = TacticalMap:WorldToMinimap(r)
        if pos.x ~= 0 then
            pts[#pts + 1] = pos
        end
    end

    for i = 1, #pts - 1 do
        DrawHandler:Line(pts[i], pts[i + 1], color)
    end
end

function Xerath:ShouldCast()
    for spell, time in pairs(self.LastCasts) do
        if time and RiotClock.time < time + 0.25 + NetClient.ping / 2000 + 0.06 then
            return false
        end
    end

    return true
end

function Xerath:OnDraw()
    local isQActive, remainingTime = self:IsQActive()
    local range = self.q.max

    if isQActive then
        range = self:GetQRange(remainingTime)
    end

    DrawHandler:Circle3D(myHero.position, range, Color.White)

    if myHero.spellbook:Spell(SpellSlot.R).level > 0 then
        DrawHandler:Circle3D(myHero.position, self.r.range, Color.White)
        local radius = TacticalMap.width * self.r.range / 14692
        self:DrawMinimapCircle(myHero, self.r.range, Color.White)
    end
    if self:IsRActive() then
        DrawHandler:Circle3D(pwHud.hudManager.virtualCursorPos, self.menu.rr:get(), Color.White)
        local text = "All"
        if self.r.mode then
            text = "Mouse"
        end
        DrawHandler:Text(DrawHandler.defaultFont, Renderer:WorldToScreen(myHero.position), text, Color.White)
    end
end

function Xerath:CastQ(pred)
    local isQActive, remainingTime = self:IsQActive()
    if isQActive then
        return self:CastQ2(pred, isQActive and self:GetQRange(remainingTime) or self.q.max, remainingTime)
    else
        myHero.spellbook:CastSpell(0, pred.castPosition)
        self.LastCasts.Q1 = RiotClock.time
        self:CastQ2(pred, self.q.min)
        return true
    end
end

function Xerath:CastQ2(pred, range, remainingTime)
    local dist = GetDistanceSqr(pred.castPosition)
    local forceCast = (remainingTime and remainingTime < .1 and pred.rates["instant"])
    local rangeAdjust = range - 100

    if pred.rates["slow"] or forceCast then
        if forceCast or (pred.isMoving and not pred.targetDashing) then
            if dist > rangeAdjust * rangeAdjust then
                return
            end
        else
            if dist > range * range then
                return
            end
        end
        myHero.spellbook:UpdateChargeableSpell(0, pred.castPosition, true)

        pred.drawRange = range -- So debug draw shows it at the correct range rather than always self.q.max
        pred:draw()

        self.LastCasts.Q2 = RiotClock.time
        return true
    end
end

function Xerath:CastW(pred)
    if pred.rates["slow"] then
        myHero.spellbook:CastSpell(SpellSlot.W, pred.castPosition)
        self.LastCasts.W = RiotClock.time
        pred:draw()
        return true
    end
end

function Xerath:CastE(pred)
    if pred.rates["very slow"] then
        myHero.spellbook:CastSpell(2, pred.castPosition)
        self.LastCasts.E = RiotClock.time
        pred:draw()
        return true
    end
end

function Xerath:CastTrinket()
    if
        myHero.spellbook:CanUseSpell(SpellSlot.Trinket) and self.r.lastTarget and not self.r.lastTarget.isDead and
            not self.r.lastTarget.isVisible
     then
        local castRange = myHero.spellbook:Spell(SpellSlot.Trinket).castRange
        if GetDistanceSqr(self.r.lastTarget) <= castRange * castRange then
            myHero.spellbook:CastSpell(SpellSlot.Trinket, self.r.lastTarget.position)
        end
    end
end

function Xerath:CastR()
    if self.menu.tap:get() and myHero.spellbook:CanUseSpell(3) == 0 then
        local maxRangeSqr = self.menu.rr:get() * self.menu.rr:get()
        local mouseTarget, mousePred =
            self.TS:GetTarget(
            self.r,
            myHero,
            nil,
            function(unit)
                return GetDistanceSqr(pwHud.hudManager.virtualCursorPos, unit) <= maxRangeSqr
            end
        )

        local allTarget, allPred = self.TS:GetTarget(self.r)
        if
            self.r.lastTarget and self.r.lastTarget.isVisible and allTarget and allPred and
                allTarget ~= self.r.lastTarget
         then
            self.r.lastTarget = nil
            self.r.mode = nil
        end

        if mouseTarget and mousePred then
            if mousePred.rates["very slow"] then
                myHero.spellbook:CastSpell(3, mousePred.castPosition)
                self.LastCasts.R = RiotClock.time
                self.r.lastTarget = mouseTarget
                self.r.mode = true
                mousePred:draw()
                return true
            end
        elseif (not self.r.mode) and allTarget and allPred then
            if allPred.rates["very slow"] then
                myHero.spellbook:CastSpell(3, allPred.castPosition)
                self.LastCasts.R = RiotClock.time
                self.r.lastTarget = allTarget
                allPred:draw()
                return true
            end
        end
    end
end

local UnitsInRange = {}
-- Filter units before pred for Q, W, E
local function InComboRange(unit)
    return GetDistanceSqr(unit) < 2000 * 2000
end

local function InComboRangeCallback(unit)
    return UnitsInRange[unit.index]
end

function Xerath:TriggerBuffCallbacks()
    local buffs = myHero.buffManager.buffs

    local buffsThisTick = {}

    for i = 1, #buffs do
        ---@type BuffInstance
        local buff = buffs[i]

        if buff and buff.name and buff.name:find("Xerath") and buff.remainingTime > 0 then
            buffsThisTick[buff.name] = buff
        end
    end

    for buffName, buff in pairs(buffsThisTick) do
        if not self.active_buffs[buffName] then
            self.active_buffs[buffName] = true

            self:OnBuffGain(myHero, buff)
        end
    end

    for buffName, isBuffActive in pairs(self.active_buffs) do
        if buffName == "XerathLocusOfPower2" then
        --print(isBuffActive, buffsThisTick[buffName])
        end
        if isBuffActive and (not buffsThisTick[buffName] or buffsThisTick[buffName].remainingTime <= 0) then
            self.active_buffs[buffName] = false

            self:OnBuffLost(myHero, {name = buffName})
        end
    end
end

function Xerath:OnTick()
    if myHero.dead then
        return
    end

    self:TriggerBuffCallbacks()

    local qActive = self:IsQActive()
    local rActive = self:IsRActive()

    for i, enemy in ipairs(ObjectManager:GetEnemyHeroes()) do
        UnitsInRange[enemy.index] = InComboRange(enemy)
    end

    local ComboMode = Orbwalker:GetMode() == "Combo"
    local HarassMode = Orbwalker:GetMode() == "Harass" and not Orbwalker:IsAttacking()

    -- Will waste pred calls without these conditions as well as call Cast when can't cast
    if not qActive and self:ShouldCast() then
        if rActive then
            if self:CastTrinket() or self:CastR() then
                return
            end
        else
            self.r.lastTarget = nil
            self.r.mode = nil

            if myHero.spellbook:CanUseSpell(SpellSlot.E) == 0 then
                local e_targets, e_preds =
                    self.TS:GetTargets(self.e, myHero, InComboRangeCallback, nil, self.TS.Modes["Hybrid [1.0]"])

                for i = 1, #e_targets do
                    local unit = e_targets[i]
                    local pred = e_preds[unit.networkId]
                    if pred then
                        if
                            pred.targetDashing and self.antiGapHeros[unit.networkId] and
                                self.menu.antigap[unit.charName]:get() and
                                self:CastE(pred)
                         then
                            return
                        end
                        if pred.isInterrupt and self.menu.interrupt[pred.interruptName]:get() and self:CastE(pred) then
                            return
                        end
                    end
                end

                if ComboMode then
                    local target = e_targets[1]
                    if target then
                        local pred = e_preds[target.networkId]

                        if
                            pred and not pred:minionCollision() and not pred:heroCollision() and
                                not pred:windWallCollision() and
                                self:CastE(pred)
                         then
                            return
                        end
                    end
                end
            end

            if myHero.spellbook:CanUseSpell(SpellSlot.W) == 0 and ComboMode then
                local w_target, w_pred = self.TS:GetTarget(self.w, myHero, InComboRangeCallback)
                if w_target and w_pred and self:CastW(w_pred) then
                    return
                end
            end
        end
    end

    if
        myHero.spellbook:CanUseSpell(SpellSlot.Q) == 0 and self:ShouldCast() and
            (ComboMode and (not self.menu.forceW:get() or myHero.spellbook:CanUseSpell(SpellSlot.W) ~= 0) or HarassMode)
     then
        self.q.range = self.q.max

        local q_target, q_pred = self.TS:GetTarget(self.q, myHero, InComboRangeCallback)

        if q_target and q_pred and self:CastQ(q_pred) then
            return
        end
    end
end

---@param unit GameObject
---@param buff BuffInstance
function Xerath:OnBuffGain(unit, buff)
    if unit.networkId == myHero.networkId then
        local time = RiotClock.time

        if buff.name == "XerathArcanopulseChargeUp" then
            Orbwalker:BlockAttack(true)

            self.QTracker.StartT = time
            self.QTracker.EndT = time + buff.remainingTime
            self.QTracker.Active = true
        elseif buff.name == "XerathLocusOfPower2" then
            Orbwalker:BlockAttack(true)
            Orbwalker:BlockMove(true)

            self.RTracker.StartT = time
            self.RTracker.EndT = time + buff.remainingTime
            self.RTracker.Active = true
        end
    end
end

---@param unit GameObject
---@param buff BuffInstance
function Xerath:OnBuffLost(unit, buff)
    if unit.networkId == myHero.networkId then
        if buff.name == "XerathArcanopulseChargeUp" then
            Orbwalker:BlockAttack(false)

            self.QTracker.Active = false
        elseif buff.name == "XerathLocusOfPower2" then
            Orbwalker:BlockAttack(false)
            Orbwalker:BlockMove(false)

            self.RTracker.Active = false
        end
    end
end

function Xerath:IsQActive()
    return self.QTracker.Active and RiotClock.time < self.QTracker.EndT, (self.QTracker.EndT - RiotClock.time)
end

function Xerath:IsRActive()
    return self.RTracker.Active
end

function Xerath:OnProcessSpell(obj, spell)
    if obj == myHero then
        if spell.spellData.name == "XerathArcanopulseChargeUp" then
            self.LastCasts.Q1 = nil
        elseif spell.spellData.name == "XerathArcanopulse2" then
            self.LastCasts.Q2 = nil
        elseif spell.spellData.name == "XerathArcaneBarrage2" then
            self.LastCasts.W = nil
        elseif spell.spellData.name == "XerathMageSpear" then
            self.LastCasts.E = nil
        elseif spell.spellData.name == "XerathLocusPulse" then
            self.LastCasts.R = nil
        end
    end
end

function Xerath:GetQRange(remainingTime)
    local chargeStart = RiotClock.time + remainingTime - 4
    return math.min(
        self.q.min + (self.q.max - self.q.min) * (RiotClock.time - chargeStart - 0.07) / self.q.charge,
        self.q.max
    )
end

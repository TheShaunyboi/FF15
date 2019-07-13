if myHero.charName ~= "Xerath" then
    return
end

local CastModeOptions = {"slow", "very slow"}

local Xerath = {}
local version = 2.5
if tonumber(GetInternalWebResult("asdfxerath.version")) > version then
    DownloadInternalFile("asdfxerath.lua", SCRIPT_PATH .. "asdfxerath.lua")
    PrintChat("New version:" .. tonumber(GetInternalWebResult("asdfxerath.version")) .. " Press F5")
end
require("FF15Menu")
require("utils")
local DreamTS = require("DreamTS")
local Orbwalker = require("FF15OL")
local Vector = require("GeometryLib").Vector

function OnLoad()
    if not _G.Prediction then
        _G.LoadPaidScript(_G.PaidScript.DREAM_PRED)
    end
    if not _G.AuroraOrb and not _G.LegitOrbwalker then
        LoadPaidScript(PaidScript.AURORA_BUNDLE)
    end
    Orbwalker:Setup()
    Xerath:__init()
end

function Xerath:__init()
    self.q = {
        type = "linear",
        last = nil,
        min = 850,
        max = 1500,
        charge = 1.2,
        range = 1450,
        delay = 0.65,
        width = 145,
        speed = math.huge,
    }
    self.w1 = {
        type = "circular",
        range = 1000,
        delay = 0.83,
        radius = 270,
        speed = math.huge,
    }
    self.w2 = {
        type = "circular",
        range = 1000,
        delay = 0.83 ,
        radius = 270,
        speed = math.huge,
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
        range = 80000,
        delay = 0.69,
        radius = 200,
        speed = math.huge,
        ignoreBuffer = true
    }

    self.WindUpTimes = {
        Q = 0.5,
        W = 0.25,
        E = 0.25,
        R = 0.25
    }

    self.LastCasts = {
        Q = 0,
        W = 0,  
        E = 0,
        R = 0
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
    PrintChat("Xerath loaded")
    self.font = DrawHandler:CreateFont("Calibri", 10)
end

function Xerath:Menu()
    self.menu = Menu("asdfxerath", "Xerath")

    self.menu:sub("dreamTs", "Target Selector")
    self.menu:sub("antigap", "Anti Gapclose")
    self.antiGapHeros = {}
    for _, enemy in ipairs(ObjectManager:GetEnemyHeroes()) do
        self.menu.antigap:checkbox(enemy.charName, enemy.charName, true)
        self.antiGapHeros[enemy.networkId] = true
    end
    self.menu:sub("interrupt", "Interrupter")
    _G.Prediction.LoadInterruptToMenu(self.menu.interrupt)

    self.menu:sub("spells", "Spell cast rates")
    self.menu.spells:list("q", "Q", 2, CastModeOptions)
    self.menu.spells:list("w", "W", 2, CastModeOptions)
    self.menu.spells:list("e", "E", 2, CastModeOptions)
    self.menu.spells:list("r", "R", 2, CastModeOptions)

    self.menu:slider("rr", "R Near Mouse Radius", 0, 3000, 1500)
    self.menu:key("tap", "Tap Key", string.byte("T"))
    self.menu:sub("xerathDraw", "Draw")
    self.menu.xerathDraw:sub("q", "Q")
    self.menu.xerathDraw.q:checkbox("q", "Q", true)
    self.menu.xerathDraw.q:slider("qa", "Alpha", 1, 255, 150)
    self.menu.xerathDraw.q:slider("qr", "Red", 1, 255, 150)
    self.menu.xerathDraw.q:slider("qg", "Green", 1, 255, 150)
    self.menu.xerathDraw.q:slider("qb", "Blue", 1, 255, 150)
    self.menu.xerathDraw:sub("r", "R")
    self.menu.xerathDraw.r:checkbox("r", "R", true)
    self.menu.xerathDraw.r:checkbox("rmini", "R Minimap", true)
    self.menu.xerathDraw.r:slider("ra", "Alpha", 1, 255, 150)
    self.menu.xerathDraw.r:slider("rr", "Red", 1, 255, 150)
    self.menu.xerathDraw.r:slider("rg", "Green", 1, 255, 150)
    self.menu.xerathDraw.r:slider("rb", "Blue", 1, 255, 150)
end

local function DrawMinimapCircle(pos3d, radius, color)
    pos3d = Vector(pos3d)
    local pts = {}
    local dir = pos3d:normalized()

    for angle = 0, 360, 15 do
        local pos = TacticalMap:WorldToMinimap((pos3d + dir:RotatedAngle(angle) * radius):toDX3())
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
        if RiotClock.time < time + self.WindUpTimes[spell] then
            return false
        end
    end

    return true
end

function Xerath:GetCastRate(spell)
    return CastModeOptions[self.menu.spells[spell].value]
end

function Xerath:OnDraw()
    if self.menu.xerathDraw.q.q:get() then
        local isQActive, remainingTime = self:IsQActive()
        local range = self.q.max

        if isQActive then
            range = self:GetQRange(remainingTime)
        end

        DrawHandler:Circle3D(
            myHero.position,
            range,
            self.Hex(
                self.menu.xerathDraw.q.qa:get() or 255,
                self.menu.xerathDraw.q.qr:get() or 255,
                self.menu.xerathDraw.q.qg:get() or 255,
                self.menu.xerathDraw.q.qb:get() or 255
            )
        )
    end
    local color =
        self.Hex(
        self.menu.xerathDraw.r.ra:get() or 255,
        self.menu.xerathDraw.r.rr:get() or 255,
        self.menu.xerathDraw.r.rg:get() or 255,
        self.menu.xerathDraw.r.rb:get() or 255
    )
    if myHero.spellbook:Spell(SpellSlot.R).level > 0 then
        self.r.range = self:GetRRange()
        if self.menu.xerathDraw.r.r:get() then
            DrawHandler:Circle3D(myHero.position, self.r.range, color)
        end
        if self.menu.xerathDraw.r.rmini:get() then
            local radius = TacticalMap.width * self.r.range / 14692
            DrawMinimapCircle(myHero, self.r.range, color)
        --DrawHandler:Circle(TacticalMap:WorldToMinimap(myHero.position), self.r.range, color)
        end
    end
    if self:IsRActive() then
        DrawHandler:Circle3D(pwHud.hudManager.virtualCursorPos, self.menu.rr:get(), color)
    end
end

function Xerath:CastQ(pred)
    local isQActive, remainingTime = self:IsQActive()

    local range = isQActive and self:GetQRange(remainingTime) or self.q.max
    local rangeAdjust = range - 100

    if isQActive then
        local dist = GetDistanceSqr(pred.castPosition)
        if pred.rates[self:GetCastRate("q")] or (dist > 100 * 100 and dist < 400 * 400) then

            if pred.isMoving and not pred.targetDashing then
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

            self.LastCasts.Q = RiotClock.time

            return true
        end
    elseif pred.rates["instant"] then
        myHero.spellbook:CastSpell(0, pwHud.hudManager.virtualCursorPos)
        return true
    end
end

function Xerath:CastW(pred)
    if pred.rates[self:GetCastRate("w")] then
        myHero.spellbook:CastSpell(SpellSlot.W, pred.castPosition)
        self.LastCasts.W = RiotClock.time
        pred:draw()
        return true
    end
end

function Xerath:CastE(pred)
    if pred.rates[self:GetCastRate("e")] then
        myHero.spellbook:CastSpell(2, pred.castPosition)
        self.LastCasts.E = RiotClock.time
        pred:draw()
        return true
    end
end

function Xerath:GetRRange()
    return 2000 + 1200 * myHero.spellbook:Spell(3).level
end

function Xerath:CastR()
    self.r.range = self:GetRRange()
    if myHero.spellbook:CanUseSpell(3) == 0 and self.menu.tap:get() then
        local maxRangeSqr = self.menu.rr:get() * self.menu.rr:get()
        local target, pred =
            self:GetTarget(
            self.r,
            false,
            function(unit)
                --return GetDistanceSqr(pwHud.hudManager.virtualCursorPos, unit.position) <= maxRangeSqr
                return true
            end
        )

        if target and pred and pred.rates[self:GetCastRate("r")] then
            myHero.spellbook:CastSpell(3, pred.castPosition)
            self.LastCasts.R = RiotClock.time
            pred:draw()
            return true
        end
    end
end

function Xerath:OnTick()
    local qActive = self:IsQActive()
    local rActive = self:IsRActive()

    if qActive or rActive then
        Orbwalker:BlockAttack(true)
    else
        Orbwalker:BlockAttack(false)
    end

    -- Will waste pred calls without these conditions as well as call Cast when can't cast
    if not qActive and self:ShouldCast() then
        if rActive then
            if self:CastR() then
                return
            end
        end

        if myHero.spellbook:CanUseSpell(SpellSlot.E) == 0 then
            local gapcloser_targets, gapcloser_preds =
                self:GetTarget(self.e, true, nil,
                function(unit, pred)
                    if not pred then return end

                    if pred.targetDashing and self.antiGapHeros[unit.networkId] and self.menu.antigap[unit.charName]:get() then
                        return true
                    end
                    if pred.isInterrupt and self.menu.interrupt[pred.interruptName]:get() then
                        return true
                    end

                    return false
                end
            )

            for i = 1, #gapcloser_targets do
                local pred = gapcloser_preds[gapcloser_targets[i].networkId]
                if pred and self:CastE(pred) then
                    return
                end
            end

            local e_target, e_pred = self:GetTarget(self.e)

            if
                e_target and e_pred and Orbwalker:GetMode() == "Combo" and not Orbwalker:IsAttacking() and
                    self:CastE(e_pred)
             then
                return
            end
        end

        if myHero.spellbook:CanUseSpell(SpellSlot.W) == 0 then
            local w2_target, w2_pred = self:GetTarget(self.w2)
            if w2_target and w2_pred then
                if Orbwalker:GetMode() == "Combo" and not Orbwalker:IsAttacking() then
                    if self:CastW(w2_pred) then
                        return
                    end
                end
            end
            local w1_target, w1_pred = self:GetTarget(self.w1)
            if w1_target and w1_pred then
                if Orbwalker:GetMode() == "Combo" and not Orbwalker:IsAttacking() then
                    if self:CastW(w1_pred) then
                        return
                    end
                end
            end
        end
    end

    if myHero.spellbook:CanUseSpell(SpellSlot.Q) == 0 and self:ShouldCast() then
        self.q.range = self.q.max

        local q_target, q_pred =
            self:GetTarget(
            self.q,
            false,
            nil,
            function(unit, pred)
                return pred.rates["instant"]
            end
        )
        if q_target and q_pred then
            if Orbwalker:GetMode() == "Combo" and not Orbwalker:IsAttacking() and self:CastQ(q_pred) then
                return
            elseif Orbwalker:GetMode() == "Harass" and not Orbwalker:IsAttacking() and self:CastQ(q_pred) then
                return
            end
        end
    end
end

function Xerath:IsQActive()
    local buffs = myHero.buffManager.buffs

    for i = 1, #buffs do
        local buff = buffs[i]

        if buff.name == "XerathArcanopulseChargeUp" then
            return true, buff.remainingTime
        end
    end

    return false, 0
end

function Xerath:IsRActive()
    local buffs = myHero.buffManager.buffs

    for i = 1, #buffs do
        local buff = buffs[i]

        if buff.name == "XerathLocusOfPower2" then
            return true, buff.remainingTime
        end
    end

    return false, 0
end

function Xerath:GetQRange(remainingTime)
    local chargeStart = RiotClock.time + remainingTime - 4
    return math.min(
        self.q.min + (self.q.max - self.q.min) * (RiotClock.time - chargeStart - 0.2) / self.q.charge,
        self.q.max
    )
end

function Xerath.Hex(a, r, g, b)
    return string.format("0x%.2X%.2X%.2X%.2X", a, r, g, b)
end

function Xerath:GetTarget(spell, all, targetFilter, predFilter)
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
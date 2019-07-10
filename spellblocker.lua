require "FF15Menu"
require "utils"

local SpellBlocker =
    setmetatable(
    {},
    {
        __call = function(self, ...)
            local result = setmetatable({}, {__index = self})
            result:__init(...)

            return result
        end
    }
)

function SpellBlocker:__init(menu)
    self.menu = menu:sub("spellblocker", "Spell Blocker")
    self.activeSpells = {}
    self.shouldBlock = false
    local enemies = ObjectManager:GetEnemyHeroes()
    for spellName, spell in pairs(spells) do
        for i = 1, #enemies do
            if spell.charName == enemies[i].charName then
                self.menu:checkbox(spellName, spellName, true)
                self.activeSpells[spellName] = spell
            end
        end
    end
    AddEvent(
        Events.OnTick,
        function()
            self:OnTick()
        end
    )
end

--[[Spell Types
    autoAttack
        name
    missile
        name
    spell
        name
        speed
            dash
        delay
    buff
        stacks
        condition
            all
            end
        unit
            self
            enemy
        name
    
            



]]
local spells = {
    ["Aatrox P Deathbringer Stance"] = {
        charName = "Aatrox",
        check = {type = "autoAttack", name = "AatroxPassiveAttack"}
    },
    ["Aatrox W Infernal Chains"] = {
        charName = "Aatrox",
        check = {type = "buff", condition = "end", unit = "self", name = "aatroxwchains"}
    },
    ["Alistar W Headbutt"] = {
        charName = "Alistar",
        check = {type = "spell", name = "Headbutt", speed = "dash"}
    },
    ["Alistar E Trample"] = {
        charName = "Alistar",
        check = {
            {type = "autoAttack", name = {"AlistarBasicAttack", "AlistarBasicAttack2"}},
            {type = "buff", condition = "all", unit = "enemy", name = "AlistarE"}
        }
    },
    ["Anivia E Frostbite (Double)"] = {
        charName = "Anivia",
        check = {
            {type = "missile", name = "Frostbite"},
            {type = "buff", condition = "all", unit = "self", name = "aniviaiced"}
        }
    },
    ["Annie Q Disintegrate (Stun)"] = {
        charName = "Annie",
        check = {
            {type = "missile", name = "AnnieQ"},
            {type = "buff", condition = "all", unit = "self", name = "anniepassiveprimed"}
        }
    },
    ["Blitzcrank E Power Fist"] = {
        charName = "Blitzcrank",
        check = {type = "autoAttack", name = "PowerFistAttack"}
    },
    ["Brand P Blaze"] = {
        charName = "Brand",
        check = {type = "buff", condition = "end", unit = "self", name = "BrandAblazeDetonateMarker"}
    },
    ["Braum P Concussive"] = {
        charName = "Braum",
        check = {
            {type = "autoAttack"},
            {type = "buff", condition = "all", unit = "self", name = "BraumMark"}
        }
    },
    ["Caitlyn P Headshot"] = {
        charName = "Caitlyn",
        check = {type = "missile", name = "CaitlynHeadshotMissile"}
    },
    ["Caitlyn R Ace in the Hole"] = {
        charName = "Caitlyn",
        check = {type = "missile", name = "CaitlynAceintheHole"}
    },
    ["Camille Q Precision Protocol"] = {
        charName = "Camille",
        check = {type = "autoAttack", name = "CamilleQAttackEmpowered"}
    },
    ["Cho'Gath R Feast"] = {
        charName = "Chogath",
        check = {type = "spell", name = "Feast"}
    },
    ["Darius R Noxian Guillotine"] = {
        charName = "Darius",
        check = {type = "spell", name = "DariusExecute"}
    },
    ["Diana P Moonsilver Blade"] = {
        charName = "Diana",
        check = {type = "autoAttack", name = "DianaBasicAttack3"}
    },
    ["Dr Mundo E Masochism"] = {
        charName = "DrMundo",
        check = {type = "autoAttack", name = "MasoChismAtttack"}
    },
    ["Ekko P Z-Drive Resonance"] = {
        charName = "Ekko",
        check = {type = "autoAttack", name = "DianaBasicAttack3"}
    },
    ["Ekko E Phase Dive"] = {
        charName = "Ekko",
        check = {type = "spell", name = "EkkoEAttack"}
    },
    ["Elise Human Q Neurotoxin"] = {
        charName = "Elise",
        check = {type = "missile", name = "EliseHumanQ"}
    },
    ["Elise Spider Q Venomous Bite"] = {
        charName = "Elise",
        check = {type = "spell", name = "EliseSpiderQCast"}
    },
    ["Fiddlesticks Q Terrify"] = {
        charName = "Fiddlesticks",
        check = {type = "spell", name = "Terrify"}
    },
    ["Fiddlesticks E Dark Wind"] = {
        charName = "Fiddlesticks",
        check = {type = "missile", name = "FiddleSticksDarkWindMissile"}
    },
    ["Fiora E Bladework (Second)"] = {
        charName = "Fiora",
        check = {
            {type = "autoAttack", name = {"FioraBasicAttack", "FioraBasicAttack2"}},
            {type = "buff", condition = "all", unit = "self", name = "fiorae2"}
        }
    },
    ["Fizz R Chum the Waters (Emerge)"] = {
        charName = "Fizz",
        check = {type = "buff", condition = "end", unit = "self", name = "fizzrbomb"}
    },
    ["Garen Q Decisive Strike"] = {
        charName = "Garen",
        check = {type = "spell", name = "GarenQAttack"}
    },
    ["Garen R Demacian Justice"] = {
        charName = "Garen",
        check = {type = "spell", name = "GarenR"}
    },
    --Gnar
    --Gragas
    ["Hecarim E Drunken Rage"] = {
        charName = "Hecarim",
        check = {type = "autoAttack", name = "HecarimRampAttack"}
    },
    ["Illaoi W Harsh Lesson"] = {
        charName = "Illaoi",
        check = {type = "autoAttack", name = "IllaoiWAttack"}
    },
    ["Irelia Q Bladesurge (Reset)"] = {
        charName = "Irelia",
        check = {
            {type = "spell", name = "IreliaQ", speed = "dash"},
            {type = "buff", condition = "all", unit = "self", name = "ireliamark"}
        }
    },
    --Ivern
    ["Janna W Zephyr"] = {
            charName = "Janna",
        check = {type = "missile", name = "SowTheWind"}
    },
}

local function OnTick()
end

local function HasBuff(unit, buffName, isEnd)
    local buffs = enemy.buffManager.buffs
    for i = 1, #buffs do
        local buff = buffs[i]
        if not isEnd or (buff.name == buffName and buff.remainingTime < 0.05 + NetClient.ping / 1000) then
            return true
        end
    end
end

return SpellBlocker

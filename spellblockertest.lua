require "FF15Menu"
require "utils"
require "SpellBlocker"

local SpellBlockerTest = {}

function OnLoad()
    SpellBlockerTest:__init()
end


function SpellBlockerTest:__init()
    self.menu = Menu("spellblockertest", "Spell Blocker Test")
    self.spellblock = SpellBlock(self.menu)
    AddEvent(
        Events.OnTick,
        function()
            self:OnTick()
        end
    )
end

function  SpellBlockerTest:OnTick()
    if spellblock.shouldblock then
        print("Hi")
    end
end


--!strict
--[[
	Module: UpgradeConfig
	Purpose: Declarative registry of the 3 visible Stage 1 Ranch Upgrades.
	Connections: Read by EconomyService, PlotService, and UIController.
	How to Test in Studio: Press Play (F5) to run SharedSelfTest verifying upgrade costs and slot mappings.
]]

local Shared = script.Parent.Parent
local Types = require(Shared:WaitForChild("Types"))

local byId: { [Types.UpgradeId]: Types.UpgradeDefinition } = {
	PenSlot_2 = table.freeze({
		Id = "PenSlot_2",
		DisplayName = "Habitat Slot #2",
		Order = 1,
		Cost = 60,
		UnlocksSlotId = "Pen_2",
		SlotCategory = "Pen",
		Description = "Expands your Ranch Pen with a second active Critter slot.",
	}),
	Incubator_2 = table.freeze({
		Id = "Incubator_2",
		DisplayName = "Incubator Pad #2",
		Order = 2,
		Cost = 150,
		UnlocksSlotId = "Incubator_2",
		SlotCategory = "Incubator",
		Description = "Builds a second Incubator Pad so you can hatch two pods at once.",
	}),
	PenSlot_3 = table.freeze({
		Id = "PenSlot_3",
		DisplayName = "Habitat Slot #3 & Ranch Arch",
		Order = 3,
		Cost = 320,
		UnlocksSlotId = "Pen_3",
		SlotCategory = "Pen",
		Description = "Widens your Ranch Deck, illuminates the Ranch Arch, and adds Slot #3.",
	}),
}

local orderedIds: { Types.UpgradeId } = table.freeze({
	"PenSlot_2",
	"Incubator_2",
	"PenSlot_3",
})

local UpgradeConfig = {
	OrderedIds = orderedIds,
	ById = table.freeze(byId),
}

return table.freeze(UpgradeConfig)

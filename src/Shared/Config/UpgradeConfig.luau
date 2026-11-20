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
		PadOffsetX = -18,
		RequiresUpgradeId = nil,
		Description = "Expands your Ranch Pen with a second active Critter slot.",
	}),
	FrostCracker = table.freeze({
		Id = "FrostCracker",
		DisplayName = "Frost Cracker",
		Order = 2,
		Cost = 120,
		UnlocksSlotId = "FrostTool",
		SlotCategory = "Tool",
		PadOffsetX = 6,
		RequiresUpgradeId = nil,
		Description = "Unlocks Frost Ridge Meteors & Frost Lures (Beetle & Nebula Fox!).",
	}),
	Incubator_2 = table.freeze({
		Id = "Incubator_2",
		DisplayName = "Incubator Pad #2",
		Order = 3,
		Cost = 190,
		UnlocksSlotId = "Incubator_2",
		SlotCategory = "Incubator",
		PadOffsetX = -10,
		RequiresUpgradeId = nil,
		Description = "Builds a second Incubator Pad so you can hatch two pods at once.",
	}),
	PenSlot_3 = table.freeze({
		Id = "PenSlot_3",
		DisplayName = "Habitat Slot #3",
		Order = 4,
		Cost = 360,
		UnlocksSlotId = "Pen_3",
		SlotCategory = "Pen",
		PadOffsetX = -2,
		RequiresUpgradeId = "PenSlot_2",
		Description = "Adds a 3rd active Critter slot in your Habitat Pen.",
	}),
	StarCracker = table.freeze({
		Id = "StarCracker",
		DisplayName = "Astral Cracker",
		Order = 5,
		Cost = 550,
		UnlocksSlotId = "AstralTool",
		SlotCategory = "Tool",
		PadOffsetX = 14,
		RequiresUpgradeId = "FrostCracker",
		Description = "Unlocks glowing Astral Meteors (Solar Golem & Comet Owl!).",
	}),
	PenSlot_4 = table.freeze({
		Id = "PenSlot_4",
		DisplayName = "Habitat Slot #4 & Gold Arch",
		Order = 6,
		Cost = 1150,
		UnlocksSlotId = "Pen_4",
		SlotCategory = "Pen",
		PadOffsetX = 21,
		RequiresUpgradeId = "PenSlot_3",
		Description = "Adds Pen Slot #4 and lights your Ranch Arch in Starlight Gold!",
	}),
}

local orderedIds: { Types.UpgradeId } = table.freeze({
	"PenSlot_2",
	"FrostCracker",
	"Incubator_2",
	"PenSlot_3",
	"StarCracker",
	"PenSlot_4",
})

local UpgradeConfig = {
	OrderedIds = orderedIds,
	ById = table.freeze(byId),
}

return table.freeze(UpgradeConfig)

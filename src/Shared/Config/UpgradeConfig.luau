--!strict
--[[
	Module: UpgradeConfig
	Purpose: Declarative registry of the 8 Stage 3 Ranch & Hub Upgrades (Ranch pads + Hub Tool Workbench).
	Connections: Read by EconomyService, PlotService, GreyboxBuilder, and UIController.
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
		StationZone = "Ranch",
		PadOffsetX = -30,
		PadOffsetZ = 27,
		RequiresUpgradeId = nil,
		Description = "Expands your Ranch Pen with a second active Critter slot.",
	}),
	FrostCracker = table.freeze({
		Id = "FrostCracker",
		DisplayName = "Frost Cracker",
		Order = 2,
		Cost = 150,
		UnlocksSlotId = "FrostTool",
		SlotCategory = "Tool",
		StationZone = "Hub",
		PadOffsetX = -32,
		PadOffsetZ = -16,
		RequiresUpgradeId = nil,
		Description = "Unlocks North Frost Ridge Meteors & Frost Lures (sold at Hub Tool Workbench).",
	}),
	Incubator_2 = table.freeze({
		Id = "Incubator_2",
		DisplayName = "Incubator Pad #2",
		Order = 3,
		Cost = 260,
		UnlocksSlotId = "Incubator_2",
		SlotCategory = "Incubator",
		StationZone = "Ranch",
		PadOffsetX = -18,
		PadOffsetZ = 27,
		RequiresUpgradeId = nil,
		Description = "Builds a second Incubator Pad so you can hatch two pods at once.",
	}),
	PenSlot_3 = table.freeze({
		Id = "PenSlot_3",
		DisplayName = "Habitat Slot #3",
		Order = 4,
		Cost = 500,
		UnlocksSlotId = "Pen_3",
		SlotCategory = "Pen",
		StationZone = "Ranch",
		PadOffsetX = -6,
		PadOffsetZ = 27,
		RequiresUpgradeId = "PenSlot_2",
		Description = "Adds a 3rd active Critter slot in your Habitat Pen.",
	}),
	StarCracker = table.freeze({
		Id = "StarCracker",
		DisplayName = "Astral Cracker",
		Order = 5,
		Cost = 850,
		UnlocksSlotId = "AstralTool",
		SlotCategory = "Tool",
		StationZone = "Hub",
		PadOffsetX = -32,
		PadOffsetZ = -32,
		RequiresUpgradeId = "FrostCracker",
		Description = "Unlocks timed Astral Fall Meteors (sold at Hub Tool Workbench).",
	}),
	PenSlot_4 = table.freeze({
		Id = "PenSlot_4",
		DisplayName = "Habitat Slot #4 & Gold Arch",
		Order = 6,
		Cost = 1850,
		UnlocksSlotId = "Pen_4",
		SlotCategory = "Pen",
		StationZone = "Ranch",
		PadOffsetX = 18,
		PadOffsetZ = 27,
		RequiresUpgradeId = "PenSlot_3",
		Description = "Adds Pen Slot #4 and lights your Ranch Arch in Starlight Gold!",
	}),
	BagCap_20 = table.freeze({
		Id = "BagCap_20",
		DisplayName = "Expanded Bag (20)",
		Order = 7,
		Cost = 1200,
		UnlocksSlotId = "Bag_20",
		SlotCategory = "Bag",
		StationZone = "Ranch",
		PadOffsetX = 6,
		PadOffsetZ = 27,
		RequiresUpgradeId = "Incubator_2",
		Description = "Doubles your Ranch Bag capacity from 10 to 20 slots.",
	}),
	PenSlot_5 = table.freeze({
		Id = "PenSlot_5",
		DisplayName = "Habitat Slot #5",
		Order = 8,
		Cost = 3600,
		UnlocksSlotId = "Pen_5",
		SlotCategory = "Pen",
		StationZone = "Ranch",
		PadOffsetX = 30,
		PadOffsetZ = 27,
		RequiresUpgradeId = "PenSlot_4",
		Description = "Adds a 5th active Critter slot in your expanded Habitat Pen.",
	}),
}

local orderedIds: { Types.UpgradeId } = table.freeze({
	"PenSlot_2",
	"FrostCracker",
	"Incubator_2",
	"PenSlot_3",
	"StarCracker",
	"PenSlot_4",
	"BagCap_20",
	"PenSlot_5",
})

local UpgradeConfig = {
	OrderedIds = orderedIds,
	ById = table.freeze(byId),
}

return table.freeze(UpgradeConfig)

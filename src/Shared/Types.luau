--!strict
--[[
	Module: Types
	Purpose: Central Luau type definitions shared across Server, Client, and Config modules.
	Connections: Required by Shared/Config, Server/Services, and Client/Controllers.
	How to Test in Studio: Play (F5) and verify zero Luau Script Analysis warnings in Output.
]]

export type SpeciesId = "StarSlime" | "NebulaFox" | "SolarGolem"
export type VariantId = "Normal" | "Radiant"
export type MeteorTraitId = "Ember" | "Frost" | "Astral"
export type ItemState = "PodInBag" | "Incubating" | "HatchedInBag" | "InPen"

export type CritterItemRecord = {
	UID: string,
	SpeciesId: SpeciesId,
	Variant: VariantId,
	State: ItemState,
	AssignedSlot: string?,
	PlantedAt: number?,
	MaturesAt: number?,
	CreatedAt: number,
}

export type PlayerProfileData = {
	SchemaVersion: number,
	Coins: number,
	PendingFraction: number,
	LastAccrualTimestamp: number,
	Revision: number,
	Items: { [string]: CritterItemRecord },
	Slots: { [string]: string },
	Upgrades: { [string]: boolean },
	DiscoveredSpecies: { [SpeciesId]: boolean },
}

export type OwnerStateDTO = {
	Revision: number,
	Coins: number,
	BagCap: number,
	Items: { [string]: CritterItemRecord },
	Slots: { [string]: string },
	Upgrades: { [string]: boolean },
	DiscoveredSpecies: { [SpeciesId]: boolean },
}

export type PublicPenVisual = {
	SpeciesId: SpeciesId,
	Variant: VariantId,
}

export type PublicIncubatorVisual = {
	MaturesAt: number,
}

export type PublicPlotDTO = {
	PlotId: number,
	OwnerUserId: number,
	OwnerDisplayName: string,
	PlotRevision: number,
	UnlockedUpgrades: { [string]: boolean },
	ActivePenVisuals: { [string]: PublicPenVisual },
	IncubatorVisuals: { [string]: PublicIncubatorVisual },
}

export type SpeciesDefinition = {
	Id: SpeciesId,
	DisplayName: string,
	HatchSeconds: number,
	CoinsPerSecond: number,
	SellPrice: number,
	Description: string,
}

export type MeteorTraitDefinition = {
	Id: MeteorTraitId,
	DisplayName: string,
	TrailColor: Color3,
	DropWeights: { [SpeciesId]: number },
}

export type UpgradeDefinition = {
	Id: string,
	DisplayName: string,
	Cost: number,
	Description: string,
}

export type Service = {
	Name: string,
	Init: (self: Service) -> (),
	Start: (self: Service) -> (),
}

export type Controller = {
	Name: string,
	Init: (self: Controller) -> (),
	Start: (self: Controller) -> (),
}

return nil

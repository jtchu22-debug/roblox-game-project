--!strict
--[[
	Module: Types
	Purpose: Central Luau type definitions shared across Server, Client, and Config modules.
	Connections: Required by Shared/Config, Server/Services, and Client/Controllers.
	How to Test in Studio: Play (F5) and verify zero Luau Script Analysis warnings in Output.
]]

export type SpeciesId = "StarSlime" | "CinderPup" | "FrostBeetle" | "NebulaFox" | "SolarGolem" | "CometOwl"
export type RarityId = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary"
export type VariantId = "Normal" | "Radiant"
export type MeteorTraitId = "Ember" | "Frost" | "Astral"
export type ItemState = "PodInBag" | "Incubating" | "HatchedInBag" | "InPen"
export type UpgradeId =
	"PenSlot_2"
	| "FrostCracker"
	| "Incubator_2"
	| "PenSlot_3"
	| "StarCracker"
	| "PenSlot_4"
	| "BagCap_20"
	| "PenSlot_5"
export type PlotAction =
	"StartIncubate"
	| "Hatch"
	| "PlaceInPen"
	| "RemoveFromPen"
	| "SellCritter"
	| "FeedCritter"
	| "UseFrostLure"
export type MeteorShapeStyle = "FlameCrest" | "IceSpikes" | "StarRing"
export type SlotCategory = "Pen" | "Incubator" | "Tool" | "Bag"
export type CrackerToolId = "StarterCracker" | "FrostCracker" | "AstralCracker"
export type StationZone = "Ranch" | "Hub"
export type NavigationTarget = "Hub" | "Ranch"
export type OnboardingFunnelStep = "Spawn" | "FirstMeteor" | "FirstHatch" | "FirstPen" | "FirstUpgrade" | "SecondRescue"
export type OnboardingFunnelCohort = "Fresh" | "Legacy"

export type CritterItemRecord = {
	UID: string,
	SpeciesId: SpeciesId,
	Variant: VariantId,
	State: ItemState,
	AssignedSlot: string?,
	PlantedAt: number?,
	MaturesAt: number?,
	CreatedAt: number,
	FeedLevel: number?,
}

export type PlayerProfileData = {
	SchemaVersion: number,
	StarterMeteorCompleted: boolean,
	Coins: number,
	PendingFraction: number,
	LastAccrualTimestamp: number,
	Revision: number,
	Items: { [string]: CritterItemRecord },
	Slots: { [string]: string },
	Upgrades: { [string]: boolean },
	DiscoveredSpecies: { [SpeciesId]: boolean },
	OnboardingFunnelCohort: OnboardingFunnelCohort,
	OnboardingFunnelAchieved: { [OnboardingFunnelStep]: boolean },
	OnboardingFunnelSubmitted: { [OnboardingFunnelStep]: boolean },
}

export type OwnerStateDTO = {
	Revision: number,
	Coins: number,
	BagCap: number,
	ReservedBagSlots: number,
	StarterMeteorCompleted: boolean,
	Items: { [string]: CritterItemRecord },
	Slots: { [string]: string },
	Upgrades: { [string]: boolean },
	DiscoveredSpecies: { [SpeciesId]: boolean },
}

export type PublicPenVisual = {
	SpeciesId: SpeciesId,
	Variant: VariantId,
	FeedLevel: number?,
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
	Rarity: RarityId,
	HatchSeconds: number,
	CoinsPerSecond: number,
	SellPrice: number,
	BodyColor: Color3,
	SecondaryColor: Color3,
	AccentColor: Color3,
	DisplayScale: Vector3,
	FieldClue: string,
	Description: string,
}

export type MeteorTraitDefinition = {
	Id: MeteorTraitId,
	DisplayName: string,
	TrailColor: Color3,
	RockColor: Color3,
	CoreColor: Color3,
	ShapeStyle: MeteorShapeStyle,
	IconText: string,
	RequiredUpgradeId: UpgradeId?,
	DropWeights: { [SpeciesId]: number },
}

export type UpgradeDefinition = {
	Id: UpgradeId,
	DisplayName: string,
	Order: number,
	Cost: number,
	UnlocksSlotId: string,
	SlotCategory: SlotCategory,
	StationZone: StationZone,
	PadOffsetX: number,
	PadOffsetZ: number,
	RequiresUpgradeId: UpgradeId?,
	Description: string,
}

export type CrackerToolDefinition = {
	Id: CrackerToolId,
	DisplayName: string,
	RequiredUpgradeId: UpgradeId?,
	WorkbenchZ: number,
	HandleColor: Color3,
	GripColor: Color3,
	BandColor: Color3,
	HeadColor: Color3,
	AccentColor: Color3,
	HandleMaterial: Enum.Material,
	BandMaterial: Enum.Material,
	HeadMaterial: Enum.Material,
	AccentMaterial: Enum.Material,
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

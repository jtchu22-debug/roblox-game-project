# Art Direction & Low-Poly Asset Pipeline

> **Last Updated:** November 15, 2026  
> **Author:** Gemini (Primary Art & Technical Planner)  
> **Reviewer:** ChatGPT (Independent Technical Director)  
> **Visual Pillar:** *"Toy-Box Cosmic Pastel"* — Chunky, high-saturation low-poly shapes with clean silhouettes, tactile materials, and unmistakable mutation shaders.

---

## 1. Visual Style & Color Palette

Younger Roblox players (ages 8–14) respond strongly to high-contrast, toy-like readability (similar to *Bee Swarm Simulator*, *Grow a Garden*, *Pet Simulator 99*, and *Slime Rancher*).

### Core Aesthetic Rules
1. **Chunky Proportions & Beveled Edges:** Avoid thin, sharp, realistic geometry. Every building, fence, crystal, and critter uses chunky proportions with soft `Bevel` edges so highlights catch the sun cleanly.
2. **Flat Vertex / Gradient Coloring Over Noisy Textures:** Do not use photorealistic image textures. Use solid Roblox materials (`SmoothPlastic`, `Neon`, `Glass`, `Metal`, `ForceField`) paired with clean vertex colors or simple color-palette UV unwraps. This keeps memory usage near zero and lets our **Mutation System** dynamically recolor any model in code!
3. **High-Readability Silhouette Rule:** A player standing 100 studs away must be able to tell the difference between a *Star-Slime*, a *Nebula Fox*, and a *Solar Golem* purely from its outer silhouette (ears, horns, floating rings) and size.

### Master Color Palette (`Color3.fromRGB`)
| Palette Role | Color Name | RGB Values | Hex | Where Used |
| :--- | :--- | :---: | :---: | :--- |
| **Environment Base** | Meadow Mint / Sky Grass | `(95, 215, 145)` | `#5FD791` | Floating island grass tops |
| **Environment Cliff** | Warm Lilac Stone | `(120, 105, 155)` | `#78699B` | Floating island rock undersides & Crater rim |
| **Plot Structure** | Clean Cream Wood / Trim | `(245, 235, 220)` | `#F5EBDC` | Ranch fences, gates, and Incubator frames |
| **Tech / Futuristic** | Orbital Cyan | `(65, 210, 255)` | `#41D2FF` | Supply Ship, Collector Drones, Upgrade Pads |
| **Currency / Gold** | Starlight Gold | `(255, 205, 45)` | `#FFCD2D` | Coins, Golden Mutation, Critical Crack Zone |
| **Epic / Cosmic** | Nebula Magenta | `(215, 75, 255)` | `#D74BFF` | Mythic Pods, Void/Nebula accents |

---

## 2. Asset Strategy: Roblox Parts First vs. Custom Blender Models Later

Because the developer is a beginner in Blender, we follow a strict **two-stage asset strategy** so art creation never blocks gameplay programming:

### Stage A: Assets Built Permanently (or Initially) with Native Roblox Parts & Unions
These assets look great using native Roblox Studio primitives (`Part`, `WedgePart`, `Cylinder`, `Sphere`, `CornerWedgePart`) and **never need Blender**:
1. **Ranch Plot Base & Fences:** Chunky `SmoothPlastic` blocks and cylinders with `Studs` or `SmoothPlastic` surfaces.
2. **Crystal Soil Beds & Incubator Pads:** Concentric cylinders with a glowing `Neon` inner ring.
3. **Tycoon Upgrade Buttons:** Classic beveled cylinder pads (Green = Buy, Blue = Drone Upgrade, Purple = Rebirth) with floating `BillboardGui` price labels.
4. **Phase 1 Placeholder Critters ("Cube Critters"):** A `3x3x3` rounded cube (`Block` + `SpecialMesh` bevel or 3 stacked parts) with two black sphere eyes and `WedgePart` ears. *(Note: Cube-style pets are an iconic, beloved aesthetic on Roblox, meaning Phase 1 placeholders already look charming!)*

### Stage B: Assets Upgraded to Custom Low-Poly Blender Meshes (Phase 5)
Once the gameplay loop is proven in Phases 1–4, we replace only the hero collectible models with lightweight `.fbx` meshes (< 400 triangles each):

| Asset Category | Count (MVP) | Triangle Budget | Why Blender Helps Here |
| :--- | :---: | :---: | :--- |
| **Wild Meteors & Geodes** | 4 tiers | `80 – 180 tris` | Procedural icosphere with flat-shaded crater indentations and glowing crystal veins poking out. |
| **Crystal Crops** | 6 species | `100 – 250 tris` | Tapered hexagonal crystal clusters angled outward from a central cluster base. |
| **Cosmic Critters** | 8 species | `200 – 450 tris` | Chibi-proportioned low-poly bodies with distinct ears, tails, wings, or floating crystal crowns. |
| **Collector Drone** | 2 tiers | `150 – 300 tris` | Cute spherical sci-fi bot with angled thruster wings. |

---

## 3. Blender Automation: Procedural Python (`bpy`) Generator Script

Instead of modeling every crystal cluster, meteor geode, and blocky critter by hand in Blender, we have included an automated **Blender Python script** at [`tools/blender/generate_lowpoly_assets.py`](../tools/blender/generate_lowpoly_assets.py).

### What the Python Script Automates for a Beginner
1. **Procedural Crystal Cluster Generator (`create_crystal_cluster`):** Automatically spawns 5–9 hexagonal prisms, tapers their tips into sharp crystal points, angles them outward organically, applies a clean `Bevel` modifier, and combines them into a single export-ready mesh.
2. **Procedural Meteor Geode Generator (`create_meteor_geode`):** Creates a low-poly subdivided icosphere, applies randomized rocky displacement, and embeds glowing crystal shards sticking out of its surface.
3. **Procedural Chibi Critter Base Generator (`create_blocky_critter`):** Generates a symmetrical, rounded-cube critter body with ears, feet, and a tail attachment point—giving a beginner a 90%-finished base mesh for all 8 Critter species in 1 click!
4. **Roblox-Correct Scale & Orientation Export:** Automatically sets scale and exports `.fbx` files with `apply_unit_scale=True` and `bake_space_transform=True` so models import into Roblox Studio at exact stud dimensions without being 100x too giant or sideways.

---

## 4. How Mutations Transform Any Asset Dynamically in Luau

To avoid making 8 separate 3D models in Blender for every single Critter (which would require $14 \times 8 = 112$ models!), we model **only 1 base mesh per species** (`14 models total`).

Our Luau helper (`MutationVisuals.luau`) transforms any base model into any Mutation combination at runtime:
1. **Size / Weight Scaling:** Calls `Model:ScaleTo(math.clamp((WeightKg / BaseWeightKg) ^ 0.6, 0.75, 8.0))` so heavier rolls are physically massive.
2. **Material & Color Overrides:**
   - *Wet:* Sets `Reflectance = 0.35`, attaches water droplet `ParticleEmitter`.
   - *Solar-Charged:* Turns accent parts into `Enum.Material.Neon` with `Color3.fromRGB(255, 140, 20)`.
   - *Frost-Crowned:* Clones a low-poly Ice Crown mesh onto the `HeadAttachment` and sets body material to translucent ice blue.
   - *Golden:* Sets all body parts to `Enum.Material.Metal`, `Color3.fromRGB(255, 205, 45)`, `Reflectance = 0.25`.
   - *Void-Touched:* Wraps primary parts in a dark purple `Highlight` / `ForceField` shell and attaches orbiting dark-matter ring particles.
   - *Prismatic:* Attaches a client-side tag (`CollectionService:AddTag(model, "PrismaticCycle")`) so a single centralized client loop smoothly cycles its hue across the rainbow every 3 seconds.

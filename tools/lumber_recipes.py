"""Builds AuctionCoach/Data/LumberRecipes.lua: every profession recipe that uses lumber,
from a game build's tables on wago.tools.

    python tools/lumber_recipes.py                 newest retail build
    python tools/lumber_recipes.py 12.1.5.70783    a given build

Run again on every patch. Lumber is Warbound, so it never has an AH price; everything
else a recipe needs, and the item it makes, is priced in game from Auction Coach's data.

Where each recipe comes from: a recipe item that teaches it (its item ID, so the addon can
name it and price it), or a trainer. A character who has the profession replaces this
with the game's own text when the profession window is opened.
"""
import csv
import io
import json
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "AuctionCoach" / "Data" / "LumberRecipes.lua"
UA = {"User-Agent": "Mozilla/5.0"}

CREATE_ITEM = "24"
CRAFT_ITEM = "288"  # crafting-data recipes: EffectMiscValue_0 is a CraftingData ID
LEARN_TRIGGER = "6"  # ItemEffect trigger: using the item teaches the spell
ACQUIRE_ON_SKILL = "1"  # SkillLineAbility: learned automatically with the profession
BASIC_SLOT = "1"  # ModifiedCraftingReagentSlot.ReagentType: a required material
LUMBER_KIND = ("7", "11", "2")  # Item: ClassID trade goods, SubclassID other, Material wood
# Same item type and also used by decor, but not lumber.
NOT_LUMBER = {20520}  # Dark Rune
EXPANSIONS = 12  # one lumber type each, Classic to Midnight


def get(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=600) as r:
        return r.read().decode("utf-8")


def table(name, build):
    print("reading", name, flush=True)
    return list(csv.DictReader(io.StringIO(get(f"https://wago.tools/db2/{name}/csv?build={build}"))))


def latest_build():
    builds = json.loads(get("https://wago.tools/api/builds"))
    return builds["wow"][0]["version"]


def lua_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main(build):
    skill_lines = {r["ID"]: r for r in table("SkillLine", build)}
    abilities = table("SkillLineAbility", build)
    spell_names = {r["ID"]: r["Name_lang"] for r in table("SpellName", build)}
    # Item names are read in game (ItemSparse is too big to download reliably); lumber is
    # told apart by its item type: trade goods, "other", made of wood.
    item_kind = {r["ID"]: (r["ClassID"], r["SubclassID"], r["Material"]) for r in table("Item", build)}
    reagents = {r["SpellID"]: r for r in table("SpellReagents", build)}

    # The item each recipe makes, and how many.
    crafting_data = {r["ID"]: r["CraftedItemID"] for r in table("CraftingData", build)}
    outputs = {}
    for r in table("SpellEffect", build):
        if r["Effect"] == CRAFT_ITEM and r["EffectMiscValue_0"] in crafting_data:
            item = crafting_data[r["EffectMiscValue_0"]]
            if item != "0":
                outputs.setdefault(r["SpellID"], (int(item), 1))
        elif r["Effect"] == CREATE_ITEM and r["EffectItemType"] not in ("0", ""):
            made = max(1, round(float(r["EffectBasePointsF"] or 1)))
            outputs.setdefault(r["SpellID"], (int(r["EffectItemType"]), made))

    # Materials that come in qualities sit in "modified" slots: slot -> categories -> items.
    slot_types = {r["ID"]: r["ReagentType"] for r in table("ModifiedCraftingReagentSlot", build)}
    slot_categories = {}
    for r in sorted(table("MCRSlotXMCRCategory", build), key=lambda r: int(r["_Order"])):
        slot_categories.setdefault(r["ModifiedCraftingReagentSlotID"], []).append(r["ModifiedCraftingCategoryID"])
    category_items = {}
    for r in sorted(table("CraftingReagentQuality", build), key=lambda r: int(r["OrderIndex"])):
        if r["ItemID"] != "0":
            category_items.setdefault(r["ModifiedCraftingCategoryID"], []).append(int(r["ItemID"]))
    reagent_item_category = {r["ID"]: r["ModifiedCraftingCategoryID"] for r in table("ModifiedCraftingReagentItem", build)}
    for r in table("ModifiedCraftingItem", build):
        category = reagent_item_category.get(r["ModifiedCraftingReagentItemID"])
        if category and int(r["ItemID"]) not in category_items.get(category, []):
            category_items.setdefault(category, []).append(int(r["ItemID"]))
    spell_slots = {}
    for r in sorted(table("ModifiedCraftingSpellSlot", build), key=lambda r: int(r["Slot"])):
        spell_slots.setdefault(r["SpellID"], []).append(r)

    # Recipe items: using the item teaches the spell.
    effect_spell = {r["ID"]: r["SpellID"] for r in table("ItemEffect", build) if r["TriggerType"] == LEARN_TRIGGER}
    taught_by = {}
    for r in table("ItemXItemEffect", build):
        spell = effect_spell.get(r["ItemEffectID"])
        if spell:
            taught_by.setdefault(spell, int(r["ItemID"]))

    def basic(spell):
        row = reagents.get(spell)
        found = []
        for i in range(8):
            item = row and row[f"Reagent_{i}"]
            if item and item != "0":
                found.append((int(item), int(row[f"ReagentCount_{i}"])))
        return found

    # Lumber: the wooden trade goods House Decor recipes use, in at least two professions
    # (one profession's own wooden material isn't lumber).
    decor_categories = {r["ID"] for r in table("TradeSkillCategory", build) if r["Name_lang"] == "House Decor"}
    used_by = {}
    for a in abilities:
        if a["TradeSkillCategoryID"] in decor_categories:
            for item, _ in basic(a["Spell"]):
                if item_kind.get(str(item)) == LUMBER_KIND:
                    used_by.setdefault(item, set()).add(a["SkillLine"])
    lumber = {item: "" for item, professions in used_by.items() if len(professions) >= 2 and item not in NOT_LUMBER}
    if not lumber:
        sys.exit("No lumber found: the table layout may have changed.")
    if len(lumber) != EXPANSIONS:
        print(f"Check: {len(lumber)} lumber types, expected {EXPANSIONS}: {sorted(lumber)}")

    recipes = []
    skipped = []
    for a in abilities:
        spell = a["Spell"]
        mats = basic(spell)
        wood = [(item, n) for item, n in mats if item in lumber]
        if not wood:
            continue
        name = spell_names.get(spell, "")
        if spell not in outputs:
            skipped.append(name or spell)
            continue
        tier = a["SkillupSkillLineID"] if a["SkillupSkillLineID"] not in ("0", "") else a["SkillLine"]
        parent = skill_lines.get(tier, {}).get("ParentSkillLineID", "0")
        profession = parent if parent not in ("0", "") else tier
        slots = [{"ids": [item], "n": n} for item, n in mats if item not in lumber]
        complete = True
        for slot in spell_slots.get(spell, []):
            if slot_types.get(slot["ModifiedCraftingReagentSlotID"]) != BASIC_SLOT:
                continue  # Sparks, finishing and optional materials aren't a craft's cost
            ids = []
            for category in slot_categories.get(slot["ModifiedCraftingReagentSlotID"], []):
                ids += [i for i in category_items.get(category, []) if i not in ids]
            if not ids:
                complete = False
                continue
            slots.append({"ids": ids, "n": int(slot["ReagentCount"])})
        item, made = outputs[spell]
        recipes.append({
            "spell": int(spell),
            "name": name,
            "profession": int(profession),
            "tier": int(tier),
            "output": item,
            "made": made,
            "lumber": wood,
            "slots": slots,
            "source": taught_by.get(spell, 0) or (-1 if a["AcquireMethod"] == ACQUIRE_ON_SKILL else 0),
            "complete": complete,
        })

    # Each lumber type belongs to one expansion: order them by the newest tier that uses them.
    def expansion(tier):
        # SkillLine.ParentTierIndex: Classic is 4, Midnight 15.
        return int(skill_lines.get(str(tier), {}).get("ParentTierIndex") or 0)

    lumber_order = sorted(lumber, key=lambda item: (min(
        (expansion(r["tier"]) for r in recipes if any(w == item for w, _ in r["lumber"])), default=0), item))
    tiers = sorted({r["tier"] for r in recipes})
    recipes.sort(key=lambda r: (r["profession"], r["tier"], r["name"]))

    lines = [
        "-- Auction Coach - every recipe that uses lumber. Built by tools/lumber_recipes.py",
        f"-- from game build {build}; don't edit by hand, run the script again on a patch.",
        "--",
        "--   lumber   { itemID, ... }  oldest expansion first",
        "--   tiers    { [skillLineID] = { name, expansion order } }  \"Midnight Jewelcrafting\", newest highest",
        "--   recipes  { [spellID] = { n name, p profession skill line, t expansion line,",
        "--              o item made, q how many, w = { { lumberID, n }, ... },",
        "--              r = { { ids = { itemID, ... }, n }, ... } other materials,",
        "--              s recipe item that teaches it, 0 trainer, -1 learned with the profession,",
        "--              x true when a material slot couldn't be read } }",
        "",
        "local _, ns = ...",
        "",
        "ns.LumberRecipes = {",
        f"    build = {lua_string(build)},",
        "    lumber = {",
    ]
    for item in lumber_order:
        lines.append(f"        {item},")
    lines.append("    },")
    lines.append("    tiers = {")
    for tier in tiers:
        name = lua_string(skill_lines.get(str(tier), {}).get("DisplayName_lang", ""))
        lines.append(f"        [{tier}] = {{ {name}, {expansion(tier)} }},")
    lines.append("    },")
    lines.append("    recipes = {")
    for r in recipes:
        wood = ", ".join(f"{{ {i}, {n} }}" for i, n in r["lumber"])
        slots = ", ".join("{ ids = { " + ", ".join(str(i) for i in s["ids"]) + f" }}, n = {s['n']} }}" for s in r["slots"])
        extra = "" if r["complete"] else ", x = true"
        lines.append(
            f"        [{r['spell']}] = {{ n = {lua_string(r['name'])}, p = {r['profession']}, t = {r['tier']}, "
            f"o = {r['output']}, q = {r['made']}, w = {{ {wood} }}, r = {{ {slots} }}, s = {r['source']}{extra} }},"
        )
    lines.append("    },")
    lines.append("}")
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print(f"{len(recipes)} recipes, {len(lumber)} lumber types, {len(tiers)} expansion lines -> {OUT}")
    if skipped:
        print("No output item, left out:", ", ".join(skipped[:20]))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else latest_build())

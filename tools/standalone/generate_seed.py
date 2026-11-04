#!/usr/bin/env python3
"""IronStack's built-in content for the standalone mode (docs/STANDALONE.md):
writes qml/data/seed.json, qml/data/exercise_images/ and
qml/data/ATTRIBUTION.md.

    python3 -I tools/standalone/generate_seed.py ../IronStack \\
        --server http://localhost:8000 --key-file /tmp/ironstack-dev/key

Which rows are built in comes from IronStack's own seed migrations and
seed_data (read as text with `ast`, never imported or run). Their content
comes from a server's API, in the API's own shape, so every later
migration that edits seeded rows (the em-dash clean-ups, instructions,
images) is already applied. A server's database can hold other rows
without an owner - test data, admin edits - which are left out unless
the migrations seed them.

Ids are kept stable across runs in tools/standalone/seed_ids.json (kind
and name -> id, all below 100000): a phone's history refers to them, so
a regenerated seed must never renumber a built-in.
"""

import argparse
import ast
import hashlib
import json
import os
import shutil
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA = os.path.join(ROOT, "qml", "data")
IDS_FILE = os.path.join(ROOT, "tools", "standalone", "seed_ids.json")
MAX_BUILTIN_ID = 99999
EM_DASH = "—"


def constants(path):
    """Top-level NAME = <literal> assignments of a migration, as values."""
    with open(path, encoding="utf-8") as f:
        tree = ast.parse(f.read())
    found = {}
    for node in tree.body:
        if isinstance(node, ast.Assign) and isinstance(node.targets[0], ast.Name):
            try:
                found[node.targets[0].id] = ast.literal_eval(node.value)
            except ValueError:
                pass
    return found


def clean(name):
    # The em-dash migrations rewrote seeded text to plain hyphens.
    return name.replace(EM_DASH, "-")


def builtin_names(ironstack):
    apps = os.path.join(ironstack, "apps")

    def migration(app, prefix):
        folder = os.path.join(apps, app, "migrations")
        match = [f for f in sorted(os.listdir(folder)) if f.startswith(prefix)]
        if len(match) != 1:
            sys.exit(f"Expected one {app} migration {prefix}*, found {match}")
        return constants(os.path.join(folder, match[0]))

    names = {key: [] for key in (
        "muscle_groups", "equipment", "exercises", "programs", "stretches", "stretch_routines",
        "measurement_types", "activity_types", "meal_slots", "foods", "recipes",
    )}
    for prefix in ("0002", "0004", "0005"):
        c = migration("exercises", prefix)
        names["muscle_groups"] += c.get("MUSCLE_GROUPS", [])
        names["equipment"] += c.get("EQUIPMENT", [])
        names["exercises"] += [row[0] for row in c.get("EXERCISES", [])]
    # 0002 seeds one program by a literal name, the later ones list theirs.
    with open(os.path.join(apps, "programs", "migrations",
                           [f for f in os.listdir(os.path.join(apps, "programs", "migrations"))
                            if f.startswith("0002")][0]), encoding="utf-8") as f:
        if '"Full Body A/B/C"' not in f.read():
            sys.exit("programs 0002 no longer seeds 'Full Body A/B/C' - update generate_seed.py")
    names["programs"].append("Full Body A/B/C")
    for prefix in ("0004", "0006"):
        names["programs"] += [row[0] for row in migration("programs", prefix).get("TEMPLATES", [])]
    with open(os.path.join(apps, "stretching", "seed_data", "stretches.json"), encoding="utf-8") as f:
        stretching = json.load(f)
    names["stretches"] = [s["name"] for s in stretching["stretches"]]
    names["stretch_routines"] = [r["name"] for r in stretching["routines"]]
    names["measurement_types"] = [row[0] for row in migration("measurements", "0002")["MEASUREMENT_TYPES"]]
    names["activity_types"] = [row if isinstance(row, str) else row[0]
                               for row in migration("activities", "0002")["ACTIVITY_TYPES"]]
    names["meal_slots"] = [row[0] for row in migration("nutrition", "0013")["MEAL_SLOT_ORDER"]]
    recipes = migration("nutrition", "0008")
    # Template foods are matched by their Open Food Facts barcode.
    names["foods"] = [row[0] for row in recipes["INGREDIENTS"].values()]
    names["recipes"] = [row[0] for row in recipes["RECIPES"]]
    return {kind: [clean(n) for n in values] for kind, values in names.items()}


ENDPOINTS = {
    "muscle_groups": "muscle-groups/",
    "equipment": "equipment/",
    "exercises": "exercises/?page_size=500",
    "programs": "programs/?page_size=500",
    "stretches": "stretches/?page_size=500",
    "stretch_routines": "stretch-routines/?page_size=500",
    "measurement_types": "measurement-types/?page_size=500",
    "activity_types": "activity-types/?page_size=500",
    "meal_slots": "meal-slots/?page_size=500",
    "foods": "foods/?page_size=500",
    "recipes": "recipes/?page_size=500",
}


def fetch(server, key, path):
    rows = []
    url = f"{server}/api/v1/{path}"
    while url:
        request = urllib.request.Request(url, headers={
            "Authorization": f"Bearer {key}", "Accept": "application/json", "Accept-Language": "en"})
        with urllib.request.urlopen(request) as response:
            data = json.load(response)
        if isinstance(data, list):
            return data
        rows += data["results"]
        url = data.get("next")
    return rows


def strip_display(value):
    """Drops the display_* twins: the app translates built-in names itself
    (Store.shown with content.js) when they're missing."""
    if isinstance(value, dict):
        return {k: strip_display(v) for k, v in value.items()
                if not k.startswith("display_") and not k.endswith("_display_name") and k != "estimate"}
    if isinstance(value, list):
        return [strip_display(v) for v in value]
    return value


class Ids:
    """Stable ids per kind and name, kept in seed_ids.json."""

    def __init__(self):
        self.ids = {}
        if os.path.exists(IDS_FILE):
            with open(IDS_FILE, encoding="utf-8") as f:
                self.ids = json.load(f)

    def get(self, kind, name, preferred=None):
        table = self.ids.setdefault(kind, {})
        if name not in table:
            used = set(table.values())
            candidate = preferred if preferred and preferred not in used and preferred <= MAX_BUILTIN_ID else None
            if candidate is None:
                candidate = max(used, default=0) + 1
            if candidate > MAX_BUILTIN_ID:
                sys.exit(f"Out of built-in ids for {kind}")
            table[name] = candidate
        return table[name]

    def save(self):
        with open(IDS_FILE, "w", encoding="utf-8") as f:
            json.dump(self.ids, f, indent=1, sort_keys=True, ensure_ascii=False)
            f.write("\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("ironstack")
    parser.add_argument("--server", required=True)
    parser.add_argument("--key-file", required=True)
    args = parser.parse_args()
    with open(args.key_file, encoding="utf-8") as f:
        key = f.read().strip()

    names = builtin_names(args.ironstack)
    ids = Ids()
    rows = {}
    server_ids = {}  # kind -> server id -> seed id
    missing = []
    for kind, path in ENDPOINTS.items():
        fetched = [r for r in fetch(args.server, key, path) if r.get("owner", None) is None]
        if kind == "programs":
            fetched = [r for r in fetched if r.get("is_system_template")]
        by_name = {}
        for row in fetched:
            match_key = row.get("off_id") if kind == "foods" else row["name"]
            by_name.setdefault(match_key, row)
        chosen = []
        for name in names[kind]:
            row = by_name.get(name)
            if row is None:
                missing.append(f"{kind}: {name}")
                continue
            seed_id = ids.get(kind, name, row["id"])
            server_ids.setdefault(kind, {})[row["id"]] = seed_id
            chosen.append(row)
        rows[kind] = chosen
    if missing:
        sys.exit("Not on the server (an older IronStack?):\n  " + "\n  ".join(missing))

    def ref(kind, server_id):
        if server_id is None:
            return None
        return server_ids[kind][server_id]

    images_dir = os.path.join(DATA, "exercise_images")
    shutil.rmtree(images_dir, ignore_errors=True)
    os.makedirs(images_dir)
    attributions = []
    seed = {}
    for kind, chosen in rows.items():
        out = []
        for row in chosen:
            row = strip_display(row)
            name = row.get("off_id") if kind == "foods" else row["name"]
            row["id"] = ids.get(kind, name)
            row["builtin_key"] = row["name"]
            if kind == "exercises":
                row["equipment"] = ref("equipment", row["equipment"])
                row["primary_muscle_groups"] = [ref("muscle_groups", m) for m in row["primary_muscle_groups"]]
                row["secondary_muscle_groups"] = [ref("muscle_groups", m) for m in row["secondary_muscle_groups"]]
                images = []
                for image in row["images"]:
                    filename = f"{row['id']}-{os.path.basename(image['image'])}"
                    with urllib.request.urlopen(image["image"]) as response, \
                            open(os.path.join(images_dir, filename), "wb") as f:
                        shutil.copyfileobj(response, f)
                    image_id = ids.get("exercise_images", filename, image["id"])
                    images.append({**image, "id": image_id, "image": "exercise_images/" + filename})
                    attributions.append(f"- {row['name']}: image {image['attribution']}")
                row["images"] = images
                if row.get("instructions_attribution"):
                    attributions.append(f"- {row['name']}: instructions {row['instructions_attribution']}")
            elif kind == "programs":
                for workout in row["workouts"]:
                    workout_id = ids.get("workouts", f"{row['name']}/{workout['name']}", workout["id"])
                    for prescription in workout["prescriptions"]:
                        prescription["id"] = ids.get(
                            "prescriptions", f"{row['name']}/{workout['name']}/{prescription['order']}",
                            prescription["id"])
                        prescription["workout"] = workout_id
                        prescription["exercise"] = ref("exercises", prescription["exercise"])
                    workout["id"] = workout_id
                    workout["program"] = row["id"]
            elif kind == "stretches":
                row["muscle_groups"] = [ref("muscle_groups", m) for m in row["muscle_groups"]]
            elif kind == "stretch_routines":
                for item in row["items"]:
                    item["id"] = ids.get("stretch_routine_items", f"{row['name']}/{item['order']}", item["id"])
                    item["routine"] = row["id"]
                    item["stretch"] = ref("stretches", item["stretch"])
            elif kind == "recipes":
                for ingredient in row["ingredients"]:
                    ingredient["id"] = ids.get("recipe_ingredients", f"{row['name']}/{ingredient['order']}",
                                               ingredient["id"])
                    ingredient["recipe"] = row["id"]
                    ingredient["food"] = ref("foods", ingredient["food"])
            out.append(row)
        seed[kind] = sorted(out, key=lambda r: r["id"])

    content = json.dumps(seed, sort_keys=True, ensure_ascii=False)
    seed["version"] = hashlib.sha256(content.encode("utf-8")).hexdigest()[:12]
    with open(os.path.join(DATA, "seed.json"), "w", encoding="utf-8") as f:
        json.dump(seed, f, indent=1, sort_keys=True, ensure_ascii=False)
        f.write("\n")
    with open(os.path.join(DATA, "ATTRIBUTION.md"), "w", encoding="utf-8") as f:
        f.write("# Built-in content\n\n"
                "The built-in exercises, programs, stretches, foods and recipes are IronStack's\n"
                "(https://github.com/JonneSaloranta/ironstack, AGPL-3.0), generated by\n"
                "tools/standalone/generate_seed.py. The exercise images and instructions\n"
                "are from wger.de under Creative Commons Attribution-ShareAlike, by:\n\n")
        f.write("\n".join(sorted(set(attributions))) + "\n")
    ids.save()
    print(f"seed {seed['version']}: " + ", ".join(f"{len(v)} {k}" for k, v in seed.items() if k != "version"))


if __name__ == "__main__":
    main()

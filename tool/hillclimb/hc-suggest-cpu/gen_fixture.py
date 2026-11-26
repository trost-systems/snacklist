#!/usr/bin/env python3
"""Writes the frozen hc-suggest-cpu workload (seed 131) to app/test/list/suggest_fixture/.

catalog.txt: 5,000 usuals/history names, in the server's order (one per line).
on_list.txt: 60 of them that are active on the list (left out of suggestions).
queries.txt: 40 typed texts (short prefixes, umlauts, multi-word, typos, misses).
Rerunning it reproduces the committed files byte for byte.
"""
import pathlib
import random

SEED = 131
rng = random.Random(SEED)

nouns = """Milch Hafermilch Sojamilch Butter Käse Joghurt Quark Sahne Schmand Frischkäse
Mozzarella Gouda Feta Parmesan Ei Eier Brot Brötchen Toast Vollkornbrot Baguette Croissant
Mehl Zucker Salz Pfeffer Reis Nudeln Spaghetti Penne Linsen Kichererbsen Bohnen Haferflocken
Müsli Cornflakes Honig Marmelade Nutella Erdnussbutter Kaffee Tee Kakao Saft Orangensaft
Apfelsaft Wasser Mineralwasser Limo Bier Wein Sekt Tomate Tomaten Gurke Paprika Zwiebel
Knoblauch Kartoffeln Möhren Karotten Brokkoli Blumenkohl Zucchini Aubergine Spinat Salat
Rucola Feldsalat Lauch Sellerie Kürbis Pilze Champignons Äpfel Birnen Bananen Orangen
Zitronen Limetten Trauben Erdbeeren Himbeeren Heidelbeeren Kiwi Mango Ananas Avocado
Hähnchen Hackfleisch Schnitzel Würstchen Salami Schinken Speck Lachs Thunfisch Garnelen
Tofu Hummus Pesto Ketchup Senf Mayonnaise Essig Öl Olivenöl Sonnenblumenöl Brühe
Tomatensoße Pizza Lasagne Chips Schokolade Kekse Gummibärchen Eis Popcorn Nüsse Mandeln
Rosinen Windeln Feuchttücher Klopapier Küchenrolle Taschentücher Spülmittel Waschmittel
Weichspüler Müllbeutel Alufolie Frischhaltefolie Backpapier Zahnpasta Zahnbürste Shampoo
Duschgel Seife Deo Rasierer Sonnencreme Pflaster Batterien Kerzen Streichhölzer Hefe
Backpulver Vanillezucker Puderzucker Rote Bete Grüne Bohnen Weiße Bohnen Schwarzer Tee
Grüner Tee Joghurtdrink Milchreis Grießbrei Pudding Rührei Spätzle Maultaschen Knödel
Sauerkraut Rotkohl Weißkohl Kohlrabi Radieschen Ingwer Petersilie Schnittlauch Basilikum
Dill Koriander Minze Oregano Thymian Rosmarin Zimt Muskat Curry Paprikapulver Chili""".split("\n")
nouns = [w for line in nouns for w in line.split(" ")]
# Two-word nouns above got split; rejoin the known ones.
multi = ["Rote Bete", "Grüne Bohnen", "Weiße Bohnen", "Schwarzer Tee", "Grüner Tee"]
for m in multi:
    a, b = m.split(" ")
    nouns = [n for n in nouns if n not in (a, b)] + [m]
nouns = sorted(set(nouns))

prefixes = ["Bio", "Vollkorn", "Frische", "Laktosefreie", "Fettarme", "Tiefkühl", "Mini",
            "Groß", "Rote", "Grüne", "Gelbe", "Süße", "Scharfe", "Geräucherte", "Gesalzene",
            "Ungesalzene", "Vegane", "Glutenfreie", "Regionale", "Französische", "Italienische",
            "Griechische", "Würzige", "Milde", "Kalte", "Heiße", "Dunkle", "Helle", "Zarte", "Feine"]
brands = ["Weihenstephan", "Alnatura", "Barilla", "Dr. Oetker", "Müller", "Zott", "Kerrygold",
          "Bärenmarke", "Rügenwalder", "Iglo", "Knorr", "Maggi", "Haribo", "Milka", "Ritter Sport",
          "Lindt", "Tchibo", "Jacobs", "Teekanne", "Pampers", "Tempo", "Nivea", "Balea", "Frosch",
          "Persil", "Lenor", "Ja!", "Gut & Günstig", "K-Classic", "dmBio", "Rewe Bio", "Edeka",
          "Andechser", "Berchtesgadener", "Schwarzwaldmilch", "Landliebe", "Ehrmann", "Danone"]
suffixes = ["Big Pack", "4er Pack", "6er Pack", "1 kg", "500 g", "250 g", "1,5 l", "0,5 l",
            "Größe 3", "Größe 4", "Größe 5", "laktosefrei", "light", "extra", "natur", "classic",
            "Nachfüllpack", "Familienpackung", "XXL", "mild", "scharf", "geräuchert"]
seps = [" ", "-"]

names = set()
names.update(nouns)
while len(names) < 5000:
    noun = rng.choice(nouns)
    shape = rng.random()
    if shape < 0.30:
        name = f"{rng.choice(prefixes)}{rng.choice(seps)}{noun}"
    elif shape < 0.55:
        name = f"{noun} {rng.choice(brands)}"
    elif shape < 0.75:
        name = f"{noun} {rng.choice(suffixes)}"
    elif shape < 0.88:
        name = f"{rng.choice(prefixes)} {noun} {rng.choice(suffixes)}"
    else:
        other = rng.choice(nouns).lower()
        name = f"{noun}{other}" if " " not in noun + other else f"{noun} {other}"
    if rng.random() < 0.05:
        name = name.lower()
    if rng.random() < 0.03:
        name = f"  {name} "
    names.add(name)

catalog = sorted(names)
rng.shuffle(catalog)
on_list = rng.sample(catalog, 60)

queries = [
    "m", "k", "b", "ä", "mi", "kä", "br", "sc", "ö",
    "mil", "käs", "bröt", "müs", "äpf", "kür", "öl", "süß", "weiß", "grüne",
    "milch", "Käse", "Brötchen", "Hafermilch", "Tomate", "Joghurt", "spülmittel",
    "rote bete", "bio milch", "Frische Eier", "Windeln Größe 4", "milch weihenstephan",
    "mlch", "jogurt", "tomatn", "bannane", "brokoli", "Spagetti", "zuccini",
    "xyzq", "  MILCH  ",
]
assert len(queries) == 40

out = pathlib.Path(__file__).resolve().parents[3] / "app/test/list/suggest_fixture"
out.mkdir(parents=True, exist_ok=True)
(out / "catalog.txt").write_text("\n".join(catalog) + "\n", encoding="utf-8")
(out / "on_list.txt").write_text("\n".join(on_list) + "\n", encoding="utf-8")
(out / "queries.txt").write_text("\n".join(queries) + "\n", encoding="utf-8")
print(len(catalog), len(on_list), len(queries))

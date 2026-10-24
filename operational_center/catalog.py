"""Catalog references and ranked Unicode search; catalogs never own events."""
from __future__ import annotations

import re
import unicodedata

from .domain import uid


def normalize(value):
    text = unicodedata.normalize("NFKC", str(value).replace("№", " ")).casefold().replace("ё", "е")
    text = re.sub(r"\b(?:км|km)\s*[-№:#]?\s*0*(\d+)\b", r"км \1", text)
    return " ".join(text.split())


def new_catalog():
    return {"id": uid(), "type": "master_catalog", "name": "Новый каталог", "icon": "К",
            "color": "#8AB4FF", "opening": "compact", "members": []}


def search(config, catalog_id, query="", category="", mode="all", favorites=(), recent=()):
    catalog = next(c for c in config.get("catalogs", []) if c["id"] == catalog_id) if catalog_id else {"members": [m["id"] for m in config["masters"]]}
    members = set(catalog["members"])
    q = normalize(query)
    words = re.findall(r"\w+", q)
    wanted_numbers = set(re.findall(r"\d+", q))
    km = re.findall(r"\bкм (\d+)\b", q)
    ranked = []
    for master in config["masters"]:
        identity = master["id"]
        if identity not in members or (category and normalize(master.get("category", "")) != normalize(category)):
            continue
        if mode == "favorites" and identity not in favorites or mode == "recent" and identity not in recent:
            continue
        texts = [master["name"], master["tag"], master.get("km_code", ""),
                 *master.get("aliases", []), *master.get("tags", []), master.get("category", "")]
        texts = [normalize(t) for t in texts if t]
        combined = " ".join(texts)
        # Numeric tokens must match whole numbers: KM 1 must never match KM 10/11.
        if wanted_numbers and not wanted_numbers <= set(re.findall(r"\d+", combined)):
            continue
        if km and not set(km) <= set(re.findall(r"\bкм (\d+)\b", combined)):
            continue
        if q and not all(word in combined for word in words):
            continue
        exact = bool(q and q in texts)
        prefix = bool(q and any(t.startswith(q) for t in texts))
        rank = (0 if exact else 1 if prefix else 2) if q else 0
        recent_index = list(recent).index(identity) if identity in recent else len(recent) + 1
        row = {"id": identity, "name": master["name"], "tag": master["tag"],
               "km_code": master.get("km_code", ""), "category": master.get("category", ""),
               "favorite": identity in favorites, "recent": identity in recent, "exact": exact}
        ranked.append(((rank, identity not in favorites, recent_index, normalize(master["name"]), identity), row))
    return [row for _, row in sorted(ranked, key=lambda item: item[0])]

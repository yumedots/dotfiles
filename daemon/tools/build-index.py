#!/usr/bin/env python3
import gzip
import html
import json
import os
import re
import struct
import sys
import tarfile
import urllib.request

LANGS = "en,de,es,pt,ja,zh,fr,it,ko,ru,nl,pl,tr,id,vi,uk,hi,th,ar".split(",")
KAO_LANGS = "en,de,es,pt,ja,zh".split(",")
CLDR_TAG = "release-49"
EMOJI_TEST = "https://unicode.org/Public/emoji/16.0/emoji-test.txt"
KAOJI = "https://registry.npmjs.org/kaomoji-dataset/-/kaomoji-dataset-1.0.6.tgz"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, "cache", "launcher-index-src")
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "assets", "launcher-index.bin.gz")
FORCE = "--force" in sys.argv[2:]
ANNOTATION = re.compile(r'^<annotation cp="([^"]*)"( type="tts")?>(.*?)</annotation>$')


def fetch(url, path):
    if os.path.exists(path):
        return path
    os.makedirs(os.path.dirname(path), exist_ok=True)
    request = urllib.request.Request(url, headers={"User-Agent": "yudaemond-index"})
    with urllib.request.urlopen(request, timeout=120) as response:
        body = response.read()
    tmp = path + ".tmp"
    with open(tmp, "wb") as file:
        file.write(body)
    os.replace(tmp, path)
    return path


def load_language(language):
    path = fetch(
        f"https://raw.githubusercontent.com/unicode-org/cldr/{CLDR_TAG}/common/annotations/{language}.xml",
        os.path.join(CACHE, "cldr", CLDR_TAG, language + ".xml"),
    )
    annotations = {}
    with open(path, encoding="utf-8") as file:
        for line in file:
            match = ANNOTATION.match(line.strip())
            if not match:
                continue
            cp, tts, text = match.groups()
            text = html.unescape(text)
            entry = annotations.setdefault(cp, {"name": "", "keywords": []})
            if tts:
                entry["name"] = text
            else:
                entry["keywords"] = [word for word in text.split(" | ") if word]
    return annotations


def load_kaomoji():
    archive = fetch(KAOJI, os.path.join(CACHE, "kaomoji-dataset-1.0.6.tgz"))
    path = os.path.join(CACHE, "kaomoji-dataset-1.0.6.jsonl.gz")
    if not os.path.exists(path):
        with tarfile.open(archive, "r:gz") as tar:
            source = tar.extractfile("package/data/kaomoji.jsonl.gz")
            if source is None:
                raise RuntimeError("kaomoji dataset archive is missing its jsonl")
            with open(path + ".tmp", "wb") as target:
                target.write(source.read())
        os.replace(path + ".tmp", path)
    return path


def string_ref(pool, offsets, text):
    if text in offsets:
        return offsets[text]
    start = len(pool)
    raw = text.encode("utf-8")
    pool.extend(raw)
    offsets[text] = (start, len(raw))
    return offsets[text]


def build():
    annotations = {language: load_language(language) for language in LANGS}
    skin = set(range(0x1F3FB, 0x1F400))
    seen = set()
    entries = []

    emoji_test = fetch(EMOJI_TEST, os.path.join(CACHE, "emoji-test-16.0.txt"))
    with open(emoji_test, encoding="utf-8") as file:
        for line in file:
            line = line.split("#")[0].strip()
            if "; fully-qualified" not in line:
                continue
            cps = [int(code, 16) for code in line.split(";")[0].split()]
            if any(cp in skin for cp in cps):
                continue
            key = "".join(chr(cp) for cp in cps if cp != 0xFE0F)
            if key in seen:
                continue
            seen.add(key)
            text = "".join(chr(cp) for cp in cps)
            english = annotations["en"].get(key) or annotations["en"].get(text)
            if not english or not english["name"]:
                continue
            keywords = set()
            for language in LANGS:
                annotation = annotations[language].get(key) or annotations[language].get(text)
                if not annotation:
                    continue
                keywords.update(annotation["keywords"])
                if annotation["name"]:
                    keywords.add(annotation["name"])
            entries.append((0, text, english["name"][0].upper() + english["name"][1:], keywords))

    kaomoji = {}
    with gzip.open(load_kaomoji(), "rt", encoding="utf-8") as file:
        for line in file:
            row = json.loads(line)
            if row.get("tier") != "core":
                continue
            text = row["text"].replace("\n", " ").replace("\t", " ")
            if not text:
                continue
            name = row.get("names", {}).get("en", "").replace("\n", " ").replace("\t", " ")
            keywords = set()
            for language in KAO_LANGS:
                keywords.update(row.get("keywords", {}).get(language, []))
                localized = row.get("names", {}).get(language, "")
                if localized:
                    keywords.add(localized)
            if text in kaomoji:
                old_kind, old_text, old_name, old_keywords = kaomoji[text]
                old_keywords.update(keywords)
                kaomoji[text] = (old_kind, old_text, old_name or name, old_keywords)
            else:
                kaomoji[text] = (1, text, name, keywords)

    entries.extend(kaomoji.values())

    pool = bytearray()
    offsets = {}
    keyword_set = set()
    for kind, text, name, keywords in entries:
        for keyword in keywords:
            keyword = keyword.strip().lower()
            if keyword:
                keyword_set.add(keyword)
    keyword_list = sorted(keyword_set)
    keyword_ids = {keyword: index for index, keyword in enumerate(keyword_list)}

    keyword_refs = [string_ref(pool, offsets, keyword) for keyword in keyword_list]
    ids = []
    records = []
    for kind, text, name, keywords in entries:
        text_ref = string_ref(pool, offsets, text)
        name_ref = string_ref(pool, offsets, name)
        lower_ref = string_ref(pool, offsets, name.lower())
        keyword_ids_for_entry = sorted({keyword_ids[keyword.strip().lower()] for keyword in keywords if keyword.strip()})
        start = len(ids)
        ids.extend(keyword_ids_for_entry)
        records.append((kind, text_ref, name_ref, lower_ref, start, len(keyword_ids_for_entry)))

    id_size = 2 if len(keyword_list) <= 65535 else 4
    body = bytearray()
    body += b"YIDX"
    body += struct.pack("<IIIIII", 1, len(records), len(keyword_list), len(ids), id_size, len(pool))
    body += pool
    for offset, length in keyword_refs:
        body += struct.pack("<II", offset, length)
    for keyword_id in ids:
        body += struct.pack("<H" if id_size == 2 else "<I", keyword_id)
    for kind, text_ref, name_ref, lower_ref, start, count in records:
        body += struct.pack(
            "<BIIIIIIIHH",
            kind,
            text_ref[0],
            text_ref[1],
            name_ref[0],
            name_ref[1],
            lower_ref[0],
            lower_ref[1],
            start,
            count,
            0,
        )

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    tmp = OUT + ".tmp"
    with open(tmp, "wb") as file:
        file.write(gzip.compress(bytes(body), compresslevel=9, mtime=0))
    os.replace(tmp, OUT)
    print(
        f"launcher index: {len(records)} entries, {len(keyword_list)} keywords, "
        f"{os.path.getsize(OUT)} bytes"
    )


if os.path.exists(OUT) and not FORCE:
    sys.exit(0)

build()

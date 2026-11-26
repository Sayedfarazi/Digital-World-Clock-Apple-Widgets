#!/usr/bin/env python3
"""Regenerate Shared/Resources/cities.json from macOS's built-in world-clock city database.

Apple's Clock app (and its World Clock widget) draw their city list from
  /System/Library/PrivateFrameworks/AppSupport.framework/Resources/CityInfo.db        (cities, time zones)
  /System/Library/PrivateFrameworks/AppSupport.framework/Resources/Localizable_Cities.loctable (city names)
  /System/Library/PrivateFrameworks/MobileTimer.framework/Resources/WorldClock.loctable       (3-letter abbreviations)

We snapshot that data into a JSON resource so the build never depends on private
system files at runtime. CORRECTIONS below fixes the few records that are wrong in Apple's data, keeping their IDs.
Re-run only if you want to refresh the list from a newer macOS:

    python3 Shared/scripts/gen_cities.py            # writes Shared/Resources/cities.json
"""
import json
import os
import plistlib
import sqlite3
import sys

APPSUPPORT = "/System/Library/PrivateFrameworks/AppSupport.framework/Versions/A/Resources"
MOBILETIMER = "/System/Library/PrivateFrameworks/MobileTimer.framework/Versions/A/Resources"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Resources", "cities.json")


# Apple's records that are wrong, by Apple's ID (which stays). Each says why. main() stops if a correction no longer
# changes anything (Apple fixed the record: remove it) or names a zone this Mac doesn't know.
CORRECTIONS = {
    # Rio Branco, Brazil. Apple's record has America/La_Paz (UTC-4), but Acre has been on UTC-5 since
    # 10 November 2013 (America/Rio_Branco): the clock was an hour fast and could show the wrong day. Its
    # coordinates are right (zone.tab: -0958-06748).
    "334": {"tz": "America/Rio_Branco"},
    # Santa Isabel, Mexico. Apple's zone table makes it the city of America/Santa_Isabel (Baja California; now
    # another name of America/Tijuana), and the Clock app shows it on that time. But its coordinates are those of
    # Santa Isabel, Chihuahua, 870 km east, so its day and night face followed a different place than its time.
    # The zone's reference point in the tz database's zone.tab (+3018-11452) puts it back in Baja California.
    "349": {"lat": 30.3, "lon": -114.8667},
}


def apply_corrections(cities):
    by_id = {city["id"]: city for city in cities}
    for ident, fix in CORRECTIONS.items():
        city = by_id.get(ident)
        if city is None:
            sys.exit(f"gen_cities.py: CORRECTIONS names city {ident}, which Apple's database no longer has")
        if all(city[key] == value for key, value in fix.items()):
            sys.exit(f"gen_cities.py: Apple's record {ident} ({city['name']}) already has {fix}: remove the correction")
        if "tz" in fix and not os.path.exists(os.path.join("/usr/share/zoneinfo", fix["tz"])):
            sys.exit(f"gen_cities.py: the correction for {ident} names an unknown time zone, {fix['tz']}")
        city.update(fix)


def load_loctable(path, lang="en"):
    with open(path, "rb") as f:
        table = plistlib.load(f)
    return table.get(lang, {})


def main():
    db = sqlite3.connect(f"file:{APPSUPPORT}/CityInfo.db?mode=ro", uri=True)
    names = load_loctable(f"{APPSUPPORT}/Localizable_Cities.loctable")
    abbrs = load_loctable(f"{MOBILETIMER}/WorldClock.loctable")

    countries = {code: name for code, name in db.execute("select code, country_name from locales")}

    cities = []
    for ident, override, lat, lon, name, tz, locale in db.execute(
        "select identifier, country_override, latitude, longitude, name, timezonename, locale_code from cities order by identifier"
    ):
        key = str(ident)
        display = names.get(key, name)
        abbr = abbrs.get(key) or display[:3].upper()
        country = (override or "").strip() or countries.get(locale or "", "")
        cities.append({
            "id": key,
            "name": display,
            "abbr": abbr,
            "tz": tz,
            "country": country,
            "lat": round(lat or 0.0, 4),
            "lon": round(lon or 0.0, 4),
        })

    apply_corrections(cities)

    # time zone identifier -> representative city id (used to find "your" city from the system time zone)
    tz_to_city = {}
    for tz, locale, city_id in db.execute("select timezonename, locale_code, city_id from timezone_locale_to_city_map"):
        if not locale:  # locale-independent default mapping
            tz_to_city.setdefault(tz, str(city_id))

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump({
            "version": 1,
            "source": "macOS AppSupport CityInfo.db + MobileTimer WorldClock.loctable, with CORRECTIONS from Shared/scripts/gen_cities.py",
            "cities": cities,
            "tzToCity": dict(sorted(tz_to_city.items())),
        }, f, ensure_ascii=False, indent=1, sort_keys=False)
        f.write("\n")
    print(f"wrote {len(cities)} cities and {len(tz_to_city)} time-zone mappings to {os.path.relpath(OUT, ROOT)}")


if __name__ == "__main__":
    sys.exit(main())

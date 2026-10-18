"""Rebuild the reviewed offline subset, preserving City IDs and provenance.

python3 tools/toronto/import_waste_wizard.py --data /path/to/download.json \
    --metadata /path/to/package_show.json
No network calls; inspect new source data and review curation.json before importing.
"""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def build(data_path, metadata_path):
    raw = data_path.read_bytes()
    rows = json.loads(raw)
    metadata = json.loads(metadata_path.read_text())["result"]
    resource = next(r for r in metadata["resources"] if r["id"] == "274fde37-233c-485d-bc68-8177f0793412")
    curation = json.loads((ROOT / "tools/toronto/curation.json").read_text())
    if hashlib.sha256(raw).hexdigest() != curation["expected_source_sha256"]:
        raise ValueError("Source bytes changed. Review the new resource and update curation before importing.")
    if len(rows) != curation["expected_source_records"]:
        raise ValueError("Unexpected source record count")
    by_id = {row["id"]: row for row in rows}
    assert len(by_id) == len(rows), "Duplicate source IDs"
    items = []
    for curated in curation["items"]:
        source = by_id[curated["id"]]
        if source["category"] != curated.pop("expected_category"):
            raise ValueError(f"Category changed: {source['id']}. Review before publishing.")
        items.append({**curated, "source_item": source["item"],
                      "source_category": source["category"],
                      "source_instructions": source["instructions"]})
    output = {
        "version": 1, "reviewed_at": curation["reviewed_at"],
        "provenance": {
            "title": metadata["title"], "publisher": "City of Toronto",
            "catalogue_url": "https://open.toronto.ca/dataset/waste-wizard-lookup-table/",
            "resource_id": resource["id"], "resource_url": resource["url"],
            "resource_modified": resource["last_modified"],
            "source_sha256": hashlib.sha256(raw).hexdigest(), "source_records": len(rows),
            "license": metadata["license_title"],
        }, "sources": curation["sources"], "stats": curation["stats"], "items": items,
    }
    target = ROOT / "app/assets/data/toronto_waste.json"
    target.write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n")
    # Keep only the exact source rows used by this subset for offline auditing/rebuilds.
    (ROOT / "testdata/toronto/waste_wizard_subset.json").write_text(
        json.dumps([by_id[i["id"]] for i in items], ensure_ascii=False, indent=2) + "\n")
    print(f"Imported {len(items)} reviewed items from {len(rows)} City records into {target}")


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--data", type=Path, required=True)
    p.add_argument("--metadata", type=Path, required=True)
    a = p.parse_args()
    build(a.data, a.metadata)

import argparse
import json
import re
import sqlite3
import xml.etree.ElementTree as ET
from pathlib import Path
from uuid import UUID


def check_identity_map(root):
    # Refuse the plugin's username-based recovery if an established map is lost.
    db = root / "data/jellyfin.db"
    mapping = root / "plugins/configurations/Jellyfin.Plugin.OIDC.UserProviderMap.json"
    with sqlite3.connect(db.as_uri() + "?mode=ro", uri=True) as connection:
        provider = "Jellyfin.Plugin.OIDC.Auth.OidcAuthProvider"
        if connection.execute(
            "SELECT 1 FROM Users WHERE AuthenticationProviderId IS NOT ? LIMIT 1",
            (provider,),
        ).fetchone():
            raise SystemExit(
                "Local authentication account found; explicitly bind it before starting Jellyfin"
            )
        users = connection.execute("SELECT Id FROM Users").fetchall()
    entries = json.loads(mapping.read_text()) if mapping.exists() else []
    if not isinstance(entries, list):
        raise SystemExit(
            "OIDC identity map must be an array; restore it before starting Jellyfin"
        )
    identities, owners, names = set(), set(), set()
    for entry in entries:
        if not isinstance(entry, dict) or any(
            not isinstance(entry.get(key), str) or not entry[key].strip()
            for key in ("UserId", "ProviderId", "Subject", "Username")
        ):
            raise SystemExit(
                "Incomplete OIDC identity map; restore it before starting Jellyfin"
            )
        identity = (entry["ProviderId"].casefold(), entry["Subject"])
        owner, name = UUID(entry["UserId"]), entry["Username"].casefold()
        if (
            identity[0] != "authentik"
            or identity in identities
            or owner in owners
            or name in names
        ):
            raise SystemExit(
                "Conflicting OIDC identity map; restore it before starting Jellyfin"
            )
        identities.add(identity)
        owners.add(owner)
        names.add(name)
    if any(UUID(user_id) not in owners for (user_id,) in users):
        raise SystemExit(
            "Missing OIDC account binding; restore the identity map before starting Jellyfin"
        )


def update_branding(config_dir, login_html, login_css):
    branding = config_dir / "branding.xml"
    tree = (
        ET.parse(branding)
        if branding.exists()
        else ET.ElementTree(ET.Element("BrandingOptions"))
    )
    blocks = {
        "LoginDisclaimer": login_html.read_text().strip(),
        "CustomCss": login_css.read_text().strip(),
    }
    changed = False
    for tag, block in blocks.items():
        element = tree.getroot().find(tag)
        if element is None:
            element = ET.SubElement(tree.getroot(), tag)
        start, end = (
            ("<!-- foundry-oidc:start -->", "<!-- foundry-oidc:end -->")
            if tag == "LoginDisclaimer"
            else ("/* foundry-oidc:start */", "/* foundry-oidc:end */")
        )
        previous = element.text or ""
        existing = re.sub(
            re.escape(start) + r".*?" + re.escape(end), "", previous, flags=re.S
        ).rstrip()
        element.text = (
            existing + ("\n" if existing else "") + start + "\n" + block + "\n" + end
        )
        changed |= element.text != previous
    if changed:
        branding.parent.mkdir(parents=True, exist_ok=True)
        temporary = branding.with_suffix(".xml.tmp")
        tree.write(temporary, encoding="utf-8", xml_declaration=True)
        temporary.replace(branding)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("data_dir", type=Path)
    parser.add_argument("config_dir", type=Path)
    parser.add_argument("login_html", type=Path)
    parser.add_argument("login_css", type=Path)
    args = parser.parse_args()
    check_identity_map(args.data_dir)
    update_branding(args.config_dir, args.login_html, args.login_css)


if __name__ == "__main__":
    main()

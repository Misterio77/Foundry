import argparse
import re
import xml.etree.ElementTree as ET
from pathlib import Path


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
    update_branding(args.config_dir, args.login_html, args.login_css)


if __name__ == "__main__":
    main()

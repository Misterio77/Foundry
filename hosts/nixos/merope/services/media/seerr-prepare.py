import json
import os
from pathlib import Path
import shutil
import sys
import tempfile


def configure(config_dir, secret_file):
    settings_path = config_dir / "settings.json"
    settings = json.loads(settings_path.read_text())
    secret = secret_file.read_text().strip()
    if not secret:
        raise ValueError("Seerr OIDC client secret is empty")

    # The preview adds database migrations; rollback needs the old DB and settings.
    backup = config_dir.with_name(config_dir.name + ".pre-oidc")
    if not backup.exists():
        with tempfile.TemporaryDirectory(dir=config_dir.parent) as staging:
            snapshot = Path(staging) / "snapshot"
            shutil.copytree(config_dir, snapshot)
            snapshot.rename(backup)

    settings["main"]["applicationUrl"] = "https://requests.m7.rs"
    settings["main"]["oidcLogin"] = True
    oidc = settings.setdefault("oidc", {})
    providers = [p for p in oidc.get("providers", []) if p["slug"] != "authentik"]
    providers.append({
        "slug": "authentik",
        "name": "Gablogin",
        "issuerUrl": "https://auth.m7.rs/application/o/seerr/",
        "clientId": "seerr",
        "clientSecret": secret,
        "scopes": "openid profile email",
        "newUserLogin": True,
    })
    oidc["providers"] = providers
    fd, temporary = tempfile.mkstemp(dir=config_dir)
    try:
        with os.fdopen(fd, "w") as output:
            json.dump(settings, output, indent=2)
            output.write("\n")
        os.replace(temporary, settings_path)
    finally:
        Path(temporary).unlink(missing_ok=True)


if __name__ == "__main__":
    configure(Path(sys.argv[1]), Path(os.environ["CREDENTIALS_DIRECTORY"]) / "oidc-secret")

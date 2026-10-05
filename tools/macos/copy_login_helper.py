#!/usr/bin/env python3
"""Copy the pinned LaunchAtLogin helper, respecting explicit unsigned builds.

The checksums and signing arguments match LaunchAtLogin revision
9a894d799269cb591037f9f9cb0961510d4dca81. Never fall back to unsigned on a
signing error: only CODE_SIGNING_ALLOWED=NO selects the development path.
"""

import hashlib
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys


HELPER_CHECKSUMS = {
    "LaunchAtLoginHelper": "0a3d09438fb595802d554ce0a7c4ba8e1d2d91d5170362adc965da82e70d74cb",
    "LaunchAtLoginHelper-with-runtime": "98ef556b490e02f4084a11d8a07c33a880177a9816b355885a11f58c95876d62",
}


def required(environment, name):
    value = environment.get(name, "").strip()
    if not value:
        raise ValueError(f"Missing build setting: {name}")
    return value


def copy_helper(environment):
    products = Path(required(environment, "BUILT_PRODUCTS_DIR")).resolve()
    contents = Path(required(environment, "CONTENTS_FOLDER_PATH"))
    if contents.is_absolute() or ".." in contents.parts or contents.name != "Contents":
        raise ValueError("CONTENTS_FOLDER_PATH must identify an app inside build products")
    app_contents = (products / contents).resolve()
    if not app_contents.is_relative_to(products) or app_contents.parent.suffix != ".app":
        raise ValueError("App contents escape build products")
    host_id = required(environment, "PRODUCT_BUNDLE_IDENTIFIER")
    if not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", host_id):
        raise ValueError("Invalid host bundle identifier")
    deployment = required(environment, "MACOSX_DEPLOYMENT_TARGET")
    if not re.fullmatch(r"\d+(?:\.\d+){1,2}", deployment):
        raise ValueError("Invalid macOS deployment target")
    version = tuple((list(map(int, deployment.split("."))) + [0, 0])[:3])
    helper_name = "LaunchAtLoginHelper" if version >= (10, 14, 4) else "LaunchAtLoginHelper-with-runtime"
    resources = products / "LaunchAtLogin_LaunchAtLogin.bundle/Contents/Resources"
    archive = resources / f"{helper_name}.zip"
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    if digest != HELPER_CHECKSUMS[helper_name]:
        raise ValueError("Wrong checksum of pinned LaunchAtLoginHelper")

    unsigned = environment.get("CODE_SIGNING_ALLOWED") == "NO"
    identity = None if unsigned else required(environment, "EXPANDED_CODE_SIGN_IDENTITY_NAME")
    entitlements = resources / "LaunchAtLogin.entitlements"
    use_entitlements = bool(environment.get("CODE_SIGN_ENTITLEMENTS"))
    if use_entitlements and not entitlements.is_file():
        raise ValueError("Missing LaunchAtLogin entitlements")

    login_items = app_contents / "Library/LoginItems"
    if not login_items.resolve().is_relative_to(app_contents):
        raise ValueError("LoginItems escape the app bundle")
    helper = login_items / "LaunchAtLoginHelper.app"
    # Only replace this generated bundle after validating the pinned input and
    # required signing settings. A symlink is removed without following it.
    if helper.is_symlink():
        helper.unlink()
    elif helper.exists():
        shutil.rmtree(helper)
    login_items.mkdir(parents=True, exist_ok=True)
    subprocess.run(["/usr/bin/ditto", "-x", "-k", str(archive), str(login_items)], check=True)
    info_path = helper / "Contents/Info.plist"
    info_bytes = info_path.read_bytes()
    info = plistlib.loads(info_bytes)
    info["CFBundleIdentifier"] = f"{host_id}-LaunchAtLoginHelper"
    info_path.write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_BINARY if info_bytes.startswith(b"bplist") else plistlib.FMT_XML))
    executable = info.get("CFBundleExecutable")
    if not isinstance(executable, str) or Path(executable).name != executable or not (helper / "Contents/MacOS" / executable).is_file():
        raise ValueError("LaunchAtLogin helper executable is missing")

    if unsigned:
        print("Copied LaunchAtLogin helper for explicitly unsigned development build; no signing identity used.")
        return helper
    command = ["/usr/bin/codesign", "--force"]
    if use_entitlements:
        command.append(f"--entitlements={entitlements}")
    command += ["--deep", "--options=runtime", f"--sign={identity}", str(helper)]
    subprocess.run(command, check=True)
    subprocess.run(["/usr/bin/codesign", "--verify", "--strict", "--verbose=2", str(helper)], check=True)
    return helper


if __name__ == "__main__":
    try:
        copy_helper(os.environ)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"error: LaunchAtLogin helper preparation failed: {error}", file=sys.stderr)
        sys.exit(1)

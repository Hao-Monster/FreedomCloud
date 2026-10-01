#!/usr/bin/env python3
"""Serialize native signed-identity exports to an unsigned MDM profile.

This tool never verifies code signatures, reads Keychain secrets, installs a
profile, contacts MDM, or changes the device. Run with Python 3.9 or newer.
"""
import argparse
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import sys
import uuid

MAX_INPUT = 2 * 1024 * 1024
MAX_APPLICATIONS = 128
MAX_IDENTITIES = 256
BUNDLE_ID = re.compile(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+\Z")
TEAM_ID = re.compile(r"[A-Z0-9]{10}\Z")
IDENTITY_KEYS = {"identifier", "signingIdentifier", "teamIdentifier", "designatedRequirement", "path", "codeDirectoryHash"}


def bounded_text(value, label, maximum):
    if not isinstance(value, str) or not value or len(value.encode("utf-8")) > maximum:
        raise ValueError(f"{label} must be a nonempty bounded string")
    if any(ord(char) < 32 or ord(char) == 127 for char in value):
        raise ValueError(f"{label} contains control characters")
    return value


def bundle_id(value, label):
    value = bounded_text(value, label, 255)
    if not BUNDLE_ID.fullmatch(value):
        raise ValueError(f"{label} must be an exact bundle identifier")
    return value


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate JSON object key")
        result[key] = value
    return result


def identity(value, label):
    if not isinstance(value, dict) or set(value) - IDENTITY_KEYS:
        raise ValueError(f"{label} contains unknown fields; use the native identity export")
    identifier = bundle_id(value.get("identifier"), f"{label}.identifier")
    signing = bounded_text(value.get("signingIdentifier"), f"{label}.signingIdentifier", 255)
    requirement = bounded_text(value.get("designatedRequirement"), f"{label}.designatedRequirement", 16384)
    # The native exporter supplies SecRequirementCopyString output. Do not
    # rewrite or attempt to interpret Apple's code-requirement language here.
    path = bounded_text(value.get("path"), f"{label}.path", 4096)
    parts = PurePosixPath(path)
    if not path.startswith("/") or path.startswith("//") or ".." in parts.parts or str(parts) != path:
        raise ValueError(f"{label}.path must be a canonical absolute macOS path")
    team = bounded_text(value.get("teamIdentifier"), f"{label}.teamIdentifier", 10)
    if not TEAM_ID.fullmatch(team):
        raise ValueError(f"{label}.teamIdentifier is invalid")
    digest = bounded_text(value.get("codeDirectoryHash"), f"{label}.codeDirectoryHash", 64)
    if not re.fullmatch(r"(?:[a-fA-F0-9]{40}|[a-fA-F0-9]{64})", digest):
        raise ValueError(f"{label}.codeDirectoryHash is invalid")
    return {"Identifier": identifier, "SigningIdentifier": signing,
            "DesignatedRequirement": requirement, "Path": path}, team


def payload(payload_type, identifier, name):
    return {"PayloadType": payload_type, "PayloadVersion": 1,
            "PayloadIdentifier": identifier, "PayloadUUID": str(uuid.uuid4()).upper(),
            "PayloadDisplayName": name}


def build_profile(args, exported):
    host = bundle_id(args.host_bundle_id, "host bundle ID")
    provider = bundle_id(args.provider_bundle_id, "provider bundle ID")
    if not provider.startswith(host + "."):
        raise ValueError("Provider bundle ID must be a child of the host bundle ID")
    if not TEAM_ID.fullmatch(args.team_id):
        raise ValueError("Team ID must contain exactly 10 uppercase letters or digits")
    account = uuid.UUID(args.control_key_account)
    if account.int == 0 or str(account) != args.control_key_account.lower():
        raise ValueError("controlKeyAccount must be a canonical nonzero UUID")
    if not isinstance(exported, dict) or set(exported) != {"schemaVersion", "provider", "applications"}:
        raise ValueError("Expected schemaVersion, provider, and applications from the native export")
    if type(exported["schemaVersion"]) is not int or exported["schemaVersion"] != 1:
        raise ValueError("Unsupported identity export schemaVersion")
    provider_identity, provider_team = identity(exported["provider"], "provider")
    if provider_identity["Identifier"] != provider or provider_identity["SigningIdentifier"] != provider or provider_team != args.team_id:
        raise ValueError("Native provider identity does not match requested bundle ID and Team ID")
    applications = exported["applications"]
    if not isinstance(applications, list) or not 1 <= len(applications) <= MAX_APPLICATIONS:
        raise ValueError("Native export must contain between 1 and 128 applications")
    vpn_uuid = str(uuid.uuid4()).upper()
    mappings = []
    seen = set()
    signing_identifiers = set()
    for index, application in enumerate(applications):
        mapping, _ = identity(application, f"applications[{index}]")
        key = (mapping["Identifier"], mapping["SigningIdentifier"], mapping["Path"])
        if key in seen or mapping["SigningIdentifier"] in signing_identifiers:
            raise ValueError("Duplicate application mapping or signing identity")
        signing_identifiers.add(mapping["SigningIdentifier"])
        if mapping["Identifier"] in {host, provider}:
            raise ValueError("Do not route the host or provider back through its own VPN")
        seen.add(key)
        mapping["VPNUUID"] = vpn_uuid
        mappings.append(mapping)
    if len(mappings) > MAX_IDENTITIES:
        raise ValueError("Provider supports at most 256 exact identities")
    # This is a local app proxy. RemoteAddress satisfies the VPN schema; the
    # provider never uses it to create a direct destination connection.
    vpn = payload("com.apple.vpn.managed.applayer", f"{host}.strict.vpn.{vpn_uuid}", "FreedomCloud managed strict VPN")
    vpn.update({"VPNType": "VPN", "VPNSubType": host, "VPNUUID": vpn_uuid,
                "UserDefinedName": "FreedomCloud managed strict VPN", "OnDemandMatchAppEnabled": True,
                "VendorConfig": {"controlKeyAccount": str(account).upper()},
                "VPN": {"ProviderType": "app-proxy", "ProviderBundleIdentifier": provider,
                        "ProviderDesignatedRequirement": provider_identity["DesignatedRequirement"],
                        "RemoteAddress": "127.0.0.1", "OnDemandEnabled": 1,
                        "OnDemandRules": [{"Action": "Connect"}], "DisconnectOnIdle": 0}})
    mapping_payload = payload("com.apple.vpn.managed.appmapping", f"{host}.strict.mapping.{vpn_uuid}", "FreedomCloud application mappings")
    mapping_payload["AppLayerVPNMapping"] = mappings
    profile = payload("Configuration", f"{host}.strict.profile.{vpn_uuid}", "FreedomCloud managed strict proxy")
    profile.update({"PayloadScope": "System", "PayloadContent": [vpn, mapping_payload],
                    "PayloadDescription": "Managed application proxy routing. Install only after reviewing the native signature export and provisioning the provider."})
    return plistlib.dumps(profile, fmt=plistlib.FMT_XML, sort_keys=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host-bundle-id", required=True)
    parser.add_argument("--provider-bundle-id", required=True)
    parser.add_argument("--team-id", required=True)
    parser.add_argument("--control-key-account", required=True)
    parser.add_argument("--identities", type=Path, required=True, help="Native signed-identity JSON export")
    parser.add_argument("--output", type=Path, required=True, help="New unsigned .mobileconfig file; existing files are refused")
    args = parser.parse_args()
    try:
        with args.identities.open("rb") as source:
            data = source.read(MAX_INPUT + 1)
        if len(data) > MAX_INPUT:
            raise ValueError("Identity export exceeds 2 MiB")
        exported = json.loads(data.decode("utf-8-sig"), object_pairs_hook=unique_object)
        encoded = build_profile(args, exported)
        if args.output.suffix.lower() != ".mobileconfig":
            raise ValueError("Output must have the .mobileconfig suffix")
        # Exclusive creation protects existing deployment profiles and symlinks.
        descriptor = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "wb") as destination:
            destination.write(encoded)
            destination.flush()
            os.fsync(destination.fileno())
    except (OSError, ValueError, UnicodeError, RecursionError) as error:
        # Native export and requirement content may be sensitive; never echo it.
        print(f"Profile not generated: {type(error).__name__}: {str(error) if isinstance(error, ValueError) and not isinstance(error, json.JSONDecodeError) else 'invalid input or file operation failed'}", file=sys.stderr)
        return 1
    print("Unsigned profile created. No signature verification, enrollment, installation, or deployment was performed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

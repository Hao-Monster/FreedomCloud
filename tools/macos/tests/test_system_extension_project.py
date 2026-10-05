"""Static Xcode model contracts; real configuration builds remain a CI gate."""

from pathlib import Path
import plistlib
import re
import unittest


ROOT = Path(__file__).resolve().parents[3]
PROJECT = ROOT / "macos/Runner.xcodeproj/project.pbxproj"


def object_body(project, identifier):
    match = re.search(r"^\s*" + identifier + r"(?: /\*[^\n]*?\*/)?\s*=\s*\{", project, re.MULTILINE)
    if not match:
        raise AssertionError(f"Missing Xcode object {identifier}")
    start = match.end()
    depth, quoted, escaped = 1, False, False
    for index in range(start, len(project)):
        character = project[index]
        if escaped:
            escaped = False
        elif character == "\\" and quoted:
            escaped = True
        elif character == '"':
            quoted = not quoted
        elif not quoted:
            depth += (character == "{") - (character == "}")
            if depth == 0:
                return project[start:index]
    raise AssertionError(f"Unterminated Xcode object {identifier}")


def field(body, name):
    match = re.search(r"\b" + name + r"\s*=\s*(\"[^\"]*\"|[^;]+);", body)
    if not match:
        raise AssertionError(f"Missing Xcode field {name}")
    # CocoaPods may reserialize UUID values with explanatory inline comments.
    return re.sub(r"/\*.*?\*/", "", match.group(1), flags=re.DOTALL).strip().strip('"')


class SystemExtensionProjectTest(unittest.TestCase):
    def setUp(self):
        self.project = PROJECT.read_text(encoding="utf-8")
        self.target = object_body(self.project, "FC0100010000000000000004")
        self.embed_build_file = object_body(self.project, "FC0100010000000000000002")

    def test_embed_reference_is_not_target_product_placeholder(self):
        product_reference = field(self.target, "productReference")
        embed_reference = field(self.embed_build_file, "fileRef")
        self.assertNotEqual(product_reference, embed_reference,
                            "Copy phase must resolve its own path in Runner's configuration, not reuse the target product placeholder")
        reference = object_body(self.project, embed_reference)
        self.assertEqual(field(reference, "sourceTree"), "BUILT_PRODUCTS_DIR")
        self.assertEqual(field(reference, "path"), "$(FCX_STRICT_BUNDLE_IDENTIFIER).systemextension")
        self.assertEqual(field(reference, "explicitFileType"), "wrapper.system-extension")

    def test_all_configuration_filenames_match_provider_identity(self):
        configurations = {"Debug": ("FC0100010000000000000014", "Debug"),
                          "Release": ("FC0100010000000000000015", "Release"),
                          "Profile": ("FC0100010000000000000016", "Release")}
        for name, (identifier, config_file) in configurations.items():
            with self.subTest(configuration=name):
                provider = field(object_body(self.project, identifier), "PRODUCT_BUNDLE_IDENTIFIER")
                config = (ROOT / f"macos/Runner/Configs/{config_file}.xcconfig").read_text()
                embed_id = re.search(r"^FCX_STRICT_BUNDLE_IDENTIFIER\s*=\s*(\S+)", config, re.MULTILINE).group(1)
                self.assertEqual(embed_id, provider)
                self.assertEqual(provider, "com.follow.clash.debug.StrictProxy" if name == "Debug" else "com.follow.clash.StrictProxy")
        provider_config = (ROOT / "macos/StrictProxy/StrictProxy.xcconfig").read_text()
        self.assertRegex(provider_config, r"(?m)^PRODUCT_NAME\s*=\s*\$\(PRODUCT_BUNDLE_IDENTIFIER\)\s*$")

    def test_native_embedding_and_explicit_dependency_are_preserved(self):
        phase = object_body(self.project, "FC0100010000000000000006")
        self.assertEqual(field(phase, "isa"), "PBXCopyFilesBuildPhase")
        self.assertEqual(field(phase, "dstPath"), "$(CONTENTS_FOLDER_PATH)/Library/SystemExtensions")
        self.assertIn("FC0100010000000000000002", field(phase, "files"))
        self.assertIn("CodeSignOnCopy", field(self.embed_build_file, "ATTRIBUTES"))
        self.assertIn("RemoveHeadersOnCopy", field(self.embed_build_file, "ATTRIBUTES"))
        dependency = object_body(self.project, "FC0100010000000000000005")
        self.assertEqual(field(dependency, "target"), "FC0100010000000000000004")
        runner = object_body(self.project, "33CC10EC2044A3C60003C045")
        self.assertIn("FC0100010000000000000005", field(runner, "dependencies"))
        self.assertIn("FC0100010000000000000006", field(runner, "buildPhases"))

    def test_bundle_metadata_and_restricted_entitlements_remain_intact(self):
        with (ROOT / "macos/Runner/Info.plist").open("rb") as source:
            host_info = plistlib.load(source)
        self.assertEqual(host_info["FCXStrictProviderBundleIdentifier"], "$(PRODUCT_BUNDLE_IDENTIFIER).StrictProxy")
        with (ROOT / "macos/StrictProxy/Info.plist").open("rb") as source:
            provider_info = plistlib.load(source)
        self.assertEqual(provider_info["CFBundleIdentifier"], "$(PRODUCT_BUNDLE_IDENTIFIER)")
        with (ROOT / "macos/StrictProxy/StrictProxy.entitlements").open("rb") as source:
            entitlements = plistlib.load(source)
        self.assertIn("app-proxy-provider-systemextension", entitlements["com.apple.developer.networking.networkextension"])


if __name__ == "__main__":
    project = PROJECT.read_text(encoding="utf-8")
    target_reference = field(object_body(project, "FC0100010000000000000004"), "productReference")
    embed_reference = field(object_body(project, "FC0100010000000000000002"), "fileRef")
    for label, identifier in [("StrictProxy target product", target_reference), ("Runner embed input", embed_reference)]:
        print(f"{label}: {identifier} {field(object_body(project, identifier), 'path')}")
    unittest.main()

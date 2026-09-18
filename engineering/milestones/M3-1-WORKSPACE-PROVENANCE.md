# M3-1 workspace provenance

Status: Implemented in the focused M3-1 change; the checkout remains
intentionally dirty because existing owner work has not been assigned to this
commit.

Baseline before this task: `development` at `420665f`
(`docs: establish FreedomCloud M3 readiness milestone`). The source tree was
already dirty before M3-1 started. No existing file was cleaned, reset,
normalized, or staged as part of this task.

## What changed

`setup.dart` now records the full source commit, the current branch or
detached state, and the Git working-tree state when Windows package metadata is
written. The metadata template no longer contains a hard-coded branch and
marks dirty or unverifiable source trees as `NON-REPRODUCIBLE`.

The resolver uses read-only Git commands. A Git failure produces an explicit
error for commit or branch identity, and an `unknown` tree state for working
tree inspection; neither path is allowed to claim a clean source tree.

## Pre-task dirty-worktree inventory

The snapshot immediately before the M3-1 change contained 26 tracked modified
paths and 8 untracked entries. They remain outside the M3-1 commit:

Tracked owner or experiment changes:

- `analysis_options.yaml`
- `arb/intl_en.arb`, `arb/intl_ja.arb`, `arb/intl_ru.arb`, `arb/intl_zh_CN.arb`
- `lib/common/navigation.dart`, `lib/enum/enum.dart`, `lib/views/config/general.dart`
- `lib/views/dashboard/widgets/hero_connect.dart`
- `lib/views/profiles/add_profile.dart`, `lib/views/views.dart`
- `lib/l10n/intl/messages_en.dart`, `lib/l10n/intl/messages_ja.dart`,
  `lib/l10n/intl/messages_ru.dart`, `lib/l10n/intl/messages_zh_CN.dart`,
  `lib/l10n/l10n.dart`
- `linux/flutter/generated_plugin_registrant.cc`,
  `linux/flutter/generated_plugin_registrant.h`,
  `linux/flutter/generated_plugins.cmake`
- `macos/Flutter/GeneratedPluginRegistrant.swift`
- `pubspec.lock`
- `services/helper/src/main.rs`, `services/helper/src/service/mod.rs`
- `windows/flutter/generated_plugin_registrant.cc`,
  `windows/flutter/generated_plugin_registrant.h`,
  `windows/flutter/generated_plugins.cmake`

Untracked experiments or owner files:

- `engineering/m3-test-package/_tmp-strict-manifest-runtime-test.json`
- `engineering/m3-test-package/_tmp-test-manifest.json`
- `include/flclash_strict_build.h`
- `lib/views/purchase.dart`
- `strict-package-manifest.json`
- `tmp_vswhere.json`, `vswhere-all.json`, `vswhere-components.json`,
  `vswhere.json`

Some tracked paths may be line-ending or generated-file noise, but that is not
resolved automatically. Git still reports the checkout as dirty until the
owner reviews and assigns each path. The two temporary manifests and the
generated strict header are not release inputs.

## Reproducibility rule

Run the metadata-producing command from the repository root. A clean tree is
reported as reproducible from its recorded 40-character commit. A dirty or
unverifiable tree is explicitly marked `NON-REPRODUCIBLE`; it must not be used
as release provenance. The current dirty checkout is therefore evidence for
the audit only, not a clean release baseline.

Only these M3-1 files belong in the focused commit:

- `setup.dart`
- `engineering/test-package/BUILD-INFO.txt.in`
- this document

Future work must assign the inventory above to focused commits or retain it as
an explicitly named local experiment before the M3 milestone can close.

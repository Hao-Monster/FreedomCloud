# Windows package reproducibility inputs

This document records the CI inputs used by the Windows rows in
`.github/workflows/build.yaml`. It is a provenance aid for M3-2; it is not a
claim that the current Flutter, MSVC, Cargo or Inno outputs are byte-for-byte
reproducible.

## Pinned inputs

| Input | Windows x64 | Windows ARM64 | Source or reason |
| --- | --- | --- | --- |
| Flutter | Stable `3.41.7` | Flutter Git commit `e4cb8ffd9882e8db5edb7ab356205630f863c1e0` | `3.41.7` is the existing repository CI pin. The ARM job previously used the moving `master` channel; it now checks out one recorded Flutter commit so a later master change cannot silently alter the SDK. |
| Rust | `1.98.1` | `1.98.1` | The Windows jobs use one explicit Rust toolchain. The ARM job installs the aarch64 host toolchain; the x64 job selects the same version through rustup. |
| Go | `1.26.0` | `1.26.0` | Existing `actions/setup-go` input in the build workflow. |
| Inno Setup | `6.7.3` | `6.7.3` | Existing delivery evidence records Inno Setup 6.7.3; Chocolatey is now asked for that exact package version. |
| WDK/SDK | Not used by the ordinary package job | Not used by the ordinary package job | Strict-driver source pins `10.0.28000.2526` in `windows/strict-driver/packages.config` and `Directory.Build.props`; driver qualification remains a separate M3 gate. |

The Flutter ARM value is an exact commit from the official Flutter repository.
The action still names the `master` clone path because that is how the action
fetches an ARM-capable checkout; `flutter-version` immediately detaches it at
the recorded commit. It does not follow the branch tip.

## Clean checkout procedure

Use a fresh directory and a reviewed commit. Do not build from the dirty
developer checkout used for investigation:

```powershell
git clone https://github.com/Hao-Monster/FreedomCloud.git FreedomCloud-clean
Set-Location .\FreedomCloud-clean
git checkout --detach <reviewed-40-character-commit>
if ((git status --porcelain)) { throw 'checkout is not clean' }
flutter pub get
```

The reviewed commit must be recorded in `BUILD-INFO.txt`. A dirty or
unverifiable source tree is diagnostic evidence only and must not be presented
as a reproducible release.

The release workflow now creates adjacent `.sha256` files for pre-releases as
well as stable releases. The links in both release templates use the actual
`windows-arm64` filenames emitted by the Windows build matrix.

## Known limitations

- `windows-latest` and `windows-11-arm` are GitHub-hosted runner labels, not
  immutable machine images. Visual Studio/MSVC revisions supplied by those
  images remain a separate toolchain gate.
- `setup.dart` derives `SOURCE_DATE_EPOCH` from the explicit environment value
  or the recorded source commit, and uses `New-DeterministicZip.ps1` for the
  portable archive. The strict VM bundle uses the same archive writer. A dirty
  source tree is still marked non-reproducible, and native compiler output can
  vary when the runner toolchain differs.
- The workflow does not produce a signed strict WFP package. Driver signing,
  Broker/manifest identity, HLK and Windows 11 traffic qualification remain
  external M3 gates.
- No package build or Windows VM test is implied by this document.

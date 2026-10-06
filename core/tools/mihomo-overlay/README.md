# Checked Mihomo TUN lifecycle overlay

FlClashX pins Mihomo `v1.19.32` at upstream commit
`88dcbf7f1614a67c3b36b848ee3592dfa92ada36`. The upstream listener does not
provide a synchronized lifecycle/error snapshot and its cleanup can leave an
enabled configuration without a listener. The small patches in `patches/`
make this state observable without changing the packet-processing algorithm.

From the `core` directory:

```sh
go run ./tools/mihomo-overlay
go test -modfile=.generated/go.mod -overlay=.generated/mihomo-overlay.json ./...
go test -modfile=.generated/go.mod -overlay=.generated/mihomo-overlay.json -race -run '^TestFCXTun' github.com/metacubex/mihomo/listener
go build -modfile=.generated/go.mod -overlay=.generated/mihomo-overlay.json -tags=with_gvisor -trimpath -o .generated/FlClashCore.exe .
```

In PowerShell, quote the complete arguments containing `=` and a relative path,
for example `'-modfile=.generated/go.mod'`. Race tests require a supported C
compiler. All `TestFCXTun` tests inject an in-memory listener factory; they never
create an actual adapter, route, service, or firewall rule.

The generator downloads only the exact pinned upstream module when needed,
checks its module checksum, runs `go mod verify`, and verifies SHA256 for every
upstream file it replaces. It creates an isolated source copy outside the module
cache, then publishes it to a content-addressed directory and generates an
alternate module file and Go overlay. The replacement path is relative to the
Core root so host paths do not enter module build metadata. Cached dependency
files are never patched. An existing generated source tree is reused only after
its complete file inventory matches the fresh verified copy; extra or altered
files fail the build and remain available for investigation. Old directories are
never deleted by this tool.

The patch also routes the external-controller's configuration read through the
same listener lock. Configuration snapshots clone their slice backing arrays,
so external edits cannot mutate live listener data outside that lock. TUN close
failure remains latched until Core restart: a second cleanup cannot convert an
uncertain resource release into a successful disabled state.

`.generated/mihomo-v1.19.32/manifest.json` records the upstream commit and module
sum, original file hashes, each patch hash, generator hash, project module-file
hash, and the complete effective dependency file inventory and its aggregate
SHA256. Generated outputs are build inputs/artifacts, not tracked source. Attach
the manifest to previews built with this patch.

The Core deliberately calls the added `GetTunLifecycleStatus` symbol. Compiling
without the overlay fails instead of silently shipping a build without the
observability fix. Dependency upgrades must update the pinned version, source
hashes, patch review and tests together; do not suppress hash failures.

`getTunStatus` is a read-only Core action. It reports the current Core instance,
listener revision, request intent, actual listener creation, Windows adapter
observation and current Core token elevation. It does not attest that every
application or destination is routed through a proxy. `fcx://runtime` retains its
configuration semantics, and configuration acceptance remains distinct from
TUN activation.

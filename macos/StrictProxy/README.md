# macOS managed strict app proxy

The user selected MDM-managed per-app VPN for R-111. `StrictAppProxyProvider`
implements the system extension provider, using the existing exact signed identity
matching and bounded TCP/UDP flow dispatcher. `main.swift` enters
`NEProvider.startSystemExtensionMode()`. The containing app owns activation and
loads the MDM-created `NEAppProxyProviderManager`; it must not manufacture an
unmanaged app-proxy profile or describe the extension as installed from source alone.

## Control and persistence contract

- The host keeps its random 32-byte control key in its login Keychain. The root
  system extension uses `/Library/Keychains/System.keychain`; it never assumes
  the user's login/data-protection Keychain is visible across the user boundary.
- MDM/host `NETunnelProviderProtocol.providerConfiguration.controlKeyAccount`
  is a UUID. On first start, the host passes `startTunnel(options:)` with
  `controlKey` as NSData through the OS-owned channel, never in the MDM profile.
  Provider stores the key at generic-password service `com.freedomcloud.strict.control`
  and that UUID account in the system Keychain, with its default process access ACL.
- A later supplied bootstrap key must constant-time match the stored key. Missing
  key with an existing saved state is an error, never a replay-watermark reset.
  Automatic OS restart may omit the bootstrap key once it is durably stored.
  Explicit profile/key reprovisioning requires a new managed account UUID.
- The provider does not generate keys. It starts blocked if there is no saved
  policy; unavailable keys or corrupted persisted state fail startup. No key
  enters logs, diagnostics, source, a configuration profile, or ordinary files.
- `sendProviderMessage` accepts `StrictControlEnvelope` JSON, whose `body` is
  JSON-encoded `StrictProxyConfiguration`. Data properties use Codable base64.
  HMAC-SHA256 covers unsigned 64-bit big-endian generation followed by body.
  Both generations must agree and exceed the last accepted generation.
- Configuration fields: `generation`, `policies`, `dnsServers`. DNS is an explicit
  list of at most four IPv4/IPv6 literals; at least one is required with proxy
  policies. There is no public-DNS or physical-route fallback default.
- Policy fields: `signingIdentifier`, `codeDirectoryHash`, `action` (`proxy` or
  `block`), TCP `port`, `username`, `password`, Core `generation`, Core `udpPort`.
  Proxy policies require positive ports/generation and two 64-character hex
  credentials. The outer control generation and Core ingress generation have
  distinct scopes and must not be conflated.
- Accepted envelope and replay watermark are atomically persisted as a single
  Keychain item, service `com.freedomcloud.strict.state`, same system-Keychain account.
  Restart re-authenticates it before installation. No policy secrets enter
  UserDefaults, diagnostics, ordinary files, or the MDM profile.
- The bounded read-only message `{"operation":"status"}` returns `ok`, `code`,
  `generation`, `ready`, `applying`, `identityCount`, `activeFlows`, and `stopping`.
  This status read is not a policy mutation and exposes no identities or secrets.
- Configure returns the same status shape with `code=configured` only after OS
  DNS settings and dispatcher configuration complete. Busy, invalid, replayed,
  persistence, or network-settings failures return `ok=false`. A settings timeout
  after 15 seconds blocks flows and ignores any late callback. Generation may
  advance while ready remains false: read status and issue a higher generation.

## Enforcement lifecycle

Every flow delivered by MDM is handled or explicitly closed; an unknown identity
never returns false to the OS. Missing policy, changed CDHash, blocked policy,
unsupported protocol, exhausted capacity, and stopped/unready provider close both
flow directions. Policy updates revoke old sessions before persistence; storage
failure stays blocked. Stop closes sessions and preserves authenticated intent.
Restart restores intent; stale Core endpoints/credentials fail transport closed.
At most 256 identities and sessions are retained; flow idle limit is five minutes.

DNS settings apply the explicit servers to all domains in this per-app VPN.
Source changes do not prove attribution of all OS/shared-resolver DNS traffic,
MDM capture completeness, crash-time persistence, or DNS/FakeIP domain recovery;
those require the user's real managed-device acceptance. Explicit DIRECT/INHERIT
applications must be excluded by the containing app/MDM mapping, not converted to
a direct socket inside the provider. Each real network executable is enrolled
with its exact signing identifier and CDHash; upgrades require verified enrollment.

The Runner shares only `StrictProxyModels`, `StrictControlEnvelope`, and
`StrictApplicationIdentity`; the system extension compiles all files here.
Transport integration uses policy-bound Core ingress; ordinary mixed-port traffic
cannot substitute for strict ingress. No tests, builds, signing, network probes,
profile installation, MDM registration, or device changes were executed.

## Primary references

- https://developer.apple.com/documentation/networkextension/neappproxyprovider
- https://developer.apple.com/documentation/networkextension/neappproxyprovidermanager
- https://developer.apple.com/documentation/networkextension/netunnelprovidermanager
- https://developer.apple.com/documentation/networkextension/nednssettings
- https://developer.apple.com/documentation/networkextension/neflowmetadata/sourceappuniqueidentifier
- https://developer.apple.com/documentation/technotes/tn3134-network-extension-provider-deployment

### Managed runtime integration (source delivery)

The host panel configures the managed provider, authenticates Core ingress and
registers the user login Agent only on explicit action. Agent replay stores the
Core configuration and fixed-port strict credentials in a bounded 4 MiB Keychain
envelope. Provider state uses its own root System.keychain context.

FCXD v1 carries IP endpoints; macOS-only v2 carries bounded ASCII/IDNA domain
endpoints through Core's existing proxy resolver. Windows rejects v2. Neither
registration nor provider readiness proves runtime acceptance. See
`engineering/macos-managed-strict.md` for prerequisites and unexecuted checks.

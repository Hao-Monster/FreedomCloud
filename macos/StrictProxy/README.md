# macOS strict proxy reusable implementation

These sources provide actual SOCKS5 transport, flow pumps, exact signed identity
matching, bounded session dispatch and authenticated control envelopes. They are
not an installed Network Extension and do not advertise strict readiness.

## Architecture decision required

Apple documents that NETransparentProxyProvider returning false permits direct
traffic. A running proxy plus a heartbeat-only filter has a bypass interval on
provider loss, so that design does not meet FreedomCloud's persistent failclosed
requirement. An always-drop filter is not a proven substitute: capture/filter
ordering and the lifetime of an allowed flow must be established.

Apple documents NEAppProxyProviderManager as loading profiles created through
com.apple.vpn.managed.applayer MDM payloads. Managed per-app VPN is the documented
route for selected applications to remain unable to communicate while the VPN
is disconnected. This adds an MDM prerequisite and must not be silently imposed
on the existing unmanaged-desktop product requirement.

Until the user/coordinator chooses that deployment architecture, provider class,
Xcode extension target/embedding, host activation UI, policy bootstrap and
persistent configuration are intentionally not implemented. This is unfinished
R-111 development, not just an external certificate or acceptance blocker.

## Integration contract

- Validate StrictProxyConfiguration before constructing transports.
- Enroll each real network executable separately with signingIdentifier and
  codeDirectoryHash from StrictApplicationIdentity.inspect; upgrades require
  publisher-verified re-enrollment. No bundle prefix matching is used.
- Pass per-policy authenticated loopback Core SOCKS listener credentials; a
  generic mixed-port cannot guarantee policy-specific routing.
- Windows strict ingress currently disables standard SOCKS UDP. macOS must
  explicitly provide a policy-bound UDP-capable SOCKS listener before enabling
  the UDP path. Never advertise support based only on client source presence.
- Provider owns StrictFlowDispatcher; stop/reconfigure closes all old sessions.
- Host and provider use a per-install 32-byte key for StrictControlEnvelope,
  authenticated OS provider communication, and persisted monotonic generation.
- Secret material must remain in Keychain/OS provider storage, never diagnostic
  reports or source control.
- Flow timeout is five minutes idle; at most 256 sessions and 256 exact identities.
- No network/system configuration changes and no tests/builds were executed.

## Primary references consulted

- https://developer.apple.com/documentation/networkextension/handling-flow-copying
- https://developer.apple.com/documentation/networkextension/neappproxyprovidermanager
- https://developer.apple.com/documentation/networkextension/routing-your-vpn-network-traffic
- https://developer.apple.com/documentation/networkextension/neflowmetadata/sourceappuniqueidentifier
- https://developer.apple.com/documentation/networkextension/neappproxyudpflow

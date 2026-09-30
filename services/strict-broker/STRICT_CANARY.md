# Windows strict forwarding activation canary

The Broker now qualifies forwarding before production data-plane filters are installed. Persistent selected-application guards remain installed throughout qualification. This is runtime feature code; no canary was executed during development.

## Evidence and isolation

- A private child of the signed, file-locked Broker executable runs `--strict-canary`; no extra unsigned helper or package artifact is needed. Parent passes only a random challenge and DNS address over inherited private stdin, never ingress credentials.
- The prepare phase already installs the persistent global conditional DATAGRAM_DATA_V4/V6 guard filters through WfpPolicyPlan.guard_filters. Canary reuses those flow-context-bound callouts; it must not install duplicate datagram filters.
- Six dynamic App-ID filters select the Broker image. Driver filter context bypasses every PID except the admitted child. Admission binds a referenced process object, revision, digest, target and endpoint lease nonce for 30 seconds. During this phase production application rules remain blocked. Parent Broker/Core processes are not granted the canary rule.
- Each target requires IPv4 and IPv6 HTTP TCP, IPv4 and IPv6 UDP DNS and QUIC version negotiation, plus a TCP connection to the address produced by Core DNS. Successful external replies alone never qualify: TCP needs validated driver redirect metadata with exact child PID and active lease; UDP needs four successful kernel-injection bits bound to a per-admission sequence, target and nonce.
- Core uses its actual DNS resolver, not a synthetic cache insertion. A delegate around the real blocking Mihomo `HandleTCPConn` records actual post-processing Host and DNSMapping/DNSFakeIP metadata, tied to authenticated strict listener user, target, original destination, nonce and 30-second expiry. A second HMAC-authenticated FCXU exchange confirms this observation. Both redir-host and Fake-IP are supported; absent mappings/restoration fail explicitly.
- Canaries finish with the UDP gate closed, contexts drained, child reaped, filters closed and canary admission cleared. The UDP receiver is then newly pre-armed before production commit. Failures revoke the endpoint lease and retain user guards.

## External dependencies and limits

The default probes use `1.1.1.1` and `2606:4700:4700::1111`: TCP 80 `/cdn-cgi/trace` with Host `one.one.one.one`, UDP 53 with a random subdomain of `example.com`, and UDP 443 reserved-version QUIC negotiation. Domain-restoration uses Core resolution of `www.cloudflare.com`, then its TCP 80 `/cdn-cgi/trace` response. These are genuine external connections through each selected proxy group; availability, IPv6, UDP and the endpoint response protocols are runtime prerequisites. Restricted/offline networks can fail qualification even when some proxy functions work; no success is fabricated and no application is permitted as a fallback.

Administrators may set `FCX_STRICT_CANARY_IPV4` / `FCX_STRICT_CANARY_IPV6` in the Broker service environment to replace the two literal addresses. Replacements must support the same HTTP Host/path, DNS and QUIC response protocols. Loopback, unspecified and multicast destinations are rejected. The restoration domain is fixed. No credentials, challenge, domain response body or raw internal error is exposed to UI.

Each socket operation is bounded at two seconds; each child is killed/reaped at 25 seconds; per-target driver admission expires at 30 seconds. The whole sequential target qualification has a 240-second budget (remaining budget also limits the current child); the pre-existing Core authentication phase is separately bounded. CommitPolicy pipe response read allows 300 seconds; ordinary commands retain their default deadline. Very large/slow target sets can exceed the budget and fail closed. Driver endpoint renewal remains every two seconds while qualification runs.

Broker emits only allowlisted error categories: ForwardingDnsMapping, ForwardingDnsRestoration, ForwardingCanary, ForwardingTimeout. Agent converts these to fixed Chinese diagnostics. Compile, signed-driver installation, real WFP traffic, rollback and UI acceptance remain user-owned and were NOT RUN.

## Wire extensions

Driver IOCTL 0x909 binds the 80-byte canary descriptor; 0x90a clears only after closing the datagram gate; 0x90b returns the usual attested snapshot with reserved bytes 160..168 containing the admission UDP evidence bitmask. Ordinary snapshot reserved bytes remain zero. TCP context protocol 1 remains unchanged; canary context protocol 2 adds the child PID at bytes 96..104 and retains zero tail bytes. Core FCXU kinds 3/4 obtain a mapped IPv4 address and kinds 5/6 confirm observed restoration; all preserve generation/key/nonce correlation and HMAC authentication.

## Strict PROXY exit enforcement

Canary connectivity alone does not prove that a proxy group avoided DIRECT. The Core therefore routes authenticated strict TCP and UDP ingresses through generation-scoped internal adapters. At each TCP dial or UDP association creation the adapter unwraps the current selector/fallback/url-test/load-balance chain, rejects DIRECT/PASS/COMPATIBLE/rematch/DNS/reject/unknown classes and cycles, and invokes the selected real proxy protocol leaf object directly. The mutable group is never dialed after inspection, closing the check-then-switch race. Existing UDP associations remain on their already selected proxy leaf; new associations reevaluate the group. There is no physical-direct fallback on errors.

These adapters require the matching random authenticated ingress username, loopback source, expected inbound name and generation alias. Ordinary profiles and explicit DIRECT application policy are unchanged. Route cleanup marks the old generation revoked and removes only its own registered adapter objects; proxy/provider objects belonging to normal traffic are retained. User connection chains retain the original policy group name and internal aliases are filtered from the app proxy inventory. DNS restoration attestation recognizes the same internal route alias while retaining the original target group as its policy identity.

This implementation covers the actual dynamic group classes present in the pinned Mihomo dependency. Unrecognized new group/protocol types are intentionally rejected until an explicit safe implementation is added. No test or runtime verification was performed for this source change.

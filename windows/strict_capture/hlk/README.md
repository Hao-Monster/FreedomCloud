# HLK / attestation hand-off

This folder is a release checklist, not a replacement for Microsoft's Hardware
Lab Kit.  The driver must be tested on a dedicated Windows 11 HLK client with
an HLK controller and the exact target build/architectures.  Run the official
Code Integrity, Device Fundamentals, INF, reboot, power and networking tests;
export the resulting `.hlkx` project and preserve the controller logs.

Required inputs from the publisher:

1. Microsoft Partner Center account with Windows Hardware/attestation access.
2. EV/attestation code-signing certificate and its protected signing workflow.
3. HLK controller plus one or more clean Windows 11 client VMs or machines.
4. A release decision for attestation versus WHQL (and timestamp service).

Do not claim a signed release from a locally self-signed test certificate.  The
local script is useful only for isolated development boot tests.

use flclash_strict_broker::{BrokerAuthenticator, ClientPrincipal, ClientRole};

fn hex(character: char) -> String {
    std::iter::repeat_n(character, 64).collect()
}

fn frame(capability: &str, command: &str) -> String {
    format!(
        r#"{{"protocol":1,"requestId":"request-1","sessionCapability":"{capability}","command":{command}}}"#
    )
}

#[test]
fn local_owner_requires_the_exact_session_capability() {
    let authenticator = BrokerAuthenticator::new([0x11; 32]);
    let owner = ClientPrincipal::new(true, ClientRole::Owner);

    assert!(authenticator
        .authenticate(&owner, &frame(&hex('1'), r#"{"type":"status"}"#))
        .is_ok());
    assert!(authenticator
        .authenticate(&owner, &frame(&hex('2'), r#"{"type":"status"}"#))
        .is_err());
}

#[test]
fn remote_principals_are_rejected_even_with_the_capability() {
    let authenticator = BrokerAuthenticator::new([0x11; 32]);
    let remote = ClientPrincipal::new(false, ClientRole::Owner);

    assert!(authenticator
        .authenticate(&remote, &frame(&hex('1'), r#"{"type":"status"}"#))
        .is_err());
}

#[test]
fn recovery_administrator_cannot_prepare_or_commit_policy() {
    let authenticator = BrokerAuthenticator::new([0x11; 32]);
    let administrator = ClientPrincipal::new(true, ClientRole::RecoveryAdministrator);

    assert!(authenticator
        .authenticate(
            &administrator,
            &frame(&hex('1'), r#"{"type":"forceBlocking","revision":7}"#),
        )
        .is_ok());
    assert!(authenticator
        .authenticate(
            &administrator,
            &frame(
                &hex('1'),
                &format!(
                    r#"{{"type":"commitPolicy","revision":7,"policyDigest":"{}"}}"#,
                    hex('a')
                ),
            ),
        )
        .is_err());
}

#[test]
fn malformed_and_unknown_command_fields_are_rejected_before_authorization() {
    let authenticator = BrokerAuthenticator::new([0x11; 32]);
    let owner = ClientPrincipal::new(true, ClientRole::Owner);

    assert!(authenticator.authenticate(&owner, "not-json").is_err());
    assert!(authenticator
        .authenticate(
            &owner,
            &frame(&hex('1'), r#"{"type":"status","extra":true}"#),
        )
        .is_err());
}

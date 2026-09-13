use flclash_strict_broker::{
    VerifiedApplicationAppIds, VerifiedPolicyAppIds, MAX_VERIFIED_APP_ID_BYTES,
};
use flclash_strict_contract::{
    StrictChildIdentity, StrictIdentity, StrictPolicyBundle, StrictPolicyEntry,
};

fn policy_with_child() -> StrictPolicyBundle {
    StrictPolicyBundle::new(
        1,
        vec![StrictPolicyEntry::block(StrictIdentity {
            identity_id: "10000000-0000-4000-8000-000000000001".into(),
            canonical_path: r"C:\Apps\Alpha\alpha.exe".into(),
            wfp_app_id_sha256: "a".repeat(64),
            publisher_certificate_sha256: "b".repeat(64),
            verified_children: vec![StrictChildIdentity {
                canonical_path: r"C:\Apps\Alpha\child.exe".into(),
                wfp_app_id_sha256: "c".repeat(64),
                publisher_certificate_sha256: "b".repeat(64),
            }],
        })],
    )
    .unwrap()
}

#[test]
fn verified_app_ids_must_match_every_declared_identity_exactly() {
    let policy = policy_with_child();
    let verified = VerifiedPolicyAppIds::new(
        &policy,
        vec![VerifiedApplicationAppIds::new(
            "10000000-0000-4000-8000-000000000001",
            vec![vec![1, 2], vec![3, 4]],
        )
        .unwrap()],
    )
    .unwrap();
    assert_eq!(verified.application_count(), 1);
    assert_eq!(verified.app_id_count(), 2);

    let missing_child =
        VerifiedApplicationAppIds::new("10000000-0000-4000-8000-000000000001", vec![vec![1, 2]])
            .unwrap();
    assert!(VerifiedPolicyAppIds::new(&policy, vec![missing_child]).is_err());

    let wrong_family = VerifiedApplicationAppIds::new(
        "20000000-0000-4000-8000-000000000002",
        vec![vec![1], vec![2]],
    )
    .unwrap();
    assert!(VerifiedPolicyAppIds::new(&policy, vec![wrong_family]).is_err());
}

#[test]
fn verified_app_id_memory_is_strictly_bounded() {
    assert!(VerifiedApplicationAppIds::new(
        "10000000-0000-4000-8000-000000000001",
        vec![Vec::new()],
    )
    .is_err());
    assert!(VerifiedApplicationAppIds::new(
        "10000000-0000-4000-8000-000000000001",
        vec![vec![0; MAX_VERIFIED_APP_ID_BYTES + 1]],
    )
    .is_err());
}

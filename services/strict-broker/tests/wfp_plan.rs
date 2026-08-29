use std::collections::BTreeSet;

use flclash_strict_broker::{
    PlanInstallStep, PlanRemoveStep, VerifiedApplicationAppIds, VerifiedPolicyAppIds,
    WfpFilterLifetime, WfpLayer, WfpObjectKey, WfpPolicyPlan,
};
use flclash_strict_contract::{
    StrictAction, StrictChildIdentity, StrictIdentity, StrictPolicyBundle, StrictPolicyEntry,
};

fn identity(id: &str, path: &str, character: char) -> StrictIdentity {
    StrictIdentity {
        identity_id: id.into(),
        canonical_path: path.into(),
        wfp_app_id_sha256: character.to_string().repeat(64),
        publisher_certificate_sha256: "f".repeat(64),
        verified_children: Vec::new(),
    }
}

fn proxy_policy(revision: u64) -> StrictPolicyBundle {
    let mut proxy = identity(
        "10000000-0000-4000-8000-000000000001",
        r"C:\Apps\Alpha\alpha.exe",
        'a',
    );
    proxy.verified_children.push(StrictChildIdentity {
        canonical_path: r"C:\Apps\Alpha\child.exe".into(),
        wfp_app_id_sha256: "b".repeat(64),
        publisher_certificate_sha256: "f".repeat(64),
    });
    StrictPolicyBundle::new(
        revision,
        vec![
            StrictPolicyEntry::proxy(proxy, "Proxy-A".into()),
            StrictPolicyEntry::block(identity(
                "20000000-0000-4000-8000-000000000002",
                r"C:\Apps\Blocked\blocked.exe",
                'c',
            )),
        ],
    )
    .unwrap()
}

fn verified(policy: &StrictPolicyBundle) -> VerifiedPolicyAppIds {
    let applications = policy
        .entries
        .iter()
        .enumerate()
        .map(|(family_index, entry)| {
            let app_ids = (0..=entry.identity.verified_children.len())
                .map(|member_index| vec![family_index as u8 + 1, member_index as u8 + 1])
                .collect();
            VerifiedApplicationAppIds::new(&entry.identity.identity_id, app_ids).unwrap()
        })
        .collect();
    VerifiedPolicyAppIds::new(policy, applications).unwrap()
}

#[test]
fn plan_indexes_every_verified_app_id_without_global_network_filters() {
    let policy = proxy_policy(7);
    let app_ids = verified(&policy);
    let plan = WfpPolicyPlan::new(&policy, &app_ids).unwrap();

    assert_eq!(plan.rules().len(), 3);
    assert_eq!(plan.guard_filters().len(), 6);
    assert_eq!(plan.redirect_filters().len(), 4);
    assert!(plan
        .guard_filters()
        .iter()
        .all(|filter| filter.lifetime() == WfpFilterLifetime::Persistent
            && filter.is_indexed()
            && !filter.app_id().is_empty()));
    assert!(plan
        .redirect_filters()
        .iter()
        .all(|filter| filter.lifetime() == WfpFilterLifetime::Dynamic
            && filter.is_indexed()
            && !filter.app_id().is_empty()));
    assert_eq!(
        plan.guard_filters()
            .iter()
            .map(|filter| filter.layer())
            .collect::<Vec<_>>(),
        vec![
            WfpLayer::AuthConnectV4,
            WfpLayer::AuthConnectV6,
            WfpLayer::AuthConnectV4,
            WfpLayer::AuthConnectV6,
            WfpLayer::AuthConnectV4,
            WfpLayer::AuthConnectV6,
        ]
    );
    assert_eq!(plan.rules()[0].app_id(), &[1, 1]);
    assert_eq!(plan.rules()[1].app_id(), &[1, 2]);
    assert_eq!(plan.rules()[2].action(), StrictAction::Block);
    assert_eq!(plan.target_groups(), &["Proxy-A"]);
    let filter_keys: BTreeSet<_> = plan
        .guard_filters()
        .iter()
        .chain(plan.redirect_filters())
        .map(|filter| filter.key())
        .collect();
    assert_eq!(filter_keys.len(), 10);
    assert!(plan
        .guard_filters()
        .iter()
        .filter(|filter| filter.app_id() == [1, 1])
        .all(|filter| filter.action() == StrictAction::Proxy));
}

#[test]
fn plan_order_is_fail_closed_and_object_deletion_is_allowlisted() {
    let policy = proxy_policy(8);
    let plan = WfpPolicyPlan::new(&policy, &verified(&policy)).unwrap();
    assert_eq!(
        plan.install_steps(),
        &[
            PlanInstallStep::UploadImmutableSnapshot,
            PlanInstallStep::InstallPersistentGuards,
            PlanInstallStep::InstallDynamicRedirects,
        ]
    );
    assert_eq!(
        plan.remove_steps(),
        &[
            PlanRemoveStep::RemoveDynamicRedirects,
            PlanRemoveStep::RemovePersistentGuards,
            PlanRemoveStep::UnloadImmutableSnapshot,
        ]
    );
    for filter in plan.guard_filters().iter().chain(plan.redirect_filters()) {
        assert!(plan.owns_filter_key(filter.key()));
    }
    assert!(!plan.owns_filter_key(WfpObjectKey::from_bytes([0xff; 16])));
}

#[test]
fn block_only_plan_never_installs_redirect_filters() {
    let policy = StrictPolicyBundle::new(
        9,
        vec![StrictPolicyEntry::block(identity(
            "30000000-0000-4000-8000-000000000003",
            r"C:\Apps\Blocked\only.exe",
            'd',
        ))],
    )
    .unwrap();
    let plan = WfpPolicyPlan::new(&policy, &verified(&policy)).unwrap();
    assert!(plan.redirect_filters().is_empty());
    assert_eq!(plan.guard_filters().len(), 2);
    assert_eq!(
        plan.install_steps(),
        &[
            PlanInstallStep::UploadImmutableSnapshot,
            PlanInstallStep::InstallPersistentGuards,
        ]
    );
}

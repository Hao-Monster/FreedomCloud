//! Privileged strict-mode application identity resolution.
//!
//! A UI path is only a selector.  It is never allowed to provide WFP App-ID
//! or signer digests.  This module runs in the elevated Helper and reopens the
//! file before calculating the canonical identity, so the caller receives
//! evidence for the exact file the privileged backend inspected.

use serde::{Deserialize, Serialize};
use std::path::Path;

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct InspectStrictIdentityParams {
    pub path: String,
    pub home_dir: String,
    pub helper_token: String,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ResolvedStrictIdentity {
    pub canonical_path: String,
    pub wfp_app_id_sha256: String,
    pub publisher_certificate_sha256: String,
}

#[cfg(windows)]
pub fn inspect(params: InspectStrictIdentityParams) -> Result<ResolvedStrictIdentity, String> {
    let home_dir = super::hub::validate_home_directory(Some(params.home_dir))?;
    super::hub::validate_helper_token(&home_dir, &params.helper_token)?;
    let identity = flclash_strict_broker::inspect_windows_executable(Path::new(&params.path))
        .map_err(|error| format!("strict identity inspection failed: {error:#}"))?;
    Ok(ResolvedStrictIdentity {
        canonical_path: identity.canonical_path,
        wfp_app_id_sha256: identity.wfp_app_id_sha256,
        publisher_certificate_sha256: identity.publisher_certificate_sha256,
    })
}

#[cfg(not(windows))]
pub fn inspect(_params: InspectStrictIdentityParams) -> Result<ResolvedStrictIdentity, String> {
    Err("strict identity inspection is unavailable on this platform".to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn request_requires_the_authentication_fields() {
        let parsed = serde_json::from_str::<InspectStrictIdentityParams>(
            r#"{"path":"C:\\Apps\\edge.exe","homeDir":"C:\\Users\\test\\AppData\\Roaming\\com.follow\\clashx","helperToken":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}"#,
        )
        .expect("valid inspect request");
        assert_eq!(parsed.path, r#"C:\Apps\edge.exe"#);
        assert!(serde_json::from_str::<InspectStrictIdentityParams>(
            r#"{"path":"C:\\Apps\\edge.exe"}"#
        )
        .is_err());
    }

    #[test]
    fn response_serializes_only_verified_evidence() {
        let response = ResolvedStrictIdentity {
            canonical_path: r#"C:\Apps\edge.exe"#.into(),
            wfp_app_id_sha256: "a".repeat(64),
            publisher_certificate_sha256: "b".repeat(64),
        };
        let json = serde_json::to_value(response).expect("serialize response");
        assert_eq!(json["canonicalPath"], r#"C:\Apps\edge.exe"#);
        assert!(json.get("helperToken").is_none());
    }
}

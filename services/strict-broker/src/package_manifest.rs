use anyhow::{bail, Context, Result};
use serde::Deserialize;

const PACKAGE_MANIFEST_PROTOCOL: u32 = 2;
const MAX_PACKAGE_MANIFEST_BYTES: usize = 16 * 1024;

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StrictPackageManifest {
    protocol: u32,
    package_version: String,
    driver_build_id: String,
    driver_file_sha256: String,
    driver_publisher_certificate_sha256: String,
    broker_file_sha256: String,
    broker_publisher_certificate_sha256: String,
    agent_file_sha256: String,
    agent_publisher_certificate_sha256: String,
    core_file_sha256: String,
    core_publisher_certificate_sha256: String,
}

impl StrictPackageManifest {
    #[cfg(feature = "production-host")]
    pub fn embedded() -> Result<Self> {
        Self::parse(include_bytes!(concat!(
            env!("OUT_DIR"),
            "/strict-package-manifest.json"
        )))
    }

    pub fn parse(bytes: &[u8]) -> Result<Self> {
        if bytes.is_empty() || bytes.len() > MAX_PACKAGE_MANIFEST_BYTES {
            bail!("strict package manifest size is invalid");
        }
        let manifest: Self =
            serde_json::from_slice(bytes).context("parse embedded strict package manifest")?;
        manifest.validate()?;
        Ok(manifest)
    }

    pub fn package_version(&self) -> &str {
        &self.package_version
    }

    pub fn driver_build_id(&self) -> &str {
        &self.driver_build_id
    }

    pub fn driver_file_sha256(&self) -> &str {
        &self.driver_file_sha256
    }

    pub fn driver_publisher_certificate_sha256(&self) -> &str {
        &self.driver_publisher_certificate_sha256
    }

    pub fn agent_publisher_certificate_sha256(&self) -> &str {
        &self.agent_publisher_certificate_sha256
    }

    pub fn broker_file_sha256(&self) -> &str {
        &self.broker_file_sha256
    }

    pub fn broker_publisher_certificate_sha256(&self) -> &str {
        &self.broker_publisher_certificate_sha256
    }

    pub fn agent_file_sha256(&self) -> &str {
        &self.agent_file_sha256
    }

    pub fn core_file_sha256(&self) -> &str {
        &self.core_file_sha256
    }

    pub fn core_publisher_certificate_sha256(&self) -> &str {
        &self.core_publisher_certificate_sha256
    }

    fn validate(&self) -> Result<()> {
        if self.protocol != PACKAGE_MANIFEST_PROTOCOL {
            bail!("unsupported strict package manifest protocol");
        }
        if self.package_version.is_empty()
            || self.package_version.len() > 64
            || !self.package_version.is_ascii()
            || !self
                .package_version
                .bytes()
                .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'+' | b'-'))
        {
            bail!("strict package version is invalid");
        }
        validate_hex(&self.driver_build_id, 32, "driver build ID")?;
        validate_hex(&self.driver_file_sha256, 64, "driver file digest")?;
        validate_hex(
            &self.driver_publisher_certificate_sha256,
            64,
            "driver publisher certificate digest",
        )?;
        validate_hex(&self.broker_file_sha256, 64, "Broker file digest")?;
        validate_hex(
            &self.broker_publisher_certificate_sha256,
            64,
            "Broker publisher certificate digest",
        )?;
        validate_hex(&self.agent_file_sha256, 64, "Agent file digest")?;
        validate_hex(
            &self.agent_publisher_certificate_sha256,
            64,
            "Agent publisher certificate digest",
        )?;
        validate_hex(&self.core_file_sha256, 64, "Core file digest")?;
        validate_hex(
            &self.core_publisher_certificate_sha256,
            64,
            "Core publisher certificate digest",
        )?;
        Ok(())
    }
}

fn validate_hex(value: &str, length: usize, label: &str) -> Result<()> {
    if value.len() != length
        || !value.bytes().all(|byte| byte.is_ascii_hexdigit())
        || value.bytes().all(|byte| byte == b'0')
    {
        bail!("strict package {label} is invalid");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn manifest() -> Vec<u8> {
        format!(
            r#"{{"protocol":2,"packageVersion":"1.2.3-m3","driverBuildId":"{}","driverFileSha256":"{}","driverPublisherCertificateSha256":"{}","brokerFileSha256":"{}","brokerPublisherCertificateSha256":"{}","agentFileSha256":"{}","agentPublisherCertificateSha256":"{}","coreFileSha256":"{}","corePublisherCertificateSha256":"{}"}}"#,
            "12".repeat(16),
            "23".repeat(32),
            "34".repeat(32),
            "45".repeat(32),
            "56".repeat(32),
            "67".repeat(32),
            "78".repeat(32),
            "89".repeat(32),
            "9a".repeat(32),
        )
        .into_bytes()
    }

    #[test]
    fn accepts_an_exact_bounded_package_identity() {
        let parsed = StrictPackageManifest::parse(&manifest()).unwrap();
        assert_eq!(parsed.package_version(), "1.2.3-m3");
        assert_eq!(parsed.driver_build_id(), "12".repeat(16));
        assert_eq!(parsed.driver_file_sha256(), "23".repeat(32));
        assert_eq!(
            parsed.driver_publisher_certificate_sha256(),
            "34".repeat(32)
        );
        assert_eq!(parsed.broker_file_sha256(), "45".repeat(32));
        assert_eq!(
            parsed.broker_publisher_certificate_sha256(),
            "56".repeat(32)
        );
        assert_eq!(parsed.agent_file_sha256(), "67".repeat(32));
        assert_eq!(parsed.agent_publisher_certificate_sha256(), "78".repeat(32));
        assert_eq!(parsed.core_file_sha256(), "89".repeat(32));
        assert_eq!(parsed.core_publisher_certificate_sha256(), "9a".repeat(32));
    }

    #[test]
    fn rejects_unknown_fields_zero_identities_and_oversized_input() {
        let mut unknown: serde_json::Value = serde_json::from_slice(&manifest()).unwrap();
        unknown["driverPath"] = serde_json::Value::String(r"C:\arbitrary.sys".into());
        assert!(StrictPackageManifest::parse(&serde_json::to_vec(&unknown).unwrap()).is_err());

        let mut zero: serde_json::Value = serde_json::from_slice(&manifest()).unwrap();
        zero["driverFileSha256"] = serde_json::Value::String("0".repeat(64));
        assert!(StrictPackageManifest::parse(&serde_json::to_vec(&zero).unwrap()).is_err());
        assert!(StrictPackageManifest::parse(&vec![b'x'; MAX_PACKAGE_MANIFEST_BYTES + 1]).is_err());
    }

    #[test]
    fn package_identity_requires_a_pinned_core() {
        let mut missing: serde_json::Value = serde_json::from_slice(&manifest()).unwrap();
        missing.as_object_mut().unwrap().remove("coreFileSha256");
        assert!(StrictPackageManifest::parse(&serde_json::to_vec(&missing).unwrap()).is_err());

        let mut missing: serde_json::Value = serde_json::from_slice(&manifest()).unwrap();
        missing
            .as_object_mut()
            .unwrap()
            .remove("corePublisherCertificateSha256");
        assert!(StrictPackageManifest::parse(&serde_json::to_vec(&missing).unwrap()).is_err());

        let mut missing = serde_json::from_slice::<serde_json::Value>(&manifest()).unwrap();
        missing
            .as_object_mut()
            .unwrap()
            .remove("brokerPublisherCertificateSha256");
        assert!(StrictPackageManifest::parse(&serde_json::to_vec(&missing).unwrap()).is_err());
    }

    #[cfg(feature = "production-host")]
    #[test]
    fn production_feature_embeds_a_validated_manifest() {
        let embedded = StrictPackageManifest::embedded().unwrap();
        assert_eq!(embedded.driver_build_id().len(), 32);
        assert_eq!(embedded.driver_file_sha256().len(), 64);
        assert_eq!(embedded.agent_file_sha256().len(), 64);
        assert_eq!(embedded.core_file_sha256().len(), 64);
    }
}

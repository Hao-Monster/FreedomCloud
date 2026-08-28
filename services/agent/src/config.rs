use std::ffi::OsString;
use std::path::{Path, PathBuf};

use anyhow::{anyhow, bail, Context, Result};

const CORE_FILE_NAME: &str = if cfg!(windows) {
    "FlClashCore.exe"
} else {
    "FlClashCore"
};

#[derive(Debug, Clone)]
pub struct AgentConfig {
    pub home: PathBuf,
    pub core: PathBuf,
    pub service_core: Option<PathBuf>,
    pub helper_port: u16,
    pub use_helper: bool,
}

impl AgentConfig {
    pub fn parse() -> Result<Self> {
        Self::parse_from(std::env::args_os().skip(1), &std::env::current_exe()?)
    }

    pub fn parse_from(
        args: impl IntoIterator<Item = OsString>,
        agent_executable: &Path,
    ) -> Result<Self> {
        let mut home = None;
        let mut core = None;
        let mut service_core = None;
        let mut helper_port = 47_890;
        let mut use_helper = false;
        let mut args = args.into_iter();

        while let Some(argument) = args.next() {
            match argument.to_string_lossy().as_ref() {
                "--home" => home = Some(PathBuf::from(next_value(&mut args, "--home")?)),
                "--core" => core = Some(PathBuf::from(next_value(&mut args, "--core")?)),
                "--service-core" => {
                    service_core = Some(PathBuf::from(next_value(&mut args, "--service-core")?))
                }
                "--helper-port" => {
                    helper_port = next_value(&mut args, "--helper-port")?
                        .to_string_lossy()
                        .parse::<u16>()
                        .context("--helper-port must be between 1 and 65535")?;
                    if helper_port == 0 {
                        bail!("--helper-port must be between 1 and 65535");
                    }
                }
                "--use-helper" => use_helper = true,
                other => bail!("unknown argument: {other}"),
            }
        }

        let home = canonical_directory(home.context("--home is required")?)?;
        let core = core.context("--core is required")?;
        let core = validate_local_core(agent_executable, &core)?;
        let service_core = service_core.map(|path| canonical_core(&path)).transpose()?;
        if use_helper && service_core.is_none() {
            bail!("--service-core is required with --use-helper");
        }

        Ok(Self {
            home,
            core,
            service_core,
            helper_port,
            use_helper,
        })
    }
}

fn next_value(args: &mut impl Iterator<Item = OsString>, option: &str) -> Result<OsString> {
    args.next()
        .ok_or_else(|| anyhow!("{option} requires a value"))
}

fn canonical_directory(path: PathBuf) -> Result<PathBuf> {
    let canonical = path
        .canonicalize()
        .with_context(|| format!("invalid home directory: {}", path.display()))?;
    if !canonical.is_dir() {
        bail!("home path is not a directory");
    }
    Ok(canonical)
}

fn canonical_core(path: &Path) -> Result<PathBuf> {
    let canonical = path
        .canonicalize()
        .with_context(|| format!("invalid Core executable: {}", path.display()))?;
    if !canonical.is_file()
        || canonical.file_name().and_then(|value| value.to_str()) != Some(CORE_FILE_NAME)
    {
        bail!("Core executable must be named {CORE_FILE_NAME}");
    }
    Ok(canonical)
}

pub fn validate_local_core(agent_executable: &Path, core: &Path) -> Result<PathBuf> {
    let agent = agent_executable
        .canonicalize()
        .context("unable to resolve Agent executable")?;
    let core = canonical_core(core)?;
    if agent.parent() != core.parent() && !is_macos_application_support_core(&core) {
        bail!("local Core must be installed beside FlClashAgent");
    }
    Ok(core)
}

#[cfg(target_os = "macos")]
fn is_macos_application_support_core(core: &Path) -> bool {
    let components = core
        .components()
        .map(|component| component.as_os_str().to_string_lossy().into_owned())
        .collect::<Vec<_>>();
    let expected = [
        "Library".to_owned(),
        "Application Support".to_owned(),
        "com.follow.clash".to_owned(),
        "cores".to_owned(),
        CORE_FILE_NAME.to_owned(),
    ];
    components.ends_with(&expected)
}

#[cfg(not(target_os = "macos"))]
fn is_macos_application_support_core(_core: &Path) -> bool {
    false
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::time::{SystemTime, UNIX_EPOCH};

    struct TempDir(PathBuf);

    impl TempDir {
        fn new() -> Self {
            let nonce = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos();
            let path = std::env::temp_dir().join(format!(
                "flclashx-agent-config-{}-{nonce}",
                std::process::id()
            ));
            fs::create_dir_all(&path).unwrap();
            Self(path)
        }
    }

    impl Drop for TempDir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    #[test]
    fn local_core_is_restricted_to_the_agent_directory() {
        let install = TempDir::new();
        let outside = TempDir::new();
        let agent = install.0.join(if cfg!(windows) {
            "FlClashAgent.exe"
        } else {
            "FlClashAgent"
        });
        let core = install.0.join(CORE_FILE_NAME);
        let outside_core = outside.0.join(CORE_FILE_NAME);
        fs::write(&agent, b"agent").unwrap();
        fs::write(&core, b"core").unwrap();
        fs::write(&outside_core, b"core").unwrap();

        assert_eq!(
            validate_local_core(&agent, &core).unwrap(),
            core.canonicalize().unwrap()
        );
        assert!(validate_local_core(&agent, &outside_core).is_err());
    }
}

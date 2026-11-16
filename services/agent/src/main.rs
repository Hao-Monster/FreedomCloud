use flclash_agent::{config::AgentConfig, logging, runtime};

#[tokio::main(flavor = "current_thread")]
async fn main() {
    let result = match AgentConfig::parse() {
        Ok(config) => runtime::run(config).await,
        Err(error) => Err(error),
    };
    if let Err(error) = result {
        logging::log_bootstrap_failure(format!("{error:#}"));
        eprintln!(
            "{}: {error:#}",
            if cfg!(windows) {
                "FreedomNetAgent"
            } else {
                "FlClashAgent"
            }
        );
        std::process::exit(2);
    }
}

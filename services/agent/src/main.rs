use flclash_agent::{config::AgentConfig, runtime};

#[tokio::main(flavor = "multi_thread", worker_threads = 2)]
async fn main() {
    let result = match AgentConfig::parse() {
        Ok(config) => runtime::run(config).await,
        Err(error) => Err(error),
    };
    if let Err(error) = result {
        eprintln!("FlClashAgent: {error:#}");
        std::process::exit(2);
    }
}

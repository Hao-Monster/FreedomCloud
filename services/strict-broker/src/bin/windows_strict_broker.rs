#[cfg(not(windows))]
compile_error!("FlClashStrictBroker is a Windows-only service executable");

#[cfg(windows)]
fn main() {
    if let Err(error) = flclash_strict_broker::run_windows_strict_broker_service() {
        eprintln!("FlClashStrictBroker: {error:#}");
        std::process::exit(1);
    }
}

use std::env;
use std::fs;
use std::path::PathBuf;

const MANIFEST_ENV: &str = "FLCLASH_STRICT_PACKAGE_MANIFEST";
const EMBEDDED_NAME: &str = "strict-package-manifest.json";
const MAX_MANIFEST_BYTES: u64 = 16 * 1024;

fn main() {
    println!("cargo:rerun-if-env-changed={MANIFEST_ENV}");
    if env::var_os("CARGO_FEATURE_PRODUCTION_HOST").is_none() {
        return;
    }
    let source = env::var_os(MANIFEST_ENV)
        .map(PathBuf::from)
        .unwrap_or_else(|| panic!("{MANIFEST_ENV} is mandatory for production-host builds"));
    if !source.is_absolute() {
        panic!("{MANIFEST_ENV} must be an absolute path");
    }
    println!("cargo:rerun-if-changed={}", source.display());
    let metadata = fs::symlink_metadata(&source)
        .unwrap_or_else(|error| panic!("inspect strict package manifest: {error}"));
    if !metadata.file_type().is_file()
        || metadata.file_type().is_symlink()
        || metadata.len() == 0
        || metadata.len() > MAX_MANIFEST_BYTES
    {
        panic!("strict package manifest must be a nonempty bounded plain file");
    }
    let output_directory = PathBuf::from(env::var_os("OUT_DIR").expect("Cargo OUT_DIR is missing"));
    let output = output_directory.join(EMBEDDED_NAME);
    fs::copy(&source, output)
        .unwrap_or_else(|error| panic!("embed strict package manifest: {error}"));
}

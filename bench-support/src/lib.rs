//! Process, sampling and report helpers shared by the historical benchmark suites.
use anyhow::{anyhow, ensure, Context, Result};
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::{
    fs,
    io::Write,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    time::Instant,
};

/// Convert mixed path and text arguments into a fixed-size command line.
#[macro_export]
macro_rules! args_array {
    ($($arg:expr),* $(,)?) => {
        [$(std::ffi::OsStr::new(&$arg).to_string_lossy().into_owned()),*]
    };
}
/// Create a command line that can grow as flags are selected.
#[macro_export]
macro_rules! argv {
    ($($arg:expr),* $(,)?) => {
        Vec::from($crate::args_array![$($arg),*])
    };
}
pub fn command(args: &[String]) -> Command {
    let mut c = Command::new(&args[0]);
    c.args(&args[1..]);
    c
}
pub fn output(c: &mut Command) -> Result<String> {
    let out = c.output().with_context(|| format!("starting {c:?}"))?;
    ensure!(
        out.status.success(),
        "{c:?} exited {}: {}",
        out.status,
        String::from_utf8_lossy(&out.stderr)
    );
    Ok(String::from_utf8(out.stdout)?.trim().to_owned())
}
pub fn run(args: &[String]) -> Result<String> {
    output(&mut command(args))
}
pub fn logged(args: &[String], log: &fs::File) -> Result<String> {
    output(command(args).stderr(log.try_clone()?))
}
pub fn combined(c: &mut Command, log: &fs::File) -> Result<std::process::ExitStatus> {
    c.stdout(log.try_clone()?)
        .stderr(log.try_clone()?)
        .status()
        .with_context(|| format!("starting {c:?}"))
}
pub fn measured<T>(f: impl FnOnce() -> Result<T>) -> Result<(T, f64)> {
    let start = Instant::now();
    let value = f()?;
    Ok((value, start.elapsed().as_secs_f64()))
}
pub fn read_json(p: &Path) -> Result<Value> {
    serde_json::from_reader(fs::File::open(p).with_context(|| p.display().to_string())?)
        .with_context(|| p.display().to_string())
}
pub fn save(p: &Path, v: &Value) -> Result<()> {
    let mut temp = tempfile::NamedTempFile::new_in(
        p.parent()
            .filter(|p| !p.as_os_str().is_empty())
            .unwrap_or(Path::new(".")),
    )?;
    serde_json::to_writer_pretty(&mut temp, v)?;
    writeln!(temp)?;
    temp.persist(p)?;
    Ok(())
}
pub fn pretty(v: &Value) -> Result<()> {
    println!("{}", serde_json::to_string_pretty(v)?);
    Ok(())
}
pub fn median(mut values: Vec<f64>) -> Result<f64> {
    ensure!(!values.is_empty(), "no samples");
    values.sort_by(f64::total_cmp);
    Ok((values[(values.len() - 1) / 2] + values[values.len() / 2]) / 2.)
}
pub fn stats<'a>(rows: impl IntoIterator<Item = &'a Value>, field: &str) -> Result<f64> {
    median(
        rows.into_iter()
            .map(|r| {
                r[field]
                    .as_f64()
                    .ok_or_else(|| anyhow!("missing sample field {field}"))
            })
            .collect::<Result<_>>()?,
    )
}
pub fn alternating<T: Clone>(v: &[T], trial: usize) -> Vec<T> {
    let mut order = v.to_vec();
    if trial % 2 == 1 {
        order.reverse();
    }
    order
}
pub fn sha256(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}
pub fn nix_string(s: &str) -> String {
    serde_json::to_string(s)
        .expect("string serialization")
        .replace("${", "\\${")
}
pub fn quote_path(p: &Path) -> Result<String> {
    Ok(nix_string(p.to_str().context("non-UTF-8 Nix path")?))
}
pub fn empty_dir(path: Option<&Path>, prefix: &str) -> Result<PathBuf> {
    let p = match path {
        Some(p) => {
            fs::create_dir_all(p)?;
            p.canonicalize()?
        }
        None => tempfile::Builder::new().prefix(prefix).tempdir()?.keep(),
    };
    ensure!(
        p.read_dir()?.next().is_none(),
        "output directory must be empty: {}",
        p.display()
    );
    eprintln!("Benchmark output: {}", p.display());
    Ok(p)
}
pub fn fresh_dir(p: &Path) -> Result<()> {
    if let Some(parent) = p.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::create_dir(p).with_context(|| format!("creating fresh {}", p.display()))
}
pub fn nonce() -> Result<String> {
    let scratch = tempfile::Builder::new().rand_bytes(16).tempdir()?;
    Ok(sha256(scratch.path().as_os_str().as_encoded_bytes())[..12].into())
}
pub fn log_file(out: &Path, name: &str) -> Result<fs::File> {
    Ok(fs::File::create(out.join(name))?)
}
pub fn safe_label(s: &str) -> bool {
    !s.is_empty() && s != "." && s != ".." && Path::new(s).file_name().is_some_and(|n| n == s)
}
pub fn copy_tree(from: &Path, to: &Path, dereference: bool) -> Result<()> {
    fs::create_dir_all(to)?;
    let flag = if dereference { "-RLp" } else { "-RPp" };
    run(&args_array!["cp", flag, "--", from.join("."), to])?;
    Ok(())
}
pub fn quiet(c: &mut Command) -> Result<()> {
    let status = c.stdout(Stdio::null()).status()?;
    ensure!(status.success(), "{c:?} exited {status}");
    Ok(())
}

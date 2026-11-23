use std::env;
use std::io;
use std::os::unix::fs::symlink;

fn main() -> io::Result<()> {
    let mut args = env::args_os().skip(1);
    let source = args.next().ok_or_else(|| io::Error::other("missing target"))?;
    let output = env::var_os("out").ok_or_else(|| io::Error::other("missing output"))?;
    symlink(source, output)
}

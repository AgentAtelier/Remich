//! Asset path types and the `repo_path!` macro.

use crate::{AnvilCoreError, ErrorCode, FailureClass};
use serde::{Deserialize, Serialize};
use std::fmt;
use std::path::{Path, PathBuf};

// ---------------------------------------------------------------------------
// repo_root_from_manifest – non‑panicking repo‑root resolver
// ---------------------------------------------------------------------------

/// Resolves the repo root from a crate's own `CARGO_MANIFEST_DIR`.
///
/// Every Anvil crate sits exactly 2 levels below the repo root:
///
/// ```text
/// <repo_root>
///   ├── crates/
///   │    ├── anvil_core/
///   │    ├── anvil_world/
///   │    └── …
///   ├── apps/
///   │    └── anvil_cli/
///   └── assets/
/// ```
///
/// Use the `repo_path!` macro instead of calling this function directly,
/// as the macro ensures `CARGO_MANIFEST_DIR` is captured at the call site.
#[doc(hidden)]
#[allow(clippy::result_large_err)]
pub fn repo_root_from_manifest(manifest_dir: &str) -> Result<PathBuf, AnvilCoreError> {
    let root = Path::new(manifest_dir)
        .parent()
        .and_then(|p| p.parent())
        .ok_or_else(|| {
            AnvilCoreError::validation(
                FailureClass::Structural,
                ErrorCode::new("E022"),
                "repo_root",
                "manifest_dir",
                manifest_dir.to_string(),
                "unable to resolve repo root – expected crate at depth 2 (crates/<name>/ or apps/<name>/)",
            )
        })?;

    Ok(root.to_path_buf())
}

// ---------------------------------------------------------------------------
// repo_path! macro
// ---------------------------------------------------------------------------

/// Resolves a repo‑relative path anchored at the calling crate's
/// `CARGO_MANIFEST_DIR`.
///
/// All Anvil crates sit 2 levels below the repo root
/// (`crates/<name>/` or `apps/<name>/`), so this macro climbs 2 levels then
/// joins the provided segments.
///
/// # Panics
///
/// Panics if the directory structure does not match the expected layout
/// (should never happen in CI or normal usage).
///
/// # Examples
///
/// ```no_run
/// use anvil_core::repo_path;
/// let catalogue = repo_path!("assets/catalogue.json");
/// let scenario  = repo_path!("scenarios", "expedition", "world.json");
/// ```
#[macro_export]
macro_rules! repo_path {
    ($path:literal) => {{
        anvil_core::path::repo_root_from_manifest(env!("CARGO_MANIFEST_DIR"))
            .expect("Failed to determine repository root. \
The crate must be located exactly two levels below the workspace root, \
e.g. `crates/anvil_core`. If the directory structure has changed, update \n`repo_root_from_manifest`.")
            .join($path)
    }};
    ($($seg:expr),+ $(,)?) => {{
        let mut p = anvil_core::path::repo_root_from_manifest(env!("CARGO_MANIFEST_DIR"))
                        .expect("Failed to determine repository root. \
The crate must be located exactly two levels below the workspace root, \
e.g. `crates/anvil_core`. If the directory structure has changed, update \n`repo_root_from_manifest`.");
        $(p = p.join($seg);)+
        p
    }};
}

// ---------------------------------------------------------------------------
// AssetPath – validated, typed asset path
// ---------------------------------------------------------------------------

/// A filesystem path to a validated asset.
///
/// Serialised transparently as a plain string.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(transparent)]
pub struct AssetPath(PathBuf);

impl AssetPath {
    /// Creates a new `AssetPath`, rejecting empty paths.
    ///
    /// **Note:** The path's existence on disk is **not** checked here;
    /// that validation belongs to the asset catalogue.  See
    /// `AssetCatalogue::validate_paths()`.
    #[allow(clippy::result_large_err)]
    pub fn new(path: impl Into<PathBuf>) -> Result<Self, AnvilCoreError> {
        let path: PathBuf = path.into();

        if path.as_os_str().is_empty() {
            return Err(AnvilCoreError::validation(
                FailureClass::Asset,
                ErrorCode::new("E023"),
                "AssetPath",
                "path",
                format!("{:?}", path),
                "asset path cannot be empty",
            ));
        }

        Ok(Self(path))
    }

    // -- accessors -------------------------------------------------------

    /// Returns a reference to the inner `Path`.
    pub fn as_path(&self) -> &Path {
        self.0.as_path()
    }

    /// Returns the file extension, if any.
    pub fn extension(&self) -> Option<&str> {
        self.0.extension().and_then(|s| s.to_str())
    }

    /// Returns the file stem (filename without extension), if any.
    pub fn file_stem(&self) -> Option<&str> {
        self.0.file_stem().and_then(|s| s.to_str())
    }
}

// ---------------------------------------------------------------------------
// Trait implementations
// ---------------------------------------------------------------------------

impl fmt::Display for AssetPath {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0.display())
    }
}

impl AsRef<Path> for AssetPath {
    fn as_ref(&self) -> &Path {
        self.0.as_path()
    }
}

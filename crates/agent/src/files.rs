use std::fs;
use std::path::{Component, Path, PathBuf};

use proto_gen::{DirListing, FileContent, FileEntry, FileMutationAck, FileWriteAck};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileServiceError {
    code: &'static str,
    message: String,
}

impl FileServiceError {
    pub fn new(code: &'static str, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
        }
    }

    pub fn code(&self) -> &'static str {
        self.code
    }

    pub fn message(&self) -> &str {
        &self.message
    }
}

pub struct FileService;

impl FileService {
    pub fn list_dir(
        working_dir: &Path,
        path: &str,
        _recursive: bool,
        _max_depth: u32,
    ) -> Result<DirListing, FileServiceError> {
        let session_root = canonical_session_root(working_dir)?;
        let target = resolve_existing_path(&session_root, path, true)?;
        if !target.is_dir() {
            return Err(FileServiceError::new(
                "FILE_UNSUPPORTED_TYPE",
                format!("'{}' is not a directory", path),
            ));
        }

        let mut entries = fs::read_dir(&target)
            .map_err(|error| {
                FileServiceError::new(
                    "FILE_NOT_FOUND",
                    format!("failed to read directory '{}': {error}", display_relative(path)),
                )
            })?
            .filter_map(|entry| entry.ok())
            .filter_map(|entry| {
                let metadata = entry.metadata().ok()?;
                let file_name = entry.file_name().to_string_lossy().into_owned();
                let relative_path = relative_path(&session_root, &entry.path()).ok()?;
                Some(FileEntry {
                    name: file_name,
                    path: relative_path,
                    is_dir: metadata.is_dir(),
                    size: if metadata.is_file() { metadata.len() } else { 0 },
                    modified_ms: metadata
                        .modified()
                        .ok()
                        .and_then(|time| time.duration_since(std::time::UNIX_EPOCH).ok())
                        .map(|duration| duration.as_millis() as u64)
                        .unwrap_or(0),
                })
            })
            .collect::<Vec<_>>();

        entries.sort_by(|left, right| {
            right.is_dir.cmp(&left.is_dir).then_with(|| left.name.cmp(&right.name))
        });

        Ok(DirListing { entries })
    }

    pub fn read_file(
        working_dir: &Path,
        path: &str,
        offset: u64,
        length: u64,
    ) -> Result<FileContent, FileServiceError> {
        let session_root = canonical_session_root(working_dir)?;
        let target = resolve_existing_path(&session_root, path, false)?;
        if target.is_dir() {
            return Err(FileServiceError::new(
                "FILE_UNSUPPORTED_TYPE",
                format!("'{}' is a directory", display_relative(path)),
            ));
        }

        let metadata = fs::metadata(&target).map_err(|error| {
            FileServiceError::new(
                "FILE_NOT_FOUND",
                format!("failed to read metadata for '{}': {error}", display_relative(path)),
            )
        })?;
        if metadata.len() > 1_048_576 {
            return Err(FileServiceError::new(
                "FILE_TOO_LARGE",
                format!("'{}' exceeds the 1 MiB read limit", display_relative(path)),
            ));
        }

        let contents = fs::read(&target).map_err(|error| {
            FileServiceError::new(
                "FILE_NOT_FOUND",
                format!("failed to read '{}': {error}", display_relative(path)),
            )
        })?;

        if contents.iter().take(8192).any(|byte| *byte == 0) {
            return Err(FileServiceError::new(
                "FILE_UNSUPPORTED_TYPE",
                format!("'{}' is not a supported text file", display_relative(path)),
            ));
        }

        let start = usize::try_from(offset).unwrap_or(usize::MAX).min(contents.len());
        let end = if length == 0 {
            contents.len()
        } else {
            start.saturating_add(usize::try_from(length).unwrap_or(usize::MAX)).min(contents.len())
        };

        Ok(FileContent {
            path: normalize_relative_path(path)?,
            content: contents[start..end].to_vec(),
            mime_type: "text/plain".to_owned(),
        })
    }

    pub fn write_file(
        working_dir: &Path,
        path: &str,
        content: &[u8],
    ) -> Result<FileWriteAck, FileServiceError> {
        let session_root = canonical_session_root(working_dir)?;
        let target = resolve_existing_path(&session_root, path, false)?;
        if target.is_dir() {
            return Err(FileServiceError::new(
                "FILE_UNSUPPORTED_TYPE",
                format!("'{}' is a directory", display_relative(path)),
            ));
        }

        fs::write(&target, content).map_err(|error| {
            FileServiceError::new(
                "FILE_WRITE_FAILED",
                format!("failed to write '{}': {error}", display_relative(path)),
            )
        })?;

        Ok(FileWriteAck {
            path: normalize_relative_path(path)?,
            success: true,
        })
    }

    pub fn create_file(
        working_dir: &Path,
        path: &str,
    ) -> Result<FileMutationAck, FileServiceError> {
        let session_root = canonical_session_root(working_dir)?;
        let target = resolve_new_path(&session_root, path)?;
        ensure_parent_exists(&target)?;

        fs::write(&target, []).map_err(|error| {
            FileServiceError::new(
                "FILE_WRITE_FAILED",
                format!("failed to create '{}': {error}", display_relative(path)),
            )
        })?;

        Ok(FileMutationAck {
            path: normalize_relative_path(path)?,
            success: true,
            message: "created".to_owned(),
        })
    }

    pub fn create_dir(
        working_dir: &Path,
        path: &str,
    ) -> Result<FileMutationAck, FileServiceError> {
        let session_root = canonical_session_root(working_dir)?;
        let target = resolve_new_path(&session_root, path)?;
        ensure_parent_exists(&target)?;

        fs::create_dir(&target).map_err(|error| {
            FileServiceError::new(
                "FILE_WRITE_FAILED",
                format!("failed to create directory '{}': {error}", display_relative(path)),
            )
        })?;

        Ok(FileMutationAck {
            path: normalize_relative_path(path)?,
            success: true,
            message: "created".to_owned(),
        })
    }

    pub fn delete_path(
        working_dir: &Path,
        path: &str,
        recursive: bool,
    ) -> Result<FileMutationAck, FileServiceError> {
        let session_root = canonical_session_root(working_dir)?;
        let normalized = normalize_relative_path(path)?;
        if normalized.is_empty() {
            return Err(FileServiceError::new(
                "FILE_PATH_OUT_OF_BOUNDS",
                "cannot delete session root",
            ));
        }
        let target = resolve_existing_path(&session_root, &normalized, true)?;

        let result = if target.is_dir() {
            let mut entries = fs::read_dir(&target).map_err(|error| {
                FileServiceError::new(
                    "FILE_DELETE_FAILED",
                    format!("failed to inspect directory '{}': {error}", display_relative(path)),
                )
            })?;
            if entries.next().is_some() && !recursive {
                return Err(FileServiceError::new(
                    "FILE_NOT_EMPTY",
                    format!("directory '{}' is not empty", display_relative(path)),
                ));
            }
            if recursive {
                fs::remove_dir_all(&target)
            } else {
                fs::remove_dir(&target)
            }
        } else {
            fs::remove_file(&target)
        };

        result.map_err(|error| {
            FileServiceError::new(
                "FILE_DELETE_FAILED",
                format!("failed to delete '{}': {error}", display_relative(path)),
            )
        })?;

        Ok(FileMutationAck {
            path: normalized,
            success: true,
            message: "deleted".to_owned(),
        })
    }

    pub fn rename_path(
        working_dir: &Path,
        from_path: &str,
        to_path: &str,
    ) -> Result<FileMutationAck, FileServiceError> {
        let session_root = canonical_session_root(working_dir)?;
        let source = resolve_existing_path(&session_root, from_path, true)?;
        let target = resolve_new_path(&session_root, to_path)?;
        ensure_parent_exists(&target)?;

        fs::rename(&source, &target).map_err(|error| {
            FileServiceError::new(
                "FILE_RENAME_FAILED",
                format!(
                    "failed to rename '{}' to '{}': {error}",
                    display_relative(from_path),
                    display_relative(to_path),
                ),
            )
        })?;

        Ok(FileMutationAck {
            path: normalize_relative_path(to_path)?,
            success: true,
            message: "renamed".to_owned(),
        })
    }
}

fn canonical_session_root(working_dir: &Path) -> Result<PathBuf, FileServiceError> {
    if working_dir.as_os_str().is_empty() || !working_dir.exists() || !working_dir.is_dir() {
        return Err(FileServiceError::new(
            "FILE_ROOT_INVALID",
            format!("working dir '{}' is invalid", working_dir.display()),
        ));
    }
    working_dir.canonicalize().map_err(|error| {
        FileServiceError::new(
            "FILE_ROOT_INVALID",
            format!("failed to resolve session root '{}': {error}", working_dir.display()),
        )
    })
}

fn normalize_relative_path(path: &str) -> Result<String, FileServiceError> {
    if path.is_empty() {
        return Ok(String::new());
    }
    let candidate = Path::new(path);
    if candidate.is_absolute() {
        return Err(FileServiceError::new(
            "FILE_PATH_OUT_OF_BOUNDS",
            "absolute paths are not allowed",
        ));
    }

    let mut parts = Vec::new();
    for component in candidate.components() {
        match component {
            Component::Normal(part) => {
                let part = part.to_string_lossy();
                if part.is_empty() {
                    return Err(FileServiceError::new(
                        "FILE_PATH_OUT_OF_BOUNDS",
                        "empty path components are not allowed",
                    ));
                }
                parts.push(part.into_owned());
            }
            Component::CurDir | Component::ParentDir | Component::RootDir | Component::Prefix(_) => {
                return Err(FileServiceError::new(
                    "FILE_PATH_OUT_OF_BOUNDS",
                    format!("path '{}' escapes the session root", path),
                ))
            }
        }
    }
    Ok(parts.join("/"))
}

fn resolve_existing_path(
    session_root: &Path,
    path: &str,
    allow_root: bool,
) -> Result<PathBuf, FileServiceError> {
    let normalized = normalize_relative_path(path)?;
    if normalized.is_empty() {
        if allow_root {
            return Ok(session_root.to_path_buf());
        }
        return Err(FileServiceError::new(
            "FILE_PATH_OUT_OF_BOUNDS",
            "path cannot be empty for this operation",
        ));
    }

    let target = session_root.join(normalized.split('/').collect::<PathBuf>());
    if !target.exists() {
        return Err(FileServiceError::new(
            "FILE_NOT_FOUND",
            format!("'{}' does not exist", display_relative(path)),
        ));
    }

    let canonical_target = target.canonicalize().map_err(|error| {
        FileServiceError::new(
            "FILE_NOT_FOUND",
            format!("failed to resolve '{}': {error}", display_relative(path)),
        )
    })?;
    if !canonical_target.starts_with(session_root) {
        return Err(FileServiceError::new(
            "FILE_PATH_OUT_OF_BOUNDS",
            format!("path '{}' escapes the session root", display_relative(path)),
        ));
    }

    Ok(canonical_target)
}

fn resolve_new_path(session_root: &Path, path: &str) -> Result<PathBuf, FileServiceError> {
    let normalized = normalize_relative_path(path)?;
    if normalized.is_empty() {
        return Err(FileServiceError::new(
            "FILE_PATH_OUT_OF_BOUNDS",
            "path cannot be empty for this operation",
        ));
    }

    let target = session_root.join(normalized.split('/').collect::<PathBuf>());
    if target.exists() {
        return Err(FileServiceError::new(
            "FILE_ALREADY_EXISTS",
            format!("'{}' already exists", display_relative(path)),
        ));
    }
    Ok(target)
}

fn ensure_parent_exists(path: &Path) -> Result<(), FileServiceError> {
    let Some(parent) = path.parent() else {
        return Ok(());
    };
    if !parent.exists() || !parent.is_dir() {
        return Err(FileServiceError::new(
            "FILE_NOT_FOUND",
            format!("parent directory '{}' does not exist", parent.display()),
        ));
    }
    Ok(())
}

fn relative_path(root: &Path, path: &Path) -> Result<String, FileServiceError> {
    let relative = path.strip_prefix(root).map_err(|error| {
        FileServiceError::new(
            "FILE_PATH_OUT_OF_BOUNDS",
            format!("failed to relativize '{}': {error}", path.display()),
        )
    })?;
    let text = relative.to_string_lossy().replace('\\', "/");
    Ok(text)
}

fn display_relative(path: &str) -> &str {
    if path.is_empty() { "<root>" } else { path }
}

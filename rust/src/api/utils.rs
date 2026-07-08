//! Filename/category/code helpers, re-using `bishare_protocol::utils` so naming
//! and code generation match the native apps exactly.

use bishare_protocol::utils::{CodeGenerator, FileCategorizer, FileNameSanitizer, SmartNaming};

/// Path-safe a received filename (strips separators, `..`, control chars).
#[flutter_rust_bridge::frb(sync)]
pub fn sanitize_filename(name: String) -> String {
    FileNameSanitizer::sanitize(&name)
}

/// Coarse category name for a MIME type (image/video/document/…).
#[flutter_rust_bridge::frb(sync)]
pub fn category_name(mime_type: String) -> String {
    FileCategorizer::category_name(&mime_type).to_string()
}

/// A 4-char room code (charset excludes I/O/0/1).
#[flutter_rust_bridge::frb(sync)]
pub fn room_code() -> String {
    CodeGenerator::room_code()
}

/// A transfer code.
#[flutter_rust_bridge::frb(sync)]
pub fn transfer_code() -> String {
    CodeGenerator::transfer_code()
}

/// Smart-rename an incoming file using the sender alias.
#[flutter_rust_bridge::frb(sync)]
pub fn smart_name(original_name: String, sender_alias: String) -> String {
    SmartNaming::format(&original_name, &sender_alias)
}

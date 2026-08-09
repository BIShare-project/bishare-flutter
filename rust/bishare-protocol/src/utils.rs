use crate::constants::{Config, FileCategory};
use chrono::Utc;
use rand::Rng;

/// File name sanitizer — prevents path traversal
pub struct FileNameSanitizer;

impl FileNameSanitizer {
    pub fn sanitize(name: &str) -> String {
        // Extract last path component
        let name = name.rsplit('/').next().unwrap_or(name);
        let name = name.rsplit('\\').next().unwrap_or(name);

        let sanitized = name
            .replace("..", "_")
            .replace('/', "_")
            .replace('\\', "_")
            .replace(':', "_");

        let trimmed = sanitized.trim();
        if trimmed.is_empty() {
            "unnamed".to_string()
        } else {
            trimmed.to_string()
        }
    }
}

/// File categorizer — maps MIME type to category folder
pub struct FileCategorizer;

impl FileCategorizer {
    pub fn category(mime_type: &str) -> FileCategory {
        FileCategory::from_mime(mime_type)
    }

    pub fn category_name(mime_type: &str) -> &'static str {
        FileCategory::from_mime(mime_type).as_str()
    }
}

/// Room/transfer code generator
pub struct CodeGenerator;

impl CodeGenerator {
    /// Generate a random code of given length from the BIShare charset
    pub fn generate(length: usize) -> String {
        let charset = Config::CODE_CHARSET;
        let mut rng = rand::thread_rng();
        (0..length)
            .map(|_| {
                let idx = rng.gen_range(0..charset.len());
                charset[idx] as char
            })
            .collect()
    }

    /// Generate a 4-character room code
    pub fn room_code() -> String {
        Self::generate(Config::ROOM_CODE_LENGTH)
    }

    /// Generate a 6-character transfer code
    pub fn transfer_code() -> String {
        Self::generate(6)
    }

    /// Format code with hyphen (e.g., "ABCDEF" → "ABC-DEF")
    pub fn format_transfer_code(code: &str) -> String {
        if code.len() == 6 {
            format!("{}-{}", &code[..3], &code[3..])
        } else {
            code.to_uppercase()
        }
    }

    /// Normalize code: remove hyphens, uppercase
    pub fn normalize_code(code: &str) -> String {
        code.replace('-', "").to_uppercase()
    }
}

/// Smart file naming: {date}_{sender}_{filename}
pub struct SmartNaming;

impl SmartNaming {
    pub fn format(original_name: &str, sender_alias: &str) -> String {
        let date_str = Utc::now().format("%Y-%m-%d").to_string();
        let safe_sender = sender_alias
            .replace(' ', "-")
            .replace('/', "_")
            .replace(':', "_");

        format!("{}_{}_{}",  date_str, safe_sender, original_name)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sanitize_normal() {
        assert_eq!(FileNameSanitizer::sanitize("photo.jpg"), "photo.jpg");
    }

    #[test]
    fn test_sanitize_path_traversal() {
        // Last path component extracted, ".." in path stripped by split
        assert_eq!(FileNameSanitizer::sanitize("../../etc/passwd"), "passwd");
        // Direct ".." in name replaced
        assert_eq!(FileNameSanitizer::sanitize("..secret.txt"), "_secret.txt");
    }

    #[test]
    fn test_sanitize_empty() {
        assert_eq!(FileNameSanitizer::sanitize(""), "unnamed");
    }

    #[test]
    fn test_sanitize_slashes() {
        assert_eq!(FileNameSanitizer::sanitize("path/to/file.txt"), "file.txt");
    }

    #[test]
    fn test_category_image() {
        assert_eq!(FileCategorizer::category_name("image/jpeg"), "Images");
    }

    #[test]
    fn test_category_video() {
        assert_eq!(FileCategorizer::category_name("video/mp4"), "Videos");
    }

    #[test]
    fn test_category_pdf() {
        assert_eq!(FileCategorizer::category_name("application/pdf"), "Documents");
    }

    #[test]
    fn test_category_zip() {
        assert_eq!(FileCategorizer::category_name("application/zip"), "Archives");
    }

    #[test]
    fn test_category_unknown() {
        assert_eq!(FileCategorizer::category_name("application/octet-stream"), "Other");
    }

    #[test]
    fn test_code_generator_length() {
        let code = CodeGenerator::room_code();
        assert_eq!(code.len(), 4);
        for ch in code.chars() {
            assert!(Config::CODE_CHARSET.contains(&(ch as u8)));
        }
    }

    #[test]
    fn test_format_transfer_code() {
        assert_eq!(CodeGenerator::format_transfer_code("ABCDEF"), "ABC-DEF");
    }

    #[test]
    fn test_normalize_code() {
        assert_eq!(CodeGenerator::normalize_code("abc-def"), "ABCDEF");
    }

    #[test]
    fn test_smart_naming() {
        let name = SmartNaming::format("photo.jpg", "iPhone 16");
        assert!(name.contains("iPhone-16"));
        assert!(name.ends_with("photo.jpg"));
    }

    #[test]
    fn test_compressible() {
        assert!(crate::constants::Config::is_compressible("text/plain"));
        assert!(crate::constants::Config::is_compressible("application/json"));
        assert!(!crate::constants::Config::is_compressible("image/jpeg"));
    }
}

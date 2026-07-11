//! Engine internals (hte-architecture.md §2.2) — pure Rust, never exposed over
//! FRB (codegen scans `crate::api` only). Grows toward the target layout:
//! bufpool (Phase 1c) → adaptive/io/metrics (Phase 2/3).

pub mod bufpool;
pub mod metrics;
pub mod resume;

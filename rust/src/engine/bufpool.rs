//! Fixed slab arena behind an async semaphore — **the hard RAM ceiling** for the
//! transfer data plane (hte-architecture.md §5, Phase 1c).
//!
//! Every transfer buffer (sender pread slabs, receiver chunk-assembly slabs, the
//! legacy single-stream buffers) is acquired from one global pool. `acquire()`
//! suspends the calling task the instant `POOL_SLABS` buffers are outstanding, so
//! app-layer data-plane RAM **cannot exceed `POOL_SLABS × SLAB_SIZE` regardless of
//! file size, stream count, or disk/network speed** — the ceiling is mechanical,
//! not emergent. Freed slabs are reused (no per-chunk alloc/free churn), and slabs
//! are allocated lazily, so an idle app pays nothing.
//!
//! ## Backpressure chain (bounds RAM whichever side is slow)
//! `pool.acquire()` (suspends when full) → quinn stream flow control → peer recv
//! window → `pwrite` speed. A stalled writer idles the reader; nothing accumulates
//! on the heap. No task ever holds more than ONE slab at a time and no slab-free
//! ever requires a slab-acquire, so the pool cannot deadlock — an over-subscribed
//! stream simply waits its turn.
//!
//! ## Published envelope (Phase 1c exit + 2b revision, hte-architecture.md §5)
//! - Pool: `32 slabs × 1 MB = 32 MB` hard app-layer ceiling.
//! - Reachable concurrently AT FULL RATE: **16 slabs per direction** — Phase 2b
//!   sends up to 4 files × 4 streams concurrently (the Dart sender enforces
//!   files × streams ≤ 16), and a device simultaneously RECEIVING the same
//!   pattern uses the other 16. Beyond that, streams queue on the semaphore
//!   (bounded acquire) rather than allocating.
//! - Single size-class (`SLAB_SIZE = MAX_CHUNK = 1 MB`; every negotiated
//!   `chunkSize ≤ 1 MB` fits). The second size-class (compress/decrypt output)
//!   arrives with Phase 2 compression.
//! - Dominant REMAINING data-plane RAM is quinn's windows — tuned in Phase 2a to
//!   32 MB receive/conn (4 MB/stream) + 32 MB send ⇒ worst case ≈ 32 + 32 + 32
//!   ≈ 96 MB per active connection, comfortably under the 200 MB gate.

use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use tokio::sync::Semaphore;

/// Slab size — matches `MAX_CHUNK` (1 MB) so every negotiated chunk fits.
pub const SLAB_SIZE: usize = 1024 * 1024;

/// Hard cap on outstanding slabs (the RAM ceiling: 32 × 1 MB = 32 MB —
/// 16 per direction so full-rate concurrent send AND receive never contend).
pub const POOL_SLABS: usize = 32;

struct PoolInner {
    slab_size: usize,
    sem: Arc<Semaphore>,
    free: Mutex<Vec<Box<[u8]>>>,
    // Stats — proof of the ceiling + reuse, and surfaced to Dart for field checks.
    in_use: AtomicUsize,
    peak_in_use: AtomicUsize,
    allocated: AtomicUsize,
    total_acquires: AtomicU64,
}

/// Semaphore-gated arena of fixed-size reusable buffers.
pub struct SlabPool {
    inner: Arc<PoolInner>,
}

impl SlabPool {
    pub fn new(slab_size: usize, capacity: usize) -> Self {
        Self {
            inner: Arc::new(PoolInner {
                slab_size,
                sem: Arc::new(Semaphore::new(capacity)),
                free: Mutex::new(Vec::with_capacity(capacity)),
                in_use: AtomicUsize::new(0),
                peak_in_use: AtomicUsize::new(0),
                allocated: AtomicUsize::new(0),
                total_acquires: AtomicU64::new(0),
            }),
        }
    }

    /// Acquire a slab with a deadline. This is what the transfer paths use: the
    /// suspension is still the RAM-bounding backpressure, but a pool starved for
    /// longer than `timeout` (e.g. by stalled peers holding slabs) fails the
    /// caller cleanly instead of parking it forever — a parked transfer task
    /// would pin its stream/`.part`/registry state with no way to cancel, which
    /// is exactly the Phase 0 stall bug the idle timeouts exist to prevent.
    pub async fn acquire_timeout(&self, timeout: std::time::Duration) -> Result<Slab, String> {
        tokio::time::timeout(timeout, self.acquire())
            .await
            .map_err(|_| "buffer pool exhausted (acquire timeout)".to_string())
    }

    /// Acquire a slab, suspending until one is available. This suspension IS the
    /// backpressure that bounds data-plane RAM.
    pub async fn acquire(&self) -> Slab {
        let permit = self
            .inner
            .sem
            .clone()
            .acquire_owned()
            .await
            .expect("slab pool semaphore closed");
        let buf = self.inner.free.lock().unwrap().pop().unwrap_or_else(|| {
            self.inner.allocated.fetch_add(1, Ordering::Relaxed);
            vec![0u8; self.inner.slab_size].into_boxed_slice()
        });
        let now = self.inner.in_use.fetch_add(1, Ordering::Relaxed) + 1;
        self.inner.peak_in_use.fetch_max(now, Ordering::Relaxed);
        self.inner.total_acquires.fetch_add(1, Ordering::Relaxed);
        Slab {
            buf: Some(buf),
            pool: self.inner.clone(),
            _permit: permit,
        }
    }

    /// (capacity, allocated, in_use, peak_in_use, total_acquires)
    pub fn stats(&self) -> (usize, usize, usize, usize, u64) {
        (
            self.inner.sem.available_permits() + self.inner.in_use.load(Ordering::Relaxed),
            self.inner.allocated.load(Ordering::Relaxed),
            self.inner.in_use.load(Ordering::Relaxed),
            self.inner.peak_in_use.load(Ordering::Relaxed),
            self.inner.total_acquires.load(Ordering::Relaxed),
        )
    }
}

/// One pooled buffer. Dereferences to `[u8; slab_size]`-sized slice; callers
/// slice to their chunk length. Returns to the pool on drop (RAII) — including
/// when dropped inside a `spawn_blocking` closure.
pub struct Slab {
    buf: Option<Box<[u8]>>,
    pool: Arc<PoolInner>,
    _permit: tokio::sync::OwnedSemaphorePermit,
}

impl Drop for Slab {
    fn drop(&mut self) {
        if let Some(buf) = self.buf.take() {
            self.pool.free.lock().unwrap().push(buf);
        }
        self.pool.in_use.fetch_sub(1, Ordering::Relaxed);
        // `_permit` drops after this body: the buffer is back on the free list
        // before the next waiter is admitted, so it always finds one (or allocs).
    }
}

impl std::ops::Deref for Slab {
    type Target = [u8];
    fn deref(&self) -> &[u8] {
        self.buf.as_ref().expect("slab buffer taken")
    }
}

impl std::ops::DerefMut for Slab {
    fn deref_mut(&mut self) -> &mut [u8] {
        self.buf.as_mut().expect("slab buffer taken")
    }
}

/// The process-wide transfer-buffer pool (the §5 hard ceiling).
pub fn pool() -> &'static SlabPool {
    static P: OnceLock<SlabPool> = OnceLock::new();
    P.get_or_init(|| SlabPool::new(SLAB_SIZE, POOL_SLABS))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rt() -> tokio::runtime::Runtime {
        tokio::runtime::Builder::new_current_thread()
            .enable_time()
            .build()
            .unwrap()
    }

    /// The ceiling is mechanical: a full pool suspends the next acquire until a
    /// slab is returned.
    #[test]
    fn pool_blocks_at_capacity_and_resumes() {
        rt().block_on(async {
            let pool = SlabPool::new(1024, 2);
            let a = pool.acquire().await;
            let _b = pool.acquire().await;
            // Third acquire must NOT complete while 2 are outstanding.
            let blocked =
                tokio::time::timeout(std::time::Duration::from_millis(50), pool.acquire()).await;
            assert!(blocked.is_err(), "acquire must suspend at capacity");
            drop(a);
            // Now it completes promptly.
            let c =
                tokio::time::timeout(std::time::Duration::from_millis(50), pool.acquire()).await;
            assert!(c.is_ok(), "acquire must resume once a slab is returned");
            let (cap, allocated, in_use, peak, acquires) = pool.stats();
            assert_eq!(cap, 2);
            assert!(allocated <= 2, "never allocate beyond capacity");
            assert_eq!(in_use, 2);
            assert_eq!(peak, 2);
            assert_eq!(acquires, 3);
        });
    }

    /// Freed slabs are reused — RAM does not scale with acquire count.
    #[test]
    fn pool_reuses_buffers() {
        rt().block_on(async {
            let pool = SlabPool::new(1024, 4);
            for _ in 0..64 {
                let mut s = pool.acquire().await;
                s[0] = 0xAB; // touch it
            }
            let (_, allocated, in_use, peak, acquires) = pool.stats();
            assert_eq!(allocated, 1, "sequential use must reuse ONE buffer");
            assert_eq!(in_use, 0);
            assert_eq!(peak, 1);
            assert_eq!(acquires, 64);
        });
    }
}

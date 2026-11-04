// 검색 화면 하나의 인덱스와 미리 만드는 작업 스레드
// 잠금은 표를 바꾸거나 항목 목록을 복사할 때만 잡고 항목 생성은 잠금 밖에서 함

use std::collections::HashMap;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Condvar, Mutex, MutexGuard};
use std::thread;

use crate::fold::fold;
use crate::text::{matches, Field};

pub const NAME: usize = 0;
pub const BODY: usize = 1;
pub const TIME0: usize = 2;
pub const TIME1: usize = 3;

#[derive(Clone, Default)]
pub struct ClipEntry {
    pub fields: [Option<Arc<Field>>; 4],
}

#[derive(Default)]
struct Table {
    order: Vec<Arc<ClipEntry>>,
    by_id: HashMap<Vec<u16>, Arc<ClipEntry>>,
}

#[derive(Default)]
struct Request {
    requested: u64,
    handled: u64,
}

struct Shared {
    table: Mutex<Table>,
    generation: AtomicU64,
    closed: AtomicBool,
    request: Mutex<Request>,
    wake: Condvar,
}

pub struct Index {
    shared: Arc<Shared>,
}

// 오염된 잠금도 안의 값을 그대로 씀
fn lock<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    mutex
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

impl Default for Index {
    fn default() -> Self {
        Self::new()
    }
}

impl Index {
    pub fn new() -> Index {
        let shared = Arc::new(Shared {
            table: Mutex::new(Table::default()),
            generation: AtomicU64::new(0),
            closed: AtomicBool::new(false),
            request: Mutex::new(Request::default()),
            wake: Condvar::new(),
        });
        let worker = Arc::clone(&shared);
        thread::Builder::new()
            .name("plyst-search-prebuild".into())
            .spawn(move || run_worker(worker))
            .expect("작업 스레드 생성 실패");
        Index { shared }
    }

    // order 전체와 바뀐 필드만 받음
    // order에 없는 클립은 지움
    // 바뀌었는지는 JS 래퍼가 판단하므로 받은 필드는 모두 새로 만듦
    // 필드는 잠금 밖에서 만들어 받음
    pub fn sync_fields(&self, order: Vec<Vec<u16>>, updates: Vec<(usize, usize, Field)>) {
        let mut table = lock(&self.shared.table);
        let mut by_id: HashMap<Vec<u16>, Arc<ClipEntry>> = HashMap::with_capacity(order.len());
        let mut entries: Vec<ClipEntry> = order
            .iter()
            .map(|id| {
                table
                    .by_id
                    .get(id)
                    .map(|entry| (**entry).clone())
                    .unwrap_or_default()
            })
            .collect();
        let mut changed = vec![false; order.len()];
        for (position, field, text) in updates {
            if position >= entries.len() || field > TIME1 {
                continue;
            }
            entries[position].fields[field] = Some(Arc::new(text));
            changed[position] = true;
        }
        let mut list = Vec::with_capacity(order.len());
        for (position, (id, entry)) in order.iter().zip(entries).enumerate() {
            let value = match table.by_id.get(id) {
                Some(existing) if !changed[position] => Arc::clone(existing),
                _ => Arc::new(entry),
            };
            by_id.insert(id.clone(), Arc::clone(&value));
            list.push(value);
        }
        table.order = list;
        table.by_id = by_id;
    }

    // 현재 order로 미리 만들기 시작
    // 이전 세대는 멈춤
    pub fn prebuild(&self) {
        let generation = self.shared.generation.fetch_add(1, Ordering::SeqCst) + 1;
        let mut request = lock(&self.shared.request);
        request.requested = generation;
        self.shared.wake.notify_all();
    }

    pub fn cancel_prebuild(&self) {
        self.shared.generation.fetch_add(1, Ordering::SeqCst);
    }

    fn snapshot(&self) -> Vec<Arc<ClipEntry>> {
        lock(&self.shared.table).order.clone()
    }

    // 일치한 order 위치의 오름차순 목록
    pub fn filter(&self, query: &[u16]) -> Vec<u32> {
        let folded = fold(query);
        let mut result = Vec::new();
        if folded.is_empty() {
            return result;
        }
        for (position, entry) in self.snapshot().iter().enumerate() {
            let fields = &entry.fields;
            let hit = |field: usize| {
                fields[field]
                    .as_ref()
                    .is_some_and(|value| matches(value, &folded))
            };
            // 본문 필드가 있으면 텍스트 클립
            // 없으면 이미지 클립
            let matched = hit(NAME)
                || if fields[BODY].is_some() {
                    hit(BODY)
                } else {
                    hit(TIME0) || hit(TIME1)
                };
            if matched {
                result.push(position as u32);
            }
        }
        result
    }

    // stored는 JS 래퍼가 text가 마지막으로 보낸 값과 같다고 확인한 경우
    // 아니거나 저장된 필드가 없으면 text로 임시 필드를 만들어 계산
    pub fn field(&self, id: &[u16], field: usize, text: &[u16], stored: bool) -> Arc<Field> {
        if stored {
            let table = lock(&self.shared.table);
            if let Some(value) = table
                .by_id
                .get(id)
                .and_then(|entry| entry.fields.get(field).cloned().flatten())
            {
                return value;
            }
        }
        Arc::new(Field::new(text.to_vec()))
    }
}

impl Drop for Index {
    fn drop(&mut self) {
        self.shared.closed.store(true, Ordering::SeqCst);
        self.shared.generation.fetch_add(1, Ordering::SeqCst);
        let _request = lock(&self.shared.request);
        self.shared.wake.notify_all();
    }
}

fn run_worker(shared: Arc<Shared>) {
    loop {
        let target = {
            let mut request = lock(&shared.request);
            while !shared.closed.load(Ordering::SeqCst) && request.requested == request.handled {
                request = shared
                    .wake
                    .wait(request)
                    .unwrap_or_else(|poisoned| poisoned.into_inner());
            }
            if shared.closed.load(Ordering::SeqCst) {
                return;
            }
            request.handled = request.requested;
            request.requested
        };
        let entries = lock(&shared.table).order.clone();
        for entry in entries {
            if shared.closed.load(Ordering::SeqCst)
                || shared.generation.load(Ordering::SeqCst) != target
            {
                break;
            }
            for field in [NAME, BODY] {
                if let Some(value) = &entry.fields[field] {
                    // 한 항목의 패닉이 작업 스레드를 끝내지 않게 함
                    let _ = catch_unwind(AssertUnwindSafe(|| value.build_ahead()));
                }
            }
        }
    }
}

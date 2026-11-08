import type { ClipRecord } from '../../Model/clipRecord';
import type { ClipTextRange } from '../../Shared/UI';
import { edgeWhitespace } from '../../Model/clipWhitespace';
import { cancelSearchCorePrebuild, createSearchCore, filterSearchCore, freeSearchCore, prebuildSearchCore, searchCoreCardText, syncSearchCore } from 'plyst-search';

const fold = (text: string) => text.normalize('NFC').toUpperCase();

export function normalizeSearchQuery(raw: string): string {
  return raw.replace(edgeWhitespace, '');
}

// Rust 필드 번호와 같은 순서
const nameField = 0;
const bodyField = 1;
const timeField = 2;

export type SearchCardText = {
  nameRanges: ClipTextRange[];
  bodyRanges: ClipTextRange[];
  excerptStart: number;
};

const emptyCardText: SearchCardText = {
  nameRanges: [],
  bodyRanges: [],
  excerptStart: 0,
};

function rangesOf(values: number[]): ClipTextRange[] {
  const ranges: ClipTextRange[] = [];
  for (let i = 0; i + 1 < values.length; i += 2) ranges.push({ location: values[i], length: values[i + 1] });
  return ranges;
}

export function createSearchIndex() {
  let handle: number | null = null;
  let synced: ClipRecord[] | null = null;
  let syncedNow: number | null = null;
  // 클립마다 마지막으로 보낸 필드 값
  let sent = new Map<string, (string | undefined)[]>();
  const cards = new Map<string, { name: string; body: string; query: string; value: SearchCardText }>();

  // 실패한 핸들은 버리고 다음 호출이 새 핸들에 전체를 다시 보냄
  function reset() {
    if (handle !== null) freeSearchCore(handle);
    handle = null;
    synced = null;
    syncedNow = null;
    sent = new Map();
    cards.clear();
  }

  function ensure(): number | null {
    if (handle === null) {
      const created = createSearchCore();
      if (created === 0) return null;
      handle = created;
    }
    return handle;
  }

  // 같은 clips와 같은 now면 보내지 않음
  // 이미지 클립의 시간 필드는 times가 있을 때만 보냄
  function sync(clips: ClipRecord[], times?: { now: number; texts: (clip: ClipRecord) => string[] }): number | null {
    const current = ensure();
    if (current === null) return null;
    const isSameClips = synced === clips;
    if (isSameClips && (times === undefined || syncedNow === times.now)) return current;
    const order: string[] = [];
    const positions: number[] = [];
    const fields: number[] = [];
    const texts: string[] = [];
    const next = new Map<string, (string | undefined)[]>();
    clips.forEach((clip, position) => {
      order.push(clip.id);
      const previous = sent.get(clip.id) ?? [];
      const values = [...previous];
      const update = (field: number, text: string) => {
        values[field] = text;
        if (previous[field] === text) return;
        positions.push(position);
        fields.push(field);
        texts.push(text);
      };
      update(nameField, clip.name ?? '');
      if (clip.image === null) update(bodyField, clip.text ?? '');
      else if (times) times.texts(clip).forEach((text, offset) => update(timeField + offset, text));
      next.set(clip.id, values);
    });
    if (!(isSameClips && texts.length === 0) && !syncSearchCore(current, order, positions, fields, texts)) {
      reset();
      return null;
    }
    sent = next;
    for (const id of cards.keys()) if (!next.has(id)) cards.delete(id);
    synced = clips;
    if (times) syncedNow = times.now;
    else if (!isSameClips) syncedNow = null;
    return current;
  }

  return {
    // clips 차분 동기화 뒤 작업 스레드 시작
    prebuild(clips: ClipRecord[]) {
      const current = sync(clips);
      if (current !== null && !prebuildSearchCore(current)) reset();
    },
    // 일치 클립을 입력 순서로 반환
    filter(clips: ClipRecord[], rawQuery: string, now: number, times: (clip: ClipRecord) => string[]): ClipRecord[] {
      const query = normalizeSearchQuery(rawQuery);
      if (!query) return [];
      const current = sync(clips, { now, texts: times });
      if (current === null) return [];
      const found = filterSearchCore(current, query);
      if (found === null) {
        reset();
        return [];
      }
      return found.map((position) => clips[position]);
    },
    // 같은 이름, 본문, 접은 질의면 이전 결과를 그대로 반환
    cardText(clip: ClipRecord, rawQuery: string): SearchCardText {
      const query = normalizeSearchQuery(rawQuery);
      const folded = fold(query);
      if (!folded) return emptyCardText;
      const name = clip.name ?? '';
      const body = clip.text ?? '';
      const cached = cards.get(clip.id);
      if (cached?.name === name && cached.body === body && cached.query === folded) return cached.value;
      const current = ensure();
      // Rust는 원문을 두지 않으므로 마지막으로 보낸 값과 같은지 여기서 판단
      const values = sent.get(clip.id);
      const isSynced = values !== undefined && values[nameField] === name && (clip.image !== null || values[bodyField] === body);
      const result = current === null ? null : searchCoreCardText(current, clip.id, name, body, query, isSynced);
      if (result === null) {
        reset();
        return emptyCardText;
      }
      const value = {
        nameRanges: rangesOf(result.nameRanges),
        bodyRanges: rangesOf(result.bodyRanges),
        excerptStart: result.excerptStart,
      };
      cards.set(clip.id, { name, body, query: folded, value });
      return value;
    },
    cancelPrebuild() {
      if (handle !== null) cancelSearchCorePrebuild(handle);
    },
    dispose: reset,
  };
}

export type SearchIndex = ReturnType<typeof createSearchIndex>;

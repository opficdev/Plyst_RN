// Jest에는 네이티브 모듈이 없어 Rust 코어 대신 쓰는 가짜
// 일치는 대문자 부분 문자열만 보며 글자 경계, 접기, 발췌 규칙은 core/tests/search_cases.rs가 검증

type Fields = (string | undefined)[];
type Core = { entries: Fields[]; fields: Map<string, Fields> };

const cores = new Map<number, Core>();
let nextHandle = 1;

function textRanges(text: string, query: string) {
  const folded = query.toUpperCase();
  const haystack = text.toUpperCase();
  const ranges: number[] = [];
  let cursor = haystack.indexOf(folded);
  while (folded && cursor !== -1) {
    ranges.push(cursor, folded.length);
    cursor = haystack.indexOf(folded, cursor + folded.length);
  }
  return ranges;
}

export const createSearchCore = jest.fn(() => {
  const handle = nextHandle;
  nextHandle += 1;
  cores.set(handle, { entries: [], fields: new Map() });
  return handle;
});

export const freeSearchCore = jest.fn((handle: number) => {
  cores.delete(handle);
});

export const syncSearchCore = jest.fn((handle: number, order: string[], positions: number[], fields: number[], texts: string[]) => {
  const core = cores.get(handle);
  if (!core) return false;
  const entries = order.map((id) => [...(core.fields.get(id) ?? [])]);
  texts.forEach((text, index) => {
    entries[positions[index]][fields[index]] = text;
  });
  core.entries = entries;
  core.fields = new Map(order.map((id, position) => [id, entries[position]]));
  return true;
});

export const prebuildSearchCore = jest.fn((handle: number) => cores.has(handle));

export const cancelSearchCorePrebuild = jest.fn();

export const filterSearchCore = jest.fn((handle: number, query: string): number[] | null => {
  const core = cores.get(handle);
  if (!core) return null;
  const hit = (text: string | undefined) => text !== undefined && textRanges(text, query).length !== 0;
  const found: number[] = [];
  core.entries.forEach(([name, body, ...times], position) => {
    if (hit(name) || (body !== undefined ? hit(body) : times.some(hit))) found.push(position);
  });
  return found;
});

export const searchCoreCardText = jest.fn((handle: number, id: string, name: string, body: string, query: string, isSynced: boolean) => {
  if (!cores.has(handle)) return null;
  return {
    nameRanges: textRanges(name, query),
    bodyRanges: textRanges(body, query),
    excerptStart: 0,
  };
});

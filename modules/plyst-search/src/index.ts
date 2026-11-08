import NativePlystSearch from './NativePlystSearch';
import type { CardRanges } from './NativePlystSearch';

export type { CardRanges } from './NativePlystSearch';

export function createSearchCore(): number {
  return NativePlystSearch.createIndex();
}

export function freeSearchCore(handle: number) {
  NativePlystSearch.freeIndex(handle);
}

export function syncSearchCore(handle: number, order: string[], positions: number[], fields: number[], texts: string[]): boolean {
  return NativePlystSearch.sync(handle, order, positions, fields, texts);
}

export function prebuildSearchCore(handle: number): boolean {
  return NativePlystSearch.prebuild(handle);
}

export function cancelSearchCorePrebuild(handle: number) {
  NativePlystSearch.cancelPrebuild(handle);
}

export function filterSearchCore(handle: number, query: string): number[] | null {
  return NativePlystSearch.filter(handle, query);
}

export function searchCoreCardText(handle: number, id: string, name: string, body: string, query: string, isSynced: boolean): CardRanges | null {
  return NativePlystSearch.cardText(handle, id, name, body, query, isSynced);
}

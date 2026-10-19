import { createAction } from '../../Shared/State/screenStore';
import type { ClipRecord } from '../../Model/clipRecord';
import type { ClipFilter } from './filter';

export const clipGridActions = {
  clipsLoaded: createAction<{ clips: ClipRecord[]; now: number }>(
    'clipGrid/clipsLoaded',
  ),
  loadFailed: createAction('clipGrid/loadFailed'),
  timeChanged: createAction<number>('clipGrid/timeChanged'),
  filterSelected: createAction<ClipFilter>('clipGrid/filterSelected'),
  thumbnailStarted: createAction<string>('clipGrid/thumbnailStarted'),
  thumbnailLoaded: createAction<{ key: string; uri: string }>(
    'clipGrid/thumbnailLoaded',
  ),
  thumbnailFailed: createAction<string>('clipGrid/thumbnailFailed'),
  thumbnailCancelled: createAction<string>('clipGrid/thumbnailCancelled'),
  thumbnailRequested: createAction<{ id: string; pixels: number }>(
    'clipGrid/thumbnailRequested',
  ),
  thumbnailCancelRequested: createAction<{ id: string; pixels: number }>(
    'clipGrid/thumbnailCancelRequested',
  ),
};

export type ClipGridAction = ReturnType<
  (typeof clipGridActions)[keyof typeof clipGridActions]
>;

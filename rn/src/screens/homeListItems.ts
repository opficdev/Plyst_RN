import type { ClipRecord } from 'plyst-bridge';
import type { HomeContent, HomeSectionKind } from './homeContent';

export type HomeListItem =
  | { kind: 'pinned'; key: string; clips: ClipRecord[] }
  | {
      kind: 'section';
      key: string;
      section: HomeSectionKind;
      hasPreviousSection: boolean;
    }
  | { kind: 'card'; key: string; clip: ClipRecord };

export function makeHomeListItems(content: HomeContent): HomeListItem[] {
  const items: HomeListItem[] = [];
  if (content.pinnedClips.length !== 0)
    items.push({ kind: 'pinned', key: 'pinned', clips: content.pinnedClips });
  content.sections.forEach((section, index) => {
    items.push({
      kind: 'section',
      key: `section:${section.kind}`,
      section: section.kind,
      hasPreviousSection: 0 < index,
    });
    for (const clip of section.clips)
      items.push({ kind: 'card', key: `clip:${clip.id}`, clip });
  });
  return items;
}

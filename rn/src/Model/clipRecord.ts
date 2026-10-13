import { clipCharacterCount, clipTextPrefix } from './clipText';

export type ClipImageRecord = {
  byteCount: number;
  contentType: string;
  pixelWidth: number;
  pixelHeight: number;
};

type ClipRecordSource = {
  id: string;
  text: string | null;
  image: ClipImageRecord | null;
  name: string | null;
  memo: string | null;
  pinnedAt: number | null;
  isWebLink: boolean;
  createdAt: number;
  lastUsedAt: number | null;
};

export type ClipRecord = ClipRecordSource & {
  characterCount: number;
  textPrefix: string | null;
};

export function makeClipRecord(record: ClipRecordSource): ClipRecord {
  return {
    ...record,
    characterCount: clipCharacterCount(record.text),
    textPrefix: clipTextPrefix(record.text),
  };
}

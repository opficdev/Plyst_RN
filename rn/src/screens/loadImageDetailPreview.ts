import { getClipImagePreview } from 'plyst-bridge';

export type ImageDetailPreviewResult =
  { status: 'loaded'; uri: string } | { status: 'failed' };

export async function loadImageDetailPreview(
  clipID: string,
): Promise<ImageDetailPreviewResult> {
  try {
    const uri = await getClipImagePreview(clipID);
    return uri === null ? { status: 'failed' } : { status: 'loaded', uri };
  } catch {
    return { status: 'failed' };
  }
}

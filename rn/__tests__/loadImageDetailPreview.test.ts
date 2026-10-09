import { getClipImagePreview } from 'plyst-bridge';
import { loadImageDetailPreview } from '../src/screens/loadImageDetailPreview';

jest.mock('plyst-bridge', () => ({ getClipImagePreview: jest.fn() }));
const preview = jest.mocked(getClipImagePreview);
beforeEach(() => jest.resetAllMocks());

test('미리보기 URI를 전달한다', async () => {
  preview.mockResolvedValue('file:///images/preview');
  await expect(loadImageDetailPreview('id')).resolves.toEqual({
    status: 'loaded',
    uri: 'file:///images/preview',
  });
  expect(preview).toHaveBeenCalledWith('id');
  expect(preview).toHaveBeenCalledTimes(1);
});

test('미리보기가 없으면 실패한다', async () => {
  preview.mockResolvedValue(null);
  await expect(loadImageDetailPreview('id')).resolves.toEqual({
    status: 'failed',
  });
});

test('브리지 오류는 실패로 반환한다', async () => {
  preview.mockRejectedValue(new Error('E_IMAGE_UNAVAILABLE'));
  await expect(loadImageDetailPreview('id')).resolves.toEqual({
    status: 'failed',
  });
});

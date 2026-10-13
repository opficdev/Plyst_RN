import { formatByteCount } from '../../../src/Feature/ImageDetail/formatByteCount';

test.each([
  [0, '0KB'],
  [1, '1바이트'],
  [999, '999바이트'],
  [1000, '1KB'],
  [1499, '1KB'],
  [1500, '2KB'],
  [999_499, '999KB'],
  [999_500, '1MB'],
  [1_500_000, '1.5MB'],
  [123_456_789, '123.5MB'],
  [999_500_000, '999.5MB'],
  [999_950_000, '1GB'],
  [999_999_999, '1GB'],
  [1_190_000_000, '1.19GB'],
  [1_200_000_000, '1.2GB'],
  [12_345_000_000, '12.35GB'],
  [999_995_000_000, '1TB'],
  [1_190_000_000_000, '1.19TB'],
])('ByteCountFormatter file 출력과 맞춘다: %d', (byteCount, expected) => {
  expect(formatByteCount(byteCount)).toBe(expected);
});

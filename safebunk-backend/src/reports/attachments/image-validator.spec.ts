import { BadRequestException } from '@nestjs/common';
import {
  assertValidImage,
  detectImageMime,
  MAX_IMAGE_BYTES,
  UploadedImage,
} from './image-validator';

const JPEG = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46]);
const PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00]);
const WEBP = Buffer.concat([
  Buffer.from('RIFF', 'ascii'),
  Buffer.from([0x20, 0x00, 0x00, 0x00]),
  Buffer.from('WEBP', 'ascii'),
  Buffer.from('VP8 '),
]);

const file = (buffer: Buffer, over: Partial<UploadedImage> = {}): UploadedImage => ({
  originalname: 'photo.bin',
  mimetype: 'application/octet-stream',
  size: buffer.length,
  buffer,
  ...over,
});

describe('detectImageMime', () => {
  it('detects JPEG, PNG and WebP from magic bytes', () => {
    expect(detectImageMime(JPEG)).toBe('image/jpeg');
    expect(detectImageMime(PNG)).toBe('image/png');
    expect(detectImageMime(WEBP)).toBe('image/webp');
  });

  it('rejects non-image and too-short buffers', () => {
    expect(detectImageMime(Buffer.from('hello world, not an image'))).toBeNull();
    expect(detectImageMime(Buffer.from([0xff]))).toBeNull();
    expect(detectImageMime(Buffer.alloc(0))).toBeNull();
  });
});

describe('assertValidImage', () => {
  it('trusts the sniffed type, not the client-declared MIME', () => {
    // Declared as PNG but the bytes are actually a JPEG.
    const result = assertValidImage(file(JPEG, { mimetype: 'image/png' }));
    expect(result).toEqual({ mime: 'image/jpeg', ext: 'jpg' });
  });

  it('rejects a spoofed file whose bytes are not a supported image', () => {
    expect(() =>
      assertValidImage(file(Buffer.from('#!/bin/sh\nrm -rf /'), { mimetype: 'image/png' })),
    ).toThrow(BadRequestException);
  });

  it('rejects a missing or empty upload', () => {
    expect(() => assertValidImage(undefined)).toThrow(BadRequestException);
    expect(() => assertValidImage(file(Buffer.alloc(0)))).toThrow(BadRequestException);
  });

  it('rejects an image over the size limit', () => {
    expect(() => assertValidImage(file(PNG, { size: MAX_IMAGE_BYTES + 1 }))).toThrow(
      BadRequestException,
    );
  });
});

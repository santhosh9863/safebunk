import { BadRequestException } from '@nestjs/common';

/** 5 MiB — keep in sync with the client-side check in the Flutter app. */
export const MAX_IMAGE_BYTES = 5 * 1024 * 1024;

export type SupportedImageMime = 'image/jpeg' | 'image/png' | 'image/webp';

export interface UploadedImage {
  originalname: string;
  mimetype: string;
  size: number;
  buffer: Buffer;
}

const EXTENSIONS: Record<SupportedImageMime, string> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
};

/**
 * Sniffs the real image type from the file's magic bytes.
 *
 * The client-supplied `Content-Type` / filename extension is NOT trusted:
 * a text file renamed `photo.png` with `image/png` will not match a signature
 * here and is rejected. Returns null for anything that is not a supported
 * raster image.
 */
export function detectImageMime(buffer: Buffer): SupportedImageMime | null {
  if (buffer.length >= 3 && buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) {
    return 'image/jpeg';
  }
  if (
    buffer.length >= 8 &&
    buffer[0] === 0x89 &&
    buffer[1] === 0x50 &&
    buffer[2] === 0x4e &&
    buffer[3] === 0x47 &&
    buffer[4] === 0x0d &&
    buffer[5] === 0x0a &&
    buffer[6] === 0x1a &&
    buffer[7] === 0x0a
  ) {
    return 'image/png';
  }
  if (
    buffer.length >= 12 &&
    buffer.toString('ascii', 0, 4) === 'RIFF' &&
    buffer.toString('ascii', 8, 12) === 'WEBP'
  ) {
    return 'image/webp';
  }
  return null;
}

/**
 * Validates an uploaded image and returns the trusted MIME type + extension.
 * Throws BadRequestException (400) for anything that is empty, over the size
 * limit, or not a supported image — regardless of what the client claimed.
 */
export function assertValidImage(file: UploadedImage | undefined): {
  mime: SupportedImageMime;
  ext: string;
} {
  if (!file || !file.buffer || file.buffer.length === 0) {
    throw new BadRequestException('No image file was uploaded.');
  }
  if (file.size > MAX_IMAGE_BYTES) {
    throw new BadRequestException('Image is larger than the 5 MB limit.');
  }
  const mime = detectImageMime(file.buffer);
  if (!mime) {
    throw new BadRequestException('Unsupported image. Use a JPEG, PNG or WebP file.');
  }
  return { mime, ext: EXTENSIONS[mime] };
}

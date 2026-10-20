import {
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { randomUUID } from 'crypto';
import { Attachment } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import { assertValidImage, UploadedImage } from './image-validator';
import { ReportStorageService } from './report-storage.service';

export interface AttachmentView {
  id: string;
  url: string;
  contentType: string;
  size: number;
  createdAt: Date;
}

/**
 * Owns report-photo upload/download/removal. The image bytes live in object
 * storage; the DB row only records ownership + metadata. Every operation is
 * scoped to the authenticated student, so another student's attachment is
 * indistinguishable from a missing one (404).
 */
@Injectable()
export class AttachmentsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly storage: ReportStorageService,
  ) {}

  /** Relative URL the client resolves against the backend base URL. */
  static urlFor(id: string): string {
    return `/api/reports/attachments/${id}`;
  }

  async createFromUpload(
    studentId: string,
    file: UploadedImage | undefined,
  ): Promise<AttachmentView> {
    const { mime, ext } = assertValidImage(file);
    // Throws 503 (never a silent fallback) when storage is not configured.
    const id = randomUUID();
    const storagePath = `reports/${studentId}/${id}.${ext}`;

    await this.storage.put(storagePath, file!.buffer, mime);

    try {
      const row = await this.prisma.attachment.create({
        data: {
          id,
          studentId,
          reportId: null,
          storagePath,
          contentType: mime,
          size: file!.size,
        },
      });
      return this.toView(row);
    } catch (error) {
      // DB write failed after upload — delete the object so we never leave an
      // uncontrolled orphan in the bucket.
      await this.storage.remove(storagePath).catch(() => undefined);
      throw error;
    }
  }

  async download(
    studentId: string,
    id: string,
  ): Promise<{ buffer: Buffer; contentType: string }> {
    const row = await this.requireOwned(studentId, id);
    const buffer = await this.storage.get(row.storagePath);
    return { buffer, contentType: row.contentType };
  }

  /**
   * Attachment download used by the staff report route. The caller MUST first
   * authorize the staff/admin actor against the report; this method only
   * resolves the bytes and deliberately performs no identity check itself.
   */
  async downloadForReport(
    reportId: string,
  ): Promise<{ buffer: Buffer; contentType: string }> {
    const row = await this.prisma.attachment.findFirst({
      where: { reportId },
    });
    if (!row) {
      throw new NotFoundException('Attachment not found');
    }
    const buffer = await this.storage.get(row.storagePath);
    return { buffer, contentType: row.contentType };
  }

  /**
   * Removes an attachment the student uploaded but has not yet attached to a
   * report. Once linked to a report it is immutable here (report history must
   * stay intact).
   */
  async removeOwnUnlinked(studentId: string, id: string): Promise<void> {
    const row = await this.requireOwned(studentId, id);
    if (row.reportId) {
      throw new ConflictException('Attachment is already part of a report.');
    }
    await this.storage.remove(row.storagePath).catch(() => undefined);
    await this.prisma.attachment.delete({ where: { id: row.id } });
  }

  /**
   * Atomically claims an unlinked attachment for a report, but only if it
   * belongs to the same student. Returns false when the id is unknown, owned by
   * someone else, or already used — callers treat that as a bad request.
   */
  async claimForReport(studentId: string, attachmentId: string, reportId: string): Promise<boolean> {
    const result = await this.prisma.attachment.updateMany({
      where: { id: attachmentId, studentId, reportId: null },
      data: { reportId },
    });
    return result.count === 1;
  }

  private async requireOwned(studentId: string, id: string): Promise<Attachment> {
    const row = await this.prisma.attachment.findFirst({ where: { id, studentId } });
    if (!row) {
      throw new NotFoundException('Attachment not found');
    }
    return row;
  }

  private toView(row: Attachment): AttachmentView {
    return {
      id: row.id,
      url: AttachmentsService.urlFor(row.id),
      contentType: row.contentType,
      size: row.size,
      createdAt: row.createdAt,
    };
  }
}

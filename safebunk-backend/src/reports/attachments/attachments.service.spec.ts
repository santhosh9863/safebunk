import { BadRequestException, ConflictException, NotFoundException } from '@nestjs/common';
import { AttachmentsService } from './attachments.service';
import { UploadedImage } from './image-validator';

const PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00]);

const file = (buffer: Buffer = PNG): UploadedImage => ({
  originalname: 'photo.png',
  mimetype: 'image/png',
  size: buffer.length,
  buffer,
});

class FakePrisma {
  rows: any[] = [];

  attachment = {
    create: jest.fn(async ({ data }: any) => {
      const row = { createdAt: new Date('2026-10-09T00:00:00Z'), ...data };
      this.rows.push(row);
      return row;
    }),
    findFirst: jest.fn(async ({ where }: any) => {
      return this.rows.find((r) => Object.entries(where).every(([k, v]) => r[k] === v)) ?? null;
    }),
    updateMany: jest.fn(async ({ where, data }: any) => {
      const matches = this.rows.filter((r) =>
        Object.entries(where).every(([k, v]) => r[k] === v),
      );
      matches.forEach((r) => Object.assign(r, data));
      return { count: matches.length };
    }),
    delete: jest.fn(async ({ where }: any) => {
      const i = this.rows.findIndex((r) => r.id === where.id);
      const [row] = this.rows.splice(i, 1);
      return row;
    }),
  };
}

const fakeStorage = () => ({
  isConfigured: jest.fn(() => true),
  put: jest.fn(async () => undefined),
  get: jest.fn(async () => Buffer.from([1, 2, 3])),
  remove: jest.fn(async () => undefined),
});

describe('AttachmentsService', () => {
  let prisma: FakePrisma;
  let storage: ReturnType<typeof fakeStorage>;
  let service: AttachmentsService;

  beforeEach(() => {
    prisma = new FakePrisma();
    storage = fakeStorage();
    service = new AttachmentsService(prisma as any, storage as any);
  });

  describe('createFromUpload', () => {
    it('stores the object under the student path and records metadata', async () => {
      const view = await service.createFromUpload('4301', file());

      expect(view.contentType).toBe('image/png');
      expect(view.url).toBe(`/api/reports/attachments/${view.id}`);
      expect(storage.put).toHaveBeenCalledTimes(1);
      const [path, , contentType] = storage.put.mock.calls[0] as unknown as [
        string,
        Buffer,
        string,
      ];
      expect(path).toBe(`reports/4301/${view.id}.png`);
      expect(contentType).toBe('image/png');
      expect(prisma.rows[0].studentId).toBe('4301');
      expect(prisma.rows[0].reportId).toBeNull();
    });

    it('rejects an invalid upload before touching storage', async () => {
      await expect(
        service.createFromUpload('4301', file(Buffer.from('not an image'))),
      ).rejects.toThrow(BadRequestException);
      expect(storage.put).not.toHaveBeenCalled();
    });

    it('deletes the object if the DB write fails (no orphan)', async () => {
      prisma.attachment.create.mockRejectedValueOnce(new Error('db down'));
      await expect(service.createFromUpload('4301', file())).rejects.toThrow('db down');
      expect(storage.remove).toHaveBeenCalledTimes(1);
    });
  });

  describe('download — IDOR protection', () => {
    it('returns bytes for the owning student', async () => {
      const view = await service.createFromUpload('4301', file());
      const result = await service.download('4301', view.id);
      expect(result.contentType).toBe('image/png');
      expect(result.buffer).toEqual(Buffer.from([1, 2, 3]));
    });

    it("throws NotFound for another student's attachment (no existence leak)", async () => {
      const view = await service.createFromUpload('4301', file());
      await expect(service.download('9999', view.id)).rejects.toThrow(NotFoundException);
      await expect(service.download('9999', 'missing')).rejects.toThrow(NotFoundException);
    });
  });

  describe('removeOwnUnlinked', () => {
    it('removes the object and row for an unlinked attachment', async () => {
      const view = await service.createFromUpload('4301', file());
      await service.removeOwnUnlinked('4301', view.id);
      expect(storage.remove).toHaveBeenCalledTimes(1);
      expect(prisma.rows).toHaveLength(0);
    });

    it('refuses to remove an attachment already linked to a report', async () => {
      const view = await service.createFromUpload('4301', file());
      await service.claimForReport('4301', view.id, 'rep_1');
      await expect(service.removeOwnUnlinked('4301', view.id)).rejects.toThrow(
        ConflictException,
      );
      expect(storage.remove).not.toHaveBeenCalled();
    });

    it('throws NotFound for another student', async () => {
      const view = await service.createFromUpload('4301', file());
      await expect(service.removeOwnUnlinked('9999', view.id)).rejects.toThrow(
        NotFoundException,
      );
    });
  });

  describe('claimForReport', () => {
    it('claims an unlinked attachment for its owner', async () => {
      const view = await service.createFromUpload('4301', file());
      await expect(service.claimForReport('4301', view.id, 'rep_1')).resolves.toBe(true);
      await expect(service.claimForReport('4301', view.id, 'rep_2')).resolves.toBe(false);
    });

    it('refuses to claim a foreign attribute or unknown id', async () => {
      const view = await service.createFromUpload('4301', file());
      await expect(service.claimForReport('9999', view.id, 'rep_1')).resolves.toBe(false);
      await expect(service.claimForReport('4301', 'missing', 'rep_1')).resolves.toBe(false);
    });
  });
});

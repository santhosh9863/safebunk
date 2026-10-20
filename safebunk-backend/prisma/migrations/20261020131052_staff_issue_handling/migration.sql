-- RedefineTables
PRAGMA defer_foreign_keys=ON;
PRAGMA foreign_keys=OFF;
CREATE TABLE "new_Report" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "code" TEXT NOT NULL,
    "studentId" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "description" TEXT NOT NULL,
    "category" TEXT,
    "location" TEXT,
    "imageUrl" TEXT,
    "priority" TEXT NOT NULL DEFAULT 'MEDIUM',
    "status" TEXT NOT NULL DEFAULT 'SUBMITTED',
    "assignedDepartment" TEXT,
    "assignedStaffId" TEXT,
    "assignedAt" DATETIME,
    "resolutionNotes" TEXT,
    "rejectionReason" TEXT,
    "aiCategory" TEXT,
    "aiPriority" TEXT,
    "aiConfidence" REAL,
    "aiDepartment" TEXT,
    "aiReasons" TEXT,
    "aiOverrideBy" TEXT,
    "aiOverrideAt" DATETIME,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    "resolvedAt" DATETIME,
    CONSTRAINT "Report_assignedStaffId_fkey" FOREIGN KEY ("assignedStaffId") REFERENCES "StaffUser" ("id") ON DELETE SET NULL ON UPDATE CASCADE
);
INSERT INTO "new_Report" ("aiCategory", "aiConfidence", "aiDepartment", "aiOverrideAt", "aiOverrideBy", "aiPriority", "aiReasons", "assignedDepartment", "category", "code", "createdAt", "description", "id", "imageUrl", "location", "priority", "resolvedAt", "status", "studentId", "title", "updatedAt") SELECT "aiCategory", "aiConfidence", "aiDepartment", "aiOverrideAt", "aiOverrideBy", "aiPriority", "aiReasons", "assignedDepartment", "category", "code", "createdAt", "description", "id", "imageUrl", "location", "priority", "resolvedAt", "status", "studentId", "title", "updatedAt" FROM "Report";
DROP TABLE "Report";
ALTER TABLE "new_Report" RENAME TO "Report";
CREATE UNIQUE INDEX "Report_code_key" ON "Report"("code");
CREATE INDEX "Report_studentId_createdAt_idx" ON "Report"("studentId", "createdAt");
CREATE INDEX "Report_assignedStaffId_status_idx" ON "Report"("assignedStaffId", "status");
CREATE INDEX "Report_status_createdAt_idx" ON "Report"("status", "createdAt");
PRAGMA foreign_keys=ON;
PRAGMA defer_foreign_keys=OFF;

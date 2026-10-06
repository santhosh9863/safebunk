-- CreateTable
CREATE TABLE "Report" (
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
    "aiCategory" TEXT,
    "aiPriority" TEXT,
    "aiConfidence" REAL,
    "aiDepartment" TEXT,
    "aiReasons" TEXT,
    "aiOverrideBy" TEXT,
    "aiOverrideAt" DATETIME,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    "resolvedAt" DATETIME
);

-- CreateTable
CREATE TABLE "ReportEvent" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "reportId" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "actorId" TEXT,
    "actorRole" TEXT NOT NULL DEFAULT 'SYSTEM',
    "remark" TEXT,
    "aiPayload" TEXT,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "ReportEvent_reportId_fkey" FOREIGN KEY ("reportId") REFERENCES "Report" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "Category" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "name" TEXT NOT NULL,
    "active" BOOLEAN NOT NULL DEFAULT true
);

-- CreateTable
CREATE TABLE "Location" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "block" TEXT NOT NULL,
    "floor" TEXT,
    "room" TEXT,
    "label" TEXT NOT NULL
);

-- CreateTable
CREATE TABLE "Department" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "name" TEXT NOT NULL,
    "active" BOOLEAN NOT NULL DEFAULT true
);

-- CreateIndex
CREATE UNIQUE INDEX "Report_code_key" ON "Report"("code");

-- CreateIndex
CREATE INDEX "Report_studentId_createdAt_idx" ON "Report"("studentId", "createdAt");

-- CreateIndex
CREATE INDEX "ReportEvent_reportId_createdAt_idx" ON "ReportEvent"("reportId", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "Category_name_key" ON "Category"("name");

-- CreateIndex
CREATE UNIQUE INDEX "Department_name_key" ON "Department"("name");

import { NotificationRuleService } from './notification-rule.service';

describe('NotificationRuleService', () => {
  const rules = new NotificationRuleService();

  describe('evaluateAttendanceTransition', () => {
    it('returns no event for a first (baseline) observation', () => {
      const result = rules.evaluateAttendanceTransition(null, 72.5);
      expect(result.event).toBeNull();
      expect(result.milestones).toEqual([]);
    });

    it('returns no event when the percentage is unchanged', () => {
      const result = rules.evaluateAttendanceTransition(72.5, 72.5);
      expect(result.event).toBeNull();
    });

    it('detects improvement', () => {
      expect(rules.evaluateAttendanceTransition(72.5, 73.1).event).toBe('attendanceImproved');
    });

    it('detects a drop', () => {
      expect(rules.evaluateAttendanceTransition(73.1, 68.4).event).toBe('attendanceDropped');
    });

    it('detects entering the danger zone', () => {
      expect(rules.evaluateAttendanceTransition(60, 59).event).toBe('enteredDangerZone');
    });

    it('detects entering the safe zone', () => {
      expect(rules.evaluateAttendanceTransition(74.5, 75.2).event).toBe('enteredSafeZone');
    });

    it('detects leaving the safe zone', () => {
      expect(rules.evaluateAttendanceTransition(76.1, 74.8).event).toBe('leftSafeZone');
    });

    it('detects recovering from danger', () => {
      expect(rules.evaluateAttendanceTransition(59, 62).event).toBe('recoveredFromDanger');
    });

    it('detects perfect attendance', () => {
      expect(rules.evaluateAttendanceTransition(98.5, 100).event).toBe('perfectAttendance');
    });

    it('returns exactly one event per evaluation', () => {
      const result = rules.evaluateAttendanceTransition(74.5, 81.2);
      expect([result.event]).toHaveLength(1);
    });
  });

  describe('evaluateMilestones', () => {
    it('flags thresholds crossed on an increase', () => {
      const milestones = rules.evaluateMilestones(79.5, 90.5);
      expect(milestones).toEqual(['reached80', 'reached90']);
    });

    it('returns none on a decrease', () => {
      expect(rules.evaluateMilestones(95, 80)).toEqual([]);
    });

    it('returns none when already above the threshold', () => {
      expect(rules.evaluateMilestones(96, 97)).toEqual([]);
    });
  });

  describe('statusToEvent', () => {
    it('maps present / absent and ignores leave codes', () => {
      expect(rules.statusToEvent('1')).toBe('attendanceMarkedPresent');
      expect(rules.statusToEvent('0')).toBe('attendanceMarkedAbsent');
      expect(rules.statusToEvent('2')).toBeNull();
      expect(rules.statusToEvent('3')).toBeNull();
    });
  });
});

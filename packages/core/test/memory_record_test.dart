import 'package:nex_core/nex_core.dart';
import 'package:test/test.dart';

void main() {
  group('MemoryRecord', () {
    test('toJson / fromRow round-trip every field', () {
      final now = DateTime.now().toUtc();
      final record = MemoryRecord(
        id: newUuidV7(),
        kind: MemoryKind.communicationStyle,
        key: 'tone',
        valueText: 'prefers concise replies',
        source: MemorySource.crossAiImport,
        confidence: 0.8,
        createdAt: now,
        updatedAt: now,
        deviceId: 'test-device',
        rev: 1,
      );

      final restored = MemoryRecord.fromRow(record.toJson());

      expect(restored.id, record.id);
      expect(restored.kind, MemoryKind.communicationStyle);
      expect(restored.key, 'tone');
      expect(restored.valueText, 'prefers concise replies');
      expect(restored.source, MemorySource.crossAiImport);
      expect(restored.confidence, 0.8);
      expect(restored.deviceId, 'test-device');
      expect(restored.rev, 1);
      expect(restored.deletedAt, isNull);
    });

    test('MemoryKind.fromWire rejects unknown values', () {
      expect(() => MemoryKind.fromWire('nonsense'), throwsArgumentError);
    });
  });
}

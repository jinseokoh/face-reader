import 'dart:convert';

/// 교감도 팀(방) — PIVOT A6/A7. capture-only 원칙: 멤버는 supabaseId 참조만
/// 저장하고 표시·계산은 매번 history 의 FaceReadingReport 로 resolve 한다.
class TeamRoom {
  static const int kMinMembers = 3; // A3 — 2명은 기존 1:1 궁합으로.
  static const int kMaxMembers = 12; // A3 — 하드캡 (66쌍).

  final String id;
  String title;
  /// 생성 시 슬라이더로 정한 예상 인원 (3~12). 멤버 추가 상한·진행바 분모.
  final int memberTarget;
  /// FaceReadingReport.supabaseId 목록. [0] = 방장(내 관상).
  final List<String> memberReportIds;
  final DateTime createdAt;
  DateTime updatedAt;
  DateTime? closedAt;

  TeamRoom({
    required this.id,
    required this.title,
    this.memberTarget = kMaxMembers,
    required this.memberReportIds,
    required this.createdAt,
    required this.updatedAt,
    this.closedAt,
  });

  bool get isClosed => closedAt != null;

  factory TeamRoom.fromJsonString(String json) {
    final m = jsonDecode(json) as Map<String, dynamic>;
    return TeamRoom(
      id: m['id'] as String,
      title: m['title'] as String,
      // 필드 도입 이전에 만든 방은 최대 인원으로 간주.
      memberTarget: (m['memberTarget'] as int?) ?? kMaxMembers,
      memberReportIds:
          (m['memberReportIds'] as List<dynamic>).cast<String>().toList(),
      createdAt: DateTime.parse(m['createdAt'] as String),
      updatedAt: DateTime.parse(m['updatedAt'] as String),
      closedAt: m['closedAt'] == null
          ? null
          : DateTime.parse(m['closedAt'] as String),
    );
  }

  String toJsonString() => jsonEncode({
        'id': id,
        'title': title,
        'memberTarget': memberTarget,
        'memberReportIds': memberReportIds,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'closedAt': closedAt?.toIso8601String(),
      });
}

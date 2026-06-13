import 'dart:convert';

/// 교감도 팀 멤버. 이름만 있는 **대기**(미스캔) 상태와, 얼굴 스캔이 끝나
/// [reportId] 가 박힌 **스캔 완료** 상태를 함께 표현한다. capture-only —
/// 스캔된 멤버의 표시·계산은 history 의 FaceReadingReport 로 매번 resolve.
class TeamMember {
  String name;

  /// FaceReadingReport.supabaseId. null 이면 아직 안 찍은 대기 멤버.
  String? reportId;

  TeamMember({required this.name, this.reportId});

  bool get isScanned => reportId != null;

  factory TeamMember.fromJson(Map<String, dynamic> m) => TeamMember(
        name: m['name'] as String,
        reportId: m['reportId'] as String?,
      );

  Map<String, dynamic> toJson() => {'name': name, 'reportId': reportId};
}

/// 교감도 팀(방) — PIVOT A6/A7. 멤버 명단은 생성 시 칩 입력으로 미리 깔고,
/// 한 명씩 얼굴을 스캔해 대기 슬롯을 채운다. 매트릭스는 스캔된 멤버만으로 계산.
class TeamRoom {
  static const int kMinMembers = 3; // A3 — 2명은 기존 1:1 궁합으로.
  static const int kMaxMembers = 12; // A3 — 하드캡 (66쌍).

  final String id;
  String title;

  /// [0] = 방장(내 관상, 스캔 완료). 이후 대기/스캔 멤버.
  final List<TeamMember> members;
  final DateTime createdAt;
  DateTime updatedAt;
  DateTime? closedAt;

  TeamRoom({
    required this.id,
    required this.title,
    required this.members,
    required this.createdAt,
    required this.updatedAt,
    this.closedAt,
  });

  bool get isClosed => closedAt != null;

  /// 얼굴 스캔이 끝난 멤버 수 (매트릭스 참여 가능 인원).
  int get scannedCount => members.where((m) => m.isScanned).length;

  factory TeamRoom.fromJsonString(String json) {
    final m = jsonDecode(json) as Map<String, dynamic>;
    return TeamRoom(
      id: m['id'] as String,
      title: m['title'] as String,
      members: (m['members'] as List<dynamic>)
          .map((e) => TeamMember.fromJson(e as Map<String, dynamic>))
          .toList(),
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
        'members': members.map((e) => e.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'closedAt': closedAt?.toIso8601String(),
      });
}

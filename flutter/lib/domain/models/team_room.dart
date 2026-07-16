import 'dart:convert';

/// 교감도 팀 멤버. 이름만 있는 **대기**(미스캔) 상태와, 얼굴 스캔이 끝나
/// [reportId] 가 박힌 **스캔 완료** 상태를 함께 표현한다. capture-only —
/// 스캔된 멤버의 표시·계산은 history 의 FaceReadingReport 로 매번 resolve.
class TeamMember {
  String name;

  /// FaceReadingReport.supabaseId. null 이면 아직 안 찍은 대기 멤버.
  String? reportId;

  /// 멤버 본인 계정 uid — 본인 합류·방장 본인 슬롯만. 읽기 쪽이 이 값으로
  /// 그 유저의 현재 my-face 를 live resolve 한다 (케미 = 최신 데이터).
  /// 직접촬영/walk-in 슬롯은 null (metrics 스냅샷 유지).
  String? userId;

  TeamMember({required this.name, this.reportId, this.userId});

  bool get isScanned => reportId != null;

  factory TeamMember.fromJson(Map<String, dynamic> m) => TeamMember(
        name: m['name'] as String,
        reportId: m['reportId'] as String?,
        userId: m['userId'] as String?,
      );

  Map<String, dynamic> toJson() =>
      {'name': name, 'reportId': reportId, 'userId': userId};
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

  /// 이 기기 사용자가 방장(생성자)인가 — 생성 시점에 고정. 홈의 내가 만든/
  /// 초대받은 분류 기준. 변경 가능한 내 관상 id 와 비교하지 않는다(재등록해도
  /// 소유가 흔들리지 않게). P3 원격 합류 방은 false 로 들어온다.
  final bool ownedByMe;

  /// 방장(나)이 참가자 명단에 포함되는가. true 면 members[0] = 내 관상,
  /// false 면 내 얼굴을 빼고 참가자끼리만 본다(index 0 도 일반 참가자).
  final bool includeOwner;

  TeamRoom({
    required this.id,
    required this.title,
    required this.members,
    required this.createdAt,
    required this.updatedAt,
    this.closedAt,
    this.ownedByMe = true,
    this.includeOwner = true,
  });

  /// 발표(마감) 상태 — 방장이 일찍 닫았거나(closedAt) 빈자리 없이 전원
  /// 스캔돼 자동 마감된(isFull) 방. 저장된 stamp 에 의존하지 않고 매번 파생해,
  /// 정원이 찼는데도 열려 보이는 상태가 구조적으로 생기지 않게 한다.
  bool get isClosed => closedAt != null || isFull;

  /// 빈 슬롯 없이 전원 스캔(≥최소 인원) — 더 채울 수 없어 사실상 마감.
  bool get isFull =>
      scannedCount >= kMinMembers && scannedCount == members.length;

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
      // 기존 그룹은 전부 로컬 생성(내 것) — 누락 시 true.
      ownedByMe: m['ownedByMe'] as bool? ?? true,
      includeOwner: m['includeOwner'] as bool? ?? true,
    );
  }

  String toJsonString() => jsonEncode({
        'id': id,
        'title': title,
        'members': members.map((e) => e.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'closedAt': closedAt?.toIso8601String(),
        'ownedByMe': ownedByMe,
        'includeOwner': includeOwner,
      });
}

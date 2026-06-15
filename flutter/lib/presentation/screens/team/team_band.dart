import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:face_engine/domain/services/compat/compat_label.dart';
import 'package:facely/domain/services/team_matrix.dart';
import 'package:flutter/material.dart';

// 밴드 색상 스케일 — best→worst. matrix 셀 색깔 닷 전용 (화면-국지 상수).
const _kBandGreen = Color(0xFF2E7D32); // 환상 케미
const _kBandBlue = Color(0xFF1565C0); // 시너지
const _kBandOrange = Color(0xFFEF6C00); // 무난
const _kBandRed = Color(0xFFD32F2F); // 보완 조합

/// 교감도의 4단 밴드 표기 — PIVOT A4.
/// 엔진의 4-tier CompatLabel(임계값 포함)을 그대로 쓰고, 표기만 팀 맥락의
/// 현대 한국어로 바꾼다 (한자 단독 라벨 금지 · 하위 밴드는 "보완 조합" 프레임).
/// UI 레이어 전용 — shared 엔진에는 손대지 않는다.
extension TeamBand on CompatLabel {
  /// 밴드 색상 — matrix 셀 색깔 닷. 녹색(최상)→파랑→오렌지→빨강(최하).
  Color get bandColor {
    switch (this) {
      case CompatLabel.cheonjakjihap:
        return _kBandGreen;
      case CompatLabel.geumseulsanghwa:
        return _kBandBlue;
      case CompatLabel.mahapgaseong:
        return _kBandOrange;
      case CompatLabel.hyeonggeuknanjo:
        return _kBandRed;
    }
  }

  /// 밴드 등급 색 동그라미 이모지 — bandColor 와 매칭 (녹색→파랑→오렌지→빨강).
  String get bandEmoji {
    switch (this) {
      case CompatLabel.cheonjakjihap:
        return '🟢';
      case CompatLabel.geumseulsanghwa:
        return '🔵';
      case CompatLabel.mahapgaseong:
        return '🟠';
      case CompatLabel.hyeonggeuknanjo:
        return '🔴';
    }
  }

  String get bandLabel {
    switch (this) {
      case CompatLabel.cheonjakjihap:
        return '천작지합';
      case CompatLabel.geumseulsanghwa:
        return '금슬상화';
      case CompatLabel.mahapgaseong:
        return '마합가성';
      case CompatLabel.hyeonggeuknanjo:
        return '형극난조';
    }
  }
}

/// 마감 시 서버 `teams.matrix_payload` 로 올릴 JSON — **이름 + 밴드만**(점수·
/// landmark 없음, web 공개 안전). react `/g/:id` 쇼케이스가 그대로 렌더한다.
/// 멤버 2명 미만이면 null. [nameOf] 로 표시 이름을 주입(그룹 명단 이름 우선).
Map<String, dynamic>? buildTeamMatrixPayload({
  required String title,
  required List<FaceReadingReport> reports,
  required String Function(FaceReadingReport) nameOf,
}) {
  if (reports.length < 2) return null;
  final matrix = computeTeamMatrix(reports);
  final members = matrix.members;
  final idxOf = <String?, int>{
    for (int i = 0; i < members.length; i++) members[i].supabaseId: i,
  };
  final names = [for (final m in members) nameOf(m)];

  final pairs = <Map<String, dynamic>>[];
  for (final p in matrix.allPairs) {
    final ai = idxOf[p.a.supabaseId];
    final bi = idxOf[p.b.supabaseId];
    if (ai == null || bi == null) continue;
    pairs.add({
      'a': ai < bi ? ai : bi,
      'b': ai < bi ? bi : ai,
      'e': p.label.bandEmoji,
      'l': p.label.bandLabel,
      'c': _bandHex(p.label.bandColor),
    });
  }

  List<Map<String, int>> highlight(List<TeamPair> ps) => [
        for (final p in ps)
          if (idxOf[p.a.supabaseId] != null && idxOf[p.b.supabaseId] != null)
            {'a': idxOf[p.a.supabaseId]!, 'b': idxOf[p.b.supabaseId]!},
      ];

  return {
    'v': 1,
    'title': title,
    'members': names,
    'pairs': pairs,
    'best': highlight(matrix.bests),
    'surprises': highlight(matrix.surprises),
  };
}

String _bandHex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

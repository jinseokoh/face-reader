import 'package:face_reader/core/theme.dart';
import 'package:face_reader/domain/models/compatibility_result.dart';
import 'package:flutter/material.dart';

// ─── Tortoise palette (관상 report_page와 동일) ───
class _Palette {
  static const darkBrown = Color(0xFF5C4033);
  static const warmBrown = Color(0xFF7B5B3A);
  static const amber = Color(0xFF9B7B4F);
  static const sand = Color(0xFFBFA67A);
  static const olive = Color(0xFF8B9A6B);
  static const lightOlive = Color(0xFFA8B590);
  static const cream = Color(0xFFF5EFE0);
  static const shell = Color(0xFFEDE5D5);

  static const gradient = LinearGradient(
    colors: [darkBrown, warmBrown, amber, sand, olive, lightOlive],
    stops: [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
  );
}

class CompatibilityReportPage extends StatelessWidget {
  final CompatibilityResult result;
  final String albumName;

  const CompatibilityReportPage({
    super.key,
    required this.result,
    required this.albumName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('궁합 분석')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _buildScoreHeader(),
          const SizedBox(height: 16),
          _buildArchetypeCard(),
          const SizedBox(height: 20),
          _buildCategorySection(),
          if (result.specialNote != null) ...[
            const SizedBox(height: 20),
            _buildSpecialNote(),
          ],
          const SizedBox(height: 20),
          _buildSummarySection(),
        ],
      ),
    );
  }

  // ─── Score Header ───
  Widget _buildScoreHeader() {
    final score = result.score.round();
    final label = score >= 80
        ? '천생연분'
        : score >= 60
            ? '좋은 궁합'
            : score >= 40
                ? '보통'
                : '어려운 궁합';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_Palette.cream, Colors.white],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _Palette.shell),
      ),
      child: Column(
        children: [
          Text(
            '$score',
            style: const TextStyle(
              fontFamily: 'SongMyung',
              fontSize: 56,
              fontWeight: FontWeight.w600,
              color: _Palette.darkBrown,
            ),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(
                  fontFamily: 'SongMyung',
                  fontSize: 18,
                  color: _Palette.warmBrown,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          // Score bar — same style as attribute bars in report_page
          Container(
            height: 14,
            decoration: BoxDecoration(
              color: _Palette.shell,
              borderRadius: BorderRadius.circular(7),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: (result.score / 100).clamp(0, 1),
              child: Container(
                decoration: BoxDecoration(
                  gradient: _Palette.gradient,
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Archetype Card ───
  Widget _buildArchetypeCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_Palette.darkBrown, _Palette.warmBrown],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _archetypeChip('나', result.myArchetype),
              const Icon(Icons.favorite, color: _Palette.sand, size: 24),
              _archetypeChip('상대방', result.albumArchetype),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '원형 궁합 ${result.archetypeScore.round()}점',
            style: const TextStyle(
                color: _Palette.sand,
                fontSize: 14,
                fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _archetypeChip(String who, String archetype) {
    return Column(
      children: [
        Text(who,
            style: const TextStyle(
                color: _Palette.sand,
                fontSize: 13,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
          ),
          child: Text(archetype,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  // ─── Category Bars ───
  Widget _buildCategorySection() {
    final sorted = result.categoryScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('분야별 궁합',
            style: TextStyle(
                color: _Palette.darkBrown,
                fontSize: 19,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ...sorted.map((e) => _buildCategoryBar(e.key, e.value)),
      ],
    );
  }

  Widget _buildCategoryBar(String attrName, double score) {
    final label = _attrLabel(attrName);
    final fraction = (score / 100).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Container(
              height: 14,
              decoration: BoxDecoration(
                color: _Palette.shell,
                borderRadius: BorderRadius.circular(7),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: fraction,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: _Palette.gradient,
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 36,
            child: Text(score.round().toString(),
                textAlign: TextAlign.right,
                style: const TextStyle(
                    color: _Palette.darkBrown,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ─── Special Note ───
  Widget _buildSpecialNote() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _Palette.cream,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _Palette.shell),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _Palette.darkBrown.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome, color: _Palette.amber, size: 16),
                const SizedBox(width: 6),
                const Text('특별 관상 궁합',
                    style: TextStyle(
                        color: _Palette.darkBrown,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(result.specialNote!,
              style: const TextStyle(
                color: _Palette.warmBrown,
                fontSize: 16,
                height: 1.7,
              )),
        ],
      ),
    );
  }

  // ─── Summary Sections ───
  Widget _buildSummarySection() {
    final sections = _parseSummarySections(result.summary);

    if (sections.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _Palette.cream,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _Palette.shell),
        ),
        child: Text(result.summary,
            style: const TextStyle(
              color: _Palette.warmBrown,
              fontSize: 16,
              height: 1.7,
            )),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _Palette.cream,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _Palette.shell),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('궁합 해석',
              style: TextStyle(
                  color: _Palette.darkBrown,
                  fontSize: 19,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ...sections.asMap().entries.map((entry) {
            final i = entry.key;
            final section = entry.value;
            return _buildReadingBlock(section, isFirst: i == 0);
          }),
        ],
      ),
    );
  }

  Widget _buildReadingBlock(_SummarySection section, {required bool isFirst}) {
    return Padding(
      padding: EdgeInsets.only(top: isFirst ? 0 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _Palette.darkBrown.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(section.title,
                style: const TextStyle(
                    color: _Palette.darkBrown,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 8),
          Text(section.body,
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  height: 1.7)),
        ],
      ),
    );
  }

  List<_SummarySection> _parseSummarySections(String summary) {
    final sections = <_SummarySection>[];
    final lines = summary.split('\n');
    String? currentTitle;
    final bodyLines = <String>[];

    for (final line in lines) {
      if (line.startsWith('## ')) {
        if (currentTitle != null && bodyLines.isNotEmpty) {
          sections.add(_SummarySection(
            title: currentTitle,
            body: bodyLines.join('\n').trim(),
          ));
        }
        currentTitle = line.substring(3).trim();
        bodyLines.clear();
      } else if (currentTitle != null) {
        bodyLines.add(line);
      }
    }
    if (currentTitle != null && bodyLines.isNotEmpty) {
      sections.add(_SummarySection(
        title: currentTitle,
        body: bodyLines.join('\n').trim(),
      ));
    }

    return sections;
  }

  String _attrLabel(String name) {
    const labels = {
      'wealth': '재물운',
      'leadership': '리더십',
      'intelligence': '통찰력',
      'sociability': '사회성',
      'emotionality': '감정성',
      'stability': '안정성',
      'sensuality': '바람기',
      'trustworthiness': '신뢰성',
      'attractiveness': '매력도',
      'libido': '관능도',
    };
    return labels[name] ?? name;
  }
}

class _SummarySection {
  final String title;
  final String body;
  const _SummarySection({required this.title, required this.body});
}

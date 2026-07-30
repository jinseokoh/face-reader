import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme.dart';
import '../../../data/services/team_service.dart';
import '../../../domain/models/team.dart';

/// 비밀 그룹 문 앞 비밀번호 입력 dialog — 숫자 4자리. 확인 시
/// check_team_password RPC 로 서버 검증하고, 일치할 때만 입력값을 pop 으로
/// 돌려준다. 불일치·통신 실패는 dialog 안 errorText.
///
/// 케미 목록(문 앞 진입)과 그룹 상세(초대 링크 경유 참가)가 공유하는 단일
/// 검증 UI (2026-07-30 chemistry_screen 에서 공용 승격).
class TeamPinDialog extends StatefulWidget {
  final String teamId;
  const TeamPinDialog({super.key, required this.teamId});

  @override
  State<TeamPinDialog> createState() => _TeamPinDialogState();
}

class _TeamPinDialogState extends State<TeamPinDialog> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final ready = _ctrl.text.trim().length == 4 && !_busy;
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      title: const Text('비밀 그룹', style: AppText.modalTitle),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        keyboardType: TextInputType.number,
        maxLength: 4,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: AppText.body.copyWith(color: AppColors.textPrimary),
        onChanged: (_) => setState(() => _error = null),
        decoration: InputDecoration(hintText: '비밀번호 4자리', errorText: _error),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(
            '취소',
            style: AppText.body.copyWith(color: AppColors.textHint),
          ),
        ),
        TextButton(
          onPressed: ready ? _submit : null,
          child: Text(
            '확인',
            style: AppText.subTitle.copyWith(
              color: ready ? AppColors.textPrimary : AppColors.textHint,
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pin = _ctrl.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await TeamService.instance.checkPassword(
        widget.teamId,
        pin,
      );
      if (!mounted) return;
      if (ok) {
        Navigator.pop(context, pin);
        return;
      }
      setState(() {
        _busy = false;
        _error = TeamJoinError.badPassword.labelKo;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = TeamJoinError.unknown.labelKo;
      });
    }
  }
}

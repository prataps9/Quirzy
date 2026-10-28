import 'package:flutter/material.dart';

import '../../../shared/theme/app_palette.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../mocktest/screens/mock_test_screen.dart';

/// One tap into a timed mock test.
class MockTestTile extends StatelessWidget {
  const MockTestTile({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: AppCard(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MockTestScreen())),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(shape: BoxShape.circle, color: p.accentSoft),
              child: Icon(Icons.timer_outlined, color: p.accentText),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Mock test', style: text.titleSmall),
                  Text(
                    'Exam conditions: timed, answers at the end',
                    style: text.bodySmall!.copyWith(color: p.textMuted),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: p.textMuted),
          ],
        ),
      ),
    );
  }
}

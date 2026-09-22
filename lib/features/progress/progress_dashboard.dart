import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../theme.dart';
import 'progress_provider.dart';
import '../../ui/swapnio_kit.dart';
import 'package:google_fonts/google_fonts.dart';

class ProgressDashboard extends StatelessWidget {
  const ProgressDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    return ChangeNotifierProvider(
      create: (_) => ProgressProvider(userId: userId),
      child: Consumer<ProgressProvider>(
        builder: (context, provider, _) {
          final progress = provider.progress;
          if (progress == null) {
            return Scaffold(
              appBar: AppBar(title: Text('Progress Dashboard')),
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return Scaffold(
            appBar: AppBar(title: Text('Progress Dashboard')),
            body: Padding(
              padding: const EdgeInsets.all(16.0),
              child: ListView(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _metric(context, '${progress.totalSessions}', 'sessions',
                            context.sw.give),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _metric(context, '${progress.totalMessages}', 'messages',
                            context.sw.get),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _metric(context, '${progress.totalTasks}', 'tasks',
                            context.sw.success),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  const KitSection('Skill progress'),
                  ...progress.skills.map((s) => SurfaceCard(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.skillName,
                                  style: AppTheme.display(
                                      fontSize: 19, color: context.sw.text)),
                              const SizedBox(height: 10),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(5),
                                child: LinearProgressIndicator(
                                  value: (s.sessionsCompleted / 20).clamp(0.0, 1.0),
                                  minHeight: 9,
                                  backgroundColor: context.sw.surfaceLow,
                                  color: context.sw.give,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text('Sessions: ${s.sessionsCompleted}'),
                              Text('Quiz Score: ${s.avgQuizScore.toStringAsFixed(1)} / 100'),
                              Text('Streak: ${s.streakDays} days'),
                              Row(
                                children: [
                                  Text('Peer Rating: '),
                                  Icon(Icons.star, color: context.sw.give, size: 18),
                                  Text('${s.peerRating.toStringAsFixed(1)} / 5'),
                                ],
                              ),
                              if (s.avgQuizScore < 60 || s.peerRating < 3)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text(
                                    'Needs Improvement',
                                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              if (s.avgQuizScore >= 80 && s.peerRating >= 4)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text(
                                    'Excellent Progress!',
                                    style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                                  ),
                                ),
                            ],
                        ),
                      )),
                  if (progress.skills.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        'Complete a swap session to start tracking progress.',
                        style: TextStyle(color: context.sw.textMuted),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _metric(BuildContext context, String value, String label, Color color) {
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: AppTheme.display(fontSize: 24, color: color)),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: GoogleFonts.manrope(
                  fontSize: 11, fontWeight: FontWeight.w700, color: context.sw.textMuted)),
        ],
      ),
    );
  }
}

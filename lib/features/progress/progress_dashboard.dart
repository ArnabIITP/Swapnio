import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../theme.dart';
import 'progress_provider.dart';

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
                  Text('Total Sessions: ${progress.totalSessions}', style: TextStyle(fontSize: 18)),
                  Text('Total Messages: ${progress.totalMessages}', style: TextStyle(fontSize: 18)),
                  Text('Total Tasks: ${progress.totalTasks}', style: TextStyle(fontSize: 18)),
                  SizedBox(height: 24),
                  Text('Skill Progress', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  ...progress.skills.map((s) => Card(
                        margin: EdgeInsets.symmetric(vertical: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.skillName, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                              SizedBox(height: 8),
                              LinearProgressIndicator(
                                value: (s.sessionsCompleted / 20).clamp(0.0, 1.0),
                                minHeight: 8,
                                backgroundColor: Colors.grey[300],
                                color: Colors.blueAccent,
                              ),
                              SizedBox(height: 8),
                              Text('Sessions: ${s.sessionsCompleted}'),
                              Text('Quiz Score: ${s.avgQuizScore.toStringAsFixed(1)} / 100'),
                              Text('Streak: ${s.streakDays} days'),
                              Row(
                                children: [
                                  Text('Peer Rating: '),
                                  Icon(Icons.star, color: AppTheme.primaryColor, size: 18),
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
                        ),
                      )),
                  if (progress.skills.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        'Complete a swap session to start tracking progress.',
                        style: TextStyle(color: Colors.grey[600]),
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
}

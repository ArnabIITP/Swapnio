import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import '../theme.dart';
import '../services/feedback_service.dart';

/// Quick "how's the app going" dialog - a star rating plus a note, always
/// attributed to the signed-in user (see [FeedbackService]) so admins know
/// who sent it in real time.
Future<void> showFeedbackDialog(BuildContext context) async {
  double rating = 0;
  final messageController = TextEditingController();

  final submitted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Send feedback'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tell us what is working and what is not - it goes straight '
                'to the Swapnio team, with your account attached.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 14),
              Center(
                child: RatingBar.builder(
                  initialRating: rating,
                  minRating: 0,
                  direction: Axis.horizontal,
                  allowHalfRating: false,
                  itemCount: 5,
                  itemSize: 30,
                  itemBuilder: (context, _) =>
                      Icon(Icons.star, color: dialogContext.sw.give),
                  onRatingUpdate: (value) => setDialogState(() => rating = value),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: messageController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Your feedback',
                  hintText: 'What should we know?',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Send'),
          ),
        ],
      ),
    ),
  );

  if (submitted != true) return;
  final message = messageController.text.trim();
  if (message.isEmpty) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please write a note before sending.')),
    );
    return;
  }
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final ok = await FeedbackService.instance.submitFeedback(
    message: message,
    rating: rating.round(),
  );
  messenger.showSnackBar(
    SnackBar(
      content: Text(ok
          ? 'Thanks for the feedback!'
          : 'Could not send feedback. Please try again.'),
      backgroundColor: ok ? null : Colors.redAccent,
    ),
  );
}

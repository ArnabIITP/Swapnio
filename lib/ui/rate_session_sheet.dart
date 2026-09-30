import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/swap_service.dart';
import '../theme.dart';
import 'swapnio_kit.dart';

/// What went well - quick tags alongside the stars.
const List<String> kRatingTags = [
  'Punctual',
  'Clear teacher',
  'Patient',
  'Friendly',
  'Well prepared',
  'Great listener',
];

/// Rates the other person for one session. A session only counts (hours,
/// badges, points, the Skill Passport) once both people have rated it, so
/// this opens right after confirming, and from the session and Inbox until
/// it's done. Returns true if this rating completed the session.
Future<bool> showRateSessionSheet(
  BuildContext context, {
  required String swapId,
  required String otherName,
}) async {
  final completed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.sw.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _RateSessionSheet(swapId: swapId, otherName: otherName),
  );
  return completed == true;
}

class _RateSessionSheet extends StatefulWidget {
  final String swapId;
  final String otherName;

  const _RateSessionSheet({required this.swapId, required this.otherName});

  @override
  State<_RateSessionSheet> createState() => _RateSessionSheetState();
}

class _RateSessionSheetState extends State<_RateSessionSheet> {
  double _rating = 0;
  final Set<String> _tags = {};
  final TextEditingController _review = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _review.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a star rating first.')),
      );
      return;
    }
    setState(() => _busy = true);
    final result = await SwapSessionService.instance.rateSession(
      widget.swapId,
      rating: _rating,
      review: _review.text.trim(),
      tags: _tags.toList(),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error!), backgroundColor: Colors.redAccent),
      );
      return;
    }
    Navigator.pop(context, result.completed);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final first = widget.otherName.split(' ').first;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: c.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Rate your session with $first',
              style: AppTheme.display(fontSize: 24, color: c.text),
            ),
            const SizedBox(height: 6),
            Text(
              "It's added to both your records once you've both rated - "
              'that keeps ratings on Swapnio honest.',
              style: GoogleFonts.manrope(
                fontSize: 13,
                height: 1.4,
                color: c.textMuted,
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: RatingBar.builder(
                initialRating: _rating,
                minRating: 1,
                allowHalfRating: true,
                itemCount: 5,
                itemSize: 42,
                itemPadding: const EdgeInsets.symmetric(horizontal: 3),
                itemBuilder: (context, _) =>
                    Icon(Icons.star_rounded, color: c.give),
                onRatingUpdate: (r) => setState(() => _rating = r),
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in kRatingTags)
                  FilterChip(
                    label: Text(tag, style: const TextStyle(fontSize: 12.5)),
                    selected: _tags.contains(tag),
                    onSelected: (v) => setState(
                      () => v ? _tags.add(tag) : _tags.remove(tag),
                    ),
                    selectedColor: c.give.withValues(alpha: 0.2),
                    checkmarkColor: c.give,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _review,
              maxLines: 3,
              maxLength: 1000,
              decoration: InputDecoration(
                hintText: 'Write a review (optional)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: c.border),
                ),
              ),
            ),
            const SizedBox(height: 8),
            PillButton(
              label: 'Submit rating',
              icon: Icons.star_rounded,
              loading: _busy,
              onTap: _busy ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

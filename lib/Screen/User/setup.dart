import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../providers/app_state.dart';
import '../../services/match_service.dart';
import '../../services/skill_catalog_service.dart';
import '../../theme.dart';
import '../../ui/celebration.dart';
import '../../ui/skill_suggestion_chips.dart';
import 'Bottomnav.dart';

class ProfileSetupPage extends StatefulWidget {
  const ProfileSetupPage({super.key});

  @override
  State<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends State<ProfileSetupPage> {
  final _name = TextEditingController();
  final _headline = TextEditingController();
  final _location = TextEditingController();
  final _bio = TextEditingController();
  final _offer = TextEditingController();
  final _learn = TextEditingController();
  // Commitment & consistency: people follow through on goals they've stated.
  final _goal = TextEditingController();
  int _step = 0;
  bool _forward = true;
  String _experience = 'Intermediate';
  File? _resume;
  File? _photo;
  final _offers = <String>[];
  final _learns = <String>[];
  bool _saving = false;
  // Real profiles to preview a match against, fetched once.
  List<Map<String, dynamic>> _candidates = [];

  @override
  void initState() {
    super.initState();
    final user = context.read<AppState>().currentUser;
    _name.text = user?.name ?? '';
    _bio.text = user?.bio ?? '';
    _offers.addAll(user?.skillsOffered ?? const []);
    _learns.addAll(user?.skillsWanted ?? const []);
    SkillCatalogService.instance.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
    _offer.addListener(() => setState(() {}));
    _learn.addListener(() => setState(() {}));
    _loadCandidates();
  }

  Future<void> _loadCandidates() async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('users').limit(100).get();
      if (!mounted) return;
      setState(() {
        _candidates = snapshot.docs
            .where((d) => d.id != me && d.data()['isBanned'] != true)
            .map((d) => {'id': d.id, ...d.data()})
            .toList();
      });
    } catch (_) {
      // The teaser is a bonus - onboarding works fine without it.
    }
  }

  void _goToStep(int step) {
    HapticFeedback.selectionClick();
    setState(() {
      _forward = step > _step;
      _step = step;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _headline.dispose();
    _location.dispose();
    _bio.dispose();
    _offer.dispose();
    _learn.dispose();
    _goal.dispose();
    super.dispose();
  }

  void _add(TextEditingController controller, List<String> target) {
    final value = SkillCatalogService.instance.canonicalize(controller.text);
    if (value.isEmpty ||
        target.any((s) => s.toLowerCase() == value.toLowerCase())) {
      return;
    }
    setState(() {
      target.add(value);
      controller.clear();
    });
  }

  Future<void> _chooseResume() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result?.files.single.path != null) {
      setState(() => _resume = File(result!.files.single.path!));
    }
  }

  Future<void> _choosePhoto() async {
    final result = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1200,
    );
    if (result != null) setState(() => _photo = File(result.path));
  }

  Future<void> _finish() async {
    final app = context.read<AppState>();
    final current = app.currentUser;
    if (current == null || _name.text.trim().isEmpty || _offers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add your name and at least one skill you teach.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      var updated = current.copyWith(
        name: _name.text.trim(),
        bio: '${_headline.text.trim()} ${_location.text.trim()} ${_bio.text.trim()}'.trim(),
        skillsOffered: List.of(_offers),
        skillsWanted: List.of(_learns),
        availability: [_experience],
      );
      if (!await app.updateUserProfile(updated)) {
        throw StateError(app.error);
      }
      if (_photo != null) await app.uploadProfileImage(_photo!);
      if (_resume != null) await app.uploadResume(_resume!);
      final goal = _goal.text.trim();
      if (goal.isNotEmpty) {
        await FirebaseFirestore.instance.collection('users').doc(current.id).set(
          {'monthlyGoal': goal, 'monthlyGoalSetAt': FieldValue.serverTimestamp()},
          SetOptions(merge: true),
        );
      }
      if (!mounted) return;
      // Finishing onboarding is a real accomplishment - mark it, then land
      // them in the app whichever way they dismiss the celebration.
      await showCelebrationDialog(
        context,
        icon: Icons.rocket_launch,
        headline: "You're all set!",
        message: goal.isNotEmpty
            ? 'Your goal: "$goal". Let\'s find someone who can help you get there.'
            : 'Your profile is live. Let\'s find your first skill swap.',
        primaryLabel: 'Start discovering',
      );
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const BottomNavPage()),
        (_) => false,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not complete profile: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  Widget _chips(List<String> values) => Wrap(
        spacing: 8,
        children: values
            .map((value) => Chip(
                  label: Text(value),
                  onDeleted: () => setState(() => values.remove(value)),
                ))
            .toList(),
      );

  Widget _content() {
    switch (_step) {
      case 0:
        return Column(children: [
          _field(_name, 'Full name'),
          _field(_headline, 'Professional headline'),
          _field(_location, 'Location'),
        ]);
      case 1:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _field(_offer, 'Skill you can teach'),
          SkillSuggestionChips(
            query: _offer.text,
            onSelected: (s) {
              _offer.text = s;
              _add(_offer, _offers);
            },
          ),
          ElevatedButton(onPressed: () => _add(_offer, _offers), child: const Text('Add skill')),
          _chips(_offers),
          const SizedBox(height: 20),
          _field(_learn, 'Skill you want to learn'),
          SkillSuggestionChips(
            query: _learn.text,
            onSelected: (s) {
              _learn.text = s;
              _add(_learn, _learns);
            },
          ),
          ElevatedButton(onPressed: () => _add(_learn, _learns), child: const Text('Add skill')),
          _chips(_learns),
          _buildMatchTeaser(),
        ]);
      case 2:
        return Column(children: [
          TextField(
            controller: _goal,
            decoration: const InputDecoration(
              labelText: 'One thing you want to learn this month',
              hintText: 'e.g. Play my first song on guitar',
              helperText: 'Optional - we\'ll keep it on your home screen',
            ),
          ),
          const SizedBox(height: 18),
          ...['Beginner', 'Intermediate', 'Advanced', 'Expert'].map(
            (level) => RadioListTile<String>(
              value: level,
              groupValue: _experience,
              title: Text(level),
              onChanged: (value) => setState(() => _experience = value!),
            ),
          ),
          _field(_bio, 'Tell us about yourself'),
        ]);
      default:
        return Column(children: [
          _uploadTile(Icons.picture_as_pdf, 'Add resume / CV (PDF)', _resume?.path, _chooseResume),
          const SizedBox(height: 16),
          _uploadTile(Icons.add_a_photo, 'Add display picture', _photo?.path, _choosePhoto),
        ]);
    }
  }

  /// "See a match before you finish": once someone has entered a couple of
  /// skills, show them a real person they'd match with. Value shown before
  /// the form is done is the strongest reason to actually finish it.
  Widget _buildMatchTeaser() {
    if (_offers.length + _learns.length < 2 || _candidates.isEmpty) {
      return const SizedBox.shrink();
    }
    Map<String, dynamic>? best;
    MatchResult? bestMatch;
    for (final candidate in _candidates) {
      final match = MatchService.compute(
        mySkillsOffered: _offers,
        mySkillsWanted: _learns,
        myAvailability: const [],
        candidateSkillsOffered: List<String>.from(candidate['skillsOffered'] ?? []),
        candidateSkillsWanted: List<String>.from(candidate['skillsWanted'] ?? []),
        candidateAvailability: const [],
        candidateRating: (candidate['rating'] as num?)?.toDouble() ?? 0,
      );
      if (!match.hasAnyOverlap) continue;
      if (bestMatch == null || match.percent > bestMatch.percent) {
        bestMatch = match;
        best = candidate;
      }
    }
    if (best == null || bestMatch == null) return const SizedBox.shrink();

    final firstName = (best['name'] as String? ?? 'Someone').split(' ').first;
    final reasons = <String>[
      if (bestMatch.theyTeachIWant.isNotEmpty)
        'teaches ${bestMatch.theyTeachIWant.join(', ')}',
      if (bestMatch.iTeachTheyWant.isNotEmpty)
        'wants to learn ${bestMatch.iTeachTheyWant.join(', ')}',
    ];

    return TweenAnimationBuilder<double>(
      key: ValueKey(best['id']),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutBack,
      builder: (context, value, child) => Opacity(
        opacity: value.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.92 + 0.08 * value, child: child),
      ),
      child: Container(
        margin: const EdgeInsets.only(top: 24),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            const Icon(Icons.bolt, color: AppTheme.primaryColor, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${bestMatch.percent.round()}% match already!',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$firstName ${reasons.join(' and ')}. '
                    'Finish your profile to connect.',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _uploadTile(IconData icon, String label, String? path, VoidCallback onTap) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: AppTheme.primaryColor),
        title: Text(label),
        subtitle: Text(path == null ? 'Optional' : 'Selected'),
        trailing: ElevatedButton(onPressed: onTap, child: const Text('Choose')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['Tell us who you are', 'What skills can you teach?', 'Your experience level', 'Finish your profile'];
    return Scaffold(
      appBar: AppBar(title: Text('${_step + 1}/4  ${titles[_step]}')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TweenAnimationBuilder<double>(
              tween: Tween(end: (_step + 1) / 4),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => LinearProgressIndicator(value: value),
            ),
            const SizedBox(height: 28),
            Expanded(
              // Steps slide in from the direction you're travelling, instead
              // of jump-cutting between screens.
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  final incoming = child.key == ValueKey(_step);
                  final dx = (incoming == _forward) ? 1.0 : -1.0;
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: Offset(dx * 0.25, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: FadeTransition(opacity: animation, child: child),
                  );
                },
                child: SingleChildScrollView(
                  key: ValueKey(_step),
                  child: _content(),
                ),
              ),
            ),
            Row(children: [
              if (_step > 0)
                TextButton(onPressed: _saving ? null : () => _goToStep(_step - 1), child: const Text('Back')),
              const Spacer(),
              ElevatedButton(
                onPressed: _saving
                    ? null
                    : _step == 3
                        ? _finish
                        : () => _goToStep(_step + 1),
                child: _saving
                    ? const CircularProgressIndicator()
                    : Text(_step == 3 ? 'Finish' : 'Continue'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

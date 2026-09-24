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
import 'package:google_fonts/google_fonts.dart';

import '../../theme.dart';
import '../../ui/swapnio_widgets.dart';
import '../../ui/celebration.dart';
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
      // Experience level is not a day of the week - it must never be
      // written into `availability`, which Discover, Requests and the
      // profile's own availability editor all read as weekday names.
      var updated = current.copyWith(
        name: _name.text.trim(),
        bio: '${_headline.text.trim()} ${_location.text.trim()} ${_bio.text.trim()}'.trim(),
        skillsOffered: List.of(_offers),
        skillsWanted: List.of(_learns),
      );
      if (!await app.updateUserProfile(updated)) {
        throw StateError(app.error);
      }
      await FirebaseFirestore.instance.collection('users').doc(current.id).set(
        {'experienceLevel': _experience},
        SetOptions(merge: true),
      );
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
        badgeId: 'profile_complete',
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

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    IconData? icon,
    int maxLines = 1,
    String? helper,
  }) {
    final c = context.sw;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: AppTheme.label(fontSize: 10, color: c.textMuted)),
          const SizedBox(height: 7),
          TextField(
            controller: controller,
            maxLines: maxLines,
            textCapitalization: TextCapitalization.sentences,
            style: GoogleFonts.manrope(color: c.text),
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: icon == null
                  ? null
                  : Padding(
                      padding: EdgeInsets.only(bottom: maxLines > 1 ? 44 : 0),
                      child: Icon(icon, size: 19, color: c.textMuted),
                    ),
              filled: true,
              fillColor: c.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: c.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: c.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: c.get, width: 1.8),
              ),
            ),
          ),
          if (helper != null) ...[
            const SizedBox(height: 6),
            Text(helper, style: GoogleFonts.manrope(fontSize: 11.5, color: c.textMuted)),
          ],
        ],
      ),
    );
  }

  Widget _chips(List<String> values, {required bool give}) {
    final color = give ? context.sw.give : context.sw.get;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: values
          .map((value) => Pressable(
                onTap: () => setState(() => values.remove(value)),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 9, 9, 9),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(value,
                          style: GoogleFonts.manrope(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                      const SizedBox(width: 6),
                      const Icon(Icons.close_rounded, size: 15, color: Colors.white),
                    ],
                  ),
                ),
              ))
          .toList(),
    );
  }


  /// Skills are chosen, not typed: tapping a suggestion avoids typos and
  /// keeps everyone's skill names matching, which is what makes search and
  /// matching work at all. Free text still works for anything not listed.
  Widget _skillPicker({
    required TextEditingController controller,
    required List<String> selected,
    required bool give,
    required String hint,
    required String emptyHint,
  }) {
    final c = context.sw;
    final color = give ? c.give : c.get;
    final query = controller.text.trim();
    final suggestions = (query.isEmpty
            ? SkillCatalogService.instance.curated
            : SkillCatalogService.instance.suggestionsFor(query))
        .where((s) => !selected.any((v) => v.toLowerCase() == s.toLowerCase()))
        .take(8)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _add(controller, selected),
          textCapitalization: TextCapitalization.words,
          style: GoogleFonts.manrope(color: c.text),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(Icons.search_rounded, size: 19, color: c.textMuted),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    icon: Icon(Icons.add_circle_rounded, color: color),
                    tooltip: 'Add "$query"',
                    onPressed: () => _add(controller, selected),
                  ),
            filled: true,
            fillColor: c.surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: c.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: c.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: color, width: 1.8),
            ),
          ),
        ),
        if (selected.isNotEmpty) ...[
          const SizedBox(height: 12),
          _chips(selected, give: give),
        ],
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(query.isEmpty ? 'POPULAR RIGHT NOW' : 'SUGGESTIONS',
              style: AppTheme.label(fontSize: 10, color: c.textMuted)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final skill in suggestions)
                Pressable(
                  onTap: () {
                    controller.text = skill;
                    _add(controller, selected);
                  },
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(10, 9, 13, 9),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: c.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_rounded, size: 15, color: color),
                        const SizedBox(width: 5),
                        Text(skill,
                            style: GoogleFonts.manrope(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: c.text)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (selected.isEmpty) ...[
          const SizedBox(height: 10),
          Text(emptyHint, style: GoogleFonts.manrope(fontSize: 12, color: c.textMuted)),
        ],
      ],
    );
  }

  Widget _content() {
    switch (_step) {
      case 0:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _field(_name, 'Full name',
              hint: 'How people will see you', icon: Icons.person_outline_rounded),
          _field(_headline, 'Headline',
              hint: 'e.g. CS student who loves teaching',
              icon: Icons.badge_outlined),
          _field(_location, 'Location',
              hint: 'City or campus', icon: Icons.place_outlined),
        ]);
      case 1:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _skillPicker(
            controller: _offer,
            selected: _offers,
            give: true,
            hint: 'Search skills you can teach',
            emptyHint: 'Pick at least one.',
          ),
          const SizedBox(height: 26),
          Text('WHAT DO YOU WANT TO LEARN?',
              style: AppTheme.label(fontSize: 10, color: context.sw.get)),
          const SizedBox(height: 10),
          _skillPicker(
            controller: _learn,
            selected: _learns,
            give: false,
            hint: 'Search skills you want',
            emptyHint: 'Optional, but it makes matches far better.',
          ),
          _buildMatchTeaser(),
        ]);
      case 2:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('HOW EXPERIENCED ARE YOU?',
              style: AppTheme.label(fontSize: 10, color: context.sw.get)),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final level in ['Beginner', 'Intermediate', 'Advanced', 'Expert'])
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: level == 'Expert' ? 0 : 8),
                    child: _levelChip(level),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          // Commitment and consistency: a goal stated out loud here is what
          // the home screen holds you to later.
          _field(_goal, 'Your goal this month',
              hint: 'e.g. Play my first song on guitar',
              icon: Icons.flag_outlined,
              helper: "Optional - we'll keep it on your home screen."),
          _field(_bio, 'About you',
              hint: 'A line or two about what you teach and why',
              icon: Icons.notes_rounded,
              maxLines: 4),
        ]);
      default:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _uploadTile(
            Icons.add_a_photo_rounded,
            'Display picture',
            'Profiles with a photo get far more accepted swaps',
            _photo?.path,
            _choosePhoto,
            give: true,
          ),
          const SizedBox(height: 10),
          _uploadTile(
            Icons.picture_as_pdf_rounded,
            'Resume / CV',
            'Optional - adds credibility to what you teach',
            _resume?.path,
            _chooseResume,
            give: false,
          ),
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
          color: context.sw.win,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(Icons.bolt_rounded, color: context.sw.onWin, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${bestMatch.percent.round()}% match already',
                    style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: context.sw.onWin),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$firstName ${reasons.join(' and ')}. '
                    'Finish your profile to connect.',
                    style: GoogleFonts.manrope(
                        fontSize: 12.5, color: context.sw.onWin, height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _uploadTile(
    IconData icon,
    String label,
    String subtitle,
    String? path,
    VoidCallback onTap, {
    required bool give,
  }) {
    final c = context.sw;
    final color = give ? c.give : c.get;
    final chosen = path != null;
    return Pressable(
      scale: 0.985,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: chosen ? color : c.border, width: chosen ? 1.6 : 1),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(chosen ? Icons.check_rounded : icon, size: 21, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: GoogleFonts.manrope(
                          fontSize: 14, fontWeight: FontWeight.w800, color: c.text)),
                  const SizedBox(height: 2),
                  Text(
                    chosen ? path.split(RegExp(r'[\\/]')).last : subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                        fontSize: 12, color: chosen ? color : c.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(chosen ? 'Change' : 'Choose',
                style: GoogleFonts.manrope(
                    fontSize: 12.5, fontWeight: FontWeight.w800, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _levelChip(String level) {
    final c = context.sw;
    final selected = _experience == level;
    return Pressable(
      onTap: () => setState(() => _experience = level),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? c.cta : c.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? c.cta : c.border),
        ),
        child: Text(
          level,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.manrope(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: selected ? c.onCta : c.text,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    const titles = [
      'Tell us who you are',
      'What could you teach someone?',
      'Where are you starting from?',
      'Finish your profile',
    ];
    const subtitles = [
      'This is what people see first.',
      "Pick at least one. You don't need to be an expert - just a step ahead.",
      'It helps partners pitch at the right level.',
      'A photo makes a profile far more likely to get a yes.',
    ];
    const eyebrows = ['ABOUT YOU', 'YOUR GIVE SIDE', 'YOUR LEVEL', 'ALMOST THERE'];

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (_step > 0)
                    Pressable(
                      onTap: _saving ? null : () => _goToStep(_step - 1),
                      child: Icon(Icons.arrow_back_rounded, color: c.text),
                    )
                  else
                    const SizedBox(width: 24),
                  const SizedBox(width: 14),
                  // Four bars, the first already filled: progress that starts
                  // above zero is far more likely to be finished.
                  for (var i = 0; i < 4; i++) ...[
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 320),
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: i <= _step ? c.give : c.surfaceLow,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 10),
                  Text('${_step + 1}/4',
                      style: GoogleFonts.manrope(
                          fontSize: 12, fontWeight: FontWeight.w800, color: c.textMuted)),
                ],
              ),
              const SizedBox(height: 22),
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: (_step == 1 ? c.give : c.get).withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(eyebrows[_step],
                      style: AppTheme.label(
                          fontSize: 10, color: _step == 1 ? c.give : c.get)),
                ),
              ),
              const SizedBox(height: 10),
              Text(titles[_step],
                  style: AppTheme.display(fontSize: 30, color: c.text, height: 1.1)),
              const SizedBox(height: 8),
              Text(subtitles[_step],
                  style: GoogleFonts.manrope(fontSize: 13, color: c.textMuted, height: 1.4)),
              const SizedBox(height: 20),
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
              const SizedBox(height: 12),
              Pressable(
                onTap: _saving ? null : (_step == 3 ? _finish : () => _goToStep(_step + 1)),
                child: Container(
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _saving ? c.surfaceLow : c.cta,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: _saving
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            valueColor: AlwaysStoppedAnimation<Color>(c.give),
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(_step == 3 ? 'Finish' : 'Continue',
                                style: GoogleFonts.manrope(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: c.onCta)),
                            const SizedBox(width: 8),
                            Icon(
                              _step == 3
                                  ? Icons.check_rounded
                                  : Icons.arrow_forward_rounded,
                              size: 18,
                              color: c.give,
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

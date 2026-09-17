import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/user_model.dart';
import '../../providers/app_state.dart';
import '../../theme.dart';
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
  int _step = 0;
  String _experience = 'Intermediate';
  File? _resume;
  File? _photo;
  final _offers = <String>[];
  final _learns = <String>[];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AppState>().currentUser;
    _name.text = user?.name ?? '';
    _bio.text = user?.bio ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _headline.dispose();
    _location.dispose();
    _bio.dispose();
    _offer.dispose();
    _learn.dispose();
    super.dispose();
  }

  void _add(TextEditingController controller, List<String> target) {
    final value = controller.text.trim();
    if (value.isEmpty || target.contains(value)) return;
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
          ElevatedButton(onPressed: () => _add(_offer, _offers), child: const Text('Add skill')),
          _chips(_offers),
          const SizedBox(height: 20),
          _field(_learn, 'Skill you want to learn'),
          ElevatedButton(onPressed: () => _add(_learn, _learns), child: const Text('Add skill')),
          _chips(_learns),
        ]);
      case 2:
        return Column(children: [
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
            LinearProgressIndicator(value: (_step + 1) / 4),
            const SizedBox(height: 28),
            Expanded(child: SingleChildScrollView(child: _content())),
            Row(children: [
              if (_step > 0)
                TextButton(onPressed: _saving ? null : () => setState(() => _step--), child: const Text('Back')),
              const Spacer(),
              ElevatedButton(
                onPressed: _saving
                    ? null
                    : _step == 3
                        ? _finish
                        : () => setState(() => _step++),
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

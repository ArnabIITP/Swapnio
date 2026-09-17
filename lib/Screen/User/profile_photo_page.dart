import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../providers/app_state.dart';
import '../../theme.dart';
import 'Bottomnav.dart';

class ProfilePhotoPage extends StatefulWidget {
  const ProfilePhotoPage({super.key});

  @override
  State<ProfilePhotoPage> createState() => _ProfilePhotoPageState();
}

class _ProfilePhotoPageState extends State<ProfilePhotoPage> {
  File? _selectedImage;
  bool _isUploading = false;

  Future<void> _choosePhoto() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1200,
    );
    if (image == null || !mounted) return;
    setState(() => _selectedImage = File(image.path));
  }

  Future<void> _uploadAndContinue() async {
    final image = _selectedImage;
    if (image == null) {
      _continueToHome();
      return;
    }

    setState(() => _isUploading = true);
    final uploaded = await context.read<AppState>().uploadProfileImage(image);
    if (!mounted) return;

    setState(() => _isUploading = false);
    if (uploaded == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.read<AppState>().error.isEmpty
                ? 'Could not upload the photo. Please try again.'
                : context.read<AppState>().error,
          ),
        ),
      );
      return;
    }
    _continueToHome();
  }

  void _continueToHome() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const BottomNavPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Complete your profile'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              Text(
                'Add a profile photo',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.darkTextColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Profiles with a photo get more meaningful skill matches.',
                style: theme.textTheme.bodyMedium,
              ),
              const Spacer(),
              Center(
                child: GestureDetector(
                  onTap: _isUploading ? null : _choosePhoto,
                  child: CircleAvatar(
                    radius: 78,
                    backgroundColor: AppTheme.warmBorder,
                    backgroundImage: _selectedImage == null
                        ? null
                        : FileImage(_selectedImage!),
                    child: _selectedImage == null
                        ? const Icon(
                            Icons.add_a_photo_outlined,
                            size: 42,
                            color: AppTheme.primaryColor,
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: TextButton(
                  onPressed: _isUploading ? null : _choosePhoto,
                  child: Text(
                    _selectedImage == null
                        ? 'Choose from gallery'
                        : 'Change photo',
                  ),
                ),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: _isUploading ? null : _uploadAndContinue,
                child: _isUploading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_selectedImage == null
                        ? 'Skip for now'
                        : 'Upload and continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

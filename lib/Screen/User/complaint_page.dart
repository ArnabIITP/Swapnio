import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../services/complaint_service.dart';

/// A dedicated screen for filing a complaint about an issue (a bug, a bad
/// experience, anything that needs a moderator to actually resolve it) -
/// distinct from reporting another user. Admins see these on their own
/// route with the reporter's contact email attached.
class ComplaintPage extends StatefulWidget {
  /// Set when reporting a specific session (from its detail page).
  final String sessionCode;
  final String swapId;

  const ComplaintPage({super.key, this.sessionCode = '', this.swapId = ''});

  @override
  State<ComplaintPage> createState() => _ComplaintPageState();
}

class _ComplaintPageState extends State<ComplaintPage> {
  final _subjectController = TextEditingController();
  final _descriptionController = TextEditingController();
  late final _sessionController = TextEditingController(
    text: widget.sessionCode,
  );
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.sessionCode.isNotEmpty) {
      _subjectController.text = 'Problem with session ${widget.sessionCode}';
    }
  }

  @override
  void dispose() {
    _sessionController.dispose();
    _subjectController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final subject = _subjectController.text.trim();
    final description = _descriptionController.text.trim();
    if (subject.isEmpty || description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in both fields.')),
      );
      return;
    }
    setState(() => _submitting = true);
    final code = _sessionController.text.trim().toUpperCase();
    final ok = await ComplaintService.instance.submitComplaint(
      subject: subject,
      description: description,
      sessionCode: code,
      swapId: code == widget.sessionCode ? widget.swapId : '',
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Complaint submitted - our team will follow up by email.',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not submit your complaint. Please try again.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: const Text('Report an issue'),
        backgroundColor: c.bg,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Something not working right, or a situation you need help with? '
              "Describe it below - we'll follow up at the email on your account.",
              style: TextStyle(color: c.textMuted, fontSize: 13.5, height: 1.4),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _subjectController,
              decoration: const InputDecoration(
                labelText: 'Subject',
                hintText: 'Short summary of the issue',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _sessionController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Session ID (optional)',
                hintText: 'e.g. SES-7K3P-9QXA - shown on the session page',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText:
                    'What happened? Include any details that help us investigate.',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.give,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Submit complaint'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

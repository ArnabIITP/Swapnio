import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'verification_provider.dart';

class VerificationScreen extends StatelessWidget {
  const VerificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => VerificationProvider(),
      child: Consumer<VerificationProvider>(
        builder: (context, provider, _) {
          final verification = provider.verification;
          if (verification == null) {
            return Scaffold(
              appBar: AppBar(title: Text('Profile Verification')),
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return Scaffold(
            appBar: AppBar(title: Text('Profile Verification')),
            body: Padding(
              padding: const EdgeInsets.all(16.0),
              child: ListView(
                children: [
                  // ── Email verification ──────────────────────────
                  Row(
                    children: [
                      Icon(
                        verification.emailVerified ? Icons.verified : Icons.email,
                        color: verification.emailVerified ? Colors.green : Colors.grey,
                      ),
                      SizedBox(width: 8),
                      Text('Email: ${verification.emailVerified ? 'Verified' : 'Not Verified'}'),
                      if (!verification.emailVerified)
                        TextButton(
                          onPressed: () async {
                            final sent = await provider.sendEmailVerification();
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(sent
                                    ? 'Verification email sent!'
                                    : 'Could not send verification email. Please try again.'),
                              ),
                            );
                          },
                          child: Text('Send Verification'),
                        ),
                    ],
                  ),
                  SizedBox(height: 24),

                  // ── Phone verification ──────────────────────────
                  Row(
                    children: [
                      Icon(
                        verification.phoneVerified ? Icons.verified : Icons.phone,
                        color: verification.phoneVerified ? Colors.green : Colors.grey,
                      ),
                      SizedBox(width: 8),
                      Text('Phone: ${verification.phoneVerified ? 'Verified' : 'Not verified'}'),
                    ],
                  ),
                  SizedBox(height: 12),

                  if (!verification.phoneVerified) _PhoneVerificationSection(),

                  SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () async {
                      await provider.reload();
                    },
                    child: Text('Refresh Status'),
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

class _PhoneVerificationSection extends StatefulWidget {
  @override
  State<_PhoneVerificationSection> createState() => _PhoneVerificationSectionState();
}

class _PhoneVerificationSectionState extends State<_PhoneVerificationSection> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<VerificationProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Error banner ──────────────────────────
        if (provider.verificationError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      provider.verificationError!,
                      style: TextStyle(color: Colors.red.shade800, fontSize: 13),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 16),
                    onPressed: provider.resetPhoneVerification,
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(),
                  ),
                ],
              ),
            ),
          ),

        // ── Phone number input ────────────────────
        if (!provider.codeSent) ...[
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Phone number',
              hintText: '+91 98765 43210',
              prefixIcon: Icon(Icons.phone),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              helperText: 'Include country code (e.g. +91)',
            ),
          ),
          SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: provider.phoneVerificationInProgress
                  ? null
                  : () {
                      final phone = _phoneController.text.trim();
                      if (phone.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Please enter a phone number.')),
                        );
                        return;
                      }
                      provider.startPhoneVerification(phone);
                    },
              icon: provider.phoneVerificationInProgress
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.send),
              label: Text(
                provider.phoneVerificationInProgress ? 'Sending...' : 'Send Verification Code',
              ),
            ),
          ),
        ],

        // ── OTP input ──────────────────────────────
        if (provider.codeSent) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'A verification code has been sent to ${_phoneController.text.trim()}',
              style: TextStyle(color: Colors.green.shade700, fontSize: 13),
            ),
          ),
          TextField(
            controller: _otpController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: InputDecoration(
              labelText: 'Verification code',
              hintText: '123456',
              prefixIcon: Icon(Icons.lock_outline),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: provider.phoneVerificationInProgress
                      ? null
                      : () {
                          _otpController.clear();
                          provider.resetPhoneVerification();
                        },
                  child: Text('Cancel'),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: provider.phoneVerificationInProgress
                      ? null
                      : () async {
                          final code = _otpController.text.trim();
                          if (code.isEmpty || code.length < 6) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Please enter the 6-digit code.')),
                            );
                            return;
                          }
                          final success = await provider.verifyOTP(code);
                          if (!context.mounted) return;
                          if (success) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Phone verified successfully!')),
                            );
                          }
                        },
                  icon: provider.phoneVerificationInProgress
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.check),
                  label: Text(
                    provider.phoneVerificationInProgress ? 'Verifying...' : 'Verify Code',
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: provider.phoneVerificationInProgress
                  ? null
                  : () {
                      provider.startPhoneVerification(_phoneController.text.trim());
                    },
              child: Text('Resend code'),
            ),
          ),
        ],
      ],
    );
  }
}

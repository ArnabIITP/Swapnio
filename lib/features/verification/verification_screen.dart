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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(
                        verification.phoneVerified ? Icons.verified : Icons.phone,
                        color: verification.phoneVerified ? Colors.green : Colors.grey,
                      ),
                      SizedBox(width: 8),
                      Text('Phone: ${verification.phoneVerified ? 'Verified' : 'Not added'}'),
                    ],
                  ),
                  if (!verification.phoneVerified)
                    const Padding(
                      padding: EdgeInsets.only(top: 4, left: 32),
                      child: Text(
                        'Phone verification is coming soon.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
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

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme.dart';

/// Static, in-app Terms of Service & Privacy Policy. Swapnio has no
/// separate marketing site yet, so this is the canonical copy the Signup
/// and consent-gate checkboxes link to - keeping it in-app means it ships
/// with the app instead of depending on external hosting.
class LegalPage extends StatelessWidget {
  const LegalPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: const Text('Terms & Privacy Policy'),
        backgroundColor: c.bg,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Text('Last updated: September 2026',
                style: GoogleFonts.manrope(fontSize: 12.5, color: c.textMuted)),
            const SizedBox(height: 20),
            _section(
              context,
              'Terms of Service',
              'By creating a Swapnio account you agree to use the app to teach and '
                  'learn skills in good faith. You must be 18 years of age or older to '
                  'register. Swapnio is a peer-to-peer barter platform - no payment is '
                  'exchanged through the app, and we do not mediate or guarantee the '
                  'outcome of any swap session between users.\n\n'
                  'You are responsible for the accuracy of the information on your '
                  'profile and for your conduct toward other members, including during '
                  'chats and scheduled sessions. Harassment, spam, impersonation and '
                  'fraudulent listings are not tolerated and may result in account '
                  'suspension. Repeated no-shows to scheduled sessions may temporarily '
                  'restrict your ability to book new ones.\n\n'
                  'We may update these terms as the app evolves; continued use after a '
                  'change means you accept the updated terms.',
            ),
            _section(
              context,
              'Privacy Policy',
              'We collect the information you provide directly: your name, email, '
                  'profile photo, bio, and the skills you offer or want to learn. '
                  'Chat messages, swap session details and ratings are stored so the '
                  'app can function, and are visible only to the participants involved '
                  '(or to moderators reviewing a report).\n\n'
                  'If you sign in with Google, we receive your name, email and profile '
                  'photo from Google. If you choose to connect Google Calendar when '
                  'proposing a swap session, we request access only to create the '
                  'calendar event and Meet link for that session - this access is used '
                  'solely for that purpose and is never used to read your existing '
                  'calendar contents beyond what is necessary to create the event.\n\n'
                  'Security and devices: to protect your account we record the devices '
                  'you sign in on - device model, operating system and app version, an '
                  'approximate city worked out from your internet address (never GPS), '
                  'and when each device was last active - plus a security log of '
                  'sign-ins, device sign-outs, two-factor changes and similar events. '
                  'You can see and manage all of this in Profile > Settings > Security. '
                  'The security log is kept for 90 days. If you turn on two-factor, your '
                  'authenticator key is stored encrypted and never shown again.\n\n'
                  'Google Calendar: if you connect it, Swapnio keeps an encrypted '
                  'access token so that when a session is accepted it can add the '
                  'event, with a Google Meet link, to your calendar and invite the other '
                  'person, and move or remove it if the session is rescheduled or '
                  'cancelled. If you also allow busy times, Swapnio reads only when you '
                  'are busy (start and end, never event details) to grey those times out '
                  'on your time picker; people you swap with see them only if you turn on '
                  'sharing. You can disconnect at any time in Settings > Google Calendar, '
                  'which revokes the access.\n\n'
                  'Verification: if you verify your phone, the number is kept by our '
                  'sign-in provider (Firebase Authentication) only to confirm it is yours '
                  'and that it isn\'t already used by another account - one number can '
                  'verify one account. It is never shown to other members; they only see '
                  'that you are verified.\n\n'
                  'Invites: if you join by scanning someone\'s Swapnio QR on your first '
                  'day, we record who invited you so their invite can count once you '
                  'complete a session.\n\n'
                  'We do not sell your personal data. Aggregate, non-identifying stats '
                  '(like total user count) may be shown publicly. You can request '
                  'deletion of your account and all associated data at any time from '
                  'Profile > Settings > Delete Account, which permanently removes your '
                  'login and every chat, swap, request and rating attached to it.',
            ),
            _section(
              context,
              'Age requirement',
              'Swapnio is intended for adults. You must be at least 18 years old to '
                  'create an account. If we learn an account belongs to someone under '
                  '18, it will be removed.',
            ),
            _section(
              context,
              'Contact',
              'Questions about these terms or your data can be sent through '
                  'Profile > Settings > Report an Issue, or via the feedback option in '
                  'the same menu.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title, String body) {
    final c = context.sw;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: GoogleFonts.manrope(
                  fontSize: 17, fontWeight: FontWeight.w800, color: c.text)),
          const SizedBox(height: 8),
          Text(body,
              style: GoogleFonts.manrope(fontSize: 13.5, color: c.textMuted, height: 1.5)),
        ],
      ),
    );
  }
}

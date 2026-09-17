import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'analytics_provider.dart';

class AnalyticsDashboard extends StatelessWidget {
  const AnalyticsDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AnalyticsProvider()..fetchEvents(),
      child: Consumer<AnalyticsProvider>(
        builder: (context, provider, _) {
          return Scaffold(
            appBar: AppBar(title: Text('Analytics Dashboard')),
            body: provider.loading
                ? Center(child: CircularProgressIndicator())
                : provider.error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Could not load analytics. This dashboard is '
                            'restricted to admins.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : provider.events.isEmpty
                        ? const Center(child: Text('No events recorded yet'))
                        : ListView.builder(
                            itemCount: provider.events.length,
                            itemBuilder: (context, idx) {
                              final event = provider.events[idx];
                              return ListTile(
                                leading: Icon(Icons.analytics),
                                title: Text(event.eventType),
                                subtitle: Text('User: ${event.userId}\nTime: ${event.timestamp}\nDetails: ${event.details.toString()}'),
                              );
                            },
                          ),
          );
        },
      ),
    );
  }
}

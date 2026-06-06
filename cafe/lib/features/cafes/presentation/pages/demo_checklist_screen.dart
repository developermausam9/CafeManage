import 'package:flutter/material.dart';
import '../../../../core/presentation/theme/app_theme.dart';
import '../../../../core/presentation/widgets/app_button.dart';

class DemoChecklistScreen extends StatefulWidget {
  final VoidCallback onComplete;
  
  const DemoChecklistScreen({super.key, required this.onComplete});

  @override
  State<DemoChecklistScreen> createState() => _DemoChecklistScreenState();
}

class _DemoChecklistScreenState extends State<DemoChecklistScreen> {
  final List<Map<String, dynamic>> _tasks = [
    {
      'title': 'Setup Business Profile',
      'description': 'Add your café name, address, and VAT number.',
      'completed': true,
    },
    {
      'title': 'Add First Product',
      'description': 'Go to Menu and add your first food or drink item.',
      'completed': false,
    },
    {
      'title': 'Connect Thermal Printer',
      'description': 'Pair your Bluetooth printer in Settings.',
      'completed': false,
    },
    {
      'title': 'Place First Order',
      'description': 'Use the POS to create a test order and print a receipt.',
      'completed': false,
    },
  ];

  @override
  Widget build(BuildContext context) {
    final progress = _tasks.where((t) => t['completed'] == true).length / _tasks.length;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Getting Started', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Colors.white,
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Welcome to Café OS',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 8),
              const Text(
                'Follow this checklist to get your POS ready for production.',
                style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 32),
              
              // Progress Bar
              Row(
                children: [
                  Text('${(progress * 100).toInt()}% Completed', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.grey.shade200,
                      color: AppTheme.primaryColor,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              Expanded(
                child: ListView.separated(
                  itemCount: _tasks.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final task = _tasks[index];
                    final isDone = task['completed'] as bool;
                    
                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: isDone ? Colors.green : Colors.grey.shade300, width: 1),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: CircleAvatar(
                          backgroundColor: isDone ? Colors.green.shade100 : Colors.grey.shade100,
                          child: Icon(
                            isDone ? Icons.check : Icons.circle_outlined,
                            color: isDone ? Colors.green : Colors.grey,
                          ),
                        ),
                        title: Text(task['title'], style: TextStyle(fontWeight: FontWeight.bold, decoration: isDone ? TextDecoration.lineThrough : null)),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(task['description']),
                        ),
                        trailing: isDone ? null : TextButton(
                          onPressed: () {
                            // In real app, navigate to specific screen
                            setState(() {
                              _tasks[index]['completed'] = true;
                            });
                          },
                          child: const Text('Start'),
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 16),
              if (progress == 1.0)
                AppButton(
                  text: 'Go to Dashboard',
                  onPressed: widget.onComplete,
                )
            ],
          ),
        ),
      ),
    );
  }
}

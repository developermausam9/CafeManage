import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/presentation/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/operations_provider.dart';
import '../../data/models/customer_due_model.dart';
import 'package:uuid/uuid.dart';

class DuesScreen extends StatelessWidget {
  const DuesScreen({super.key});

  void _showAddDueDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        final _nameController = TextEditingController();
        final _phoneController = TextEditingController();
        final _amountController = TextEditingController();

        return AlertDialog(
          title: const Text('Record Customer Due'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Customer Name'),
              ),
              TextField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: 'Phone Number'),
                keyboardType: TextInputType.phone,
              ),
              TextField(
                controller: _amountController,
                decoration: const InputDecoration(labelText: 'Due Amount'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final cafeId = context.read<AuthProvider>().cafeId;
                if (cafeId == null) return;

                final due = CustomerDueModel(
                  id: const Uuid().v4(),
                  cafeId: cafeId,
                  name: _nameController.text,
                  phone: _phoneController.text,
                  totalDue: double.parse(_amountController.text),
                  lastUpdatedAt: DateTime.now(),
                );

                context.read<OperationsProvider>().addCustomerDue(due);
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _showPaymentDialog(BuildContext context, CustomerDueModel due) {
    showDialog(
      context: context,
      builder: (context) {
        final _amountController = TextEditingController();
        String _paymentMethod = 'Cash';

        return AlertDialog(
          title: Text('Process Payment: ${due.name}'),
          content: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _amountController,
                    decoration: const InputDecoration(
                      labelText: 'Amount Paid',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Payment Source',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _paymentMethod,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: ['Cash', 'QR', 'Card'].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                    onChanged: (val) {
                      setState(() {
                        _paymentMethod = val!;
                      });
                    },
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final amount = double.tryParse(_amountController.text) ?? 0.0;
                if (amount <= 0) return;
                context.read<OperationsProvider>().processDuePayment(due, amount, _paymentMethod);
                Navigator.pop(context);
              },
              child: const Text('Process'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width <= 850;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDueDialog(context),
        child: const Icon(Icons.person_add),
      ),
      body: Consumer<OperationsProvider>(
        builder: (context, provider, child) {
          final dues = provider.customerDues;

          if (provider.state == OperationsState.loading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.errorMessage != null) {
            return RefreshIndicator(
              onRefresh: () async {
                final cafeId = context.read<AuthProvider>().cafeId;
                if (cafeId != null) {
                  await provider.fetchAll();
                }
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Container(
                  height: MediaQuery.of(context).size.height - 200,
                  alignment: Alignment.center,
                  child: Text(provider.errorMessage!),
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              final cafeId = context.read<AuthProvider>().cafeId;
              if (cafeId != null) {
                await provider.fetchAll();
              }
            },
            child: dues.isEmpty
                ? SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Container(
                      height: MediaQuery.of(context).size.height - 200,
                      alignment: Alignment.center,
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.people_outline, size: 64, color: AppTheme.textSecondary),
                          SizedBox(height: 16),
                          Text(
                            'No customer accounts found.',
                            style: TextStyle(fontSize: 18, color: AppTheme.textSecondary, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 8),
                          Text('Tap the floating action button to create one.', style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(24),
                    itemCount: dues.length,
                    itemBuilder: (context, index) {
                      final d = dues[index];
                      final hasDues = d.totalDue > 0;

                      if (isMobile) {
                        return Card(
                          margin: const EdgeInsets.only(bottom: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: hasDues ? Colors.orange.withOpacity(0.2) : Colors.green.withOpacity(0.2),
                              width: 1.5,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: hasDues ? Colors.orange.shade50 : Colors.green.shade50,
                                      child: Icon(
                                        Icons.person,
                                        color: hasDues ? Colors.orange.shade800 : Colors.green.shade700,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(d.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), overflow: TextOverflow.ellipsis),
                                          const SizedBox(height: 2),
                                          Text(
                                            d.phone.isNotEmpty ? d.phone : 'No Phone Number',
                                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: hasDues ? Colors.orange.shade50 : Colors.green.shade50,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: hasDues ? Colors.orange.shade200 : Colors.green.shade200,
                                        ),
                                      ),
                                      child: Text(
                                        hasDues ? 'Outstanding' : 'Cleared',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: hasDues ? Colors.orange.shade800 : Colors.green.shade700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(height: 24),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'DUE BALANCE',
                                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Rs. ${d.totalDue.toStringAsFixed(2)}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: hasDues ? Colors.orange.shade800 : Colors.green.shade700,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ],
                                    ),
                                    ElevatedButton(
                                      onPressed: hasDues ? () => _showPaymentDialog(context, d) : null,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppTheme.primaryColor,
                                        foregroundColor: Colors.white,
                                        disabledBackgroundColor: Colors.grey.shade100,
                                        disabledForegroundColor: Colors.grey.shade400,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                      ),
                                      child: Text(hasDues ? 'Clear' : 'Paid'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: hasDues ? Colors.orange.withOpacity(0.2) : Colors.green.withOpacity(0.2),
                            width: 1.5,
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          leading: CircleAvatar(
                            backgroundColor: hasDues ? Colors.orange.shade50 : Colors.green.shade50,
                            child: Icon(
                              Icons.person,
                              color: hasDues ? Colors.orange.shade800 : Colors.green.shade700,
                            ),
                          ),
                          title: Row(
                            children: [
                              Text(d.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: hasDues ? Colors.orange.shade50 : Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: hasDues ? Colors.orange.shade200 : Colors.green.shade200,
                                  ),
                                ),
                                child: Text(
                                  hasDues ? 'Outstanding' : 'Cleared',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: hasDues ? Colors.orange.shade800 : Colors.green.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(
                              d.phone.isNotEmpty ? d.phone : 'No Phone Number',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const Text(
                                    'DUE BALANCE',
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Rs. ${d.totalDue.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: hasDues ? Colors.orange.shade800 : Colors.green.shade700,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 20),
                              ElevatedButton(
                                onPressed: hasDues ? () => _showPaymentDialog(context, d) : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primaryColor,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: Colors.grey.shade100,
                                  disabledForegroundColor: Colors.grey.shade400,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                ),
                                child: Text(hasDues ? 'Clear' : 'Paid'),
                              )
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          );
        },
      ),
    );
  }
}

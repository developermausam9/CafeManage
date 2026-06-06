import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/presentation/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/operations_provider.dart';
import '../../data/models/expense_model.dart';
import 'package:uuid/uuid.dart';

class ExpensesScreen extends StatelessWidget {
  const ExpensesScreen({super.key});

  void _showAddExpenseDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        final _descController = TextEditingController();
        final _amountController = TextEditingController();
        String _category = 'rent';

        return AlertDialog(
          title: const Text('Add Expense'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: _category,
                items: const [
                  DropdownMenuItem(value: 'rent', child: Text('Rent')),
                  DropdownMenuItem(value: 'salary', child: Text('Salary')),
                  DropdownMenuItem(value: 'electricity', child: Text('Electricity')),
                  DropdownMenuItem(value: 'internet', child: Text('Internet')),
                  DropdownMenuItem(value: 'gas', child: Text('Gas')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (v) => _category = v!,
                decoration: const InputDecoration(labelText: 'Category'),
              ),
              TextField(
                controller: _descController,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              TextField(
                controller: _amountController,
                decoration: const InputDecoration(labelText: 'Amount'),
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

                final expense = ExpenseModel(
                  id: const Uuid().v4(),
                  cafeId: cafeId,
                  category: _category,
                  amount: double.parse(_amountController.text),
                  description: _descController.text,
                  date: DateTime.now(),
                  createdAt: DateTime.now(),
                );

                context.read<OperationsProvider>().addExpense(expense);
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddExpenseDialog(context),
        child: const Icon(Icons.add),
      ),
      body: Consumer<OperationsProvider>(
        builder: (context, provider, child) {
          final expenses = provider.expenses;

          if (provider.state == OperationsState.loading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.errorMessage != null) {
            return Center(child: Text(provider.errorMessage!));
          }

          if (expenses.isEmpty) {
            return const Center(child: Text('No expenses recorded.'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(24),
            itemCount: expenses.length,
            itemBuilder: (context, index) {
              final e = expenses[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.primaryColor.withOpacity(0.1),
                    child: const Icon(Icons.money_off, color: AppTheme.primaryColor),
                  ),
                  title: Text(e.description.isNotEmpty ? e.description : e.category.toUpperCase()),
                  subtitle: Text(e.date.toLocal().toString().split(' ')[0]),
                  trailing: Text('Rs. ${e.amount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

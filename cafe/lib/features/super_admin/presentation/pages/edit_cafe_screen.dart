import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/cafe_with_subscription_model.dart';
import '../../domain/usecases/update_cafe_usecase.dart';
import '../providers/super_admin_provider.dart';
import '../../../../core/utils/snackbar_helper.dart';

class EditCafeScreen extends StatefulWidget {
  final CafeWithSubscriptionModel cafeData;

  const EditCafeScreen({super.key, required this.cafeData});

  @override
  State<EditCafeScreen> createState() => _EditCafeScreenState();
}

class _EditCafeScreenState extends State<EditCafeScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _cafeNameCtrl;
  late TextEditingController _ownerNameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _panVatCtrl;
  late TextEditingController _monthlyFeeCtrl;

  late String _planType;
  late String _status;
  late DateTime _endDate;

  @override
  void initState() {
    super.initState();
    final cafe = widget.cafeData.cafe;
    final owner = widget.cafeData.owner;
    final sub = widget.cafeData.subscription;

    _cafeNameCtrl = TextEditingController(text: cafe.name);
    _ownerNameCtrl = TextEditingController(text: owner?.fullName ?? '');
    _phoneCtrl = TextEditingController(text: owner?.phone ?? '');
    _addressCtrl = TextEditingController(text: cafe.address ?? '');
    _panVatCtrl = TextEditingController(text: cafe.panVatNumber ?? '');
    _monthlyFeeCtrl = TextEditingController(text: sub?.monthlyFee.toString() ?? '0.0');

    _planType = sub?.planType ?? 'Standard';
    _status = cafe.status;
    _endDate = sub?.subscriptionEnd ?? DateTime.now().add(const Duration(days: 30));
  }

  @override
  void dispose() {
    _cafeNameCtrl.dispose();
    _ownerNameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _panVatCtrl.dispose();
    _monthlyFeeCtrl.dispose();
    super.dispose();
  }

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final provider = context.read<SuperAdminProvider>();

    final params = UpdateCafeParams(
      cafeId: widget.cafeData.cafe.id,
      ownerId: widget.cafeData.owner!.id,
      subscriptionId: '', // not needed since we update by cafe_id
      cafeName: _cafeNameCtrl.text.trim(),
      ownerName: _ownerNameCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
      panVat: _panVatCtrl.text.trim(),
      planType: _planType,
      monthlyFee: double.tryParse(_monthlyFeeCtrl.text) ?? 0.0,
      subscriptionEnd: _endDate,
      status: _status,
    );

    final success = await provider.updateCafe(params);

    if (!mounted) return;

    if (success) {
      SnackbarHelper.showSuccess('Cafe updated successfully!');
      Navigator.of(context).pop();
    } else {
      SnackbarHelper.showError(provider.errorMessage ?? 'Failed to update cafe');
    }
  }

  void _sendPasswordReset() async {
    final email = widget.cafeData.cafe.ownerEmail;
    final ownerId = widget.cafeData.owner?.id;

    if (ownerId == null) {
      SnackbarHelper.showError('Owner profile not found.');
      return;
    }

    final tempPasswordCtrl = TextEditingController();
    bool isResettingEmail = false;
    bool isResettingTemp = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Reset Owner Password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (email != null) ...[
                Text('Owner Email: $email', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
              ],
              const Text('Option 1: Send Password Reset Email'),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: isResettingEmail || isResettingTemp
                      ? null
                      : () async {
                          if (email == null || email.isEmpty) {
                            SnackbarHelper.showError('No email registered for this owner.');
                            return;
                          }
                          setDialogState(() => isResettingEmail = true);
                          try {
                            await Supabase.instance.client.auth.resetPasswordForEmail(email);
                            SnackbarHelper.showSuccess('Password reset email sent successfully!');
                            Navigator.pop(ctx);
                          } catch (e) {
                            SnackbarHelper.showError('Failed to send email: ${e.toString()}');
                          } finally {
                            setDialogState(() => isResettingEmail = false);
                          }
                        },
                  icon: isResettingEmail
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.email),
                  label: const Text('Send Reset Email'),
                ),
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              const Text('Option 2: Set Temporary Password Directly'),
              const SizedBox(height: 8),
              TextField(
                controller: tempPasswordCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'New Temporary Password',
                  border: OutlineInputBorder(),
                  hintText: 'Enter at least 6 characters',
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: isResettingEmail || isResettingTemp
                      ? null
                      : () async {
                          final newPwd = tempPasswordCtrl.text.trim();
                          if (newPwd.length < 6) {
                            SnackbarHelper.showError('Password must be at least 6 characters.');
                            return;
                          }
                          setDialogState(() => isResettingTemp = true);
                          try {
                            final res = await Supabase.instance.client.rpc(
                              'admin_reset_user_password',
                              params: {
                                'p_user_id': ownerId,
                                'p_new_password': newPwd,
                              },
                            );
                            if (res == true) {
                              SnackbarHelper.showSuccess('Password updated successfully!');
                              Navigator.pop(ctx);
                            } else {
                              SnackbarHelper.showError('Failed to update password. User not found.');
                            }
                          } catch (e) {
                            SnackbarHelper.showError('Error: ${e.toString()}');
                          } finally {
                            setDialogState(() => isResettingTemp = false);
                          }
                        },
                  icon: isResettingTemp
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.lock),
                  label: const Text('Set New Password'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = context.watch<SuperAdminProvider>().state == SuperAdminState.loading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Café Details'),
      ),
      body: isLoading 
        ? const Center(child: CircularProgressIndicator())
        : Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(24.0),
              children: [
                const Text('Café Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _cafeNameCtrl,
                  decoration: const InputDecoration(labelText: 'Café Name', border: OutlineInputBorder()),
                  validator: (v) => v!.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _addressCtrl,
                  decoration: const InputDecoration(labelText: 'Address', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _panVatCtrl,
                  decoration: const InputDecoration(labelText: 'PAN/VAT Number', border: OutlineInputBorder()),
                ),
                
                const SizedBox(height: 32),
                const Text('Owner Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _ownerNameCtrl,
                  decoration: const InputDecoration(labelText: 'Owner Full Name', border: OutlineInputBorder()),
                  validator: (v) => v!.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Owner Phone', border: OutlineInputBorder()),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _sendPasswordReset,
                  icon: const Icon(Icons.lock_reset),
                  label: const Text('Reset Owner Password'),
                ),

                const SizedBox(height: 32),
                const Text('Subscription & Plan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _planType,
                  decoration: const InputDecoration(labelText: 'Plan Type', border: OutlineInputBorder()),
                  items: ['Basic', 'Standard', 'Premium']
                      .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                      .toList(),
                  onChanged: (v) => setState(() => _planType = v!),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _monthlyFeeCtrl,
                  decoration: const InputDecoration(labelText: 'Monthly Fee (Rs.)', border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                  validator: (v) => v!.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _status,
                  decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
                  items: ['active', 'suspended']
                      .map((p) => DropdownMenuItem(value: p, child: Text(p.toUpperCase())))
                      .toList(),
                  onChanged: (v) => setState(() => _status = v!),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Subscription End Date'),
                  subtitle: Text(_endDate.toString().substring(0, 10)),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _endDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (date != null) {
                      setState(() => _endDate = date);
                    }
                  },
                ),
                const SizedBox(height: 32),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _submit,
                    child: const Text('Save Changes', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
    );
  }
}

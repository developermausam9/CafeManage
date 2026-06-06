import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/utils/snackbar_helper.dart';
import 'add_staff_screen.dart';

class StaffManagementScreen extends StatefulWidget {
  const StaffManagementScreen({super.key});

  @override
  State<StaffManagementScreen> createState() => _StaffManagementScreenState();
}

class _StaffManagementScreenState extends State<StaffManagementScreen> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _staff = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchStaff();
  }

  Future<void> _fetchStaff() async {
    setState(() => _isLoading = true);
    try {
      final user = _client.auth.currentUser;
      if (user == null) throw Exception('Not logged in');

      // Get current profile
      final currentProfile = await _client.from('profiles').select().eq('id', user.id).single();
      final cafeId = currentProfile['cafe_id'];

      // Fetch all staff for this cafe (excluding super_admin)
      final staffList = await _client
          .from('profiles')
          .select()
          .eq('cafe_id', cafeId)
          .neq('role', 'super_admin')
          .order('created_at', ascending: false);

      setState(() {
        _staff = List<Map<String, dynamic>>.from(staffList);
      });
    } catch (e) {
      SnackbarHelper.showError('Failed to load staff: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleStatus(String profileId, bool currentStatus) async {
    try {
      await _client.from('profiles').update({'is_active': !currentStatus}).eq('id', profileId);
      _fetchStaff();
      SnackbarHelper.showSuccess('Staff status updated');
    } catch (e) {
      SnackbarHelper.showError('Failed to update status');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff Management'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _staff.isEmpty
              ? const Center(child: Text('No staff found.'))
              : ListView.builder(
                  itemCount: _staff.length,
                  itemBuilder: (context, index) {
                    final staff = _staff[index];
                    final isActive = staff['is_active'] ?? true;
                    final role = staff['role'] ?? 'unknown';
                    
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(staff['full_name']?[0] ?? '?'),
                      ),
                      title: Text(staff['full_name'] ?? 'No Name'),
                      subtitle: Text('Role: ${role.toString().toUpperCase()} | Phone: ${staff['phone'] ?? 'N/A'}'),
                      trailing: Switch(
                        value: isActive,
                        onChanged: (val) => _toggleStatus(staff['id'], isActive),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const AddStaffScreen()));
          _fetchStaff();
        },
        child: const Icon(Icons.person_add),
        tooltip: 'Add Staff',
      ),
    );
  }
}

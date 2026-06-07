import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../../core/presentation/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/presentation/providers/subscription_provider.dart';
import '../../../../core/network/supabase_config.dart';

class BookingsManagementScreen extends StatefulWidget {
  const BookingsManagementScreen({super.key});

  @override
  State<BookingsManagementScreen> createState() =>
      _BookingsManagementScreenState();
}

class _BookingsManagementScreenState extends State<BookingsManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _client = SupabaseConfig.client;
  String? _cafeId;
  bool _isLoading = true;
  List<Map<String, dynamic>> _pending = [];
  List<Map<String, dynamic>> _confirmed = [];
  List<Map<String, dynamic>> _checkedIn = [];
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cafeId = context.read<AuthProvider>().cafeId;
      _loadBookings();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadBookings() async {
    if (_cafeId == null) return;
    setState(() => _isLoading = true);
    try {
      final data = await _client
          .from('room_bookings')
          .select('*, rooms(room_number, type, price_per_night, floor_number)')
          .eq('cafe_id', _cafeId!)
          .order('created_at', ascending: false);

      final bookings = List<Map<String, dynamic>>.from(data);
      setState(() {
        _pending =
            bookings.where((b) => b['status'] == 'pending').toList();
        _confirmed =
            bookings.where((b) => b['status'] == 'confirmed').toList();
        _checkedIn =
            bookings.where((b) => b['status'] == 'checked_in').toList();
        _history = bookings
            .where((b) =>
                b['status'] == 'checked_out' || b['status'] == 'cancelled')
            .toList();
      });
    } catch (e) {
      _showError('Failed to load bookings: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.green));
  }

  // ── CONFIRM BOOKING ──────────────────────────────────────────────────────
  Future<void> _confirmBooking(Map<String, dynamic> booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm Booking'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow('Guest', booking['guest_name']),
            _infoRow('Room', 'Room ${booking['rooms']['room_number']}'),
            _infoRow('Check-in', booking['check_in_date']),
            _infoRow('Check-out', booking['check_out_date']),
            _infoRow('Amount', 'Rs. ${booking['total_amount']?.toStringAsFixed(0) ?? '0'}'),
            if (booking['transaction_ref'] != null &&
                booking['transaction_ref'].toString().isNotEmpty)
              _infoRow('Tx Ref', booking['transaction_ref']),
            const SizedBox(height: 12),
            const Text('Confirm this booking? Payment will be marked as verified.',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm Booking')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _client.from('room_bookings').update({
        'status': 'confirmed',
        'payment_status': 'paid',
      }).eq('id', booking['id']);
      _showSuccess('Booking confirmed!');
      _loadBookings();
    } catch (e) {
      _showError('Failed: $e');
    }
  }

  // ── CHECK-IN ─────────────────────────────────────────────────────────────
  Future<void> _checkIn(Map<String, dynamic> booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.login, color: Colors.green),
          ),
          const SizedBox(width: 12),
          const Text('Check-In Guest'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow('Guest', booking['guest_name']),
            _infoRow('Phone', booking['guest_phone'] ?? 'N/A'),
            _infoRow('Room', 'Room ${booking['rooms']['room_number']} (${booking['rooms']['type'].toString().toUpperCase()})'),
            _infoRow('Check-in Date', booking['check_in_date']),
            _infoRow('Check-out Date', booking['check_out_date']),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade200)),
              child: const Text(
                '⚠️ After check-in, the room QR code will become active for in-room ordering.',
                style: TextStyle(fontSize: 12, color: Colors.black87),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('✓ Check In')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final now = DateTime.now().toIso8601String();
      final nights = DateTime.parse(booking['check_out_date'])
          .difference(DateTime.parse(booking['check_in_date']))
          .inDays;
      final roomCharge =
          (booking['rooms']['price_per_night'] as num).toDouble() * nights;

      await _client.from('room_bookings').update({
        'status': 'checked_in',
        'actual_checkin_at': now,
        'room_charge': roomCharge,
      }).eq('id', booking['id']);

      await _client
          .from('rooms')
          .update({'status': 'occupied'}).eq('id', booking['room_id']);

      _showSuccess('Guest checked in to Room ${booking['rooms']['room_number']}!');
      _loadBookings();
    } catch (e) {
      _showError('Check-in failed: $e');
    }
  }

  // ── VIEW ROOM PASS QR ─────────────────────────────────────────────────────
  void _showRoomPassQR(Map<String, dynamic> booking) {
    final cafeId = _cafeId ?? '';
    final roomId = booking['room_id'] as String;
    final bookingId = booking['id'] as String;
    final baseUrl = Uri.base.origin;
    final qrUrl = '$baseUrl/#/order?cafe_id=$cafeId&room_id=$roomId&booking_id=$bookingId';

    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Room ${booking['rooms']['room_number']} — In-Room QR',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 4),
              Text('Guest: ${booking['guest_name']}',
                  style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200)),
                child: QrImageView(
                  data: qrUrl,
                  version: QrVersions.auto,
                  size: 220,
                ),
              ),
              const SizedBox(height: 16),
              Text('Scan to access in-room menu & order tracking',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  textAlign: TextAlign.center),
              const SizedBox(height: 4),
              SelectableText(qrUrl,
                  style: const TextStyle(fontSize: 10, color: Colors.blue),
                  textAlign: TextAlign.center),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 44)),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
                label: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── CHECK-OUT ─────────────────────────────────────────────────────────────
  Future<void> _checkOut(Map<String, dynamic> booking) async {
    // First, fetch all food orders for this booking
    List<Map<String, dynamic>> foodOrders = [];
    double foodTotal = 0;

    try {
      final ordersData = await _client
          .from('orders')
          .select('grand_total, status, created_at')
          .eq('room_booking_id', booking['id'])
          .neq('status', 'cancelled');
      foodOrders = List<Map<String, dynamic>>.from(ordersData);
      foodTotal = foodOrders.fold(
          0.0, (sum, o) => sum + ((o['grand_total'] as num?)?.toDouble() ?? 0));
    } catch (_) {}

    final roomCharge = (booking['room_charge'] as num?)?.toDouble() ?? 0;
    final grandTotal = roomCharge + foodTotal;
    String selectedPayment = 'cash';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDState) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.logout, color: Colors.red),
                    ),
                    const SizedBox(width: 12),
                    const Text('Check-Out & Bill',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 20)),
                  ]),
                  const SizedBox(height: 20),
                  _infoRow('Guest', booking['guest_name']),
                  _infoRow('Room',
                      'Room ${booking['rooms']['room_number']} (${booking['rooms']['type'].toString().toUpperCase()})'),
                  _infoRow('Check-in', booking['check_in_date']),
                  _infoRow('Check-out', DateFormat('yyyy-MM-dd').format(DateTime.now())),
                  const Divider(height: 24),
                  const Text('BILL SUMMARY',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.grey,
                          letterSpacing: 1.2)),
                  const SizedBox(height: 12),
                  _billRow('Room Charges', roomCharge),
                  _billRow('Food & Room Service', foodTotal),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('GRAND TOTAL',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('Rs. ${grandTotal.toStringAsFixed(0)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                              color: AppTheme.primaryColor)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text('Payment Method',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: ['cash', 'qr', 'card'].map((method) {
                      return ChoiceChip(
                        label: Text(method.toUpperCase()),
                        selected: selectedPayment == method,
                        onSelected: (_) =>
                            setDState(() => selectedPayment = method),
                        selectedColor: AppTheme.primaryColor,
                        labelStyle: TextStyle(
                          color: selectedPayment == method
                              ? Colors.white
                              : AppTheme.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade600,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 48)),
                    onPressed: () => Navigator.pop(ctx, true),
                    icon: const Icon(Icons.check),
                    label: Text(
                        'Check Out & Collect Rs. ${grandTotal.toStringAsFixed(0)}'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    style: TextButton.styleFrom(
                        minimumSize: const Size(double.infinity, 44)),
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      final now = DateTime.now().toIso8601String();
      await _client.from('room_bookings').update({
        'status': 'checked_out',
        'actual_checkout_at': now,
        'food_orders_total': foodTotal,
        'grand_total': grandTotal,
        'payment_method': selectedPayment,
        'payment_status': 'paid',
      }).eq('id', booking['id']);

      await _client
          .from('rooms')
          .update({'status': 'dirty'}).eq('id', booking['room_id']);

      _showSuccess(
          'Guest checked out! Total collected: Rs. ${grandTotal.toStringAsFixed(0)}');
      _loadBookings();
    } catch (e) {
      _showError('Check-out failed: $e');
    }
  }

  // ── CANCEL BOOKING ────────────────────────────────────────────────────────
  Future<void> _cancelBooking(Map<String, dynamic> booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel Booking'),
        content: Text(
            'Cancel booking for ${booking['guest_name']}? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Yes, Cancel')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _client
          .from('room_bookings')
          .update({'status': 'cancelled'}).eq('id', booking['id']);
      _showSuccess('Booking cancelled.');
      _loadBookings();
    } catch (e) {
      _showError('Failed: $e');
    }
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final subProvider = context.watch<SubscriptionProvider>();
    if (!subProvider.hasPremium) {
      return _buildPremiumPaywall();
    }

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Bookings',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadBookings,
              tooltip: 'Refresh'),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primaryColor,
          unselectedLabelColor: Colors.grey,
          indicatorColor: AppTheme.primaryColor,
          tabs: [
            Tab(text: 'Pending (${_pending.length})'),
            Tab(text: 'Confirmed (${_confirmed.length})'),
            Tab(text: 'Checked In (${_checkedIn.length})'),
            const Tab(text: 'History'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildList(_pending, status: 'pending'),
                _buildList(_confirmed, status: 'confirmed'),
                _buildList(_checkedIn, status: 'checked_in'),
                _buildList(_history, status: 'history'),
              ],
            ),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> bookings,
      {required String status}) {
    if (bookings.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.hotel, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text('No $status bookings',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadBookings,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: bookings.length,
        itemBuilder: (context, i) =>
            _buildBookingCard(bookings[i], status: status),
      ),
    );
  }

  Widget _buildBookingCard(Map<String, dynamic> booking,
      {required String status}) {
    final room = booking['rooms'] as Map<String, dynamic>;
    final nights = DateTime.parse(booking['check_out_date'])
        .difference(DateTime.parse(booking['check_in_date']))
        .inDays;
    final statusColor = _statusColor(booking['status'] as String? ?? '');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.hotel,
                      color: AppTheme.primaryColor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(booking['guest_name'] ?? 'Guest',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(booking['guest_phone'] ?? '',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(
                    (booking['status'] as String? ?? '').replaceAll('_', ' ').toUpperCase(),
                    style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            // Room + dates info
            Row(
              children: [
                Expanded(
                    child: _miniInfo(Icons.bed,
                        'Room ${room['room_number']} • ${room['type'].toString().toUpperCase()}')),
                Expanded(
                    child: _miniInfo(Icons.calendar_today,
                        '${booking['check_in_date']} → ${booking['check_out_date']}')),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: _miniInfo(
                        Icons.nights_stay, '$nights night(s)')),
                Expanded(
                    child: _miniInfo(Icons.payments,
                        'Rs. ${booking['total_amount']?.toStringAsFixed(0) ?? '0'}')),
              ],
            ),
            if (booking['transaction_ref'] != null &&
                booking['transaction_ref'].toString().isNotEmpty) ...[
              const SizedBox(height: 8),
              _miniInfo(Icons.receipt, 'Tx: ${booking['transaction_ref']}'),
            ],
            // Actions
            const SizedBox(height: 16),
            _buildActions(booking, status: status),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(Map<String, dynamic> booking,
      {required String status}) {
    switch (status) {
      case 'pending':
        return Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red)),
                onPressed: () => _cancelBooking(booking),
                icon: const Icon(Icons.cancel, size: 16),
                label: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white),
                onPressed: () => _confirmBooking(booking),
                icon: const Icon(Icons.check_circle, size: 16),
                label: const Text('Confirm Booking'),
              ),
            ),
          ],
        );
      case 'confirmed':
        return Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red)),
                onPressed: () => _cancelBooking(booking),
                icon: const Icon(Icons.cancel, size: 16),
                label: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white),
                onPressed: () => _checkIn(booking),
                icon: const Icon(Icons.login, size: 16),
                label: const Text('Check In Guest'),
              ),
            ),
          ],
        );
      case 'checked_in':
        return Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _showRoomPassQR(booking),
                icon: const Icon(Icons.qr_code, size: 16),
                label: const Text('Room QR'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
                    foregroundColor: Colors.white),
                onPressed: () => _checkOut(booking),
                icon: const Icon(Icons.logout, size: 16),
                label: const Text('Check Out & Bill'),
              ),
            ),
          ],
        );
      default:
        // History
        final co = booking['actual_checkout_at'];
        return Row(
          children: [
            _miniInfo(Icons.payments,
                'Final: Rs. ${booking['grand_total']?.toStringAsFixed(0) ?? booking['total_amount']?.toStringAsFixed(0) ?? '0'}'),
            const Spacer(),
            if (co != null)
              Text(
                'Out: ${DateFormat('MMM d, HH:mm').format(DateTime.parse(co).toLocal())}',
                style:
                    const TextStyle(fontSize: 12, color: Colors.grey),
              ),
          ],
        );
    }
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style:
                  const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _billRow(String label, double amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text('Rs. ${amount.toStringAsFixed(0)}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _miniInfo(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey),
        const SizedBox(width: 4),
        Flexible(
          child: Text(text,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'confirmed':
        return Colors.blue;
      case 'checked_in':
        return Colors.green;
      case 'checked_out':
        return Colors.grey;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Widget _buildPremiumPaywall() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(32.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.shade200,
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.bed_outlined,
                size: 64,
                color: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Unlock Room & Booking Systems',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'Upgrade to the Premium subscription package to enable full lodging management, self-service QR room ordering, public date booking, and QR payment verification workflows.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, height: 1.5, fontSize: 14),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please contact Super Admin in staff panel to upgrade plan to Premium.'),
                    backgroundColor: AppTheme.primaryColor,
                  ),
                );
              },
              child: const Text('Upgrade to Premium Tier', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

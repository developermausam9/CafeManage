import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../../core/presentation/theme/app_theme.dart';
import '../../../../core/network/supabase_config.dart';

class CustomerBookingScreen extends StatefulWidget {
  const CustomerBookingScreen({super.key});

  @override
  State<CustomerBookingScreen> createState() => _CustomerBookingScreenState();
}

class _CustomerBookingScreenState extends State<CustomerBookingScreen>
    with SingleTickerProviderStateMixin {
  final SupabaseClient _client = SupabaseConfig.client;

  // State
  String? _cafeId;
  String? _cafeName;
  String? _cafePhone;
  String? _cafeAddress;
  String? _paymentQrUrl;
  bool _isLoading = true;
  String? _errorMessage;

  // Dates
  DateTime _checkInDate = DateTime.now().add(const Duration(days: 1));
  DateTime _checkOutDate = DateTime.now().add(const Duration(days: 2));

  // Rooms data
  List<Map<String, dynamic>> _rooms = [];
  List<Map<String, dynamic>> _bookings = [];
  List<Map<String, dynamic>> _availableRooms = [];

  // Step
  int _step = 0; // 0=dates, 1=room, 2=details, 3=payment, done=success

  // Form
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _txRefCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  int _guestCount = 1;

  Map<String, dynamic>? _selectedRoom;
  bool _isSubmitting = false;
  Map<String, dynamic>? _completedBooking;

  // Real-time tracking and lookup
  Timer? _trackingTimer;
  final _trackBookingIdCtrl = TextEditingController();
  bool _isTrackingLookup = false;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  @override
  void dispose() {
    _trackingTimer?.cancel();
    _trackBookingIdCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _txRefCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Map<String, String> _getQueryParams() {
    final params = Map<String, String>.from(Uri.base.queryParameters);
    final fragment = Uri.base.fragment;
    if (fragment.contains('?')) {
      final queryString = fragment.split('?').last;
      for (var part in queryString.split('&')) {
        final kv = part.split('=');
        if (kv.length == 2) params[kv[0]] = Uri.decodeComponent(kv[1]);
      }
    }
    return params;
  }

  /// Returns true if the given string is a valid UUID v4 format
  bool _isValidUuid(String? s) {
    if (s == null || s.isEmpty) return false;
    final uuidRegex = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    );
    return uuidRegex.hasMatch(s);
  }

  Future<void> _initializeData() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    final params = _getQueryParams();
    final rawCafeId = params['cafe_id'];

    // If cafe_id is missing or not a valid UUID, auto-detect the first cafe
    if (!_isValidUuid(rawCafeId)) {
      _cafeId = null; // force auto-detect
    } else {
      _cafeId = rawCafeId;
    }

    try {
      if (_cafeId == null) {
        // Auto-detect: load first available cafe
        final cafes = await _client
            .from('cafes')
            .select('id, name, phone, address')
            .limit(1);
        if (cafes.isEmpty) throw Exception('No hotel configured.');
        _cafeId = cafes.first['id'];
        _cafeName = cafes.first['name'];
        _cafePhone = cafes.first['phone'];
        _cafeAddress = cafes.first['address'];
      } else {
        final cafe = await _client
            .from('cafes')
            .select('name, phone, address')
            .eq('id', _cafeId!)
            .maybeSingle();
        if (cafe == null) {
          // UUID provided but cafe not found — fall back to auto-detect
          final cafes = await _client
              .from('cafes')
              .select('id, name, phone, address')
              .limit(1);
          if (cafes.isEmpty) throw Exception('No hotel configured.');
          _cafeId = cafes.first['id'];
          _cafeName = cafes.first['name'];
          _cafePhone = cafes.first['phone'];
          _cafeAddress = cafes.first['address'];
        } else {
          _cafeName = cafe['name'];
          _cafePhone = cafe['phone'];
          _cafeAddress = cafe['address'];
        }
      }
      final settings = await _client
          .from('settings')
          .select('payment_qr_url')
          .eq('cafe_id', _cafeId!)
          .maybeSingle();
      if (settings != null) _paymentQrUrl = settings['payment_qr_url'];
      await _loadRooms();

      // Check if direct booking tracking is requested via URL
      final bookingIdStr = params['booking_id'];
      if (_isValidUuid(bookingIdStr)) {
        final res = await _client.from('room_bookings')
            .select('*, rooms(room_number, type, price_per_night, floor_number)')
            .eq('id', bookingIdStr!)
            .maybeSingle();
        if (res != null) {
          _completedBooking = Map<String, dynamic>.from(res);
          _step = 99;
          _startTracking();
        }
      }
    } catch (e) {
      setState(() => _errorMessage = 'Failed to load: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadRooms() async {
    final roomsRes = await _client.from('rooms').select().eq('cafe_id', _cafeId!);
    _rooms = List<Map<String, dynamic>>.from(roomsRes);
    final bookingsRes = await _client.from('room_bookings').select().eq('cafe_id', _cafeId!).not('status', 'eq', 'cancelled').not('status', 'eq', 'checked_out');
    _bookings = List<Map<String, dynamic>>.from(bookingsRes);
    _computeAvailability();
  }

  void _computeAvailability() {
    final ciStr = DateFormat('yyyy-MM-dd').format(_checkInDate);
    final coStr = DateFormat('yyyy-MM-dd').format(_checkOutDate);
    final overlapping = _bookings.where((b) {
      final bIn = b['check_in_date'] as String;
      final bOut = b['check_out_date'] as String;
      return ciStr.compareTo(bOut) < 0 && bIn.compareTo(coStr) < 0;
    });
    final bookedIds = overlapping.map((b) => b['room_id'] as String).toSet();
    setState(() {
      _availableRooms = _rooms.where((r) {
        return !bookedIds.contains(r['id']) &&
            (r['status'] == 'available' || r['status'] == 'dirty');
      }).toList();
      _selectedRoom = null;
    });
  }

  int get _nights => _checkOutDate.difference(_checkInDate).inDays;
  double get _totalAmount => (_selectedRoom?['price_per_night'] as num? ?? 0).toDouble() * _nights;

  Future<void> _pickDates() async {
    final range = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _checkInDate, end: _checkOutDate),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: ThemeData.light().copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppTheme.primaryColor,
            onPrimary: Colors.white,
            surface: Colors.white,
            onSurface: Color(0xFF1A1A2E),
          ),
        ),
        child: child!,
      ),
    );
    if (range != null) {
      setState(() {
        _checkInDate = range.start;
        _checkOutDate = range.end;
      });
      _computeAvailability();
    }
  }

  void _startTracking() {
    _trackingTimer?.cancel();
    _trackingTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (_completedBooking == null) return;
      try {
        final res = await _client.from('room_bookings')
            .select('*, rooms(room_number, type, price_per_night, floor_number)')
            .eq('id', _completedBooking!['id'])
            .maybeSingle();
        if (res != null && mounted) {
          setState(() {
            _completedBooking = Map<String, dynamic>.from(res);
          });
          if (res['status'] == 'cancelled' || res['status'] == 'checked_out') {
            _trackingTimer?.cancel();
          }
        }
      } catch (e) {
        debugPrint('Error polling booking status: $e');
      }
    });
  }

  Future<void> _lookupAndTrackBooking() async {
    final rawId = _trackBookingIdCtrl.text.trim();
    if (!_isValidUuid(rawId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid Booking ID (UUID).'), backgroundColor: Colors.red),
      );
      return;
    }
    setState(() => _isTrackingLookup = true);
    try {
      final res = await _client.from('room_bookings')
          .select('*, rooms(room_number, type, price_per_night, floor_number)')
          .eq('id', rawId)
          .maybeSingle();
      if (res == null) {
        throw Exception('Booking not found. Please check your Booking ID.');
      }
      setState(() {
        _completedBooking = Map<String, dynamic>.from(res);
        _step = 99; // success / pass screen
      });
      _startTracking();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Booking found! Loading status...'), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString().replaceAll('Exception: ', '')}'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isTrackingLookup = false);
    }
  }

  Future<void> _submitBooking() async {
    // Already validated in Step 2; check if form state is active and valid
    if (_formKey.currentState != null && !_formKey.currentState!.validate()) return;
    if (_paymentQrUrl != null && _paymentQrUrl!.isNotEmpty && _txRefCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the transaction reference after payment.'), backgroundColor: Colors.red),
      );
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final res = await _client.from('room_bookings').insert({
        'cafe_id': _cafeId,
        'room_id': _selectedRoom!['id'],
        'guest_name': _nameCtrl.text.trim(),
        'guest_phone': _phoneCtrl.text.trim(),
        'guest_email': _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        'check_in_date': DateFormat('yyyy-MM-dd').format(_checkInDate),
        'check_out_date': DateFormat('yyyy-MM-dd').format(_checkOutDate),
        'status': 'pending',
        'total_amount': _totalAmount,
        'payment_status': _txRefCtrl.text.trim().isNotEmpty ? 'pending_verification' : 'unpaid',
        'transaction_ref': _txRefCtrl.text.trim().isEmpty ? null : _txRefCtrl.text.trim(),
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      }).select('*, rooms(room_number, type, price_per_night, floor_number)').single();
      setState(() {
        _completedBooking = Map<String, dynamic>.from(res);
        _step = 99; // success
      });
      _startTracking();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Booking failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  // ────────────────────────────────────────────────────────── BUILD
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const CircularProgressIndicator(color: AppTheme.primaryColor),
            const SizedBox(height: 20),
            Text('Loading rooms...', style: TextStyle(color: Colors.grey.shade600)),
          ]),
        ),
      );
    }
    if (_errorMessage != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
            ]),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: CustomScrollView(
        slivers: [
          _buildHeroAppBar(),
          SliverToBoxAdapter(
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 900),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                child: _step == 99 ? _buildRoomPass() : _buildWizard(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroAppBar() {
    return SliverAppBar(
      expandedHeight: 200,
      pinned: true,
      backgroundColor: AppTheme.primaryColor,
      flexibleSpace: FlexibleSpaceBar(
        title: Text(_cafeName ?? 'Hotel Booking',
            style: const TextStyle(fontWeight: FontWeight.bold, shadows: [
              Shadow(blurRadius: 4, color: Colors.black38)
            ])),
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFE65100), Color(0xFFBF360C)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(children: [
            Positioned(right: -30, top: -30,
              child: Container(width: 180, height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.08),
                ))),
            Positioned(left: -20, bottom: -20,
              child: Container(width: 120, height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.06),
                ))),
            Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 60),
                child: Row(children: [
                  const Icon(Icons.location_on, color: Colors.white70, size: 14),
                  const SizedBox(width: 4),
                  Text(_cafeAddress ?? 'Hotel', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildWizard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        // Step indicator
        _buildStepIndicator(),
        const SizedBox(height: 24),
        // Step content
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _buildStepContent(),
        ),
      ],
    );
  }

  Widget _buildStepIndicator() {
    final steps = ['Dates', 'Room', 'Details', 'Payment'];
    return Row(
      children: List.generate(steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          return Expanded(
            child: Container(
              height: 2,
              color: i ~/ 2 < _step ? AppTheme.primaryColor : Colors.grey.shade300,
            ),
          );
        }
        final idx = i ~/ 2;
        final done = idx < _step;
        final active = idx == _step;
        return Column(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? Colors.green : active ? AppTheme.primaryColor : Colors.grey.shade200,
            ),
            child: Center(
              child: done
                  ? const Icon(Icons.check, color: Colors.white, size: 18)
                  : Text('${idx + 1}', style: TextStyle(
                    color: active ? Colors.white : Colors.grey,
                    fontWeight: FontWeight.bold,
                  )),
            ),
          ),
          const SizedBox(height: 4),
          Text(steps[idx], style: TextStyle(
            fontSize: 11, fontWeight: active ? FontWeight.bold : FontWeight.normal,
            color: active ? AppTheme.primaryColor : Colors.grey,
          )),
        ]);
      }),
    );
  }

  Widget _buildStepContent() {
    switch (_step) {
      case 0: return _buildStep0Dates();
      case 1: return _buildStep1Rooms();
      case 2: return _buildStep2Details();
      case 3: return _buildStep3Payment();
      default: return const SizedBox();
    }
  }

  // ── STEP 0: Date Selection ──────────────────────────────────────────────
  Widget _buildStep0Dates() {
    return Column(key: const ValueKey(0), children: [
      Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 4,
        shadowColor: Colors.black12,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const Icon(Icons.date_range, color: AppTheme.primaryColor, size: 40),
            const SizedBox(height: 12),
            const Text('When are you arriving?',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            const SizedBox(height: 4),
            const Text('Select your check-in and check-out dates',
                style: TextStyle(color: Colors.grey, fontSize: 14)),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(child: _dateCard('Check-In', _checkInDate, Icons.login)),
              const SizedBox(width: 12),
              const Icon(Icons.arrow_forward, color: Colors.grey),
              const SizedBox(width: 12),
              Expanded(child: _dateCard('Check-Out', _checkOutDate, Icons.logout)),
            ]),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                side: const BorderSide(color: AppTheme.primaryColor, width: 2),
                foregroundColor: AppTheme.primaryColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _pickDates,
              icon: const Icon(Icons.edit_calendar),
              label: const Text('Change Dates', style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.nights_stay, color: AppTheme.primaryColor, size: 18),
                const SizedBox(width: 8),
                Text('$_nights night${_nights != 1 ? 's' : ''}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                        fontSize: 16)),
              ]),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 20),
      // Available rooms summary
      if (_availableRooms.isNotEmpty)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Row(children: [
            const Icon(Icons.check_circle, color: Colors.green),
            const SizedBox(width: 8),
            Text('${_availableRooms.length} room${_availableRooms.length != 1 ? 's' : ''} available for these dates',
                style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
          ]),
        )
      else
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.shade200),
          ),
          child: const Row(children: [
            Icon(Icons.info_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('No rooms available for selected dates', style: TextStyle(color: Colors.red)),
          ]),
        ),
      const SizedBox(height: 24),
      ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryColor,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 4,
          shadowColor: AppTheme.primaryColor.withOpacity(0.4),
        ),
        onPressed: _availableRooms.isEmpty ? null : () => setState(() => _step = 1),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('Browse Available Rooms', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          const Icon(Icons.arrow_forward),
        ]),
      ),
      const SizedBox(height: 32),
      const Divider(),
      const SizedBox(height: 24),
      _buildTrackBookingCard(),
    ]);
  }

  Widget _buildTrackBookingCard() {
    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.track_changes, color: AppTheme.primaryColor),
                SizedBox(width: 8),
                Text(
                  'Track Existing Booking',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Enter your Booking ID (UUID) to check the real-time status of your reservation and payment.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _trackBookingIdCtrl,
                    decoration: InputDecoration(
                      hintText: 'e.g. 123e4567-e89b-12d3-a456-426614174000',
                      hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  ),
                  onPressed: _isTrackingLookup ? null : _lookupAndTrackBooking,
                  child: _isTrackingLookup
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Track', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateCard(String label, DateTime date, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 14, color: AppTheme.primaryColor),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 6),
        Text(DateFormat('MMM dd').format(date),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        Text(DateFormat('EEEE, yyyy').format(date),
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ]),
    );
  }

  // ── STEP 1: Room Selection ───────────────────────────────────────────────
  Widget _buildStep1Rooms() {
    return Column(key: const ValueKey(1), children: [
      // Header
      Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: AppTheme.primaryColor,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            const Icon(Icons.bed, color: Colors.white, size: 28),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${_availableRooms.length} Rooms Available',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              Text('${DateFormat('MMM d').format(_checkInDate)} → ${DateFormat('MMM d').format(_checkOutDate)} • $_nights nights',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      ...(_availableRooms.map((room) => _buildRoomCard(room)).toList()),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 46),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: () => setState(() => _step = 0),
        icon: const Icon(Icons.arrow_back),
        label: const Text('Change Dates'),
      ),
    ]);
  }

  Widget _buildRoomCard(Map<String, dynamic> room) {
    final isSelected = _selectedRoom?['id'] == room['id'];
    final typeIcons = {'standard': Icons.hotel, 'deluxe': Icons.star, 'suite': Icons.king_bed, 'family': Icons.family_restroom};
    final typeColors = {'standard': Colors.blue, 'deluxe': Colors.amber, 'suite': Colors.purple, 'family': Colors.green};
    final type = room['type'] as String? ?? 'standard';
    final nightTotal = (room['price_per_night'] as num).toDouble() * _nights;

    return GestureDetector(
      onTap: () {
        setState(() => _selectedRoom = room);
        Future.delayed(const Duration(milliseconds: 200), () {
          setState(() => _step = 2);
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : Colors.transparent,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? AppTheme.primaryColor.withOpacity(0.15)
                  : Colors.black.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Room type icon
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  color: (typeColors[type] ?? Colors.blue).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(typeIcons[type] ?? Icons.hotel,
                    color: typeColors[type] ?? Colors.blue, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('Room ${room['room_number']}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: (typeColors[type] ?? Colors.blue).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(type.toUpperCase(),
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: typeColors[type] ?? Colors.blue)),
                  ),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.stairs, size: 13, color: Colors.grey),
                  const SizedBox(width: 3),
                  Text('Floor ${room['floor_number'] ?? 1}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(width: 12),
                  const Icon(Icons.person, size: 13, color: Colors.grey),
                  const SizedBox(width: 3),
                  Text('Max ${room['max_occupancy'] ?? 2} guests',
                      style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ]),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('Rs. ${(room['price_per_night'] as num).toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                        fontSize: 18)),
                const Text('/night', style: TextStyle(fontSize: 11, color: Colors.grey)),
              ]),
            ]),
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Total for $_nights nights: Rs. ${nightTotal.toStringAsFixed(0)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                onPressed: () {
                  setState(() { _selectedRoom = room; _step = 2; });
                },
                child: const Row(children: [
                  Text('Select', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(width: 4),
                  Icon(Icons.arrow_forward, size: 16),
                ]),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  // ── STEP 2: Guest Details ───────────────────────────────────────────────
  Widget _buildStep2Details() {
    return Column(key: const ValueKey(2), children: [
      // Selected room summary
      _selectedRoomSummaryCard(),
      const SizedBox(height: 20),
      Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Guest Information',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 4),
              const Text('Please fill in your details', style: TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: _inputDeco('Full Name *', Icons.person),
                validator: (v) => (v?.trim().isEmpty ?? true) ? 'Please enter your name' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: _inputDeco('Phone Number *', Icons.phone),
                validator: (v) => (v?.trim().isEmpty ?? true) ? 'Please enter your phone' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: _inputDeco('Email Address (Optional)', Icons.email),
              ),
              const SizedBox(height: 14),
              // Guest count
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Number of Guests', style: TextStyle(fontWeight: FontWeight.w600)),
                Row(children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, color: AppTheme.primaryColor),
                    onPressed: _guestCount > 1 ? () => setState(() => _guestCount--) : null,
                  ),
                  Container(
                    width: 36,
                    alignment: Alignment.center,
                    child: Text('$_guestCount', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, color: AppTheme.primaryColor),
                    onPressed: _guestCount < (_selectedRoom?['max_occupancy'] as int? ?? 10)
                        ? () => setState(() => _guestCount++)
                        : null,
                  ),
                ]),
              ]),
              const SizedBox(height: 14),
              TextFormField(
                controller: _notesCtrl,
                maxLines: 2,
                decoration: _inputDeco('Special Requests (Optional)', Icons.notes),
              ),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => setState(() => _step = 1),
                    child: const Text('Back'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      if (_formKey.currentState!.validate()) setState(() => _step = 3);
                    },
                    child: const Text('Continue to Payment', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    ]);
  }

  // ── STEP 3: Payment ─────────────────────────────────────────────────────
  Widget _buildStep3Payment() {
    return Column(key: const ValueKey(3), children: [
      _selectedRoomSummaryCard(),
      const SizedBox(height: 20),
      Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Payment', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 20),
            // Amount due
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppTheme.primaryColor, Color(0xFFBF360C)]),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(children: [
                const Text('Total Amount Due', style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 6),
                Text('Rs. ${_totalAmount.toStringAsFixed(0)}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 32)),
                Text('$_nights night${_nights != 1 ? 's' : ''} × Rs. ${(_selectedRoom?['price_per_night'] as num?)?.toStringAsFixed(0) ?? 0}/night',
                    style: const TextStyle(color: Colors.white60, fontSize: 12)),
              ]),
            ),
            const SizedBox(height: 20),

            if (_paymentQrUrl != null && _paymentQrUrl!.isNotEmpty) ...[
              const Text('Scan QR to Pay', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 8),
              const Text('Open your banking app, scan the QR below and send the exact amount.',
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 16),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 12)],
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(_paymentQrUrl!, width: 220, height: 220, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox(
                          width: 220, height: 220,
                          child: Center(child: Icon(Icons.qr_code, size: 80, color: Colors.grey)),
                        )),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _txRefCtrl,
                decoration: _inputDeco('Transaction Reference ID *', Icons.receipt_long).copyWith(
                  hintText: 'e.g. TXN123456789',
                  helperText: 'Copy the reference/transaction ID from your banking app',
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: const Row(children: [
                  Icon(Icons.info, color: Colors.amber),
                  SizedBox(width: 12),
                  Expanded(child: Text('No online QR payment configured. You can pay cash at reception on arrival.',
                      style: TextStyle(color: Colors.black87))),
                ]),
              ),
            ],
            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => setState(() => _step = 2),
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 4,
                    shadowColor: Colors.green.withOpacity(0.4),
                  ),
                  onPressed: _isSubmitting ? null : _submitBooking,
                  child: _isSubmitting
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.lock),
                          SizedBox(width: 8),
                          Text('Confirm Booking', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ]),
                ),
              ),
            ]),
          ]),
        ),
      ),
    ]);
  }

  Widget _selectedRoomSummaryCard() {
    if (_selectedRoom == null) return const SizedBox();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.primaryColor.withOpacity(0.2)),
      ),
      child: Row(children: [
        const Icon(Icons.hotel, color: AppTheme.primaryColor),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Room ${_selectedRoom!['room_number']} — ${(_selectedRoom!['type'] as String).toUpperCase()}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('${DateFormat('MMM d').format(_checkInDate)} → ${DateFormat('MMM d').format(_checkOutDate)} · $_nights nights',
              style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ])),
        Text('Rs. ${_totalAmount.toStringAsFixed(0)}',
            style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryColor, fontSize: 16)),
      ]),
    );
  }

  InputDecoration _inputDeco(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: const Color(0xFFF8F9FA),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
    );
  }

  // ── SUCCESS: Room Pass ──────────────────────────────────────────────────
  Widget _buildRoomPass() {
    final b = _completedBooking!;
    final room = b['rooms'] as Map<String, dynamic>;
    final bookingId = b['id'] as String;
    final shortId = bookingId.substring(0, 8).toUpperCase();

    final status = b['status'] as String? ?? 'pending';
    final paymentStatus = b['payment_status'] as String? ?? 'unpaid';

    String statusText = 'Pending';
    Color statusColor = Colors.orange;
    IconData statusIcon = Icons.hourglass_empty;

    Gradient bannerGradient = const LinearGradient(colors: [Colors.orange, Color(0xFFE65100)]);
    String bannerTitle = 'Booking Submitted!';
    String bannerSubtitle = 'Your request is pending confirmation from the hotel staff.';

    if (status == 'pending') {
      statusText = 'Pending Confirmation';
      statusColor = Colors.orange;
      statusIcon = Icons.hourglass_empty;
      bannerGradient = const LinearGradient(colors: [Colors.orange, Color(0xFFE65100)]);
      bannerTitle = 'Booking Submitted!';
      bannerSubtitle = 'Your request is pending confirmation from the hotel staff.';
    } else if (status == 'confirmed') {
      statusText = 'Confirmed';
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
      bannerGradient = const LinearGradient(colors: [Colors.green, Color(0xFF2E7D32)]);
      bannerTitle = 'Booking Confirmed!';
      bannerSubtitle = 'Your reservation is confirmed! Check-in: ${b['check_in_date']}.';
    } else if (status == 'checked_in') {
      statusText = 'Checked In';
      statusColor = Colors.blue;
      statusIcon = Icons.vpn_key;
      bannerGradient = const LinearGradient(colors: [Colors.blue, Color(0xFF0D47A1)]);
      bannerTitle = 'Welcome to Room ${room['room_number']}!';
      bannerSubtitle = 'You are currently checked in. Enjoy your stay!';
    } else if (status == 'checked_out') {
      statusText = 'Checked Out';
      statusColor = Colors.grey;
      statusIcon = Icons.done_all;
      bannerGradient = const LinearGradient(colors: [Colors.grey, Color(0xFF424242)]);
      bannerTitle = 'Checked Out';
      bannerSubtitle = 'Thank you for staying with us! Safe travels.';
    } else if (status == 'cancelled') {
      statusText = 'Cancelled';
      statusColor = Colors.red;
      statusIcon = Icons.cancel;
      bannerGradient = const LinearGradient(colors: [Colors.red, Color(0xFFB71C1C)]);
      bannerTitle = 'Booking Cancelled';
      bannerSubtitle = 'This reservation has been cancelled.';
    }

    String payText = 'Unpaid';
    Color payColor = Colors.red;
    if (paymentStatus == 'paid') {
      payText = 'Verified & Paid';
      payColor = Colors.green;
    } else if (paymentStatus == 'pending_verification') {
      payText = 'Pending Verification';
      payColor = Colors.orange;
    } else if (paymentStatus == 'partial') {
      payText = 'Partially Paid';
      payColor = Colors.blue;
    }

    return Column(children: [
      const SizedBox(height: 16),
      // Success banner
      Container(
        padding: const EdgeInsets.all(20),
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: bannerGradient,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(children: [
          Icon(statusIcon, color: Colors.white, size: 56),
          const SizedBox(height: 12),
          Text(bannerTitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22)),
          const SizedBox(height: 6),
          Text(bannerSubtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ]),
      ),
      const SizedBox(height: 20),
      // Room Pass Card
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 8)),
          ],
        ),
        child: Column(children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [AppTheme.primaryColor, Color(0xFFBF360C)]),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(children: [
              Text(_cafeName ?? 'Hotel', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
              const SizedBox(height: 4),
              const Text('ROOM BOOKING PASS', style: TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 2)),
            ]),
          ),
          // QR Code
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade100),
                ),
                child: QrImageView(data: bookingId, version: QrVersions.auto, size: 180),
              ),
              const SizedBox(height: 10),
              Text('Booking ID: $shortId',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 2)),
              const SizedBox(height: 4),
              const Text('Show this QR to hotel staff at check-in',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
            ]),
          ),
          // Divider with scissors
          Row(children: [
            const SizedBox(width: 8),
            const Icon(Icons.cut, color: Colors.grey, size: 16),
            Expanded(child: DashedDivider()),
            const SizedBox(width: 8),
          ]),
          // Booking details
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              _passRow('Guest Name', b['guest_name']),
              _passRow('Phone', b['guest_phone']),
              _passRow('Room', 'Room ${room['room_number']} (${(room['type'] as String).toUpperCase()})'),
              _passRow('Floor', 'Floor ${room['floor_number'] ?? 1}'),
              _passRow('Check-In', b['check_in_date']),
              _passRow('Check-Out', b['check_out_date']),
              _passRow('Nights', '$_nights night(s)'),
              const Divider(height: 20),
              _passRow('Total Amount', 'Rs. ${b['total_amount']?.toStringAsFixed(0) ?? '0'}',
                  highlight: true),
              _passRow('Booking Status', statusText, color: statusColor),
              _passRow('Payment Status', payText, color: payColor),
            ]),
          ),
          // Bottom note
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            child: Column(children: [
              const Text('Please save a screenshot of this booking pass.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 4),
              SelectableText(
                'Ref: $bookingId',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 10),
              ),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 20),
      // Copy tracking link button
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: () {
          final trackingUrl = "${Uri.base.origin}${Uri.base.path}?booking_id=$bookingId&cafe_id=$_cafeId";
          Clipboard.setData(ClipboardData(text: trackingUrl));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tracking Link copied! Bookmark it to check status later.')),
          );
        },
        icon: const Icon(Icons.link),
        label: const Text('Copy Direct Tracking Link'),
      ),
      const SizedBox(height: 12),
      // Copy booking ID button
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: () {
          Clipboard.setData(ClipboardData(text: bookingId));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Booking ID copied!')),
          );
        },
        icon: const Icon(Icons.copy),
        label: const Text('Copy Booking ID'),
      ),
      const SizedBox(height: 12),
      ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryColor,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: () {
          setState(() {
            _step = 0;
            _completedBooking = null;
            _selectedRoom = null;
            _nameCtrl.clear();
            _phoneCtrl.clear();
            _emailCtrl.clear();
            _txRefCtrl.clear();
            _notesCtrl.clear();
            _trackBookingIdCtrl.clear();
            _trackingTimer?.cancel();
          });
          _loadRooms();
        },
        icon: const Icon(Icons.add),
        label: const Text('Book Another Room'),
      ),
    ]);
  }

  Widget _passRow(String label, String value, {bool highlight = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5.0),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        Text(value, style: TextStyle(
          fontWeight: highlight ? FontWeight.bold : FontWeight.w600,
          color: color ?? (highlight ? AppTheme.primaryColor : AppTheme.textPrimary),
          fontSize: highlight ? 16 : 13,
        )),
      ]),
    );
  }
}

class DashedDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final dashCount = (constraints.constrainWidth() / 8).floor();
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(dashCount, (_) => Container(
          width: 4, height: 1, color: Colors.grey.shade300,
        )),
      );
    });
  }
}

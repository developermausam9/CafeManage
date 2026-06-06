import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../../../core/presentation/theme/app_theme.dart';
import '../../../../core/network/supabase_config.dart';

class CustomerBookingScreen extends StatefulWidget {
  const CustomerBookingScreen({super.key});

  @override
  State<CustomerBookingScreen> createState() => _CustomerBookingScreenState();
}

class _CustomerBookingScreenState extends State<CustomerBookingScreen> {
  final SupabaseClient _client = SupabaseConfig.client;

  String? _cafeId;
  String? _cafeName;
  String? _paymentQrUrl;
  bool _isLoading = true;
  String? _errorMessage;

  DateTime _checkInDate = DateTime.now().add(const Duration(days: 1));
  DateTime _checkOutDate = DateTime.now().add(const Duration(days: 2));

  List<Map<String, dynamic>> _rooms = [];
  List<Map<String, dynamic>> _bookings = [];
  List<Map<String, dynamic>> _availableRooms = [];
  bool _checkingAvailability = false;

  // Booking Form Controllers
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _txRefCtrl = TextEditingController();

  Map<String, dynamic>? _selectedRoom;
  bool _bookingSubmitted = false;
  String? _submittedBookingId;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Map<String, String> _getQueryParams() {
    final params = Map<String, String>.from(Uri.base.queryParameters);
    final fragment = Uri.base.fragment;
    if (fragment.contains('?')) {
      final queryString = fragment.split('?').last;
      final parts = queryString.split('&');
      for (var part in parts) {
        final kv = part.split('=');
        if (kv.length == 2) {
          params[kv[0]] = Uri.decodeComponent(kv[1]);
        }
      }
    }
    return params;
  }

  Future<void> _initializeData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final params = _getQueryParams();
    _cafeId = params['cafe_id'];

    if (_cafeId == null || _cafeId!.isEmpty) {
      // Look up first cafe as fallback for convenience
      try {
        final cafes = await _client.from('cafes').select('id, name').limit(1);
        if (cafes.isNotEmpty) {
          _cafeId = cafes.first['id'];
          _cafeName = cafes.first['name'];
        } else {
          setState(() {
            _errorMessage = 'No active hotels/cafes found in the system.';
            _isLoading = false;
          });
          return;
        }
      } catch (e) {
        setState(() {
          _errorMessage = 'Invalid URL configuration. Missing cafe_id.';
          _isLoading = false;
        });
        return;
      }
    }

    try {
      // Load Cafe Name & QR payment settings
      final cafeRes = await _client.from('cafes').select('name').eq('id', _cafeId!).single();
      _cafeName = cafeRes['name'];

      final settingsRes = await _client.from('settings').select('payment_qr_url').eq('cafe_id', _cafeId!).maybeSingle();
      if (settingsRes != null) {
        _paymentQrUrl = settingsRes['payment_qr_url'];
      }

      await _loadRoomsAndBookings();
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load hotel configuration: $e';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadRoomsAndBookings() async {
    final roomsRes = await _client.from('rooms').select().eq('cafe_id', _cafeId!);
    _rooms = List<Map<String, dynamic>>.from(roomsRes);

    final bookingsRes = await _client
        .from('room_bookings')
        .select()
        .eq('cafe_id', _cafeId!)
        .not('status', 'eq', 'cancelled');
    _bookings = List<Map<String, dynamic>>.from(bookingsRes);

    _runAvailabilityCheck();
  }

  void _runAvailabilityCheck() {
    setState(() => _checkingAvailability = true);

    final checkInStr = DateFormat('yyyy-MM-dd').format(_checkInDate);
    final checkOutStr = DateFormat('yyyy-MM-dd').format(_checkOutDate);

    final overlapBookings = _bookings.where((b) {
      final bIn = b['check_in_date'] as String;
      final bOut = b['check_out_date'] as String;
      // Overlap formula: start1 < end2 && start2 < end1
      return checkInStr.compareTo(bOut) < 0 && bIn.compareTo(checkOutStr) < 0;
    }).toList();

    final bookedRoomIds = overlapBookings.map((b) => b['room_id'] as String).toSet();

    setState(() {
      _availableRooms = _rooms.where((room) {
        // Must be available status and not booked in this range
        final isNotBooked = !bookedRoomIds.contains(room['id']);
        final isClean = room['status'] == 'available' || room['status'] == 'dirty';
        return isNotBooked && isClean;
      }).toList();
      
      _selectedRoom = null;
      _checkingAvailability = false;
    });
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _checkInDate, end: _checkOutDate),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.primaryColor,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: AppTheme.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _checkInDate = picked.start;
        _checkOutDate = picked.end;
      });
      _runAvailabilityCheck();
    }
  }

  int get _nightsCount => _checkOutDate.difference(_checkInDate).inDays;

  Future<void> _submitBooking() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedRoom == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a room to book.'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _checkingAvailability = true);

    try {
      final totalAmount = _selectedRoom!['price_per_night'] * _nightsCount;

      final res = await _client.from('room_bookings').insert({
        'cafe_id': _cafeId,
        'room_id': _selectedRoom!['id'],
        'guest_name': _nameCtrl.text.trim(),
        'guest_phone': _phoneCtrl.text.trim(),
        'guest_email': _emailCtrl.text.trim(),
        'check_in_date': DateFormat('yyyy-MM-dd').format(_checkInDate),
        'check_out_date': DateFormat('yyyy-MM-dd').format(_checkOutDate),
        'status': 'pending',
        'total_amount': totalAmount,
        'payment_status': _txRefCtrl.text.trim().isNotEmpty ? 'pending' : 'unpaid',

        'transaction_ref': _txRefCtrl.text.trim(),
      }).select().single();

      // Update room status to occupied
      await _client.from('rooms').update({'status': 'occupied'}).eq('id', _selectedRoom!['id']);

      setState(() {
        _bookingSubmitted = true;
        _submittedBookingId = res['id'];
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Booking failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _checkingAvailability = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _txRefCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_errorMessage != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text(_errorMessage!, style: const TextStyle(fontSize: 18, color: AppTheme.textSecondary), textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Text('$_cafeName - Room Booking', style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 900),
            padding: const EdgeInsets.all(24.0),
            child: _bookingSubmitted ? _buildSuccessView() : _buildBookingFlow(),
          ),
        ),
      ),
    );
  }

  Widget _buildBookingFlow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Date selector Card
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 2,
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                const Text('Select Booking Dates', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildDateDisplayTile('Check-in', _checkInDate),
                    ),
                    const Icon(Icons.arrow_forward, color: Colors.grey),
                    Expanded(
                      child: _buildDateDisplayTile('Check-out', _checkOutDate),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.date_range),
                  label: const Text('Change Dates', style: TextStyle(fontSize: 16)),
                  onPressed: () => _selectDateRange(context),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Available rooms
        const Text('Available Rooms', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 12),
        _checkingAvailability
            ? const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            : _availableRooms.isEmpty
                ? const Card(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('No rooms available for these dates.', style: TextStyle(color: Colors.grey))),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _availableRooms.length,
                    itemBuilder: (context, index) {
                      final room = _availableRooms[index];
                      final isSelected = _selectedRoom != null && _selectedRoom!['id'] == room['id'];

                      return Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: isSelected ? AppTheme.primaryColor : Colors.transparent, width: 2),
                        ),
                        color: Colors.white,
                        elevation: 1,
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          title: Text('Room ${room['room_number']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text('${room['type'].toString().toUpperCase()} • Max ${room['max_occupancy']} Guests'),
                              Text('Floor ${room['floor_number']}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('Rs. ${room['price_per_night']}/night', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryColor, fontSize: 16)),
                              const SizedBox(height: 4),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isSelected ? Colors.green : AppTheme.primaryColor.withOpacity(0.1),
                                  foregroundColor: isSelected ? Colors.white : AppTheme.primaryColor,
                                  elevation: 0,
                                ),
                                onPressed: () {
                                  setState(() => _selectedRoom = room);
                                },
                                child: Text(isSelected ? 'Selected' : 'Select'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
        const SizedBox(height: 24),

        if (_selectedRoom != null) ...[
          // Guest details form
          const Text('Guest Details & Payment', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 12),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 2,
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(labelText: 'Guest Full Name *', border: OutlineInputBorder()),
                      validator: (value) => value == null || value.trim().isEmpty ? 'Please enter your name' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _phoneCtrl,
                      decoration: const InputDecoration(labelText: 'Guest Phone Number *', border: OutlineInputBorder()),
                      keyboardType: TextInputType.phone,
                      validator: (value) => value == null || value.trim().isEmpty ? 'Please enter your phone number' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _emailCtrl,
                      decoration: const InputDecoration(labelText: 'Guest Email (Optional)', border: OutlineInputBorder()),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),
                    const Text('Payment Verification', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    Text('Total Amount: Rs. ${(_selectedRoom!['price_per_night'] * _nightsCount).toStringAsFixed(0)} for $_nightsCount night(s)',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryColor, fontSize: 16)),
                    const SizedBox(height: 16),
                    if (_paymentQrUrl != null && _paymentQrUrl!.isNotEmpty) ...[
                      const Text('Scan this QR Code using your banking app to send the payment:', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                      const SizedBox(height: 16),
                      Center(
                        child: Container(
                          height: 250,
                          width: 250,
                          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(12)),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(_paymentQrUrl!, fit: BoxFit.cover, errorBuilder: (ctx, err, stack) => const Center(child: Text('QR Code Loading Error'))),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _txRefCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Transaction Reference ID (Reference ID) *',
                          border: OutlineInputBorder(),
                          hintText: 'e.g. TXN983274932',
                        ),
                        validator: (value) => value == null || value.trim().isEmpty ? 'Please enter the transaction reference ID' : null,
                      ),
                      const SizedBox(height: 8),
                      const Text('Please paste the reference ID from your banking app transaction receipt above so we can verify your booking payment.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ] else ...[
                      const Text('Note: No online QR payment has been configured by the admin yet. You can book now and pay cash at reception upon arrival.',
                          style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                    ],
                    const SizedBox(height: 32),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _submitBooking,
                      child: const Text('Confirm Booking', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDateDisplayTile(String title, DateTime date) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(DateFormat('EEE, MMM dd, yyyy').format(date), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
        ],
      ),
    );
  }

  Widget _buildSuccessView() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.white,
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 80),
            const SizedBox(height: 24),
            const Text('Booking Request Received!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            const SizedBox(height: 12),
            const Text(
              'Thank you for booking with us. Your booking is currently pending verification. We will process your payment and confirm your booking shortly.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            _buildInfoRow('Guest Name', _nameCtrl.text),
            _buildInfoRow('Room Booked', 'Room ${_selectedRoom!['room_number']} (${_selectedRoom!['type'].toString().toUpperCase()})'),
            _buildInfoRow('Check-In Date', DateFormat('MMM dd, yyyy').format(_checkInDate)),
            _buildInfoRow('Check-Out Date', DateFormat('MMM dd, yyyy').format(_checkOutDate)),
            _buildInfoRow('Nights Count', '$_nightsCount night(s)'),
            _buildInfoRow('Total Amount', 'Rs. ${(_selectedRoom!['price_per_night'] * _nightsCount).toStringAsFixed(0)}'),
            if (_txRefCtrl.text.isNotEmpty) _buildInfoRow('Transaction Ref', _txRefCtrl.text),
            const SizedBox(height: 32),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                minimumSize: const Size(200, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                setState(() {
                  _bookingSubmitted = false;
                  _nameCtrl.clear();
                  _phoneCtrl.clear();
                  _emailCtrl.clear();
                  _txRefCtrl.clear();
                  _selectedRoom = null;
                });
                _initializeData();
              },
              child: const Text('Book Another Room'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
        ],
      ),
    );
  }
}

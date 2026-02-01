/// Location Screen
/// 
/// Parent view showing child's real-time location on a map with history trail.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../models/location_record.dart';
import '../../models/geofence.dart';
import '../../services/location_service.dart';

class LocationScreen extends StatefulWidget {
  final String childId;
  final String? childName;

  const LocationScreen({
    super.key,
    required this.childId,
    this.childName,
  });

  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  final _locationService = LocationService();
  final _mapController = MapController();

  LocationRecord? _currentLocation;
  List<LocationRecord> _locationHistory = [];
  List<Geofence> _geofences = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final [location, history, geofences] = await Future.wait([
        _locationService.getLatestLocation(widget.childId),
        _locationService.getLocationHistory(widget.childId, hours: 24),
        _locationService.getGeofences(widget.childId),
      ]);

      setState(() {
        _currentLocation = location as LocationRecord?;
        _locationHistory = history as List<LocationRecord>;
        _geofences = geofences as List<Geofence>;
      });

      // Center map on current location if available
      if (_currentLocation != null) {
        _mapController.move(
          LatLng(_currentLocation!.latitude, _currentLocation!.longitude),
          15,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading location: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.childName ?? "Child's Location"),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Map
                Expanded(
                  flex: 3,
                  child: _buildMap(),
                ),

                // Info Panel
                Expanded(
                  flex: 2,
                  child: _buildInfoPanel(),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddGeofenceDialog(),
        icon: const Icon(Icons.add_location),
        label: const Text('Add Safe Zone'),
      ),
    );
  }

  Widget _buildMap() {
    // Default to a generic location if no data
    final center = _currentLocation != null
        ? LatLng(_currentLocation!.latitude, _currentLocation!.longitude)
        : const LatLng(0, 0);

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 15,
      ),
      children: [
        // OpenStreetMap tiles
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.parentlock.parentlock',
        ),

        // Geofence circles
        CircleLayer(
          circles: _geofences.map((g) => CircleMarker(
            point: LatLng(g.latitude, g.longitude),
            radius: g.radiusMeters.toDouble(),
            color: Colors.blue.withOpacity(0.2),
            borderColor: Colors.blue,
            borderStrokeWidth: 2,
            useRadiusInMeter: true,
          )).toList(),
        ),

        // Location history trail
        PolylineLayer(
          polylines: [
            if (_locationHistory.length > 1)
              Polyline(
                points: _locationHistory
                    .map((l) => LatLng(l.latitude, l.longitude))
                    .toList(),
                color: Colors.blue.withOpacity(0.5),
                strokeWidth: 3,
              ),
          ],
        ),

        // Markers
        MarkerLayer(
          markers: [
            // Geofence labels
            ..._geofences.map((g) => Marker(
              point: LatLng(g.latitude, g.longitude),
              width: 100,
              height: 30,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                ),
                child: Text(
                  g.name,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            )),

            // Current location marker
            if (_currentLocation != null)
              Marker(
                point: LatLng(
                  _currentLocation!.latitude,
                  _currentLocation!.longitude,
                ),
                width: 50,
                height: 50,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8)],
                  ),
                  child: const Icon(
                    Icons.child_care,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, -2))],
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status bar
            if (_currentLocation != null)
              _buildStatusBar()
            else
              const Center(
                child: Text(
                  'No location data available',
                  style: TextStyle(color: Colors.grey),
                ),
              ),

            const SizedBox(height: 16),

            // Location History
            Text(
              '📍 Location History',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),

            if (_locationHistory.isEmpty)
              const Text('No history available', style: TextStyle(color: Colors.grey))
            else
              ..._locationHistory.take(5).map((location) => ListTile(
                dense: true,
                leading: const Icon(Icons.location_on, size: 20),
                title: Text(
                  _formatTime(location.recordedAt),
                  style: const TextStyle(fontSize: 14),
                ),
                subtitle: Text(
                  '${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}',
                  style: const TextStyle(fontSize: 12),
                ),
              )),

            const SizedBox(height: 16),

            // Safe Zones
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '🏠 Safe Zones',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${_geofences.length} zones',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (_geofences.isEmpty)
              const Text('No safe zones set up', style: TextStyle(color: Colors.grey))
            else
              ..._geofences.map((g) => ListTile(
                dense: true,
                leading: const Icon(Icons.shield, color: Colors.blue),
                title: Text(g.name),
                subtitle: Text('${g.radiusMeters}m radius'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _deleteGeofence(g),
                ),
              )),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    final timeSince = DateTime.now().difference(_currentLocation!.recordedAt);
    String timeAgo;
    if (timeSince.inMinutes < 1) {
      timeAgo = 'Just now';
    } else if (timeSince.inMinutes < 60) {
      timeAgo = '${timeSince.inMinutes} min ago';
    } else {
      timeAgo = '${timeSince.inHours}h ago';
    }

    return Row(
      children: [
        Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Text(
          'Last updated: $timeAgo',
          style: TextStyle(color: Colors.grey[600], fontSize: 13),
        ),
        const Spacer(),
        if (_currentLocation!.batteryLevel != null) ...[
          Icon(
            _currentLocation!.batteryLevel! > 20
                ? Icons.battery_std
                : Icons.battery_alert,
            size: 16,
            color: _currentLocation!.batteryLevel! > 20
                ? Colors.green
                : Colors.red,
          ),
          const SizedBox(width: 4),
          Text(
            '${_currentLocation!.batteryLevel}%',
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
        ],
      ],
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 60) {
      return '${diff.inMinutes} minutes ago';
    } else if (diff.inHours < 24) {
      final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
      final ampm = time.hour < 12 ? 'AM' : 'PM';
      return '$hour:${time.minute.toString().padLeft(2, '0')} $ampm';
    } else {
      return '${time.month}/${time.day} ${time.hour}:${time.minute.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _showAddGeofenceDialog() async {
    final nameController = TextEditingController();
    double radius = 100;

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setBottomState) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add Safe Zone',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Zone Name',
                  hintText: 'e.g., Home, School',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Text('Radius: ${radius.toInt()}m'),
              Slider(
                value: radius,
                min: 50,
                max: 500,
                divisions: 9,
                label: '${radius.toInt()}m',
                onChanged: (v) => setBottomState(() => radius = v),
              ),
              const SizedBox(height: 8),
              const Text(
                'The safe zone will be centered on your child\'s current location.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (nameController.text.isNotEmpty) {
                      Navigator.pop(context, {
                        'name': nameController.text,
                        'radius': radius.toInt(),
                      });
                    }
                  },
                  child: const Text('Create Safe Zone'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (result != null && _currentLocation != null) {
      await _createGeofence(result['name'], result['radius']);
    }
  }

  Future<void> _createGeofence(String name, int radius) async {
    if (_currentLocation == null) return;

    try {
      final geofence = Geofence(
        id: '',
        parentId: '', // Will be set by RLS
        childId: widget.childId,
        name: name,
        latitude: _currentLocation!.latitude,
        longitude: _currentLocation!.longitude,
        radiusMeters: radius,
        createdAt: DateTime.now(),
      );

      await _locationService.createGeofence(geofence);
      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Safe zone "$name" created!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating safe zone: $e')),
        );
      }
    }
  }

  Future<void> _deleteGeofence(Geofence geofence) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Safe Zone'),
        content: Text('Are you sure you want to delete "${geofence.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _locationService.deleteGeofence(geofence.id);
        await _loadData();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Safe zone "${geofence.name}" deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting safe zone: $e')),
          );
        }
      }
    }
  }
}

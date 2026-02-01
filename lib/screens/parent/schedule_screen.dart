/// Schedule Screen
/// 
/// Parent view for managing screen time schedules (bedtime, homework, allowed hours).
library;

import 'package:flutter/material.dart';
import '../../models/schedule.dart';
import '../../services/schedule_service.dart';
import '../../services/auth_service.dart';

class ScheduleScreen extends StatefulWidget {
  final String childId;
  final String? childName;

  const ScheduleScreen({
    super.key,
    required this.childId,
    this.childName,
  });

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  final _scheduleService = ScheduleService();
  final _authService = AuthService();

  List<Schedule> _schedules = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSchedules();
  }

  Future<void> _loadSchedules() async {
    setState(() => _isLoading = true);

    try {
      final schedules = await _scheduleService.getSchedules(widget.childId);
      setState(() => _schedules = schedules);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading schedules: $e')),
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
        title: Text('${widget.childName ?? "Child"} Schedules'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _schedules.isEmpty
              ? _buildEmptyState()
              : _buildScheduleList(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showScheduleEditor(null),
        icon: const Icon(Icons.add),
        label: const Text('Add Schedule'),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.schedule, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'No schedules yet',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create bedtime or homework schedules',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _schedules.length,
      itemBuilder: (context, index) {
        final schedule = _schedules[index];
        return _ScheduleCard(
          schedule: schedule,
          onToggle: (active) => _toggleSchedule(schedule, active),
          onEdit: () => _showScheduleEditor(schedule),
          onDelete: () => _deleteSchedule(schedule),
        );
      },
    );
  }

  Future<void> _toggleSchedule(Schedule schedule, bool active) async {
    try {
      await _scheduleService.toggleScheduleActive(schedule.id, active);
      await _loadSchedules();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating schedule: $e')),
        );
      }
    }
  }

  Future<void> _deleteSchedule(Schedule schedule) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Schedule'),
        content: Text('Delete "${schedule.name}"?'),
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
        await _scheduleService.deleteSchedule(schedule.id);
        await _loadSchedules();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }
  }

  Future<void> _showScheduleEditor(Schedule? existing) async {
    final result = await showModalBottomSheet<Schedule>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ScheduleEditorSheet(
        existing: existing,
        childId: widget.childId,
        parentId: _authService.currentUser?.id ?? '',
      ),
    );

    if (result != null) {
      try {
        if (existing != null) {
          await _scheduleService.updateSchedule(result);
        } else {
          await _scheduleService.createSchedule(result);
        }
        await _loadSchedules();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(existing != null ? 'Schedule updated!' : 'Schedule created!'),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }
  }
}

class _ScheduleCard extends StatelessWidget {
  final Schedule schedule;
  final void Function(bool) onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ScheduleCard({
    required this.schedule,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isActiveNow = schedule.isActiveNow(DateTime.now());

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isActiveNow ? Colors.orange.shade50 : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  schedule.scheduleType.icon,
                  style: const TextStyle(fontSize: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        schedule.name,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        schedule.timeRangeDisplay,
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: schedule.isActive,
                  onChanged: onToggle,
                  activeColor: Colors.green,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  schedule.daysDisplay,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const Spacer(),
                if (schedule.blockAllApps)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Blocks All',
                      style: TextStyle(fontSize: 11, color: Colors.red),
                    ),
                  )
                else if (schedule.blockedCategories?.isNotEmpty == true)
                  Text(
                    'Blocks: ${schedule.blockedCategories!.join(", ")}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
              ],
            ),
            if (isActiveNow) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '● ACTIVE NOW',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('Edit'),
                ),
                TextButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete, size: 18),
                  label: const Text('Delete'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleEditorSheet extends StatefulWidget {
  final Schedule? existing;
  final String childId;
  final String parentId;

  const _ScheduleEditorSheet({
    this.existing,
    required this.childId,
    required this.parentId,
  });

  @override
  State<_ScheduleEditorSheet> createState() => _ScheduleEditorSheetState();
}

class _ScheduleEditorSheetState extends State<_ScheduleEditorSheet> {
  late TextEditingController _nameController;
  late ScheduleType _type;
  late List<int> _daysOfWeek;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late bool _blockAllApps;
  late Set<String> _blockedCategories;

  @override
  void initState() {
    super.initState();

    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _type = existing?.scheduleType ?? ScheduleType.bedtime;
    _daysOfWeek = existing?.daysOfWeek ?? [0, 1, 2, 3, 4, 5, 6];
    _startTime = existing != null
        ? TimeOfDay(hour: existing.startTime.hour, minute: existing.startTime.minute)
        : const TimeOfDay(hour: 21, minute: 0);
    _endTime = existing != null
        ? TimeOfDay(hour: existing.endTime.hour, minute: existing.endTime.minute)
        : const TimeOfDay(hour: 7, minute: 0);
    _blockAllApps = existing?.blockAllApps ?? true;
    _blockedCategories = Set.from(existing?.blockedCategories ?? ['games', 'social']);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.existing != null ? 'Edit Schedule' : 'New Schedule',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),

            // Name
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Schedule Name',
                hintText: 'e.g., Bedtime, Homework Time',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // Type
            Text('Type', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<ScheduleType>(
              segments: ScheduleType.values.map((t) => ButtonSegment(
                value: t,
                label: Text(t.displayName),
                icon: Text(t.icon),
              )).toList(),
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 16),

            // Time Range
            Row(
              children: [
                Expanded(
                  child: _TimePickerTile(
                    label: 'Start Time',
                    time: _startTime,
                    onChanged: (t) => setState(() => _startTime = t),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _TimePickerTile(
                    label: 'End Time',
                    time: _endTime,
                    onChanged: (t) => setState(() => _endTime = t),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Days of Week
            Text('Days', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            _DaySelector(
              selectedDays: _daysOfWeek,
              onChanged: (days) => setState(() => _daysOfWeek = days),
            ),
            const SizedBox(height: 16),

            // Block options (for homework mode)
            if (_type == ScheduleType.homework) ...[
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Block all apps'),
                value: _blockAllApps,
                onChanged: (v) => setState(() => _blockAllApps = v ?? false),
              ),
              if (!_blockAllApps) ...[
                Text('Block categories:', style: Theme.of(context).textTheme.bodySmall),
                Wrap(
                  spacing: 8,
                  children: ['games', 'social', 'video'].map((cat) => FilterChip(
                    label: Text(cat),
                    selected: _blockedCategories.contains(cat),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _blockedCategories.add(cat);
                        } else {
                          _blockedCategories.remove(cat);
                        }
                      });
                    },
                  )).toList(),
                ),
              ],
            ],

            const SizedBox(height: 24),

            // Save Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _save,
                child: Text(widget.existing != null ? 'Update' : 'Create'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a name')),
      );
      return;
    }

    final schedule = Schedule(
      id: widget.existing?.id ?? '',
      parentId: widget.parentId,
      childId: widget.childId,
      name: _nameController.text,
      scheduleType: _type,
      daysOfWeek: _daysOfWeek,
      startTime: TimeOfDayData(hour: _startTime.hour, minute: _startTime.minute),
      endTime: TimeOfDayData(hour: _endTime.hour, minute: _endTime.minute),
      blockedCategories: _type == ScheduleType.homework
          ? _blockedCategories.toList()
          : null,
      blockAllApps: _type == ScheduleType.bedtime || _blockAllApps,
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
    );

    Navigator.pop(context, schedule);
  }
}

class _TimePickerTile extends StatelessWidget {
  final String label;
  final TimeOfDay time;
  final void Function(TimeOfDay) onChanged;

  const _TimePickerTile({
    required this.label,
    required this.time,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: time,
        );
        if (picked != null) onChanged(picked);
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            const SizedBox(height: 4),
            Text(
              time.format(context),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

class _DaySelector extends StatelessWidget {
  final List<int> selectedDays;
  final void Function(List<int>) onChanged;

  const _DaySelector({
    required this.selectedDays,
    required this.onChanged,
  });

  static const _dayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(7, (i) {
        final isSelected = selectedDays.contains(i);
        return InkWell(
          onTap: () {
            final newDays = List<int>.from(selectedDays);
            if (isSelected) {
              newDays.remove(i);
            } else {
              newDays.add(i);
            }
            onChanged(newDays);
          },
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey.shade200,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                _dayLabels[i],
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

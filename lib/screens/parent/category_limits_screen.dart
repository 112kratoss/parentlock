import 'package:flutter/material.dart';
import '../../services/database_service.dart';
import '../../models/category_limit.dart';
import '../../models/child_activity.dart';

class CategoryLimitsScreen extends StatefulWidget {
  final String childId;
  final String childName;

  const CategoryLimitsScreen({
    Key? key,
    required this.childId,
    required this.childName,
  }) : super(key: key);

  @override
  State<CategoryLimitsScreen> createState() => _CategoryLimitsScreenState();
}

class _CategoryLimitsScreenState extends State<CategoryLimitsScreen> {
  final DatabaseService _databaseService = DatabaseService();
  bool _isLoading = true;
  List<CategoryLimit> _limits = [];
  Map<String, int> _usage = {}; // Category -> Minutes used today
  
  // Standard Android categories
  final List<String> _categories = [
    'social',
    'game',
    'video',
    'audio',
    'image',
    'productivity',
    'news',
    'maps',
    'other',
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // 1. Fetch current limits
      final limits = await _databaseService.getCategoryLimits(widget.childId);
      
      // 2. Fetch usage to calculate today's category totals
      final activities = await _databaseService.getChildActivities(widget.childId);
      final usageMap = <String, int>{};
      for (var a in activities) {
        final cat = a.category.isEmpty ? 'other' : a.category;
        usageMap[cat] = (usageMap[cat] ?? 0) + a.minutesUsed;
      }

      if (mounted) {
        setState(() {
          _limits = limits;
          _usage = usageMap;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading limits: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _setLimit(String category, int? limitMinutes) async {
    try {
      if (limitMinutes == null) {
        // Remove limit
        await _databaseService.deleteCategoryLimit(widget.childId, category);
      } else {
        // Set limit
        final limit = CategoryLimit(
          id: '', // database will generate or ignore for upsert
          childId: widget.childId,
          category: category,
          dailyLimitMinutes: limitMinutes,
          lastUpdated: DateTime.now(),
        );
        await _databaseService.upsertCategoryLimit(limit);
      }
      
      await _loadData(); // Refresh
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Limit updated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating limit: $e')),
        );
      }
    }
  }

  String _formatCategory(String cat) {
    if (cat.isEmpty) return 'Other';
    return cat[0].toUpperCase() + cat.substring(1);
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'game': return Icons.games;
      case 'social': return Icons.people;
      case 'video': return Icons.video_library;
      case 'audio': return Icons.audiotrack;
      case 'image': return Icons.image;
      case 'productivity': return Icons.work;
      case 'news': return Icons.newspaper;
      case 'maps': return Icons.map;
      default: return Icons.category;
    }
  }

  void _showLimitDialog(String category, int? currentLimit) {
    final controller = TextEditingController(
      text: currentLimit?.toString() ?? '',
    );
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Set Limit for ${_formatCategory(category)}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
             const Text('Enter daily limit in minutes (or leave empty for unlimited).'),
             const SizedBox(height: 16),
             TextField(
               controller: controller,
               keyboardType: TextInputType.number,
               decoration: const InputDecoration(
                 labelText: 'Minutes',
                 border: OutlineInputBorder(),
                 suffixText: 'min',
               ),
             ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) {
                _setLimit(category, null);
              } else {
                final mins = int.tryParse(text);
                if (mins != null && mins >= 0) {
                  _setLimit(category, mins);
                }
              }
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.childName} - Category Limits'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final category = _categories[index];
                
                // Find existing limit
                final limitObj = _limits.firstWhere(
                  (l) => l.category == category, 
                  orElse: () => CategoryLimit(
                    id: '', childId: '', category: '', dailyLimitMinutes: -1, lastUpdated: DateTime.now()
                  )
                );
                final hasLimit = limitObj.dailyLimitMinutes != -1;
                final limitMinutes = hasLimit ? limitObj.dailyLimitMinutes : null;
                
                final usage = _usage[category] ?? 0;
                
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                      child: Icon(_getCategoryIcon(category), color: Theme.of(context).primaryColor),
                    ),
                    title: Text(_formatCategory(category)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Used today: ${usage}m'),
                        if (hasLimit)
                          Text(
                            'Limit: ${limitMinutes}m',
                            style: TextStyle(
                              color: usage >= limitMinutes! ? Colors.red : Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                    trailing: hasLimit
                        ? IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => _showLimitDialog(category, limitMinutes),
                          )
                        : OutlinedButton(
                            onPressed: () => _showLimitDialog(category, null),
                            child: const Text('Set Limit'),
                          ),
                    onTap: () => _showLimitDialog(category, limitMinutes),
                  ),
                );
              },
            ),
    );
  }
}

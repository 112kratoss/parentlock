/// Reports Screen
/// 
/// Parent view showing activity reports with charts and usage trends.
library;

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../models/usage_report.dart';
import '../../models/child_activity.dart';
import '../../services/database_service.dart';

class ReportsScreen extends StatefulWidget {
  final String childId;
  final String? childName;

  const ReportsScreen({
    super.key,
    required this.childId,
    this.childName,
  });

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final _databaseService = DatabaseService();

  String _period = 'week'; // 'today', 'week', 'month'
  Map<String, dynamic>? _stats;
  List<ChildActivity> _activities = [];
  List<Map<String, dynamic>> _trendData = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final days = _period == 'today' ? 1 : (_period == 'week' ? 7 : 30);
      
      final [stats, activities, trend] = await Future.wait([
        _databaseService.getChildStats(widget.childId),
        _databaseService.getChildActivities(widget.childId),
        _databaseService.getUsageTrend(widget.childId, days: days),
      ]);

      setState(() {
        _stats = stats as Map<String, dynamic>;
        _activities = activities as List<ChildActivity>;
        _trendData = trend as List<Map<String, dynamic>>;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading reports: $e')),
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
        title: Text('${widget.childName ?? "Child"} Activity'),
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
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Period Selector
                  _buildPeriodSelector(),
                  const SizedBox(height: 20),

                  // Summary Cards
                  _buildSummaryCards(),
                  const SizedBox(height: 24),

                  // Usage Trend Chart
                  _buildTrendChart(),
                  const SizedBox(height: 24),

                  // Category Breakdown
                  _buildCategoryBreakdown(),
                  const SizedBox(height: 24),

                  // Category Breakdown
                  _buildCategoryBreakdown(),
                  const SizedBox(height: 24),

                  // Top Apps Chart
                  _buildTopAppsChart(),
                  const SizedBox(height: 24),

                  // Top Apps List
                  _buildTopApps(),
                ],
              ),
            ),
    );
  }

  Widget _buildTopAppsChart() {
    final sortedApps = [..._activities]
      ..sort((a, b) => b.minutesUsed.compareTo(a.minutesUsed));
    final topApps = sortedApps.take(5).toList();

    if (topApps.isEmpty || topApps.every((a) => a.minutesUsed == 0)) {
      return const SizedBox();
    }

    final maxY = topApps.first.minutesUsed.toDouble() * 1.2;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '📊 Top Apps Chart',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxY > 0 ? maxY : 60,
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final app = topApps[group.x.toInt()];
                        return BarTooltipItem(
                          '${app.appDisplayName}\n',
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                          children: [
                            TextSpan(
                              text: _formatDuration(app.minutesUsed),
                              style: const TextStyle(
                                color: Colors.yellow,
                                fontSize: 12,
                                fontWeight: FontWeight.normal,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= topApps.length) {
                            return const SizedBox();
                          }
                          final app = topApps[index];
                          // Truncate name if too long
                          String name = app.appDisplayName;
                          if (name.length > 8) {
                            name = '${name.substring(0, 6)}..';
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Tooltip(
                              message: app.appDisplayName,
                              child: Text(
                                name,
                                style: const TextStyle(fontSize: 10),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          );
                        },
                        reservedSize: 40,
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          if (value == 0) return const SizedBox();
                          final hours = value / 60;
                          return Text(
                            hours >= 1 ? '${hours.toStringAsFixed(1)}h' : '${value.toInt()}m',
                            style: const TextStyle(fontSize: 10),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 30,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: Colors.grey.withOpacity(0.2),
                      strokeWidth: 1,
                    ),
                  ),
                  barGroups: topApps.asMap().entries.map((entry) {
                    final index = entry.key;
                    final app = entry.value;
                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: app.minutesUsed.toDouble(),
                          color: _getRankColor(index + 1),
                          width: 20,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'today', label: Text('Today')),
        ButtonSegment(value: 'week', label: Text('This Week')),
        ButtonSegment(value: 'month', label: Text('This Month')),
      ],
      selected: {_period},
      onSelectionChanged: (s) {
        setState(() => _period = s.first);
        _loadData();
      },
    );
  }

  Widget _buildSummaryCards() {
    final todayMinutes = _stats?['today_minutes'] ?? 0;
    final weeklyMinutes = _stats?['weekly_total_minutes'] ?? 0;
    final blockedApps = _stats?['blocked_apps'] ?? 0;

    return Row(
      children: [
        Expanded(
          child: _SummaryCard(
            icon: Icons.timer,
            label: 'Today',
            value: _formatDuration(todayMinutes),
            color: Colors.blue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryCard(
            icon: Icons.calendar_today,
            label: 'This Week',
            value: _formatDuration(weeklyMinutes),
            color: Colors.green,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryCard(
            icon: Icons.block,
            label: 'Blocked',
            value: '$blockedApps',
            color: Colors.red,
          ),
        ),
      ],
    );
  }

  Widget _buildTrendChart() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '📈 Usage Trend',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: _trendData.isEmpty
                  ? const Center(child: Text('No data available'))
                  : BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: _getMaxY(),
                        barTouchData: BarTouchData(
                          enabled: true,
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipItem: (group, groupIndex, rod, rodIndex) {
                              return BarTooltipItem(
                                '${rod.toY.toInt()} min',
                                const TextStyle(color: Colors.white),
                              );
                            },
                          ),
                        ),
                        titlesData: FlTitlesData(
                          show: true,
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, meta) {
                                final index = value.toInt();
                                if (index < 0 || index >= _trendData.length) {
                                  return const SizedBox();
                                }
                                final date = DateTime.parse(_trendData[index]['date']);
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    _getDayLabel(date),
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                );
                              },
                              reservedSize: 30,
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              getTitlesWidget: (value, meta) {
                                if (value == 0) return const SizedBox();
                                final hours = value / 60;
                                return Text(
                                  hours >= 1 ? '${hours.toStringAsFixed(1)}h' : '${value.toInt()}m',
                                  style: const TextStyle(fontSize: 10),
                                );
                              },
                            ),
                          ),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        borderData: FlBorderData(show: false),
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval: 60, // Every hour
                        ),
                        barGroups: _trendData.asMap().entries.map((entry) {
                          final minutes = entry.value['total_minutes'] ?? 0;
                          return BarChartGroupData(
                            x: entry.key,
                            barRods: [
                              BarChartRodData(
                                toY: minutes.toDouble(),
                                color: Theme.of(context).colorScheme.primary,
                                width: 20,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryBreakdown() {
    // Aggregate by category
    final Map<String, int> categories = {};
    for (final activity in _activities) {
      final category = AppCategoryMapper.categorize(activity.appPackageName);
      categories[category] = (categories[category] ?? 0) + activity.minutesUsed;
    }

    final total = categories.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) return const SizedBox();

    final sortedCategories = categories.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final colors = {
      'social': Colors.pink,
      'video': Colors.red,
      'games': Colors.purple,
      'education': Colors.green,
      'other': Colors.grey,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '📊 Usage by Category',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ...sortedCategories.map((entry) {
              final percent = entry.value / total;
              final color = colors[entry.key] ?? Colors.grey;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _capitalize(entry.key),
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        Text(
                          _formatDuration(entry.value),
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: percent,
                      backgroundColor: color.withOpacity(0.2),
                      valueColor: AlwaysStoppedAnimation(color),
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildTopApps() {
    final sortedApps = [..._activities]
      ..sort((a, b) => b.minutesUsed.compareTo(a.minutesUsed));
    final topApps = sortedApps.take(5).toList();

    if (topApps.isEmpty) return const SizedBox();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '📱 Top Apps',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            ...topApps.asMap().entries.map((entry) {
              final app = entry.value;
              final rank = entry.key + 1;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: _getRankColor(rank),
                  child: Text(
                    '$rank',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                title: Text(app.appDisplayName),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatDuration(app.minutesUsed),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (app.dailyLimitMinutes > 0)
                      Text(
                        'Limit: ${app.dailyLimitMinutes}m',
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // Helpers
  String _formatDuration(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m > 0 ? '${h}h ${m}m' : '${h}h';
  }

  double _getMaxY() {
    if (_trendData.isEmpty) return 120;
    final max = _trendData.fold<int>(
      0,
      (m, d) => (d['total_minutes'] ?? 0) > m ? d['total_minutes'] : m,
    );
    return (max * 1.2).clamp(60, double.infinity).toDouble();
  }

  String _getDayLabel(DateTime date) {
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return days[date.weekday % 7];
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  Color _getRankColor(int rank) {
    switch (rank) {
      case 1:
        return Colors.amber;
      case 2:
        return Colors.grey;
      case 3:
        return Colors.brown;
      default:
        return Colors.blueGrey;
    }
  }
}

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

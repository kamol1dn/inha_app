import 'package:flutter/material.dart';
import '../../models/class_session.dart';
import '../../services/timetable_service.dart';
import 'widgets/class_session_card.dart';

class TimetableScreen extends StatefulWidget {
  final bool demoMode;

  const TimetableScreen({
    Key? key,
    this.demoMode = false,
  }) : super(key: key);

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  final TimetableService _timetableService = TimetableService();
  late Future<Map<String, List<ClassSession>>> _timetableFuture;
  late List<String> _days;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _days = _timetableService.getDays();

    if (!widget.demoMode) {
      _fetchTimetable();
    }
  }

  void _fetchTimetable() {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    _timetableFuture = _timetableService.fetchTimetable();

    _timetableFuture.then((_) {
      setState(() {
        _isLoading = false;
      });
    }).catchError((error) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load timetable: ${error.toString()}';
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.demoMode) {
      return _buildTimetableUI(_timetableService.getDemoTimetable());
    } else {
      return _buildFetchUI();
    }
  }

  Widget _buildFetchUI() {
    if (_isLoading) {
      return _buildLoadingUI();
    }

    if (_errorMessage != null) {
      return _buildErrorUI();
    }

    return FutureBuilder<Map<String, List<ClassSession>>>(
      future: _timetableFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingUI();
        } else if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Colors.red,
                  size: 60,
                ),
                const SizedBox(height: 16),
                Text(
                  'Error: ${snapshot.error}',
                  style: const TextStyle(color: Colors.red),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _fetchTimetable,
                  child: const Text('Try Again'),
                ),
              ],
            ),
          );
        } else if (snapshot.hasData) {
          return _buildTimetableUI(snapshot.data!);
        } else {
          return const Center(child: Text('No data available'));
        }
      },
    );
  }

  Widget _buildLoadingUI() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Loading your timetable...'),
        ],
      ),
    );
  }

  Widget _buildErrorUI() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            color: Colors.red,
            size: 60,
          ),
          const SizedBox(height: 16),
          Text(
            _errorMessage ?? 'An unknown error occurred',
            style: const TextStyle(color: Colors.red),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _fetchTimetable,
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  Widget _buildTimetableUI(Map<String, List<ClassSession>> timetable) {
    return DefaultTabController(
      length: _days.length,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            labelColor: Colors.blue,
            unselectedLabelColor: Colors.grey,
            tabs: _days.map((day) => Tab(text: day)).toList(),
          ),
          Expanded(
            child: TabBarView(
              children: _days.map((day) {
                List<ClassSession> sessions = timetable[day] ?? [];

                return sessions.isEmpty
                    ? const Center(child: Text('No classes scheduled'))
                    : ListView.builder(
                  itemCount: sessions.length,
                  padding: const EdgeInsets.all(16),
                  itemBuilder: (context, index) {
                    return ClassSessionCard(session: sessions[index]);
                  },
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
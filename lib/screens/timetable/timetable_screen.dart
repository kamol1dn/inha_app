import 'package:flutter/material.dart';
import '../../models/class_session.dart';
import '../../models/edupage_models.dart';
import '../../services/edupage_service.dart';
import 'widgets/class_session_card.dart';

enum TimetableFilterType {
  student,
  group,
  demo,
}

class TimetableScreen extends StatefulWidget {
  final bool demoMode;

  const TimetableScreen({
    super.key,
    this.demoMode = false,
  });

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  final EdupageTimetableService _timetableService = EdupageTimetableService();
  final TextEditingController _searchController = TextEditingController();

  TimetableFilterType _filterType = TimetableFilterType.student;
  String? _selectedId;
  String? _selectedName;

  bool _isLoading = false;
  String? _errorMessage;

  Map<String, List<ClassSession>>? _timetable;
  List<dynamic> _searchResults = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    if (widget.demoMode) {
      _filterType = TimetableFilterType.demo;
      _loadDemoTimetable();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadDemoTimetable() {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    Future.delayed(const Duration(milliseconds: 300), () {
      setState(() {
        _timetable = _timetableService.getDemoTimetableForStudent('demo');
        _isLoading = false;
        _selectedName = 'Demo Student';
      });
    });
  }

  void _searchItems(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _isLoading = true;
    });

    try {
      if (_filterType == TimetableFilterType.student) {
        final students = await _timetableService.searchStudents(query);
        setState(() {
          _searchResults = students;
          _isLoading = false;
        });
      } else if (_filterType == TimetableFilterType.group) {
        final groups = await _timetableService.searchGroups(query);
        setState(() {
          _searchResults = groups;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error searching: $e';
        _isLoading = false;
      });
    }
  }

  void _selectItem(dynamic item) {
    if (item is Student) {
      _selectedId = item.id;
      _selectedName = item.name;
      _loadStudentTimetable(item.id);
    } else if (item is Group) {
      _selectedId = item.id;
      _selectedName = item.name;
      _loadGroupTimetable(item.id);
    }
    _searchController.text = '';
    setState(() {
      _searchResults = [];
      _isSearching = false;
    });
  }

  void _loadStudentTimetable(String studentId) {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    _timetableService.getTimetableForStudent(studentId).then((timetable) {
      setState(() {
        _timetable = timetable;
        _isLoading = false;
      });
    }).catchError((error) {
      setState(() {
        _errorMessage = 'Failed to load timetable: ${error.toString()}';
        _isLoading = false;
      });
    });
  }

  void _loadGroupTimetable(String groupId) {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    _timetableService.getTimetableForGroup(groupId).then((timetable) {
      setState(() {
        _timetable = timetable;
        _isLoading = false;
      });
    }).catchError((error) {
      setState(() {
        _errorMessage = 'Failed to load timetable: ${error.toString()}';
        _isLoading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Timetable'),
        actions: [
          if (!widget.demoMode)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                if (_selectedId != null) {
                  if (_filterType == TimetableFilterType.student) {
                    _loadStudentTimetable(_selectedId!);
                  } else {
                    _loadGroupTimetable(_selectedId!);
                  }
                }
              },
            ),
        ],
      ),
      body: Column(
        children: [
          if (!widget.demoMode) _buildFilterOptions(),
          if (!widget.demoMode) _buildSearchBar(),
          if (_isSearching) _buildSearchResults(),
          if (_selectedName != null && !_isSearching)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                'Timetable for: $_selectedName',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          if (_isLoading)
            const Expanded(
              child: Center(
                child: CircularProgressIndicator(),
              ),
            )
          else if (_errorMessage != null)
            Expanded(
              child: _buildErrorUI(),
            )
          else if (_timetable != null)
              Expanded(
                child: _buildTimetableUI(_timetable!),
              )
            else
              const Expanded(
                child: Center(
                  child: Text('Select a student or group to view timetable'),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildFilterOptions() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Filter by: '),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('Student'),
            selected: _filterType == TimetableFilterType.student,
            onSelected: (selected) {
              if (selected) {
                setState(() {
                  _filterType = TimetableFilterType.student;
                  _selectedId = null;
                  _selectedName = null;
                  _timetable = null;
                  _searchController.text = '';
                  _searchResults = [];
                });
              }
            },
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('Group'),
            selected: _filterType == TimetableFilterType.group,
            onSelected: (selected) {
              if (selected) {
                setState(() {
                  _filterType = TimetableFilterType.group;
                  _selectedId = null;
                  _selectedName = null;
                  _timetable = null;
                  _searchController.text = '';
                  _searchResults = [];
                });
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: _filterType == TimetableFilterType.student
              ? 'Search for a student...'
              : 'Search for a group...',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
        ),
        onChanged: (value) {
          _searchItems(value);
        },
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_searchResults.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text('No results found'),
      );
    }

    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.5),
            spreadRadius: 1,
            blurRadius: 2,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListView.builder(
        itemCount: _searchResults.length,
        itemBuilder: (context, index) {
          final item = _searchResults[index];
          final name = item is Student ? item.name : (item as Group).name;

          return ListTile(
            title: Text(name),
            onTap: () => _selectItem(item),
          );
        },
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
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              if (_selectedId != null) {
                if (_filterType == TimetableFilterType.student) {
                  _loadStudentTimetable(_selectedId!);
                } else {
                  _loadGroupTimetable(_selectedId!);
                }
              } else if (widget.demoMode) {
                _loadDemoTimetable();
              }
            },
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  Widget _buildTimetableUI(Map<String, List<ClassSession>> timetable) {
    final days = _timetableService.getDays();

    return DefaultTabController(
      length: days.length,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            labelColor: Theme.of(context).primaryColor,
            unselectedLabelColor: Colors.grey,
            tabs: days.map((day) => Tab(text: day)).toList(),
          ),
          Expanded(
            child: TabBarView(
              children: days.map((day) {
                final sessions = timetable[day] ?? [];

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
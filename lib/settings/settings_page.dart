import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../models/task_model.dart';
import '../services/export_service.dart';
import '../scheduling/notification_service.dart';
import '../terms_of_service/terms_page.dart';

class SettingsPage extends StatefulWidget {
  final List<Task> tasks;
  final String userName;
  final Function(String) onNameChanged;
  final VoidCallback onOpenCalendar;
  
  const SettingsPage({
    Key? key, 
    required this.tasks, 
    required this.userName,
    required this.onNameChanged,
    required this.onOpenCalendar
  }) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isDarkMode = false;
  bool _notificationsEnabled = true;
  bool _syncEnabled = true;
  late String _currentUserName;

  @override
  void initState() {
    super.initState();
    _currentUserName = widget.userName;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA), // Light premium background
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Settings',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w700,
            fontSize: 22,
            letterSpacing: 0.3,
          ),
        ),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back, color: Colors.black87),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        children: [
          _buildProfileSection(),
          const SizedBox(height: 32),
          _buildSectionHeader('Preferences'),
          _buildSettingsCard(
            children: [
              _buildSettingsTile(
                icon: CupertinoIcons.moon_stars_fill,
                iconColor: Colors.indigo,
                title: 'Dark Mode',
                trailing: CupertinoSwitch(
                  activeColor: Colors.indigo,
                  value: false, // Force false
                  onChanged: (value) {
                    ScaffoldMessenger.of(context).clearSnackBars();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Dark Mode is coming soon! 🌙'),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: Colors.indigo.shade800,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ),

            ],
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('Data & Sync'),
          _buildSettingsCard(
            children: [
              _buildSettingsTile(
                icon: CupertinoIcons.calendar_today,
                iconColor: Colors.green,
                title: 'Calendar Sync',
                onTap: () {
                  widget.onOpenCalendar();
                },
              ),
              _buildDivider(),
              _buildSettingsTile(
                icon: CupertinoIcons.square_arrow_down,
                iconColor: Colors.deepPurple,
                title: 'Convert to PDF',
                onTap: () {
                  ExportService.exportToPdf(widget.tasks);
                },
              ),
              _buildDivider(),
              _buildSettingsTile(
                icon: CupertinoIcons.doc_text,
                iconColor: Colors.teal,
                title: 'Export to CSV',
                onTap: () {
                  ExportService.exportToCsv(widget.tasks);
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('About'),
          _buildSettingsCard(
            children: [
              _buildSettingsTile(
                icon: CupertinoIcons.info_circle_fill,
                iconColor: Colors.grey,
                title: 'App Version',
                trailing: const Text(
                  '1.0.0', 
                  style: TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _buildDivider(),
              _buildSettingsTile(
                icon: CupertinoIcons.doc_text_fill,
                iconColor: Colors.blueGrey,
                title: 'Terms of Service',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const TermsOfServicePage(),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProfileSection() {
    String initials = _currentUserName.isNotEmpty 
        ? _currentUserName.trim().split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join().toUpperCase()
        : 'U';

    return GestureDetector(
      onTap: _showEditNameDialog,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Colors.indigoAccent, Colors.blueAccent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.indigoAccent.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _currentUserName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Premium Member',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.indigoAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: const Icon(CupertinoIcons.pencil, color: Colors.black87, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditNameDialog() {
    TextEditingController _nameController = TextEditingController(text: _currentUserName);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Edit Name', style: TextStyle(fontWeight: FontWeight.bold)),
          content: TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: 'Enter your name',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.indigoAccent, width: 2),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                final newName = _nameController.text.trim();
                if (newName.isNotEmpty) {
                  setState(() {
                    _currentUserName = newName;
                  });
                  widget.onNameChanged(newName);
                }
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigoAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Save', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 12),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade500,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSettingsCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap ?? () {},
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),
              if (trailing != null)
                trailing
              else
                Icon(CupertinoIcons.chevron_right, color: Colors.grey.shade400, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.only(left: 68, right: 20),
      child: Divider(
        height: 1,
        thickness: 1,
        color: Colors.grey.shade100,
      ),
    );
  }
}
